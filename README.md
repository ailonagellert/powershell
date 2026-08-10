# PowerShell Scripts

A curated collection of reusable PowerShell utilities for Windows endpoint management, Entra ID / Active Directory admin work, BIOS / Secure Boot configuration, Windows Update repair, WinRE recovery, and ConfigMgr (SCCM) operations.

Scripts were selected for public usefulness, reviewed to remove secrets and org-specific hardcoding, and organized by category.

## Requirements

- **Windows PowerShell 5.1** or **PowerShell 7+** (most scripts target Windows endpoints)
- Many scripts need an **elevated (Administrator)** session
- Category-specific modules / tools as noted below

| Area | Typical requirements |
|------|----------------------|
| Entra ID | Microsoft Graph PowerShell SDK (`Microsoft.Graph`) and signed-in Graph context |
| Active Directory | `ActiveDirectory` RSAT module |
| BIOS / Secure Boot | Vendor WMI / BIOS providers (HP, Lenovo, Dell); BitLocker cmdlets for suspend flows |
| SCCM / ConfigMgr | ConfigMgr console / PowerShell module on a site server or admin workstation |
| Windows Update / WinRE | Local admin; `DISM`, `reagentc`, related system tools |

> **Important:** Always review a script before running it in production. Several scripts make destructive changes (profile cleanup, partition resize, BIOS settings, client uninstall). Prefer test machines and `-WhatIf` / report-only modes where available.

## Repository layout

```text
scripts/
  entra-id/              Entra ID / hybrid join helpers
  active-directory/      AD computer audits and group/OU utilities
  bios-firmware/         Secure Boot + HP/Lenovo/Dell BIOS helpers
  winre-recovery/        Windows Recovery Environment repair & resize
  windows-update/        Windows Update reset, repair, and policy remediation
  sccm-configmgr/        ConfigMgr client, content, and migration helpers
  security/              Defender status, BitLocker suspend, app cleanup
  endpoint-utilities/    Disk, battery, profiles, diagnostics, Azure VHD prep
```

## Script catalog

### `entra-id/`

| Script | Description |
|--------|-------------|
| `check_hybrid_entra_id_join_status.ps1` | Parse `dsregcmd /status` for hybrid join health |
| `repair_hybrid_entra_id_join_advanced.ps1` | Advanced hybrid join repair workflow |
| `cleanup_stale_entra_id_devices.ps1` | Clean up stale Entra ID device objects |
| `export_stale_entra_id_devices_to_csv.ps1` | Export devices stale past a threshold to CSV |
| `get_entra_id_pending_registration_devices.ps1` | List devices pending registration |
| `remediate_workplace_join_scheduled_tasks.ps1` | Remediate workplace-join related scheduled tasks |
| `audit_ms_graph_copilot_licenses.ps1` | Audit Copilot-related license assignments via Graph |

### `active-directory/`

| Script | Description |
|--------|-------------|
| `add_computers_to_ad_group.ps1` | Add computers to an AD group |
| `audit_stale_ad_computers_parallel.ps1` | Find stale AD computer accounts and ping in parallel |
| `audit_stale_ad_computers_with_ping_validation.ps1` | Stale computer audit with connectivity validation |
| `move_local_computer_to_ad_ou.ps1` | Move the local computer object to a target OU |

### `bios-firmware/`

Secure Boot enablement / remediation for HP and Lenovo, plus Dell / Lenovo BIOS setting helpers, System Interface Foundation installers, and Lenovo System Update automation.

Highlights: `configure_secure_boot.ps1`, `configure_secure_boot_hp_lenovo.ps1`, `manage_dell_bios_settings_*.ps1`, `manage_lenovo_bios_settings.ps1`, `optimize_lenovo_boot_order.ps1`.

### `winre-recovery/`

| Script | Description |
|--------|-------------|
| `get_winre_status.ps1` | Report WinRE status |
| `enable_winre_recovery.ps1` | Enable / restore WinRE |
| `repair_and_register_winre_partition.ps1` | Repair and re-register WinRE |
| `repair_winre_with_network_fallback.ps1` | Repair with network source fallback |
| `resize_winre_partition_to_1gb.ps1` | Grow recovery partition toward 1 GB |
| `recreate_recovery_partition_800mb.ps1` | Recreate an ~800 MB recovery partition |

### `windows-update/`

Reset / repair Windows Update components, remediate update source policies, quiet MSU install, GUI force-update helpers, DISM health checks, and KB4023057 helpers.

Highlights: `reset_windows_update_and_component_store.ps1`, `repair_system_integrity_via_dism.ps1`, `restore_windows_update_connectivity.ps1`, `remediate_windows_update_source_policies.ps1`.

### `sccm-configmgr/`

ConfigMgr client cleanup, baseline evaluation, content distribution remediation, driver orphan cleanup, DataLdr rollback monitoring, task-sequence WMI condition extraction, and SCCM→Intune migration audit helpers.

### `security/`

| Script | Description |
|--------|-------------|
| `get_defender_running_mode.ps1` | Report Microsoft Defender running mode |
| `get_defender_service_status.ps1` | Defender service status |
| `audit_windows_defender_registry_settings.ps1` | Audit Defender-related registry settings |
| `suspend_bitlocker_single_reboot.ps1` | Suspend BitLocker for one reboot |
| `force_uninstall_adobe_reader.ps1` | Force-remove Adobe Reader remnants |

### `endpoint-utilities/`

Everyday endpoint tools: silent Disk Cleanup, stale profile purge, top process diagnostics, battery inventory (including custom WMI), WinSAT disk metrics, Delivery Optimization cache purge, Intel bloatware service disable, RDP enable + firewall, Procmon capture automation, driver folder → WIM capture, and Azure VHD prep.

## Usage

```powershell
# Example: check hybrid join health (run elevated on the endpoint)
cd .\scripts\entra-id
.\check_hybrid_entra_id_join_status.ps1

# Example: Windows Update nuclear reset (elevated; disruptive)
cd .\scripts\windows-update
.\reset_windows_update_and_component_store.ps1
```

If your execution policy blocks local scripts:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
# or
powershell.exe -ExecutionPolicy Bypass -File .\script.ps1
```

## Safety & curation notes

- Secrets, tokens, API keys, certificates, and app registrations were **excluded** (not published).
- Company-specific deployment scripts (internal apps, EPM agents, sensor repair tooling) and machine-specific one-offs were **excluded**.
- Hardcoded personal paths and org DN / UNC values found during review were **removed or parameterized**; remaining scripts still expect you to supply your own group names, OU paths, and Graph context where applicable.
- This is a **curated** set (quality over volume). Many autosaved / unfinished snippets from the source archive were intentionally left out.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

Issues and pull requests that improve safety (parameters, `-WhatIf`, clearer docs) or fix bugs are welcome. Please do not open PRs that add credentials, tenant IDs, or private environment details.
