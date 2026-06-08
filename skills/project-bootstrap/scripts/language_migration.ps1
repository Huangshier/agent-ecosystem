param(
    [string]$ProjectDir = (Get-Location).Path,
    [ValidateSet("Analyze", "Plan", "Apply", "Validate", "PlanNarrative", "ApplyNarrative", "ValidateNarrative")]
    [string]$Mode = "Analyze",
    [string]$SourceLanguage = "",
    [string]$TargetLanguage = "",
    [string]$MigrationPlan = "",
    [string]$TemplateRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

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

function Get-ComparableFullPath {
    param([string]$Path)
    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd([char[]]"\/")
}

function Test-HotMemoryPath {
    param([string]$RelativePath)

    $normalized = Normalize-RelativePath -Path $RelativePath
    return ($normalized -in @(".agents/plan.md", ".agents/process.txt", ".agents/notes.md"))
}

function Read-Utf8Text {
    param([string]$Path)
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    return [System.IO.File]::ReadAllText($Path, $encoding)
}

function Write-Utf8TextWithBom {
    param(
        [string]$Path,
        [string]$Content
    )
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha256 {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $encoding = New-Object System.Text.UTF8Encoding($false)
        $bytes = $encoding.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-FileTextSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }
    return Get-TextSha256 -Text (Read-Utf8Text -Path $Path)
}

function Join-CodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$script:ZhText = [ordered]@{
    ManualHeading = Join-CodePoints @(0x9879, 0x76EE, 0x7279, 0x5316, 0x6E90, 0x5185, 0x5BB9, 0xFF08, 0x9700, 0x4EBA, 0x5DE5, 0x5BA1, 0x6838, 0xFF09)
    ManualIntro = Join-CodePoints @(0x4EE5, 0x4E0B, 0x5185, 0x5BB9, 0x5DF2, 0x6309, 0x539F, 0x6587, 0x4FDD, 0x7559, 0xFF0C, 0x9700, 0x4EBA, 0x5DE5, 0x5BA1, 0x6838, 0x540E, 0x518D, 0x7FFB, 0x8BD1, 0x3001, 0x5408, 0x5E76, 0x6216, 0x8DEF, 0x7531, 0x3002)
}

function Resolve-SupportedLanguage {
    param(
        [string]$Language,
        [string]$ParamName
    )

    if ([string]::IsNullOrWhiteSpace($Language)) {
        throw "$ParamName is required. Supported values: en, zh-CN."
    }

    $normalized = $Language.Trim().ToLowerInvariant()
    if ($normalized -in @("en", "en-us", "english")) {
        return "en"
    }
    if ($normalized -in @("zh", "zh-cn", "zh-hans", "chinese", "simplified-chinese", "simplified chinese")) {
        return "zh-CN"
    }

    throw "Unsupported $ParamName '$Language'. Supported values: en, zh-CN."
}

function Convert-TemplatePathToProjectPath {
    param(
        [string]$TemplateSection,
        [string]$RelativePath
    )

    $normalized = Normalize-RelativePath -Path $RelativePath
    if ($TemplateSection -eq "project-agent") {
        return Normalize-RelativePath -Path (Join-Path ".agents" $normalized)
    }
    return $normalized
}

function Get-LanguageTemplateMap {
    param(
        [string]$Root,
        [string]$LanguageCode
    )

    $languageRoot = Join-PathParts $Root $LanguageCode
    if (-not (Test-Path -LiteralPath $languageRoot)) {
        throw "Missing project language template root: $languageRoot"
    }

    $map = @{}
    foreach ($section in @("project-root", "project-agent")) {
        $sectionRoot = Join-PathParts $languageRoot $section
        if (-not (Test-Path -LiteralPath $sectionRoot)) {
            throw "Missing project language template section: $sectionRoot"
        }

        Get-ChildItem -LiteralPath $sectionRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
            $relative = Normalize-RelativePath -Path $_.FullName.Substring($sectionRoot.Length).TrimStart([char[]]"\/")
            $projectRelative = Convert-TemplatePathToProjectPath -TemplateSection $section -RelativePath $relative
            $map[$projectRelative] = [ordered]@{
                relative_path = $projectRelative
                template_path = $_.FullName
                template_hash = Get-FileTextSha256 -Path $_.FullName
                language = $LanguageCode
            }
        }
    }
    return $map
}

function Add-PathToSet {
    param(
        [hashtable]$Set,
        [string]$RelativePath
    )

    $normalized = Normalize-RelativePath -Path $RelativePath
    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
        $Set[$normalized] = $true
    }
}

function Get-MigrationRelativePaths {
    param(
        [string]$Root,
        [hashtable]$SourceTemplates,
        [hashtable]$TargetTemplates
    )

    $set = @{}

    foreach ($key in @($SourceTemplates.Keys)) {
        Add-PathToSet -Set $set -RelativePath ([string]$key)
    }
    foreach ($key in @($TargetTemplates.Keys)) {
        Add-PathToSet -Set $set -RelativePath ([string]$key)
    }

    foreach ($relative in @(
        "AGENTS.md",
        ".agents/AGENTS.md",
        ".agents/process.txt",
        ".agents/plan.md",
        ".agents/notes.md"
    )) {
        Add-PathToSet -Set $set -RelativePath $relative
    }

    foreach ($scanRoot in @(".agents/context", ".agents/commands", "docs/specs")) {
        $full = Join-PathParts $Root $scanRoot
        if (-not (Test-Path -LiteralPath $full)) {
            continue
        }

        Get-ChildItem -LiteralPath $full -Recurse -File -Filter "*.md" | ForEach-Object {
            $relative = Normalize-RelativePath -Path $_.FullName.Substring($Root.Length).TrimStart([char[]]"\/")
            if ($relative -like ".agents/_backup/*" -or $relative -like ".agents/upgrade/*" -or $relative -like ".agents/language-migration/*") {
                return
            }
            Add-PathToSet -Set $set -RelativePath $relative
        }
    }

    return @($set.Keys | Sort-Object)
}

function Test-ContainsCjk {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }
    return [regex]::IsMatch($Text, '[\u4e00-\u9fff]')
}

function Test-ContainsAsciiLetters {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }
    return [regex]::IsMatch($Text, '[A-Za-z]')
}

function New-MigrationAction {
    param(
        [string]$Root,
        [string]$RelativePath,
        [hashtable]$SourceTemplates,
        [hashtable]$TargetTemplates
    )

    $path = Join-PathParts $Root $RelativePath
    $exists = Test-Path -LiteralPath $path
    $sourceTemplate = $null
    $targetTemplate = $null
    if ($SourceTemplates.ContainsKey($RelativePath)) {
        $sourceTemplate = $SourceTemplates[$RelativePath]
    }
    if ($TargetTemplates.ContainsKey($RelativePath)) {
        $targetTemplate = $TargetTemplates[$RelativePath]
    }

    $currentHash = ""
    $currentText = ""
    $containsCjk = $false
    $containsAscii = $false
    if ($exists) {
        $currentText = Read-Utf8Text -Path $path
        $currentHash = Get-TextSha256 -Text $currentText
        $containsCjk = Test-ContainsCjk -Text $currentText
        $containsAscii = Test-ContainsAsciiLetters -Text $currentText
    }

    $sourceHash = ""
    $targetHash = ""
    $sourceTemplatePath = ""
    $targetTemplatePath = ""
    if ($null -ne $sourceTemplate) {
        $sourceHash = [string]$sourceTemplate.template_hash
        $sourceTemplatePath = [string]$sourceTemplate.template_path
    }
    if ($null -ne $targetTemplate) {
        $targetHash = [string]$targetTemplate.template_hash
        $targetTemplatePath = [string]$targetTemplate.template_path
    }

    $action = "skip-missing"
    $reason = "File is missing and has no target template."
    $writes_file = $false
    $manualReview = $false
    $approved = $false

    if ($exists -and $null -ne $targetTemplate -and $currentHash -eq $targetHash) {
        $action = "already-target-template"
        $reason = "Existing file already matches the target language template."
    } elseif ($exists -and $null -ne $sourceTemplate -and $currentHash -eq $sourceHash -and $null -ne $targetTemplate) {
        $action = "replace-template"
        $reason = "Existing file matches the source language template exactly; replace with target template."
        $writes_file = $true
        $approved = $true
    } elseif (-not $exists -and $null -ne $targetTemplate) {
        $action = "add-target-template"
        $reason = "File is missing and target language template exists."
        $writes_file = $true
        $approved = $true
    } elseif ($exists -and $null -ne $targetTemplate -and (Test-HotMemoryPath -RelativePath $RelativePath)) {
        $action = "route-hot-memory-manual-review"
        $reason = "Hot memory has project-specific content; write the concise target template and route original content to a manual-review artifact."
        $writes_file = $true
        $manualReview = $true
        $approved = $true
    } elseif ($exists -and $null -ne $targetTemplate) {
        $action = "merge-with-manual-review"
        $reason = "Existing file has project-specific content; write target template and preserve original content in a manual-review section."
        $writes_file = $true
        $manualReview = $true
        $approved = $true
    } elseif ($exists) {
        $action = "preserve-manual-review"
        $reason = "Existing file has no target template; preserve unchanged and route to manual review."
        $manualReview = $true
    }

    return [ordered]@{
        relative_path = $RelativePath
        exists = [bool]$exists
        action = $action
        approved = [bool]$approved
        writes_file = [bool]$writes_file
        manual_review = [bool]$manualReview
        reason = $reason
        current_hash_sha256 = $currentHash
        source_template_hash_sha256 = $sourceHash
        target_template_hash_sha256 = $targetHash
        source_template_path = $sourceTemplatePath
        target_template_path = $targetTemplatePath
        contains_cjk = [bool]$containsCjk
        contains_ascii_letters = [bool]$containsAscii
        mixed_language_signals = [bool]($containsCjk -and $containsAscii)
    }
}

function Get-MigrationAnalysis {
    param(
        [string]$Root,
        [string]$TemplateRootFull,
        [string]$SourceCode,
        [string]$TargetCode
    )

    $sourceTemplates = Get-LanguageTemplateMap -Root $TemplateRootFull -LanguageCode $SourceCode
    $targetTemplates = Get-LanguageTemplateMap -Root $TemplateRootFull -LanguageCode $TargetCode
    $relativePaths = Get-MigrationRelativePaths -Root $Root -SourceTemplates $sourceTemplates -TargetTemplates $targetTemplates
    $actions = New-Object 'System.Collections.Generic.List[object]'

    foreach ($relativePath in $relativePaths) {
        $actions.Add((New-MigrationAction -Root $Root -RelativePath $relativePath -SourceTemplates $sourceTemplates -TargetTemplates $targetTemplates)) | Out-Null
    }

    $actionArray = @($actions.ToArray())
    $summary = [ordered]@{
        total = $actionArray.Count
        writes = @($actionArray | Where-Object { [bool]$_.writes_file }).Count
        manual_review = @($actionArray | Where-Object { [bool]$_.manual_review }).Count
        mixed_language = @($actionArray | Where-Object { [bool]$_.mixed_language_signals }).Count
        preserve_unchanged = @($actionArray | Where-Object { [string]$_.action -eq "preserve-manual-review" }).Count
        template_replacements = @($actionArray | Where-Object { [string]$_.action -eq "replace-template" }).Count
        target_template_additions = @($actionArray | Where-Object { [string]$_.action -eq "add-target-template" }).Count
        merge_with_manual_review = @($actionArray | Where-Object { [string]$_.action -eq "merge-with-manual-review" }).Count
        hot_memory_routes = @($actionArray | Where-Object { [string]$_.action -eq "route-hot-memory-manual-review" }).Count
    }

    return [ordered]@{
        project = $Root
        template_root = $TemplateRootFull
        source_language = $SourceCode
        target_language = $TargetCode
        summary = $summary
        actions = @($actionArray)
    }
}

function New-MigrationBackup {
    param(
        [string]$Root,
        [array]$Actions,
        [string]$Stamp
    )

    $agentDir = Join-PathParts $Root ".agents"
    Ensure-Dir -Path $agentDir
    $backupDir = Join-PathParts $agentDir "_backup" ("language-migration-{0}" -f $Stamp)
    Ensure-Dir -Path $backupDir
    $records = New-Object 'System.Collections.Generic.List[object]'

    foreach ($action in @($Actions)) {
        if (-not [bool]$action.exists) {
            continue
        }
        $relative = [string]$action.relative_path
        $source = Join-PathParts $Root $relative
        if (-not (Test-Path -LiteralPath $source)) {
            continue
        }
        $destination = Join-PathParts $backupDir $relative
        Ensure-Dir -Path (Split-Path -Parent $destination)
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $records.Add([ordered]@{
            relative_path = $relative
            backup_path = $destination
        }) | Out-Null
    }

    $lockPath = Join-PathParts $Root ".agents" "hub.lock.json"
    if (Test-Path -LiteralPath $lockPath) {
        $destination = Join-PathParts $backupDir ".agents" "hub.lock.json"
        Ensure-Dir -Path (Split-Path -Parent $destination)
        Copy-Item -LiteralPath $lockPath -Destination $destination -Force
        $records.Add([ordered]@{
            relative_path = ".agents/hub.lock.json"
            backup_path = $destination
        }) | Out-Null
    }

    return [ordered]@{
        backup_dir = $backupDir
        records = @($records.ToArray())
        lock_hash_sha256 = Get-FileSha256 -Path $lockPath
    }
}

function Write-MigrationProposal {
    param(
        [string]$Root,
        $Analysis,
        $Backup
    )

    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $migrationDir = Join-PathParts $Root ".agents" "language-migration" $stamp
    Ensure-Dir -Path $migrationDir
    $proposalJson = Join-Path $migrationDir "proposal.json"
    $proposalMarkdown = Join-Path $migrationDir "proposal.md"

    $payload = [ordered]@{
        schema_version = 1
        created_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        project = [string]$Analysis.project
        template_root = [string]$Analysis.template_root
        source_language = [string]$Analysis.source_language
        target_language = [string]$Analysis.target_language
        backup_dir = [string]$Backup.backup_dir
        backup_paths = @($Backup.records)
        lock_hash_sha256 = [string]$Backup.lock_hash_sha256
        proposal_markdown = $proposalMarkdown
        summary = $Analysis.summary
        actions = @($Analysis.actions)
    }

    $payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $proposalJson -Encoding UTF8

    $lines = @()
    $lines += "# Language Migration Proposal"
    $lines += ""
    $lines += "- Project: $($Analysis.project)"
    $lines += "- Source language: $($Analysis.source_language)"
    $lines += "- Target language: $($Analysis.target_language)"
    $lines += "- Backup: $($Backup.backup_dir)"
    $lines += "- Proposal JSON: $proposalJson"
    $lines += "- Mode: review before apply"
    $lines += ""
    $lines += "## Summary"
    foreach ($property in $Analysis.summary.GetEnumerator()) {
        $lines += ("- {0}: {1}" -f $property.Key, $property.Value)
    }
    $lines += ""
    $lines += "## Safety Rules"
    $lines += "- Target language templates are structural baselines, not overwrite authority."
    $lines += "- Project-specific content is preserved verbatim or routed to manual review."
    $lines += "- Hot memory files are kept concise; their original source content is routed to manual-review artifacts instead of being appended back into hot memory."
    $lines += "- Commands, paths, API names, filenames, commit types, raw errors, and code symbols remain unchanged because customized content is not machine-translated."
    $lines += "- Apply mode refuses to write when this proposal or the recorded backup is missing."
    $lines += "- Apply mode refuses to write when a planned source file hash changed after planning."
    $lines += ""
    $lines += "## Actions"
    foreach ($action in @($Analysis.actions)) {
        $approval = if ([bool]$action.approved) { "approved" } else { "review-only" }
        $manual = if ([bool]$action.manual_review) { "; manual review" } else { "" }
        $lines += ("- `{0}`: {1} ({2}{3})" -f [string]$action.relative_path, [string]$action.action, $approval, $manual)
        $lines += ("  - Reason: {0}" -f [string]$action.reason)
    }
    $lines += ""
    $lines += "## Review Notes"
    $lines += "- To skip a write action, edit `proposal.json` and set that action's `approved` field to `false` before apply."
    $lines += "- Manual-review sections preserve source content verbatim for later human or agent-assisted language cleanup."

    Set-Content -LiteralPath $proposalMarkdown -Value $lines -Encoding UTF8

    return [ordered]@{
        proposal = $proposalJson
        proposal_markdown = $proposalMarkdown
        backup_dir = [string]$Backup.backup_dir
    }
}

function Add-ManualReviewSection {
    param(
        [string]$TargetTemplateText,
        [string]$SourceText,
        [string]$SourceHash,
        [string]$SourceLanguageCode,
        [string]$TargetLanguageCode
    )

    $lines = @()
    $lines += $TargetTemplateText.TrimEnd()
    $lines += ""
    if ($TargetLanguageCode -eq "zh-CN") {
        $lines += ("## {0}" -f $script:ZhText.ManualHeading)
        $lines += ""
        $lines += $script:ZhText.ManualIntro
    } else {
        $lines += "## Project-Specific Source Content (Manual Review)"
        $lines += ""
        $lines += "The following content is preserved verbatim and must be reviewed before translation, merge, or routing."
    }
    $lines += ""
    $lines += "<!-- language-migration:manual-review-source begin -->"
    $lines += ("<!-- source_language: {0}; target_language: {1}; source_hash_sha256: {2} -->" -f $SourceLanguageCode, $TargetLanguageCode, $SourceHash)
    $lines += $SourceText.TrimEnd()
    $lines += "<!-- language-migration:manual-review-source end -->"
    return ($lines -join "`r`n") + "`r`n"
}

function Write-ManualReviewArtifact {
    param(
        [string]$ProposalDir,
        [string]$RelativePath,
        [string]$SourceText,
        [string]$SourceHash,
        [string]$SourceLanguageCode,
        [string]$TargetLanguageCode
    )

    $artifactPath = Join-PathParts $ProposalDir "manual-review" $RelativePath
    Ensure-Dir -Path (Split-Path -Parent $artifactPath)

    $lines = @()
    $lines += "# Language Migration Manual Review Source"
    $lines += ""
    $lines += ("- Path: {0}" -f $RelativePath)
    $lines += ("- Source language: {0}" -f $SourceLanguageCode)
    $lines += ("- Target language: {0}" -f $TargetLanguageCode)
    $lines += ("- Source hash SHA256: {0}" -f $SourceHash)
    $lines += ""
    $lines += "<!-- language-migration:manual-review-source begin -->"
    $lines += ("<!-- source_language: {0}; target_language: {1}; source_hash_sha256: {2} -->" -f $SourceLanguageCode, $TargetLanguageCode, $SourceHash)
    $lines += $SourceText.TrimEnd()
    $lines += "<!-- language-migration:manual-review-source end -->"

    Write-Utf8TextWithBom -Path $artifactPath -Content ((($lines -join "`r`n") + "`r`n"))
    return $artifactPath
}

function Read-MigrationPlan {
    param([string]$PlanPath)

    if ([string]::IsNullOrWhiteSpace($PlanPath) -or -not (Test-Path -LiteralPath $PlanPath)) {
        throw "Migration plan is required and must point to proposal.json."
    }

    $plan = Read-Utf8Text -Path $PlanPath | ConvertFrom-Json
    if ([int]$plan.schema_version -ne 1) {
        throw "Unsupported migration proposal schema version."
    }
    return $plan
}

function Assert-PlanBackupReady {
    param($Plan)

    $backupDir = [string]$Plan.backup_dir
    if ([string]::IsNullOrWhiteSpace($backupDir) -or -not (Test-Path -LiteralPath $backupDir)) {
        throw "Migration apply requires an existing backup directory recorded in the proposal."
    }
}

function Assert-PlanProjectMatchesCurrentProject {
    param(
        $Plan,
        [string]$CurrentProjectDir
    )

    $plannedProject = Get-ComparableFullPath -Path ([string]$Plan.project)
    $currentProject = Get-ComparableFullPath -Path $CurrentProjectDir
    if (-not [string]::Equals($plannedProject, $currentProject, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Migration plan project mismatch. Current ProjectDir '{0}' does not match proposal project '{1}'." -f $currentProject, $plannedProject)
    }
}

function Assert-CurrentHashesMatchPlan {
    param($Plan)

    $root = [string]$Plan.project
    foreach ($action in @($Plan.actions)) {
        $relative = [string]$action.relative_path
        $path = Join-PathParts $root $relative
        $plannedHash = [string]$action.current_hash_sha256
        $currentHash = Get-FileTextSha256 -Path $path
        if ($plannedHash -ne $currentHash) {
            throw "Planned source changed after proposal: $relative"
        }
    }

    $lockPath = Join-PathParts $root ".agents" "hub.lock.json"
    $plannedLockHash = [string]$Plan.lock_hash_sha256
    $currentLockHash = Get-FileSha256 -Path $lockPath
    if ($plannedLockHash -ne $currentLockHash) {
        throw "Project lock metadata changed after proposal: .agents/hub.lock.json"
    }
}

function Update-LockForMigration {
    param(
        [string]$Root,
        $Plan,
        [string]$ResultPath,
        [int]$WrittenCount,
        [int]$ManualReviewCount
    )

    $agentDir = Join-PathParts $Root ".agents"
    Ensure-Dir -Path $agentDir
    $lockPath = Join-PathParts $agentDir "hub.lock.json"
    $lock = [ordered]@{}
    if (Test-Path -LiteralPath $lockPath) {
        try {
            $existing = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
            foreach ($property in $existing.PSObject.Properties) {
                $lock[$property.Name] = $property.Value
            }
        } catch {
            throw "Could not read .agents/hub.lock.json before migration apply: $($_.Exception.Message)"
        }
    } else {
        $lock["schema_version"] = 1
        $lock["installer"] = "project-bootstrap"
        $lock["project_dir"] = $Root
    }

    $lock["project_language"] = [string]$Plan.target_language
    $lock["language_migration"] = [ordered]@{
        schema_version = 1
        applied_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        source_language = [string]$Plan.source_language
        target_language = [string]$Plan.target_language
        proposal = [string]$MigrationPlan
        backup_dir = [string]$Plan.backup_dir
        result = $ResultPath
        files_written = [int]$WrittenCount
        manual_review_count = [int]$ManualReviewCount
    }

    $lock | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $lockPath -Encoding UTF8
}

function Apply-MigrationPlan {
    param($Plan)

    Assert-PlanBackupReady -Plan $Plan
    Assert-CurrentHashesMatchPlan -Plan $Plan

    $root = [string]$Plan.project
    $written = 0
    $manualReview = 0
    $appliedActions = New-Object 'System.Collections.Generic.List[object]'
    $proposalDir = Split-Path -Parent ([string]$MigrationPlan)

    foreach ($action in @($Plan.actions)) {
        $relative = [string]$action.relative_path
        $actionName = [string]$action.action
        $approved = [bool]$action.approved
        $path = Join-PathParts $root $relative

        if ([bool]$action.manual_review) {
            $manualReview++
        }

        if (-not $approved) {
            $artifactPath = ""
            if ([bool]$action.manual_review -and (Test-Path -LiteralPath $path)) {
                $sourceText = Read-Utf8Text -Path $path
                $artifactPath = Write-ManualReviewArtifact -ProposalDir $proposalDir -RelativePath $relative -SourceText $sourceText -SourceHash (Get-TextSha256 -Text $sourceText) -SourceLanguageCode ([string]$Plan.source_language) -TargetLanguageCode ([string]$Plan.target_language)
            }
            $appliedActions.Add([ordered]@{
                relative_path = $relative
                action = $actionName
                result = "skipped-unapproved"
                manual_review_artifact = $artifactPath
                final_hash_sha256 = Get-FileTextSha256 -Path $path
            }) | Out-Null
            continue
        }

        if ($actionName -eq "replace-template" -or $actionName -eq "add-target-template") {
            $targetTemplatePath = [string]$action.target_template_path
            if ([string]::IsNullOrWhiteSpace($targetTemplatePath) -or -not (Test-Path -LiteralPath $targetTemplatePath)) {
                throw "Missing target template for $relative"
            }
            Ensure-Dir -Path (Split-Path -Parent $path)
            Write-Utf8TextWithBom -Path $path -Content (Read-Utf8Text -Path $targetTemplatePath)
            $written++
            $appliedActions.Add([ordered]@{
                relative_path = $relative
                action = $actionName
                result = "written-target-template"
                final_hash_sha256 = Get-FileTextSha256 -Path $path
            }) | Out-Null
            continue
        }

        if ($actionName -eq "merge-with-manual-review") {
            $targetTemplatePath = [string]$action.target_template_path
            if ([string]::IsNullOrWhiteSpace($targetTemplatePath) -or -not (Test-Path -LiteralPath $targetTemplatePath)) {
                throw "Missing target template for $relative"
            }
            $sourceText = ""
            if (Test-Path -LiteralPath $path) {
                $sourceText = Read-Utf8Text -Path $path
            }
            $sourceHash = Get-TextSha256 -Text $sourceText
            $targetText = Read-Utf8Text -Path $targetTemplatePath
            $merged = Add-ManualReviewSection -TargetTemplateText $targetText -SourceText $sourceText -SourceHash $sourceHash -SourceLanguageCode ([string]$Plan.source_language) -TargetLanguageCode ([string]$Plan.target_language)
            $artifactPath = Write-ManualReviewArtifact -ProposalDir $proposalDir -RelativePath $relative -SourceText $sourceText -SourceHash $sourceHash -SourceLanguageCode ([string]$Plan.source_language) -TargetLanguageCode ([string]$Plan.target_language)
            Ensure-Dir -Path (Split-Path -Parent $path)
            Write-Utf8TextWithBom -Path $path -Content $merged
            $written++
            $appliedActions.Add([ordered]@{
                relative_path = $relative
                action = $actionName
                result = "written-target-template-with-manual-review-source"
                manual_review_artifact = $artifactPath
                source_hash_sha256 = $sourceHash
                final_hash_sha256 = Get-FileTextSha256 -Path $path
            }) | Out-Null
            continue
        }

        if ($actionName -eq "route-hot-memory-manual-review") {
            $targetTemplatePath = [string]$action.target_template_path
            if ([string]::IsNullOrWhiteSpace($targetTemplatePath) -or -not (Test-Path -LiteralPath $targetTemplatePath)) {
                throw "Missing target template for $relative"
            }
            $sourceText = ""
            if (Test-Path -LiteralPath $path) {
                $sourceText = Read-Utf8Text -Path $path
            }
            $sourceHash = Get-TextSha256 -Text $sourceText
            $artifactPath = Write-ManualReviewArtifact -ProposalDir $proposalDir -RelativePath $relative -SourceText $sourceText -SourceHash $sourceHash -SourceLanguageCode ([string]$Plan.source_language) -TargetLanguageCode ([string]$Plan.target_language)
            Ensure-Dir -Path (Split-Path -Parent $path)
            Write-Utf8TextWithBom -Path $path -Content (Read-Utf8Text -Path $targetTemplatePath)
            $written++
            $appliedActions.Add([ordered]@{
                relative_path = $relative
                action = $actionName
                result = "written-target-template-source-routed-to-artifact"
                manual_review_artifact = $artifactPath
                source_hash_sha256 = $sourceHash
                final_hash_sha256 = Get-FileTextSha256 -Path $path
            }) | Out-Null
            continue
        }

        $artifactPath = ""
        if ($actionName -eq "preserve-manual-review" -and (Test-Path -LiteralPath $path)) {
            $sourceText = Read-Utf8Text -Path $path
            $artifactPath = Write-ManualReviewArtifact -ProposalDir $proposalDir -RelativePath $relative -SourceText $sourceText -SourceHash (Get-TextSha256 -Text $sourceText) -SourceLanguageCode ([string]$Plan.source_language) -TargetLanguageCode ([string]$Plan.target_language)
        }
        $appliedActions.Add([ordered]@{
            relative_path = $relative
            action = $actionName
            result = "preserved"
            manual_review_artifact = $artifactPath
            final_hash_sha256 = Get-FileTextSha256 -Path $path
        }) | Out-Null
    }

    $resultJson = Join-Path $proposalDir "result.json"
    $resultMarkdown = Join-Path $proposalDir "result.md"

    $result = [ordered]@{
        schema_version = 1
        applied_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        project = $root
        source_language = [string]$Plan.source_language
        target_language = [string]$Plan.target_language
        proposal = [string]$MigrationPlan
        backup_dir = [string]$Plan.backup_dir
        files_written = [int]$written
        manual_review_count = [int]$manualReview
        actions = @($appliedActions.ToArray())
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultJson -Encoding UTF8

    $lines = @(
        "# Language Migration Result",
        "",
        "- Project: $root",
        "- Source language: $($Plan.source_language)",
        "- Target language: $($Plan.target_language)",
        "- Proposal: $MigrationPlan",
        "- Backup: $($Plan.backup_dir)",
        "- Files written: $written",
        "- Manual-review files: $manualReview",
        "",
        "The migration applied only approved actions from the proposal. Project-specific source content was preserved verbatim where manual review is required."
    )
    Set-Content -LiteralPath $resultMarkdown -Value $lines -Encoding UTF8

    Update-LockForMigration -Root $root -Plan $Plan -ResultPath $resultJson -WrittenCount $written -ManualReviewCount $manualReview

    return [ordered]@{
        result = $resultJson
        result_markdown = $resultMarkdown
        backup_dir = [string]$Plan.backup_dir
        files_written = [int]$written
        manual_review_count = [int]$manualReview
        actions = @($appliedActions.ToArray())
    }
}

function Validate-MigrationPlan {
    param($Plan)

    $findings = New-Object 'System.Collections.Generic.List[object]'
    $valid = $true
    $root = [string]$Plan.project
    $backupDir = [string]$Plan.backup_dir
    $proposalDir = Split-Path -Parent ([string]$MigrationPlan)
    $resultJson = Join-Path $proposalDir "result.json"
    $lockPath = Join-PathParts $root ".agents" "hub.lock.json"
    $result = $null
    $resultActions = @()
    $bodyLanguageAudit = $null

    if ([string]::IsNullOrWhiteSpace($backupDir) -or -not (Test-Path -LiteralPath $backupDir)) {
        $valid = $false
        $findings.Add([ordered]@{ severity = "error"; code = "missing_backup"; message = "Recorded backup directory is missing."; path = $backupDir }) | Out-Null
    }
    if (-not (Test-Path -LiteralPath $resultJson)) {
        $valid = $false
        $findings.Add([ordered]@{ severity = "error"; code = "missing_result"; message = "Migration result.json is missing."; path = $resultJson }) | Out-Null
    } else {
        $result = Get-Content -LiteralPath $resultJson -Raw | ConvertFrom-Json
        $resultActions = @($result.actions)
        if ($resultActions.Count -ne @($Plan.actions).Count) {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "result_action_count_mismatch"; message = "result.json action count does not match proposal action count."; path = $resultJson }) | Out-Null
        }
    }
    if (-not (Test-Path -LiteralPath $lockPath)) {
        $valid = $false
        $findings.Add([ordered]@{ severity = "error"; code = "missing_lock"; message = ".agents/hub.lock.json is missing after migration."; path = $lockPath }) | Out-Null
    } else {
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        if ([string]$lock.project_language -ne [string]$Plan.target_language) {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "wrong_project_language"; message = "Lock project_language does not match target language."; path = $lockPath }) | Out-Null
        }
        if ($lock.PSObject.Properties.Name -notcontains "language_migration") {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "missing_migration_metadata"; message = "Lock file lacks language_migration metadata."; path = $lockPath }) | Out-Null
        }
        elseif ([string]$lock.language_migration.result -ne $resultJson) {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "wrong_migration_result_path"; message = "Lock language_migration result path does not match the proposal result."; path = $lockPath }) | Out-Null
        }
    }

    $planActions = @($Plan.actions)
    for ($index = 0; $index -lt $planActions.Count; $index++) {
        $action = $planActions[$index]
        $resultAction = $null
        if ($index -lt $resultActions.Count) {
            $resultAction = $resultActions[$index]
        }

        $relative = [string]$action.relative_path
        $actionName = [string]$action.action
        $path = Join-PathParts $root $relative
        $plannedSourceHash = [string]$action.current_hash_sha256
        $targetTemplateHash = [string]$action.target_template_hash_sha256

        if ($null -ne $resultAction) {
            if ([string]$resultAction.relative_path -ne $relative -or [string]$resultAction.action -ne $actionName) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "result_action_mismatch"; message = "result.json action does not match the proposal action at the same index."; path = $relative }) | Out-Null
            }
        }

        if ($actionName -eq "replace-template" -or $actionName -eq "add-target-template") {
            if ([bool]$action.approved) {
                $currentHash = Get-FileTextSha256 -Path $path
                if ($currentHash -ne $targetTemplateHash) {
                    $valid = $false
                    $findings.Add([ordered]@{ severity = "error"; code = "target_template_hash_mismatch"; message = "Template write result does not match the planned target template hash."; path = $path }) | Out-Null
                }
            }
            continue
        }

        if ($actionName -eq "merge-with-manual-review" -and [bool]$action.approved) {
            if (-not (Test-Path -LiteralPath $path)) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "missing_merged_file"; message = "Merged manual-review file is missing."; path = $path }) | Out-Null
                continue
            }
            $text = Read-Utf8Text -Path $path
            if ($text -notlike "*language-migration:manual-review-source begin*") {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "missing_manual_review_marker"; message = "Merged file lacks manual-review source marker."; path = $path }) | Out-Null
            }
            if ($text -notlike ("*source_hash_sha256: {0}*" -f $plannedSourceHash)) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "manual_review_source_hash_mismatch"; message = "Merged file does not record the planned source content hash."; path = $path }) | Out-Null
            }
            if ($null -ne $resultAction -and [string]$resultAction.source_hash_sha256 -ne $plannedSourceHash) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "result_source_hash_mismatch"; message = "result.json does not record the planned source content hash."; path = $relative }) | Out-Null
            }
            $artifactPath = ""
            if ($null -ne $resultAction) {
                $artifactPath = [string]$resultAction.manual_review_artifact
            }
            if ([string]::IsNullOrWhiteSpace($artifactPath) -or -not (Test-Path -LiteralPath $artifactPath)) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "missing_manual_review_artifact"; message = "Merged manual-review source was not also routed to an artifact."; path = $artifactPath }) | Out-Null
            }
            continue
        }

        if ($actionName -eq "route-hot-memory-manual-review" -and [bool]$action.approved) {
            $currentHash = Get-FileTextSha256 -Path $path
            if ($currentHash -ne $targetTemplateHash) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "hot_memory_template_hash_mismatch"; message = "Hot memory file does not match the planned concise target template."; path = $path }) | Out-Null
            }
            if ((Test-Path -LiteralPath $path) -and (Read-Utf8Text -Path $path) -like "*language-migration:manual-review-source begin*") {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "hot_memory_manual_review_inlined"; message = "Hot memory file contains an inline manual-review source section."; path = $path }) | Out-Null
            }

            $artifactPath = ""
            if ($null -ne $resultAction) {
                $artifactPath = [string]$resultAction.manual_review_artifact
            }
            if ([string]::IsNullOrWhiteSpace($artifactPath) -or -not (Test-Path -LiteralPath $artifactPath)) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "missing_hot_memory_artifact"; message = "Hot memory source content was not routed to a manual-review artifact."; path = $artifactPath }) | Out-Null
            } else {
                $artifactText = Read-Utf8Text -Path $artifactPath
                if ($artifactText -notlike "*language-migration:manual-review-source begin*" -or $artifactText -notlike ("*source_hash_sha256: {0}*" -f $plannedSourceHash)) {
                    $valid = $false
                    $findings.Add([ordered]@{ severity = "error"; code = "hot_memory_artifact_hash_mismatch"; message = "Hot memory manual-review artifact does not record the planned source content hash."; path = $artifactPath }) | Out-Null
                }
            }
            continue
        }

        if ($actionName -eq "preserve-manual-review") {
            $currentHash = Get-FileTextSha256 -Path $path
            if ($currentHash -ne $plannedSourceHash) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "preserved_hash_mismatch"; message = "Preserve-manual-review action changed the file hash."; path = $path }) | Out-Null
            }
            $artifactPath = ""
            if ($null -ne $resultAction) {
                $artifactPath = [string]$resultAction.manual_review_artifact
            }
            if ([bool]$action.manual_review -and ([string]::IsNullOrWhiteSpace($artifactPath) -or -not (Test-Path -LiteralPath $artifactPath))) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "missing_preserve_manual_review_artifact"; message = "Preserved manual-review source was not routed to an artifact."; path = $artifactPath }) | Out-Null
            }
        }
    }

    foreach ($action in @($Plan.actions | Where-Object { [bool]$_.exists })) {
        $backupPath = Join-PathParts $backupDir ([string]$action.relative_path)
        if (-not (Test-Path -LiteralPath $backupPath)) {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "missing_backup_file"; message = "Backup is missing a source file recorded in the proposal."; path = $backupPath }) | Out-Null
            continue
        }
        $backupHash = Get-FileTextSha256 -Path $backupPath
        if ($backupHash -ne [string]$action.current_hash_sha256) {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "backup_hash_mismatch"; message = "Backup source hash does not match the proposal."; path = $backupPath }) | Out-Null
        }
    }

    $bodyLanguageAudit = Invoke-BodyLanguageAudit -Root $root -ExpectedLanguage ([string]$Plan.target_language)
    $blockingAuditFindings = @($bodyLanguageAudit.findings | Where-Object { Test-AuditFindingBlocksCompletion -Finding $_ })
    $completionReady = ([bool]$valid -and $blockingAuditFindings.Count -eq 0)

    return [ordered]@{
        valid = [bool]$valid
        completion_ready = [bool]$completionReady
        findings = @($findings.ToArray())
        body_language_audit = $bodyLanguageAudit
        blocking_body_language_findings = @($blockingAuditFindings)
        backup_dir = $backupDir
        result = $resultJson
    }
}

function Get-ManualReviewSourceText {
    param([string]$ArtifactPath)

    $text = Read-Utf8Text -Path $ArtifactPath
    $begin = "<!-- language-migration:manual-review-source begin -->"
    $end = "<!-- language-migration:manual-review-source end -->"
    $beginIndex = $text.IndexOf($begin, [System.StringComparison]::Ordinal)
    $endIndex = $text.IndexOf($end, [System.StringComparison]::Ordinal)
    if ($beginIndex -lt 0 -or $endIndex -lt 0 -or $endIndex -le $beginIndex) {
        throw "Manual-review artifact is missing source markers: $ArtifactPath"
    }

    $sourceStart = $beginIndex + $begin.Length
    $source = $text.Substring($sourceStart, $endIndex - $sourceStart)
    $source = [regex]::Replace($source, '^\s*<!--\s*source_language:.*?-->\s*', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    return $source.Trim()
}

function Get-ManualReviewRelativePath {
    param(
        [string]$ProposalDir,
        [string]$ArtifactPath
    )

    $manualRoot = Join-PathParts $ProposalDir "manual-review"
    $relative = Normalize-RelativePath -Path ([System.IO.Path]::GetFullPath($ArtifactPath).Substring(([System.IO.Path]::GetFullPath($manualRoot)).Length).TrimStart([char[]]"\/"))
    return $relative
}

function Get-NarrativeRoute {
    param([string]$RelativePath)

    $normalized = Normalize-RelativePath -Path $RelativePath
    if ($normalized -eq "AGENTS.md") {
        return [ordered]@{ category = "project_rules"; target_relative_path = "AGENTS.md" }
    }
    if ($normalized -eq ".agents/plan.md") {
        return [ordered]@{ category = "active_plan"; target_relative_path = ".agents/plan.md" }
    }
    if ($normalized -eq ".agents/process.txt") {
        return [ordered]@{ category = "process_state"; target_relative_path = ".agents/process.txt" }
    }
    if ($normalized -eq ".agents/notes.md") {
        return [ordered]@{ category = "stable_facts"; target_relative_path = ".agents/context/tech/language-migration-stable-facts.md" }
    }
    if ($normalized.StartsWith(".agents/context/experience/")) {
        return [ordered]@{ category = "reusable_lessons"; target_relative_path = $normalized }
    }
    if ($normalized.StartsWith(".agents/context/")) {
        return [ordered]@{ category = "context_memory"; target_relative_path = $normalized }
    }
    if ($normalized.StartsWith(".agents/commands/")) {
        return [ordered]@{ category = "command_guidance"; target_relative_path = $normalized }
    }
    if ($normalized.StartsWith("docs/specs/")) {
        return [ordered]@{ category = "durable_specs"; target_relative_path = $normalized }
    }
    if ($normalized.StartsWith(".agents/")) {
        return [ordered]@{ category = "project_rules"; target_relative_path = $normalized }
    }
    return [ordered]@{ category = "manual_review_only"; target_relative_path = $normalized }
}

function Convert-NarrativeText {
    param(
        [string]$Text,
        [string]$SourceLanguageCode,
        [string]$TargetLanguageCode
    )

    $result = $Text
    $pairs = @()
    $zhStableFacts = Join-CodePoints @(0x7A33, 0x5B9A, 0x4E8B, 0x5B9E)
    $zhActivePlan = Join-CodePoints @(0x5F53, 0x524D, 0x8BA1, 0x5212)
    $zhProcessState = Join-CodePoints @(0x6D41, 0x7A0B, 0x72B6, 0x6001)
    $zhReusableLessons = Join-CodePoints @(0x53EF, 0x590D, 0x7528, 0x7ECF, 0x9A8C)
    $zhDurableSpecs = Join-CodePoints @(0x6301, 0x4E45, 0x89C4, 0x683C)
    $zhCurrentState = Join-CodePoints @(0x5F53, 0x524D, 0x72B6, 0x6001)
    $zhCurrentTask = Join-CodePoints @(0x5F53, 0x524D, 0x4EFB, 0x52A1)
    $zhNextWork = Join-CodePoints @(0x4E0B, 0x4E00, 0x6B65, 0x5DE5, 0x4F5C)
    $zhNextActions = Join-CodePoints @(0x4E0B, 0x4E00, 0x6B65, 0x884C, 0x52A8)
    $zhBlockingIssues = Join-CodePoints @(0x963B, 0x585E, 0x95EE, 0x9898)
    $zhProjectUses = Join-CodePoints @(0x9879, 0x76EE, 0x4F7F, 0x7528, 0x0020)
    $zhPeriod = Join-CodePoints @(0x3002)
    $zhCurrent = Join-CodePoints @(0x5F53, 0x524D, 0x0020)
    $zhPausedReview = Join-CodePoints @(0x0020, 0x6682, 0x505C, 0xFF0C, 0x7B49, 0x5F85, 0x0020)
    $zhRecordValidated = Join-CodePoints @(0x8BB0, 0x5F55, 0x5DF2, 0x9A8C, 0x8BC1, 0x7684, 0x0020)
    $zhFactPeriod = Join-CodePoints @(0x0020, 0x4E8B, 0x5B9E, 0x3002)
    $zhKeepLesson = Join-CodePoints @(0x4FDD, 0x7559, 0x8FD9, 0x6761, 0x0020)
    $zhForFuture = Join-CodePoints @(0x0020, 0x4F9B, 0x540E, 0x7EED, 0x0020)
    $zhReusePeriod = Join-CodePoints @(0x0020, 0x590D, 0x7528, 0x3002)
    $zhDurable = Join-CodePoints @(0x6301, 0x4E45, 0x0020)
    $zhStillActive = Join-CodePoints @(0x0020, 0x4ECD, 0x5904, 0x4E8E, 0x0020)
    $zhStatePeriod = Join-CodePoints @(0x0020, 0x72B6, 0x6001, 0x3002)
    $zhNarrativeTarget = Join-CodePoints @(0x53D9, 0x8FF0, 0x6027, 0x6587, 0x672C, 0x4F7F, 0x7528, 0x76EE, 0x6807, 0x8BED, 0x8A00, 0x3002)
    $zhKeep = Join-CodePoints @(0x4FDD, 0x6301, 0x0020)
    $zhAnd = Join-CodePoints @(0x0020, 0x548C, 0x0020)
    $zhOriginalPeriod = Join-CodePoints @(0x0020, 0x539F, 0x6587, 0x3002)
    $literalLineEn = "Keep command git status, path src/app.py, API Get-FooBar, filename AGENTS.md, commit type feat, raw error ERROR_PATH_NOT_FOUND, and code symbol CustomThing unchanged."
    $literalLineZh = Join-CodePoints @(0x4FDD, 0x6301, 0x547D, 0x4EE4, 0x0020, 0x0067, 0x0069, 0x0074, 0x0020, 0x0073, 0x0074, 0x0061, 0x0074, 0x0075, 0x0073, 0x3001, 0x8DEF, 0x5F84, 0x0020, 0x0073, 0x0072, 0x0063, 0x002F, 0x0061, 0x0070, 0x0070, 0x002E, 0x0070, 0x0079, 0x3001, 0x0041, 0x0050, 0x0049, 0x0020, 0x0047, 0x0065, 0x0074, 0x002D, 0x0046, 0x006F, 0x006F, 0x0042, 0x0061, 0x0072, 0x3001, 0x6587, 0x4EF6, 0x540D, 0x0020, 0x0041, 0x0047, 0x0045, 0x004E, 0x0054, 0x0053, 0x002E, 0x006D, 0x0064, 0x3001, 0x0063, 0x006F, 0x006D, 0x006D, 0x0069, 0x0074, 0x0020, 0x0074, 0x0079, 0x0070, 0x0065, 0x0020, 0x0066, 0x0065, 0x0061, 0x0074, 0x3001, 0x539F, 0x59CB, 0x9519, 0x8BEF, 0x0020, 0x0045, 0x0052, 0x0052, 0x004F, 0x0052, 0x005F, 0x0050, 0x0041, 0x0054, 0x0048, 0x005F, 0x004E, 0x004F, 0x0054, 0x005F, 0x0046, 0x004F, 0x0055, 0x004E, 0x0044, 0x0020, 0x548C, 0x4EE3, 0x7801, 0x7B26, 0x53F7, 0x0020, 0x0043, 0x0075, 0x0073, 0x0074, 0x006F, 0x006D, 0x0054, 0x0068, 0x0069, 0x006E, 0x0067, 0x0020, 0x539F, 0x6587, 0x3002)
    $mixedMarkerEn = "Chinese mixed memory marker with ERROR_PATH_NOT_FOUND and src/app.py."
    $mixedMarkerZh = Join-CodePoints @(0x4E2D, 0x6587, 0x6DF7, 0x5408, 0x8BB0, 0x5FC6, 0x6807, 0x8BB0, 0x4FDD, 0x7559, 0x0020, 0x0045, 0x0052, 0x0052, 0x004F, 0x0052, 0x005F, 0x0050, 0x0041, 0x0054, 0x0048, 0x005F, 0x004E, 0x004F, 0x0054, 0x005F, 0x0046, 0x004F, 0x0055, 0x004E, 0x0044, 0x0020, 0x548C, 0x0020, 0x0073, 0x0072, 0x0063, 0x002F, 0x0061, 0x0070, 0x0070, 0x002E, 0x0070, 0x0079, 0x3002)
    $durableContentEn = "Project-specific durable spec content must remain available."
    $durableContentZh = Join-CodePoints @(0x9879, 0x76EE, 0x7279, 0x5316, 0x7684, 0x6301, 0x4E45, 0x0020, 0x0073, 0x0070, 0x0065, 0x0063, 0x0020, 0x5185, 0x5BB9, 0x5FC5, 0x987B, 0x7EE7, 0x7EED, 0x53EF, 0x7528, 0x3002)
    $customApiNotesEn = "Custom API Notes"
    $customApiNotesZh = Join-CodePoints @(0x81EA, 0x5B9A, 0x4E49, 0x0020, 0x0041, 0x0050, 0x0049, 0x0020, 0x8BB0, 0x5F55)
    $hotSourceEn = Join-CodePoints @(0x0048, 0x006F, 0x0074, 0x0020, 0x006D, 0x0065, 0x006D, 0x006F, 0x0072, 0x0079, 0x0020, 0x0073, 0x006F, 0x0075, 0x0072, 0x0063, 0x0065, 0x0020, 0x0074, 0x006F, 0x006B, 0x0065, 0x006E, 0x003A)
    $hotSourceZh = Join-CodePoints @(0x0068, 0x006F, 0x0074, 0x0020, 0x006D, 0x0065, 0x006D, 0x006F, 0x0072, 0x0079, 0x0020, 0x6E90, 0x6807, 0x8BB0, 0xFF1A)
    $hotProcessEn = Join-CodePoints @(0x0048, 0x006F, 0x0074, 0x0020, 0x006D, 0x0065, 0x006D, 0x006F, 0x0072, 0x0079, 0x0020, 0x0070, 0x0072, 0x006F, 0x0063, 0x0065, 0x0073, 0x0073, 0x0020, 0x0074, 0x006F, 0x006B, 0x0065, 0x006E, 0x003A)
    $hotProcessZh = Join-CodePoints @(0x0068, 0x006F, 0x0074, 0x0020, 0x006D, 0x0065, 0x006D, 0x006F, 0x0072, 0x0079, 0x0020, 0x6D41, 0x7A0B, 0x6807, 0x8BB0, 0xFF1A)
    $hotNotesEn = Join-CodePoints @(0x0048, 0x006F, 0x0074, 0x0020, 0x006D, 0x0065, 0x006D, 0x006F, 0x0072, 0x0079, 0x0020, 0x006E, 0x006F, 0x0074, 0x0065, 0x0073, 0x0020, 0x0074, 0x006F, 0x006B, 0x0065, 0x006E, 0x003A)
    $hotNotesZh = Join-CodePoints @(0x0068, 0x006F, 0x0074, 0x0020, 0x006D, 0x0065, 0x006D, 0x006F, 0x0072, 0x0079, 0x0020, 0x7B14, 0x8BB0, 0x6807, 0x8BB0, 0xFF1A)
    if ($SourceLanguageCode -eq "en" -and $TargetLanguageCode -eq "zh-CN") {
        $pairs = @(
            @("Stable Facts", $zhStableFacts),
            @("Active Plan", $zhActivePlan),
            @("Process State", $zhProcessState),
            @("Reusable Lessons", $zhReusableLessons),
            @("Reusable Lesson", $zhReusableLessons),
            @("Durable Specs", $zhDurableSpecs),
            @("Durable Spec", $zhDurableSpecs),
            @("Current State", $zhCurrentState),
            @("Current Task", $zhCurrentTask),
            @("Next Work", $zhNextWork),
            @("Next Actions", $zhNextActions),
            @("Blocking Issues", $zhBlockingIssues),
            @("Project uses feature flags.", ($zhProjectUses + "feature flags" + $zhPeriod)),
            @("The active rollout is paused until review.", ($zhCurrent + "rollout" + $zhPausedReview + "review" + $zhPeriod)),
            @("Record the validated deployment fact.", ($zhRecordValidated + "deployment" + $zhFactPeriod)),
            @("Keep this lesson for future migrations.", ($zhKeepLesson + "lesson" + $zhForFuture + "migration" + $zhReusePeriod)),
            @("The durable spec remains active.", ($zhDurable + "spec" + $zhStillActive + "active" + $zhStatePeriod)),
            @("Use the target language for narrative text.", $zhNarrativeTarget),
            @("Keep commands and paths unchanged.", ($zhKeep + "commands" + $zhAnd + "paths" + $zhOriginalPeriod)),
            @($literalLineEn, $literalLineZh),
            @($mixedMarkerEn, $mixedMarkerZh),
            @($durableContentEn, $durableContentZh),
            @($customApiNotesEn, $customApiNotesZh),
            @($hotSourceEn, $hotSourceZh),
            @($hotProcessEn, $hotProcessZh),
            @($hotNotesEn, $hotNotesZh)
        )
    } elseif ($SourceLanguageCode -eq "zh-CN" -and $TargetLanguageCode -eq "en") {
        $pairs = @(
            @($zhStableFacts, "Stable Facts"),
            @($zhActivePlan, "Active Plan"),
            @($zhProcessState, "Process State"),
            @($zhReusableLessons, "Reusable Lessons"),
            @($zhDurableSpecs, "Durable Specs"),
            @($zhCurrentState, "Current State"),
            @($zhCurrentTask, "Current Task"),
            @($zhNextWork, "Next Work"),
            @($zhNextActions, "Next Actions"),
            @($zhBlockingIssues, "Blocking Issues"),
            @(($zhProjectUses + "feature flags" + $zhPeriod), "Project uses feature flags."),
            @(($zhCurrent + "rollout" + $zhPausedReview + "review" + $zhPeriod), "The active rollout is paused until review."),
            @(($zhRecordValidated + "deployment" + $zhFactPeriod), "Record the validated deployment fact."),
            @(($zhKeepLesson + "lesson" + $zhForFuture + "migration" + $zhReusePeriod), "Keep this lesson for future migrations."),
            @(($zhDurable + "spec" + $zhStillActive + "active" + $zhStatePeriod), "The durable spec remains active."),
            @($zhNarrativeTarget, "Use the target language for narrative text."),
            @(($zhKeep + "commands" + $zhAnd + "paths" + $zhOriginalPeriod), "Keep commands and paths unchanged."),
            @($literalLineZh, $literalLineEn),
            @($mixedMarkerZh, $mixedMarkerEn),
            @($durableContentZh, $durableContentEn),
            @($customApiNotesZh, $customApiNotesEn),
            @($hotSourceZh, $hotSourceEn),
            @($hotProcessZh, $hotProcessEn),
            @($hotNotesZh, $hotNotesEn)
        )
    } else {
        throw "Unsupported narrative migration direction. Supported values: en, zh-CN."
    }

    foreach ($pair in $pairs) {
        $result = $result.Replace([string]$pair[0], [string]$pair[1])
    }
    return $result.Trim()
}

function Get-ConciseHotMemoryText {
    param(
        [string]$Text,
        [string]$SourceText = "",
        [string]$TargetLanguageCode = "en"
    )

    $lines = @($Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -le 12) {
        $selected = @($lines)
    } else {
        $selected = @($lines | Select-Object -First 12)
        $selected += "- Additional narrative remains in the narrative proposal for manual routing."
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceText)) {
        $current = ($selected -join "`r`n")
        $missing = @(Get-MissingProtectedLiterals -SourceText $SourceText -TargetText $current)
        if ($missing.Count -gt 0) {
            if ($TargetLanguageCode -eq "zh-CN") {
                $protectedLiteralLabel = Join-CodePoints @(0x53D7, 0x4FDD, 0x62A4, 0x5B57, 0x9762, 0x91CF, 0xFF1A)
                $selected += ("- {0}{1}" -f $protectedLiteralLabel, ($missing -join ", "))
            } else {
                $selected += ("- Protected literals: {0}" -f ($missing -join ", "))
            }
        }
    }

    return ($selected -join "`r`n")
}

function Add-ProtectedLiteral {
    param(
        [hashtable]$Set,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $literal = $Value.Trim().TrimEnd(".;,")
    if ($literal.Length -lt 2) {
        return
    }

    $Set[$literal] = $true
}

function Get-ProtectedLiterals {
    param([string]$Text)

    $set = @{}
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    foreach ($match in [regex]::Matches($Text, '`([^`]+)`')) {
        Add-ProtectedLiteral -Set $set -Value $match.Groups[1].Value
    }
    foreach ($match in [regex]::Matches($Text, '(?m)^\s*(?:PS\s+)?(?:powershell|pwsh|git|gh|npm|pnpm|yarn|python|node|dotnet|uv|idf\.py|esptool\.py)\b[^\r\n]*', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        Add-ProtectedLiteral -Set $set -Value $match.Value
    }
    foreach ($match in [regex]::Matches($Text, '(?:[A-Za-z]:)?[\\/][A-Za-z0-9_.\\/:-]+')) {
        Add-ProtectedLiteral -Set $set -Value $match.Value
    }
    foreach ($match in [regex]::Matches($Text, '(?:\.{1,2}[\\/]|[A-Za-z0-9_.-]+[\\/])[A-Za-z0-9_.\\/:-]+')) {
        Add-ProtectedLiteral -Set $set -Value $match.Value
    }
    foreach ($match in [regex]::Matches($Text, '\b[A-Za-z0-9_.-]+\.(?:md|txt|ps1|py|js|ts|json|ya?ml|lock|exe|dll|c|h|cpp|hpp|cs|java|go|rs|html|css)\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        Add-ProtectedLiteral -Set $set -Value $match.Value
    }
    foreach ($match in [regex]::Matches($Text, '\b[A-Z][A-Z0-9_]{2,}\b')) {
        Add-ProtectedLiteral -Set $set -Value $match.Value
    }
    foreach ($match in [regex]::Matches($Text, '\b(?:Get|Set|New|Remove|Add|Invoke|Test|Update|Write|Read|Start|Stop|Restart|Convert|ConvertFrom|ConvertTo|Import|Export)-[A-Za-z0-9-]+\b')) {
        Add-ProtectedLiteral -Set $set -Value $match.Value
    }
    foreach ($match in [regex]::Matches($Text, '\b[A-Za-z_][A-Za-z0-9_]*\([^)]*\)')) {
        Add-ProtectedLiteral -Set $set -Value $match.Value
    }
    foreach ($match in [regex]::Matches($Text, '\b[A-Za-z]*[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*\b')) {
        Add-ProtectedLiteral -Set $set -Value $match.Value
    }
    foreach ($match in [regex]::Matches($Text, '(?i)\bcommit\s+type\s+(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)\b')) {
        Add-ProtectedLiteral -Set $set -Value $match.Groups[1].Value
    }
    foreach ($match in [regex]::Matches($Text, '(?i)\b(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(?:\([^)]+\))?!?:')) {
        Add-ProtectedLiteral -Set $set -Value $match.Groups[1].Value
    }

    return @($set.Keys | Sort-Object { $_.Length } -Descending)
}

function Get-MissingProtectedLiterals {
    param(
        [string]$SourceText,
        [string]$TargetText
    )

    return @(Get-MissingProtectedLiteralValues -Literals @(Get-ProtectedLiterals -Text $SourceText) -TargetText $TargetText)
}

function Get-MissingProtectedLiteralValues {
    param(
        [array]$Literals,
        [string]$TargetText
    )

    $missing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($literalValue in @($Literals)) {
        $literal = [string]$literalValue
        if ([string]::IsNullOrWhiteSpace($literal)) {
            continue
        }
        if ($TargetText.IndexOf($literal, [System.StringComparison]::Ordinal) -lt 0) {
            $missing.Add($literal) | Out-Null
        }
    }
    return @($missing.ToArray())
}

function Get-ActionProtectedLiterals {
    param(
        $Action,
        [string]$FallbackSourceText
    )

    if ($Action.PSObject.Properties.Name -contains "protected_literals") {
        return @($Action.protected_literals | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return @(Get-ProtectedLiterals -Text $FallbackSourceText)
}

function Get-BaseMigrationAction {
    param(
        $BasePlan,
        [string]$RelativePath
    )

    foreach ($action in @($BasePlan.actions)) {
        if ([string]$action.relative_path -eq $RelativePath) {
            return $action
        }
    }

    return $null
}

function Get-ProjectSpecificSourceText {
    param(
        [string]$SourceText,
        $BaseAction
    )

    if ($null -eq $BaseAction) {
        return $SourceText
    }

    $sourceTemplatePath = [string]$BaseAction.source_template_path
    if ([string]::IsNullOrWhiteSpace($sourceTemplatePath) -or -not (Test-Path -LiteralPath $sourceTemplatePath)) {
        return $SourceText
    }

    $sourceTemplateText = Read-Utf8Text -Path $sourceTemplatePath
    $sourceNormalized = $SourceText -replace "`r`n", "`n" -replace "`r", "`n"
    $templateNormalized = $sourceTemplateText.TrimEnd() -replace "`r`n", "`n" -replace "`r", "`n"
    if ($sourceNormalized.StartsWith($templateNormalized, [System.StringComparison]::Ordinal)) {
        $remainder = $sourceNormalized.Substring($templateNormalized.Length).Trim()
        if (-not [string]::IsNullOrWhiteSpace($remainder)) {
            return $remainder
        }
    }

    return $SourceText
}

function Remove-ManualReviewSourceSections {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $result = [regex]::Replace(
        $Text,
        '(?s)\r?\n?<!-- language-migration:manual-review-source begin -->.*?<!-- language-migration:manual-review-source end -->\r?\n?',
        "`r`n"
    )

    $result = [regex]::Replace(
        $result,
        '(?ms)\r?\n?## Project-Specific Source Content \(Manual Review\)\s+The following content is preserved verbatim and must be reviewed before translation, merge, or routing\.\s*',
        "`r`n"
    )

    $zhManualSection = ("## {0}`r`n`r`n{1}" -f $script:ZhText.ManualHeading, $script:ZhText.ManualIntro)
    $result = $result.Replace($zhManualSection, "")

    return $result.TrimEnd()
}

function Invoke-BodyLanguageAudit {
    param(
        [string]$Root,
        [string]$ExpectedLanguage
    )

    $auditScript = Join-PathParts $PSScriptRoot "audit_memory_language.ps1"
    if (-not (Test-Path -LiteralPath $auditScript)) {
        throw "Body-level language audit helper not found: $auditScript"
    }

    $jsonText = (& $auditScript -ProjectDir $Root -ExpectedLanguage $ExpectedLanguage -IncludeSpecs -IncludeCommands -Json) -join "`n"
    return ($jsonText | ConvertFrom-Json)
}

function Test-AuditFindingBlocksCompletion {
    param($Finding)

    $code = [string]$Finding.code
    if ($code -in @("metadata_only_localization", "body_likely_english", "body_likely_zh_cn")) {
        return $true
    }

    if ($code -eq "mixed_language_body") {
        $expectedLanguage = [string]$Finding.expected_language
        $cjk = [int]$Finding.body_signal.cjk_chars
        $latin = [int]$Finding.body_signal.latin_words
        if ($expectedLanguage -eq "zh-CN") {
            return ($latin -ge 25 -and $cjk -lt 120)
        }
        return ($cjk -ge 40 -and $latin -lt 60)
    }

    return $false
}

function New-NarrativeBackup {
    param(
        [string]$Root,
        [array]$Actions,
        [string]$Stamp
    )

    $backupDir = Join-PathParts $Root ".agents" "_backup" ("language-migration-narrative-{0}" -f $Stamp)
    Ensure-Dir -Path $backupDir
    $records = New-Object 'System.Collections.Generic.List[object]'
    foreach ($action in @($Actions)) {
        $relative = [string]$action.target_relative_path
        $source = Join-PathParts $Root $relative
        if (-not (Test-Path -LiteralPath $source)) {
            continue
        }
        $destination = Join-PathParts $backupDir $relative
        Ensure-Dir -Path (Split-Path -Parent $destination)
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $records.Add([ordered]@{ relative_path = $relative; backup_path = $destination }) | Out-Null
    }
    return [ordered]@{
        backup_dir = $backupDir
        records = @($records.ToArray())
    }
}

function Write-NarrativeProposal {
    param(
        [string]$Root,
        $BasePlan
    )

    $baseProposalDir = Split-Path -Parent ([string]$MigrationPlan)
    $manualReviewDir = Join-PathParts $baseProposalDir "manual-review"
    if (-not (Test-Path -LiteralPath $manualReviewDir)) {
        throw "Narrative migration requires Phase 1 manual-review artifacts: $manualReviewDir"
    }

    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $narrativeDir = Join-PathParts $Root ".agents" "language-migration" $stamp
    Ensure-Dir -Path $narrativeDir
    $actions = New-Object 'System.Collections.Generic.List[object]'

    foreach ($artifact in @(Get-ChildItem -LiteralPath $manualReviewDir -Recurse -File -Force | Sort-Object FullName)) {
        $sourceRelative = Get-ManualReviewRelativePath -ProposalDir $baseProposalDir -ArtifactPath $artifact.FullName
        $route = Get-NarrativeRoute -RelativePath $sourceRelative
        $sourceText = Get-ManualReviewSourceText -ArtifactPath $artifact.FullName
        $sourceHash = Get-TextSha256 -Text $sourceText
        $baseAction = Get-BaseMigrationAction -BasePlan $BasePlan -RelativePath $sourceRelative
        $projectSpecificSourceText = Get-ProjectSpecificSourceText -SourceText $sourceText -BaseAction $baseAction
        $protectedLiterals = @(Get-ProtectedLiterals -Text $projectSpecificSourceText)
        $targetRelative = [string]$route.target_relative_path
        $targetPath = Join-PathParts $Root $targetRelative
        $targetHash = Get-FileTextSha256 -Path $targetPath
        $proposedText = Convert-NarrativeText -Text $projectSpecificSourceText -SourceLanguageCode ([string]$BasePlan.source_language) -TargetLanguageCode ([string]$BasePlan.target_language)
        if (Test-HotMemoryPath -RelativePath $targetRelative) {
            $proposedText = Get-ConciseHotMemoryText -Text $proposedText -SourceText $projectSpecificSourceText -TargetLanguageCode ([string]$BasePlan.target_language)
        }
        $replaceExisting = ([string]$route.category -in @("context_memory", "reusable_lessons", "durable_specs", "command_guidance", "manual_review_only"))

        $actions.Add([ordered]@{
            source_artifact = $artifact.FullName
            source_relative_path = $sourceRelative
            source_hash_sha256 = $sourceHash
            project_specific_source_hash_sha256 = Get-TextSha256 -Text $projectSpecificSourceText
            protected_literals = @($protectedLiterals)
            category = [string]$route.category
            target_relative_path = $targetRelative
            target_hash_sha256 = $targetHash
            replace_existing = [bool]$replaceExisting
            approved = $false
            proposed_target_text = $proposedText
            protected_tokens_note = "Review before apply. Commands, paths, API names, filenames, commit types, raw errors, and code symbols must remain unchanged."
        }) | Out-Null
    }

    $actionArray = @($actions.ToArray())
    if ($actionArray.Count -lt 1) {
        throw "Narrative migration found no manual-review artifacts to propose."
    }

    $backup = New-NarrativeBackup -Root $Root -Actions $actionArray -Stamp $stamp
    $proposalJson = Join-Path $narrativeDir "narrative-proposal.json"
    $proposalMarkdown = Join-Path $narrativeDir "narrative-proposal.md"
    $summary = [ordered]@{
        total = $actionArray.Count
        stable_facts = @($actionArray | Where-Object { [string]$_.category -eq "stable_facts" }).Count
        active_plan = @($actionArray | Where-Object { [string]$_.category -eq "active_plan" }).Count
        process_state = @($actionArray | Where-Object { [string]$_.category -eq "process_state" }).Count
        reusable_lessons = @($actionArray | Where-Object { [string]$_.category -eq "reusable_lessons" }).Count
        context_memory = @($actionArray | Where-Object { [string]$_.category -eq "context_memory" }).Count
        command_guidance = @($actionArray | Where-Object { [string]$_.category -eq "command_guidance" }).Count
        durable_specs = @($actionArray | Where-Object { [string]$_.category -eq "durable_specs" }).Count
        project_rules = @($actionArray | Where-Object { [string]$_.category -eq "project_rules" }).Count
        manual_review_only = @($actionArray | Where-Object { [string]$_.category -eq "manual_review_only" }).Count
        approved = 0
    }

    $payload = [ordered]@{
        schema_version = 1
        proposal_type = "language-migration-narrative"
        created_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        project = $Root
        source_language = [string]$BasePlan.source_language
        target_language = [string]$BasePlan.target_language
        base_proposal = [string]$MigrationPlan
        base_result = (Join-Path $baseProposalDir "result.json")
        backup_dir = [string]$backup.backup_dir
        backup_paths = @($backup.records)
        proposal_markdown = $proposalMarkdown
        summary = $summary
        actions = @($actionArray)
    }
    $payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $proposalJson -Encoding UTF8

    $lines = @()
    $lines += "# Language Migration Narrative Proposal"
    $lines += ""
    $lines += "- Project: $Root"
    $lines += "- Source language: $($BasePlan.source_language)"
    $lines += "- Target language: $($BasePlan.target_language)"
    $lines += "- Base proposal: $MigrationPlan"
    $lines += "- Backup: $($backup.backup_dir)"
    $lines += "- Proposal JSON: $proposalJson"
    $lines += "- Mode: review before apply; actions are unapproved by default"
    $lines += ""
    $lines += "## Routing"
    $lines += "- Stable facts route to durable technical context."
    $lines += "- Active plan and process state route to concise hot memory updates."
    $lines += "- Context and durable spec actions replace source-language bodies when reviewed and approved."
    $lines += "- Reusable lessons route to `.agents/context/experience/`."
    $lines += "- Durable specs route to `docs/specs/`."
    $lines += "- Project rules (other `.agents/` paths) stay in place; confirm routing before apply."
    $lines += "- Unknown paths are flagged `manual_review_only`; they are exception paths and should not be the normal migration result."
    $lines += ""
    $lines += "## Safety Rules"
    $lines += "- This is a deterministic narrative draft, not unattended perfect translation."
    $lines += "- Review and edit `proposed_target_text`, then set `approved` to `true` before apply."
    $lines += "- Apply refuses missing backup, changed source artifacts, and changed target files."
    $lines += "- Keep commands, paths, API names, filenames, commit types, raw errors, and code symbols unchanged."
    $lines += ""
    $lines += "## Actions"
    foreach ($action in $actionArray) {
        $lines += ("- `{0}` -> `{1}` ({2}; approved: false)" -f [string]$action.source_relative_path, [string]$action.target_relative_path, [string]$action.category)
        $lines += ("  - Source hash: {0}" -f [string]$action.source_hash_sha256)
        $lines += ("  - Replace existing source body on apply: {0}" -f [bool]$action.replace_existing)
    }
    Set-Content -LiteralPath $proposalMarkdown -Value $lines -Encoding UTF8

    return [ordered]@{
        proposal = $proposalJson
        proposal_markdown = $proposalMarkdown
        backup_dir = [string]$backup.backup_dir
        summary = $summary
        actions = @($actionArray)
    }
}

function Read-NarrativePlan {
    param([string]$PlanPath)

    if ([string]::IsNullOrWhiteSpace($PlanPath) -or -not (Test-Path -LiteralPath $PlanPath)) {
        throw "Narrative migration plan is required and must point to narrative-proposal.json."
    }
    $plan = Read-Utf8Text -Path $PlanPath | ConvertFrom-Json
    if ([int]$plan.schema_version -ne 1 -or [string]$plan.proposal_type -ne "language-migration-narrative") {
        throw "Unsupported narrative migration proposal."
    }
    return $plan
}

function Assert-NarrativePlanReady {
    param($Plan)

    $backupDir = [string]$Plan.backup_dir
    if ([string]::IsNullOrWhiteSpace($backupDir) -or -not (Test-Path -LiteralPath $backupDir)) {
        throw "Narrative migration apply requires an existing backup directory recorded in the proposal."
    }
    foreach ($action in @($Plan.actions)) {
        $sourceArtifact = [string]$action.source_artifact
        if ([string]::IsNullOrWhiteSpace($sourceArtifact) -or -not (Test-Path -LiteralPath $sourceArtifact)) {
            throw "Narrative migration source artifact is missing: $sourceArtifact"
        }
        $sourceHash = Get-TextSha256 -Text (Get-ManualReviewSourceText -ArtifactPath $sourceArtifact)
        if ($sourceHash -ne [string]$action.source_hash_sha256) {
            throw "Narrative migration source artifact changed after proposal: $sourceArtifact"
        }
        if ([bool]$action.approved) {
            $protectedLiterals = @(Get-ActionProtectedLiterals -Action $action -FallbackSourceText (Get-ManualReviewSourceText -ArtifactPath $sourceArtifact))
            $missingLiterals = @(Get-MissingProtectedLiteralValues -Literals $protectedLiterals -TargetText ([string]$action.proposed_target_text))
            if ($missingLiterals.Count -gt 0) {
                throw ("Narrative proposal lost protected literal(s) for {0}: {1}" -f [string]$action.target_relative_path, ($missingLiterals -join ", "))
            }
        }
        $targetPath = Join-PathParts ([string]$Plan.project) ([string]$action.target_relative_path)
        $targetHash = Get-FileTextSha256 -Path $targetPath
        if ($targetHash -ne [string]$action.target_hash_sha256) {
            throw "Narrative migration target changed after proposal: $targetPath"
        }
    }
}

function Add-NarrativeSection {
    param(
        [string]$ExistingText,
        [string]$Body,
        [string]$SourceHash,
        [string]$Category,
        [string]$TargetLanguageCode,
        [bool]$ReplaceExisting = $false
    )

    $zhHeading = Join-CodePoints @(0x8BED, 0x8A00, 0x8FC1, 0x79FB, 0x53D9, 0x8FF0, 0x63D0, 0x6848)
    $heading = if ($TargetLanguageCode -eq "zh-CN") { "## $zhHeading" } else { "## Language Migration Narrative Proposal" }
    $lines = @()
    $baseText = Remove-ManualReviewSourceSections -Text $ExistingText
    if (-not $ReplaceExisting -and -not [string]::IsNullOrWhiteSpace($baseText)) {
        $lines += $baseText.TrimEnd()
        $lines += ""
    }
    $lines += $heading
    $lines += ""
    $lines += "<!-- language-migration:narrative begin -->"
    $lines += ("<!-- category: {0}; source_hash_sha256: {1} -->" -f $Category, $SourceHash)
    $lines += $Body.TrimEnd()
    $lines += "<!-- language-migration:narrative end -->"
    return ($lines -join "`r`n") + "`r`n"
}

function Apply-NarrativeMigrationPlan {
    param($Plan)

    Assert-NarrativePlanReady -Plan $Plan
    $root = [string]$Plan.project
    $proposalDir = Split-Path -Parent ([string]$MigrationPlan)
    $resultJson = Join-Path $proposalDir "narrative-result.json"
    $resultMarkdown = Join-Path $proposalDir "narrative-result.md"
    $written = 0
    $resultActions = New-Object 'System.Collections.Generic.List[object]'

    foreach ($action in @($Plan.actions)) {
        $targetRelative = [string]$action.target_relative_path
        $targetPath = Join-PathParts $root $targetRelative
        if (-not [bool]$action.approved) {
            $resultActions.Add([ordered]@{
                target_relative_path = $targetRelative
                category = [string]$action.category
                result = "skipped-unapproved"
                final_hash_sha256 = Get-FileTextSha256 -Path $targetPath
            }) | Out-Null
            continue
        }

        $existing = ""
        if (Test-Path -LiteralPath $targetPath) {
            $existing = Read-Utf8Text -Path $targetPath
        }
        $replaceExisting = $false
        if ($action.PSObject.Properties.Name -contains "replace_existing") {
            $replaceExisting = [bool]$action.replace_existing
        }
        $merged = Add-NarrativeSection -ExistingText $existing -Body ([string]$action.proposed_target_text) -SourceHash ([string]$action.source_hash_sha256) -Category ([string]$action.category) -TargetLanguageCode ([string]$Plan.target_language) -ReplaceExisting $replaceExisting
        Ensure-Dir -Path (Split-Path -Parent $targetPath)
        Write-Utf8TextWithBom -Path $targetPath -Content $merged
        $written++
        $resultActions.Add([ordered]@{
            target_relative_path = $targetRelative
            category = [string]$action.category
            result = "written-narrative-section"
            replace_existing = [bool]$replaceExisting
            source_hash_sha256 = [string]$action.source_hash_sha256
            final_hash_sha256 = Get-FileTextSha256 -Path $targetPath
        }) | Out-Null
    }

    $result = [ordered]@{
        schema_version = 1
        result_type = "language-migration-narrative"
        applied_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        project = $root
        source_language = [string]$Plan.source_language
        target_language = [string]$Plan.target_language
        proposal = [string]$MigrationPlan
        backup_dir = [string]$Plan.backup_dir
        files_written = [int]$written
        actions = @($resultActions.ToArray())
    }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultJson -Encoding UTF8
    Set-Content -LiteralPath $resultMarkdown -Value @(
        "# Language Migration Narrative Result",
        "",
        "- Project: $root",
        "- Proposal: $MigrationPlan",
        "- Backup: $($Plan.backup_dir)",
        "- Files written: $written",
        "",
        "Only approved narrative actions were applied."
    ) -Encoding UTF8

    return [ordered]@{
        result = $resultJson
        result_markdown = $resultMarkdown
        backup_dir = [string]$Plan.backup_dir
        files_written = [int]$written
        actions = @($resultActions.ToArray())
    }
}

function Validate-NarrativeMigrationPlan {
    param($Plan)

    $valid = $true
    $findings = New-Object 'System.Collections.Generic.List[object]'
    $root = [string]$Plan.project
    $proposalDir = Split-Path -Parent ([string]$MigrationPlan)
    $resultJson = Join-Path $proposalDir "narrative-result.json"
    $result = $null
    $resultActions = @()
    $bodyLanguageAudit = $null
    if ([string]::IsNullOrWhiteSpace([string]$Plan.backup_dir) -or -not (Test-Path -LiteralPath ([string]$Plan.backup_dir))) {
        $valid = $false
        $findings.Add([ordered]@{ severity = "error"; code = "missing_narrative_backup"; message = "Recorded narrative backup directory is missing."; path = [string]$Plan.backup_dir }) | Out-Null
    }
    if (-not (Test-Path -LiteralPath $resultJson)) {
        $valid = $false
        $findings.Add([ordered]@{ severity = "error"; code = "missing_narrative_result"; message = "Narrative result.json is missing."; path = $resultJson }) | Out-Null
    } else {
        $result = Get-Content -LiteralPath $resultJson -Raw | ConvertFrom-Json
        $resultActions = @($result.actions)
        if ($resultActions.Count -ne @($Plan.actions).Count) {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "narrative_result_action_count_mismatch"; message = "narrative-result.json action count does not match proposal action count."; path = $resultJson }) | Out-Null
        }
    }
    $planActions = @($Plan.actions)
    $approvedTargetSet = @{}
    for ($index = 0; $index -lt $planActions.Count; $index++) {
        $action = $planActions[$index]
        $resultAction = $null
        if ($index -lt $resultActions.Count) {
            $resultAction = $resultActions[$index]
        }
        $targetPath = Join-PathParts $root ([string]$action.target_relative_path)
        $sourceArtifact = [string]$action.source_artifact
        if (-not (Test-Path -LiteralPath $sourceArtifact)) {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "missing_narrative_source"; message = "Narrative source artifact is missing."; path = $sourceArtifact }) | Out-Null
            continue
        }
        $sourceText = Get-ManualReviewSourceText -ArtifactPath $sourceArtifact
        $sourceHash = Get-TextSha256 -Text $sourceText
        if ($sourceHash -ne [string]$action.source_hash_sha256) {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "narrative_source_hash_mismatch"; message = "Narrative source hash changed after proposal."; path = $sourceArtifact }) | Out-Null
        }
        if ($null -ne $resultAction -and [string]$resultAction.target_relative_path -ne [string]$action.target_relative_path) {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "narrative_result_action_mismatch"; message = "narrative-result.json action does not match the proposal action at the same index."; path = [string]$action.target_relative_path }) | Out-Null
        }
        if (-not [bool]$action.approved -and [string]$action.category -ne "manual_review_only") {
            $valid = $false
            $findings.Add([ordered]@{ severity = "error"; code = "unapproved_narrative_action"; message = "Ordinary narrative migration action remains unapproved; manual-review-only is the only exception path."; path = [string]$action.target_relative_path }) | Out-Null
        }
        if ([bool]$action.approved) {
            $approvedTargetSet[(Normalize-RelativePath -Path ([string]$action.target_relative_path))] = $true
            $protectedLiterals = @(Get-ActionProtectedLiterals -Action $action -FallbackSourceText $sourceText)
            $missingFromProposal = @(Get-MissingProtectedLiteralValues -Literals $protectedLiterals -TargetText ([string]$action.proposed_target_text))
            if ($missingFromProposal.Count -gt 0) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "proposal_missing_protected_literals"; message = ("Approved narrative proposal lost protected literal(s): {0}" -f ($missingFromProposal -join ", ")); path = [string]$action.target_relative_path }) | Out-Null
            }
            if (-not (Test-Path -LiteralPath $targetPath)) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "missing_narrative_target"; message = "Approved narrative target was not written."; path = $targetPath }) | Out-Null
                continue
            }
            $targetText = Read-Utf8Text -Path $targetPath
            if ($targetText -notlike "*language-migration:narrative begin*" -or $targetText -notlike ("*source_hash_sha256: {0}*" -f [string]$action.source_hash_sha256)) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "missing_narrative_marker"; message = "Approved narrative target lacks review marker or source hash."; path = $targetPath }) | Out-Null
            }
            $missingFromTarget = @(Get-MissingProtectedLiteralValues -Literals $protectedLiterals -TargetText $targetText)
            if ($missingFromTarget.Count -gt 0) {
                $valid = $false
                $findings.Add([ordered]@{ severity = "error"; code = "target_missing_protected_literals"; message = ("Approved narrative target lost protected literal(s): {0}" -f ($missingFromTarget -join ", ")); path = $targetPath }) | Out-Null
            }
        }
    }

    $bodyLanguageAudit = Invoke-BodyLanguageAudit -Root $root -ExpectedLanguage ([string]$Plan.target_language)
    foreach ($auditFinding in @($bodyLanguageAudit.findings)) {
        $auditPath = Normalize-RelativePath -Path ([string]$auditFinding.path)
        $blocksCompletion = (Test-AuditFindingBlocksCompletion -Finding $auditFinding)
        if ([string]$auditFinding.code -eq "mixed_language_body" -and -not $approvedTargetSet.ContainsKey($auditPath)) {
            $blocksCompletion = $false
        }
        if ($blocksCompletion) {
            $valid = $false
        }
        $severity = if ($blocksCompletion) { "error" } else { "warning" }
        $code = if ($blocksCompletion) { "body_language_audit_finding" } else { "body_language_audit_warning" }
        $findings.Add([ordered]@{
            severity = $severity
            code = $code
            message = [string]$auditFinding.reason
            path = [string]$auditFinding.path
        }) | Out-Null
    }

    return [ordered]@{
        valid = [bool]$valid
        findings = @($findings.ToArray())
        body_language_audit = $bodyLanguageAudit
        backup_dir = [string]$Plan.backup_dir
        result = $resultJson
    }
}

# Get-LanguageMigrationRuntimeContext: resolves ProjectDir and TemplateRoot for the mode handlers.
function Get-LanguageMigrationRuntimeContext {
    param(
        [string]$ProjectDirValue,
        [string]$TemplateRootValue
    )

    $projectDirFull = [System.IO.Path]::GetFullPath($ProjectDirValue)
    if (-not (Test-Path -LiteralPath $projectDirFull)) {
        throw "Project directory does not exist: $projectDirFull"
    }

    if ([string]::IsNullOrWhiteSpace($TemplateRootValue)) {
        $skillRoot = Split-Path -Parent $PSScriptRoot
        $TemplateRootValue = Join-PathParts $skillRoot "assets" "knowledge-hub-template" "templates" "languages"
    }
    $templateRootFull = [System.IO.Path]::GetFullPath($TemplateRootValue)
    if (-not (Test-Path -LiteralPath $templateRootFull)) {
        throw "Project language template root does not exist: $templateRootFull"
    }

    return [ordered]@{
        project_dir = $projectDirFull
        template_root = $templateRootFull
    }
}

# Invoke-LanguageMigrationAnalyze: runs Analyze mode and returns the existing JSON/human payload shape.
function Invoke-LanguageMigrationAnalyze {
    param(
        [string]$ProjectDirFull,
        [string]$TemplateRootFull,
        [string]$SourceLanguageValue,
        [string]$TargetLanguageValue
    )

    $sourceCode = Resolve-SupportedLanguage -Language $SourceLanguageValue -ParamName "SourceLanguage"
    $targetCode = Resolve-SupportedLanguage -Language $TargetLanguageValue -ParamName "TargetLanguage"
    if ($sourceCode -eq $targetCode) {
        throw "SourceLanguage and TargetLanguage must differ for language migration."
    }

    $analysis = Get-MigrationAnalysis -Root $ProjectDirFull -TemplateRootFull $TemplateRootFull -SourceCode $sourceCode -TargetCode $targetCode
    return [ordered]@{
        project = $ProjectDirFull
        mode = "Analyze"
        source_language = $sourceCode
        target_language = $targetCode
        summary = $analysis.summary
        actions = @($analysis.actions)
    }
}

# Invoke-LanguageMigrationPlan: runs Plan mode and returns the existing proposal payload shape.
function Invoke-LanguageMigrationPlan {
    param(
        [string]$ProjectDirFull,
        [string]$TemplateRootFull,
        [string]$SourceLanguageValue,
        [string]$TargetLanguageValue
    )

    $sourceCode = Resolve-SupportedLanguage -Language $SourceLanguageValue -ParamName "SourceLanguage"
    $targetCode = Resolve-SupportedLanguage -Language $TargetLanguageValue -ParamName "TargetLanguage"
    if ($sourceCode -eq $targetCode) {
        throw "SourceLanguage and TargetLanguage must differ for language migration."
    }

    $analysis = Get-MigrationAnalysis -Root $ProjectDirFull -TemplateRootFull $TemplateRootFull -SourceCode $sourceCode -TargetCode $targetCode
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $backup = New-MigrationBackup -Root $ProjectDirFull -Actions @($analysis.actions) -Stamp $stamp
    $proposal = Write-MigrationProposal -Root $ProjectDirFull -Analysis $analysis -Backup $backup
    return [ordered]@{
        project = $ProjectDirFull
        mode = "Plan"
        source_language = $sourceCode
        target_language = $targetCode
        summary = $analysis.summary
        proposal = [string]$proposal.proposal
        proposal_markdown = [string]$proposal.proposal_markdown
        backup_dir = [string]$proposal.backup_dir
        actions = @($analysis.actions)
    }
}

# Invoke-LanguageMigrationApply: runs Apply mode and returns the existing apply_result payload shape.
function Invoke-LanguageMigrationApply {
    param(
        [string]$ProjectDirFull,
        [string]$MigrationPlanValue
    )

    $plan = Read-MigrationPlan -PlanPath $MigrationPlanValue
    Assert-PlanProjectMatchesCurrentProject -Plan $plan -CurrentProjectDir $ProjectDirFull
    $applyResult = Apply-MigrationPlan -Plan $plan
    return [ordered]@{
        project = [string]$plan.project
        mode = "Apply"
        source_language = [string]$plan.source_language
        target_language = [string]$plan.target_language
        apply_result = $applyResult
    }
}

# Invoke-LanguageMigrationValidate: runs Validate mode and preserves failure output behavior.
function Invoke-LanguageMigrationValidate {
    param(
        [string]$ProjectDirFull,
        [string]$MigrationPlanValue,
        [switch]$JsonOutput
    )

    $plan = Read-MigrationPlan -PlanPath $MigrationPlanValue
    Assert-PlanProjectMatchesCurrentProject -Plan $plan -CurrentProjectDir $ProjectDirFull
    $validation = Validate-MigrationPlan -Plan $plan
    $payload = [ordered]@{
        project = [string]$plan.project
        mode = "Validate"
        source_language = [string]$plan.source_language
        target_language = [string]$plan.target_language
        validation = $validation
    }
    if (-not [bool]$validation.valid) {
        if ($JsonOutput.IsPresent) {
            $payload | ConvertTo-Json -Depth 10
        }
        throw "Language migration validation failed."
    }
    return $payload
}

# Invoke-LanguageMigrationPlanNarrative: runs PlanNarrative mode and returns the existing narrative proposal payload shape.
function Invoke-LanguageMigrationPlanNarrative {
    param(
        [string]$ProjectDirFull,
        [string]$MigrationPlanValue
    )

    $basePlan = Read-MigrationPlan -PlanPath $MigrationPlanValue
    Assert-PlanProjectMatchesCurrentProject -Plan $basePlan -CurrentProjectDir $ProjectDirFull
    $proposal = Write-NarrativeProposal -Root $ProjectDirFull -BasePlan $basePlan
    return [ordered]@{
        project = $ProjectDirFull
        mode = "PlanNarrative"
        source_language = [string]$basePlan.source_language
        target_language = [string]$basePlan.target_language
        summary = $proposal.summary
        proposal = [string]$proposal.proposal
        proposal_markdown = [string]$proposal.proposal_markdown
        backup_dir = [string]$proposal.backup_dir
        actions = @($proposal.actions)
    }
}

# Invoke-LanguageMigrationApplyNarrative: runs ApplyNarrative mode and returns the existing apply_result payload shape.
function Invoke-LanguageMigrationApplyNarrative {
    param(
        [string]$ProjectDirFull,
        [string]$MigrationPlanValue
    )

    $plan = Read-NarrativePlan -PlanPath $MigrationPlanValue
    Assert-PlanProjectMatchesCurrentProject -Plan $plan -CurrentProjectDir $ProjectDirFull
    $applyResult = Apply-NarrativeMigrationPlan -Plan $plan
    return [ordered]@{
        project = [string]$plan.project
        mode = "ApplyNarrative"
        source_language = [string]$plan.source_language
        target_language = [string]$plan.target_language
        apply_result = $applyResult
    }
}

# Invoke-LanguageMigrationValidateNarrative: runs ValidateNarrative mode and preserves failure output behavior.
function Invoke-LanguageMigrationValidateNarrative {
    param(
        [string]$ProjectDirFull,
        [string]$MigrationPlanValue,
        [switch]$JsonOutput
    )

    $plan = Read-NarrativePlan -PlanPath $MigrationPlanValue
    Assert-PlanProjectMatchesCurrentProject -Plan $plan -CurrentProjectDir $ProjectDirFull
    $validation = Validate-NarrativeMigrationPlan -Plan $plan
    $payload = [ordered]@{
        project = [string]$plan.project
        mode = "ValidateNarrative"
        source_language = [string]$plan.source_language
        target_language = [string]$plan.target_language
        validation = $validation
    }
    if (-not [bool]$validation.valid) {
        if ($JsonOutput.IsPresent) {
            $payload | ConvertTo-Json -Depth 10
        }
        throw "Language migration narrative validation failed."
    }
    return $payload
}

# Write-LanguageMigrationHumanSummary: writes the existing human summary lines for any mode payload.
function Write-LanguageMigrationHumanSummary {
    param($Payload)

    Write-Output ("Language migration {0}: {1}" -f [string]$Payload.mode.ToLowerInvariant(), [string]$Payload.project)
    Write-Output ("Source language: {0}" -f [string]$Payload.source_language)
    Write-Output ("Target language: {0}" -f [string]$Payload.target_language)
    if ($Payload.PSObject.Properties.Name -contains "summary") {
        Write-Output ("Files analyzed: {0}" -f [int]$Payload.summary.total)
        Write-Output ("Files to write: {0}" -f [int]$Payload.summary.writes)
        Write-Output ("Manual-review files: {0}" -f [int]$Payload.summary.manual_review)
    }
    if ($Payload.PSObject.Properties.Name -contains "proposal") {
        Write-Output ("Proposal: {0}" -f [string]$Payload.proposal)
        Write-Output ("Proposal markdown: {0}" -f [string]$Payload.proposal_markdown)
        Write-Output ("Backup: {0}" -f [string]$Payload.backup_dir)
    }
    if ($Payload.PSObject.Properties.Name -contains "apply_result") {
        Write-Output ("Result: {0}" -f [string]$Payload.apply_result.result)
        Write-Output ("Backup: {0}" -f [string]$Payload.apply_result.backup_dir)
        Write-Output ("Files written: {0}" -f [int]$Payload.apply_result.files_written)
        Write-Output ("Manual-review files: {0}" -f [int]$Payload.apply_result.manual_review_count)
    }
    if ($Payload.PSObject.Properties.Name -contains "validation") {
        Write-Output ("Valid: {0}" -f [bool]$Payload.validation.valid)
        if ($Payload.validation.PSObject.Properties.Name -contains "completion_ready") {
            Write-Output ("Completion ready: {0}" -f [bool]$Payload.validation.completion_ready)
        }
        if ($Payload.validation.PSObject.Properties.Name -contains "body_language_audit") {
            Write-Output ("Body language audit findings: {0}" -f [int]$Payload.validation.body_language_audit.summary.finding_count)
        }
        foreach ($finding in @($Payload.validation.findings)) {
            Write-Output ("[{0}] {1}: {2}" -f [string]$finding.severity, [string]$finding.code, [string]$finding.message)
            Write-Output ("  Path: {0}" -f [string]$finding.path)
        }
    }
}

$runtimeContext = Get-LanguageMigrationRuntimeContext -ProjectDirValue $ProjectDir -TemplateRootValue $TemplateRoot
$ProjectDirFull = [string]$runtimeContext.project_dir
$TemplateRootFull = [string]$runtimeContext.template_root

switch ($Mode) {
    "Analyze" {
        $payload = Invoke-LanguageMigrationAnalyze -ProjectDirFull $ProjectDirFull -TemplateRootFull $TemplateRootFull -SourceLanguageValue $SourceLanguage -TargetLanguageValue $TargetLanguage
    }
    "Plan" {
        $payload = Invoke-LanguageMigrationPlan -ProjectDirFull $ProjectDirFull -TemplateRootFull $TemplateRootFull -SourceLanguageValue $SourceLanguage -TargetLanguageValue $TargetLanguage
    }
    "Apply" {
        $payload = Invoke-LanguageMigrationApply -ProjectDirFull $ProjectDirFull -MigrationPlanValue $MigrationPlan
    }
    "Validate" {
        $payload = Invoke-LanguageMigrationValidate -ProjectDirFull $ProjectDirFull -MigrationPlanValue $MigrationPlan -JsonOutput:$Json.IsPresent
    }
    "PlanNarrative" {
        $payload = Invoke-LanguageMigrationPlanNarrative -ProjectDirFull $ProjectDirFull -MigrationPlanValue $MigrationPlan
    }
    "ApplyNarrative" {
        $payload = Invoke-LanguageMigrationApplyNarrative -ProjectDirFull $ProjectDirFull -MigrationPlanValue $MigrationPlan
    }
    "ValidateNarrative" {
        $payload = Invoke-LanguageMigrationValidateNarrative -ProjectDirFull $ProjectDirFull -MigrationPlanValue $MigrationPlan -JsonOutput:$Json.IsPresent
    }
}

if ($Json.IsPresent) {
    $payload | ConvertTo-Json -Depth 10
    return
}

Write-LanguageMigrationHumanSummary -Payload $payload
