<#
.SYNOPSIS
    Professional auditor for SCCM-to-Intune application migration.

.DESCRIPTION
    The definitive version of the SCCM migration auditor:
    1. Parses 'SDMPackageXML' from SCCM applications to extract:
       - Install/Uninstall command lines.
       - Content UNC paths.
       - Detection method definitions (Scripts/MSIs).
    2. Cross-references each app against an existing Intune content 
       library share (fuzzy matching).
    3. Validates if the app meets all Intune Win32 requirements.
    4. Generates a comprehensive CSV report indicating migration readiness 
       and whether content is already staged.

.NOTES
    Original Filename: AutoSaved_cb049a32-9fee-4ddd-9b6d-98f52ebc10f0_Untitled639.ps1
#>

<#
.SYNOPSIS
    Validates deployed SCCM applications for Intune migration using SDMPackageXML parsing.
.DESCRIPTION
    1. Gets all deployed SCCM applications (where NumberOfDeployments > 0)
    2. Parses SDMPackageXML to extract:
       - Install/Uninstall command lines
       - Content locations
       - Detection methods
    3. Checks deployment intent (Required/Available)
    4. Checks if app already exists in Intune source files
    5. Validates if apps are suitable for Intune Win32 migration
    6. Exports results to CSV
.PARAMETER SCCMSiteServer
    The SCCM site server name.
.PARAMETER SCCMSiteCode
    The SCCM site code.
.PARAMETER OutputPath
    CSV file path for export.
.PARAMETER SkipPathValidation
    Skip validating if UNC paths exist (useful for remote execution)
.PARAMETER IntuneSourcePath
    Base path for Intune application source files
#>

[CmdletBinding()]
param(
    [string]$SCCMSiteServer = "dalpsccm21.corp.local",
    [string]$SCCMSiteCode   = "S21",
    [string]$OutputPath     = "c:\temp\ValidForIntune5.csv",
    [switch]$SkipPathValidation,
    [string]$IntuneSourcePath = "\\dalpsccm22\intune\Applications"
)

function Import-SCCMModule {
    Write-Verbose "Attempting to import SCCM module..."
    $PossiblePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft Configuration Manager\AdminConsole\bin",
        "${env:ProgramFiles}\Microsoft Configuration Manager\AdminConsole\bin",
        "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin",
        "C:\Program Files\Microsoft Configuration Manager\AdminConsole\bin",
        "D:\Program Files\Microsoft Configuration Manager\AdminConsole\bin"
    )
    foreach ($Path in $PossiblePaths) {
        if (Test-Path "$Path\ConfigurationManager.psd1") {
            try {
                Write-Verbose "Found module at: $Path"
                Import-Module "$Path\ConfigurationManager.psd1" -Force -ErrorAction Stop
                return $true
            } catch {
                Write-Verbose "Failed to load from $Path"
            }
        }
    }
    return $false
}

function Test-UNCPath {
    param(
        [string]$Path
    )
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    
    # If path validation is skipped, assume UNC paths are valid
    if ($SkipPathValidation -and $Path.StartsWith("\\")) {
        Write-Verbose "Skipping path validation for UNC path: $Path"
        return $true
    }
    
    try {
        # For UNC paths, try to test with different methods
        if ($Path.StartsWith("\\")) {
            Write-Verbose "Testing UNC path: $Path"
            
            # Method 1: Try direct Test-Path
            if (Test-Path $Path -ErrorAction SilentlyContinue) {
                Write-Verbose "UNC path accessible: $Path"
                return $true
            }
            
            # Method 2: Try to resolve the path
            try {
                $resolvedPath = Resolve-Path $Path -ErrorAction Stop
                Write-Verbose "UNC path resolved: $Path"
                return $true
            } catch {
                Write-Verbose "Could not resolve UNC path: $Path - $($_.Exception.Message)"
            }
            
            # Method 3: Try Get-Item
            try {
                $item = Get-Item $Path -ErrorAction Stop
                Write-Verbose "UNC path accessible via Get-Item: $Path"
                return $true
            } catch {
                Write-Verbose "Could not access UNC path via Get-Item: $Path - $($_.Exception.Message)"
            }
            
            return $false
        } else {
            # Local path
            return Test-Path $Path
        }
    } catch {
        Write-Verbose "Error testing path $Path : $($_.Exception.Message)"
        return $false
    }
}

function Get-AppDeploymentInfo {
    param(
        [string]$AppName
    )
    
    Write-Verbose "Getting deployment info for: $AppName"
    set-location S21:
    try {
        $Deployments = Get-CMDeployment -SoftwareName $AppName
        
        if (-not $Deployments) {
            return @{
                DeploymentIntent = "None"
                DeploymentIntentSummary = "No deployments found"
                DeploymentCount = 0
            }
        }
        
        # Analyze all deployments for this app
        $RequiredCount = ($Deployments | Where-Object { $_.DeploymentIntent -eq 1 }).Count
        $AvailableCount = ($Deployments | Where-Object { $_.DeploymentIntent -eq 2 }).Count
        
        # Create summary
        $IntentSummary = @()
        if ($RequiredCount -gt 0) { $IntentSummary += "Required ($RequiredCount)" }
        if ($AvailableCount -gt 0) { $IntentSummary += "Available ($AvailableCount)" }
        
        # Determine primary intent (Required takes precedence)
        $PrimaryIntent = if ($RequiredCount -gt 0) { "Required" } 
                        elseif ($AvailableCount -gt 0) { "Available" } 
                        else { "Unknown" }
        
        return @{
            DeploymentIntent = $PrimaryIntent
            DeploymentIntentSummary = $IntentSummary -join ", "
            DeploymentCount = $Deployments.Count
        }
        
    } catch {
        Write-Verbose "Error getting deployment info: $($_.Exception.Message)"
        return @{
            DeploymentIntent = "Error"
            DeploymentIntentSummary = "Error retrieving deployment info"
            DeploymentCount = 0
        }
    }
}

function Test-IntuneAppExists {
    param(
        [string]$AppName,
        [string]$Manufacturer,
        [string]$Version,
        [string]$IntuneBasePath
    )
    
    Write-Verbose "Checking if app exists in Intune source files: $AppName"
    Set-Location c:
    if (-not (Test-Path $IntuneBasePath)) {
        Write-Verbose "Intune base path not accessible: $IntuneBasePath"
        return @{
            Exists = $false
            Status = "Base path not accessible"
            FoundPath = ""
            FoundVersion = ""
        }
    }
    
    try {
        # Get all publishers
        $publishers = Get-ChildItem -Path $IntuneBasePath -Directory -ErrorAction SilentlyContinue
        
        $foundResults = @()
        
        foreach ($publisher in $publishers) {
            Write-Verbose "Checking publisher: $($publisher.Name)"
            
            # Check for exact manufacturer match first
            $manufacturerMatch = $false
            if (-not [string]::IsNullOrWhiteSpace($Manufacturer)) {
                $manufacturerMatch = $publisher.Name -like "*$Manufacturer*" -or $Manufacturer -like "*$($publisher.Name)*"
            }
            
            # Get applications under this publisher
            $applications = Get-ChildItem -Path $publisher.FullName -Directory -ErrorAction SilentlyContinue
            
            foreach ($app in $applications) {
                Write-Verbose "Checking application: $($app.Name)"
                
                # Check for app name match (fuzzy matching)
                $appNameMatch = $app.Name -like "*$AppName*" -or $AppName -like "*$($app.Name)*"
                
                if ($appNameMatch -or $manufacturerMatch) {
                    # Get versions under this application
                    $versions = Get-ChildItem -Path $app.FullName -Directory -ErrorAction SilentlyContinue | 
                               Where-Object { $_.Name -match '^\d+(\.\d+)*' }
                    
                    foreach ($ver in $versions) {
                        $foundResults += @{
                            PublisherName = $publisher.Name
                            ApplicationName = $app.Name
                            Version = $ver.Name
                            FullPath = $ver.FullName
                            MatchType = if ($appNameMatch -and $manufacturerMatch) { "Exact" } 
                                       elseif ($appNameMatch) { "App Name" } 
                                       else { "Manufacturer" }
                            VersionMatch = $ver.Name -eq $Version
                        }
                    }
                }
            }
        }
        
        if ($foundResults.Count -eq 0) {
            return @{
                Exists = $false
                Status = "Not found"
                FoundPath = ""
                FoundVersion = ""
                MatchDetails = ""
            }
        }
        
        # Check for exact version match
        $exactVersionMatch = $foundResults | Where-Object { $_.VersionMatch -eq $true }
        if ($exactVersionMatch) {
            $match = $exactVersionMatch[0]
            return @{
                Exists = $true
                Status = "Exact version match"
                FoundPath = "$($match.PublisherName)\$($match.ApplicationName)\$($match.Version)"
                FoundVersion = $match.Version
                MatchDetails = "Exact match: $($match.MatchType)"
            }
        }
        
        # Check for app match with different version
        $appMatch = $foundResults | Sort-Object { 
            try { [System.Version]$_.Version } 
            catch { $_.Version } 
        } -Descending | Select-Object -First 1
        
        if ($appMatch) {
            return @{
                Exists = $true
                Status = "Different version"
                FoundPath = "$($appMatch.PublisherName)\$($appMatch.ApplicationName)\$($appMatch.Version)"
                FoundVersion = $appMatch.Version
                MatchDetails = "App exists with version $($appMatch.Version) ($($appMatch.MatchType) match)"
            }
        }
        
        return @{
            Exists = $false
            Status = "Not found"
            FoundPath = ""
            FoundVersion = ""
            MatchDetails = ""
        }
        
    } catch {
        Write-Verbose "Error checking Intune app existence: $($_.Exception.Message)"
        return @{
            Exists = $false
            Status = "Error checking"
            FoundPath = ""
            FoundVersion = ""
            MatchDetails = "Error: $($_.Exception.Message)"
        }
    }
}

function Parse-DetectionMethod {
    param(
        [object]$DeploymentType
    )
    
    Write-Verbose "Parsing detection method"
    
    if (-not $DeploymentType.Installer.DetectAction.Args.Arg) {
        return "No detection method configured"
    }
    
    $methodBody = $DeploymentType.Installer.DetectAction.Args.Arg | Where-Object { $_.Name -eq "MethodBody" }
    
    if (-not $methodBody -or [string]::IsNullOrWhiteSpace($methodBody.'#text')) {
        return "No detection method configured"
    }
    
    try {
        # Parse the MethodBody XML to understand the detection type
        [xml]$detectionXML = $methodBody.'#text'
        
        $detectionDetails = @()
        
        # Check for different types of detection methods
        if ($detectionXML.EnhancedDetectionMethod.Settings.SimpleSetting) {
            foreach ($setting in $detectionXML.EnhancedDetectionMethod.Settings.SimpleSetting) {
                switch ($setting.GetType().Name) {
                    default {
                        # Check for registry detection
                        if ($setting.RegistryDiscoverySource) {
                            $regHive = $setting.RegistryDiscoverySource.Hive
                            $regKey = $setting.RegistryDiscoverySource.Key
                            $regValue = $setting.RegistryDiscoverySource.ValueName
                            $detectionDetails += "Registry: $regHive\$regKey\$regValue"
                        }
                        # Check for file detection
                        elseif ($setting.FileDiscoverySource) {
                            $filePath = $setting.FileDiscoverySource.Path
                            $fileName = $setting.FileDiscoverySource.FileName
                            $detectionDetails += "File: $filePath\$fileName"
                        }
                        # Check for MSI detection
                        elseif ($setting.MsiDiscoverySource) {
                            $productCode = $setting.MsiDiscoverySource.ProductCode
                            $detectionDetails += "MSI Product Code: $productCode"
                        }
                        # Generic setting
                        else {
                            $detectionDetails += "Custom Setting: $($setting.LogicalName)"
                        }
                    }
                }
            }
        }
        
        # Check for rules
        if ($detectionXML.EnhancedDetectionMethod.Rule) {
            foreach ($rule in $detectionXML.EnhancedDetectionMethod.Rule) {
                if ($rule.Expression.Operator) {
                    $operator = $rule.Expression.Operator
                    $detectionDetails += "Rule: $operator operation"
                }
            }
        }
        
        if ($detectionDetails.Count -gt 0) {
            return $detectionDetails -join "; "
        } else {
            return "Enhanced detection method (details not parsed)"
        }
        
    } catch {
        Write-Verbose "Error parsing detection method XML: $($_.Exception.Message)"
        return "Enhanced detection method (parsing failed)"
    }
}

function Parse-SDMPackageXML {
    param(
        [string]$XMLContent,
        [string]$AppName
    )
    
    Write-Verbose "Parsing SDMPackageXML for: $AppName"
    
    if ([string]::IsNullOrWhiteSpace($XMLContent)) {
        Write-Verbose "No SDMPackageXML content found"
        return $null
    }
    
    try {
        [xml]$xml = $XMLContent
    } catch {
        Write-Verbose "Failed to parse XML: $($_.Exception.Message)"
        return $null
    }
    
    # Find all deployment types in the XML
    $deploymentTypes = @()
    
    # Check for deployment types under Application node
    if ($xml.AppMgmtDigest.Application.DeploymentTypes.DeploymentType) {
        $appDTReferences = $xml.AppMgmtDigest.Application.DeploymentTypes.DeploymentType
        Write-Verbose "Found $($appDTReferences.Count) deployment type references under Application"
    }
    
    # Get actual deployment type definitions
    if ($xml.AppMgmtDigest.DeploymentType) {
        $deploymentTypes = @($xml.AppMgmtDigest.DeploymentType)
        Write-Verbose "Found $($deploymentTypes.Count) deployment type definitions"
    }
    
    if (-not $deploymentTypes) {
        Write-Verbose "No deployment types found in XML"
        return $null
    }
    
    $results = @()
    
    foreach ($dt in $deploymentTypes) {
        Write-Verbose "Processing deployment type: $($dt.Title.ResourceId)"
        
        # Extract install command line
        $installCmd = ""
        if ($dt.Installer.InstallAction.Args.Arg) {
            $installArg = $dt.Installer.InstallAction.Args.Arg | Where-Object { $_.Name -eq "InstallCommandLine" }
            if ($installArg) {
                $installCmd = $installArg.'#text'
            }
        }
        
        # Extract uninstall command line
        $uninstallCmd = ""
        if ($dt.Installer.UninstallAction.Args.Arg) {
            $uninstallArg = $dt.Installer.UninstallAction.Args.Arg | Where-Object { $_.Name -eq "InstallCommandLine" }
            if ($uninstallArg) {
                $uninstallCmd = $uninstallArg.'#text'
            }
        }
        
        # Extract content locations
        $contentLocations = @()
        if ($dt.Installer.Contents.Content) {
            foreach ($content in $dt.Installer.Contents.Content) {
                if ($content.Location) {
                    $contentLocations += $content.Location
                }
            }
        }
        
        # Check for detection method and parse it
        $hasDetectionMethod = $false
        $detectionMethodDetails = "None"
        if ($dt.Installer.DetectAction.Args.Arg) {
            $methodBody = $dt.Installer.DetectAction.Args.Arg | Where-Object { $_.Name -eq "MethodBody" }
            if ($methodBody -and -not [string]::IsNullOrWhiteSpace($methodBody.'#text')) {
                $hasDetectionMethod = $true
                $detectionMethodDetails = Parse-DetectionMethod -DeploymentType $dt
            }
        }
        
        # Get deployment technology
        $deploymentTech = $dt.DeploymentTechnology
        $technology = $dt.Technology
        
        Write-Verbose "  Install Command: $installCmd"
        Write-Verbose "  Uninstall Command: $uninstallCmd"
        Write-Verbose "  Content Locations: $($contentLocations -join '; ')"
        Write-Verbose "  Has Detection Method: $hasDetectionMethod"
        Write-Verbose "  Detection Method Details: $detectionMethodDetails"
        Write-Verbose "  Technology: $technology"
        
        $results += [PSCustomObject]@{
            InstallCommand = $installCmd
            UninstallCommand = $uninstallCmd
            ContentLocations = $contentLocations
            HasDetectionMethod = $hasDetectionMethod
            DetectionMethodDetails = $detectionMethodDetails
            DeploymentTechnology = $deploymentTech
            Technology = $technology
        }
    }
    
    return $results
}

function Test-AppMigratability {
    param(
        [array]$ParsedData,
        [string]$AppName
    )
    
    Write-Verbose "Testing migratability for: $AppName"
    
    if (-not $ParsedData) {
        Write-Verbose "No parsed data available"
        return $false, "No deployment type data", "Unknown"
    }
    
    foreach ($dtData in $ParsedData) {
        # Check if all required components exist
        $hasInstallCmd = -not [string]::IsNullOrWhiteSpace($dtData.InstallCommand)
        $hasUninstallCmd = -not [string]::IsNullOrWhiteSpace($dtData.UninstallCommand)
        $hasValidContent = $false
        $contentStatus = @()
        
        # Check if at least one content location exists
        foreach ($location in $dtData.ContentLocations) {
            if ([string]::IsNullOrWhiteSpace($location)) {
                $contentStatus += "Empty location"
                continue
            }
            
            $pathExists = Test-UNCPath -Path $location
            $contentStatus += "$location : $pathExists"
            
            if ($pathExists) {
                $hasValidContent = $true
            }
        }
        
        Write-Verbose "  Has Install Command: $hasInstallCmd"
        Write-Verbose "  Has Uninstall Command: $hasUninstallCmd"
        Write-Verbose "  Content Status: $($contentStatus -join '; ')"
        Write-Verbose "  Has Valid Content: $hasValidContent"
        Write-Verbose "  Has Detection Method: $($dtData.HasDetectionMethod)"
        
        if ($hasInstallCmd  -and $hasValidContent -and $dtData.HasDetectionMethod) {
            # Determine migration type based on technology and install command
            $migrationType = "Win32"
            
            if ($dtData.Technology -eq "MSI") {
                $migrationType = "Win32 (MSI)"
            } elseif ($dtData.InstallCommand -match "\.msi|msiexec") {
                $migrationType = "Win32 (MSI)"
            } elseif ($dtData.Technology -eq "Script") {
                $migrationType = "Win32 (Script)"
            } elseif ($dtData.InstallCommand -match "\.exe") {
                $migrationType = "Win32 (EXE)"
            }
            
            return $true, "All requirements met", $migrationType
        }
    }
    
    # Determine why it failed
    $reasons = @()
    if (-not ($ParsedData | Where-Object { -not [string]::IsNullOrWhiteSpace($_.InstallCommand) })) {
        $reasons += "No install command"
    }
    if (-not ($ParsedData | Where-Object { -not [string]::IsNullOrWhiteSpace($_.UninstallCommand) })) {
        $reasons += "No uninstall command"
    }
    
    $hasAnyValidContent = $false
    foreach ($dtData in $ParsedData) {
        foreach ($location in $dtData.ContentLocations) {
            if (Test-UNCPath -Path $location) {
                $hasAnyValidContent = $true
                break
            }
        }
        if ($hasAnyValidContent) { break }
    }
    
    if (-not $hasAnyValidContent) {
        $reasons += "No accessible content location"
    }
    if (-not ($ParsedData | Where-Object { $_.HasDetectionMethod })) {
        $reasons += "No detection method"
    }
    
    return $false, ($reasons -join "; "), "Not Suitable"
}

Write-Host "Loading SCCM module..." -ForegroundColor Yellow
if (-not (Import-SCCMModule)) {
    Write-Error "Failed to load Configuration Manager PowerShell module."
    return
}

Write-Host "Connecting to SCCM Site '$SCCMSiteCode' on server '$SCCMSiteServer'..." -ForegroundColor Yellow
if (-not (Get-PSDrive -Name $SCCMSiteCode -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name $SCCMSiteCode -PSProvider CMSite -Root $SCCMSiteServer -ErrorAction Stop | Out-Null
}
Set-Location "$($SCCMSiteCode):"

if ($SkipPathValidation) {
    Write-Host "Path validation is disabled - UNC paths will be assumed valid" -ForegroundColor Yellow
}

Write-Host "Retrieving deployed applications..." -ForegroundColor Cyan
$Apps = Get-CMApplication | Where-Object { $_.NumberOfDeployments -gt 0 }

if (-not $Apps) {
    Write-Host "No deployed applications found." -ForegroundColor Yellow
    return
}

Write-Host "Found $($Apps.Count) deployed applications. Analyzing..." -ForegroundColor Green

$Results = @()
$Counter = 0

foreach ($App in $Apps) {
    $Counter++
    Write-Host "[$Counter/$($Apps.Count)] Processing: $($App.LocalizedDisplayName)" -ForegroundColor Gray
    Write-Verbose "Processing application: $($App.LocalizedDisplayName)"
    
    # Get deployment information
    $DeploymentInfo = Get-AppDeploymentInfo -AppName $App.LocalizedDisplayName
    
    # Check if app exists in Intune source files
    $IntuneExistsInfo = Test-IntuneAppExists -AppName $App.LocalizedDisplayName -Manufacturer $App.Manufacturer -Version $App.SoftwareVersion -IntuneBasePath $IntuneSourcePath
    
    # Parse the SDMPackageXML
    $ParsedData = Parse-SDMPackageXML -XMLContent $App.SDMPackageXML -AppName $App.LocalizedDisplayName
    # Return to original location
    Set-Location C:
    # Test migratability
    $IsMigratable, $Reason, $MigrationType = Test-AppMigratability -ParsedData $ParsedData -AppName $App.LocalizedDisplayName
    
    # Get first valid deployment type data for display
    $FirstDT = $ParsedData | Select-Object -First 1
    
    $Result = [PSCustomObject]@{
        ApplicationName = $App.LocalizedDisplayName
        Manufacturer = $App.Manufacturer
        SoftwareVersion = $App.SoftwareVersion
        NumberOfDeployments = $App.NumberOfDeployments
        DeploymentIntent = $DeploymentInfo.DeploymentIntent
        DeploymentIntentSummary = $DeploymentInfo.DeploymentIntentSummary
        NumberOfDeploymentTypes = $App.NumberOfDeploymentTypes
        IsMigratable = $IsMigratable
        MigrationType = $MigrationType
        Reason = $Reason
        IsMigrated = $IntuneExistsInfo.Exists
        MigrationStatus = $IntuneExistsInfo.Status
        IntuneFoundPath = $IntuneExistsInfo.FoundPath
        IntuneFoundVersion = $IntuneExistsInfo.FoundVersion
        MigrationDetails = $IntuneExistsInfo.MatchDetails
        InstallCommand = if ($FirstDT) { $FirstDT.InstallCommand } else { "" }
        UninstallCommand = if ($FirstDT) { $FirstDT.UninstallCommand } else { "" }
        ContentLocation = if ($FirstDT) { $FirstDT.ContentLocations -join "; " } else { "" }
        Technology = if ($FirstDT) { $FirstDT.Technology } else { "" }
        HasDetectionMethod = if ($FirstDT) { $FirstDT.HasDetectionMethod } else { $false }
        DetectionMethodDetails = if ($FirstDT) { $FirstDT.DetectionMethodDetails } else { "" }
    }
    
    $Results += $Result
    
    # Enhanced console output
    $migrationStatusText = if ($IntuneExistsInfo.Exists) { 
        "[$($IntuneExistsInfo.Status)]" 
    } else { 
        "[Not Migrated]" 
    }
    
    if ($IsMigratable) {
        Write-Host "  ✓ Migratable as $MigrationType [$($DeploymentInfo.DeploymentIntent)] $migrationStatusText" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Not migratable: $Reason [$($DeploymentInfo.DeploymentIntent)] $migrationStatusText" -ForegroundColor Red
    }
    
    if ($IntuneExistsInfo.Exists) {
        Write-Host "    Intune: $($IntuneExistsInfo.FoundPath)" -ForegroundColor Cyan
    }
}

# Export results
Write-Host "`nExporting results to $OutputPath..." -ForegroundColor Yellow
$Results | Export-Csv -Path $OutputPath -NoTypeInformation

# Summary
$MigratableCount = ($Results | Where-Object { $_.IsMigratable }).Count
$TotalCount = $Results.Count
$RequiredCount = ($Results | Where-Object { $_.DeploymentIntent -eq "Required" }).Count
$AvailableCount = ($Results | Where-Object { $_.DeploymentIntent -eq "Available" }).Count
$MigratedCount = ($Results | Where-Object { $_.IsMigrated }).Count
$ExactVersionCount = ($Results | Where-Object { $_.MigrationStatus -eq "Exact version match" }).Count

Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "  Total Applications: $TotalCount" -ForegroundColor White
Write-Host "  Migratable: $MigratableCount" -ForegroundColor Green
Write-Host "  Not Migratable: $($TotalCount - $MigratableCount)" -ForegroundColor Red
Write-Host "  Required Deployments: $RequiredCount" -ForegroundColor Yellow
Write-Host "  Available Deployments: $AvailableCount" -ForegroundColor Yellow
Write-Host "  Already Migrated: $MigratedCount" -ForegroundColor Magenta
Write-Host "  Exact Version Match: $ExactVersionCount" -ForegroundColor Magenta

if ($MigratableCount -gt 0) {
    Write-Host "`nMigratable apps by type:" -ForegroundColor Cyan
    $Results | Where-Object { $_.IsMigratable } | Group-Object MigrationType | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor White
    }
    
    Write-Host "`nMigratable apps by deployment intent:" -ForegroundColor Cyan
    $Results | Where-Object { $_.IsMigratable } | Group-Object DeploymentIntent | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor White
    }
    
    Write-Host "`nMigration status breakdown:" -ForegroundColor Cyan
    $Results | Group-Object MigrationStatus | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor White
    }
}

Write-Host "`nResults exported to: $OutputPath" -ForegroundColor Yellow
Write-Host "Script completed successfully." -ForegroundColor Green
