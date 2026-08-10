<#
.SYNOPSIS
    Remediates Windows Update policy source registry keys.

.DESCRIPTION
    Ensures that policy-driven update sources (Quality, Driver, Feature, 
    etc.) are configured to default (0). This is used in Intune 
    remediations to ensure devices aren't locked into a broken 
    WSUS/SCCM state. 
    Restarts 'wuauserv' and triggers a scan if changes are made.

.NOTES
#>

$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$keys = @(
    "SetPolicyDrivenUpdateSourceForQualityUpdates",
    "SetPolicyDrivenUpdateSourceForDriverUpdates",
    "SetPolicyDrivenUpdateSourceForOtherUpdates",
    "SetPolicyDrivenUpdateSourceForFeatureUpdates"
)

if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }

$remediated = $false
foreach ($k in $keys) {
    $val = Get-ItemProperty -Path $path -Name $k -ErrorAction SilentlyContinue
    if ($null -eq $val -or $val.$k -ne 0) {
        Write-Host "Remediating $k -> 0" -ForegroundColor Yellow
        Set-ItemProperty -Path $path -Name $k -Value 0 -Type DWord
        $remediated = $true
    }
}

if ($remediated) {
    Write-Host "Restarting Windows Update service and triggering scan..." -ForegroundColor Cyan
    Restart-Service wuauserv -Force
    Start-Process "UsoClient.exe" -ArgumentList "StartScan"
} else {
    Write-Host "Compliant."
}
