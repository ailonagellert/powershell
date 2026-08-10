<#
.SYNOPSIS
    Remediates Windows Update policy sources to enable Microsoft Update.

.DESCRIPTION
    An Intune Remediation script that ensures the 'SetPolicyDrivenUpdateSource' 
    registry keys are set to 0.
    This configuration forces the device to check for Quality, Driver, and 
    Feature updates directly from Microsoft Update/WUfB rather than a 
    local WSUS or SCCM endpoint.
    
    Actions:
    - Creates missing registry paths.
    - Sets values to 0 if they differ or are missing.
    - Restarts the 'wuauserv' service.
    - Triggers an immediate 'UsoClient StartScan'.

.NOTES
#>

$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$registryValues = @(
    "SetPolicyDrivenUpdateSourceForQualityUpdates",
    "SetPolicyDrivenUpdateSourceForDriverUpdates",
    "SetPolicyDrivenUpdateSourceForOtherUpdates",
    "SetPolicyDrivenUpdateSourceForFeatureUpdates"
)

if (-not (Test-Path $registryPath)) { New-Item $registryPath -Force | Out-Null }

$remediated = $false

foreach ($value in $registryValues) {
    $current = Get-ItemProperty -Path $registryPath -Name $value -ErrorAction SilentlyContinue
    if ($null -eq $current -or $current.$value -ne 0) {
        Write-Output "Remediating $value to 0..."
        Set-ItemProperty -Path $registryPath -Name $value -Value 0
        $remediated = $true
    }
}

if ($remediated) {
    Write-Output "Restarting Windows Update service and triggering scan..."
    Restart-Service wuauserv -Force
    Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartScan"
    exit 0 # Remediated
} else {
    Write-Output "Compliance confirmed."
    exit 0 # Compliant
}
