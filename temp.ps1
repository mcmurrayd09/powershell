###################################################
# Windows Server Patcher for Patch Tuesday(month) #
###################################################

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -force
Import-Module PSWindowsUpdate

$searchbase = "" #base OU of all servers in AD
$year = "2021" #current year

#organize servers into each level based on backup data level can be organized in any particular way, just will need to edit the filters and search bases in lines 14-17

$domaincontrollers=get-adcomputer -filter * -SearchBase "OU=Domain Controllers,dc=,dc=" | select -ExpandProperty DNSHostname #edit searchbase
$level1staff=get-adcomputer -filter * -SearchBase $searchbase | where {(($_.DistinguishedName -like "*Windows*") -and ($_.DistinguishedName -like "*Level-1*") )} | select -ExpandProperty DNSHostname 
$level2staff=get-adcomputer -filter * -SearchBase $searchbase | where {(($_.DistinguishedName -like "*Windows*") -and ($_.DistinguishedName -like "*Level-2*") )} | select -ExpandProperty DNSHostname 
$level3staff=get-adcomputer -filter * -SearchBase $searchbase | where {(($_.DistinguishedName -like "*Windows*") -and ($_.DistinguishedName -like "*Level-3*") )} | select -ExpandProperty DNSHostname 
$custom=get-adcomputer -filter * -SearchBase $searchbase | where {(($_.DistinguishedName -like "*Custom*"))} | select -ExpandProperty DNSHostname 

#prompt user for selection, edit these to match whatever amount of OUs there are in environment

$op1 = New-Object System.Management.Automation.Host.ChoiceDescription '&Level 1', 'Level 1 Servers'
$op2 = New-Object System.Management.Automation.Host.ChoiceDescription '&Level 2', 'Level 2 Servers'
$op3 = New-Object System.Management.Automation.Host.ChoiceDescription '&Level 3', 'Level 3 Servers'
$op4 = New-Object System.Management.Automation.Host.ChoiceDescription '&Domain Controllers', 'Domain Controllers'
$op5 = New-Object System.Management.Automation.Host.ChoiceDescription '&Custom', 'Custom'

#create array of options

$options = [System.Management.Automation.Host.ChoiceDescription[]]($op1,$op2,$op3,$op4,$op5)

$title = "Server Level Selection"
$message = "What level servers do you want to update?"
$choice = $host.ui.PromptForChoice($title, $message, $options, 0)

#dump out list of servers and verify from user to update selected servers based on level

if ($choice -eq 0){
   echo "`nThe following servers will be updated.`n"
   $servers=$level1staff
   $servers
   $confirmation = Read-Host -prompt "`nTo update these server, please confirm [y/n]"
   }
elseif ($choice -eq 1){
   echo "`nThe following servers will be updated.`n"
   $servers=$level2staff
   $servers
   $confirmation = Read-Host -prompt "`nTo update these server, please confirm [y/n]"
   }
elseif ($choice -eq 2){
   echo "`nThe following servers will be updated.`n"
   $servers=$level3staff
   $servers
   $confirmation = Read-Host -prompt "`nTo update these server, please confirm [y/n]"
   }
elseif ($choice -eq 3){
   echo "`nThe following servers will be updated.`n"
   $servers=$domaincontrollers
   $servers
   $confirmation = Read-Host -prompt "`nTo update these servers, please confirm [y/n]"
   }
elseif ($choice -eq 4){
   echo "`nThe following servers will be updated.`n"
   $servers=$custom
   $servers
   $confirmation = Read-Host -prompt "`nTo update these servers, please confirm [y/n]"
   }

##################################################
#        proceed depending on confirmation        #
##################################################
if ($confirmation -eq "y"){
    echo "Confirmation recieved by user. Preparing to patch..."
} elseif ($confirmation -eq "n") {
    echo "Confirmation rejected by user input. Quitting..."
    return
} else {
    echo "`ninput incorrect. start over fatfingerer.`n"
    return
}

#define invoked commands

$listupdatescommand = { ipmo PSWindowsUpdate; Get-WUInstall -WindowsUpdate -listonly -ignorereboot | Out-File -filepath "C:\PSWindowsList.log" }
$updatecommand = { ipmo PSWindowsUpdate; Get-WUInstall -WindowsUpdate -acceptall -ignorereboot | Out-File -filepath "C:\PSWindowsUpdate.log" }


##################################################
# iterate to list updates for selected computers #
##################################################

foreach($server in $servers) {
echo "generating list of updates for $server"
Invoke-WUInstall -ComputerName $server -Script $listupdatescommand -confirm:$false -verbose
}

echo "waiting 20 seconds..."
sleep 20

foreach($server in $servers) {
    echo "fetching generated list of updates for $server`n"
    $fetch=Invoke-Command -ComputerName $server -ScriptBlock { Get-Item C:\PSWindowsList.log | Select-String -Pattern "2021" -SimpleMatch | Select-Object -Property line } | Select-Object -Property Line,PSComputerName
    if ( $fetch -eq $null )
    {
    echo 'List does not exist or is null. Fetching the last ten installed updates of 2021.'
    }
    if ( $fetch -ne $null )
    {
    echo 'The array is not null. Dumping list of updates needed.'
    $fetch
    }
echo "`n"
}

echo ""
$confirmation = Read-Host "Scroll up and verify these are the updates you wish to install on all servers: Proceed [y], Quit [n]"
if ($confirmation -eq 'n') {
    return
}

echo "confirmed. proceeding with updates to servers...`n"
#wait a little bit
foreach($server in $servers) {
echo "Invoking updates for remote server: $server"
Invoke-WUInstall -ComputerName $server -Script $updatecommand -confirm:$false -Verbose
echo "Done. Moving to next server`n"
}


#to check on updates select the below comment block and run selection

#define update check variable
$updatecheckcommand=Invoke-Command -ComputerName $server -ScriptBlock {get-process | Select-String -Pattern "TiWorker" -SimpleMatch | Select-Object -Property line } | Select-Object -Property Line,PSComputerName


### HIGHLIGHT AND RUN ME TO CHECK STATUS ###
### IF THE AMOUNT OF DOWNLOADED UPDATES MATCHES THE NUMBER OF INSTALLED UPDATES, SAFE TO REBOOT ###

foreach($server in $servers) {
    echo "Checking for failures in logs for $server"
    Invoke-Command -ComputerName $server -ScriptBlock { Get-Item C:\PSWindowsUpdate.log | Select-String -Pattern "Failed" -SimpleMatch | Select-Object -Property line } | Select-Object -Property Line,PSComputerName
    echo "checking for windows update process.`n"
    $updatecheckcommand
    echo "Printing status log... if empty, updates not running."
    Invoke-Command -ComputerName $server -ScriptBlock { Get-Item C:\PSWindowsUpdate.log | Select-String -Pattern "C" -SimpleMatch | Select-Object -Property line } | Select-Object -Property Line,PSComputerName | Format-table -wrap -AutoSize
    echo "`n"
    
}

echo "exiting. please use the last two loops in this script to verify updates and check for reboot"
exit

### RUN THIS TO REBOOT COMPLETED SERVERS ###
echo "Checking reboot status"
echo "WARNING: Only reboot servers that have accepted, downloaded, and installed ALL required updates. Verified by the status from logs."
foreach($server in $servers) {
Get-WURebootStatus -ComputerName $server
}