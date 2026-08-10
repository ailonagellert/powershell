<#
.SYNOPSIS
    Adds multiple computer accounts to a specific AD group.

.DESCRIPTION
    Uses the Active Directory module to add a batch of computer names
    to the 'gpap-ad-gpo-autpatch' group. 
    This is typically used for GPO targeting or update ring management.

.NOTES
#>

$groupName = "gpap-ad-gpo-autpatch"
$computers = @(
    "1H844322V6", "5CD4424HRS", "1H8427135V", "1H84301WMN", "1H84301WNB", "1H84301WNN", "1H84301WNQ",
    "1H84301WNZ", "1H84301WNH", "1H84301WNT", "5CD4032VKC", "5CD4032VKN", "5CD4032VLN", "5CD4032VKH",
    "5CD4032VLS", "5CD4032VKD", "5CD4032VLD", "5CD4032VKY", "5CD4032VLM", "5CD4032VKT", "5CD3185HX4",
    "5CD2422J3G", "5CD3077NJL", "5CD3077NKB", "5CD3077NKC", "5CD3077NK1", "5CD3077NK5", "5CD3077NJT",
    "5CG2283LJL", "5CD2317BB4", "5CG2254YYD", "MJ0H33VT", "5CD203PBND", "5CG2081TZF", "5CG2081VPQ",
    "MJ0EVV0", "5CG016DM05"
)

if (-not (Get-Module -ListAvailable ActiveDirectory)) {
    Write-Error "Active Directory module not found."
    exit
}

Import-Module ActiveDirectory

foreach ($computer in $computers) {
    try {
        Add-ADGroupMember -Identity $groupName -Members $computer -ErrorAction Stop
        Write-Host "Added $computer to $groupName"
    } catch {
        Write-Warning "Failed to add $computer. It may already be a member or does not exist."
    }
}
