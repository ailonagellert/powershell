<#
.SYNOPSIS
    Cleans up orphaned (unused) drivers from the SCCM console.

.DESCRIPTION
    A maintenance utility for SCCM admins:
    1. Queries WMI (SMS_Driver) for all imported drivers.
    2. Identifies drivers that are NOT associated with any 
       'SMS_DriverContainer' (i.e., not in a Driver Package).
    3. Exports the list of orphaned drivers to CSV for archival.
    4. Automatically removes the orphaned drivers from the SCCM site 
       to reduce metadata bloat and console clutter.

.NOTES
    Original Filename: AutoSaved_dd0ed459-215b-444c-a90a-313cdd2fb107_Untitled553.ps1
#>

<#
.Synopsis
   This script queries Configuration Manager 2012 Drivers that are not related with any Driver Packages
.DESCRIPTION
.EXAMPLE
    Get-CMUnusedDrivers.ps1 -SiteCode PS1 -SiteServer CM01
.NOTES
    Developed By Johan Arwidmark and Kaido Järvemets
    Version 1.0
#>
[CMDLETBINDING()]
Param(
    ##[Parameter(Mandatory=$True,HelpMessage="dalpsccm21")]
        $SiteServer ="dalpsccm21",
    ##[Parameter(Mandatory=$True,HelpMessage="s21")]
        $SiteCode ="s21"
    )

Try{
    $DriverAr = @()
    $Drivers = Get-WmiObject -Namespace "ROOT\SMS\site_$($SiteCode)" -Class SMS_Driver -ErrorAction STOP -ComputerName $SiteServer
    foreach($Item in $Drivers){
        Try{
            $Query = Get-WmiObject -Namespace "ROOT\SMS\site_$($SiteCode)" -Query "select * from SMS_Driver where CI_ID not in(select CI_ID from SMS_DriverContainer where CI_ID='$($item.CI_ID)') and CI_ID='$($item.CI_ID)'" -ErrorAction STOP -ComputerName $SiteServer
                if(($Query | Measure-Object | Select-Object -ExpandProperty Count) -ne 0){
                    $DObject = New-Object PSOBJECT
                        $DObject | Add-Member -MemberType NoteProperty -Name "CI_ID" -Value $Query.CI_ID
                        $DObject | Add-Member -MemberType NoteProperty -Name "LocalizedDisplayName" -Value $Query.LocalizedDisplayName
                        $DObject | Add-Member -MemberType NoteProperty -Name "ContentSourcePath" -Value $Query.ContentSourcePath
                    $DriverAr += $DObject
                }
        }
        Catch{
            $_.Exception.Message
        }

    }
    $DriverAr
}
Catch{
    $_.Exception.Message
}
$driverar | Export-Csv -Path d:\drivercleanup.csv
foreach ($d in $DriverAr) {
Write-Host "removing" $d.CI_ID "-"$d.LocalizedDisplayName
get-cmdriver -Id $d.ci_id | Remove-CMDriver  -Force -Verbose -ErrorAction Continue }

Get-CMCategory -CategoryType DriverCategories -name dell*
Get-CMDriver -AdministrativeCategory 
Remove-CMCategory -Id -Force
