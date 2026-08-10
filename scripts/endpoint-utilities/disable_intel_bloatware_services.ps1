<#
.SYNOPSIS
    Stops and disables non-essential Intel background services.

.DESCRIPTION
    This optimization script targets Intel-branded services that are often
    unnecessary for core OS functionality and may consume resources or 
    transmit telemetry.
    Services:
    - IDBWM (Intel Dynamic Bandwidth Management)
    - Intel Connectivity Network Service
    - Intel Analytics Service

.NOTES
#>

$services = @(
    'IDBWM',
    'Intel Connectivity Network Service',
    'Intel Analytics Service'
)

foreach ($service in $services) {
    if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
        Write-Host "Disabling service: $service"
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        Set-Service -Name $service -StartupType Disabled
    }
}
