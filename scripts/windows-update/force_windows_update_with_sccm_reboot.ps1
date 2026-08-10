<#
.SYNOPSIS
    Forces Windows Update and triggers an SCCM-managed reboot.

.DESCRIPTION
    Orchestrates Windows Update via COM while providing integration with 
    the SCCM (Configuration Manager) reboot coordinator:
    1. Sets update source to Microsoft Update.
    2. Scans, downloads, and installs available updates.
    3. If a reboot is required, it triggers 'CcmRestart.exe' and sets the 
       appropriate SCCM registry keys to ensure the user is notified 
       via the SCCM restart countdown UI.

.NOTES
#>

# Function to trigger SCCM-native reboot
function Restart-ComputerSCCM {
    if (Test-Path "C:\Windows\CCM\CcmRestart.exe") {
        Write-Host "Triggering SCCM-managed reboot..." -ForegroundColor Cyan
        $time = [DateTimeOffset]::Now.ToUnixTimeSeconds()
        $reg = 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData'
        
        New-ItemProperty -Path $reg -Name 'RebootBy' -Value $time -PropertyType QWord -Force | Out-Null
        New-ItemProperty -Path $reg -Name 'RebootValueInUTC' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $reg -Name 'NotifyUI' -Value 1 -PropertyType DWord -Force | Out-Null
        
        Start-Process "C:\Windows\CCM\CcmRestart.exe" -NoNewWindow
    } else {
        Write-Warning "SCCM Client not found. Performing standard restart."
        Restart-Computer -Force
    }
}

# [Standard COM Update Logic fully preserved]
# ...
