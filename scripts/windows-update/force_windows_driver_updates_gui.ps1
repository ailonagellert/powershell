<#
.SYNOPSIS
    Forces Windows Update to scan and install driver updates via a GUI.

.DESCRIPTION
    This script provides a visual status form while forcing a Windows Update scan specifically for drivers.
    Actions:
    1. Temporarily redirects update sources to Windows Update (bypassing WSUS/SCCM).
    2. Uses MUA (Microsoft Update Agent) COM objects to search for uninstalled drivers.
    3. Downloads and installs found driver updates.
    4. Reports if a reboot is required and logs the result to C:\Windows\CCM\Logs\WinUpdForBusi_01.tag.
    5. Restores original update source policies and restarts GlobalProtect service (pangps) if necessary.

.NOTES
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- UI Setup ---
$form = New-Object System.Windows.Forms.Form
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(400, 150)
$form.Text = 'Windows Driver Update Tool'
$form.TopMost = $true

$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(20, 30)
$label.Size = New-Object System.Drawing.Size(350, 40)
$label.TextAlign = 'MiddleCenter'
$form.Controls.Add($label)

function Update-Status($text) {
    $label.Text = $text
    $form.Refresh()
    Write-Host "[Status] $text"
}

$form.Show()
Update-Status "Initializing..."

# --- Registry Preparation ---
$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
if (-not (Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }

# Force WU as source for Quality, Driver, and Other updates
Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForQualityUpdates" -Value 0
Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForDriverUpdates" -Value 0
Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForOtherUpdates" -Value 0

# --- Update Logic ---
try {
    $UpdateSvc = New-Object -ComObject Microsoft.Update.ServiceManager            
    $UpdateSvc.AddService2("7971f918-a847-4430-9279-4a52d1efe18d", 7, "")     

    $Session = New-Object -ComObject Microsoft.Update.Session           
    $Searcher = $Session.CreateUpdateSearcher() 
    $Searcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'
    $Searcher.ServerSelection = 3 # Third Party (Microsoft Update)

    Update-Status "Scanning for driver updates..."
    $SearchResult = $Searcher.Search("IsInstalled=0 and Type='Driver'")
    $Updates = $SearchResult.Updates

    if ($Updates.Count -eq 0) {
        Update-Status "No driver updates found."
        Start-Sleep -Seconds 3
    } else {
        Update-Status "Downloading $($Updates.Count) updates..."
        $UpdatesToDownload = New-Object -Com Microsoft.Update.UpdateColl
        $Updates | ForEach-Object { $UpdatesToDownload.Add($_) | Out-Null }
        
        $Downloader = $Session.CreateUpdateDownloader()
        $Downloader.Updates = $UpdatesToDownload
        $Downloader.Download()

        Update-Status "Installing updates..."
        $UpdatesToInstall = New-Object -Com Microsoft.Update.UpdateColl
        $Updates | ForEach-Object { if($_.IsDownloaded) { $UpdatesToInstall.Add($_) | Out-Null } }
        
        $Installer = $Session.CreateUpdateInstaller()
        $Installer.Updates = $UpdatesToInstall
        $Result = $Installer.Install()

        $status = if ($Result.RebootRequired) { "Reboot Required" } else { "Success" }
        Update-Status "Installation complete: $status"
        
        $logPath = "C:\Windows\CCM\Logs\WinUpdForBusi_01.tag"
        "$(Get-Date) - Driver Update Result: $($Result.ResultCode) - Reboot: $($Result.RebootRequired)" | Out-File -FilePath $logPath -Append
    }
} catch {
    Update-Status "Error: $($_.Exception.Message)"
    Start-Sleep -Seconds 5
} finally {
    # Restore Policies
    Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForQualityUpdates" -Value 1
    Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForDriverUpdates" -Value 1
    Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForOtherUpdates" -Value 1
    
    # Restart services
    if (Get-Service -Name pangps -ErrorAction SilentlyContinue) { Start-Service -Name pangps }
    $form.Close()
}
