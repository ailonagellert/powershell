<#
.SYNOPSIS
    Checks the Entra ID (Azure AD) Hybrid Join status.

.DESCRIPTION
    Runs 'dsregcmd /status' and parses the output to determine:
    1. If the device is AzureAdJoined.
    2. If the device is DomainJoined.
    3. The DeviceAuthStatus (SUCCESS/ERROR).
    
    If DeviceAuthStatus is not SUCCESS, it provides a placeholder for 
    rejoining the domain (dsregcmd /leave and /join).

.NOTES
#>

$dsreg = dsregcmd /status
$azureJoined = ($dsreg | Select-String "AzureAdJoined :").ToString().Split(":")[1].Trim()
$domainJoined = ($dsreg | Select-String "DomainJoined :").ToString().Split(":")[1].Trim()
$authStatus = ($dsreg | Select-String "DeviceAuthStatus :").ToString().Split(":")[1].Trim()

Write-Host "--- Entra ID Join Status ---" -ForegroundColor Cyan
Write-Host "Azure AD Joined: $azureJoined"
Write-Host "Domain Joined:   $domainJoined"
Write-Host "Auth Status:     $authStatus"

if ($azureJoined -eq "YES" -and $domainJoined -eq "YES") {
    if ($authStatus -eq "SUCCESS") {
        Write-Host "Device is healthy." -ForegroundColor Green
    } else {
        Write-Host "ERROR: Hybrid join is broken ($authStatus)." -ForegroundColor Red
        # dsregcmd /leave
        # dsregcmd /join
    }
} else {
    Write-Host "Device is not Hybrid Joined." -ForegroundColor Yellow
}
