#Requires -RunAsAdministrator
<#
.SYNOPSIS
    GUI-enhanced tool to force Windows Update and Driver updates.

.DESCRIPTION
    Provides a visual status indicator (WinForms) while orchestrating 
    Windows Update via the COM interface:
    1. Temporarily enables 'Microsoft Update' as the source.
    2. Stops 'pangps' (Palo Alto GlobalProtect) to prevent network interference.
    3. Scans for all missing updates (MachineOnly + Third Party).
    4. Downloads and Installs updates.
    5. Displays real-time progress on a UI label.
    6. Re-enables policy-driven update sources and restarts 'pangps'.
    7. Returns exit code 3010 if a reboot is required.

.NOTES
#>

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# 1. UI Setup
$form = New-Object Windows.Forms.Form -Property @{ Text='WUfB Force Update'; Size='300,100'; StartPosition='CenterScreen' }
$label = New-Object Windows.Forms.Label -Property @{ Location='10,20'; Size='280,20'; Text='Starting...' }
$form.Controls.Add($label)
$form.Show()

function Update-Status($msg) { $label.Text = $msg; $form.Refresh(); Write-Host $msg }

# 2. Config & Preparation
$reg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
Update-Status "Setting Update Policy..."
Set-ItemProperty $reg -Name "SetPolicyDrivenUpdateSourceForQualityUpdates" -Value 0
Stop-Service -Name pangps -Force -ErrorAction SilentlyContinue

# 3. WU Search & Deploy
$manager = New-Object -ComObject Microsoft.Update.ServiceManager
$manager.AddService2("7971f918-a847-4430-9279-4a52d1efe18d", 7, "")

$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$searcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'
$searcher.ServerSelection = 3

Update-Status "Scanning for updates..."
$results = $searcher.Search("IsInstalled=0")
Update-Status "Found $($results.Updates.Count) updates. Downloading..."

$downloader = $session.CreateUpdateDownloader()
$downloader.Updates = $results.Updates
$downloader.Download()

Update-Status "Installing updates..."
$installer = $session.CreateUpdateInstaller()
$installer.Updates = $results.Updates
$installResult = $installer.Install()

# 4. Cleanup
Set-ItemProperty $reg -Name "SetPolicyDrivenUpdateSourceForQualityUpdates" -Value 1
Start-Service -Name pangps -ErrorAction SilentlyContinue
$form.Close()

if ($installResult.RebootRequired) { exit 3010 } else { exit 0 }
