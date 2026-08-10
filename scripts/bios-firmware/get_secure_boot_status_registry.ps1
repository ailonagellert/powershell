<#
.SYNOPSIS
    Checks Secure Boot status via the Windows Registry.

.DESCRIPTION
    This script queries the 'UEFISecureBootEnabled' value from the registry key:
    HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State
    
    It returns 'enabled' if the value is 1, and 'disabled' otherwise.

.NOTES
#>

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State"
$regValue = "UEFISecureBootEnabled"

if (Test-Path $regPath) {
    $status = Get-ItemProperty -Path $regPath -Name $regValue -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $regValue
    
    if ($status -eq 1) {
        Write-Host "enabled"
        exit 0
    } else {
        Write-Host "disabled"
        exit 1
    }
} else {
    Write-Host "Registry key not found. Secure Boot may not be supported."
    exit 2
}
