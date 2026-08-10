#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Resets Windows Update components and the Component Store.

.DESCRIPTION
    A comprehensive "nuclear option" for fixing Windows Update and corruption issues.
    Actions:
    1. Sets TrustedInstaller to Auto.
    2. Stops BITS, wuauserv, msiserver, cryptsvc, and appidsvc.
    3. Renames SoftwareDistribution and catroot2 folders.
    4. Reregisters core Windows Update DLLs.
    5. Resets Winsock and proxy settings.
    6. Performs deep PnP cleaning of unused drivers.
    7. Runs full DISM health checks and RestoreHealth.
    8. Performs Component Store cleanup.
    9. Runs SFC ScanNow.
    10. Restarts all stopped services.

.NOTES
#>

Write-Host "Initiating Windows Update and Component Store reset..." -ForegroundColor Yellow

# 1. Services
SC.exe config trustedinstaller start=auto
$services = @('bits', 'wuauserv', 'msiserver', 'cryptsvc', 'appidsvc')
foreach ($svc in $services) { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }

# 2. Rename Folders
Write-Host "Renaming cache folders..."
if (Test-Path C:\Windows\SoftwareDistribution) { 
    Ren C:\windows\SoftwareDistribution SoftwareDistribution.old -ErrorAction SilentlyContinue 
}
if (Test-Path C:\Windows\System32\catroot2) { 
    Ren C:\windows\System32\catroot2 catroot2.old -ErrorAction SilentlyContinue 
}

# 3. DLL Reregistration
$dlls = @('atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 'browseui.dll', 'jscript.dll', 'vbscript.dll', 'scrrun.dll', 'msxml.dll', 'msxml3.dll', 'msxml6.dll', 'itss.dll', 'softpub.dll', 'wintrust.dll', 'objsel.dll', 'xmllite.dll', 'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'asferror.dll', 'wups.dll', 'wups2.dll', 'wuaueng.dll', 'wuapi.dll', 'wucltux.dll', 'wuwebv.dll', 'muweb.dll', 'wucltui.dll')
foreach ($dll in $dlls) { regsvr32.exe /s $dll }

# 4. Network Reset
netsh winsock reset
netsh winsock reset proxy

# 5. PnP Cleanup
rundll32.exe pnpclean.dll,RunDLL_PnpClean /DRIVERS /MAXCLEAN

# 6. DISM & SFC
Write-Host "Running DISM RestoreHealth and Component Cleanup..."
dism /Online /Cleanup-image /RestoreHealth
dism /Online /Cleanup-image /StartComponentCleanup
Write-Host "Running System File Checker..."
Sfc /ScanNow

# 7. Restart Services
foreach ($svc in $services) { Start-Service -Name $svc -ErrorAction SilentlyContinue }

Write-Host "Reset complete. A system restart is highly recommended." -ForegroundColor Green
