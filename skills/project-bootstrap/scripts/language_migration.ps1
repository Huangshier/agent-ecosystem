param(
    [string]$ProjectDir = (Get-Location).Path,
    [ValidateSet("Analyze", "Plan", "Apply", "Validate")]
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
        throw "Missing project-memory template language root: $languageRoot"
    }

    $map = @{}
    foreach ($section in @("project-root", "project-agent")) {
        $sectionRoot = Join-PathParts $languageRoot $section
        if (-not (Test-Path -LiteralPath $sectionRoot)) {
            throw "Missing project-memory template section: $sectionRoot"
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
    $lines += ("<!-- source_language: {0}; target_language: {1} -->" -f $SourceLanguageCode, $TargetLanguageCode)
    $lines += $SourceText.TrimEnd()
    $lines += "<!-- language-migration:manual-review-source end -->"
    return ($lines -join "`r`n") + "`r`n"
}

function Read-MigrationPlan {
    param([string]$PlanPath)

    if ([string]::IsNullOrWhiteSpace($PlanPath) -or -not (Test-Path -LiteralPath $PlanPath)) {
        throw "Migration plan is required and must point to proposal.json."
    }

    $plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
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

    foreach ($action in @($Plan.actions)) {
        $relative = [string]$action.relative_path
        $actionName = [string]$action.action
        $approved = [bool]$action.approved
        $path = Join-PathParts $root $relative

        if ([bool]$action.manual_review) {
            $manualReview++
        }

        if (-not $approved) {
            $appliedActions.Add([ordered]@{
                relative_path = $relative
                action = $actionName
                result = "skipped-unapproved"
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
            $targetText = Read-Utf8Text -Path $targetTemplatePath
            $merged = Add-ManualReviewSection -TargetTemplateText $targetText -SourceText $sourceText -SourceLanguageCode ([string]$Plan.source_language) -TargetLanguageCode ([string]$Plan.target_language)
            Ensure-Dir -Path (Split-Path -Parent $path)
            Write-Utf8TextWithBom -Path $path -Content $merged
            $written++
            $appliedActions.Add([ordered]@{
                relative_path = $relative
                action = $actionName
                result = "written-target-template-with-manual-review-source"
            }) | Out-Null
            continue
        }

        $appliedActions.Add([ordered]@{
            relative_path = $relative
            action = $actionName
            result = "preserved"
        }) | Out-Null
    }

    $proposalDir = Split-Path -Parent ([string]$MigrationPlan)
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

    if ([string]::IsNullOrWhiteSpace($backupDir) -or -not (Test-Path -LiteralPath $backupDir)) {
        $valid = $false
        $findings.Add([ordered]@{ severity = "error"; code = "missing_backup"; message = "Recorded backup directory is missing."; path = $backupDir }) | Out-Null
    }
    if (-not (Test-Path -LiteralPath $resultJson)) {
        $valid = $false
        $findings.Add([ordered]@{ severity = "error"; code = "missing_result"; message = "Migration result.json is missing."; path = $resultJson }) | Out-Null
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
    }

    foreach ($action in @($Plan.actions | Where-Object { [string]$_.action -eq "merge-with-manual-review" -and [bool]$_.approved })) {
        $path = Join-PathParts $root ([string]$action.relative_path)
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
    }

    return [ordered]@{
        valid = [bool]$valid
        findings = @($findings.ToArray())
        backup_dir = $backupDir
        result = $resultJson
    }
}

$ProjectDirFull = [System.IO.Path]::GetFullPath($ProjectDir)
if (-not (Test-Path -LiteralPath $ProjectDirFull)) {
    throw "Project directory does not exist: $ProjectDirFull"
}

if ([string]::IsNullOrWhiteSpace($TemplateRoot)) {
    $skillRoot = Split-Path -Parent $PSScriptRoot
    $TemplateRoot = Join-PathParts $skillRoot "templates" "project-memory"
}
$TemplateRootFull = [System.IO.Path]::GetFullPath($TemplateRoot)
if (-not (Test-Path -LiteralPath $TemplateRootFull)) {
    throw "Project memory template root does not exist: $TemplateRootFull"
}

$payload = $null

if ($Mode -eq "Apply" -or $Mode -eq "Validate") {
    $plan = Read-MigrationPlan -PlanPath $MigrationPlan
    if ($Mode -eq "Apply") {
        $applyResult = Apply-MigrationPlan -Plan $plan
        $payload = [ordered]@{
            project = [string]$plan.project
            mode = $Mode
            source_language = [string]$plan.source_language
            target_language = [string]$plan.target_language
            apply_result = $applyResult
        }
    } else {
        $validation = Validate-MigrationPlan -Plan $plan
        $payload = [ordered]@{
            project = [string]$plan.project
            mode = $Mode
            source_language = [string]$plan.source_language
            target_language = [string]$plan.target_language
            validation = $validation
        }
        if (-not [bool]$validation.valid) {
            if ($Json.IsPresent) {
                $payload | ConvertTo-Json -Depth 10
            }
            throw "Language migration validation failed."
        }
    }
} else {
    $sourceCode = Resolve-SupportedLanguage -Language $SourceLanguage -ParamName "SourceLanguage"
    $targetCode = Resolve-SupportedLanguage -Language $TargetLanguage -ParamName "TargetLanguage"
    if ($sourceCode -eq $targetCode) {
        throw "SourceLanguage and TargetLanguage must differ for language migration."
    }

    $analysis = Get-MigrationAnalysis -Root $ProjectDirFull -TemplateRootFull $TemplateRootFull -SourceCode $sourceCode -TargetCode $targetCode

    if ($Mode -eq "Plan") {
        $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
        $backup = New-MigrationBackup -Root $ProjectDirFull -Actions @($analysis.actions) -Stamp $stamp
        $proposal = Write-MigrationProposal -Root $ProjectDirFull -Analysis $analysis -Backup $backup
        $payload = [ordered]@{
            project = $ProjectDirFull
            mode = $Mode
            source_language = $sourceCode
            target_language = $targetCode
            summary = $analysis.summary
            proposal = [string]$proposal.proposal
            proposal_markdown = [string]$proposal.proposal_markdown
            backup_dir = [string]$proposal.backup_dir
            actions = @($analysis.actions)
        }
    } else {
        $payload = [ordered]@{
            project = $ProjectDirFull
            mode = $Mode
            source_language = $sourceCode
            target_language = $targetCode
            summary = $analysis.summary
            actions = @($analysis.actions)
        }
    }
}

if ($Json.IsPresent) {
    $payload | ConvertTo-Json -Depth 10
    return
}

Write-Output ("Language migration {0}: {1}" -f $Mode.ToLowerInvariant(), [string]$payload.project)
Write-Output ("Source language: {0}" -f [string]$payload.source_language)
Write-Output ("Target language: {0}" -f [string]$payload.target_language)
if ($payload.PSObject.Properties.Name -contains "summary") {
    Write-Output ("Files analyzed: {0}" -f [int]$payload.summary.total)
    Write-Output ("Files to write: {0}" -f [int]$payload.summary.writes)
    Write-Output ("Manual-review files: {0}" -f [int]$payload.summary.manual_review)
}
if ($payload.PSObject.Properties.Name -contains "proposal") {
    Write-Output ("Proposal: {0}" -f [string]$payload.proposal)
    Write-Output ("Proposal markdown: {0}" -f [string]$payload.proposal_markdown)
    Write-Output ("Backup: {0}" -f [string]$payload.backup_dir)
}
if ($payload.PSObject.Properties.Name -contains "apply_result") {
    Write-Output ("Result: {0}" -f [string]$payload.apply_result.result)
    Write-Output ("Backup: {0}" -f [string]$payload.apply_result.backup_dir)
    Write-Output ("Files written: {0}" -f [int]$payload.apply_result.files_written)
    Write-Output ("Manual-review files: {0}" -f [int]$payload.apply_result.manual_review_count)
}
if ($payload.PSObject.Properties.Name -contains "validation") {
    Write-Output ("Valid: {0}" -f [bool]$payload.validation.valid)
    foreach ($finding in @($payload.validation.findings)) {
        Write-Output ("[{0}] {1}: {2}" -f [string]$finding.severity, [string]$finding.code, [string]$finding.message)
        Write-Output ("  Path: {0}" -f [string]$finding.path)
    }
}
