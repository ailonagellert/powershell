#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Forces Windows Update and triggers an SCCM-managed reboot.

.DESCRIPTION
    Orchestrates Windows Update via COM while providing integration with 
    the SCCM (Configuration Manager) reboot coordinator:
    1. Sets update source to Microsoft Update.
    2. Scans, downloads, and installs available updates.
    3. If a reboot is required, it triggers 'CcmRestart.exe' and sets the 
       appropriate SCCM registry keys to ensure the user is notified 
       via the SCCM restart countdown UI.

.NOTES
    Original Filename: AutoSaved_605a331d-ff7c-458c-b8fe-9d9d15978e9a_Untitled270.ps1
#>

$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
Function Restart-ComputerCM {
   if (Test-Path -Path "C:\windows\ccm\CcmRestart.exe"){

      $time = [DateTimeOffset]::Now.ToUnixTimeSeconds()
      $Null = New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -Name 'RebootBy' -Value $time -PropertyType QWord -Force -ea SilentlyContinue;
      $Null = New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -Name 'RebootValueInUTC' -Value 1 -PropertyType DWord -Force -ea SilentlyContinue;
      $Null = New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -Name 'NotifyUI' -Value 1 -PropertyType DWord -Force -ea SilentlyContinue;
      $Null = New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -Name 'HardReboot' -Value 0 -PropertyType DWord -Force -ea SilentlyContinue;
      $Null = New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -Name 'OverrideRebootWindowTime' -Value 0 -PropertyType QWord -Force -ea SilentlyContinue;
      $Null = New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -Name 'OverrideRebootWindow' -Value 0 -PropertyType DWord -Force -ea SilentlyContinue;
      $Null = New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -Name 'PreferredRebootWindowTypes' -Value @("4") -PropertyType MultiString -Force -ea SilentlyContinue;
      $Null = New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -Name 'GraceSeconds' -Value 0 -PropertyType DWord -Force -ea SilentlyContinue;


        $CCMRestart = start-process -FilePath C:\windows\ccm\CcmRestart.exe -NoNewWindow -PassThru
        }
        else {
            Write-Output "No CM Client Found"
        }
    }

   

# Ensure the registry path exists
if (-not (Test-Path -Path $registryPath)) {
    New-Item -Path $registryPath -Force
}

# Set registry values for update settings to 0 (Windows Update)
Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForDriverUpdates" -Value 0
Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForOtherUpdates" -Value 0

$UpdateSvc = New-Object -ComObject Microsoft.Update.ServiceManager            
$UpdateSvc.AddService2("7971f918-a847-4430-9279-4a52d1efe18d",7,"")     

$Session = New-Object -ComObject Microsoft.Update.Session           
$Searcher = $Session.CreateUpdateSearcher() 

$Searcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'
$Searcher.SearchScope =  1 # MachineOnly
$Searcher.ServerSelection = 3 # Third Party
          
#$Criteria = "IsInstalled=0 and Type='Driver'"
$Criteria = "IsInstalled=0"
Write-Host('Searching Missing-Updates...') -Fore Green     
$SearchResult = $Searcher.Search($Criteria)          
$Updates = $SearchResult.Updates
	
#Show available Drivers...
$Updates | select Title, DriverModel, DriverVerDate, Driverclass, DriverManufacturer | fl


$UpdatesToDownload = New-Object -Com Microsoft.Update.UpdateColl
$updates | % { $UpdatesToDownload.Add($_) | out-null }
Write-Host('Downloading Updates...')  -Fore Green
$UpdateSession = New-Object -Com Microsoft.Update.Session
$Downloader = $UpdateSession.CreateUpdateDownloader()
$Downloader.Updates = $UpdatesToDownload
$Downloader.Download()


$UpdatesToInstall = New-Object -Com Microsoft.Update.UpdateColl
$updates | % { if($_.IsDownloaded) { $UpdatesToInstall.Add($_) | out-null } }

Write-Host('Installing Updates...')  -Fore Green
$Installer = $UpdateSession.CreateUpdateInstaller()
$Installer.Updates = $UpdatesToInstall
$InstallationResult = $Installer.Install()
$updateSvc.Services | ? { $_.IsDefaultAUService -eq $false -and $_.ServiceID -eq "7971f918-a847-4430-9279-4a52d1efe18d" } | % { $UpdateSvc.RemoveService($_.ServiceID) }
if($InstallationResult.RebootRequired) { 
    $Date = Get-Date
    Add-Content -Path C:\Windows\CCM\Logs\WinUpdForBusi_01.tag -Value "WUfB  updated $Date. Reboot Required"
    Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForDriverUpdates" -Value 1
Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForOtherUpdates" -Value 1
    Restart-ComputerCM
} 
else { 
    $Date = Get-Date
    Add-Content -Path C:\Windows\CCM\Logs\WinUpdForBusi_01.tag -Value "WUfB updated $Date. Reboot NOT Required"
    Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForDriverUpdates" -Value 1
    Set-ItemProperty -Path $registryPath -Name "SetPolicyDrivenUpdateSourceForOtherUpdates" -Value 1
    Exit 0
}


s
