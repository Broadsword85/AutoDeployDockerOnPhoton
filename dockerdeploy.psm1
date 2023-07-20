function checkreadyandrun {
    param(
		[Parameter(mandatory=$true)]
		[string] $VM,
        [Parameter(mandatory=$true)]
        [string] $cmd,
        [Parameter(mandatory=$true)]
        [string] $GuestPW,
        [Parameter(mandatory=$true)]
        [string] $Server
	)

    Write-Host "Waiting for VMWare tools to be active"
    do {
        $toolsStatus = (get-vm -server $Server $VM).extensiondata.Guest.ToolsStatus
        write-host $toolsStatus
        start-sleep 3
    } until ( ($toolsStatus -eq 'toolsOk') -or ($toolsStatus -eq 'toolsOld')   )

    $output = Invoke-VMScript -server $Server -ScriptType bash -VM $VM -ScriptText $cmd -GuestUser root -GuestPassword $GuestPW
    return $output
}

function deploy-vm {
	param(
		[Parameter(mandatory=$true)]
		[string] $Name,
        [Parameter(mandatory=$true)]
        [string] $OVF,
        [Parameter(mandatory=$true)]
        [string] $Datastore,
        [Parameter(mandatory=$true)]
        [string] $IP,
        [Parameter(mandatory=$true)]
        [string] $Gateway,
        [Parameter()]
        [string] $Slash="24",
        [Parameter()]
        [string[]] $DNS = @("8.8.8.8","8.8.4.4"),
        [Parameter(mandatory=$true)]
        [string] $GuestPW,
        [Parameter(mandatory=$true)]
        [string] $ESXHost
	)
    #Deploy VM
    #Configure network
    #Reboot


    $sVApp = @{
        Name              = $Name
        Source            = $OVF
        VMHost            = Get-VMHost -Server $ESXHost
        Datastore         = Get-Datastore -Name $Datastore -Server $ESXHost
        DiskStorageFormat = [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.VirtualDiskStorageFormat]::Thin
        Confirm           = $false
        Server            = $ESXHost
    }

    Write-Host "Deploying $Name"
    $vm = Import-VApp @sVApp

    Start-VM -Server $ESXHost -VM $vm
    
    $VMNetwork="[Match]
    Name=e*
    
    [Network]
    Address=$IP/$Slash
    Gateway=$Gateway`n"
    foreach($dnshost in $DNS){
        $VMNetwork+="DNS=$dnshost`n"
    }    

    $configNetwork = @(
        "echo ""$VMNetwork"" > /etc/systemd/network/20-wired.network.temp", #Write the network config temp file
        "echo ""$name"" > /etc/hostname", #Overwrite the host name file
        "sed `'s/; /\n/g`' /etc/systemd/network/20-wired.network.temp > /etc/systemd/network/20-wired.network", #Replace the ; character with line breaks
        "rm -rf /etc/systemd/network/20-wired.network.temp", #Remove the temp file
        #"systemctl restart systemd-networkd.service",
        "iptables -A INPUT -p tcp --dport 2377 -j ACCEPT", #The IPTables bit is actually only needed for the Masters,
        "iptables -A INPUT -p ICMP -j ACCEPT",#but its easiest to set for all & not worry later if roles change
        "iptables -A OUTPUT -p ICMP -j ACCEPT",
        "iptables-save > /etc/systemd/scripts/ip4save", #Saving so it'll be permanent
        "systemctl enable docker", #Start Docker service & make it active on reboots
        "systemctl start docker",
        "tdnf install git -y", #Install Git - probably not needed by worker nodes but handy!
        "mkdir /git", #Create a folder to hold our content
        "(sleep 5 && shutdown -r now) &" #A simple reboot command causes the system to go offline before returning success/fail
    ) 

    Write-Host "Configuring network & rebooting"
    checkreadyandrun -Server $ESXHost -VM $vm -GuestPW $GuestPW -cmd ($configNetwork -join ";")

#    Write-Host "Waiting 5 seconds for the network"
#    start-sleep 5

#    Write-Host "Rebooting"
#    checkreadyandrun -VM $vm -GuestPW $GuestPW -cmd 
    return $vm
}