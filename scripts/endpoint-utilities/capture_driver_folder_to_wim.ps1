<#
.SYNOPSIS
    Captures a driver directory into a WIM file using DISM.

.DESCRIPTION
    A utility function to take a source directory (like a driver repository)
    and create a compressed .wim image of it.
    Default output directory: C:\Drivers\.

.PARAMETER CaptureDir
    The source directory to capture.

.NOTES
#>

function Capture-ImageWithDISM {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaptureDir
    )

    if (-Not (Test-Path -Path $CaptureDir)) {
        Write-Error "Capture directory does not exist: $CaptureDir"
        return
    }

    $folderName = Split-Path -Path $CaptureDir -Leaf
    $wimOutputDir = "C:\Drivers\"
    
    if (-Not (Test-Path -Path $wimOutputDir)) {
        New-Item -ItemType Directory -Path $wimOutputDir | Out-Null
    }

    $imageFilePath = Join-Path -Path $wimOutputDir -ChildPath "$folderName.wim"
    $imageName = "$folderName Drivers"
    $imageDescription = "Captured driver pack for $folderName"

    Write-Host "Capturing $CaptureDir to $imageFilePath..." -ForegroundColor Cyan
    
    # Execute DISM
    & dism.exe /Capture-Image /ImageFile:"$imageFilePath" /CaptureDir:"$CaptureDir" /Name:"$imageName" /Description:"$imageDescription" /Compress:max
}

# Example usage:
# Capture-ImageWithDISM -CaptureDir "C:\DRIVERS\SCCM\tc_m70tsq-m80tsq-m90tsq-p340tiny_w11_21_202204"
