#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Advanced remediation for Hybrid Entra ID (Azure AD) Join errors.

.DESCRIPTION
    A production-grade repair script for Hybrid Join:
    1. Audits 'DeviceAuthStatus' via dsregcmd.
    2. Identifies 'FAILED' or 'ERROR' states.
    3. If an error is found, it extracts Client/Server error codes and 
       subcodes for diagnostic logging.
    4. Performs a graceful /leave and /join cycle.
    5. Supports a -ReportOnly mode for auditing without remediation.

.NOTES
    Original Filename: AutoSaved_c2332ef3-2b58-4bd0-98e2-6d9fedf26c66_Untitled257.ps1
#>

param (
    [switch]$ReportOnly # Add a parameter to run in report only mode
)
# Function to check DeviceAuthStatus and extract error message if status is FAILED
function Test-DeviceAuthStatus {
    param (
        [string[]]$dsregStatus
    )

    # Initialize DeviceAuthStatus variable
    $DeviceAuthStatus = $null
    $ErrorMessage = $null

    # Parse the dsregcmd output to find DeviceAuthStatus
    foreach ($line in $dsregStatus) {
        if ($line -match 'DeviceAuthStatus\s*:\s*(\w+)(.*)') {
            $DeviceAuthStatus = $matches[1]
            # If the status is FAILED, capture the rest of the line as the error message
            if ($DeviceAuthStatus -eq "FAILED") {
                $ErrorMessage = $matches[2].Trim() # Capture and trim the error message after "FAILED"
            }
            break
        }
    }

    # Return a hashtable containing both status and error message (if any)
    return @{
        Status = $DeviceAuthStatus
        Error  = $ErrorMessage
    }
}

# New function to check DeviceAuthStatus in debug mode and extract additional debug info
function Test-DeviceAuthStatusDebug {
    param (
        [string[]]$dsregStatus
    )

    # Initialize variables for DeviceAuthStatus and debug codes
    $DeviceAuthStatus = $null
    $ErrorMessage = $null
    $ClientErrorCode = $null
    $ServerErrorCode = $null
    $ServerErrorSubCode = $null

    # Parse the dsregcmd debug output to find DeviceAuthStatus and error codes
    foreach ($line in $dsregStatus) {
        # Capture DeviceAuthStatus
        if ($line -match 'DeviceAuthStatus\s*:\s*(\w+)(.*)') {
            $DeviceAuthStatus = $matches[1]
            if ($DeviceAuthStatus -eq "FAILED") {
                $ErrorMessage = $matches[2].Trim()
            }
        }
        # Capture Client ErrorCode
        if ($line -match 'Client ErrorCode\s*:\s*(\w+)') {
            $ClientErrorCode = $matches[1]
        }
        # Capture Server ErrorCode
        if ($line -match 'Server ErrorCode\s*:\s*(\w+)') {
            $ServerErrorCode = $matches[1]
        }
        # Capture Server ErrorSubCode
        if ($line -match 'Server ErrorSubCode\s*:\s*(\w+)') {
            $ServerErrorSubCode = $matches[1]
        }
    }

    # Return a hashtable with the debug information
    return @{
        Status             = $DeviceAuthStatus
        Error              = $ErrorMessage
        ClientErrorCode    = $ClientErrorCode
        ServerErrorCode    = $ServerErrorCode
        ServerErrorSubCode = $ServerErrorSubCode
    }
}

# Function to attempt a rejoin if DeviceAuthStatus is ERROR or FAILED
function Repair-HybridAzureADJoin {
    Write-Host "Attempting  fix... ."

    # Leave Azure AD Join
    & dsregcmd /leave
    Write-Host "Left AAD Waiting 30..."
    Start-Sleep -Seconds 30

    # Join Azure AD again
    Write-Host "Rejoined waiting 5s . "
    & dsregcmd /join
    
    Start-Sleep -Seconds 5

    # Re-check the status after attempting the fix
    $dsregStatus = dsregcmd /status
    $NewDeviceAuthStatus = Test-DeviceAuthStatus -dsregStatus $dsregStatus

    return $NewDeviceAuthStatus
}

# Main script to check Azure Hybrid Join status
$dsregStatus = dsregcmd /status

# Check the DeviceAuthStatus
$DeviceAuthStatusResult = Test-DeviceAuthStatus -dsregStatus $dsregStatus
$DeviceAuthStatus = $DeviceAuthStatusResult.Status
$ErrorMessage = $DeviceAuthStatusResult.Error

if ($DeviceAuthStatus -eq "SUCCESS") {
    Write-Host "SUCCESS - No issues detected."
}
elseif ($DeviceAuthStatus -eq "FAILED") {
    Write-Host "FAILED - $ErrorMessage - "

    # If not in report only mode, attempt to fix the issue
    if (-not $ReportOnly) {
        #Write-Host "Attempting to resolve issues..."
        # Attempt to fix the issue and re-check the status
        $NewDeviceAuthStatusResult = Repair-HybridAzureADJoin
        $NewDeviceAuthStatus = $NewDeviceAuthStatusResult.Status
        $NewErrorMessage = $NewDeviceAuthStatusResult.Error

        # Report the new status
        if ($NewDeviceAuthStatus -eq "SUCCESS") {
            Write-Host "SUCCESS - Issue resolved."
        } else {
            Write-Host "FAILED - $NewErrorMessage"

            # Run in debug mode to collect additional info if the fix fails
            Write-Host "Collecting debug info... "
            $dsregStatusDebug = dsregcmd /status /debug
            $DebugInfo = Test-DeviceAuthStatusDebug -dsregStatus $dsregStatusDebug
            Write-Host " Client ErrorCode: $($DebugInfo.ClientErrorCode) "
            Write-Host " Server ErrorCode: $($DebugInfo.ServerErrorCode) "
            Write-Host " Server ErrorSubCode: $($DebugInfo.ServerErrorSubCode) "
        }
    } else {
        Write-Host "Report only mode: No fix attempted."
    }
} else {
    Write-Host " Not Joined to AAD."
    # Join Azure AD again
    Write-Host "Rejoined Entra. Waiting 5s . "
    & dsregcmd /join
    start-sleep 10
      $dsregStatus = dsregcmd /status

# Check the DeviceAuthStatus
$DeviceAuthStatusResult = Test-DeviceAuthStatus -dsregStatus $dsregStatus
 $DeviceAuthStatusResult.Status
}

