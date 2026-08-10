#Requires -Version 5.1
<#
.SYNOPSIS
    Standalone Blue Screen (BSOD) Root Cause Analyzer for Windows.

.DESCRIPTION
    Collects bugcheck events, crash dumps, WHEA/hardware errors, power failures,
    and recent driver/software changes, then produces a plain-language RCA report
    plus PASTE-INTO-COPILOT.txt (copied to clipboard) for second-pass AI analysis.

    If Debugging Tools / WinDbg is missing and dumps need analysis, the script
    automatically installs WinDbg Preview via winget when possible (unless
    -SkipDebuggerInstall is set). Falls back to Windows SDK packages for cdb.exe.

    Offline-capable for event/dump inventory. Dump analysis uses Microsoft public
    symbols (needs internet the first time symbols are downloaded).

.PARAMETER Days
    Event log lookback window. Default: 60.

.PARAMETER OutputDirectory
    Report folder. Default: Desktop\BSOD-RCA-<ComputerName>-<timestamp>

.PARAMETER Count
    Max events per category. Default: 25.

.PARAMETER OpenReport
    Open the HTML report when finished.

.PARAMETER AnalyzeDumps
    Force dump analysis when cdb.exe is available (default: analyze when dumps exist).

.PARAMETER SkipDumpAnalysis
    Never run WinDbg/cdb, even if dumps and cdb.exe are present.

.PARAMETER MaxDumpsToAnalyze
    How many newest dumps to analyze. Default: 3.

.PARAMETER MaxDumpSizeMB
    Skip dumps larger than this for automated analysis. Default: 2048.

.PARAMETER DumpAnalysisTimeoutSec
    Per-dump cdb timeout. Default: 300.

.PARAMETER InstallDebuggers
    Force a winget install attempt for WinDbg (and SDK cdb fallback) even if one may already exist.
    When dumps need analysis and no debugger is found, install is attempted automatically unless
    -SkipDebuggerInstall is set.

.PARAMETER SkipDebuggerInstall
    Do not attempt winget installs. Analysis only runs if WinDbg/cdb is already present.

.PARAMETER SkipClipboard
    Do not copy PASTE-INTO-COPILOT.txt to the clipboard when finished.

.EXAMPLE
    .\Invoke-BlueScreenRCA.ps1 -OpenReport

.EXAMPLE
    .\Invoke-BlueScreenRCA.ps1 -Days 90 -AnalyzeDumps -OpenReport
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 3650)]
    [int]$Days = 60,

    [string]$OutputDirectory,

    [ValidateRange(1, 200)]
    [int]$Count = 25,

    [switch]$OpenReport,

    [switch]$AnalyzeDumps,

    [switch]$SkipDumpAnalysis,

    [ValidateRange(1, 20)]
    [int]$MaxDumpsToAnalyze = 3,

    [ValidateRange(16, 65536)]
    [int]$MaxDumpSizeMB = 2048,

    [ValidateRange(30, 3600)]
    [int]$DumpAnalysisTimeoutSec = 300,

    [switch]$InstallDebuggers,

    [switch]$SkipDebuggerInstall,

    [switch]$SkipClipboard
)

$ErrorActionPreference = 'Continue'

#region Helpers
function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NotePropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function Get-ShortText {
    param([string]$Text, [int]$Max = 240)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $flat = ($Text -replace '\s+', ' ').Trim()
    if ($flat.Length -le $Max) { return $flat }
    return $flat.Substring(0, $Max)
}

function Get-Array {
    param($InputObject)
    # Leading comma prevents PowerShell from unwrapping a single-element array on return.
    # Avoid @($genericList) which can throw "Argument types do not match" on PS 5.1.
    if ($null -eq $InputObject) { return , [object[]]@() }
    if ($InputObject -is [System.Collections.ICollection] -and $InputObject -isnot [string] -and $InputObject.PSObject.Methods['ToArray']) {
        try { return , [object[]]$InputObject.ToArray() } catch { }
    }
    if ($InputObject -is [System.Array]) {
        return , [object[]]$InputObject
    }
    return , [object[]]@($InputObject)
}

function ConvertTo-ObjectArray {
    param($InputObject)
    if ($null -eq $InputObject) { return [object[]]@() }
    if ($InputObject -is [System.Collections.ICollection] -and $InputObject.PSObject.Methods['ToArray']) {
        try { return [object[]]$InputObject.ToArray() } catch { }
    }
    if ($InputObject -is [System.Array]) { return [object[]]$InputObject }
    $tmp = New-Object System.Collections.Generic.List[object]
    foreach ($i in @($InputObject)) { [void]$tmp.Add($i) }
    return [object[]]$tmp.ToArray()
}

function Get-CrashAnchorTimes {
    param(
        $Bugchecks,
        $Dumps,
        $DumpAnalyses,
        [int]$MaxDumpAnchors = 5
    )

    $times = New-Object System.Collections.Generic.List[datetime]

    # Prefer official BSOD event times when present - do not let year-old dumps widen the filter
    foreach ($b in (Get-Array $Bugchecks)) {
        if ($b.TimeCreated) { [void]$times.Add([datetime]$b.TimeCreated) }
    }

    if ($times.Count -eq 0) {
        $dumpTimes = New-Object System.Collections.Generic.List[datetime]
        foreach ($d in (Get-Array $Dumps)) {
            if (-not $d.LastWriteTime) { continue }
            if ($d.Name -match '^\d{6}-\d+' -or $d.FullName -match '(?i)\\Kernel_[0-9a-f]+_' -or $d.Name -match '(?i)^(WHEA|WATCHDOG)-') {
                [void]$dumpTimes.Add([datetime]$d.LastWriteTime)
            }
        }
        foreach ($t in @((ConvertTo-ObjectArray $dumpTimes) | Sort-Object -Descending | Select-Object -First $MaxDumpAnchors)) {
            [void]$times.Add($t)
        }
    }

    foreach ($a in (Get-Array $DumpAnalyses)) {
        if ($a.DumpPath -and (Test-Path -LiteralPath $a.DumpPath)) {
            try {
                $wt = (Get-Item -LiteralPath $a.DumpPath).LastWriteTime
                # Only add analysis dump times if close to an existing anchor, or if we still have none
                if ($times.Count -eq 0 -or (Test-IsNearCrashTime -Time $wt -AnchorTimes (ConvertTo-ObjectArray $times) -BeforeHours 24 -AfterHours 24)) {
                    [void]$times.Add($wt)
                }
            }
            catch { }
        }
    }

    if ($times.Count -eq 0) { return , [object[]]@() }

    $sorted = @(ConvertTo-ObjectArray $times | Sort-Object)
    $collapsed = New-Object System.Collections.Generic.List[datetime]
    foreach ($t in $sorted) {
        if ($collapsed.Count -eq 0 -or ($t - $collapsed[$collapsed.Count - 1]).TotalMinutes -gt 5) {
            [void]$collapsed.Add($t)
        }
    }
    return , (ConvertTo-ObjectArray $collapsed)
}

function Test-IsNearCrashTime {
    param(
        [datetime]$Time,
        [datetime[]]$AnchorTimes,
        [double]$BeforeHours,
        [double]$AfterHours
    )
    if (-not $AnchorTimes -or @($AnchorTimes).Count -eq 0) { return $false }
    foreach ($a in $AnchorTimes) {
        if ($Time -ge $a.AddHours(-$BeforeHours) -and $Time -le $a.AddHours($AfterHours)) {
            return $true
        }
    }
    return $false
}

function Select-ItemsNearCrashTimes {
    param(
        $Items,
        [datetime[]]$AnchorTimes,
        [double]$BeforeHours,
        [double]$AfterHours,
        [string]$TimeProperty = 'TimeCreated',
        [scriptblock]$ExtraInclude = $null
    )

    $list = Get-Array $Items
    if ($list.Count -eq 0) { return , [object[]]@() }
    if (-not $AnchorTimes -or @(Get-Array $AnchorTimes).Count -eq 0) { return , [object[]]@() }

    $out = New-Object System.Collections.Generic.List[object]
    foreach ($item in $list) {
        $t = $null
        try { $t = [datetime]($item.$TimeProperty) } catch { }
        $near = ($null -ne $t -and (Test-IsNearCrashTime -Time $t -AnchorTimes $AnchorTimes -BeforeHours $BeforeHours -AfterHours $AfterHours))
        $extra = $false
        if ($ExtraInclude) {
            try { $extra = [bool](& $ExtraInclude $item) } catch { $extra = $false }
        }
        if ($near -or $extra) { [void]$out.Add($item) }
    }
    return , (ConvertTo-ObjectArray $out)
}

function Test-IsNoisyChangeDetail {
    param($Change)
    $detail = "$($Change.ChangeType) $($Change.Detail)"
    if ($detail -match '(?i)VolumeSnapshot|volsnap\.inf|HarddiskVolumeSnapshot') { return $true }
    if ($detail -match '(?i)Package KB777778|FoD-en-US was successfully changed to the Staged state') { return $true }
    return $false
}

function Get-ReportRootDirectory {
    # Elevated sessions often resolve Desktop to C:\Users\Default\Desktop - prefer the interactive user's Desktop
    $candidates = New-Object System.Collections.Generic.List[string]
    try {
        $explorer = Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction SilentlyContinue |
            Sort-Object CreationDate | Select-Object -First 1
        if ($explorer) {
            $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner -ErrorAction SilentlyContinue
            if ($owner -and $owner.User -and $owner.User -notin @('Default', 'DefaultUser', 'Public')) {
                [void]$candidates.Add((Join-Path (Join-Path 'C:\Users' $owner.User) 'Desktop'))
            }
        }
    }
    catch { }

    if ($env:USERPROFILE -and $env:USERNAME -notin @('SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE', 'DefaultAccount')) {
        [void]$candidates.Add((Join-Path $env:USERPROFILE 'Desktop'))
    }
    [void]$candidates.Add([Environment]::GetFolderPath('CommonDesktopDirectory'))
    [void]$candidates.Add([Environment]::GetFolderPath('Desktop'))
    [void]$candidates.Add((Join-Path $env:PUBLIC 'Desktop'))
    [void]$candidates.Add($env:TEMP)

    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $env:TEMP
}

function Convert-BugcheckToHex {
    param($Value)
    # Stop codes are 32-bit. Use Convert-BugcheckParamToHex for bugcheck parameters (often 64-bit pointers).
    if ($null -eq $Value -or $Value -eq '') { return $null }
    $s = ([string]$Value).Trim()
    if ($s -match '[\\/]' -or $s -match '\.dmp$' -or $s -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-') { return $null }
    try {
        if ($s -match '^0x') {
            $hex = $s.Substring(2)
            if ($hex.Length -gt 8) { $hex = $hex.Substring($hex.Length - 8) } # take low 32 bits if wider
            return ('0x{0:X8}' -f [Convert]::ToUInt32($hex, 16))
        }
        if ($s -match '^\d+$') { return ('0x{0:X8}' -f [uint32]$s) }
        if ($s -match '^[0-9A-Fa-f]+$') {
            $hex = $s
            if ($hex.Length -gt 8) { $hex = $hex.Substring($hex.Length - 8) }
            return ('0x{0:X8}' -f [Convert]::ToUInt32($hex, 16))
        }
        return $null
    }
    catch {
        if ($s -match '0x([0-9A-Fa-f]+)') {
            try {
                $hex = $Matches[1]
                if ($hex.Length -gt 8) { $hex = $hex.Substring($hex.Length - 8) }
                return ('0x{0:X8}' -f [Convert]::ToUInt32($hex, 16))
            }
            catch { return $null }
        }
        return $null
    }
}

function Convert-BugcheckParamToHex {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    $s = ([string]$Value).Trim()
    if ($s -match '[\\/]' -or $s -match '\.dmp$' -or $s -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-') { return $null }
    if ($s -match '^0[xX]([0-9A-Fa-f]+)$') { return '0x' + $Matches[1].ToUpperInvariant() }
    if ($s -match '^[0-9A-Fa-f]+$') { return '0x' + $s.ToUpperInvariant() }
    if ($s -match '^\d+$') {
        try { return ('0x{0:X}' -f [uint64]$s) } catch { return $null }
    }
    return $null
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

function Get-SafeWinEvent {
    param([hashtable]$FilterHashtable, [int]$MaxEvents = 25)
    try {
        return @(Get-WinEvent -FilterHashtable $FilterHashtable -MaxEvents $MaxEvents -ErrorAction Stop)
    }
    catch {
        return @()
    }
}

function Get-BugcheckCatalog {
    return @{
        '0x0000000A' = @{ Name = 'IRQL_NOT_LESS_OR_EQUAL'; Category = 'Driver'; Likely = 'A kernel driver accessed paged memory at too high an IRQL (often network, storage, antivirus, or filter drivers).'; Actions = @('Update or roll back recently installed drivers (NIC, storage, GPU, AV/EDR).', 'Boot into Safe Mode and uninstall the newest driver/security agent if crashes started after a change.') }
        '0x0000001A' = @{ Name = 'MEMORY_MANAGEMENT'; Category = 'Memory / Driver'; Likely = 'Memory manager detected corruption - bad RAM, faulty driver, or disk paging issues.'; Actions = @('Run Windows Memory Diagnostic or memtest86 overnight.', 'Reseat RAM / test sticks one at a time.', 'Check storage health and update chipset/storage drivers.') }
        '0x0000001E' = @{ Name = 'KMODE_EXCEPTION_NOT_HANDLED'; Category = 'Driver'; Likely = 'A kernel-mode driver threw an unhandled exception.'; Actions = @('Identify the faulting module from dump analysis if available.', 'Update GPU, chipset, and any recently installed kernel drivers.') }
        '0x0000003B' = @{ Name = 'SYSTEM_SERVICE_EXCEPTION'; Category = 'Driver / Graphics'; Likely = 'Exception while transitioning to kernel mode - frequently graphics or 3rd-party drivers.'; Actions = @('Clean-install GPU drivers (DDU in Safe Mode if needed).', 'Update Windows and chipset drivers.') }
        '0x0000004E' = @{ Name = 'PFN_LIST_CORRUPT'; Category = 'Memory / Driver'; Likely = 'Page Frame Number list corruption - often bad RAM or a driver corrupting memory.'; Actions = @('Run memory diagnostics; disable XMP/DOCP temporarily.', 'Update or remove recently installed filter drivers.') }
        '0x00000050' = @{ Name = 'PAGE_FAULT_IN_NONPAGED_AREA'; Category = 'Memory / Driver / Disk'; Likely = 'Invalid system memory reference - bad RAM, corrupt driver, or failing storage.'; Actions = @('Run memory diagnostics.', 'Check disk health (chkdsk / SMART).', 'Update or remove recently added drivers.') }
        '0x0000007A' = @{ Name = 'KERNEL_DATA_INPAGE_ERROR'; Category = 'Storage'; Likely = 'Windows could not read kernel data from disk/pagefile - failing drive, cable, controller, or bad RAM.'; Actions = @('Check SMART / manufacturer disk tools.', 'Run chkdsk /f /r after backing up data.') }
        '0x0000007E' = @{ Name = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED'; Category = 'Driver'; Likely = 'A system thread crashed in a driver.'; Actions = @('Update the driver named in dump analysis.', 'Check Device Manager for problem devices near crash times.') }
        '0x0000009F' = @{ Name = 'DRIVER_POWER_STATE_FAILURE'; Category = 'Power / Driver'; Likely = 'A driver failed to complete a power IRP in time (sleep/hibernate/resume).'; Actions = @('Update NIC, USB, GPU, and storage drivers.', 'Disable Fast Startup and test sleep/hibernate.') }
        '0x000000C2' = @{ Name = 'BAD_POOL_CALLER'; Category = 'Driver'; Likely = 'A driver made an invalid pool request.'; Actions = @('Update/remove recently installed filter drivers (AV, backup, encryption, VPN).') }
        '0x000000D1' = @{ Name = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL'; Category = 'Driver'; Likely = 'Driver IRQL violation - classic buggy 3rd-party driver pattern.'; Actions = @('Update NIC/Wi-Fi, storage, and security product drivers.', 'Uninstall newest kernel-mode software installed before the crash wave.') }
        '0x000000EF' = @{ Name = 'CRITICAL_PROCESS_DIED'; Category = 'System / Corruption / Driver'; Likely = 'A critical Windows process terminated unexpectedly.'; Actions = @('Run sfc /scannow and DISM RestoreHealth.', 'Check for disk/memory issues and recent software installs.') }
        '0x000000F4' = @{ Name = 'CRITICAL_OBJECT_TERMINATION'; Category = 'System / Corruption'; Likely = 'A critical system process/thread was terminated.'; Actions = @('Run SFC/DISM; check disk health.') }
        '0x00000109' = @{ Name = 'CRITICAL_STRUCTURE_CORRUPTION'; Category = 'Hardware / Rootkit / Memory'; Likely = 'Kernel detected corruption of critical structures.'; Actions = @('Run memory diagnostics; update BIOS/firmware.', 'Scan with an offline antimalware tool.') }
        '0x0000010E' = @{ Name = 'VIDEO_MEMORY_MANAGEMENT_INTERNAL'; Category = 'Graphics'; Likely = 'Graphics memory manager hit an internal error.'; Actions = @('Clean-install GPU drivers.', 'Check GPU thermals and power.') }
        '0x00000124' = @{ Name = 'WHEA_UNCORRECTABLE_ERROR'; Category = 'Hardware'; Likely = 'Hardware reported an uncorrectable error (CPU, RAM, PCIe, overheating, or power).'; Actions = @('Review WHEA-Logger events in this report.', 'Check temperatures, PSU, RAM seating, and BIOS/firmware updates.') }
        '0x00000133' = @{ Name = 'DPC_WATCHDOG_VIOLATION'; Category = 'Driver / Storage'; Likely = 'A DPC ran too long - often storage, USB, network, or filter drivers stalling.'; Actions = @('Update storage controller / NVMe / SATA drivers.', 'Check disk health and free space.') }
        '0x00000139' = @{ Name = 'KERNEL_SECURITY_CHECK_FAILURE'; Category = 'Memory Corruption / Driver'; Likely = 'Kernel detected corruption (stack cookie / CFG) - often a buggy driver or bad memory.'; Actions = @('Update drivers and run memory diagnostics.', 'Uninstall recent AV/EDR or VPN clients to test.') }
        '0x0000013A' = @{ Name = 'KERNEL_MODE_HEAP_CORRUPTION'; Category = 'Memory Corruption / Driver'; Likely = 'Kernel heap corruption - typically a buggy driver writing past a buffer.'; Actions = @('Identify the faulting module from dump analysis.', 'Update/remove recently installed kernel drivers and filter drivers.') }
        '0x00000154' = @{ Name = 'UNEXPECTED_STORE_EXCEPTION'; Category = 'Storage / Memory'; Likely = 'Storage stack or memory compression hit an unexpected exception.'; Actions = @('Update NVMe/SATA/chipset drivers and disk firmware.', 'Check SMART health; run memory diagnostics.') }
        '0x00000187' = @{ Name = 'VIDEO_ENGINE_TIMEOUT_DETECTED'; Category = 'Graphics'; Likely = 'GPU engine hung/timeout.'; Actions = @('Clean-install GPU drivers; check GPU thermals and PSU capacity.') }
        '0x0000007F' = @{ Name = 'UNEXPECTED_KERNEL_MODE_TRAP'; Category = 'Hardware / Driver'; Likely = 'CPU generated a trap Windows could not handle - often bad RAM, overheating, or driver.'; Actions = @('Test RAM; check CPU thermals; reset BIOS defaults.') }
        '0x000000CA' = @{ Name = 'PNP_DETECTED_FATAL_ERROR'; Category = 'Plug and Play / Driver'; Likely = 'PnP manager hit a fatal inconsistency - often a buggy device driver.'; Actions = @('Update or remove recently added hardware/drivers.') }
    }
}

function Resolve-BugcheckInfo {
    param([string]$CodeHex)
    $catalog = Get-BugcheckCatalog
    if (-not $CodeHex) {
        return @{
            Code = $null; Name = 'Unknown'; Category = 'Unknown'; Known = $false
            Likely = 'Bugcheck code could not be parsed from the event.'
            Actions = @('Open the minidump in WinDbg (!analyze -v) or share dumps with support.')
        }
    }
    $normalized = $CodeHex.ToUpperInvariant()
    if ($normalized -notmatch '^0X') { $normalized = '0x' + $normalized.TrimStart('0X') }
    try {
        $n = [Convert]::ToUInt32($normalized.Substring(2), 16)
        $normalized = '0x{0:X8}' -f $n
    }
    catch { }

    if ($catalog.ContainsKey($normalized)) {
        $info = @{} + $catalog[$normalized]
        $info['Known'] = $true
        $info['Code'] = $normalized
        return $info
    }

    return @{
        Code = $normalized; Name = 'Unrecognized / less common stop code'; Category = 'Needs dump analysis'; Known = $false
        Likely = "Stop code $normalized is not in the built-in catalog. The dump file is the best next step."
        Actions = @('Open the newest minidump in WinDbg Preview and run: !analyze -v', 'Search Microsoft Learn for the stop code hex value.')
    }
}

function Get-EventPropertyMap {
    param($Event)
    $map = @{}
    try {
        $xml = [xml]$Event.ToXml()
        foreach ($node in $xml.Event.EventData.Data) {
            if ($node.Name) { $map[$node.Name] = $node.'#text' }
        }
    }
    catch { }
    return $map
}

function Parse-BugcheckFromEvent {
    param($Event)
    $props = Get-EventPropertyMap -Event $Event
    $code = $null; $p1 = $null; $p2 = $null; $p3 = $null; $p4 = $null; $dump = $null; $reportId = $null

    if ($props.ContainsKey('BugcheckCode')) { $code = Convert-BugcheckToHex $props['BugcheckCode'] }
    elseif ($props.ContainsKey('BugCheckCode')) { $code = Convert-BugcheckToHex $props['BugCheckCode'] }

    # True BugCheck provider parameters (not WER param1/param2 which are code/path/report-id)
    foreach ($key in @('BugcheckParameter1', 'BugCheckParameter1')) { if ($props.ContainsKey($key)) { $p1 = Convert-BugcheckParamToHex $props[$key]; break } }
    foreach ($key in @('BugcheckParameter2', 'BugCheckParameter2')) { if ($props.ContainsKey($key)) { $p2 = Convert-BugcheckParamToHex $props[$key]; break } }
    foreach ($key in @('BugcheckParameter3', 'BugCheckParameter3')) { if ($props.ContainsKey($key)) { $p3 = Convert-BugcheckParamToHex $props[$key]; break } }
    foreach ($key in @('BugcheckParameter4', 'BugCheckParameter4')) { if ($props.ContainsKey($key)) { $p4 = Convert-BugcheckParamToHex $props[$key]; break } }

    foreach ($key in @('DumpFile', 'DumpPath')) {
        if ($props.ContainsKey($key) -and "$($props[$key])" -match '\.dmp') { $dump = "$($props[$key])".Trim(); break }
    }

    # WER SystemErrorReporting Event 1001: param1=stop code, param2=dump path, param3=report id
    foreach ($key in @('param1', 'Param1')) {
        if (-not $code -and $props.ContainsKey($key)) { $code = Convert-BugcheckToHex $props[$key] }
    }
    foreach ($key in @('param2', 'Param2')) {
        if (-not $dump -and $props.ContainsKey($key) -and "$($props[$key])" -match '\.dmp') { $dump = "$($props[$key])".Trim() }
    }
    foreach ($key in @('param3', 'Param3')) {
        if ($props.ContainsKey($key) -and "$($props[$key])" -match '^[0-9a-fA-F-]{16,}$') { $reportId = "$($props[$key])".Trim() }
    }

    # Prefer authoritative values from the message text when present
    if ($Event.Message) {
        if ($Event.Message -match '(?i)bugcheck was:\s*(0x[0-9A-Fa-f]+)\s*\(([^)]*)\)') {
            $code = Convert-BugcheckToHex $Matches[1]
            $parts = @($Matches[2] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if ($parts.Count -ge 1) { $p1 = Convert-BugcheckParamToHex $parts[0] }
            if ($parts.Count -ge 2) { $p2 = Convert-BugcheckParamToHex $parts[1] }
            if ($parts.Count -ge 3) { $p3 = Convert-BugcheckParamToHex $parts[2] }
            if ($parts.Count -ge 4) { $p4 = Convert-BugcheckParamToHex $parts[3] }
        }
        elseif (-not $code -and $Event.Message -match '(?i)bugcheck was:\s*(0x[0-9A-Fa-f]+)') {
            $code = Convert-BugcheckToHex $Matches[1]
        }

        if (-not $dump -and $Event.Message -match '(?i)(?:Dump file:|dump was saved in:)\s*(.+?\.dmp)') {
            $dump = $Matches[1].Trim().TrimEnd('.', ',', ';')
        }
        if (-not $reportId -and $Event.Message -match '(?i)Report Id:\s*([0-9a-fA-F-]{16,})') {
            $reportId = $Matches[1].Trim()
        }
    }

    $info = Resolve-BugcheckInfo -CodeHex $code
    return [PSCustomObject]@{
        TimeCreated        = $Event.TimeCreated
        Computer           = $Event.MachineName
        BugcheckCode       = $code
        BugcheckName       = $info.Name
        Category           = $info.Category
        Parameter1         = $p1
        Parameter2         = $p2
        Parameter3         = $p3
        Parameter4         = $p4
        DumpFile           = $dump
        ReportId           = $reportId
        LikelyCause        = $info.Likely
        RecommendedActions = ($info.Actions -join ' | ')
        Message            = $Event.Message
        KnownCode          = [bool]$info.Known
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
        ComputerName = $env:COMPUTERNAME
        UserName     = $env:USERNAME
        Domain       = $env:USERDOMAIN
        IsAdmin      = Test-IsAdministrator
        OSCaption    = Get-NotePropertyValue $os Caption
        OSVersion    = Get-NotePropertyValue $os Version
        OSBuild      = Get-NotePropertyValue $os BuildNumber
        InstallDate  = Get-NotePropertyValue $os InstallDate
        LastBoot     = Get-NotePropertyValue $os LastBootUpTime
        UptimeDays   = if ($uptime) { [math]::Round($uptime.TotalDays, 2) } else { $null }
        Manufacturer = Get-NotePropertyValue $cs Manufacturer
        Model        = Get-NotePropertyValue $cs Model
        BIOSVersion  = Get-NotePropertyValue $bios SMBIOSBIOSVersion
        BIOSDate     = Get-NotePropertyValue $bios ReleaseDate
        Processor    = Get-NotePropertyValue $cpu Name
        MemoryGB     = $memGB
        SystemType   = Get-NotePropertyValue $cs SystemType
        CollectedAt  = Get-Date
    }
}

function Get-CrashDumpConfiguration {
    $cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue
    $map = @{ 0 = 'None'; 1 = 'Complete memory dump'; 2 = 'Kernel memory dump'; 3 = 'Small memory dump (minidump)'; 7 = 'Automatic memory dump' }
    $rawEnabled = Get-NotePropertyValue $cc CrashDumpEnabled
    $enabled = if ($null -ne $rawEnabled -and "$rawEnabled" -ne '') { try { [int]$rawEnabled } catch { $null } } else { $null }
    [PSCustomObject]@{
        CrashDumpEnabled     = $enabled
        CrashDumpType        = if ($null -ne $enabled -and $map.ContainsKey($enabled)) { $map[$enabled] } else { 'Unknown / unavailable' }
        MinidumpDir          = Get-NotePropertyValue $cc MinidumpDir -Default 'C:\Windows\Minidump'
        DumpFile             = Get-NotePropertyValue $cc DumpFile -Default 'C:\Windows\MEMORY.DMP'
        LogEvent             = Get-NotePropertyValue $cc LogEvent
        AutoReboot           = Get-NotePropertyValue $cc AutoReboot
        Overwrite            = Get-NotePropertyValue $cc Overwrite
        AlwaysKeepMemoryDump = Get-NotePropertyValue $cc AlwaysKeepMemoryDump
    }
}

function Get-DumpInventory {
    param(
        [string[]]$ExtraPaths = @(),
        [string]$MinidumpDir = 'C:\Windows\Minidump'
    )

    $files = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    function Add-DumpFile {
        param([System.IO.FileInfo]$File)
        if (-not $File -or -not $File.FullName) { return }
        $key = $File.FullName.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        [void]$files.Add([PSCustomObject]@{
            FullName      = $File.FullName
            Name          = $File.Name
            LengthMB      = [math]::Round($File.Length / 1MB, 2)
            LastWriteTime = $File.LastWriteTime
            AgeDays       = [math]::Round(((Get-Date) - $File.LastWriteTime).TotalDays, 1)
            IsMinidump    = ($File.DirectoryName -match 'Minidump|LiveKernelReports|WER' -or $File.Length -lt 256MB)
            Exists        = $true
        })
    }

    $patterns = @(
        (Join-Path $MinidumpDir '*.dmp'),
        'C:\Windows\Minidump\*.dmp',
        'C:\Windows\MEMORY.DMP',
        'C:\Windows\LiveKernelReports\*.dmp',
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive\*\*.dmp'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive\*\*.mdmp'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue\*\*.dmp'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue\*\*.mdmp')
    )

    foreach ($pattern in $patterns) {
        Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object { Add-DumpFile -File $_ }
    }

    foreach ($path in $ExtraPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $clean = $path.Trim().TrimEnd('.', ',', ';', '"')
        if (Test-Path -LiteralPath $clean) {
            Add-DumpFile -File (Get-Item -LiteralPath $clean -ErrorAction SilentlyContinue)
        }
        else {
            # Still record the reported path so the report shows it was expected but missing
            $key = $clean.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                [void]$files.Add([PSCustomObject]@{
                    FullName      = $clean
                    Name          = Split-Path $clean -Leaf
                    LengthMB      = $null
                    LastWriteTime = $null
                    AgeDays       = $null
                    IsMinidump    = ($clean -match 'Minidump|\.dmp$')
                    Exists        = $false
                })
            }
        }
    }

    return , @($files | Sort-Object @{ Expression = 'Exists'; Descending = $true }, LastWriteTime -Descending)
}

function Get-BugcheckEvents {
    param([datetime]$Start, [int]$MaxEvents)
    $events = Get-SafeWinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; StartTime = $Start } -MaxEvents $MaxEvents
    $parsed = New-Object System.Collections.Generic.List[object]
    foreach ($e in $events) {
        $isBugcheck = ($e.ProviderName -match 'BugCheck|Windows Error Reporting|Microsoft-Windows-WER-SystemErrorReporting|Save Dump') -or
            ($e.Message -match 'bugcheck|blue screen|The computer has rebooted from a bugcheck')
        if ($isBugcheck) { [void]$parsed.Add((Parse-BugcheckFromEvent -Event $e)) }
    }
    if ($parsed.Count -eq 0) {
        foreach ($e in $events) {
            if ($e.Message -match 'bugcheck|0x[0-9A-Fa-f]{8}') { [void]$parsed.Add((Parse-BugcheckFromEvent -Event $e)) }
        }
    }
    return , @($parsed | Sort-Object TimeCreated -Descending)
}

function Get-RelatedCrashEvents {
    param([datetime]$Start, [int]$MaxEvents)
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($e in (Get-SafeWinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $Start } -MaxEvents $MaxEvents)) {
        [void]$rows.Add([PSCustomObject]@{ TimeCreated = $e.TimeCreated; Type = 'Kernel-Power 41 (unexpected shutdown / power loss)'; Provider = $e.ProviderName; Id = $e.Id; Summary = 'System rebooted without clean shutdown. Can be BSOD, hard power loss, or forced reset.'; Message = Get-ShortText $e.Message })
    }
    foreach ($e in (Get-SafeWinEvent -FilterHashtable @{ LogName = 'System'; Id = 6008; StartTime = $Start } -MaxEvents $MaxEvents)) {
        [void]$rows.Add([PSCustomObject]@{ TimeCreated = $e.TimeCreated; Type = 'Unexpected Shutdown 6008'; Provider = $e.ProviderName; Id = $e.Id; Summary = 'Previous shutdown was unexpected.'; Message = Get-ShortText $e.Message })
    }
    foreach ($e in (Get-SafeWinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $Start } -MaxEvents $MaxEvents)) {
        if ($e.LevelDisplayName -in @('Error', 'Critical', 'Warning') -or $e.Id -in 1, 17, 18, 19, 47) {
            [void]$rows.Add([PSCustomObject]@{ TimeCreated = $e.TimeCreated; Type = "WHEA Hardware Error (Event $($e.Id))"; Provider = $e.ProviderName; Id = $e.Id; Summary = 'Hardware error reported by WHEA - strong hardware signal when near BSOD times.'; Message = Get-ShortText $e.Message })
        }
    }
    foreach ($e in (Get-SafeWinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'disk'; StartTime = $Start } -MaxEvents ([Math]::Min(15, $MaxEvents)) | Where-Object { $_.LevelDisplayName -in @('Error', 'Warning') })) {
        [void]$rows.Add([PSCustomObject]@{ TimeCreated = $e.TimeCreated; Type = "Disk Error/Warning (Event $($e.Id))"; Provider = $e.ProviderName; Id = $e.Id; Summary = 'Storage subsystem reported an error near the analysis window.'; Message = Get-ShortText $e.Message })
    }
    return , @($rows | Sort-Object TimeCreated -Descending)
}

function Get-RecentDriverAndSoftwareChanges {
    param([datetime]$Start)
    $changes = New-Object System.Collections.Generic.List[object]

    foreach ($e in (Get-SafeWinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Configuration'; StartTime = $Start } -MaxEvents 40 | Where-Object { $_.Id -in 400, 410, 430, 440 })) {
        [void]$changes.Add([PSCustomObject]@{ TimeCreated = $e.TimeCreated; ChangeType = 'Driver / Device (Kernel-PnP)'; Detail = Get-ShortText $e.Message -Max 220 })
    }
    foreach ($e in (Get-SafeWinEvent -FilterHashtable @{ LogName = 'Setup'; StartTime = $Start } -MaxEvents 20)) {
        [void]$changes.Add([PSCustomObject]@{ TimeCreated = $e.TimeCreated; ChangeType = "Setup Log Event $($e.Id)"; Detail = Get-ShortText $e.Message -Max 220 })
    }
    try {
        Get-HotFix -ErrorAction SilentlyContinue | Where-Object { $_.InstalledOn -and $_.InstalledOn -ge $Start } | Sort-Object InstalledOn -Descending | Select-Object -First 15 | ForEach-Object {
            [void]$changes.Add([PSCustomObject]@{ TimeCreated = $_.InstalledOn; ChangeType = "Hotfix $($_.HotFixID)"; Detail = "$($_.Description) by $($_.InstalledBy)" })
        }
    }
    catch { }
    try {
        Get-ChildItem 'C:\Windows\System32\drivers\*.sys' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $Start } | Sort-Object LastWriteTime -Descending | Select-Object -First 20 | ForEach-Object {
            [void]$changes.Add([PSCustomObject]@{ TimeCreated = $_.LastWriteTime; ChangeType = 'Driver file modified (System32\drivers)'; Detail = "$($_.Name) ($([math]::Round($_.Length/1KB)) KB)" })
        }
    }
    catch { }
    return , @($changes | Sort-Object TimeCreated -Descending)
}
#endregion Collection

#region WinDbg / cdb dump analysis
function Get-WingetExecutable {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    $resolved = Resolve-Path 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe\winget.exe' -ErrorAction SilentlyContinue
    if ($resolved) { return @($resolved)[-1].Path }
    return $null
}

function Find-DumpDebugger {
    # Prefer cdb for headless automation; WinDbg Preview (WinDbgX) is also supported.
    $cdbCandidates = @(
        'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe',
        'C:\Program Files\Windows Kits\10\Debuggers\x64\cdb.exe',
        'C:\Program Files (x86)\Windows Kits\10\Debuggers\x86\cdb.exe'
    )
    foreach ($p in $cdbCandidates) {
        if (Test-Path -LiteralPath $p) {
            return [PSCustomObject]@{ Path = $p; Kind = 'cdb'; Source = 'Windows Kits' }
        }
    }
    $cdbCmd = Get-Command cdb.exe -ErrorAction SilentlyContinue
    if ($cdbCmd -and $cdbCmd.Source -and (Test-Path -LiteralPath $cdbCmd.Source)) {
        return [PSCustomObject]@{ Path = $cdbCmd.Source; Kind = 'cdb'; Source = 'PATH' }
    }

    $windbgCandidates = New-Object System.Collections.Generic.List[string]
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\WinDbgX.exe'
    if (Test-Path -LiteralPath $alias) { [void]$windbgCandidates.Add($alias) }

    $winDbgCmd = Get-Command WinDbgX.exe -ErrorAction SilentlyContinue
    if ($winDbgCmd -and $winDbgCmd.Source) { [void]$windbgCandidates.Add($winDbgCmd.Source) }

    try {
        Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinDbg') -Filter 'DbgX.Shell.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 3 | ForEach-Object { [void]$windbgCandidates.Add($_.FullName) }
    }
    catch { }

    try {
        Get-ChildItem 'C:\Program Files\WindowsApps\Microsoft.WinDbg*' -Filter 'DbgX.Shell.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 3 | ForEach-Object { [void]$windbgCandidates.Add($_.FullName) }
    }
    catch { }

    foreach ($p in $windbgCandidates) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            return [PSCustomObject]@{ Path = $p; Kind = 'windbgx'; Source = 'WinDbg Preview' }
        }
    }

    return $null
}

function Invoke-WingetInstall {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )

    $winget = Get-WingetExecutable
    if (-not $winget) {
        Write-Info 'winget.exe not found - cannot auto-install debugger.' 'Yellow'
        return $false
    }

    Write-Info "Installing $DisplayName via winget ($PackageId)..." 'Yellow'
    try {
        $args = @(
            'install', '--id', $PackageId,
            '-e', '--silent',
            '--accept-package-agreements', '--accept-source-agreements',
            '--disable-interactivity'
        )
        $p = Start-Process -FilePath $winget -ArgumentList $args -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        Write-Info "winget exit code for ${PackageId}: $($p.ExitCode)" 'Gray'
        # 0 = installed, -1978335189 / other success-ish codes may mean already installed
        return ($p.ExitCode -eq 0 -or $p.ExitCode -eq -1978335189 -or $p.ExitCode -eq -1978335135)
    }
    catch {
        Write-Info "winget install failed for ${PackageId}: $($_.Exception.Message)" 'Yellow'
        return $false
    }
}

function Install-DumpDebugger {
    param([switch]$Force)

    $existing = Find-DumpDebugger
    if ($existing -and -not $Force) { return $existing }

    Write-Info 'No usable debugger found (or -InstallDebuggers forced). Attempting winget install...' 'Yellow'

    # 1) WinDbg Preview - preferred shareable path
    [void](Invoke-WingetInstall -PackageId 'Microsoft.WinDbg' -DisplayName 'WinDbg Preview')
    Start-Sleep -Seconds 2
    $found = Find-DumpDebugger
    if ($found) {
        Write-Info "Debugger ready after WinDbg install: $($found.Path)" 'Green'
        return $found
    }

    # 2) Fallback: Windows SDK Debugging Tools (cdb.exe) - silent SDK feature install is incomplete
    #    via winget alone on some machines, but often drops cdb under Windows Kits.
    Write-Info 'WinDbg not detected after install; trying Windows SDK (for cdb.exe)...' 'Yellow'
    foreach ($sdkId in @(
            'Microsoft.WindowsSDK.10.0.26100',
            'Microsoft.WindowsSDK.10.0.22621',
            'Microsoft.WindowsSDK.10.0.19041'
        )) {
        [void](Invoke-WingetInstall -PackageId $sdkId -DisplayName "Windows SDK ($sdkId)")
        Start-Sleep -Seconds 2
        $found = Find-DumpDebugger
        if ($found) {
            Write-Info "Debugger ready after SDK install: $($found.Path)" 'Green'
            return $found
        }
    }

    Write-Info 'Automatic debugger install did not yield cdb.exe or WinDbgX.exe.' 'Yellow'
    Write-Info 'Install WinDbg from winget: winget install Microsoft.WinDbg' 'Gray'
    return $null
}

function Get-BugcheckCodeFromDumpPath {
    param([string]$DumpPath)
    if ([string]::IsNullOrWhiteSpace($DumpPath)) { return $null }
    # WER folders look like: Kernel_124_... or Kernel_1b0_... or Kernel_7e_...
    if ($DumpPath -match '(?i)[/\\]Kernel_([0-9a-fA-F]+)[_/\\]') {
        try {
            return ('0x{0:X8}' -f [Convert]::ToUInt32($Matches[1], 16))
        }
        catch { }
    }
    if ($DumpPath -match '(?i)[/\\](WHEA|WATCHDOG|BUGCHECK|LIVEKERNEL)-') {
        # filename hint only; caller may still lack a code
        return $null
    }
    return $null
}

function Test-IsLiveKernelDumpName {
    param([string]$Name, [string]$FullName = '')
    $n = "$Name $FullName"
    return [bool]($n -match '(?i)(^|[\\/])(WHEA|WATCHDOG)-' -or $n -match '(?i)\\LiveKernelReports\\' -or $n -match '(?i)LKD_')
}

function Get-CleanFaultingModule {
    param(
        [string]$Module,
        [string]$Driver,
        [string]$ProbablyCausedBy,
        [string]$FailureBucket
    )

    $candidates = @($Module, $Driver, $ProbablyCausedBy) | Where-Object { $_ -and $_.Trim() }
    $junk = @(
        'memory_corruption', 'MEMORY_CORRUPTION', 'Analysis', 'Unknown', 'nt', 'ntoskrnl',
        'ntkrnlmp.exe', 'ntoskrnl.exe', 'Unknown_Module', 'followup'
    )

    foreach ($c in $candidates) {
        $clean = ($c -replace '\s+\(.*\)$', '').Trim()
        # "memory_corruption (nt!...)" -> skip
        if ($clean -match '(?i)^memory_corruption') { continue }
        if ($clean -match '(?i)^unknown') { continue }
        if ($junk -contains $clean) { continue }
        if ($clean -match '(?i)\.(sys|dll|exe)$') { return $clean }
        if ($clean -match '!' ) {
            # nt!Wheap... is not a 3rd-party culprit; keep only if non-nt
            if ($clean -match '(?i)^(nt|ntoskrnl|hal)!') { continue }
            return $clean
        }
        if ($clean -and $clean.Length -lt 64) { return $clean }
    }

    if ($FailureBucket -match '(?i)LKD_MEMORY_CORRUPTION') { return $null }
    if ($FailureBucket -match '(?i)WHEA') { return $null }
    return $null
}

function Parse-AnalyzeOutput {
    param(
        [string]$Output,
        [string]$DumpPath = ''
    )

    $parsed = [ordered]@{
        BugcheckName     = 'Unknown'
        BugcheckCode     = 'Unknown'
        ExceptionCode    = ''
        FaultingModule   = ''
        FaultingDriver   = ''
        FailureBucket    = ''
        ProcessName      = ''
        StackSummary     = ''
        SymbolName       = ''
        ProbablyCausedBy = ''
        DumpKind         = 'Unknown'
        IsLiveKernelDump = $false
    }

    if ([string]::IsNullOrWhiteSpace($Output)) { return [PSCustomObject]$parsed }

    $isLkd = Test-IsLiveKernelDumpName -Name (Split-Path $DumpPath -Leaf) -FullName $DumpPath
    if (-not $isLkd) {
        $isLkd = ($Output -match '(?i)Live Kernel Dump' -or $Output -match '(?i)LKD_' -or $Output -match '(?i)WheapReportLiveDump')
    }
    $parsed.IsLiveKernelDump = [bool]$isLkd
    if ($DumpPath -match '(?i)WHEA-') { $parsed.DumpKind = 'WHEA Live Kernel Dump' }
    elseif ($DumpPath -match '(?i)WATCHDOG-') { $parsed.DumpKind = 'Watchdog Live Kernel Dump' }
    elseif ($isLkd) { $parsed.DumpKind = 'Live Kernel Dump' }
    else { $parsed.DumpKind = 'Bugcheck / minidump' }

    # Prefer explicit fields; do NOT match "BugCheck Analysis" headings
    if ($Output -match '(?im)^BUGCHECK_CODE:\s*([0-9a-fA-Fx]+)') {
        $parsed.BugcheckCode = Convert-BugcheckToHex $Matches[1]
    }
    elseif ($Output -match '(?i)Bugcheck code\s*[:=]?\s*(0x[0-9a-fA-F]+|\w+)') {
        $parsed.BugcheckCode = Convert-BugcheckToHex $Matches[1]
    }

    if ($Output -match '(?im)^BUGCHECK_STR:\s*([A-Z0-9_]+)') {
        $parsed.BugcheckName = $Matches[1]
    }
    elseif ($Output -match '(?i)BugCheck\s+([A-Z0-9_]+)\s*\(') {
        $parsed.BugcheckName = $Matches[1]
    }
    elseif ($Output -match '(?i)BugCheck\s+([A-Z0-9_]{6,})\b' -and $Matches[1] -ne 'Analysis') {
        $parsed.BugcheckName = $Matches[1]
    }

    # WER path Kernel_124_... / Kernel_7e_...
    if (($parsed.BugcheckCode -eq 'Unknown' -or -not $parsed.BugcheckCode) -and $DumpPath) {
        $fromPath = Get-BugcheckCodeFromDumpPath -DumpPath $DumpPath
        if ($fromPath) { $parsed.BugcheckCode = $fromPath }
    }

    if ($parsed.BugcheckCode -and $parsed.BugcheckCode -ne 'Unknown') {
        $info = Resolve-BugcheckInfo -CodeHex $parsed.BugcheckCode
        if ($parsed.BugcheckName -eq 'Unknown' -or $parsed.BugcheckName -eq 'Analysis') {
            $parsed.BugcheckName = $info.Name
        }
    }

    if ($Output -match 'ExceptionCode:\s*(0x\w+)') { $parsed.ExceptionCode = $Matches[1] }
    if ($Output -match '(?im)^IMAGE_NAME:\s*(.+)$') { $parsed.FaultingModule = $Matches[1].Trim() }
    if ($Output -match '(?im)^MODULE_NAME:\s*(.+)$') { $parsed.FaultingDriver = $Matches[1].Trim() }
    if ($Output -match '(?im)^FAILURE_BUCKET_ID:\s*(.+)$') { $parsed.FailureBucket = $Matches[1].Trim() }
    if ($Output -match '(?im)^PROCESS_NAME:\s*(.+)$') { $parsed.ProcessName = $Matches[1].Trim() }
    if ($Output -match '(?im)^SYMBOL_NAME:\s*(.+)$') { $parsed.SymbolName = $Matches[1].Trim() }
    if ($Output -match '(?i)Probably caused by\s*:\s*(.+)$') { $parsed.ProbablyCausedBy = $Matches[1].Trim() }

    if ($Output -match '(?s)STACK_TEXT:(.*?)(?:SYMBOL_NAME:|FOLLOWUP_IP:|MODULE_NAME:|IMAGE_NAME:|FAILURE_BUCKET_ID:|$)') {
        $stackLines = $Matches[1] -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 5
        $parsed.StackSummary = ($stackLines -join ' > ').Trim()
    }

    # Replace junk IMAGE_NAME values like memory_corruption with a cleaner module if possible
    $clean = Get-CleanFaultingModule -Module $parsed.FaultingModule -Driver $parsed.FaultingDriver -ProbablyCausedBy $parsed.ProbablyCausedBy -FailureBucket $parsed.FailureBucket
    if ($clean) {
        $parsed.FaultingModule = $clean
    }
    elseif ($parsed.FaultingModule -match '(?i)^memory_corruption' -or $parsed.FaultingDriver -match '(?i)^memory_corruption') {
        $parsed.FaultingModule = ''
        $parsed.FaultingDriver = ''
    }

    return [PSCustomObject]$parsed
}

function Invoke-MinidumpAnalysis {
    param(
        [string]$DumpPath,
        $Debugger,
        [string]$LogPath,
        [int]$TimeoutSec = 300
    )

    if (-not (Test-Path -LiteralPath $DumpPath)) {
        return [PSCustomObject]@{ Success = $false; Reason = 'Dump file missing'; DumpPath = $DumpPath; Parsed = $null; LogPath = $null }
    }
    if (-not $Debugger -or -not $Debugger.Path -or -not (Test-Path -LiteralPath $Debugger.Path)) {
        return [PSCustomObject]@{ Success = $false; Reason = 'Debugger missing'; DumpPath = $DumpPath; Parsed = $null; LogPath = $null }
    }

    # Same approach as Intune Remediations/BSODDiag/Remediate.ps1:
    #   cdb -z "<dump>" -y "<symbols>" -c ".symfix;.reload;!analyze -v;q"
    # Capture stdout; do NOT use .logopen / fragile nested quoting (that can leave cdb at a prompt and hang).
    $symbolPath = 'srv*C:\Symbols*https://msdl.microsoft.com/download/symbols'
    $kind = $Debugger.Kind
    $exe = $Debugger.Path
    $exitCode = $null
    $commands = '.symfix;.reload;!analyze -v;q'

    Write-Info "Running $($kind) !analyze -v on $(Split-Path $DumpPath -Leaf) (timeout ${TimeoutSec}s)..." 'Yellow'
    Write-Info "Command: `"$exe`" -z `"$DumpPath`" -y `"$symbolPath`" -c `"$commands`"" 'Gray'

    $raw = ''
    try {
        if ($kind -eq 'cdb') {
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $exe
            $processInfo.Arguments = "-z `"$DumpPath`" -y `"$symbolPath`" -c `"$commands`""
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            [void]$process.Start()

            # Async reads avoid stdout/stderr pipe deadlocks while waiting
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()

            if (-not $process.WaitForExit($TimeoutSec * 1000)) {
                try {
                    if (-not $process.HasExited) {
                        $process.Kill()
                        [void]$process.WaitForExit(5000)
                    }
                }
                catch { }
                return [PSCustomObject]@{
                    Success  = $false
                    Reason   = "Timed out after ${TimeoutSec}s (cdb still running - often symbol download or dump I/O)"
                    DumpPath = $DumpPath
                    Parsed   = $null
                    LogPath  = $LogPath
                }
            }

            $exitCode = $process.ExitCode
            $stdout = $stdoutTask.Result
            $stderr = $stderrTask.Result
            $raw = (($stdout, $stderr) | Where-Object { $_ }) -join "`r`n"
        }
        else {
            # WinDbg Preview: keep a simple -c string; log via our own capture file if process supports it
            $argString = "-z `"$DumpPath`" -y `"$symbolPath`" -c `"$commands`""
            $p = Start-Process -FilePath $exe -ArgumentList $argString -PassThru -WindowStyle Hidden -Wait -ErrorAction Stop
            # WinDbgX often won't give us stdout; fall through to empty and report
            $exitCode = $p.ExitCode
            if (Test-Path -LiteralPath $LogPath) {
                $raw = Get-Content -LiteralPath $LogPath -Raw -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Reason = $_.Exception.Message; DumpPath = $DumpPath; Parsed = $null; LogPath = $LogPath }
    }

    if (-not [string]::IsNullOrWhiteSpace($raw) -and $LogPath) {
        try { Set-Content -LiteralPath $LogPath -Value $raw -Encoding UTF8 } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [PSCustomObject]@{ Success = $false; Reason = "$kind produced no log output"; DumpPath = $DumpPath; Parsed = $null; LogPath = $LogPath }
    }

    $parsed = Parse-AnalyzeOutput -Output $raw -DumpPath $DumpPath
    $ok = (
        $parsed.FaultingModule -or
        $parsed.FaultingDriver -or
        ($parsed.BugcheckCode -and $parsed.BugcheckCode -ne 'Unknown') -or
        $parsed.ProbablyCausedBy -or
        $parsed.FailureBucket -or
        $parsed.IsLiveKernelDump
    )

    return [PSCustomObject]@{
        Success    = [bool]$ok
        Reason     = if ($ok) { 'OK' } else { 'Parsed output but no clear faulting module/code' }
        DumpPath   = $DumpPath
        DumpName   = Split-Path $DumpPath -Leaf
        LogPath    = $LogPath
        Debugger   = "$kind : $exe"
        ExitCode   = $exitCode
        Parsed     = $parsed
        RawPreview = Get-ShortText $raw -Max 500
    }
}

function Invoke-DumpAnalysisPass {
    param(
        [array]$Dumps,
        $Debugger,
        [string]$OutputDirectory,
        [int]$MaxDumps,
        [int]$MaxSizeMB,
        [int]$TimeoutSec
    )

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $Debugger) { return @() }

    $analyzeDir = Join-Path $OutputDirectory 'windbg'
    New-Item -ItemType Directory -Path $analyzeDir -Force | Out-Null

    $candidates = @(
        $Dumps |
            Where-Object { $_ -and $_.FullName -and (Test-Path -LiteralPath $_.FullName) } |
            Where-Object { $null -ne $_.LengthMB -and $_.LengthMB -le $MaxSizeMB } |
            ForEach-Object {
                $priority = 1
                $name = $_.Name
                $full = $_.FullName
                if ($full -match '\\Minidump\\' -or $name -match '^\d{6}-\d+-') { $priority = 4 }
                elseif ($full -match '\\ReportQueue\\|\\ReportArchive\\' -and $name -notmatch '(?i)^(WHEA|WATCHDOG)-') { $priority = 3 }
                elseif ($name -match '^MEMORY\.DMP$') { $priority = 2 }
                elseif ($full -match '\\LiveKernelReports\\' -or $name -match '(?i)^(WHEA|WATCHDOG)-') { $priority = 0 }
                $_ | Add-Member -NotePropertyName AnalyzePriority -NotePropertyValue $priority -Force -PassThru
            } |
            Sort-Object @{ Expression = 'AnalyzePriority'; Descending = $true }, @{ Expression = 'IsMinidump'; Descending = $true }, LastWriteTime -Descending |
            Select-Object -First $MaxDumps
    )

    if ($candidates.Count -eq 0) {
        Write-Info "No dumps under ${MaxSizeMB} MB available to analyze." 'Yellow'
        return , @()
    }

    $i = 0
    foreach ($d in $candidates) {
        $i++
        $safeName = ($d.Name -replace '[^\w\.-]', '_')
        $logPath = Join-Path $analyzeDir ("analyze-{0:D2}-{1}.txt" -f $i, $safeName)
        $result = Invoke-MinidumpAnalysis -DumpPath $d.FullName -Debugger $Debugger -LogPath $logPath -TimeoutSec $TimeoutSec
        if ($null -ne $result) { [void]$results.Add($result) }

        if ($result -and $result.Success) {
            $p = $result.Parsed
            $mod = Get-CleanFaultingModule -Module $p.FaultingModule -Driver $p.FaultingDriver -ProbablyCausedBy $p.ProbablyCausedBy -FailureBucket $p.FailureBucket
            $modLabel = if ($mod) { $mod } elseif ($p.FailureBucket) { $p.FailureBucket } else { 'n/a' }
            Write-Info "OK: $($result.DumpName) -> $($p.BugcheckCode) $($p.BugcheckName) / $modLabel [$($p.DumpKind)]" 'Green'
        }
        else {
            $reason = if ($result) { $result.Reason } else { 'unknown failure' }
            Write-Info "Skip/fail: $($d.Name) - $reason" 'Yellow'
        }
    }

    return , (ConvertTo-ObjectArray $results)
}
#endregion WinDbg

#region RCA Engine
function Build-RootCauseAssessment {
    param($Bugchecks, $Related, $Dumps, $Changes, $DumpConfig, $Context, $DumpAnalyses)

    $findings = New-Object System.Collections.Generic.List[string]
    $actions = New-Object System.Collections.Generic.List[string]
    $confidence = 'Low'
    $headline = 'No clear BSOD pattern found in the selected window.'
    $primaryCode = $null

    $bugList = Get-Array ($Bugchecks | Where-Object { $_ -and ($_.BugcheckCode -or ($_.Message -match 'bugcheck')) })
    $relList = Get-Array $Related
    $dumpList = Get-Array $Dumps
    $changeList = Get-Array $Changes
    $analysisOk = Get-Array ($DumpAnalyses | Where-Object { $_.Success -and $_.Parsed })

    if ($analysisOk.Count -gt 0) {
        $best = $analysisOk | Select-Object -First 1
        $p = $best.Parsed
        $mod = Get-CleanFaultingModule -Module $p.FaultingModule -Driver $p.FaultingDriver -ProbablyCausedBy $p.ProbablyCausedBy -FailureBucket $p.FailureBucket
        $codeLabel = if ($p.BugcheckCode -and $p.BugcheckCode -ne 'Unknown') { $p.BugcheckCode } else { $null }
        $nameLabel = if ($p.BugcheckName -and $p.BugcheckName -notin @('Unknown', 'Analysis')) { $p.BugcheckName } else { '' }
        if (-not $nameLabel -and $codeLabel) {
            $nameLabel = (Resolve-BugcheckInfo -CodeHex $codeLabel).Name
        }

        if ($p.IsLiveKernelDump -or $best.DumpName -match '(?i)^(WHEA|WATCHDOG)-') {
            $kind = if ($p.DumpKind) { $p.DumpKind } else { 'Live Kernel Dump' }
            if ($codeLabel) {
                $headline = "$kind analysis: $codeLabel $nameLabel"
            }
            else {
                $headline = "$kind analysis from $($best.DumpName)"
            }
            if ($p.FailureBucket -match '(?i)MEMORY_CORRUPTION') {
                $headline += ' - kernel reported memory corruption (hardware or driver)'
            }
            $confidence = 'Medium'
            [void]$findings.Add("Analyzed live kernel dump $($best.DumpName) (not a classic BSOD minidump).")
            if ($codeLabel) { [void]$findings.Add("WER/dump path stop code: $codeLabel $nameLabel") }
            if ($p.FailureBucket) { [void]$findings.Add("Failure bucket: $($p.FailureBucket)") }
            if ($p.FailureBucket -match '(?i)LKD_MEMORY_CORRUPTION' -or $best.DumpName -match '(?i)^WHEA-') {
                [void]$findings.Add('This pattern often points to RAM/CPU/firmware/WHEA issues rather than a single named 3rd-party .sys.')
                [void]$actions.Add('Run Windows Memory Diagnostic / memtest; reseat RAM; try with XMP/DOCP off.')
                [void]$actions.Add('Update BIOS/firmware and review WHEA-Logger events around the dump timestamp.')
            }
            if ($best.DumpName -match '(?i)^WATCHDOG-') {
                [void]$findings.Add('Watchdog live dumps often indicate a DPC/ISR stall (storage, GPU, USB, or filter driver).')
                [void]$actions.Add('Update storage/GPU/chipset drivers and check for stuck devices or docks.')
            }
            if ($mod) {
                [void]$findings.Add("Possible module signal: $mod")
                [void]$actions.Add("Investigate module: $mod")
            }
            else {
                [void]$actions.Add('Do not chase IMAGE_NAME=memory_corruption as a driver filename - it is a bucket class, not a .sys.')
            }
        }
        else {
            if ($codeLabel -and $mod) {
                $headline = "Dump analysis: $codeLabel $nameLabel likely caused by $mod"
            }
            elseif ($codeLabel) {
                $headline = "Dump analysis: $codeLabel $nameLabel"
            }
            elseif ($mod) {
                $headline = "Dump analysis likely caused by $mod"
            }
            else {
                $headline = "Dump analysis completed for $($best.DumpName)"
            }
            $confidence = 'High'
            [void]$findings.Add("WinDbg !analyze -v on $($best.DumpName)")
            if ($mod) { [void]$findings.Add("Faulting module: $mod") }
            if ($p.ProbablyCausedBy) { [void]$findings.Add("Probably caused by: $($p.ProbablyCausedBy)") }
            if ($p.FailureBucket) { [void]$findings.Add("Failure bucket: $($p.FailureBucket)") }
            if ($mod) { [void]$actions.Add("Update, roll back, or remove the driver/module implicated: $mod") }
        }

        $primaryCode = $codeLabel
        if ($p.ProcessName) { [void]$findings.Add("Process name: $($p.ProcessName)") }
        if ($p.StackSummary) {
            $stackShort = ($p.StackSummary -split ' > ' | Select-Object -First 3) -join ' > '
            [void]$findings.Add("Stack (top frames): $stackShort")
        }

        # Enrich actions from dump context (bucket / process / stack)
        if ($p.FailureBucket -match '(?i)MEMORY_CORRUPTION') {
            [void]$actions.Add('Run Windows Memory Diagnostic (mdsched) or memtest86; reseat RAM and retest with XMP/DOCP off.')
            [void]$actions.Add('Update BIOS/firmware; check for known memory or chipset issues on this model.')
        }
        if ($p.ProcessName -match '(?i)DellPair|DellSupport|SupportAssist|DDV|Wave|Nahimic|Mystic|Armoury') {
            [void]$actions.Add("Update or temporarily uninstall OEM/background component related to $($p.ProcessName).")
        }
        if ($p.StackSummary -match '(?i)CSDeviceControl|Dell|nvlddmkm|dxgkrnl|dxgmms|iaStor|stornvme|NETIO|tcpip') {
            [void]$actions.Add('Stack shows vendor/filter activity - update or remove the matching OEM/security/filter driver and retest.')
        }
        if ($codeLabel) {
            $info = Resolve-BugcheckInfo -CodeHex $codeLabel
            foreach ($a in (Get-Array $info.Actions)) { [void]$actions.Add($a) }
        }
        [void]$actions.Add('Keep the windbg\analyze-*.txt logs with this report when escalating.')
    }
    elseif ($bugList.Count -eq 0) {
        $k41 = @($relList | Where-Object { $_.Type -like 'Kernel-Power 41*' })
        $whea = @($relList | Where-Object { $_.Type -like 'WHEA*' })
        if ($k41.Count -gt 0 -and $whea.Count -gt 0) {
            $headline = 'No Bugcheck 1001 events, but Kernel-Power 41 + WHEA errors suggest hardware or hard power-loss crashes.'
            $confidence = 'Medium'
            [void]$findings.Add('Investigate PSU, RAM, overheating, and motherboard WHEA details.')
        }
        elseif ($k41.Count -gt 0) {
            $headline = 'No formal bugcheck records; unexpected Kernel-Power 41 reboot(s) detected.'
            $confidence = 'Low'
            [void]$findings.Add('Could be BSOD with dump/logging disabled, power button reset, PSU blip, or overheating shutdown.')
            [void]$findings.Add("Crash dump type is currently: $($DumpConfig.CrashDumpType).")
        }
        else {
            $headline = 'No BSOD bugchecks or Kernel-Power 41 events found in the lookback window.'
            $confidence = 'High'
            [void]$findings.Add('If crashes are still happening, reproduce once with dumps enabled and re-run this script.')
        }
    }
    else {
        $primary = $bugList | Select-Object -First 1
        $primaryCode = $primary.BugcheckCode
        $headline = "Most recent BSOD: $($primary.BugcheckCode) $($primary.BugcheckName) at $($primary.TimeCreated)"
        $confidence = if ($primary.KnownCode) { 'Medium' } else { 'Low' }

        $grouped = $bugList | Group-Object BugcheckCode | Sort-Object Count -Descending
        $categoryVotes = @{}
        foreach ($g in $grouped) {
            $info = Resolve-BugcheckInfo -CodeHex $g.Name
            if (-not $categoryVotes.ContainsKey($info.Category)) { $categoryVotes[$info.Category] = 0 }
            $categoryVotes[$info.Category] += $g.Count
            [void]$findings.Add("$($g.Count)x $($g.Name) ($($info.Name)) - $($info.Category). $($info.Likely)")
        }
        $topCategory = $categoryVotes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        if ($topCategory) {
            [void]$findings.Add("Dominant failure category: $($topCategory.Key) ($($topCategory.Value) event(s)).")
            if ($bugList.Count -ge 2) { $confidence = 'Medium' }
            if ($bugList.Count -ge 3 -and @($grouped).Count -eq 1) { $confidence = 'High' }
        }

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
            [void]$findings.Add('WHEA hardware errors occurred near one or more BSODs - prioritize hardware (CPU/RAM/PCIe/power/thermals).')
        }

        $diskNear = @($relList | Where-Object { $_.Type -like 'Disk*' })
        if ($diskNear.Count -gt 0 -and ($primary.BugcheckCode -in @('0x00000154', '0x0000007A', '0x00000050', '0x00000133'))) {
            $confidence = 'High'
            [void]$findings.Add('Disk errors appear in the same window as storage-related stop codes - check drive health and storage drivers immediately.')
        }

        $firstBug = ($bugList | Sort-Object TimeCreated | Select-Object -First 1).TimeCreated
        $recentChanges = @($changeList | Where-Object { $_.TimeCreated -ge $firstBug.AddDays(-14) -and $_.TimeCreated -le $firstBug.AddDays(1) })
        if ($recentChanges.Count -gt 0) {
            [void]$findings.Add("Potential change correlation: $($recentChanges.Count) driver/software/hotfix change(s) within ~14 days of the crash wave.")
        }

        if ($dumpList.Count -eq 0) {
            [void]$findings.Add('No dump files found. Enable at least Automatic/Kernel dumps, reproduce once, then re-run for stronger RCA.')
            if ($DumpConfig.CrashDumpEnabled -eq 0) { [void]$findings.Add('Crash dumps are currently DISABLED in registry.') }
        }
        else {
            $newest = $dumpList | Select-Object -First 1
            [void]$findings.Add("Newest dump: $($newest.FullName) ($($newest.LengthMB) MB, $($newest.LastWriteTime)).")
            if ($analysisOk.Count -eq 0) {
                [void]$findings.Add('Dump files present but WinDbg/cdb analysis did not run or failed. Re-run elevated so winget can install Microsoft.WinDbg, or install it manually.')
            }
        }

        if ($primaryCode) {
            $info = Resolve-BugcheckInfo -CodeHex $primaryCode
            foreach ($a in $info.Actions) { [void]$actions.Add($a) }
        }
    }

    [void]$actions.Add('Keep this HTML/TXT report with the newest .dmp file (and windbg logs) when escalating.')
    [void]$actions.Add('Change one variable at a time (driver, stick of RAM, disk, etc.).')
    if (-not $Context.IsAdmin) {
        [void]$findings.Add('Script was NOT elevated - some events/dumps may be missing. Re-run as Administrator for complete RCA.')
    }

    # Deduplicate actions while preserving order
    $deduped = New-Object System.Collections.Generic.List[string]
    $seenAction = @{}
    foreach ($a in $actions) {
        if ([string]::IsNullOrWhiteSpace($a)) { continue }
        $key = $a.Trim().ToLowerInvariant()
        if ($seenAction.ContainsKey($key)) { continue }
        $seenAction[$key] = $true
        [void]$deduped.Add($a.Trim())
    }

    $nextSteps = Build-NextSteps -AssessmentActions @($deduped) -PrimaryCode $primaryCode -Findings @($findings) -DumpAnalyses $analysisOk -DumpConfig $DumpConfig -Context $Context

    [PSCustomObject]@{
        Headline           = $headline
        Confidence         = $confidence
        PrimaryBugcheck    = $primaryCode
        Findings           = @($findings)
        RecommendedActions = @($deduped)
        NextSteps          = @($nextSteps)
        BugcheckCount      = $bugList.Count
        RelatedEventCount  = $relList.Count
        DumpCount          = $dumpList.Count
        DumpAnalysisCount  = $analysisOk.Count
        FaultingModule     = if ($analysisOk.Count -gt 0) {
            $ap = $analysisOk[0].Parsed
            Get-CleanFaultingModule -Module $ap.FaultingModule -Driver $ap.FaultingDriver -ProbablyCausedBy $ap.ProbablyCausedBy -FailureBucket $ap.FailureBucket
        } else { $null }
    }
}

function Build-NextSteps {
    param(
        [string[]]$AssessmentActions,
        [string]$PrimaryCode,
        [string[]]$Findings,
        $DumpAnalyses,
        $DumpConfig,
        $Context
    )

    $steps = New-Object System.Collections.Generic.List[object]
    $n = 0
    function Add-Step {
        param([string]$Title, [string]$Detail, [string]$Why = '')
        [void]$steps.Add([PSCustomObject]@{
            Number = $steps.Count + 1
            Title  = $Title
            Detail = $Detail
            Why    = $Why
        })
    }

    $best = @(Get-Array $DumpAnalyses | Select-Object -First 1)[0]
    $bucket = if ($best -and $best.Parsed) { $best.Parsed.FailureBucket } else { '' }
    $proc = if ($best -and $best.Parsed) { $best.Parsed.ProcessName } else { '' }
    $stack = if ($best -and $best.Parsed) { $best.Parsed.StackSummary } else { '' }
    $mod = if ($best -and $best.Parsed) {
        Get-CleanFaultingModule -Module $best.Parsed.FaultingModule -Driver $best.Parsed.FaultingDriver -ProbablyCausedBy $best.Parsed.ProbablyCausedBy -FailureBucket $best.Parsed.FailureBucket
    } else { $null }

    if ($PrimaryCode) {
        $info = Resolve-BugcheckInfo -CodeHex $PrimaryCode
        Add-Step -Title "Address stop code $PrimaryCode ($($info.Name))" `
            -Detail (($info.Actions | Select-Object -First 2) -join ' ') `
            -Why $info.Likely
    }

    if ($bucket -match '(?i)MEMORY_CORRUPTION') {
        Add-Step -Title 'Rule out memory corruption' `
            -Detail 'Run Windows Memory Diagnostic (mdsched.exe) or an overnight memtest. Reseat RAM and retest with XMP/DOCP disabled.' `
            -Why "Failure bucket $bucket indicates the kernel detected corrupted memory structures."
    }

    if ($mod) {
        Add-Step -Title "Investigate module $mod" `
            -Detail "Update, roll back, or temporarily remove $mod (or the product that ships it). Reboot and watch for recurrence." `
            -Why 'Dump analysis pointed at this module as the most actionable software signal.'
    }

    if ($proc -match '(?i)DellPair|DellSupport|SupportAssist|DDV') {
        Add-Step -Title "Check Dell background component ($proc)" `
            -Detail "Update Dell Pair / SupportAssist / related OEM apps from Dell Command Update, or uninstall temporarily to test stability." `
            -Why "Process $proc was active in the crash analysis."
    }
    elseif ($proc -and $proc -notmatch '(?i)^(System|smss|csrss|svchost)\.exe$') {
        Add-Step -Title "Review process $proc" `
            -Detail "Identify which product owns $proc and update or remove it if it is OEM/AV/filter software." `
            -Why 'This process appeared in the dump analysis context.'
    }

    if ($stack -match '(?i)CSDeviceControl') {
        Add-Step -Title 'Investigate Dell CSDeviceControl / pairing stack' `
            -Detail 'Update or remove Dell Pair / Dell peripheral pairing components. Check Device Manager for Dell virtual devices with errors.' `
            -Why 'Stack text includes CSDeviceControl, which is commonly Dell pairing/device-control related.'
    }

    if ($DumpConfig -and $DumpConfig.CrashDumpEnabled -eq 3) {
        Add-Step -Title 'Consider enabling Automatic/Kernel dumps' `
            -Detail 'Small minidumps are better than nothing, but Automatic (7) or Kernel (2) dumps give stronger follow-up analysis if crashes continue.' `
            -Why "Current crash dump type is $($DumpConfig.CrashDumpType)."
    }

    if (-not $Context.IsAdmin) {
        Add-Step -Title 'Re-run elevated' `
            -Detail 'Right-click PowerShell > Run as administrator, then re-run this script for complete event/dump access.' `
            -Why 'This run was not elevated.'
    }

    # Fill remaining slots from assessment actions (skip near-duplicates)
    foreach ($a in (Get-Array $AssessmentActions)) {
        if ($steps.Count -ge 8) { break }
        $already = $false
        foreach ($s in $steps) {
            if ($a -and ($s.Detail -like "*$($a.Substring(0, [Math]::Min(40, $a.Length)))*" -or $s.Title -like "*$($a.Substring(0, [Math]::Min(24, $a.Length)))*")) {
                $already = $true; break
            }
        }
        if ($already) { continue }
        if ($a -match '(?i)^Keep this HTML|^Change one variable|^Keep the windbg') { continue }
        Add-Step -Title 'Follow-up action' -Detail $a -Why 'Derived from stop-code catalog and local evidence.'
    }

    # Always end with package/escalate guidance
    Add-Step -Title 'Package evidence for escalation' `
        -Detail 'Zip this report folder (HTML, TXT, JSON, dumps\, windbg\) and attach it to the ticket or send to Tier 3 / vendor support.' `
        -Why 'Preserves dump analysis logs and timeline for someone else to continue.'

    Add-Step -Title 'Change one variable at a time' `
        -Detail 'After each change (driver, RAM stick, BIOS setting, OEM app), reboot and monitor before making the next change.' `
        -Why 'Makes it clear which fix stopped the crashes.'

    # Renumber
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $steps[$i].Number = $i + 1
    }
    return , (ConvertTo-ObjectArray $steps)
}
#endregion RCA Engine

#region Reporting
function ConvertTo-HtmlEncoded {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function New-HtmlReport {
    param($Context, $Assessment, $Bugchecks, $Related, $Dumps, $Changes, $DumpConfig, $DumpAnalyses, [string]$Path, [int]$Days)

    $rowsBug = foreach ($b in (Get-Array $Bugchecks)) {
        "<tr><td>$(ConvertTo-HtmlEncoded $b.TimeCreated)</td><td><strong>$(ConvertTo-HtmlEncoded $b.BugcheckCode)</strong><br/>$(ConvertTo-HtmlEncoded $b.BugcheckName)</td><td>$(ConvertTo-HtmlEncoded $b.Category)</td><td>$(ConvertTo-HtmlEncoded $b.Parameter1)<br/>$(ConvertTo-HtmlEncoded $b.Parameter2)<br/>$(ConvertTo-HtmlEncoded $b.Parameter3)<br/>$(ConvertTo-HtmlEncoded $b.Parameter4)</td><td>$(ConvertTo-HtmlEncoded $b.LikelyCause)</td></tr>"
    }
    $rowsRel = foreach ($r in (Get-Array $Related | Select-Object -First 40)) {
        "<tr><td>$(ConvertTo-HtmlEncoded $r.TimeCreated)</td><td>$(ConvertTo-HtmlEncoded $r.Type)</td><td>$(ConvertTo-HtmlEncoded $r.Summary)</td><td>$(ConvertTo-HtmlEncoded $r.Message)</td></tr>"
    }
    $rowsDump = foreach ($d in (Get-Array $Dumps)) {
        $exists = if ($null -eq $d.Exists -or $d.Exists) { 'Yes' } else { 'Missing' }
        "<tr><td>$(ConvertTo-HtmlEncoded $d.LastWriteTime)</td><td>$(ConvertTo-HtmlEncoded $d.FullName)</td><td>$($d.LengthMB)</td><td>$($d.AgeDays)</td><td>$exists</td></tr>"
    }
    $rowsChg = foreach ($c in (Get-Array $Changes | Select-Object -First 40)) {
        "<tr><td>$(ConvertTo-HtmlEncoded $c.TimeCreated)</td><td>$(ConvertTo-HtmlEncoded $c.ChangeType)</td><td>$(ConvertTo-HtmlEncoded $c.Detail)</td></tr>"
    }
    $rowsWindbg = foreach ($a in (Get-Array $DumpAnalyses)) {
        $p = $a.Parsed
        $mod = if ($p) { $p.FaultingModule } else { '' }
        $drv = if ($p) { $p.FaultingDriver } else { '' }
        $code = if ($p) { $p.BugcheckCode } else { '' }
        $name = if ($p) { $p.BugcheckName } else { '' }
        $bucket = if ($p) { $p.FailureBucket } else { '' }
        $cause = if ($p) { $p.ProbablyCausedBy } else { '' }
        "<tr><td>$(ConvertTo-HtmlEncoded $a.DumpName)</td><td>$(ConvertTo-HtmlEncoded $a.Success)</td><td>$(ConvertTo-HtmlEncoded $code)<br/>$(ConvertTo-HtmlEncoded $name)</td><td>$(ConvertTo-HtmlEncoded $mod)<br/>$(ConvertTo-HtmlEncoded $drv)</td><td>$(ConvertTo-HtmlEncoded $cause)<br/>$(ConvertTo-HtmlEncoded $bucket)</td><td>$(ConvertTo-HtmlEncoded $a.Reason)<br/><code>$(ConvertTo-HtmlEncoded $a.LogPath)</code></td></tr>"
    }

    $findingsLi = ((Get-Array $Assessment.Findings) | ForEach-Object { "<li>$(ConvertTo-HtmlEncoded $_)</li>" }) -join "`n"
    $nextSteps = Get-Array $Assessment.NextSteps
    if ($nextSteps.Count -eq 0) {
        $nextSteps = Get-Array ($Assessment.RecommendedActions | ForEach-Object {
                [PSCustomObject]@{ Number = 0; Title = 'Action'; Detail = $_; Why = '' }
            })
        for ($i = 0; $i -lt $nextSteps.Count; $i++) { $nextSteps[$i].Number = $i + 1 }
    }
    $nextStepsHtml = foreach ($s in $nextSteps) {
        $why = if ($s.Why) { "<div class='why'><strong>Why:</strong> $(ConvertTo-HtmlEncoded $s.Why)</div>" } else { '' }
        @"
<div class="step">
  <div class="step-num">$($s.Number)</div>
  <div class="step-body">
    <div class="step-title">$(ConvertTo-HtmlEncoded $s.Title)</div>
    <div class="step-detail">$(ConvertTo-HtmlEncoded $s.Detail)</div>
    $why
  </div>
</div>
"@
    }
    $confColor = switch ($Assessment.Confidence) { 'High' { '#0b7a0b' } 'Medium' { '#9a6b00' } default { '#8a1f1f' } }

    $html = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/>
<title>BSOD RCA - $(ConvertTo-HtmlEncoded $Context.ComputerName)</title>
<style>
body{font-family:Segoe UI,Tahoma,sans-serif;margin:24px;color:#1a1a1a;background:#fafafa}
h1,h2{color:#0b3d5c}.card{background:#fff;border:1px solid #ddd;border-radius:8px;padding:16px 20px;margin:16px 0}
.headline{font-size:1.15rem;font-weight:600}.meta{color:#555;font-size:.92rem}
.badge{display:inline-block;padding:2px 10px;border-radius:999px;background:$confColor;color:#fff;font-size:.85rem}
table{border-collapse:collapse;width:100%;font-size:.9rem}th,td{border:1px solid #e2e2e2;padding:8px;vertical-align:top;text-align:left}
th{background:#eef5fa}tr:nth-child(even){background:#f9fbfd}code{background:#f0f0f0;padding:1px 4px;border-radius:3px}ul{line-height:1.45}
.next-card{border-color:#8eb6d8;background:linear-gradient(180deg,#f3f8fc 0%,#fff 48px)}
.step{display:flex;gap:14px;padding:12px 0;border-bottom:1px solid #e6eef5}
.step:last-child{border-bottom:0}
.step-num{flex:0 0 32px;height:32px;border-radius:50%;background:#0b3d5c;color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700}
.step-title{font-weight:650;color:#0b3d5c;margin-bottom:4px}
.step-detail{color:#222;line-height:1.4}
.why{margin-top:6px;color:#5a6b78;font-size:.9rem}
.ai-card{border-color:#2f6f4e;background:linear-gradient(180deg,#eef8f2 0%,#fff 56px)}
.ai-card code{background:#e4f0e9;padding:2px 6px}
</style></head><body>
<h1>Blue Screen Root Cause Analysis</h1>
<p class="meta">Computer: <strong>$(ConvertTo-HtmlEncoded $Context.ComputerName)</strong> | Collected: $(ConvertTo-HtmlEncoded $Context.CollectedAt) | Lookback: $Days days | Elevated: $($Context.IsAdmin)</p>
<div class="card ai-card">
  <h2>Paste into Copilot / ChatGPT</h2>
  <p>Open <code>PASTE-INTO-COPILOT.txt</code> in this report folder (also copied to the clipboard when the script finished). Paste the whole file into Microsoft Copilot, ChatGPT, or Claude for a second-pass analysis and ticket wording.</p>
  <p class="meta">Keep the HTML for humans; use the paste file for AI. Attach <code>windbg\</code> / dumps only if the AI asks for more detail.</p>
</div>
<div class="card">
  <div class="headline">$(ConvertTo-HtmlEncoded $Assessment.Headline)</div>
  <p>Confidence: <span class="badge">$(ConvertTo-HtmlEncoded $Assessment.Confidence)</span>
     | Bugchecks: $($Assessment.BugcheckCount) | Related: $($Assessment.RelatedEventCount)
     | Dumps: $($Assessment.DumpCount) | WinDbg analyzed: $($Assessment.DumpAnalysisCount)
     $(if ($Assessment.FaultingModule) { "| Faulting module: <strong>$(ConvertTo-HtmlEncoded $Assessment.FaultingModule)</strong>" })</p>
  <h2>Findings</h2><ul>$findingsLi</ul>
</div>
<div class="card next-card">
  <h2>Next steps</h2>
  <p class="meta">Do these in order. Change one thing at a time, then retest.</p>
  $($nextStepsHtml -join "`n")
</div>
<div class="card"><h2>System context</h2>
<table><tr><th>Field</th><th>Value</th></tr>
<tr><td>OS</td><td>$(ConvertTo-HtmlEncoded $Context.OSCaption) ($($Context.OSVersion) / build $($Context.OSBuild))</td></tr>
<tr><td>Hardware</td><td>$(ConvertTo-HtmlEncoded $Context.Manufacturer) $(ConvertTo-HtmlEncoded $Context.Model)</td></tr>
<tr><td>BIOS</td><td>$(ConvertTo-HtmlEncoded $Context.BIOSVersion)</td></tr>
<tr><td>CPU</td><td>$(ConvertTo-HtmlEncoded $Context.Processor)</td></tr>
<tr><td>Memory</td><td>$($Context.MemoryGB) GB</td></tr>
<tr><td>Last boot</td><td>$(ConvertTo-HtmlEncoded $Context.LastBoot) (uptime $($Context.UptimeDays) days)</td></tr>
<tr><td>Crash dump config</td><td>$(ConvertTo-HtmlEncoded $DumpConfig.CrashDumpType) (CrashDumpEnabled=$($DumpConfig.CrashDumpEnabled))</td></tr>
</table></div>
<div class="card"><h2>WinDbg / cdb dump analysis</h2>
<table><tr><th>Dump</th><th>Success</th><th>Stop code</th><th>Module / driver</th><th>Cause / bucket</th><th>Notes</th></tr>
$($rowsWindbg -join "`n")
</table>
<p class="meta">Raw !analyze -v logs are saved under the report <code>windbg\</code> folder.</p></div>
<div class="card"><h2>Bugcheck events (Event ID 1001)</h2>
<table><tr><th>Time</th><th>Stop code</th><th>Category</th><th>Parameters</th><th>Likely cause</th></tr>
$($rowsBug -join "`n")</table></div>
<div class="card"><h2>Related crash / hardware signals</h2>
<p class="meta">Only events within <strong>+/- 2 hours</strong> of a BSOD/dump anchor time.</p>
<table><tr><th>Time</th><th>Type</th><th>Summary</th><th>Message preview</th></tr>
$($rowsRel -join "`n")</table></div>
<div class="card"><h2>Crash dump files</h2>
<p class="meta">Dumps near crash anchors (plus analyzed / event-referenced dumps). Older unrelated live dumps are omitted.</p>
<table><tr><th>Modified</th><th>Path</th><th>MB</th><th>Age (days)</th><th>On disk</th></tr>
$($rowsDump -join "`n")</table></div>
<div class="card"><h2>Driver / software changes near crash times</h2>
<p class="meta">Within <strong>7 days before</strong> to <strong>1 day after</strong> each BSOD/dump anchor. Volume snapshot / FoD staging noise removed.</p>
<table><tr><th>Time</th><th>Type</th><th>Detail</th></tr>
$($rowsChg -join "`n")</table></div>
<p class="meta">Generated by Invoke-BlueScreenRCA.ps1 (standalone).</p>
</body></html>
"@
    Set-Content -Path $Path -Value $html -Encoding UTF8
}

function Get-WindbgLogExcerpt {
    param(
        [string]$LogPath,
        [int]$MaxChars = 7000
    )
    if (-not $LogPath -or -not (Test-Path -LiteralPath $LogPath)) { return '' }
    try {
        $raw = Get-Content -LiteralPath $LogPath -Raw -ErrorAction Stop
    }
    catch { return '' }
    if ([string]::IsNullOrWhiteSpace($raw)) { return '' }

    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -match '(?i)BUGCHECK_ANALYSIS|Bugcheck Analysis|BugCheck |BUGCHECK_CODE|BUGCHECK_P[1-4]|PROCESS_NAME|IMAGE_NAME|MODULE_NAME|FAULTING_MODULE|FAILURE_BUCKET_ID|FAILURE_ID_HASH|Probably caused by|STACK_TEXT|FOLLOWUP_IP|SYMBOL_NAME|BUCKET_ID|Defaulted to|Use !analyze|nvlddmkm|dxgkrnl|ntoskrnl|WHEA|WATCHDOG|MEMORY_CORRUPTION|IRQL|PAGE_FAULT|SYSTEM_SERVICE|KERNEL_MODE|EXCEPTION_CODE|Arg[1-4]|SYSTEM_THREAD|DRIVER_IRQL|CRITICAL_PROCESS|DPC_WATCHDOG') {
            [void]$keep.Add($line.TrimEnd())
        }
    }

    $excerpt = if ($keep.Count -gt 0) { ($keep -join "`n") } else { $raw }
    if ($excerpt.Length -gt $MaxChars) {
        $excerpt = $excerpt.Substring(0, $MaxChars) + "`n... [truncated for AI paste size]"
    }
    return $excerpt
}

function New-TextReport {
    param($Context, $Assessment, $Bugchecks, $Related, $Dumps, $Changes, $DumpConfig, $DumpAnalyses, [string]$Path, [int]$Days)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('BLUE SCREEN ROOT CAUSE ANALYSIS')
    [void]$sb.AppendLine(('=' * 70))
    [void]$sb.AppendLine("Computer : $($Context.ComputerName)")
    [void]$sb.AppendLine("Collected: $($Context.CollectedAt)")
    [void]$sb.AppendLine("Lookback : $Days days | Elevated: $($Context.IsAdmin)")
    [void]$sb.AppendLine("OS       : $($Context.OSCaption) ($($Context.OSVersion))")
    [void]$sb.AppendLine("Hardware : $($Context.Manufacturer) $($Context.Model)")
    [void]$sb.AppendLine("Dump cfg : $($DumpConfig.CrashDumpType)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('ASSESSMENT')
    [void]$sb.AppendLine(('-' * 70))
    [void]$sb.AppendLine($Assessment.Headline)
    [void]$sb.AppendLine("Confidence: $($Assessment.Confidence)")
    if ($Assessment.FaultingModule) { [void]$sb.AppendLine("Faulting module: $($Assessment.FaultingModule)") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Findings:')
    foreach ($f in (Get-Array $Assessment.Findings)) { [void]$sb.AppendLine(" - $f") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('NEXT STEPS')
    [void]$sb.AppendLine(('-' * 70))
    foreach ($s in (Get-Array $Assessment.NextSteps)) {
        [void]$sb.AppendLine("$($s.Number). $($s.Title)")
        [void]$sb.AppendLine("    $($s.Detail)")
        if ($s.Why) { [void]$sb.AppendLine("    Why: $($s.Why)") }
    }
    if (@(Get-Array $Assessment.NextSteps).Count -eq 0) {
        [void]$sb.AppendLine('Recommended actions:')
        foreach ($a in (Get-Array $Assessment.RecommendedActions)) { [void]$sb.AppendLine(" - $a") }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('WINDBG / CDB ANALYSIS')
    [void]$sb.AppendLine(('-' * 70))
    foreach ($a in (Get-Array $DumpAnalyses)) {
        [void]$sb.AppendLine("$($a.DumpName)  success=$($a.Success)  $($a.Reason)")
        if ($a.Parsed) {
            [void]$sb.AppendLine("    Code=$($a.Parsed.BugcheckCode) Name=$($a.Parsed.BugcheckName)")
            [void]$sb.AppendLine("    Module=$($a.Parsed.FaultingModule) Driver=$($a.Parsed.FaultingDriver)")
            [void]$sb.AppendLine("    ProbablyCausedBy=$($a.Parsed.ProbablyCausedBy)")
            [void]$sb.AppendLine("    Bucket=$($a.Parsed.FailureBucket)")
            [void]$sb.AppendLine("    Log=$($a.LogPath)")
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('BUGCHECKS')
    [void]$sb.AppendLine(('-' * 70))
    foreach ($b in (Get-Array $Bugchecks)) {
        [void]$sb.AppendLine("$($b.TimeCreated)  $($b.BugcheckCode) $($b.BugcheckName) [$($b.Category)]")
        [void]$sb.AppendLine("    Params: $($b.Parameter1), $($b.Parameter2), $($b.Parameter3), $($b.Parameter4)")
        if ($b.DumpFile) { [void]$sb.AppendLine("    DumpFile: $($b.DumpFile)") }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('RELATED EVENTS')
    [void]$sb.AppendLine(('-' * 70))
    foreach ($r in (Get-Array $Related | Select-Object -First 40)) {
        [void]$sb.AppendLine("$($r.TimeCreated)  $($r.Type)  $($r.Summary)")
        if ($r.Message) { [void]$sb.AppendLine("    $(Get-ShortText $r.Message 320)") }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('DUMP FILES')
    [void]$sb.AppendLine(('-' * 70))
    foreach ($d in (Get-Array $Dumps)) {
        $exists = if ($null -eq $d.Exists -or $d.Exists) { 'on disk' } else { 'MISSING' }
        [void]$sb.AppendLine("$($d.LastWriteTime)  $($d.LengthMB) MB  [$exists]  $($d.FullName)")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('RECENT CHANGES')
    [void]$sb.AppendLine(('-' * 70))
    foreach ($c in (Get-Array $Changes | Select-Object -First 40)) {
        [void]$sb.AppendLine("$($c.TimeCreated)  $($c.ChangeType)")
        [void]$sb.AppendLine("    $($c.Detail)")
    }
    Set-Content -Path $Path -Value $sb.ToString() -Encoding UTF8
}

function New-AiPasteReport {
    param($Context, $Assessment, $Bugchecks, $Related, $Dumps, $Changes, $DumpConfig, $DumpAnalyses, [string]$Path, [int]$Days)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('=== COPY EVERYTHING BELOW THIS LINE INTO COPILOT / CHATGPT / CLAUDE ===')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('You are helping an IT technician triage a Windows blue screen (BSOD) or live kernel dump.')
    [void]$sb.AppendLine('Below is evidence collected by Invoke-BlueScreenRCA.ps1 on the affected PC.')
    [void]$sb.AppendLine('Treat this as the only source of truth for this machine. Do not invent dump results that are not listed.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Please respond with:')
    [void]$sb.AppendLine('1) Most likely root cause (with confidence: High / Medium / Low)')
    [void]$sb.AppendLine('2) What evidence supports that conclusion')
    [void]$sb.AppendLine('3) Competing alternate causes (if any)')
    [void]$sb.AppendLine('4) Ordered next actions for a field tech (change one variable at a time)')
    [void]$sb.AppendLine('5) What to collect next if the cause is still unclear')
    [void]$sb.AppendLine('6) A short ticket note (5-8 lines) suitable for ServiceNow / Jira')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('=== MACHINE EVIDENCE START ===')
    [void]$sb.AppendLine("Computer: $($Context.ComputerName)")
    [void]$sb.AppendLine("CollectedAt: $($Context.CollectedAt)")
    [void]$sb.AppendLine("LookbackDays: $Days")
    [void]$sb.AppendLine("Elevated: $($Context.IsAdmin)")
    [void]$sb.AppendLine("OS: $($Context.OSCaption) | Version $($Context.OSVersion) | Build $($Context.OSBuild)")
    [void]$sb.AppendLine("Hardware: $($Context.Manufacturer) $($Context.Model)")
    [void]$sb.AppendLine("BIOS: $($Context.BIOSVersion)")
    [void]$sb.AppendLine("CPU: $($Context.Processor)")
    [void]$sb.AppendLine("MemoryGB: $($Context.MemoryGB)")
    [void]$sb.AppendLine("LastBoot: $($Context.LastBoot) | UptimeDays: $($Context.UptimeDays)")
    [void]$sb.AppendLine("CrashDumpType: $($DumpConfig.CrashDumpType) | CrashDumpEnabled: $($DumpConfig.CrashDumpEnabled)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- Script assessment (starting point, verify against evidence) ---')
    [void]$sb.AppendLine("Headline: $($Assessment.Headline)")
    [void]$sb.AppendLine("Confidence: $($Assessment.Confidence)")
    if ($Assessment.FaultingModule) { [void]$sb.AppendLine("FaultingModule: $($Assessment.FaultingModule)") }
    foreach ($f in (Get-Array $Assessment.Findings)) { [void]$sb.AppendLine("Finding: $f") }
    foreach ($s in (Get-Array $Assessment.NextSteps)) {
        [void]$sb.AppendLine("SuggestedStep $($s.Number): $($s.Title) | $($s.Detail)$(if ($s.Why) { " | Why: $($s.Why)" })")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- Bugcheck Event ID 1001 ---')
    $bugs = Get-Array $Bugchecks
    if ($bugs.Count -eq 0) {
        [void]$sb.AppendLine('(none in lookback window)')
    }
    else {
        foreach ($b in $bugs) {
            [void]$sb.AppendLine("Time=$($b.TimeCreated) Code=$($b.BugcheckCode) Name=$($b.BugcheckName) Category=$($b.Category)")
            [void]$sb.AppendLine("  Params=$($b.Parameter1), $($b.Parameter2), $($b.Parameter3), $($b.Parameter4)")
            if ($b.LikelyCause) { [void]$sb.AppendLine("  LikelyCause=$($b.LikelyCause)") }
            if ($b.DumpFile) { [void]$sb.AppendLine("  DumpFile=$($b.DumpFile)") }
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- WinDbg / cdb !analyze -v (parsed) ---')
    $analyses = Get-Array $DumpAnalyses
    if ($analyses.Count -eq 0) {
        [void]$sb.AppendLine('(no dump analysis ran)')
    }
    else {
        foreach ($a in $analyses) {
            [void]$sb.AppendLine("Dump=$($a.DumpName) Success=$($a.Success) Reason=$($a.Reason)")
            if ($a.Parsed) {
                [void]$sb.AppendLine("  Code=$($a.Parsed.BugcheckCode) Name=$($a.Parsed.BugcheckName)")
                [void]$sb.AppendLine("  Module=$($a.Parsed.FaultingModule) Driver=$($a.Parsed.FaultingDriver)")
                [void]$sb.AppendLine("  Process=$($a.Parsed.ProcessName) Symbol=$($a.Parsed.SymbolName)")
                [void]$sb.AppendLine("  DumpKind=$($a.Parsed.DumpKind) ProbablyCausedBy=$($a.Parsed.ProbablyCausedBy)")
                [void]$sb.AppendLine("  FailureBucket=$($a.Parsed.FailureBucket)")
                if ($a.Parsed.StackSummary) { [void]$sb.AppendLine("  Stack=$($a.Parsed.StackSummary)") }
            }
            $excerpt = Get-WindbgLogExcerpt -LogPath $a.LogPath -MaxChars 7000
            if ($excerpt) {
                [void]$sb.AppendLine('  --- !analyze excerpt ---')
                [void]$sb.AppendLine($excerpt)
                [void]$sb.AppendLine('  --- end excerpt ---')
            }
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- Related signals within +/- 2 hours of crash anchors ---')
    $rels = Get-Array ($Related | Select-Object -First 40)
    if ($rels.Count -eq 0) {
        [void]$sb.AppendLine('(none)')
    }
    else {
        foreach ($r in $rels) {
            [void]$sb.AppendLine("Time=$($r.TimeCreated) Type=$($r.Type) Summary=$($r.Summary)")
            if ($r.Message) { [void]$sb.AppendLine("  Message=$(Get-ShortText $r.Message 400)") }
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- Dump inventory (filtered near crash anchors) ---')
    foreach ($d in (Get-Array $Dumps)) {
        $exists = if ($null -eq $d.Exists -or $d.Exists) { 'Yes' } else { 'Missing' }
        [void]$sb.AppendLine("Time=$($d.LastWriteTime) MB=$($d.LengthMB) OnDisk=$exists Path=$($d.FullName)")
    }
    if (@(Get-Array $Dumps).Count -eq 0) { [void]$sb.AppendLine('(none)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- Driver/software changes within 7d before to 1d after crash ---')
    $chgs = Get-Array ($Changes | Select-Object -First 40)
    if ($chgs.Count -eq 0) {
        [void]$sb.AppendLine('(none)')
    }
    else {
        foreach ($c in $chgs) {
            [void]$sb.AppendLine("Time=$($c.TimeCreated) Type=$($c.ChangeType)")
            [void]$sb.AppendLine("  Detail=$($c.Detail)")
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('=== MACHINE EVIDENCE END ===')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('=== END OF PASTE ===')

    $text = $sb.ToString()
    Set-Content -Path $Path -Value $text -Encoding UTF8
    return $text
}

function Copy-TextToClipboardSafe {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    try {
        Set-Clipboard -Value $Text -ErrorAction Stop
        return $true
    }
    catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            [System.Windows.Forms.Clipboard]::SetText($Text)
            return $true
        }
        catch {
            return $false
        }
    }
}
#endregion Reporting

#region Main
Write-Section 'Blue Screen RCA Analyzer (standalone)'
Write-Info "Lookback: $Days days | Max events/category: $Count"
$isAdmin = Test-IsAdministrator
if ($isAdmin) { Write-Info 'Running elevated - full collection enabled.' 'Green' }
else { Write-Info 'Not elevated - results may be incomplete. Right-click PowerShell > Run as administrator, then re-run.' 'Yellow' }

$start = (Get-Date).AddDays(-$Days)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutputDirectory) {
    $desktop = Get-ReportRootDirectory
    $OutputDirectory = Join-Path $desktop "BSOD-RCA-$env:COMPUTERNAME-$stamp"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Write-Section '1/7 System context'
$context = Get-SystemContext
Write-Info "$($context.Manufacturer) $($context.Model) | $($context.OSCaption) build $($context.OSBuild)"
Write-Info "Last boot: $($context.LastBoot) (uptime $($context.UptimeDays) days) | RAM: $($context.MemoryGB) GB"

Write-Section '2/7 Bugcheck events'
$bugchecks = Get-Array (Get-BugcheckEvents -Start $start -MaxEvents $Count)
if (@($bugchecks).Count -gt 0) {
    Write-Info "Found $(@($bugchecks).Count) bugcheck event(s)." 'Green'
    $bugchecks | Select-Object -First 5 | ForEach-Object {
        $dumpNote = if ($_.DumpFile) { " | dump: $($_.DumpFile)" } else { '' }
        Write-Info "$($_.TimeCreated)  $($_.BugcheckCode) $($_.BugcheckName)$dumpNote" 'Red'
    }
}
else {
    Write-Info 'No Event ID 1001 bugcheck records in lookback window.' 'Yellow'
}

Write-Section '3/7 Crash dump configuration & files'
$dumpConfig = Get-CrashDumpConfiguration
$extraDumpPaths = @(
    $bugchecks |
        Where-Object { $_.DumpFile } |
        ForEach-Object { $_.DumpFile }
)
$dumps = Get-Array (Get-DumpInventory -ExtraPaths $extraDumpPaths -MinidumpDir $dumpConfig.MinidumpDir)
$existingDumps = Get-Array ($dumps | Where-Object { $_.Exists -ne $false -and $_.FullName -and (Test-Path -LiteralPath $_.FullName) })
Write-Info "Dump type: $($dumpConfig.CrashDumpType) (CrashDumpEnabled=$($dumpConfig.CrashDumpEnabled))"
if (@($existingDumps).Count -gt 0) {
    Write-Info "Found $(@($existingDumps).Count) dump file(s) on disk. Newest: $($existingDumps[0].Name) at $($existingDumps[0].LastWriteTime)" 'Green'
}
else {
    Write-Info 'No dump files currently on disk under Minidump / MEMORY.DMP / LiveKernelReports / WER.' 'Yellow'
    $missing = Get-Array ($dumps | Where-Object { $_.Exists -eq $false })
    foreach ($m in $missing) {
        Write-Info "Event reported dump but file is missing: $($m.FullName)" 'Yellow'
    }
}

Write-Section '4/7 Related crash / hardware signals'
$relatedAll = Get-Array (Get-RelatedCrashEvents -Start $start -MaxEvents ([Math]::Max($Count, 50)))
$crashAnchors = Get-CrashAnchorTimes -Bugchecks $bugchecks -Dumps $existingDumps -DumpAnalyses @()
$related = Get-Array (Select-ItemsNearCrashTimes -Items $relatedAll -AnchorTimes $crashAnchors -BeforeHours 2 -AfterHours 2)
if (@($crashAnchors).Count -eq 0) {
    Write-Info 'No BSOD/dump anchors yet - related-event filter deferred until after dump analysis.' 'Yellow'
    $related = @()
}
else {
    Write-Info "Anchors: $(@($crashAnchors).Count) crash time(s). Related events within +/- 2 hours: $(@($related).Count) (from $(@($relatedAll).Count))" 
}

Write-Section '5/7 Recent driver / software changes'
$changesAll = Get-Array (Get-RecentDriverAndSoftwareChanges -Start $start)
$changesNear = Get-Array (Select-ItemsNearCrashTimes -Items $changesAll -AnchorTimes $crashAnchors -BeforeHours (7 * 24) -AfterHours 24)
$changes = Get-Array ($changesNear | Where-Object { -not (Test-IsNoisyChangeDetail -Change $_) })
if (@($crashAnchors).Count -eq 0) {
    Write-Info 'No crash anchors - skipping noisy full-lookback change list for the report.' 'Yellow'
    $changes = @()
}
else {
    Write-Info "Changes within 7 days before / 1 day after crash(es): $(@($changes).Count) (filtered from $(@($changesAll).Count); volsnap/FoD noise removed)"
}

Write-Section '6/7 WinDbg / cdb dump analysis'
$dumpAnalyses = @()
$debugger = Find-DumpDebugger
if ($SkipDumpAnalysis) {
    Write-Info 'Dump analysis skipped (-SkipDumpAnalysis).' 'Yellow'
}
elseif (@($existingDumps).Count -eq 0 -and -not $AnalyzeDumps) {
    Write-Info 'No dumps on disk to analyze.' 'Gray'
}
else {
    $shouldInstall = (-not $debugger -or $InstallDebuggers) -and -not $SkipDebuggerInstall
    if ($shouldInstall) {
        if ($InstallDebuggers -and $debugger) {
            Write-Info 'Forcing debugger install/refresh (-InstallDebuggers)...' 'Yellow'
            $debugger = Install-DumpDebugger -Force
        }
        elseif (-not $debugger) {
            Write-Info 'Debugger not found; installing WinDbg via winget if possible...' 'Yellow'
            $debugger = Install-DumpDebugger
        }
    }
    elseif (-not $debugger -and $SkipDebuggerInstall) {
        Write-Info 'No debugger found and -SkipDebuggerInstall was set.' 'Yellow'
    }

    if (-not $debugger) {
        Write-Info 'No WinDbg/cdb available - dump analysis skipped.' 'Yellow'
        Write-Info 'Manual install: winget install Microsoft.WinDbg' 'Gray'
    }
    else {
        Write-Info "Using debugger: $($debugger.Kind) ($($debugger.Source)) - $($debugger.Path)" 'Green'
        Write-Info 'First analysis may download symbols from Microsoft (needs internet).' 'Gray'
        $dumpAnalyses = Get-Array (Invoke-DumpAnalysisPass -Dumps $existingDumps -Debugger $debugger -OutputDirectory $OutputDirectory -MaxDumps $MaxDumpsToAnalyze -MaxSizeMB $MaxDumpSizeMB -TimeoutSec $DumpAnalysisTimeoutSec)
        Write-Info "Dump analysis results: $(@($dumpAnalyses).Count)"
    }
}

# Refresh near-crash filters using dump analysis timestamps too
$crashAnchors = Get-CrashAnchorTimes -Bugchecks $bugchecks -Dumps $existingDumps -DumpAnalyses $dumpAnalyses
if (@($crashAnchors).Count -gt 0) {
    $related = Get-Array (Select-ItemsNearCrashTimes -Items $relatedAll -AnchorTimes $crashAnchors -BeforeHours 2 -AfterHours 2)
    $changesNear = Get-Array (Select-ItemsNearCrashTimes -Items $changesAll -AnchorTimes $crashAnchors -BeforeHours (7 * 24) -AfterHours 24)
    $changes = Get-Array ($changesNear | Where-Object { -not (Test-IsNoisyChangeDetail -Change $_) })
    $dumpsForReport = Get-Array (Select-ItemsNearCrashTimes -Items $dumps -AnchorTimes $crashAnchors -BeforeHours (48) -AfterHours 24 -TimeProperty 'LastWriteTime' -ExtraInclude {
            param($d)
            # Always keep event-referenced missing dumps and dumps we analyzed
            ($d.Exists -eq $false) -or
            (@($dumpAnalyses | Where-Object { $_.DumpPath -and ($_.DumpPath -eq $d.FullName) }).Count -gt 0) -or
            ($d.Name -match '^\d{6}-\d+')
        })
    Write-Info "Report filter using $(@($crashAnchors).Count) crash anchor(s): related=$(@($related).Count), changes=$(@($changes).Count), dumps=$(@($dumpsForReport).Count)" 'Cyan'
}
else {
    $dumpsForReport = Get-Array ($existingDumps | Select-Object -First 10)
    Write-Info 'No crash anchors available - report will include limited dump inventory only.' 'Yellow'
}

Write-Section '7/7 Root cause assessment'
$assessment = Build-RootCauseAssessment -Bugchecks $bugchecks -Related $related -Dumps $existingDumps -Changes $changes -DumpConfig $dumpConfig -Context $context -DumpAnalyses $dumpAnalyses
Write-Host ""
Write-Host "  $($assessment.Headline)" -ForegroundColor White
$confColor = if ($assessment.Confidence -eq 'High') { 'Green' } elseif ($assessment.Confidence -eq 'Medium') { 'Yellow' } else { 'Red' }
Write-Info "Confidence: $($assessment.Confidence)" $confColor
if ($assessment.FaultingModule) { Write-Info "Faulting module: $($assessment.FaultingModule)" 'Green' }
foreach ($f in (Get-Array $assessment.Findings)) { Write-Info "- $f" 'Gray' }
Write-Host ""
Write-Info 'Next steps:' 'Cyan'
$steps = Get-Array $assessment.NextSteps
if ($steps.Count -gt 0) {
    foreach ($s in $steps) { Write-Info "$($s.Number). $($s.Title) - $($s.Detail)" 'White' }
}
else {
    foreach ($a in (Get-Array $assessment.RecommendedActions)) { Write-Info "- $a" 'White' }
}

$htmlPath = Join-Path $OutputDirectory 'BSOD-RCA-Report.html'
$txtPath = Join-Path $OutputDirectory 'BSOD-RCA-Report.txt'
$aiPath = Join-Path $OutputDirectory 'PASTE-INTO-COPILOT.txt'
$jsonPath = Join-Path $OutputDirectory 'BSOD-RCA-Data.json'

New-HtmlReport -Context $context -Assessment $assessment -Bugchecks $bugchecks -Related $related -Dumps $dumpsForReport -Changes $changes -DumpConfig $dumpConfig -DumpAnalyses $dumpAnalyses -Path $htmlPath -Days $Days
New-TextReport -Context $context -Assessment $assessment -Bugchecks $bugchecks -Related $related -Dumps $dumpsForReport -Changes $changes -DumpConfig $dumpConfig -DumpAnalyses $dumpAnalyses -Path $txtPath -Days $Days
$aiText = New-AiPasteReport -Context $context -Assessment $assessment -Bugchecks $bugchecks -Related $related -Dumps $dumpsForReport -Changes $changes -DumpConfig $dumpConfig -DumpAnalyses $dumpAnalyses -Path $aiPath -Days $Days

[PSCustomObject]@{
    Context      = $context
    Assessment   = $assessment
    DumpConfig   = $dumpConfig
    Bugchecks    = $bugchecks
    Related      = $related
    Dumps        = $dumps
    Changes      = $changes
    DumpAnalyses = $dumpAnalyses
    CdbPath      = if ($debugger) { $debugger.Path } else { $null }
    Debugger     = $debugger
} | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

$copyDir = Join-Path $OutputDirectory 'dumps'
New-Item -ItemType Directory -Path $copyDir -Force | Out-Null
$copied = 0
foreach ($d in @($existingDumps | Select-Object -First 5)) {
    if (-not $d -or -not $d.FullName) { continue }
    if (-not (Test-Path -LiteralPath $d.FullName)) { continue }
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

$clipboardOk = $false
if (-not $SkipClipboard) {
    $clipboardOk = Copy-TextToClipboardSafe -Text $aiText
}

Write-Section 'Report ready'
Write-Info "Folder : $OutputDirectory" 'Green'
Write-Info "HTML   : $htmlPath" 'Green'
Write-Info "Text   : $txtPath" 'Green'
Write-Info "AI paste: $aiPath" 'Green'
Write-Info "JSON   : $jsonPath"
Write-Info "Dumps copied: $copied | WinDbg logs under: $(Join-Path $OutputDirectory 'windbg')"
Write-Host ""
if ($clipboardOk) {
    Write-Info 'PASTE-INTO-COPILOT.txt is on the clipboard. Open Copilot and paste (Ctrl+V).' 'Cyan'
}
else {
    Write-Info 'Open PASTE-INTO-COPILOT.txt, Select All, Copy, then paste into Copilot.' 'Cyan'
}
Write-Info 'Share the whole BSOD-RCA-* folder (HTML + paste file + dumps + windbg) when escalating.' 'Cyan'

if ($OpenReport -and (Test-Path $htmlPath)) { Start-Process $htmlPath }

[PSCustomObject]@{
    OutputDirectory = $OutputDirectory
    HtmlReport      = $htmlPath
    TextReport      = $txtPath
    AiPasteReport   = $aiPath
    Assessment      = $assessment
    DumpAnalyses    = $dumpAnalyses
    Bugchecks       = $bugchecks
}
#endregion Main
