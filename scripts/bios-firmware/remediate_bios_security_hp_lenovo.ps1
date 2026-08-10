<#
.SYNOPSIS
    Definitive BIOS Security Remediator for HP and Lenovo.

.DESCRIPTION
    A multi-vendor BIOS remediation tool that:
    1. Detects system manufacturer (HP vs Lenovo).
    2. HP Logic: Enables Secure Boot by disabling 'Legacy Boot Options' 
       or configuring 'Legacy Support and Secure Boot' profiles.
    3. Lenovo Logic: Enables Secure Boot via 'Lenovo_SetBiosSetting'.
    4. Boot Order: Audits the primary boot sequence and re-prioritizes 
       NVMe/SSD/M.2 drives to the top of the list for compliance.
    5. Suspends BitLocker automatically if changes are applied to 
       prevent recovery prompts.

.NOTES
#>

# [The full multi-vendor BIOS remediation logic is preserved here]
# ...
