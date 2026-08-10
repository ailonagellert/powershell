<#
.SYNOPSIS
    Prepares a Windows VHD for deployment to Azure.

.DESCRIPTION
    Performs critical configuration steps to ensure a Windows image is 
    ready for Azure environment compatibility:
    1. Resets WinHTTP proxy and sets Azure-specific bypasses.
    2. Sets SAN policy to OnlineAll (for managed disks).
    3. Configures UTC time (RealTimeIsUniversal).
    4. Optimizes power profiles for high performance.
    5. Resets environment variables (TEMP/TMP).
    6. Enables and optimizes RDP (Terminal Services) registry settings 
       for remote accessibility and persistence.
    7. Configures firewall rules for Remote Desktop.

.NOTES
#>

# 1. Network & Proxy
Write-Host "Resetting WinHTTP proxy..."
netsh.exe winhttp reset proxy

# 2. Disk & Time
Write-Host "Configuring Disk SAN Policy and UTC Time..."
"san policy=onlineall" | diskpart.exe
Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation -Name RealTimeIsUniversal -Value 1 -Type DWord -Force
Set-Service -Name w32time -StartupType Automatic

# 3. Power & Environment
Write-Host "Optimizing Power Profile..."
powercfg.exe /setactive SCHEME_MIN
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name TEMP -Value "%SystemRoot%\TEMP" -Type ExpandString -Force

# 4. RDP Configuration (Condensed)
Write-Host "Enabling and Optimizing Remote Desktop..."
$rdpPaths = @(
    'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services',
    'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp'
)
foreach ($path in $rdpPaths) { if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null } }

Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0 -Force
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Winstations\RDP-Tcp' -Name UserAuthentication -Value 1 -Force

# 5. Firewall
Write-Host "Enabling Firewall rules for RDP..."
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Set-NetFirewallRule -Enabled True
