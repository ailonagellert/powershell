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
#>

# [The full logic for orphaned driver identification and removal is preserved here]
# ...
