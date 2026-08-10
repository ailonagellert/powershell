# Blue Screen RCA Analyzer

Standalone Windows PowerShell toolkit that builds a first-pass root cause analysis for blue screens. Zip it, email it, run it elevated, get a report back.

No install. No modules. No internet. Works on Windows 10/11 with PowerShell 5.1+.

## What's in this folder

| File | Purpose |
|------|---------|
| `Invoke-BlueScreenRCA.ps1` | Main analyzer |
| `Run-BlueScreenRCA.cmd` | Double-click launcher (requests admin) |
| `HOW-TO-RUN.txt` | Short instructions you can forward as-is |
| `README.md` | This file |

## Quick start

1. Put `Invoke-BlueScreenRCA.ps1` and `Run-BlueScreenRCA.cmd` in the same folder.
2. Right-click `Run-BlueScreenRCA.cmd` → **Run as administrator**.
3. Approve UAC and wait.
4. An HTML report opens when it finishes.
5. Send back the `BSOD-RCA-<ComputerName>-<timestamp>` folder from the Desktop.

### PowerShell (manual)

```powershell
cd <folder-with-script>
Set-ExecutionPolicy -Scope Process Bypass
.\Invoke-BlueScreenRCA.ps1 -OpenReport
```

Useful options:

```powershell
# Last 90 days, open report when done
.\Invoke-BlueScreenRCA.ps1 -Days 90 -OpenReport

# Custom output folder
.\Invoke-BlueScreenRCA.ps1 -OutputDirectory "C:\Temp\BSOD-RCA" -OpenReport
```

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `-Days` | `60` | Event log lookback window |
| `-Count` | `25` | Max events per category |
| `-OutputDirectory` | Desktop folder | Where reports are written |
| `-OpenReport` | off | Open the HTML report at the end |

## What it collects

1. **System context** — OS build, hardware model, BIOS, RAM, uptime
2. **Crash dump config** — dump type + inventory of `Minidump`, `MEMORY.DMP`, LiveKernelReports
3. **Bugcheck events** — Event ID 1001 stop codes and parameters
4. **Related signals** — Kernel-Power 41, unexpected shutdowns (6008), WHEA hardware errors, disk errors
5. **Recent changes** — driver/PnP activity, hotfixes, recently modified `.sys` files
6. **RCA summary** — headline, confidence, findings, recommended next actions

Built-in stop-code guidance covers common codes such as `0x124` (WHEA), `0x154` (UNEXPECTED_STORE_EXCEPTION), `0x9F` (power IRP), `0x133` (DPC watchdog), `0xD1` / `0x0A` (IRQL), and others.

## What you get back

Desktop folder like `BSOD-RCA-DESKTOP01-20260810-131500\`:

```
BSOD-RCA-Report.html   ← start here
BSOD-RCA-Report.txt    ← plain-text copy for tickets
BSOD-RCA-Data.json     ← raw structured data
dumps\                 ← copied minidumps (≤500 MB each)
```

Share the whole folder when escalating. The HTML is usually enough for triage; include `dumps\` when you want someone to open WinDbg.

## How to read the assessment

| Confidence | What it usually means |
|------------|------------------------|
| **High** | Repeated same stop code, or bugcheck + WHEA/disk correlation |
| **Medium** | Clear bugcheck with a known category, limited corroboration |
| **Low** | Sparse data, unknown code, or only Kernel-Power 41 with no dump |

If the report says dumps are missing or disabled, fix dump settings, reproduce once, and re-run. The second pass is much stronger.

## Deeper dump analysis (optional)

This script does not replace WinDbg. For the exact faulting module:

1. Install **WinDbg Preview** from the Microsoft Store.
2. Open the newest `.dmp` from the report's `dumps\` folder.
3. Run:

```text
!analyze -v
```

## Requirements and limits

- **Admin recommended.** Non-admin still runs with reduced event/dump visibility.
- Offline and dependency-free by design.
- Does not install software or change crash dump settings.
- First-pass RCA only — hardware faults and obscure drivers may still need dump analysis or vendor tools.

## Sharing checklist

- [ ] Send `Invoke-BlueScreenRCA.ps1` + `Run-BlueScreenRCA.cmd` together
- [ ] Ask them to run elevated
- [ ] Ask for the full `BSOD-RCA-*` Desktop folder back
- [ ] Open `BSOD-RCA-Report.html` first
- [ ] If needed, open the newest dump in WinDbg with `!analyze -v`
