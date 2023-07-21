# AutoDeployDockerOnPhoton
Proof of concept to deploy a Docker Swarm on VMWare from a VMWare Photon template (OVF), one or more VCenters or standalone ESXi hosts, and a config file

# Notes
This script was designed against two ESXi 6.7 hosts using the free license. I may try to test this against a newer environment or a VCenter if I get a chance.

The purpose of this script was a proof of concept - additional security concerns & basic configuration options should be addressed before attempting to use this for production.

An odd number of Manager nodes is recommended for redundancy. I may add a shared cluster IP with Keepalived in the future.

# Usage
1. The Photon template needs to be imported into ESX, the password set, and exported again. There is a way to possibly avoid this by setting the password using https://github.com/lamw/vmware-scripts/blob/master/powershell/VMKeystrokes.ps1 - it's possible I'll add that in the future. Other Linux builds would require a change from the Photon TDNF package manager & possibly other changes.

1. Create the guest password file by putting a plaintext password in a text file - just the password. Remember - this is a proof of concept in need of more security.

1. Create the Powershell credential file (or not - it'll prompt). Run CredExport.ps1 to write esxi.creds. Multiple credentials could be used for multiple ESX hosts - they would need their own files if the credentials don't match.

1. Edit the demo JSON file to meet your needs. The sections worth mentioning:
  * VMs
    * A list of virtual servers to create with the basic info
  * Template
    * The modified Photon template location
  * Network
    * This assumes all nodes are on the same network
  * ESX
    * The one or multiple VMWare targets for deployment

You may launch the script with no parameters to use the Demo.json file, or you can use: 
```
Deploy-DockerSwarm.ps1 -JSON YourCustomFile.json
```