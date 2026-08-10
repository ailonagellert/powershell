<#
.SYNOPSIS
    Allows a local computer to move itself to a specific AD OU.

.DESCRIPTION
    A self-service staging utility:
    1. Uses the 'ADSystemInfo' COM object to resolve the local computer's 
       Distinguished Name.
    2. Uses [ADSI] (LDAP) to bind to a target OU.
    3. Performs a 'MoveHere' operation to migrate the local computer object.
    
    Useful during Task Sequences to move a machine from 'Staging' to 
    'Production' without needing the RSAT-AD-PowerShell module.

.NOTES
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetOU
)

$sysInfo = New-Object -ComObject ADSystemInfo
$computerDN = $sysInfo.ComputerName
$computerName = $computerDN.Substring(0, $computerDN.IndexOf(","))

if ($TargetOU -match "^LDAP://") { $TargetOU = $TargetOU.Replace("LDAP://","") }

Write-Host "Moving computer to: $TargetOU" -ForegroundColor Cyan
try {
    $newOU = [ADSI]"LDAP://$TargetOU"
    $newOU.MoveHere("LDAP://$computerDN", $computerName)
    Write-Host "Successfully migrated to new OU." -ForegroundColor Green
} catch {
    Write-Error "Failed to move: $($_.Exception.Message)"
}
