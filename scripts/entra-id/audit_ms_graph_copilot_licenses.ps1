<#
.SYNOPSIS
    Audits Microsoft Graph users for Copilot commercial data protection licenses.

.DESCRIPTION
    This script uses the Microsoft Graph PowerShell SDK to:
    1. Verify the 'Microsoft.Graph.Users' module is installed.
    2. Connect to Microsoft Graph with 'User.Read.All' scope.
    3. Retrieve all users along with their assigned plans.
    4. List users who have 'Copilot with commercial data protection' (Service: Bing) enabled.
    5. List users who do NOT have it enabled.

.NOTES
#>

# Install Microsoft Graph module if missing
if (-not (Get-Module -ListAvailable Microsoft.Graph.Users)) {
    Write-Host "Installing Microsoft.Graph.Users module..."
    Install-Module Microsoft.Graph.Users -Scope CurrentUser -Force
}

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -Scopes 'User.Read.All'

# Get all users with assigned plans
Write-Host "Retrieving user data..."
$users = Get-MgUser -All -ConsistencyLevel eventual -Property Id, DisplayName, Mail, UserPrincipalName, AssignedPlans

# Users with Copilot with commercial data protection enabled
Write-Host "`n--- Users WITH Copilot Data Protection Enabled ---" -ForegroundColor Green
$users | Where-Object { 
    $_.AssignedPlans -and 
    ($_.AssignedPlans | Where-Object { $_.Service -eq "Bing" -and $_.CapabilityStatus -eq "Enabled" })
} | Select-Object DisplayName, Mail, UserPrincipalName | Format-Table -AutoSize

# Users without Copilot with commercial data protection enabled
Write-Host "`n--- Users WITHOUT Copilot Data Protection Enabled ---" -ForegroundColor Yellow
$users | Where-Object { 
    -not $_.AssignedPlans -or 
    -not ($_.AssignedPlans | Where-Object { $_.Service -eq "Bing" -and $_.CapabilityStatus -eq "Enabled" })
} | Select-Object DisplayName, Mail, UserPrincipalName | Format-Table -AutoSize
