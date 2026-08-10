<#
.SYNOPSIS
    Audits Windows Defender registry settings across all policy layers.

.DESCRIPTION
    A comprehensive audit tool that checks Defender configurations in:
    1. Group Policy (HKLM\...\Policies\Microsoft\Windows Defender)
    2. MDM Policy (HKLM\...\Policy Manager)
    3. Local Machine (HKLM\SOFTWARE\Microsoft\Windows Defender)
    Ensures visibility into which layer is overriding the antivirus 
    behavior.

.NOTES
#>

$paths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager",
    "HKLM:\SOFTWARE\Microsoft\Windows Defender"
)

foreach ($p in $paths) {
    Write-Host "`n--- Path: $p ---" -ForegroundColor Cyan
    if (Test-Path $p) {
        Get-ItemProperty $p | Select-Object * -ExcludeProperty PSPath, PSParentPath, PSChildName, PSDrive, PSProvider | 
                              Format-List
    } else {
        Write-Host "No settings found." -ForegroundColor Gray
    }
}
