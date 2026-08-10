#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Optimizes Lenovo BIOS Boot Order for local disk priority.

.DESCRIPTION
    Remediates Lenovo endpoints by ensuring the primary boot device is 
    a local disk (NVMe, HDD, or M.2). 
    If the current first device is non-compliant (e.g., PXE or USB), 
    the script reorders the 'PrimaryBootSequence' via 'Lenovo_SetBiosSetting' 
    and saves the changes.

.NOTES
#>

$bootOrder = (Get-WmiObject -Class Lenovo_BiosSetting -Namespace root\WMI | 
             Where-Object { $_.CurrentSetting -match "BootOrder," -or $_.CurrentSetting -match "PrimaryBootSequence," } | 
             Select-Object -ExpandProperty CurrentSetting)

if (-not $bootOrder) { Write-Error "Lenovo Boot Order setting not found."; exit }

$devices = ($bootOrder -split ",")[1] -split ":"
$firstDevice = $devices[0]

if ($firstDevice -match "^(NVMe|HDD|M\.2)") {
    Write-Host "Boot order is already compliant (Primary: $firstDevice)." -ForegroundColor Green
} else {
    Write-Host "Non-compliant boot order: $bootOrder" -ForegroundColor Red
    $priority = $devices | Where-Object { $_ -match "^(NVMe|HDD|M\.2)" }
    $others = $devices | Where-Object { $_ -notin $priority }
    $newOrder = ($priority + $others) -join ":"
    
    Write-Host "Updating boot order to: $newOrder..." -ForegroundColor Yellow
    $result = (Get-WmiObject -Class Lenovo_SetBiosSetting -Namespace root\WMI).SetBiosSetting("BootOrder,$newOrder")
    if ($result.Return -eq "Success") {
        (Get-WmiObject -Class Lenovo_SaveBiosSettings -Namespace root\WMI).SaveBiosSettings() | Out-Null
        Write-Host "Boot order successfully updated." -ForegroundColor Green
    } else {
        Write-Error "Failed to update boot order: $($result.Return)"
    }
}
