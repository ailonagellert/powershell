<#
.SYNOPSIS
    Identifies currently logged-on interactive users.

.DESCRIPTION
    Correlates 'Win32_LogonSession' (LogonType 2 - Interactive) with 
    'Win32_LoggedOnUser' to provide a clean list of domain and username 
    for users physically or interactively logged into the machine.

.NOTES
#>

$sessions = Get-CimInstance -ClassName Win32_LogonSession | Where-Object { $_.LogonType -eq 2 }
$results = foreach ($s in $sessions) {
    Get-CimInstance -ClassName Win32_LoggedOnUser | Where-Object { 
        $_.Dependent -match $s.LogonId 
    } | Select-Object -ExpandProperty Antecedent
}

$results | Select-Object -Unique | ForEach-Object {
    $_.Name
}
