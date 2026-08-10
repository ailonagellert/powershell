#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Advanced WinRE repair with Network Source Fallback (wrapper).

.DESCRIPTION
    Thin wrapper that preserves this filename for existing Intune/SCCM deployments.
    Canonical implementation: repair_and_register_winre_partition.ps1

.NOTES
    Original Filename: AutoSaved_7bcd3f1b-fc5a-4630-a2a7-b46f18e3f9e4_Untitled307.ps1
#>

[CmdletBinding()]
param(
    [int]$RecoveryPartitionSizeMB = 800,
    [string]$WinreSourcePath = "C:\Windows\System32\Recovery\Winre.wim",
    [string]$NetworkWinreSource = "\\corp\dfs\Temp\DE\WinRe-Repair\winre.wim",
    [string]$BitLockerMountPoint = "C:"
)

& "$PSScriptRoot\repair_and_register_winre_partition.ps1" @PSBoundParameters
exit $LASTEXITCODE
