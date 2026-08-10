# Blue Screen RCA Analyzer

Standalone Windows PowerShell toolkit that builds a first-pass root cause analysis for blue screens. Zip it, email it, run it elevated, get a report back.

When dump files are present it runs `!analyze -v`. If WinDbg/`cdb` is missing, it **auto-installs WinDbg Preview via winget** when possible.

No modules required. Event/dump inventory works offline. Dump analysis uses Microsoft public symbols (needs internet the first time).

## What's in this folder

| File | Purpose |
|------|---------|
| `Invoke-BlueScreenRCA.ps1` | Main analyzer (+ WinDbg/cdb) |
| `Run-BlueScreenRCA.cmd` | Double-click launcher (requests admin) |
| `HOW-TO-RUN.txt` | Short instructions you can forward as-is |
| `README.md` | This file |

## Quick start

1. Put `Invoke-BlueScreenRCA.ps1` and `Run-BlueScreenRCA.cmd` in the same folder.
2. Right-click `Run-BlueScreenRCA.cmd` → **Run as administrator**.
3. Approve UAC and wait (first run may install WinDbg via winget).
4. An HTML report opens when it finishes.
5. `PASTE-INTO-COPILOT.txt` is written and copied to the clipboard — paste into Copilot/ChatGPT for a second-pass analysis.
6. Send back the `BSOD-RCA-<ComputerName>-<timestamp>` folder from the Desktop if escalating.

### PowerShell (manual)

```powershell
cd <folder-with-script>
Set-ExecutionPolicy -Scope Process Bypass
.\Invoke-BlueScreenRCA.ps1 -OpenReport
```

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `-Days` | `60` | Event log lookback window |
| `-Count` | `25` | Max events per category |
| `-OutputDirectory` | Desktop folder | Where reports are written |
| `-OpenReport` | off | Open the HTML report at the end |
| `-AnalyzeDumps` | auto when dumps exist | Run `!analyze -v` |
| `-SkipDumpAnalysis` | off | Never run dump analysis |
| `-InstallDebuggers` | off | Force winget install attempt |
| `-SkipDebuggerInstall` | off | Never auto-install WinDbg/SDK |
| `-SkipClipboard` | off | Do not copy `PASTE-INTO-COPILOT.txt` to clipboard |
| `-MaxDumpsToAnalyze` | `3` | Newest dumps to analyze |
| `-MaxDumpSizeMB` | `2048` | Skip larger dumps for auto analysis |
| `-DumpAnalysisTimeoutSec` | `300` | Per-dump timeout |

## WinDbg behavior

When dumps are present and analysis is not skipped:

1. Looks for `cdb.exe` (Windows Kits) or **WinDbg Preview** (`WinDbgX.exe`).
2. If neither is found, **automatically installs WinDbg via winget** (`Microsoft.WinDbg`).
3. If WinDbg still is not usable, falls back to winget Windows SDK packages for `cdb.exe`.
4. Runs `!analyze -v`, parses the faulting module, and saves logs under `windbg\`.
5. Successful dump analysis becomes the report headline (**High** confidence).

```powershell
# Default: analyze dumps; auto-install WinDbg via winget if missing
.\Invoke-BlueScreenRCA.ps1 -OpenReport

# Do not install anything
.\Invoke-BlueScreenRCA.ps1 -SkipDebuggerInstall -OpenReport

# Events only
.\Invoke-BlueScreenRCA.ps1 -SkipDumpAnalysis -OpenReport
```

Admin + winget help installs succeed on locked-down machines. First symbol download needs internet.

## What it collects

1. System context (OS, hardware, BIOS, RAM, uptime)
2. Crash dump config + dump inventory
3. Bugcheck Event ID 1001 stop codes/parameters
4. Related signals (Kernel-Power 41, 6008, WHEA, disk errors)
5. Recent driver/hotfix/`.sys` changes
6. WinDbg/cdb dump analysis (auto-installs WinDbg if needed)
7. RCA summary (headline, confidence, findings, actions)

## What you get back

Desktop folder like `BSOD-RCA-DESKTOP01-20260810-131500\`:

```
PASTE-INTO-COPILOT.txt ← paste this into Copilot / ChatGPT / Claude
BSOD-RCA-Report.html   ← human-readable report
BSOD-RCA-Report.txt
BSOD-RCA-Data.json
dumps\                 ← copied minidumps (≤500 MB each)
windbg\                ← raw !analyze -v logs (when analysis ran)
```

## Copilot / AI workflow

1. Run the analyzer elevated.
2. When it finishes, `PASTE-INTO-COPILOT.txt` is on the clipboard (unless `-SkipClipboard`).
3. Open Microsoft Copilot (or ChatGPT / Claude) and paste.
4. The paste file already includes a prompt asking for root cause, confidence, next actions, and a short ticket note.
5. Use HTML for the human report; use the paste file for AI. Attach dumps/`windbg` only if needed.

## Requirements and limits

- Admin recommended (events, dumps, and winget installs).
- winget required for automatic WinDbg install.
- Does not change crash dump settings.
- Still a triage aid — exotic hardware faults may need vendor tools.

## Sharing checklist

- [ ] Send `Invoke-BlueScreenRCA.ps1` + `Run-BlueScreenRCA.cmd` together
- [ ] Ask them to run elevated
- [ ] Paste `PASTE-INTO-COPILOT.txt` into Copilot for analysis / ticket wording
- [ ] Ask for the full `BSOD-RCA-*` Desktop folder back when escalating
- [ ] Open `BSOD-RCA-Report.html` for humans; check `windbg\` if present
