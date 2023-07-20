Import-Module vmware.powercli

get-vm -name Swarm-Manager | Shutdown-VMGuest -Confirm:$false
get-vm -name Swarm-Worker-1 | Shutdown-VMGuest -Confirm:$false
get-vm -name Swarm-Worker-2 | Shutdown-VMGuest -Confirm:$false
Start-Sleep 5
get-vm -name Swarm-Manager | Remove-VM -Confirm:$false -DeletePermanently
get-vm -name Swarm-Worker-1 | Remove-VM -Confirm:$false -DeletePermanently
get-vm -name Swarm-Worker-2 | Remove-VM -Confirm:$false -DeletePermanently
