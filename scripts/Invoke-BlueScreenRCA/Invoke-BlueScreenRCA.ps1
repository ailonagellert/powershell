#Requires -Version 5.1
<#
.SYNOPSIS
    Standalone Blue Screen (BSOD) Root Cause Analyzer for Windows.

.DESCRIPTION
  Collects bugcheck events, crash dumps, WHEA/hardware errors, power failures,
  and recent driver/software changes, then produces a plain-language RCA report
  any IT person can use.

  Designed to be emailed or copied as a single file. No modules, no internet,
  no company-specific dependencies.

.PARAMETER Days
  How far back to search event logs. Default: 60.

.PARAMETER OutputDirectory
  Where to write the report. Default: Desktop\BSOD-RCA-<ComputerName>-<timestamp>

.PARAMETER Count
  Max bugcheck / related events to pull per category. Default: 25.

.PARAMETER OpenReport
  Open the HTML report when finished.

.EXAMPLE
  # Right-click > Run with PowerShell, or from an elevated PowerShell:
  .\Invoke-BlueScreenRCA.ps1

.EXAMPLE
  .\Invoke-BlueScreenRCA.ps1 -Days 90 -OpenReport

.NOTES
  - Admin recommended (full event log + dump access). Non-admin still works with reduced data.
  - Does not replace WinDbg for deep dump analysis; it gives a strong first-pass RCA.
  - Share the generated HTML/TXT report back to whoever is helping you.
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 3650)]
    [int]$Days = 60,

    [string]$OutputDirectory,

    [ValidateRange(1, 200)]
    [int]$Count = 25,

    [switch]$OpenReport
)

$ErrorActionPreference = 'Continue'

#region Helpers
function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NotePropertyValue {
    param(
        $Object,
        [string]$Name,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function Get-ShortText {
    param(
        [string]$Text,
        [int]$Max = 240
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $flat = ($Text -replace '\s+', ' ').Trim()
    if ($flat.Length -le $Max) { return $flat }
    return $flat.Substring(0, $Max)
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message, [string]$Color = 'Gray')
    Write-Host "  $Message" -ForegroundColor $Color
}

function Get-Array {
    param($InputObject)
    if ($null -eq $InputObject) { return @() }
    return @($InputObject)
}

function Get-SafeWinEvent {
    param(
        [hashtable]$FilterHashtable,
        [int]$MaxEvents = 25
    )
    try {
        return @(Get-WinEvent -FilterHashtable $FilterHashtable -MaxEvents $MaxEvents -ErrorAction Stop)
    }
    catch {
        # 15007 / no matching events is normal
        return @()
    }
}

function Convert-BugcheckToHex {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    try {
        $n = [uint32]$Value
        return ('0x{0:X8}' -f $n)
    }
    catch {
        $s = [string]$Value
        if ($s -match '0x[0-9A-Fa-f]+') { return $Matches[0].ToUpper().Replace('0X', '0x') }
        return $s
    }
}

function Get-BugcheckCatalog {
    # Common stop codes -> likely cause + next steps (public Microsoft / community knowledge)
    return @{
        '0x0000000A' = @{
            Name = 'IRQL_NOT_LESS_OR_EQUAL'
            Category = 'Driver'
            Likely = 'A kernel driver accessed paged memory at too high an IRQL (often network, storage, antivirus, or filter drivers).'
            Actions = @(
                'Update or roll back recently installed drivers (especially NIC, storage, GPU, AV/EDR).'
                'Boot into Safe Mode and uninstall the newest driver/security agent if crashes started after a change.'
                'Run driver verifier only if you can tolerate additional instability for isolation.'
            )
        }
        '0x0000001A' = @{
            Name = 'MEMORY_MANAGEMENT'
            Category = 'Memory / Driver'
            Likely = 'Memory manager detected corruption - bad RAM, faulty driver, or disk paging issues.'
            Actions = @(
                'Run Windows Memory Diagnostic or memtest86 overnight.'
                'Reseat RAM / test sticks one at a time.'
                'Check for storage health issues and update chipset/storage drivers.'
            )
        }
        '0x0000001E' = @{
            Name = 'KMODE_EXCEPTION_NOT_HANDLED'
            Category = 'Driver'
            Likely = 'A kernel-mode driver threw an unhandled exception.'
            Actions = @(
                'Identify the faulting module from dump analysis if available.'
                'Update GPU, chipset, and any recently installed kernel drivers.'
                'Remove newly installed AV/VPN/virtualization filter drivers.'
            )
        }
        '0x0000003B' = @{
            Name = 'SYSTEM_SERVICE_EXCEPTION'
            Category = 'Driver / Graphics'
            Likely = 'Exception while executing a routine that transitions to kernel mode - frequently graphics or 3rd-party drivers.'
            Actions = @(
                'Clean-install GPU drivers (DDU in Safe Mode if needed).'
                'Update Windows and chipset drivers.'
                'Check for overlay software (RGB, OSD, screen capture) conflicts.'
            )
        }
        '0x00000050' = @{
            Name = 'PAGE_FAULT_IN_NONPAGED_AREA'
            Category = 'Memory / Driver / Disk'
            Likely = 'Invalid system memory reference - bad RAM, corrupt driver, or failing storage.'
            Actions = @(
                'Run memory diagnostics.'
                'Check disk health (chkdsk / SMART).'
                'Update or remove recently added drivers.'
            )
        }
        '0x0000007A' = @{
            Name = 'KERNEL_DATA_INPAGE_ERROR'
            Category = 'Storage'
            Likely = 'Windows could not read a page of kernel data from disk/pagefile - failing drive, cable, controller, or bad RAM.'
            Actions = @(
                'Check SMART / Storage Sense / manufacturer disk tools.'
                'Replace SATA/NVMe cables or try another port/slot.'
                'Run chkdsk /f /r after backing up data.'
            )
        }
        '0x0000007E' = @{
            Name = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED'
            Category = 'Driver'
            Likely = 'A system thread crashed in a driver.'
            Actions = @(
                'Update drivers named in the dump (or uninstall the newest kernel driver).'
                'Check Device Manager for devices with errors after the crash time.'
            )
        }
        '0x0000009F' = @{
            Name = 'DRIVER_POWER_STATE_FAILURE'
            Category = 'Power / Driver'
            Likely = 'A driver failed to complete a power IRP in time (sleep/hibernate/resume issues).'
            Actions = @(
                'Update NIC, USB, GPU, and storage drivers.'
                'Disable Fast Startup and test sleep/hibernate.'
                'Remove flaky USB devices and docking stations to isolate.'
            )
        }
        '0x000000C2' = @{
            Name = 'BAD_POOL_CALLER'
            Category = 'Driver'
            Likely = 'A driver made an invalid pool request (memory corruption by a buggy driver).'
            Actions = @(
                'Update/remove recently installed filter drivers (AV, backup, encryption, VPN).'
                'Use WinDbg on the minidump to identify the culprit module.'
            )
        }
        '0x000000D1' = @{
            Name = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL'
            Category = 'Driver'
            Likely = 'Driver IRQL violation - classic buggy 3rd-party driver pattern.'
            Actions = @(
                'Update NIC/Wi-Fi, storage, and security product drivers.'
                'Uninstall newest kernel-mode software installed before the crash wave.'
            )
        }
        '0x00000124' = @{
            Name = 'WHEA_UNCORRECTABLE_ERROR'
            Category = 'Hardware'
            Likely = 'Hardware reported an uncorrectable error (CPU, RAM, PCIe, overheating, or power).'
            Actions = @(
                'Review WHEA-Logger events in this report for the hardware source.'
                'Check temperatures, PSU, RAM seating, and BIOS/firmware updates.'
                'Disable overclocking/XMP temporarily and retest.'
            )
        }
        '0x00000133' = @{
            Name = 'DPC_WATCHDOG_VIOLATION'
            Category = 'Driver / Storage'
            Likely = 'A DPC ran too long - often storage, USB, network, or filter drivers stalling.'
            Actions = @(
                'Update storage controller / NVMe / SATA drivers.'
                'Check disk health and free space.'
                'Remove USB docks/hubs and retest.'
            )
        }
        '0x00000139' = @{
            Name = 'KERNEL_SECURITY_CHECK_FAILURE'
            Category = 'Memory Corruption / Driver'
            Likely = 'Kernel detected corruption (stack cookie / CFG) - often a buggy driver or bad memory.'
            Actions = @(
                'Update drivers and run memory diagnostics.'
                'Uninstall recent AV/EDR or VPN clients to test.'
                'Analyze minidump in WinDbg for the failing module.'
            )
        }
        '0x00000154' = @{
            Name = 'UNEXPECTED_STORE_EXCEPTION'
            Category = 'Storage / Memory'
            Likely = 'Storage stack or memory compression hit an unexpected exception - frequently disk firmware, storage drivers, or RAM.'
            Actions = @(
                'Update NVMe/SATA/chipset drivers and disk firmware.'
                'Check SMART health; back up immediately if reallocated sectors rise.'
                'Run memory diagnostics; test with XMP/DOCP off.'
            )
        }
        '0x00000187' = @{
            Name = 'VIDEO_ENGINE_TIMEOUT_DETECTED'
            Category = 'Graphics'
            Likely = 'GPU engine hung/timeout.'
            Actions = @(
                'Clean-install GPU drivers; check GPU thermals and PSU capacity.'
                'Disable hardware acceleration in browsers/apps to test.'
            )
        }
        '0x000000EF' = @{
            Name = 'CRITICAL_PROCESS_DIED'
            Category = 'System / Corruption / Driver'
            Likely = 'A critical Windows process terminated unexpectedly.'
            Actions = @(
                'Run sfc /scannow and DISM RestoreHealth.'
                'Check for disk/memory issues and recent software installs.'
            )
        }
        '0x000000F4' = @{
            Name = 'CRITICAL_OBJECT_TERMINATION'
            Category = 'System / Corruption'
            Likely = 'A critical system process/thread was terminated.'
            Actions = @(
                'Run SFC/DISM; check disk health.'
                'Review Application log around the crash for faulting modules.'
            )
        }
        '0x000000CA' = @{
            Name = 'PNP_DETECTED_FATAL_ERROR'
            Category = 'Plug and Play / Driver'
            Likely = 'PnP manager hit a fatal inconsistency - often a buggy device driver.'
            Actions = @(
                'Update or remove recently added hardware/drivers.'
                'Check Device Manager for problem devices near crash times.'
            )
        }
        '0x00000109' = @{
            Name = 'CRITICAL_STRUCTURE_CORRUPTION'
            Category = 'Hardware / Rootkit / Memory'
            Likely = 'Kernel detected corruption of critical structures - hardware fault or malicious/buggy kernel code.'
            Actions = @(
                'Run memory diagnostics; update BIOS/firmware.'
                'Scan with an offline antimalware tool.'
                'Remove kernel-mode overlays and unverified drivers.'
            )
        }
        '0x0000007F' = @{
            Name = 'UNEXPECTED_KERNEL_MODE_TRAP'
            Category = 'Hardware / Driver'
            Likely = 'CPU generated a trap Windows could not handle - often bad RAM, overheating, or driver.'
            Actions = @(
                'Test RAM; check CPU thermals; reset BIOS defaults.'
                'Update chipset and storage drivers.'
            )
        }
    }
}

function Resolve-BugcheckInfo {
    param([string]$CodeHex)
    $catalog = Get-BugcheckCatalog
    if (-not $CodeHex) {
        return @{
            Name = 'Unknown'
            Category = 'Unknown'
            Likely = 'Bugcheck code could not be parsed from the event.'
            Actions = @('Open the minidump in WinDbg (!analyze -v) or share dumps with Microsoft Support / vendor.')
            Known = $false
        }
    }
    $normalized = $CodeHex.ToUpperInvariant()
    if ($normalized -notmatch '^0X') { $normalized = '0x' + $normalized.TrimStart('0X') }
    # Normalize to 0xXXXXXXXX
    try {
        $n = [Convert]::ToUInt32($normalized.Substring(2), 16)
        $normalized = '0x{0:X8}' -f $n
    }
    catch { }

    if ($catalog.ContainsKey($normalized)) {
        $info = $catalog[$normalized].Clone()
        $info['Known'] = $true
        $info['Code'] = $normalized
        return $info
    }

    return @{
        Code = $normalized
        Name = 'Unrecognized / less common stop code'
        Category = 'Needs dump analysis'
        Likely = "Stop code $normalized is not in the built-in catalog. The dump file is the best next step."
        Actions = @(
            'Open the newest minidump in WinDbg Preview and run: !analyze -v'
            'Search Microsoft Learn for the stop code hex value.'
            'Note any driver/module name returned by WinDbg.'
        )
        Known = $false
    }
}

function Get-EventPropertyMap {
    param($Event)
    $map = @{}
    try {
        $xml = [xml]$Event.ToXml()
        foreach ($node in $xml.Event.EventData.Data) {
            if ($node.Name) {
                $map[$node.Name] = $node.'#text'
            }
        }
    }
    catch { }
    return $map
}

function Parse-BugcheckFromEvent {
    param($Event)

    $props = Get-EventPropertyMap -Event $Event
    $code = $null
    $p1 = $null; $p2 = $null; $p3 = $null; $p4 = $null
    $dump = $null

    if ($props.ContainsKey('BugcheckCode')) {
        $code = Convert-BugcheckToHex $props['BugcheckCode']
    }
    elseif ($props.ContainsKey('BugCheckCode')) {
        $code = Convert-BugcheckToHex $props['BugCheckCode']
    }

    foreach ($key in @('BugcheckParameter1', 'Param1', 'Parameter1')) {
        if ($props.ContainsKey($key)) { $p1 = Convert-BugcheckToHex $props[$key]; break }
    }
    foreach ($key in @('BugcheckParameter2', 'Param2', 'Parameter2')) {
        if ($props.ContainsKey($key)) { $p2 = Convert-BugcheckToHex $props[$key]; break }
    }
    foreach ($key in @('BugcheckParameter3', 'Param3', 'Parameter3')) {
        if ($props.ContainsKey($key)) { $p3 = Convert-BugcheckToHex $props[$key]; break }
    }
    foreach ($key in @('BugcheckParameter4', 'Param4', 'Parameter4')) {
        if ($props.ContainsKey($key)) { $p4 = Convert-BugcheckToHex $props[$key]; break }
    }
    foreach ($key in @('DumpFile', 'DumpPath')) {
        if ($props.ContainsKey($key) -and $props[$key]) { $dump = $props[$key]; break }
    }

    # Fallback: parse message text "The bugcheck was: 0x..."
    if (-not $code -and $Event.Message) {
        if ($Event.Message -match 'bugcheck was:\s*(0x[0-9A-Fa-f]+)') {
            $code = Convert-BugcheckToHex $Matches[1]
        }
        elseif ($Event.Message -match '(0x[0-9A-Fa-f]{8})') {
            $code = Convert-BugcheckToHex $Matches[1]
        }
    }
    if (-not $dump -and $Event.Message -match 'Dump file:\s*(.+?\.dmp)') {
        $dump = $Matches[1].Trim()
    }

    $info = Resolve-BugcheckInfo -CodeHex $code

    return [PSCustomObject]@{
        TimeCreated     = $Event.TimeCreated
        Computer        = $Event.MachineName
        BugcheckCode    = $code
        BugcheckName    = $info.Name
        Category        = $info.Category
        Parameter1      = $p1
        Parameter2      = $p2
        Parameter3      = $p3
        Parameter4      = $p4
        DumpFile        = $dump
        LikelyCause     = $info.Likely
        RecommendedActions = ($info.Actions -join ' | ')
        Message         = $Event.Message
        KnownCode       = [bool]$info.Known
    }
}
#endregion Helpers

#region Collection
function Get-SystemContext {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $uptime = if ($os) { (Get-Date) - $os.LastBootUpTime } else { $null }

    $memGB = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { $null }

    [PSCustomObject]@{
        ComputerName   = $env:COMPUTERNAME
        UserName       = $env:USERNAME
        Domain         = $env:USERDOMAIN
        IsAdmin        = Test-IsAdministrator
        OSCaption      = $os.Caption
        OSVersion      = $os.Version
        OSBuild        = $os.BuildNumber
        InstallDate    = $os.InstallDate
        LastBoot       = $os.LastBootUpTime
        UptimeDays     = if ($uptime) { [math]::Round($uptime.TotalDays, 2) } else { $null }
        Manufacturer   = $cs.Manufacturer
        Model          = $cs.Model
        BIOSVersion    = $bios.SMBIOSBIOSVersion
        BIOSDate       = $bios.ReleaseDate
        Processor      = $cpu.Name
        MemoryGB       = $memGB
        SystemType     = $cs.SystemType
        CollectedAt    = Get-Date
    }
}

function Get-CrashDumpConfiguration {
    $cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue
    $map = @{
        0 = 'None'
        1 = 'Complete memory dump'
        2 = 'Kernel memory dump'
        3 = 'Small memory dump (minidump)'
        7 = 'Automatic memory dump'
    }
    $rawEnabled = Get-NotePropertyValue -Object $cc -Name 'CrashDumpEnabled'
    $enabled = if ($null -ne $rawEnabled -and $rawEnabled -ne '') {
        try { [int]$rawEnabled } catch { $null }
    } else { $null }

    [PSCustomObject]@{
        CrashDumpEnabled     = $enabled
        CrashDumpType        = if ($null -ne $enabled -and $map.ContainsKey($enabled)) { $map[$enabled] } else { 'Unknown / unavailable' }
        MinidumpDir          = Get-NotePropertyValue -Object $cc -Name 'MinidumpDir' -Default 'C:\Windows\Minidump'
        DumpFile             = Get-NotePropertyValue -Object $cc -Name 'DumpFile' -Default 'C:\Windows\MEMORY.DMP'
        LogEvent             = Get-NotePropertyValue -Object $cc -Name 'LogEvent'
        AutoReboot           = Get-NotePropertyValue -Object $cc -Name 'AutoReboot'
        Overwrite            = Get-NotePropertyValue -Object $cc -Name 'Overwrite'
        AlwaysKeepMemoryDump = Get-NotePropertyValue -Object $cc -Name 'AlwaysKeepMemoryDump'
    }
}

function Get-DumpInventory {
    $files = New-Object System.Collections.Generic.List[object]
    $paths = @(
        'C:\Windows\Minidump\*.dmp',
        'C:\Windows\MEMORY.DMP',
        'C:\Windows\LiveKernelReports\*.dmp'
    )
    foreach ($pattern in $paths) {
        Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            $files.Add([PSCustomObject]@{
                FullName      = $_.FullName
                Name          = $_.Name
                LengthMB      = [math]::Round($_.Length / 1MB, 2)
                LastWriteTime = $_.LastWriteTime
                AgeDays       = [math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays, 1)
            }) | Out-Null
        }
    }
    return @($files | Sort-Object LastWriteTime -Descending)
}

function Get-BugcheckEvents {
    param([datetime]$Start, [int]$MaxEvents)

    $events = Get-SafeWinEvent -FilterHashtable @{
        LogName   = 'System'
        Id        = 1001
        StartTime = $Start
    } -MaxEvents $MaxEvents

    $parsed = New-Object System.Collections.Generic.List[object]
    foreach ($e in $events) {
        $isBugcheck = ($e.ProviderName -match 'BugCheck|Windows Error Reporting|Microsoft-Windows-WER-SystemErrorReporting|Save Dump') -or
            ($e.Message -match 'bugcheck|blue screen|The computer has rebooted from a bugcheck')
        if ($isBugcheck) {
            [void]$parsed.Add((Parse-BugcheckFromEvent -Event $e))
        }
    }

    # If filter was too strict, parse 1001s that still look like crash records
    if ($parsed.Count -eq 0) {
        foreach ($e in $events) {
            if ($e.Message -match 'bugcheck|0x[0-9A-Fa-f]{8}') {
                [void]$parsed.Add((Parse-BugcheckFromEvent -Event $e))
            }
        }
    }

    return @($parsed | Sort-Object TimeCreated -Descending)
}

function Get-RelatedCrashEvents {
    param([datetime]$Start, [int]$MaxEvents)

    $rows = @()

    $k41 = Get-SafeWinEvent -FilterHashtable @{
        LogName      = 'System'
        ProviderName = 'Microsoft-Windows-Kernel-Power'
        Id           = 41
        StartTime    = $Start
    } -MaxEvents $MaxEvents
    foreach ($e in $k41) {
        $rows += [PSCustomObject]@{
            TimeCreated = $e.TimeCreated
            Type        = 'Kernel-Power 41 (unexpected shutdown / power loss)'
            Provider    = $e.ProviderName
            Id          = $e.Id
            Summary     = 'System rebooted without clean shutdown. Can be BSOD, hard power loss, or forced reset.'
            Message     = Get-ShortText -Text $e.Message
        }
    }

    $u6008 = Get-SafeWinEvent -FilterHashtable @{
        LogName   = 'System'
        Id        = 6008
        StartTime = $Start
    } -MaxEvents $MaxEvents
    foreach ($e in $u6008) {
        $rows += [PSCustomObject]@{
            TimeCreated = $e.TimeCreated
            Type        = 'Unexpected Shutdown 6008'
            Provider    = $e.ProviderName
            Id          = $e.Id
            Summary     = 'Previous shutdown was unexpected.'
            Message     = Get-ShortText -Text $e.Message
        }
    }

    $whea = Get-SafeWinEvent -FilterHashtable @{
        LogName      = 'System'
        ProviderName = 'Microsoft-Windows-WHEA-Logger'
        StartTime    = $Start
    } -MaxEvents $MaxEvents
    foreach ($e in $whea) {
        $level = $e.LevelDisplayName
        if ($level -in @('Error', 'Critical', 'Warning') -or $e.Id -in 1, 17, 18, 19, 47) {
            $rows += [PSCustomObject]@{
                TimeCreated = $e.TimeCreated
                Type        = "WHEA Hardware Error (Event $($e.Id))"
                Provider    = $e.ProviderName
                Id          = $e.Id
                Summary     = 'Hardware error reported by WHEA - strong hardware signal when near BSOD times.'
                Message     = Get-ShortText -Text $e.Message
            }
        }
    }

    # Volmgr / disk hints often precede UNEXPECTED_STORE_EXCEPTION / INPAGE errors
    $disk = Get-SafeWinEvent -FilterHashtable @{
        LogName      = 'System'
        ProviderName = 'disk'
        StartTime    = $Start
    } -MaxEvents ([Math]::Min(15, $MaxEvents))
    foreach ($e in $disk | Where-Object { $_.LevelDisplayName -in @('Error', 'Warning') }) {
        $rows += [PSCustomObject]@{
            TimeCreated = $e.TimeCreated
            Type        = "Disk Error/Warning (Event $($e.Id))"
            Provider    = $e.ProviderName
            Id          = $e.Id
            Summary     = 'Storage subsystem reported an error near the analysis window.'
            Message     = Get-ShortText -Text $e.Message
        }
    }

    return @($rows | Sort-Object TimeCreated -Descending)
}

function Get-RecentDriverAndSoftwareChanges {
    param([datetime]$Start)

    $changes = @()

    # Driver installs / Device setup (Kernel-PnP Configuration)
    $pnp = Get-SafeWinEvent -FilterHashtable @{
        LogName      = 'Microsoft-Windows-Kernel-PnP/Configuration'
        StartTime    = $Start
    } -MaxEvents 40
    foreach ($e in $pnp | Where-Object { $_.Id -in 400, 410, 430, 440 }) {
        $changes += [PSCustomObject]@{
            TimeCreated = $e.TimeCreated
            ChangeType  = 'Driver / Device (Kernel-PnP)'
            Detail      = Get-ShortText -Text $e.Message -Max 220
        }
    }

    # Setup Event Log application installs (if present)
    $setup = Get-SafeWinEvent -FilterHashtable @{
        LogName   = 'Setup'
        StartTime = $Start
    } -MaxEvents 20
    foreach ($e in $setup) {
        $changes += [PSCustomObject]@{
            TimeCreated = $e.TimeCreated
            ChangeType  = "Setup Log Event $($e.Id)"
            Detail      = Get-ShortText -Text $e.Message -Max 220
        }
    }

    # Hotfixes installed recently
    try {
        $hotfixes = Get-HotFix -ErrorAction SilentlyContinue |
            Where-Object { $_.InstalledOn -and $_.InstalledOn -ge $Start } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 15
        foreach ($hf in $hotfixes) {
            $changes += [PSCustomObject]@{
                TimeCreated = $hf.InstalledOn
                ChangeType  = "Hotfix $($hf.HotFixID)"
                Detail      = "$($hf.Description) by $($hf.InstalledBy)"
            }
        }
    }
    catch { }

    # Recently modified .sys drivers (rough signal)
    try {
        $sysFiles = Get-ChildItem 'C:\Windows\System32\drivers\*.sys' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $Start } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 20
        foreach ($f in $sysFiles) {
            $changes += [PSCustomObject]@{
                TimeCreated = $f.LastWriteTime
                ChangeType  = 'Driver file modified (System32\drivers)'
                Detail      = "$($f.Name) ($([math]::Round($f.Length/1KB)) KB)"
            }
        }
    }
    catch { }

    return @($changes | Sort-Object TimeCreated -Descending)
}
#endregion Collection

#region RCA Engine
function Build-RootCauseAssessment {
    param(
        $Bugchecks,
        $Related,
        $Dumps,
        $Changes,
        $DumpConfig,
        $Context
    )

    $findings = @()
    $confidence = 'Low'
    $headline = 'No clear BSOD pattern found in the selected window.'
    $primaryCode = $null
    $categoryVotes = @{}

    $bugList = @($Bugchecks | Where-Object { $_ -and ($_.BugcheckCode -or ($_.Message -match 'bugcheck')) })
    $relList = @($Related | Where-Object { $_ })
    $dumpList = @($Dumps | Where-Object { $_ })
    $changeList = @($Changes | Where-Object { $_ })

    if ($bugList.Count -eq 0) {
        $k41 = @($relList | Where-Object { $_.Type -like 'Kernel-Power 41*' })
        $whea = @($relList | Where-Object { $_.Type -like 'WHEA*' })
        if ($k41.Count -gt 0 -and $whea.Count -gt 0) {
            $headline = 'No Bugcheck 1001 events, but Kernel-Power 41 + WHEA errors suggest hardware or hard power-loss crashes.'
            $confidence = 'Medium'
            $findings += 'Investigate PSU, RAM, overheating, and motherboard WHEA details.'
        }
        elseif ($k41.Count -gt 0) {
            $headline = 'No formal bugcheck records; unexpected Kernel-Power 41 reboot(s) detected.'
            $confidence = 'Low'
            $findings += 'Could be BSOD with dump/logging disabled, power button reset, PSU blip, or overheating shutdown.'
            $findings += "Crash dump type is currently: $($DumpConfig.CrashDumpType)."
        }
        else {
            $headline = 'No BSOD bugchecks or Kernel-Power 41 events found in the lookback window.'
            $confidence = 'High'
            $findings += 'If crashes are still happening, reproduce once with dumps enabled and re-run this script.'
        }
    }
    else {
        $primary = $bugList | Select-Object -First 1
        $primaryCode = $primary.BugcheckCode
        $headline = "Most recent BSOD: $($primary.BugcheckCode) $($primary.BugcheckName) at $($primary.TimeCreated)"
        $confidence = if ($primary.KnownCode) { 'Medium' } else { 'Low' }

        $grouped = $bugList | Group-Object BugcheckCode | Sort-Object Count -Descending
        foreach ($g in $grouped) {
            $info = Resolve-BugcheckInfo -CodeHex $g.Name
            if (-not $categoryVotes.ContainsKey($info.Category)) { $categoryVotes[$info.Category] = 0 }
            $categoryVotes[$info.Category] += $g.Count
            $findings += "$($g.Count)x $($g.Name) ($($info.Name)) - $($info.Category). $($info.Likely)"
        }

        $topCategory = ($categoryVotes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)
        if ($topCategory) {
            $findings += "Dominant failure category: $($topCategory.Key) ($($topCategory.Value) event(s))."
            if ($bugList.Count -ge 2) { $confidence = 'Medium' }
            if ($bugList.Count -ge 3 -and $grouped.Count -eq 1) { $confidence = 'High' }
        }

        # Correlate WHEA near bugchecks
        $wheaNear = @()
        foreach ($b in $bugList) {
            $wheaNear += @($relList | Where-Object {
                    $_.Type -like 'WHEA*' -and
                    $_.TimeCreated -ge $b.TimeCreated.AddMinutes(-30) -and
                    $_.TimeCreated -le $b.TimeCreated.AddMinutes(30)
                })
        }
        if ($wheaNear.Count -gt 0) {
            $confidence = 'High'
            $findings += 'WHEA hardware errors occurred near one or more BSODs - prioritize hardware (CPU/RAM/PCIe/power/thermals).'
        }

        $diskNear = @($relList | Where-Object { $_.Type -like 'Disk*' })
        if ($diskNear.Count -gt 0 -and ($primary.BugcheckCode -in @('0x00000154', '0x0000007A', '0x00000050', '0x00000133'))) {
            $confidence = 'High'
            $findings += 'Disk errors appear in the same window as storage-related stop codes - check drive health and storage drivers immediately.'
        }

        # Changes within 14 days before first recent bugcheck
        $firstBug = ($bugList | Sort-Object TimeCreated | Select-Object -First 1).TimeCreated
        $recentChanges = @($changeList | Where-Object {
                $_.TimeCreated -ge $firstBug.AddDays(-14) -and $_.TimeCreated -le $firstBug.AddDays(1)
            })
        if ($recentChanges.Count -gt 0) {
            $findings += "Potential change correlation: $($recentChanges.Count) driver/software/hotfix change(s) within ~14 days of the crash wave. Review the Changes section."
        }

        if ($dumpList.Count -eq 0) {
            $findings += 'No dump files found. Enable at least Automatic/Kernel dumps, reproduce once, then re-run for stronger RCA.'
            if ($DumpConfig.CrashDumpEnabled -eq 0) {
                $findings += 'Crash dumps are currently DISABLED in registry.'
            }
        }
        else {
            $newest = $dumpList | Select-Object -First 1
            $findings += "Newest dump: $($newest.FullName) ($($newest.LengthMB) MB, $($newest.LastWriteTime))."
            $findings += 'For definitive module name, open that dump in WinDbg Preview and run: !analyze -v'
        }
    }

    # Recommended actions from primary code
    $actions = @()
    if ($primaryCode) {
        $info = Resolve-BugcheckInfo -CodeHex $primaryCode
        $actions = @($info.Actions)
    }
    $actions += 'Keep this HTML/TXT report with the newest .dmp file when escalating to vendor or Tier 3.'
    $actions += 'Avoid random "optimizer" tools; change one variable at a time (driver, stick of RAM, disk, etc.).'

    if (-not $Context.IsAdmin) {
        $findings += 'Script was NOT elevated - some events/dumps may be missing. Re-run as Administrator for complete RCA.'
    }

    [PSCustomObject]@{
        Headline           = $headline
        Confidence         = $confidence
        PrimaryBugcheck    = $primaryCode
        Findings           = $findings
        RecommendedActions = $actions
        BugcheckCount      = $bugList.Count
        RelatedEventCount  = $relList.Count
        DumpCount          = $dumpList.Count
    }
}
#endregion RCA Engine

#region Reporting
function ConvertTo-HtmlEncoded {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function New-HtmlReport {
    param(
        $Context,
        $Assessment,
        $Bugchecks,
        $Related,
        $Dumps,
        $Changes,
        $DumpConfig,
        [string]$Path,
        [int]$Days
    )

    $rowsBug = foreach ($b in @($Bugchecks)) {
        @"
<tr>
  <td>$(ConvertTo-HtmlEncoded $b.TimeCreated)</td>
  <td><strong>$(ConvertTo-HtmlEncoded $b.BugcheckCode)</strong><br/>$(ConvertTo-HtmlEncoded $b.BugcheckName)</td>
  <td>$(ConvertTo-HtmlEncoded $b.Category)</td>
  <td>$(ConvertTo-HtmlEncoded $b.Parameter1)<br/>$(ConvertTo-HtmlEncoded $b.Parameter2)<br/>$(ConvertTo-HtmlEncoded $b.Parameter3)<br/>$(ConvertTo-HtmlEncoded $b.Parameter4)</td>
  <td>$(ConvertTo-HtmlEncoded $b.LikelyCause)</td>
</tr>
"@
    }

    $rowsRel = foreach ($r in @($Related | Select-Object -First 40)) {
        @"
<tr>
  <td>$(ConvertTo-HtmlEncoded $r.TimeCreated)</td>
  <td>$(ConvertTo-HtmlEncoded $r.Type)</td>
  <td>$(ConvertTo-HtmlEncoded $r.Summary)</td>
  <td>$(ConvertTo-HtmlEncoded $r.Message)</td>
</tr>
"@
    }

    $rowsDump = foreach ($d in @($Dumps)) {
        @"
<tr>
  <td>$(ConvertTo-HtmlEncoded $d.LastWriteTime)</td>
  <td>$(ConvertTo-HtmlEncoded $d.FullName)</td>
  <td>$($d.LengthMB)</td>
  <td>$($d.AgeDays)</td>
</tr>
"@
    }

    $rowsChg = foreach ($c in @($Changes | Select-Object -First 40)) {
        @"
<tr>
  <td>$(ConvertTo-HtmlEncoded $c.TimeCreated)</td>
  <td>$(ConvertTo-HtmlEncoded $c.ChangeType)</td>
  <td>$(ConvertTo-HtmlEncoded $c.Detail)</td>
</tr>
"@
    }

    $findingsLi = ($Assessment.Findings | ForEach-Object { "<li>$(ConvertTo-HtmlEncoded $_)</li>" }) -join "`n"
    $actionsLi = ($Assessment.RecommendedActions | ForEach-Object { "<li>$(ConvertTo-HtmlEncoded $_)</li>" }) -join "`n"

    $confColor = switch ($Assessment.Confidence) {
        'High' { '#0b7a0b' }
        'Medium' { '#9a6b00' }
        default { '#8a1f1f' }
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>BSOD RCA - $(ConvertTo-HtmlEncoded $Context.ComputerName)</title>
<style>
  body { font-family: Segoe UI, Tahoma, sans-serif; margin: 24px; color: #1a1a1a; background: #fafafa; }
  h1,h2 { color: #0b3d5c; }
  .card { background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 16px 20px; margin: 16px 0; }
  .headline { font-size: 1.15rem; font-weight: 600; }
  .meta { color: #555; font-size: 0.92rem; }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 999px; background: $confColor; color: #fff; font-size: 0.85rem; }
  table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
  th, td { border: 1px solid #e2e2e2; padding: 8px; vertical-align: top; text-align: left; }
  th { background: #eef5fa; }
  tr:nth-child(even) { background: #f9fbfd; }
  code { background: #f0f0f0; padding: 1px 4px; border-radius: 3px; }
  ul { line-height: 1.45; }
</style>
</head>
<body>
  <h1>Blue Screen Root Cause Analysis</h1>
  <p class="meta">
    Computer: <strong>$(ConvertTo-HtmlEncoded $Context.ComputerName)</strong> |
    Collected: $(ConvertTo-HtmlEncoded $Context.CollectedAt) |
    Lookback: $Days days |
    Elevated: $($Context.IsAdmin)
  </p>

  <div class="card">
    <div class="headline">$(ConvertTo-HtmlEncoded $Assessment.Headline)</div>
    <p>Confidence: <span class="badge">$(ConvertTo-HtmlEncoded $Assessment.Confidence)</span>
       &nbsp;|&nbsp; Bugchecks: $($Assessment.BugcheckCount)
       &nbsp;|&nbsp; Related events: $($Assessment.RelatedEventCount)
       &nbsp;|&nbsp; Dump files: $($Assessment.DumpCount)
    </p>
    <h2>Findings</h2>
    <ul>$findingsLi</ul>
    <h2>Recommended next actions</h2>
    <ul>$actionsLi</ul>
  </div>

  <div class="card">
    <h2>System context</h2>
    <table>
      <tr><th>Field</th><th>Value</th></tr>
      <tr><td>OS</td><td>$(ConvertTo-HtmlEncoded $Context.OSCaption) ($($Context.OSVersion) / build $($Context.OSBuild))</td></tr>
      <tr><td>Hardware</td><td>$(ConvertTo-HtmlEncoded $Context.Manufacturer) $(ConvertTo-HtmlEncoded $Context.Model)</td></tr>
      <tr><td>BIOS</td><td>$(ConvertTo-HtmlEncoded $Context.BIOSVersion) ($(ConvertTo-HtmlEncoded $Context.BIOSDate))</td></tr>
      <tr><td>CPU</td><td>$(ConvertTo-HtmlEncoded $Context.Processor)</td></tr>
      <tr><td>Memory</td><td>$($Context.MemoryGB) GB</td></tr>
      <tr><td>Last boot</td><td>$(ConvertTo-HtmlEncoded $Context.LastBoot) (uptime $($Context.UptimeDays) days)</td></tr>
      <tr><td>Crash dump config</td><td>$(ConvertTo-HtmlEncoded $DumpConfig.CrashDumpType) (CrashDumpEnabled=$($DumpConfig.CrashDumpEnabled))</td></tr>
      <tr><td>Minidump dir</td><td>$(ConvertTo-HtmlEncoded $DumpConfig.MinidumpDir)</td></tr>
      <tr><td>Dump file path</td><td>$(ConvertTo-HtmlEncoded $DumpConfig.DumpFile)</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Bugcheck events (Event ID 1001)</h2>
    <table>
      <tr><th>Time</th><th>Stop code</th><th>Category</th><th>Parameters</th><th>Likely cause</th></tr>
      $($rowsBug -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Related crash / hardware signals</h2>
    <table>
      <tr><th>Time</th><th>Type</th><th>Summary</th><th>Message preview</th></tr>
      $($rowsRel -join "`n")
    </table>
  </div>

  <div class="card">
    <h2>Crash dump files</h2>
    <table>
      <tr><th>Modified</th><th>Path</th><th>MB</th><th>Age (days)</th></tr>
      $($rowsDump -join "`n")
    </table>
    <p class="meta">WinDbg Preview: open the newest dump -> <code>!analyze -v</code></p>
  </div>

  <div class="card">
    <h2>Recent driver / software / hotfix changes</h2>
    <table>
      <tr><th>Time</th><th>Type</th><th>Detail</th></tr>
      $($rowsChg -join "`n")
    </table>
  </div>

  <p class="meta">Generated by Invoke-BlueScreenRCA.ps1 (standalone). This is a first-pass RCA aid, not a substitute for full dump analysis when hardware or unsigned drivers are involved.</p>
</body>
</html>
"@

    Set-Content -Path $Path -Value $html -Encoding UTF8
}

function New-TextReport {
    param(
        $Context,
        $Assessment,
        $Bugchecks,
        $Related,
        $Dumps,
        $Changes,
        $DumpConfig,
        [string]$Path,
        [int]$Days
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('BLUE SCREEN ROOT CAUSE ANALYSIS')
    [void]$sb.AppendLine(('=' * 70))
    [void]$sb.AppendLine("Computer : $($Context.ComputerName)")
    [void]$sb.AppendLine("Collected: $($Context.CollectedAt)")
    [void]$sb.AppendLine("Lookback : $Days days | Elevated: $($Context.IsAdmin)")
    [void]$sb.AppendLine("OS       : $($Context.OSCaption) ($($Context.OSVersion))")
    [void]$sb.AppendLine("Hardware : $($Context.Manufacturer) $($Context.Model)")
    [void]$sb.AppendLine("BIOS     : $($Context.BIOSVersion)")
    [void]$sb.AppendLine("Memory   : $($Context.MemoryGB) GB")
    [void]$sb.AppendLine("Dump cfg : $($DumpConfig.CrashDumpType)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('ASSESSMENT')
    [void]$sb.AppendLine(('-' * 70))
    [void]$sb.AppendLine($Assessment.Headline)
    [void]$sb.AppendLine("Confidence: $($Assessment.Confidence)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Findings:')
    foreach ($f in $Assessment.Findings) { [void]$sb.AppendLine(" - $f") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Recommended actions:')
    foreach ($a in $Assessment.RecommendedActions) { [void]$sb.AppendLine(" - $a") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('BUGCHECKS')
    [void]$sb.AppendLine(('-' * 70))
    foreach ($b in @($Bugchecks)) {
        [void]$sb.AppendLine("$($b.TimeCreated)  $($b.BugcheckCode) $($b.BugcheckName) [$($b.Category)]")
        [void]$sb.AppendLine("    Params: $($b.Parameter1), $($b.Parameter2), $($b.Parameter3), $($b.Parameter4)")
        [void]$sb.AppendLine("    $($b.LikelyCause)")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('RELATED EVENTS')
    [void]$sb.AppendLine(('-' * 70))
    foreach ($r in @($Related | Select-Object -First 40)) {
        [void]$sb.AppendLine("$($r.TimeCreated)  $($r.Type)")
        [void]$sb.AppendLine("    $($r.Summary)")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('DUMP FILES')
    [void]$sb.AppendLine(('-' * 70))
    foreach ($d in @($Dumps)) {
        [void]$sb.AppendLine("$($d.LastWriteTime)  $($d.LengthMB) MB  $($d.FullName)")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('RECENT CHANGES')
    [void]$sb.AppendLine(('-' * 70))
    foreach ($c in @($Changes | Select-Object -First 40)) {
        [void]$sb.AppendLine("$($c.TimeCreated)  $($c.ChangeType)")
        [void]$sb.AppendLine("    $($c.Detail)")
    }

    Set-Content -Path $Path -Value $sb.ToString() -Encoding UTF8
}
#endregion Reporting

#region Main
Write-Section 'Blue Screen RCA Analyzer (standalone)'
Write-Info "Lookback: $Days days | Max events/category: $Count"
$isAdmin = Test-IsAdministrator
if ($isAdmin) {
    Write-Info 'Running elevated - full collection enabled.' 'Green'
}
else {
    Write-Info 'Not elevated - results may be incomplete. Right-click PowerShell > Run as administrator, then re-run.' 'Yellow'
}

$start = (Get-Date).AddDays(-$Days)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutputDirectory) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $OutputDirectory = Join-Path $desktop "BSOD-RCA-$env:COMPUTERNAME-$stamp"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Write-Section '1/6 System context'
$context = Get-SystemContext
Write-Info "$($context.Manufacturer) $($context.Model) | $($context.OSCaption) build $($context.OSBuild)"
Write-Info "Last boot: $($context.LastBoot) (uptime $($context.UptimeDays) days) | RAM: $($context.MemoryGB) GB"

Write-Section '2/6 Crash dump configuration & files'
$dumpConfig = Get-CrashDumpConfiguration
$dumps = Get-Array (Get-DumpInventory)
Write-Info "Dump type: $($dumpConfig.CrashDumpType) (CrashDumpEnabled=$($dumpConfig.CrashDumpEnabled))"
if ($dumps.Count -gt 0) {
    Write-Info "Found $($dumps.Count) dump file(s). Newest: $($dumps[0].Name) at $($dumps[0].LastWriteTime)" 'Green'
}
else {
    Write-Info 'No dump files found under Minidump / MEMORY.DMP / LiveKernelReports.' 'Yellow'
}

Write-Section '3/6 Bugcheck events'
$bugchecks = Get-Array (Get-BugcheckEvents -Start $start -MaxEvents $Count)
if ($bugchecks.Count -gt 0) {
    Write-Info "Found $($bugchecks.Count) bugcheck event(s)." 'Green'
    $bugchecks | Select-Object -First 5 | ForEach-Object {
        Write-Info "$($_.TimeCreated)  $($_.BugcheckCode) $($_.BugcheckName)" 'Red'
    }
}
else {
    Write-Info 'No Event ID 1001 bugcheck records in lookback window.' 'Yellow'
}

Write-Section '4/6 Related crash / hardware signals'
$related = Get-Array (Get-RelatedCrashEvents -Start $start -MaxEvents $Count)
Write-Info "Related events collected: $($related.Count)"

Write-Section '5/6 Recent driver / software changes'
$changes = Get-Array (Get-RecentDriverAndSoftwareChanges -Start $start)
Write-Info "Change markers collected: $($changes.Count)"

Write-Section '6/6 Root cause assessment'
$assessment = Build-RootCauseAssessment -Bugchecks $bugchecks -Related $related -Dumps $dumps -Changes $changes -DumpConfig $dumpConfig -Context $context
Write-Host ""
Write-Host "  $($assessment.Headline)" -ForegroundColor White
Write-Info "Confidence: $($assessment.Confidence)" $(if ($assessment.Confidence -eq 'High') { 'Green' } elseif ($assessment.Confidence -eq 'Medium') { 'Yellow' } else { 'Red' })
foreach ($f in $assessment.Findings) { Write-Info "- $f" 'Gray' }
Write-Host ""
Write-Info 'Next actions:' 'Cyan'
foreach ($a in $assessment.RecommendedActions) { Write-Info "- $a" 'White' }

$htmlPath = Join-Path $OutputDirectory 'BSOD-RCA-Report.html'
$txtPath  = Join-Path $OutputDirectory 'BSOD-RCA-Report.txt'
$jsonPath = Join-Path $OutputDirectory 'BSOD-RCA-Data.json'

New-HtmlReport -Context $context -Assessment $assessment -Bugchecks $bugchecks -Related $related -Dumps $dumps -Changes $changes -DumpConfig $dumpConfig -Path $htmlPath -Days $Days
New-TextReport -Context $context -Assessment $assessment -Bugchecks $bugchecks -Related $related -Dumps $dumps -Changes $changes -DumpConfig $dumpConfig -Path $txtPath -Days $Days

$payload = [PSCustomObject]@{
    Context     = $context
    Assessment  = $assessment
    DumpConfig  = $dumpConfig
    Bugchecks   = $bugchecks
    Related     = $related
    Dumps       = $dumps
    Changes     = $changes
}
$payload | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

# Copy newest dumps into report folder (small/minidumps only, cap size)
$copyDir = Join-Path $OutputDirectory 'dumps'
New-Item -ItemType Directory -Path $copyDir -Force | Out-Null
$copied = 0
foreach ($d in @($dumps | Select-Object -First 5)) {
    if (-not $d -or -not $d.FullName) { continue }
    if ($d.LengthMB -le 500) {
        try {
            Copy-Item -LiteralPath $d.FullName -Destination $copyDir -ErrorAction Stop
            $copied++
        }
        catch {
            Write-Info "Could not copy dump $($d.Name): $($_.Exception.Message)" 'Yellow'
        }
    }
    else {
        Write-Info "Skipped large dump copy ($($d.LengthMB) MB): $($d.Name) - attach manually if needed." 'Yellow'
    }
}

Write-Section 'Report ready'
Write-Info "Folder : $OutputDirectory" 'Green'
Write-Info "HTML   : $htmlPath" 'Green'
Write-Info "Text   : $txtPath" 'Green'
Write-Info "JSON   : $jsonPath"
Write-Info "Dumps copied into report folder: $copied"
Write-Host ""
Write-Info 'Share the whole BSOD-RCA-* folder (or at least the HTML + dumps) with whoever is helping.' 'Cyan'
Write-Info 'Optional deeper analysis: install WinDbg Preview from Microsoft Store, open newest .dmp, run: !analyze -v'

if ($OpenReport -and (Test-Path $htmlPath)) {
    Start-Process $htmlPath
}

# Useful object for interactive sessions
[PSCustomObject]@{
    OutputDirectory = $OutputDirectory
    HtmlReport      = $htmlPath
    TextReport      = $txtPath
    Assessment      = $assessment
    Bugchecks       = $bugchecks
}
#endregion Main
