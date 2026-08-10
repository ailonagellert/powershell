<#
.SYNOPSIS
    Automates Lenovo System Update (TVSU) via CLI.

.DESCRIPTION
    Automates the 'ThinkVantage System Update' (TVSU) tool:
    1. Configures 'AdminCommandLine' to search for and install all updates 
       silently without licenses or icons.
    2. Exports update history to the 'root\lenovo' WMI namespace.
    3. Handles 'includerebootpackages' and 'noreboot' flags.
    4. Waits for 'tvsu.exe' and 'tvsukernel.exe' processes to fully terminate.

.NOTES
#>

$tvsuPath = "C:\Program Files (x86)\Lenovo\System Update\tvsu.exe"
if (-not (Test-Path $tvsuPath)) { Write-Error "Lenovo System Update not found."; exit }

$reg = "HKLM:\SOFTWARE\WOW6432Node\Policies\Lenovo\System Update\UserSettings\General"
if (-not (Test-Path $reg)) { New-Item $reg -Force | Out-Null }

# 1. Configure Search/Export to WMI
$cmdSearch = "/CM -search A -action INSTALL -packagetypes 0 -noicon -nolicense -scheduler -exporttowmi"
Set-ItemProperty $reg -Name "AdminCommandLine" -Value $cmdSearch

Write-Host "Starting Lenovo Update Search & WMI Export..." -ForegroundColor Cyan
Start-Process $tvsuPath -ArgumentList "/CM" -Wait

# 2. Wait for background kernel to finish
while (Get-Process "tvsukernel" -ErrorAction SilentlyContinue) {
    Write-Host "Waiting for TVSU Kernel..."
    Start-Sleep -Seconds 15
}

# 3. Process Installations
$cmdInstall = "/CM -search A -action INSTALL -includerebootpackages 1,3,4,5 -noicon -noreboot -nolicense -scheduler -exporttowmi"
Set-ItemProperty $reg -Name "AdminCommandLine" -Value $cmdInstall
Write-Host "Executing Installations..." -ForegroundColor Green
Start-Process $tvsuPath -ArgumentList "/CM" -Wait
