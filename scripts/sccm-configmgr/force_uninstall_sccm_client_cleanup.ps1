<#
.SYNOPSIS
    Forcefully uninstalls and purges the SCCM (ConfigMgr) client.

.DESCRIPTION
    A cleanup script to completely remove an SCCM client and its 
    identity markers:
    1. Stops 'ccmexec'.
    2. Runs 'ccmsetup.exe /uninstall'.
    3. Purges 'smscfg.ini' (SMSID).
    4. Removes all certificates from 'Cert:\LocalMachine\sms'.
    5. Adds the SCCM server to Local Administrators (optional).

.NOTES
#>

# 1. Stop & Uninstall
Stop-Service -Name ccmexec -Force -ErrorAction SilentlyContinue
if (Test-Path "$env:windir\ccmsetup\ccmsetup.exe") {
    Start-Process "$env:windir\ccmsetup\ccmsetup.exe" -ArgumentList "/uninstall" -Wait
}

# 2. Purge Identity & Certs
if (Test-Path "$env:windir\smscfg.ini") {
    Remove-Item "$env:windir\smscfg.ini" -Force
}
Get-ChildItem "Cert:\LocalMachine\sms" | Remove-Item -Force

Write-Host "SCCM client purged. Ready for clean reinstall." -ForegroundColor Green
