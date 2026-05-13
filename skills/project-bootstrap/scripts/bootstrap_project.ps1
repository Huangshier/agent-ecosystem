param(
    [string]$ProjectDir = (Get-Location).Path,
    [string]$HubDir = "$env:USERPROFILE\.agents\knowledge-hub",
    [switch]$OverwriteTemplates,
    [switch]$RefreshUnmodifiedTemplates,
    [switch]$ForceResetScaffold,
    [switch]$AnalyzeMemoryUpgrade,
    [switch]$PlanMemoryUpgrade,
    [switch]$ApplyMemoryUpgrade,
    [switch]$AutoUpgrade,
    [switch]$AnalyzeLanguageMigration,
    [switch]$PlanLanguageMigration,
    [switch]$ApplyLanguageMigration,
    [switch]$ValidateLanguageMigration,
    [switch]$PlanNarrativeMigration,
    [switch]$ApplyNarrativeMigration,
    [switch]$ValidateNarrativeMigration,
    [switch]$SkipMemoryUpgradeAnalysis,
    [string]$UpgradePlan = "",
    [string]$MigrationPlan = "",
    [string]$SourceLanguage = "",
    [string]$TargetLanguage = "",
    [string]$ProjectLanguage = ""
)

$ErrorActionPreference = "Stop"

$memoryUpgradeModeCount = 0
foreach ($modeSwitch in @($AnalyzeMemoryUpgrade, $PlanMemoryUpgrade, $ApplyMemoryUpgrade, $AutoUpgrade)) {
    if ($modeSwitch.IsPresent) {
        $memoryUpgradeModeCount++
    }
}
if ($memoryUpgradeModeCount -gt 1) {
    throw "Choose only one memory upgrade mode: -AnalyzeMemoryUpgrade, -PlanMemoryUpgrade, -ApplyMemoryUpgrade, or -AutoUpgrade."
}
if ($AutoUpgrade.IsPresent -and $SkipMemoryUpgradeAnalysis.IsPresent) {
    throw "-AutoUpgrade cannot be combined with -SkipMemoryUpgradeAnalysis."
}

$languageMigrationModeCount = 0
foreach ($modeSwitch in @($AnalyzeLanguageMigration, $PlanLanguageMigration, $ApplyLanguageMigration, $ValidateLanguageMigration, $PlanNarrativeMigration, $ApplyNarrativeMigration, $ValidateNarrativeMigration)) {
    if ($modeSwitch.IsPresent) {
        $languageMigrationModeCount++
    }
}
if ($languageMigrationModeCount -gt 1) {
    throw "Choose only one language migration mode: -AnalyzeLanguageMigration, -PlanLanguageMigration, -ApplyLanguageMigration, -ValidateLanguageMigration, -PlanNarrativeMigration, -ApplyNarrativeMigration, or -ValidateNarrativeMigration."
}
if ($languageMigrationModeCount -gt 0 -and $memoryUpgradeModeCount -gt 0) {
    throw "Language migration modes cannot be combined with legacy memory upgrade modes."
}
if ($languageMigrationModeCount -gt 0 -and -not [string]::IsNullOrWhiteSpace($ProjectLanguage)) {
    throw "Do not combine -ProjectLanguage first-session scaffold writes with language migration modes. Use -SourceLanguage and -TargetLanguage."
}

$templateModeCount = 0
foreach ($templateModeSwitch in @($OverwriteTemplates, $RefreshUnmodifiedTemplates, $ForceResetScaffold)) {
    if ($templateModeSwitch.IsPresent) {
        $templateModeCount++
    }
}
if ($templateModeCount -gt 1) {
    throw "Choose only one template refresh/reset mode: -RefreshUnmodifiedTemplates, -ForceResetScaffold, or the compatibility -OverwriteTemplates alias."
}
if ($ForceResetScaffold.IsPresent -and $memoryUpgradeModeCount -gt 0) {
    throw "-ForceResetScaffold cannot be combined with memory upgrade modes. Use conservative analyze/plan/apply migration or force reset, not both."
}
if ($ForceResetScaffold.IsPresent -and $languageMigrationModeCount -gt 0) {
    throw "-ForceResetScaffold cannot be combined with language migration modes. Use conservative language migration or force reset, not both."
}

function Join-PathParts {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Children
    )

    $path = $Root
    foreach ($child in $Children) {
        if ([string]::IsNullOrWhiteSpace($child)) {
            continue
        }
        foreach ($segment in @($child -split '[\\/]+')) {
            if (-not [string]::IsNullOrWhiteSpace($segment)) {
                $path = Join-Path $path $segment
            }
        }
    }
    return $path
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Normalize-RelativePath {
    param([string]$Path)
    return (($Path -replace "\\", "/").TrimStart("/"))
}

function Test-ProtectedMemoryPath {
    param([string]$RelativePath)

    $normalized = Normalize-RelativePath -Path $RelativePath
    if ($normalized -eq "AGENTS.md") {
        return $true
    }
    if ($normalized -eq ".agents/AGENTS.md") {
        return $true
    }
    if ($normalized -eq ".agents/process.txt" -or $normalized -eq ".agents/plan.md" -or $normalized -eq ".agents/notes.md") {
        return $true
    }
    if ($normalized.StartsWith(".agents/context/") -or $normalized.StartsWith(".agents/commands/")) {
        return $true
    }
    return $false
}

function Test-ExistingProjectMemory {
    param([string]$Root)

    if (Test-Path -LiteralPath (Join-Path $Root "AGENTS.md")) {
        return $true
    }

    $agentDir = Join-Path $Root ".agents"
    if (-not (Test-Path -LiteralPath $agentDir)) {
        return $false
    }

    $memoryFiles = @(Get-ChildItem -LiteralPath $agentDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $relative = Normalize-RelativePath -Path $_.FullName.Substring($agentDir.Length).TrimStart([char[]]"\/")
        $relative -notlike "_backup/*" -and $relative -notlike "upgrade/*" -and $relative -ne "hub.lock.json"
    })
    return ($memoryFiles.Count -gt 0)
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-PreviousTemplateHashMap {
    param([string]$LockPath)

    $map = @{}
    if (-not (Test-Path -LiteralPath $LockPath)) {
        return $map
    }

    try {
        $lock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
    } catch {
        return $map
    }

    if ($null -eq $lock.template_installed_hashes_sha256) {
        return $map
    }

    foreach ($property in $lock.template_installed_hashes_sha256.PSObject.Properties) {
        $relative = Normalize-RelativePath -Path $property.Name
        if (-not [string]::IsNullOrWhiteSpace($relative) -and $null -ne $property.Value) {
            $map[$relative] = ([string]$property.Value).ToLowerInvariant()
        }
    }

    return $map
}

$script:bootstrapBackupDir = ""
$script:bootstrapBackupStamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$script:bootstrapBackupCount = 0
$script:bootstrapBackupRecords = New-Object 'System.Collections.Generic.List[object]'

function Get-BootstrapBackupDir {
    $agentDir = Join-Path $ProjectDir ".agents"
    Ensure-Dir -Path $agentDir
    if ([string]::IsNullOrWhiteSpace($script:bootstrapBackupDir)) {
        $script:bootstrapBackupDir = Join-Path $agentDir ("_backup\bootstrap-{0}" -f $script:bootstrapBackupStamp)
        Ensure-Dir -Path $script:bootstrapBackupDir
    }
    return $script:bootstrapBackupDir
}

function Backup-ExistingTemplateFile {
    param(
        [string]$Destination,
        [string]$RelativePath
    )

    $backupDir = Get-BootstrapBackupDir
    $backupPath = Join-PathParts $backupDir (Normalize-RelativePath -Path $RelativePath)
    Ensure-Dir -Path (Split-Path -Parent $backupPath)
    Copy-Item -LiteralPath $Destination -Destination $backupPath -Force
    $script:bootstrapBackupCount++
    $script:bootstrapBackupRecords.Add([ordered]@{
        relative_path = Normalize-RelativePath -Path $RelativePath
        backup_path = $backupPath
    }) | Out-Null
}

function Format-EvidenceSection {
    param(
        [string]$Title,
        [array]$Items
    )

    $lines = @()
    $lines += "## $Title"
    if ($Items.Count -lt 1) {
        $lines += "- none"
    } else {
        foreach ($item in $Items) {
            if ($item -is [System.Collections.IDictionary] -and $item.Contains("relative_path")) {
                $lines += ("- {0} -> {1}" -f $item.relative_path, $item.backup_path)
            } else {
                $lines += ("- {0}" -f $item)
            }
        }
    }
    $lines += ""
    return $lines
}

function Write-BootstrapEvidenceReport {
    param(
        [string]$ProjectDirFull,
        [string]$HubDirValue,
        [string]$LockPath,
        [string]$OperationMode,
        [string]$TemplateMode,
        [bool]$Overwrite,
        [bool]$RefreshUnmodified,
        [bool]$ForceReset,
        [bool]$HadExistingMemory,
        [string]$ProjectLanguageValue,
        [array]$Copied,
        [array]$Preserved,
        [array]$Replaced,
        [array]$Skipped,
        [array]$ManualReview,
        [array]$Backup
    )

    $reportDir = Get-BootstrapBackupDir
    $jsonPath = Join-Path $reportDir "bootstrap-evidence.json"
    $markdownPath = Join-Path $reportDir "bootstrap-evidence.md"
    $createdAt = (Get-Date).ToUniversalTime().ToString("o")

    $evidence = [ordered]@{
        schema_version = 1
        created_at_utc = $createdAt
        project_dir = $ProjectDirFull
        hub_dir = $HubDirValue
        lock_file = $LockPath
        operation_mode = $OperationMode
        template_mode = $TemplateMode
        overwrite_templates = $Overwrite
        refresh_unmodified_templates = $RefreshUnmodified
        force_reset_scaffold = $ForceReset
        had_existing_project_memory = $HadExistingMemory
        project_language = $ProjectLanguageValue
        copied = @($Copied)
        preserved = @($Preserved)
        replaced = @($Replaced)
        skipped = @($Skipped)
        manual_review = @($ManualReview)
        backup = @($Backup)
    }

    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $markdown = @()
    $markdown += "# Bootstrap Evidence Report"
    $markdown += ""
    $markdown += "- Created UTC: $createdAt"
    $markdown += "- Project: $ProjectDirFull"
    $markdown += "- Hub: $HubDirValue"
    $markdown += "- Lock file: $LockPath"
    $markdown += "- Operation mode: $OperationMode"
    $markdown += "- Template mode: $TemplateMode"
    $markdown += "- Overwrite templates: $Overwrite"
    $markdown += "- Refresh unmodified templates: $RefreshUnmodified"
    $markdown += "- Force reset scaffold: $ForceReset"
    $markdown += "- Existing project memory detected: $HadExistingMemory"
    if (-not [string]::IsNullOrWhiteSpace($ProjectLanguageValue)) {
        $markdown += "- Project language: $ProjectLanguageValue"
    }
    $markdown += ""
    $markdown += "Preserved files were left unchanged. Manual-review files differed from the current template or prior installed template hash and must be reviewed before any replacement."
    $markdown += ""
    $markdown += Format-EvidenceSection -Title "Preserved" -Items @($Preserved)
    $markdown += Format-EvidenceSection -Title "Replaced" -Items @($Replaced)
    $markdown += Format-EvidenceSection -Title "Skipped" -Items @($Skipped)
    $markdown += Format-EvidenceSection -Title "Manual Review" -Items @($ManualReview)
    $markdown += Format-EvidenceSection -Title "Backup" -Items @($Backup)
    $markdown | Set-Content -LiteralPath $markdownPath -Encoding UTF8

    return [ordered]@{
        json = $jsonPath
        markdown = $markdownPath
    }
}

function Copy-TemplateFile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$RelativePath,
        [bool]$RefreshUnmodified,
        [bool]$ForceReset,
        [hashtable]$PreviousTemplateHashes
    )

    $destinationDir = Split-Path -Parent $Destination
    Ensure-Dir -Path $destinationDir

    if (-not (Test-Path -LiteralPath $Destination)) {
        # Target missing, copy directly
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return "copied"
    }

    # Compare content hash
    $sourceHash = Get-FileSha256 -Path $Source
    $destHash = Get-FileSha256 -Path $Destination

    if ($sourceHash -eq $destHash) {
        # Content identical, skip
        return "skipped-current-template"
    }

    # Content differs
    if ($ForceReset) {
        Backup-ExistingTemplateFile -Destination $Destination -RelativePath $RelativePath
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return "updated"
    }

    if ($RefreshUnmodified) {
        $normalizedRelative = Normalize-RelativePath -Path $RelativePath
        $previousHash = ""
        if ($PreviousTemplateHashes.ContainsKey($normalizedRelative)) {
            $previousHash = [string]$PreviousTemplateHashes[$normalizedRelative]
        }

        if (-not [string]::IsNullOrWhiteSpace($previousHash) -and $destHash -eq $previousHash.ToLowerInvariant()) {
            Backup-ExistingTemplateFile -Destination $Destination -RelativePath $RelativePath
            Copy-Item -LiteralPath $Source -Destination $Destination -Force
            return "updated"
        }

        return "manual-review"
    }

    return "skipped"
}

function Get-TemplateTreeHash {
    param(
        [string]$ProjectRootTemplate,
        [string]$ProjectAgentTemplate
    )

    $records = @()
    $roots = @(
        @{ Label = "project-root"; Path = $ProjectRootTemplate },
        @{ Label = "project-agent"; Path = $ProjectAgentTemplate }
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root.Path)) {
            continue
        }

        Get-ChildItem -LiteralPath $root.Path -Recurse -File |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($root.Path.Length).TrimStart([char[]]"\/")
                $relative = $relative -replace "\\", "/"
                $fileHash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                $records += ("{0}/{1}:{2}" -f $root.Label, $relative, $fileHash)
            }
    }

    $content = $records -join "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $ProjectDir)) {
    throw "Project directory does not exist: $ProjectDir"
}

$languageMigrationScript = Join-PathParts $PSScriptRoot "language_migration.ps1"
if ($AnalyzeLanguageMigration.IsPresent -or $PlanLanguageMigration.IsPresent -or $ApplyLanguageMigration.IsPresent -or $ValidateLanguageMigration.IsPresent -or $PlanNarrativeMigration.IsPresent -or $ApplyNarrativeMigration.IsPresent -or $ValidateNarrativeMigration.IsPresent) {
    if (-not (Test-Path -LiteralPath $languageMigrationScript)) {
        throw "Language migration helper not found: $languageMigrationScript"
    }

    if ($AnalyzeLanguageMigration.IsPresent) {
        & $languageMigrationScript -ProjectDir $ProjectDir -Mode Analyze -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage
    } elseif ($PlanLanguageMigration.IsPresent) {
        & $languageMigrationScript -ProjectDir $ProjectDir -Mode Plan -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage
    } elseif ($ApplyLanguageMigration.IsPresent) {
        & $languageMigrationScript -ProjectDir $ProjectDir -Mode Apply -MigrationPlan $MigrationPlan
    } elseif ($ValidateLanguageMigration.IsPresent) {
        & $languageMigrationScript -ProjectDir $ProjectDir -Mode Validate -MigrationPlan $MigrationPlan
    } elseif ($PlanNarrativeMigration.IsPresent) {
        & $languageMigrationScript -ProjectDir $ProjectDir -Mode PlanNarrative -MigrationPlan $MigrationPlan
    } elseif ($ApplyNarrativeMigration.IsPresent) {
        & $languageMigrationScript -ProjectDir $ProjectDir -Mode ApplyNarrative -MigrationPlan $MigrationPlan
    } else {
        & $languageMigrationScript -ProjectDir $ProjectDir -Mode ValidateNarrative -MigrationPlan $MigrationPlan
    }
    return
}

$templateRoot = Join-PathParts $HubDir "templates"
$projectRootTemplate = Join-PathParts $templateRoot "project-root"
$projectAgentTemplate = Join-PathParts $templateRoot "project-agent"

$missingTemplateFolders = @()
if (-not (Test-Path -LiteralPath $projectRootTemplate)) {
    $missingTemplateFolders += $projectRootTemplate
}
if (-not (Test-Path -LiteralPath $projectAgentTemplate)) {
    $missingTemplateFolders += $projectAgentTemplate
}

if ($missingTemplateFolders.Count -gt 0) {
    $initHubScript = Join-PathParts $PSScriptRoot "init_hub.ps1"
    if (Test-Path -LiteralPath $initHubScript) {
        Write-Warning ("Hub templates missing; initializing hub at {0} from bundled bootstrap assets." -f $HubDir)
        & $initHubScript -HubDir $HubDir | Out-Null
    }
}

if (-not (Test-Path -LiteralPath $projectRootTemplate)) {
    throw "Missing template folder: $projectRootTemplate. Run scripts/init_hub.ps1 -HubDir `"$HubDir`" or install the knowledge-hub repository."
}
if (-not (Test-Path -LiteralPath $projectAgentTemplate)) {
    throw "Missing template folder: $projectAgentTemplate. Run scripts/init_hub.ps1 -HubDir `"$HubDir`" or install the knowledge-hub repository."
}

$copiedCount = 0
$skippedCount = 0
$updatedCount = 0
$manualReviewCount = 0
$copiedPaths = New-Object 'System.Collections.Generic.List[string]'
$skippedPaths = New-Object 'System.Collections.Generic.List[string]'
$preservedPaths = New-Object 'System.Collections.Generic.List[string]'
$replacedPaths = New-Object 'System.Collections.Generic.List[string]'
$manualReviewPaths = New-Object 'System.Collections.Generic.List[string]'
$hadExistingProjectMemory = Test-ExistingProjectMemory -Root $ProjectDir
$projectAgentDir = Join-Path $ProjectDir ".agents"
$lockPath = Join-Path $projectAgentDir "hub.lock.json"
$previousTemplateHashes = Read-PreviousTemplateHashMap -LockPath $lockPath
$installedTemplateHashes = [ordered]@{}
$refreshUnmodifiedMode = ($RefreshUnmodifiedTemplates.IsPresent -or $OverwriteTemplates.IsPresent)
$templateMode = "refresh-missing-templates"
if ($ForceResetScaffold.IsPresent) {
    $templateMode = "force-reset-scaffold"
} elseif ($refreshUnmodifiedMode) {
    $templateMode = "refresh-unmodified-templates"
}

$bootstrapOperationMode = "refresh-missing-templates"
if (-not $hadExistingProjectMemory) {
    $bootstrapOperationMode = "initialize-empty-project"
} elseif ($ForceResetScaffold.IsPresent) {
    $bootstrapOperationMode = "explicit-force-reset"
} elseif ($languageMigrationModeCount -gt 0) {
    $bootstrapOperationMode = "conservative-language-migration"
} elseif ($memoryUpgradeModeCount -gt 0) {
    $bootstrapOperationMode = "conservative-memory-migration"
} elseif ($refreshUnmodifiedMode) {
    $bootstrapOperationMode = "refresh-unmodified-templates"
}

if ($OverwriteTemplates.IsPresent) {
    Write-Warning "-OverwriteTemplates is a compatibility alias for -RefreshUnmodifiedTemplates. It does not overwrite modified project memory. Use -ForceResetScaffold only when discarding scaffold customizations is intentional; replacements remain backup-first."
}
if ($ForceResetScaffold.IsPresent) {
    Write-Warning "-ForceResetScaffold can replace existing scaffold and memory template files. Existing files are backed up under .agents/_backup before replacement. Do not use this for conservative memory migration."
}
if ($refreshUnmodifiedMode -and $hadExistingProjectMemory -and $previousTemplateHashes.Count -lt 1) {
    Write-Warning "No prior template hash manifest was found; modified existing files will be preserved for manual review instead of being refreshed."
}

function Record-InstalledTemplateHash {
    param(
        [string]$RelativePath,
        [string]$Destination,
        [string]$Result
    )

    $normalized = Normalize-RelativePath -Path $RelativePath
    if ($Result -eq "copied" -or $Result -eq "updated" -or $Result -eq "skipped-current-template") {
        if (Test-Path -LiteralPath $Destination) {
            $installedTemplateHashes[$normalized] = Get-FileSha256 -Path $Destination
        }
    } elseif ($previousTemplateHashes.ContainsKey($normalized)) {
        $installedTemplateHashes[$normalized] = [string]$previousTemplateHashes[$normalized]
    }
}

Get-ChildItem -Path $projectRootTemplate -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($projectRootTemplate.Length).TrimStart([char[]]"\/")
    $destination = Join-Path $ProjectDir $relative
    $normalizedRelative = Normalize-RelativePath -Path $relative
    $result = Copy-TemplateFile -Source $_.FullName -Destination $destination -RelativePath $normalizedRelative -RefreshUnmodified $refreshUnmodifiedMode -ForceReset $ForceResetScaffold.IsPresent -PreviousTemplateHashes $previousTemplateHashes
    Record-InstalledTemplateHash -RelativePath $normalizedRelative -Destination $destination -Result $result
    if ($result -eq "copied") {
        $copiedCount++
        $copiedPaths.Add($normalizedRelative) | Out-Null
    }
    elseif ($result -eq "updated") {
        $updatedCount++
        $replacedPaths.Add($normalizedRelative) | Out-Null
    }
    elseif ($result -eq "manual-review") {
        $skippedCount++
        $manualReviewCount++
        $manualReviewPaths.Add($normalizedRelative) | Out-Null
        $preservedPaths.Add($normalizedRelative) | Out-Null
    }
    else {
        $skippedCount++
        $skippedPaths.Add($normalizedRelative) | Out-Null
        $preservedPaths.Add($normalizedRelative) | Out-Null
    }
}

Ensure-Dir -Path $projectAgentDir

Get-ChildItem -Path $projectAgentTemplate -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($projectAgentTemplate.Length).TrimStart([char[]]"\/")
    $destination = Join-Path $projectAgentDir $relative
    $normalizedRelative = Normalize-RelativePath -Path (Join-Path ".agents" $relative)
    $result = Copy-TemplateFile -Source $_.FullName -Destination $destination -RelativePath $normalizedRelative -RefreshUnmodified $refreshUnmodifiedMode -ForceReset $ForceResetScaffold.IsPresent -PreviousTemplateHashes $previousTemplateHashes
    Record-InstalledTemplateHash -RelativePath $normalizedRelative -Destination $destination -Result $result
    if ($result -eq "copied") {
        $copiedCount++
        $copiedPaths.Add($normalizedRelative) | Out-Null
    }
    elseif ($result -eq "updated") {
        $updatedCount++
        $replacedPaths.Add($normalizedRelative) | Out-Null
    }
    elseif ($result -eq "manual-review") {
        $skippedCount++
        $manualReviewCount++
        $manualReviewPaths.Add($normalizedRelative) | Out-Null
        $preservedPaths.Add($normalizedRelative) | Out-Null
    }
    else {
        $skippedCount++
        $skippedPaths.Add($normalizedRelative) | Out-Null
        $preservedPaths.Add($normalizedRelative) | Out-Null
    }
}

$git = Get-Command git -ErrorAction SilentlyContinue
$hubCommit = "UNKNOWN"
$hubBranch = "UNKNOWN"
$hubRemote = ""
$hubDirty = $false
if ($null -ne $git) {
    try {
        $commitProbe = (& git -C $HubDir rev-parse --verify HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($commitProbe)) {
            $hubCommit = $commitProbe.Trim()
        }
    } catch {}

    try {
        $branchProbe = (& git -C $HubDir rev-parse --abbrev-ref HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branchProbe)) {
            $hubBranch = $branchProbe.Trim()
        }
    } catch {}

    try {
        $remoteProbe = (& git -C $HubDir config --get remote.origin.url 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($remoteProbe)) {
            $hubRemote = $remoteProbe.Trim()
        }
    } catch {}

    try {
        $dirtyProbe = (& git -C $HubDir status --porcelain 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($dirtyProbe)) {
            $hubDirty = $true
        }
    } catch {}
}

$templateTreeHash = Get-TemplateTreeHash -ProjectRootTemplate $projectRootTemplate -ProjectAgentTemplate $projectAgentTemplate

$languageResult = $null
if (-not [string]::IsNullOrWhiteSpace($ProjectLanguage)) {
    $languageScript = Join-PathParts $PSScriptRoot "set_project_language.ps1"
    if (-not (Test-Path -LiteralPath $languageScript)) {
        throw "Project language helper not found: $languageScript"
    }
    $languageParams = @{
        ProjectDir = $ProjectDir
        ProjectLanguage = $ProjectLanguage
    }
    if (-not $hadExistingProjectMemory) {
        $languageParams.OverwriteScaffold = $true
        $languageParams.SkipOverwriteBackup = $true
    }
    if ($ForceResetScaffold.IsPresent) {
        $languageParams.OverwriteScaffold = $true
    }
    $languageJson = & $languageScript @languageParams
    $languageResult = $languageJson | ConvertFrom-Json
    if ([bool]$languageResult.overwrite_scaffold) {
        foreach ($languagePathValue in @($languageResult.scaffold_paths)) {
            $languageRelative = Normalize-RelativePath -Path ([string]$languagePathValue)
            $languagePath = Join-PathParts $ProjectDir $languageRelative
            if (Test-Path -LiteralPath $languagePath) {
                $installedTemplateHashes[$languageRelative] = Get-FileSha256 -Path $languagePath
            }
        }
    }
}

$projectLanguageValue = if ($null -ne $languageResult) { [string]$languageResult.project_language } else { "" }
$evidenceReport = $null
if ($OverwriteTemplates.IsPresent -or $RefreshUnmodifiedTemplates.IsPresent -or $ForceResetScaffold.IsPresent -or $manualReviewCount -gt 0 -or $script:bootstrapBackupCount -gt 0) {
    $evidenceReport = Write-BootstrapEvidenceReport `
        -ProjectDirFull (Resolve-Path -LiteralPath $ProjectDir).Path `
        -HubDirValue $HubDir `
        -LockPath $lockPath `
        -OperationMode $bootstrapOperationMode `
        -TemplateMode $templateMode `
        -Overwrite ([bool]$OverwriteTemplates.IsPresent) `
        -RefreshUnmodified ([bool]$refreshUnmodifiedMode) `
        -ForceReset ([bool]$ForceResetScaffold.IsPresent) `
        -HadExistingMemory ([bool]$hadExistingProjectMemory) `
        -ProjectLanguageValue $projectLanguageValue `
        -Copied @($copiedPaths.ToArray()) `
        -Preserved @($preservedPaths.ToArray()) `
        -Replaced @($replacedPaths.ToArray()) `
        -Skipped @($skippedPaths.ToArray()) `
        -ManualReview @($manualReviewPaths.ToArray()) `
        -Backup @($script:bootstrapBackupRecords.ToArray())
}

$lockData = [ordered]@{
    schema_version = 1
    installed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    installer = "project-bootstrap"
    project_dir = (Resolve-Path -LiteralPath $ProjectDir).Path
    hub_dir = $HubDir
    hub_remote = $hubRemote
    hub_branch = $hubBranch
    hub_commit = $hubCommit
    hub_dirty = [bool]$hubDirty
    template_source = "templates/project-root + templates/project-agent"
    template_tree_hash_sha256 = $templateTreeHash
    bootstrap_operation_mode = $bootstrapOperationMode
    template_mode = $templateMode
    overwrite_templates = [bool]$OverwriteTemplates.IsPresent
    refresh_unmodified_templates = [bool]$refreshUnmodifiedMode
    force_reset_scaffold = [bool]$ForceResetScaffold.IsPresent
    template_backup_count = [int]$script:bootstrapBackupCount
    template_backup_dir = $script:bootstrapBackupDir
    template_backup_paths = @($script:bootstrapBackupRecords.ToArray())
    template_preserved_paths = @($preservedPaths.ToArray())
    template_replaced_paths = @($replacedPaths.ToArray())
    template_skipped_paths = @($skippedPaths.ToArray())
    template_manual_review_count = [int]$manualReviewCount
    template_manual_review_paths = @($manualReviewPaths.ToArray())
    template_evidence_report_json = if ($null -ne $evidenceReport) { [string]$evidenceReport.json } else { "" }
    template_evidence_report_markdown = if ($null -ne $evidenceReport) { [string]$evidenceReport.markdown } else { "" }
    template_installed_hashes_sha256 = $installedTemplateHashes
    language_backup_count = if ($null -ne $languageResult) { [int]$languageResult.backup_count } else { 0 }
    language_backup_dir = if ($null -ne $languageResult) { [string]$languageResult.backup_dir } else { "" }
    language_backup_paths = if ($null -ne $languageResult) { @($languageResult.backup_paths) } else { @() }
    language_template_root = if ($null -ne $languageResult) { [string]$languageResult.template_root } else { "" }
    language_template_warnings = if ($null -ne $languageResult) { @($languageResult.template_warnings) } else { @() }
    language_template_fallback_count = if ($null -ne $languageResult) { [int]$languageResult.fallback_count } else { 0 }
    language_template_fallback_paths = if ($null -ne $languageResult) { @($languageResult.fallback_paths) } else { @() }
    project_language = $projectLanguageValue
}

$lockData | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $lockPath -Encoding UTF8

Write-Output "Project bootstrap complete."
Write-Output "Bootstrap operation mode: $bootstrapOperationMode"
Write-Output "Project: $ProjectDir"
Write-Output "Hub: $HubDir"
Write-Output ("Template files copied: {0}, updated: {1}, skipped: {2}" -f $copiedCount, $updatedCount, $skippedCount)
if ($refreshUnmodifiedMode) {
    Write-Output "Template refresh mode: unmodified template files may be refreshed; modified files are preserved for manual review."
}
if ($ForceResetScaffold.IsPresent) {
    Write-Output "Template reset mode: explicit force reset requested; replacements are backed up before writing."
}
if ($script:bootstrapBackupCount -gt 0) {
    Write-Output ("Template backups written: {0} ({1})" -f $script:bootstrapBackupCount, $script:bootstrapBackupDir)
}
if ($manualReviewCount -gt 0) {
    Write-Output ("Template files preserved for manual review: {0}" -f $manualReviewCount)
    foreach ($manualReviewPath in $manualReviewPaths) {
        Write-Output ("  - {0}" -f $manualReviewPath)
    }
}
if ($null -ne $evidenceReport) {
    Write-Output ("Bootstrap evidence report: {0}" -f [string]$evidenceReport.markdown)
}
if ($null -ne $languageResult) {
    Write-Output ("Project language: {0} ({1} files written, {2} skipped)" -f [string]$languageResult.project_language, [int]$languageResult.files_written, [int]$languageResult.files_skipped)
    if ([int]$languageResult.fallback_count -gt 0) {
        Write-Output ("Project language template fallbacks: {0}" -f [int]$languageResult.fallback_count)
        foreach ($fallbackPath in @($languageResult.fallback_paths)) {
            Write-Output ("  - {0}" -f [string]$fallbackPath)
        }
    }
    if ([int]$languageResult.backup_count -gt 0) {
        Write-Output ("Language scaffold backups written: {0} ({1})" -f [int]$languageResult.backup_count, [string]$languageResult.backup_dir)
    }
    if ($hadExistingProjectMemory -and -not $ForceResetScaffold.IsPresent) {
        Write-Output "Project language refresh preserved existing memory files; review skipped files before replacing customized content."
    } elseif ($ForceResetScaffold.IsPresent) {
        Write-Output "Project language scaffold reset used explicit force reset; replacements are backup-first."
    }
}
Write-Output "Lock file: $lockPath"

$memoryUpgradeScript = Join-PathParts $PSScriptRoot "memory_upgrade.ps1"
if ($AnalyzeMemoryUpgrade.IsPresent -or $PlanMemoryUpgrade.IsPresent -or $ApplyMemoryUpgrade.IsPresent -or $AutoUpgrade.IsPresent) {
    if (-not (Test-Path -LiteralPath $memoryUpgradeScript)) {
        throw "Memory upgrade helper not found: $memoryUpgradeScript"
    }

    if ($AutoUpgrade.IsPresent) {
        $analysisJson = & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Analyze -Json | ConvertFrom-Json
        $findingCount = @($analysisJson.findings).Count
        if ($findingCount -lt 1) {
            Write-Output "Memory upgrade auto: no candidates detected."
        } else {
            Write-Output ("Memory upgrade auto: candidates detected: {0}" -f $findingCount)
            $planJson = & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Plan -Json | ConvertFrom-Json
            $proposalPath = [string]$planJson.proposal
            if ([string]::IsNullOrWhiteSpace($proposalPath) -or -not (Test-Path -LiteralPath $proposalPath)) {
                throw "Memory upgrade auto failed to create a proposal."
            }

            Write-Output ("Memory upgrade auto proposal: {0}" -f $proposalPath)
            $applyJson = & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Apply -UpgradePlan $proposalPath -Json | ConvertFrom-Json
            $backupDir = [string]$applyJson.apply_result.backup_dir
            $resultPath = [string]$applyJson.apply_result.result
            Write-Output ("Memory upgrade auto backup: {0}" -f $backupDir)
            Write-Output ("Memory upgrade auto result: {0}" -f $resultPath)
        }
    } elseif ($ApplyMemoryUpgrade.IsPresent) {
        & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Apply -UpgradePlan $UpgradePlan
    } elseif ($PlanMemoryUpgrade.IsPresent) {
        & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Plan
    } else {
        & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Analyze
    }
} elseif (-not $SkipMemoryUpgradeAnalysis.IsPresent -and (Test-Path -LiteralPath $memoryUpgradeScript)) {
    try {
        $analysisJson = & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Analyze -Json | ConvertFrom-Json
        $findingCount = @($analysisJson.findings).Count
        if ($findingCount -gt 0) {
            Write-Output ("Memory upgrade candidates detected: {0}" -f $findingCount)
            Write-Output "Run with -PlanMemoryUpgrade to create a reviewable proposal, then -ApplyMemoryUpgrade -UpgradePlan <path> after review. Use -AutoUpgrade only when the caller explicitly approves the default proposal actions."
        }
    } catch {
        Write-Warning "Memory upgrade analysis failed: $($_.Exception.Message)"
    }
}
