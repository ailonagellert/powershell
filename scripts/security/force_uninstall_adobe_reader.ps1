#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Forcefully uninstalls Adobe Acrobat Reader (Standard/Pro excluded).

.DESCRIPTION
    A targeted cleanup script for Adobe Reader:
    1. Scans both 32-bit and 64-bit registry uninstall paths.
    2. Identifies 'Adobe Acrobat Reader' entries while explicitly 
       skipping 'Standard' or 'Professional' editions.
    3. Triggers a silent MSI uninstall using the discovered ProductCode.
    4. Logs all actions to 'C:\Windows\CCM\Logs' for enterprise auditing.

.NOTES
#>

$log = "C:\Windows\CCM\Logs\Uninstall_AdobeReader.log"
function Write-Log($m) { "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] $m" | Add-Content $log }

$paths = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
           'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')

Write-Log "Starting Adobe Reader cleanup scan..."
$apps = Get-ItemProperty $paths | Where-Object { 
    $_.DisplayName -like "*Adobe Acrobat Reader*" -and 
    $_.DisplayName -notlike "*Standard*" -and 
    $_.DisplayName -notlike "*Professional*" 
}

foreach ($a in $apps) {
    Write-Log "Found: $($a.DisplayName) (Code: $($a.PSChildName))"
    Write-Host "Uninstalling $($a.DisplayName)..." -ForegroundColor Yellow
    $p = Start-Process "msiexec.exe" -ArgumentList "/x $($a.PSChildName) /qn /norestart" -Wait -PassThru
    Write-Log "Finished with exit code: $($p.ExitCode)"
}
