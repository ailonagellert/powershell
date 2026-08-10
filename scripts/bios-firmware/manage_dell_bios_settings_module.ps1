#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Manages Dell BIOS settings using the DellBIOSProvider module.

.DESCRIPTION
    This script is a comprehensive tool for retrieving and configuring Dell BIOS settings.
    Features:
    - Supports getting settings to screen or CSV.
    - Supports setting BIOS options from a hardcoded list or an external CSV.
    - Handles BIOS administrative passwords.
    - Generates detailed CMTrace-compatible logs.
    - Detects Task Sequence environment for SCCM/MDT integration.

.PARAMETER GetSettings
    Switch to retrieve current BIOS settings.

.PARAMETER SetSettings
    Switch to apply BIOS settings.

.PARAMETER AdminPassword
    The current BIOS administrative password.

.PARAMETER CsvPath
    Path to the CSV file for importing/exporting settings.

.PARAMETER LogFile
    Custom path for the log file.

.NOTES
    Dell manage trio (kept intentionally — different APIs / settings catalogs):
      manage_dell_bios_settings_wmi.ps1    — WMI root\dcim\sysman (no DellBIOSProvider)
      manage_dell_bios_settings_pro.ps1    — full DellBIOSProvider orchestrator (prefer for new work)
      manage_dell_bios_settings_module.ps1 — lighter DellBIOSProvider variant (this file; smaller settings list)
    Author: Jon Anderson (@ConfigJon)
#>

param(
    [Parameter(Mandatory=$false)][Switch]$GetSettings = $true,
    [Parameter(Mandatory=$false)][Switch]$SetSettings,    
    [Parameter(Mandatory=$false)][String]$AdminPassword,
    [System.IO.FileInfo]$CsvPath,
    [System.IO.FileInfo]$LogFile = "$ENV:ProgramData\ConfigJonScripts\Dell\Manage-DellBiosSettings-PSModule.log"
)

# List of default settings to be configured if CsvPath is not used
$Settings = (
    "FingerprintReader,Enabled",
    "FnLock,Enabled",
    "IntegratedAudio,Enabled",
    "NumLock,Enabled",
    "SecureBoot,Enabled",
    "TpmActivation,Enabled",
    "TpmClear,Disabled",
    "TpmPpiClearOverride,Disabled",
    "TpmPpiDpo,Disabled",
    "TpmPpiPo,Enabled",
    "TpmSecurity,Enabled",
    "UefiNwStack,Enabled",
    "Virtualization,Enabled",
    "VtForDirectIo,Enabled",
    "WakeOnLan,Disabled"
)

# --- Functions ---

Function Get-TaskSequenceStatus {
	try { $TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment } catch{}
	if($NULL -eq $TSEnv) { return $False }
	else {
		try { $SMSTSType = $TSEnv.Value("_SMSTSType") } catch{}
		return ($NULL -ne $SMSTSType)
	}
}

Function Stop-Script {
    param([String]$ErrorMessage, [String]$Exception)
    Write-LogEntry -Value $ErrorMessage -Severity 3
    if($Exception) { Write-LogEntry -Value "Exception Message: $Exception" -Severity 3 }
    throw $ErrorMessage
}

Function Set-DellBiosSetting {
    param([String]$Name, [String]$Value, [String]$Password)
    $CurrentValue = $SettingList | Where-Object Attribute -eq $Name | Select-Object -ExpandProperty CurrentValue
    if($NULL -ne $CurrentValue) {
        if($CurrentValue -eq $Value) {
            Write-LogEntry -Value "Setting '$Name' is already set to '$Value'" -Severity 1
            $Script:AlreadySet++
        } else {
            $SettingPath = $SettingList | Where-Object Attribute -eq $Name | Select-Object -ExpandProperty PSChildName
            try {
                if([String]::IsNullOrEmpty($Password)) {
                    Set-Item -Path "DellSmbios:\$SettingPath\$Name" -Value $Value
                } else {
                    Set-Item -Path "DellSmbios:\$SettingPath\$Name" -Value $Value -Password $Password
                }
                Write-LogEntry -Value "Successfully set '$Name' to '$Value'" -Severity 1
                $Script:SuccessSet++
            } catch {
                Write-LogEntry -Value "Failed to set '$Name' to '$Value'." -Severity 3
                $Script:FailSet++
            }
        }
    } else {
        Write-LogEntry -Value "Setting '$Name' not found" -Severity 2
        $Script:NotFound++
    }
}

Function Write-LogEntry {
	param([String]$Value, [ValidateSet("1", "2", "3")][String]$Severity, [String]$FileName = ($script:LogFile | Split-Path -Leaf))
    $LogFilePath = Join-Path -Path $LogsDirectory -ChildPath $FileName
    if(-not(Test-Path -Path 'variable:global:TimezoneBias')) {
        [string]$global:TimezoneBias = [System.TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalMinutes
        $TimezoneBias = if($TimezoneBias -match "^-") { $TimezoneBias.Replace('-', '+') } else { '-' + $TimezoneBias }
    }
    $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), $TimezoneBias)
    $Date = (Get-Date -Format "MM-dd-yyyy")
    $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""Manage-DellBiosSettings-PSModule"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
    try { Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop } catch { Write-Warning "Log failed: $($_.Exception.Message)" }
}

# --- Main Program ---

if(Get-TaskSequenceStatus) {
	$TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
	$LogsDirectory = $TSEnv.Value("_SMSTSLogPath")
} else {
	$LogsDirectory = ($LogFile | Split-Path)
	if([string]::IsNullOrEmpty($LogsDirectory)) { $LogsDirectory = $PSScriptRoot }
	if(!(Test-Path -PathType Container $LogsDirectory)) { New-Item -Path $LogsDirectory -ItemType "Directory" -Force | Out-Null }
}

Write-LogEntry -Value "START - Dell BIOS settings management script" -Severity 1
$ArchPath = if([System.Environment]::Is64BitOperatingSystem) { $env:ProgramFiles } else { ${env:ProgramFiles(x86)} }

# Check for DellBIOSProvider module
try {
    Import-Module DellBIOSProvider -Force -ErrorAction Stop
    Write-LogEntry -Value "Successfully imported DellBIOSProvider" -Severity 1
} catch {
    Stop-Script -ErrorMessage "DellBIOSProvider module not found or failed to import."
}

if($GetSettings -and $SetSettings) { Stop-Script -ErrorMessage "Cannot specify both Get and Set." }

if($SetSettings) {
    $AlreadySet = $SuccessSet = $FailSet = $NotFound = 0
    $AdminPasswordCheck = Get-Item -Path DellSmbios:\Security\IsAdminPasswordSet | Select-Object -ExpandProperty CurrentValue
    if($AdminPasswordCheck -eq "True" -and [String]::IsNullOrEmpty($AdminPassword)) {
        Stop-Script -ErrorMessage "Admin password is set but not supplied."
    }
}

# Get current state
$SettingList = @()
$SettingCategory = (Get-ChildItem -Path DellSmbios:\).Category
foreach($Category in $SettingCategory) {
    $SettingList += Get-ChildItem -Path "DellSmbios:\$Category" | Select-Object Attribute,CurrentValue,PSChildName
}

if($GetSettings) {
    $SettingObject = ForEach($S in $SettingList) { [PSCustomObject]@{ Name = $S.Attribute; Value = $S.CurrentValue } }
    if($CsvPath) { 
        $SettingObject | Export-Csv -Path $CsvPath -NoTypeInformation 
        Write-Host "Exported settings to $CsvPath"
    } else { 
        $SettingObject | Sort-Object Name | Format-Table 
    }
}

if($SetSettings) {
    $TargetSettings = if($CsvPath) { Import-Csv -Path $CsvPath } else { 
        $Settings | ForEach-Object { $d = $_.Split(','); [PSCustomObject]@{ Name=$d[0].Trim(); Value=$d[1].Trim() } }
    }
    foreach($Setting in $TargetSettings) {
        Set-DellBiosSetting -Name $Setting.Name -Value $Setting.Value -Password $AdminPassword
    }
    Write-Output "Results: $SuccessSet Success, $AlreadySet Already Set, $FailSet Failed, $NotFound Not Found."
}

Write-LogEntry -Value "END - Dell BIOS settings management script" -Severity 1
