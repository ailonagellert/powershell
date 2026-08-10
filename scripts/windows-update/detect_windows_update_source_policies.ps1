<#
.SYNOPSIS
    Detects non-compliant Windows Update policy source registry keys.

.DESCRIPTION
    Counterpart to the remediation script. It audits the 
    'SetPolicyDrivenUpdateSource...' keys to ensure they exist and are 
    set to 0. Used as a Detection Script in Intune/SCCM Configuration 
    Items.

.NOTES
#>

$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$keys = @(
    "SetPolicyDrivenUpdateSourceForQualityUpdates",
    "SetPolicyDrivenUpdateSourceForDriverUpdates",
    "SetPolicyDrivenUpdateSourceForOtherUpdates",
    "SetPolicyDrivenUpdateSourceForFeatureUpdates"
)

if (-not (Test-Path $path)) { Write-Host "Not Compliant (Path Missing)"; exit 1 }

$compliant = $true
foreach ($k in $keys) {
    try {
        $val = Get-ItemProperty -Path $path -Name $k -ErrorAction Stop
        if ($val.$k -ne 0) { $compliant = $false }
    } catch {
        $compliant = $false
    }
}

if ($compliant) {
    Write-Host "Compliant"
    exit 0
} else {
    Write-Host "Not Compliant"
    exit 1
}
