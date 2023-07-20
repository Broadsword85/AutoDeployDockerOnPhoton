#Export credentials
$creds = get-credential -Message "Please record ESXi credentials:" 
$creds | Export-Clixml -Path ./esxi.creds