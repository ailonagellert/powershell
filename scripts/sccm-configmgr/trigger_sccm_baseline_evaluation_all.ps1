<#
.SYNOPSIS
    Triggers evaluation of all SCCM compliance baselines.

.DESCRIPTION
    A local client remediation tool that enumerates all deployed 
    Configuration Baselines and triggers an immediate evaluation cycle 
    via WMI (root\ccm\dcm:SMS_DesiredConfiguration).

.NOTES
#>

Write-Host "Triggering evaluation of all SCCM Baselines..." -ForegroundColor Cyan
$baselines = Get-CimInstance -Namespace root\ccm\dcm -ClassName SMS_DesiredConfiguration

foreach ($b in $baselines) {
    Write-Host " - Evaluating: $($b.Name)"
    Invoke-CimMethod -Namespace root\ccm\dcm -ClassName SMS_DesiredConfiguration -MethodName TriggerEvaluation -Arguments @{
        BaselineId = $b.Name;
        BaselineVersion = $b.Version;
        IsPreflight = $false;
        IsRecursive = $true
    } | Out-Null
}
