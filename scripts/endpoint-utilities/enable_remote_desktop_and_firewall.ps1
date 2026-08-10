#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enables Remote Desktop and updates Firewall rules.

.DESCRIPTION
    A simple configuration tool to enable incoming RDP connections:
    1. Sets the 'fDenyTSConnections' registry key to 0.
    2. Enables the 'Remote Desktop' firewall group rules.

.NOTES
#>

Write-Host "Enabling Remote Desktop..." -ForegroundColor Cyan
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Write-Host "RDP enabled and firewall rules updated." -ForegroundColor Green
