<#
.SYNOPSIS
    Forcefully purges stale user profiles and registry keys.

.DESCRIPTION
    A cleanup utility to free disk space by removing inactive profiles:
    - Finds profiles unused for 30+ days.
    - Excludes 'Special' profiles (System, NetworkService, etc.).
    - Deletes the local profile directory recursively.
    - Purges the corresponding SID entry from the 'ProfileList' 
      registry key to prevent 'Temporary Profile' login errors.

.NOTES
#>

$cutoff = (Get-Date).AddDays(-30)

$profiles = Get-CimInstance -Class Win32_UserProfile | Where-Object {
    $_.LastUseTime -lt $cutoff -and $_.Special -eq $false
}

foreach ($p in $profiles) {
    Write-Host "Purging Profile: $($p.LocalPath)" -ForegroundColor Yellow
    try {
        # 1. FS Cleanup
        if (Test-Path $p.LocalPath) { Remove-Item $p.LocalPath -Recurse -Force }
        
        # 2. Registry Cleanup
        $reg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($p.SID)"
        if (Test-Path $reg) { Remove-Item $reg -Recurse -Force }
    } catch {
        Write-Warning "Failed to fully delete $($p.LocalPath)"
    }
}
