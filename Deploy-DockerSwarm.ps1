<#
    .SYNOPSIS
        Deploy a Docker Swarm to ESXi host(s)
    .DESCRIPTION
        Create a new Docker Swarm based on the input JSON file
    .PARAMETER JSON
        A JSON input file with definitions of the infrastructure and VMs to be created
    .INPUTS
        None - pipe input is not accepted
    .OUTPUTS
        System.String of creation log
    .LINK
        https://github.com/Broadsword85/AutoDeployDockerOnPhoton
#>

#Config file location:
param(
    [Parameter()]
        [string] $JSON = ".\demo.json"
)

#Includes
Import-Module vmware.powercli
Import-Module ./dockerdeploy.psm1 -force

#Set the multi-VCenter mode (can skip if using only one VCenter/ESX host)
if((Get-PowerCLIConfiguration -Scope Session).DefaultVIServerMode -ne "Multiple"){
    Set-PowerCLIConfiguration -Scope Session -DefaultVIServerMode Multiple -Confirm:$false
}

#Load config data from JSON
try {
    $data = Get-Content $JSON | ConvertFrom-Json -AsHashtable
    $GuestPW = Get-Content -Path $data.Template.GuestPWFile
}
catch {
    Write-Error "Failed to load JSON file - please correct & try again" -ErrorAction Stop
}


#Verify or connect to ESXi
foreach($esx in $data.ESX){
    if(($esx.Addr) -notin $global:defaultviservers.Name){
        if(test-path $esx.CredFile){
            $creds = Import-Clixml $esx.CredFile
            Write-Host "Creds found in file for $($esx.Addr)"
        } else {
            $creds = get-credential -Message "$($esx.Addr) credentials:" 
        }
        connect-viserver $esx.Addr -Credential $creds
    }
}

#Create the VM's
foreach($machine in $data.VMs){
    $thisHost = $null
    ForEach($esx in $data.ESX){if($esx.Name -eq $machine.Host){$thisHost = $esx.Addr}}
    $params = @{
        Name = $machine.Name
        OVF = $data.Template.OVF
        Datastore = $machine.Datastore
        ip = $machine.IP
        gateway = $data.Network.Gateway
        Slash = $data.Network.Slash
        DNS = $data.Network.DNS
        ESXHost = $thisHost
        GuestPW = $GuestPW
    }
    $vm = deploy-vm @params
    Write-Host ""
}

Write-Host "VM's created - proceeding to configuration"
Write-Host ""

#Configure the first Manager
if("Manager" -notin $data.VMs.Role){
    Write-Host "Cannot create Docker Swarm without at least one Manager"
} else {
    $firstManager = $null
    $AddionalMasters = @()
    foreach($vm in $data.VMs){
        #The first Manager needs to initialize the swarm
        if($vm.Role -eq "Manager" -and $null -eq $firstManager){
            $master = $vm
            $MasterHost = $null
            ForEach($esx in $data.ESX){if($esx.Name -eq $vm.Host){$MasterHost = $esx.Addr}}
            Write-Host "Install swarm Manager"
            $swarmcmd = @(
                "docker swarm init --advertise-addr=$($vm.ip)",
                "curl -L https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-linux-x86_64 > /usr/local/bin/docker-compose",
                "chmod +x /usr/local/bin/docker-compose"
                #"(tdnf upgrade -y) &" #We'll patch after finishing the config later
            )
            $output = checkreadyandrun -VM $vm.Name -GuestPW $GuestPW -cmd ($swarmcmd -join ";") -Server $MasterHost
            Write-Host ""

            #Parse the join command out of the output
            $start = $output.ScriptOutput.indexof("docker swarm join")
            $joincmd = $output.ScriptOutput.Substring($start,150)
            $len = $joincmd.indexof("`n")
            $joincmd = $joincmd.Substring(0,$len)
            Write-Host $joincmd
            Write-Host ""
            $firstManager = $vm.Name
        } elseif ($vm.Role -eq "Manager" -and $null -ne $firstManager) {
            $AddionalMasters+= $vm.Name
        }
    }
}

#Create all remaining nodes as Workers - additional Masters will be promoted later
foreach($vm in $data.VMs){
    if($vm.name -eq $firstManager){continue} #Skip creating the first Manager node
    Write-Host "Configuring $($vm.Name)"
    $thisHost = $null
    ForEach($esx in $data.ESX){if($esx.Name -eq $vm.Host){$thisHost = $esx.Addr}}
    $configWorker = @(
        $joincmd,
        "curl -L https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-linux-x86_64 > /usr/local/bin/docker-compose",
        "chmod +x /usr/local/bin/docker-compose",
        "(tdnf upgrade -y) &"
    )
    $output = checkreadyandrun -VM $vm.Name -GuestPW $GuestPW -cmd ($configWorker -join ";") -Server $thisHost
    Write-Host ""
}

Write-Host "Configuring additional Managers & pulling GIT repo"

$gitcmd = @(
    "cd /git",
    "git clone https://github.com/Broadsword85/DockerHAProxyApache.git",
    "cd DockerHAProxyApache/",
    "git pull",
    "docker-compose build",
    "docker stack deploy --compose-file docker-compose.yml DockerHAProxyApache"
)

foreach($m in $AddionalMasters){
    $gitcmd += "docker node promote $m"
}
$gitcmd += "(tdnf upgrade -y) &"

checkreadyandrun -VM $master.Name -GuestPW $GuestPW -cmd ($gitcmd -join ";") -Server $MasterHost

Write-Host ""
Write-Host "Complete!"