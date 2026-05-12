param(
    [string]$ProjectDir = (Get-Location).Path,
    [ValidateSet("Analyze", "Plan", "Apply")]
    [string]$Mode = "Analyze",
    [string]$UpgradePlan = "",
    [switch]$Json,
    [int]$LargeFileLineThreshold = 160
)

$ErrorActionPreference = "Stop"

function Resolve-Project {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Project directory does not exist: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-FileTextInfo {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $lines = @(Get-Content -LiteralPath $Path)
    return [ordered]@{
        path = (Resolve-Path -LiteralPath $Path).Path
        line_count = $lines.Count
        text = ($lines -join "`n")
    }
}

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [string]$Severity,
        [string]$Code,
        [string]$Path,
        [string]$Message,
        [string]$Action
    )
    $Findings.Add([ordered]@{
        severity = $Severity
        code = $Code
        path = $Path
        message = $Message
        action = $Action
    })
}

function Test-DiscoveryHeading {
    param(
        [string[]]$Lines,
        [string[]]$Aliases
    )

    foreach ($alias in $Aliases) {
        $pattern = '^\s*##\s+{0}\s*$' -f [regex]::Escape($alias)
        if ($Lines -match $pattern) {
            return $true
        }
    }
    return $false
}

$localizedSummaryHeading = -join @([char]0x6458, [char]0x8981)
$localizedKeywordsHeading = -join @([char]0x5173, [char]0x952E, [char]0x8BCD)
$discoveryHeadingAliases = [ordered]@{
    summary = @("Summary", $localizedSummaryHeading)
    keywords = @("Keywords", $localizedKeywordsHeading)
}

function Join-CodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$zhText = [ordered]@{
    Chinese = Join-CodePoints @(0x4E2D, 0x6587)
    SimplifiedChinese = Join-CodePoints @(0x7B80, 0x4F53, 0x4E2D, 0x6587)
    CurrentState = Join-CodePoints @(0x5F53, 0x524D, 0x72B6, 0x6001)
    LegacyMemoryUpgradedPrefix = Join-CodePoints @(0x65E7, 0x7248, 0x5DE5, 0x7A0B, 0x8BB0, 0x5FC6, 0x5E03, 0x5C40, 0x5DF2, 0x4E8E)
    UpgradedPeriod = Join-CodePoints @(0x5347, 0x7EA7, 0x3002)
    CurrentSpecPrefix = Join-CodePoints @(0x5F53, 0x524D, 0x0020, 0x0053, 0x0070, 0x0065, 0x0063, 0x003A, 0x0020)
    None = Join-CodePoints @(0x65E0)
    NextActions = Join-CodePoints @(0x4E0B, 0x4E00, 0x6B65)
    ContinueFromPlan = Join-CodePoints @(0x7EE7, 0x7EED, 0x67E5, 0x770B, 0x0020, 0x002E, 0x0061, 0x0067, 0x0065, 0x006E, 0x0074, 0x0073, 0x002F, 0x0070, 0x006C, 0x0061, 0x006E, 0x002E, 0x006D, 0x0064, 0x0020, 0x548C, 0x5F53, 0x524D, 0x0020, 0x0064, 0x006F, 0x0063, 0x0073, 0x002F, 0x0073, 0x0070, 0x0065, 0x0063, 0x0073, 0x0020, 0x4EFB, 0x52A1, 0x3002)
    BlockingIssues = Join-CodePoints @(0x963B, 0x585E, 0x4E8B, 0x9879)
    NoRecordedBlockers = Join-CodePoints @(0x65E0, 0x5DF2, 0x8BB0, 0x5F55, 0x963B, 0x585E)
    LastUpdated = Join-CodePoints @(0x6700, 0x540E, 0x66F4, 0x65B0)
    ActivePlanHeading = Join-CodePoints @(0x0023, 0x0020, 0x5F53, 0x524D, 0x8BA1, 0x5212)
    ActiveSpecHeading = Join-CodePoints @(0x5F53, 0x524D, 0x0020, 0x0053, 0x0070, 0x0065, 0x0063)
    CurrentTask = Join-CodePoints @(0x5F53, 0x524D, 0x4EFB, 0x52A1)
    ThisSession = Join-CodePoints @(0x672C, 0x6B21, 0x4F1A, 0x8BDD)
    ReviewBackupPrefix = Join-CodePoints @(0x67E5, 0x770B, 0x0020, 0x002E, 0x0061, 0x0067, 0x0065, 0x006E, 0x0074, 0x0073, 0x002F, 0x005F, 0x0062, 0x0061, 0x0063, 0x006B, 0x0075, 0x0070, 0x002F)
    ReviewBackupSuffix = Join-CodePoints @(0x0020, 0x4E2D, 0x7684, 0x8BB0, 0x5FC6, 0x5347, 0x7EA7, 0x5907, 0x4EFD)
    MoveDurableWork = Join-CodePoints @(0x5C06, 0x4ECD, 0x9700, 0x957F, 0x671F, 0x4FDD, 0x7559, 0x7684, 0x5DE5, 0x4F5C, 0x79FB, 0x5165, 0x0020, 0x0064, 0x006F, 0x0063, 0x0073, 0x002F, 0x0073, 0x0070, 0x0065, 0x0063, 0x0073, 0x002F)
    ConfirmedNotesHeading = Join-CodePoints @(0x0023, 0x0020, 0x5DF2, 0x786E, 0x8BA4, 0x8BB0, 0x5F55)
    MemoryUpgradedPrefix = Join-CodePoints @(0x5DE5, 0x7A0B, 0x8BB0, 0x5FC6, 0x5DF2, 0x4E8E)
    MemoryUpgradedBackupPrefix = Join-CodePoints @(0x5347, 0x7EA7, 0xFF1B, 0x539F, 0x59CB, 0x6587, 0x4EF6, 0x5DF2, 0x5907, 0x4EFD, 0x5230, 0x0020, 0x002E, 0x0061, 0x0067, 0x0065, 0x006E, 0x0074, 0x0073, 0x002F, 0x005F, 0x0062, 0x0061, 0x0063, 0x006B, 0x0075, 0x0070, 0x002F)
    Period = Join-CodePoints @(0x3002)
    StableFactsOnly = Join-CodePoints @(0x672C, 0x6587, 0x4EF6, 0x53EA, 0x4FDD, 0x7559, 0x6709, 0x8BC1, 0x636E, 0x7684, 0x7A33, 0x5B9A, 0x4E8B, 0x5B9E, 0x3002)
}

function Resolve-MemoryLanguage {
    param([string]$Root)

    $agentDir = Join-Path $Root ".agents"
    $lockPath = Join-Path $agentDir "hub.lock.json"
    $requested = ""
    $warning = ""

    if (Test-Path -LiteralPath $lockPath) {
        try {
            $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
            if ($lock.PSObject.Properties.Name -contains "project_language") {
                $requested = ([string]$lock.project_language).Trim()
            }
        } catch {
            $warning = "Could not read project_language from .agents/hub.lock.json; falling back to English."
        }
    }

    if ([string]::IsNullOrWhiteSpace($requested)) {
        return [ordered]@{
            requested = $requested
            code = "en"
            label = "English"
            warning = $warning
        }
    }

    $normalized = $requested.ToLowerInvariant()
    if ($normalized -in @("en", "en-us", "english")) {
        return [ordered]@{
            requested = $requested
            code = "en"
            label = "English"
            warning = $warning
        }
    }
    if ($normalized -in @("zh", "zh-cn", "zh-hans", "chinese", "simplified-chinese", "simplified chinese", $zhText.Chinese, $zhText.SimplifiedChinese)) {
        return [ordered]@{
            requested = $requested
            code = "zh-CN"
            label = "Simplified Chinese"
            warning = $warning
        }
    }

    return [ordered]@{
        requested = $requested
        code = "en"
        label = "English"
        warning = ("Unsupported project_language '{0}'; falling back to English." -f $requested)
    }
}

function New-ProcessLines {
    param(
        [string]$LanguageCode,
        [string]$Today,
        [string]$SpecRef
    )

    $lines = @()
    if ($LanguageCode -eq "zh-CN") {
        $lines += $zhText.CurrentState
        $lines += ("- {0} {1} {2}" -f $zhText.LegacyMemoryUpgradedPrefix, $Today, $zhText.UpgradedPeriod)
        if ($SpecRef) { $lines += ("- {0}{1}" -f $zhText.CurrentSpecPrefix, $SpecRef) } else { $lines += ("- {0}{1}" -f $zhText.CurrentSpecPrefix, $zhText.None) }
        $lines += ""
        $lines += $zhText.NextActions
        $lines += ("- {0}" -f $zhText.ContinueFromPlan)
        $lines += ""
        $lines += $zhText.BlockingIssues
        $lines += ("- {0}" -f $zhText.NoRecordedBlockers)
        $lines += ""
        $lines += $zhText.LastUpdated
        $lines += "- $Today"
        return $lines
    }

    $lines += "Current State"
    $lines += "- Memory upgraded from legacy layout on $Today."
    if ($SpecRef) { $lines += "- Active spec: $SpecRef" } else { $lines += "- Active spec: none" }
    $lines += ""
    $lines += "Next Actions"
    $lines += "- Continue from .agents/plan.md and active docs/specs tasks."
    $lines += ""
    $lines += "Blocking Issues"
    $lines += "- none recorded"
    $lines += ""
    $lines += "Last Updated"
    $lines += "- $Today"
    return $lines
}

function New-PlanLines {
    param(
        [string]$LanguageCode,
        [string]$SpecRef,
        [string]$Stamp
    )

    $lines = @()
    if ($LanguageCode -eq "zh-CN") {
        $lines += $zhText.ActivePlanHeading
        $lines += ""
        $lines += $zhText.ActiveSpecHeading
        if ($SpecRef) { $lines += "- $SpecRef" } else { $lines += ("- {0}" -f $zhText.None) }
        $lines += ""
        $lines += $zhText.CurrentTask
        $lines += ("- {0}" -f $zhText.None)
        $lines += ""
        $lines += $zhText.ThisSession
        $lines += ("- [ ] {0}{1}/{2}" -f $zhText.ReviewBackupPrefix, $Stamp, $zhText.ReviewBackupSuffix)
        $lines += ("- [ ] {0}" -f $zhText.MoveDurableWork)
        return $lines
    }

    $lines += "# Active Plan"
    $lines += ""
    $lines += "Active Spec"
    if ($SpecRef) { $lines += "- $SpecRef" } else { $lines += "- none" }
    $lines += ""
    $lines += "Current Task"
    $lines += "- none"
    $lines += ""
    $lines += "This Session"
    $lines += "- [ ] Review memory upgrade backup at .agents/_backup/$Stamp/"
    $lines += "- [ ] Move any remaining durable work into docs/specs/"
    return $lines
}

function New-NotesLines {
    param(
        [string]$LanguageCode,
        [string]$Today,
        [string]$Stamp
    )

    if ($LanguageCode -eq "zh-CN") {
        return @(
            $zhText.ConfirmedNotesHeading,
            "",
            ("- {0} {1} {2}{3}/{4}" -f $zhText.MemoryUpgradedPrefix, $Today, $zhText.MemoryUpgradedBackupPrefix, $Stamp, $zhText.Period),
            ("- {0}" -f $zhText.StableFactsOnly)
        )
    }

    return @(
        "# Confirmed Notes",
        "",
        "- Memory upgraded on $Today; original files backed up at .agents/_backup/$Stamp/.",
        "- Keep this file limited to stable verified facts with evidence."
    )
}

function Get-Analysis {
    param([string]$Root)

    $findings = New-Object 'System.Collections.Generic.List[object]'
    $agentDir = Join-Path $Root ".agents"
    $specTemplateDir = Join-Path $Root "docs\specs\_templates"
    $lockPath = Join-Path $agentDir "hub.lock.json"

    if (-not (Test-Path -LiteralPath $agentDir)) {
        Add-Finding $findings "warning" "missing_agents_dir" $agentDir "Project has no .agents directory." "Run bootstrap before memory upgrade."
        return $findings
    }

    foreach ($required in @(
        (Join-Path $Root "AGENTS.md"),
        (Join-Path $agentDir "AGENTS.md"),
        (Join-Path $agentDir "process.txt"),
        (Join-Path $agentDir "plan.md"),
        (Join-Path $agentDir "notes.md"),
        $specTemplateDir,
        $lockPath
    )) {
        if (-not (Test-Path -LiteralPath $required)) {
            Add-Finding $findings "warning" "missing_scaffold" $required "Expected scaffold path is missing." "Refresh project-bootstrap templates."
        }
    }

    $memoryFiles = @(
        (Join-Path $agentDir "process.txt"),
        (Join-Path $agentDir "plan.md"),
        (Join-Path $agentDir "notes.md")
    )

    foreach ($file in $memoryFiles) {
        $info = Get-FileTextInfo -Path $file
        if ($null -eq $info) { continue }

        if ($info.line_count -gt $LargeFileLineThreshold) {
            Add-Finding $findings "warning" "oversized_memory" $info.path ("Memory file has {0} lines." -f $info.line_count) "Compress to hot-memory role and move durable material into docs/specs or context."
        }
        if ($info.text -match '(?i)(timeline|history|previous session|session \d+|chronology)') {
            Add-Finding $findings "warning" "timeline_accumulation" $info.path "Memory file appears to contain historical session timeline." "Archive history and keep only current status or stable facts."
        }
    }

    $planInfo = Get-FileTextInfo -Path (Join-Path $agentDir "plan.md")
    if ($null -ne $planInfo) {
        $checkboxCount = ([regex]::Matches($planInfo.text, '-\s+\[[ xX]\]')).Count
        if ($planInfo.text -match '(?m)^##\s+Tasks\s*$' -or $planInfo.text -match 'T\d{2}:' -or $checkboxCount -gt 5) {
            Add-Finding $findings "warning" "durable_tasks_in_plan" $planInfo.path "plan.md appears to contain durable task content." "Move long-lived task checklist to docs/specs/<slug>/tasks.md and leave plan.md as a pointer."
        }
    }

    $notesInfo = Get-FileTextInfo -Path (Join-Path $agentDir "notes.md")
    if ($null -ne $notesInfo -and $notesInfo.text -match '(?i)(todo|next step|\[ \]|\[x\]|I tried|today|yesterday)') {
        Add-Finding $findings "warning" "notes_contains_session_state" $notesInfo.path "notes.md appears to contain task or session-state language." "Keep notes.md to verified stable facts; move current state to process/plan."
    }

    $contextDir = Join-Path $agentDir "context"
    if (Test-Path -LiteralPath $contextDir) {
        $contextFiles = @(Get-ChildItem -LiteralPath $contextDir -Recurse -File -Filter "*.md" | Where-Object { $_.Name -notin @("README.md", "case_template.md") })
        foreach ($file in $contextFiles) {
            $preview = Get-Content -LiteralPath $file.FullName -TotalCount 30
            $hasSummary = Test-DiscoveryHeading -Lines $preview -Aliases $discoveryHeadingAliases.summary
            $hasKeywords = Test-DiscoveryHeading -Lines $preview -Aliases $discoveryHeadingAliases.keywords
            if (-not $hasSummary -or -not $hasKeywords) {
                Add-Finding $findings "info" "context_metadata_missing" $file.FullName "Context file lacks discovery metadata." "Add concise Summary/Keywords discovery metadata near the top."
            }
        }
    }

    return $findings
}

function New-Proposal {
    param(
        [string]$Root,
        [array]$Findings
    )

    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $upgradeDir = Join-Path $Root ".agents\upgrade\$stamp"
    Ensure-Dir $upgradeDir
    $proposalPath = Join-Path $upgradeDir "proposal.md"

    $lines = @()
    $lines += "# Memory Upgrade Proposal"
    $lines += ""
    $lines += "- Project: $Root"
    $lines += "- Created UTC: $((Get-Date).ToUniversalTime().ToString("o"))"
    $lines += "- Mode: review before apply"
    $lines += ""
    $lines += "## Findings"
    if ($Findings.Count -eq 0) {
        $lines += "- No legacy memory issues detected."
    } else {
        foreach ($finding in $Findings) {
            $lines += "- [$($finding.severity)] $($finding.code): $($finding.message)"
            $lines += "  - Path: $($finding.path)"
            $lines += "  - Proposed action: $($finding.action)"
        }
    }
    $lines += ""
    $lines += "## Apply Plan"
    $lines += "Keep an action checked to apply it. Change `[x]` to `[ ]` to skip that action."
    $lines += ""
    $lines += "## Approved Actions"
    $lines += "- [x] normalize_process: rewrite `.agents/process.txt` to current state, blockers, next actions, and last updated."
    $lines += "- [x] normalize_plan: rewrite `.agents/plan.md` to active spec/current task/session-local steps only."
    $lines += "- [x] normalize_notes: rewrite `.agents/notes.md` to stable verified facts only."
    $lines += ""
    $lines += "## Notes For Follow-Up"
    $lines += "- Back up current `.agents` memory files into `.agents/_backup/<timestamp>/`."
    $lines += "- Move durable multi-stage work into `docs/specs/<slug>/` manually or in a follow-up targeted migration."
    $lines += "- Add summary/keyword metadata to context entries before relying on progressive disclosure."
    $lines += ""
    $lines += "## Review Notes"
    $lines += "- Edit the Approved Actions checklist before applying if any hot memory rewrite should be skipped."

    Set-Content -LiteralPath $proposalPath -Value $lines -Encoding UTF8
    return $proposalPath
}

function Get-ApprovedActions {
    param([string]$PlanPath)

    $text = Get-Content -LiteralPath $PlanPath -Raw
    $actions = [ordered]@{
        normalize_process = $false
        normalize_plan = $false
        normalize_notes = $false
    }

    $matches = [regex]::Matches($text, '(?m)^-\s+\[[xX]\]\s+(normalize_process|normalize_plan|normalize_notes)\b')
    foreach ($match in $matches) {
        $actions[$match.Groups[1].Value] = $true
    }

    return $actions
}

function Apply-Upgrade {
    param(
        [string]$Root,
        [string]$PlanPath
    )

    if ([string]::IsNullOrWhiteSpace($PlanPath) -or -not (Test-Path -LiteralPath $PlanPath)) {
        throw "Apply mode requires -UpgradePlan pointing to a reviewed proposal file."
    }
    $resolvedPlanPath = (Resolve-Path -LiteralPath $PlanPath).Path
    $approvedActions = Get-ApprovedActions -PlanPath $resolvedPlanPath

    $agentDir = Join-Path $Root ".agents"
    if (-not (Test-Path -LiteralPath $agentDir)) {
        throw "Cannot apply memory upgrade without .agents directory: $agentDir"
    }

    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $backupDir = Join-Path $agentDir "_backup\$stamp"
    Ensure-Dir $backupDir

    foreach ($relative in @("process.txt", "plan.md", "notes.md", "context")) {
        $source = Join-Path $agentDir $relative
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $backupDir $relative) -Recurse -Force
        }
    }

    $processPath = Join-Path $agentDir "process.txt"
    $planPath = Join-Path $agentDir "plan.md"
    $notesPath = Join-Path $agentDir "notes.md"
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $memoryLanguage = Resolve-MemoryLanguage -Root $Root

    if ($approvedActions.normalize_process -and (Test-Path -LiteralPath $processPath)) {
        $old = Get-Content -LiteralPath $processPath -Raw
        $specRef = ([regex]::Match($old, 'docs/specs/[A-Za-z0-9._-]+/spec\.md')).Value
        $lines = New-ProcessLines -LanguageCode $memoryLanguage.code -Today $today -SpecRef $specRef
        Set-Content -LiteralPath $processPath -Value $lines -Encoding UTF8
    }

    if ($approvedActions.normalize_plan -and (Test-Path -LiteralPath $planPath)) {
        $old = Get-Content -LiteralPath $planPath -Raw
        $specRef = ([regex]::Match($old, 'docs/specs/[A-Za-z0-9._-]+/spec\.md')).Value
        $lines = New-PlanLines -LanguageCode $memoryLanguage.code -SpecRef $specRef -Stamp $stamp
        Set-Content -LiteralPath $planPath -Value $lines -Encoding UTF8
    }

    if ($approvedActions.normalize_notes -and (Test-Path -LiteralPath $notesPath)) {
        $lines = New-NotesLines -LanguageCode $memoryLanguage.code -Today $today -Stamp $stamp
        Set-Content -LiteralPath $notesPath -Value $lines -Encoding UTF8
    }

    $resultPath = Join-Path (Split-Path -Parent $resolvedPlanPath) "result.md"
    $result = @(
        "# Memory Upgrade Result",
        "",
        "- Applied UTC: $((Get-Date).ToUniversalTime().ToString("o"))",
        "- Backup: .agents/_backup/$stamp/",
        "- Proposal: $resolvedPlanPath",
        "- Project language: $($memoryLanguage.code)",
        "- Applied actions: $((@($approvedActions.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key }) -join ', '))",
        "",
        "Approved hot memory actions were applied. Review backup before deleting or further condensing old material."
    )
    if (-not [string]::IsNullOrWhiteSpace($memoryLanguage.warning)) {
        $result += ""
        $result += ("Language warning: {0}" -f $memoryLanguage.warning)
    }
    Set-Content -LiteralPath $resultPath -Value $result -Encoding UTF8

    return [ordered]@{
        backup_dir = $backupDir
        result = $resultPath
        approved_actions = $approvedActions
        project_language = $memoryLanguage.code
        requested_project_language = $memoryLanguage.requested
        language_warning = $memoryLanguage.warning
    }
}

$projectFull = Resolve-Project $ProjectDir
$findings = @(Get-Analysis -Root $projectFull)
$findingList = @($findings)
$proposal = ""
$applyResult = $null

if ($Mode -eq "Plan") {
    $proposal = New-Proposal -Root $projectFull -Findings $findingList
} elseif ($Mode -eq "Apply") {
    $applyResult = Apply-Upgrade -Root $projectFull -PlanPath $UpgradePlan
}

$payload = [ordered]@{
    project = $projectFull
    mode = $Mode
    findings = $findingList
    proposal = $proposal
    apply_result = $applyResult
}

if ($Json.IsPresent) {
    $payload | ConvertTo-Json -Depth 8
    return
}

Write-Output ("Memory upgrade {0}: {1}" -f $Mode.ToLowerInvariant(), $projectFull)
Write-Output ("Findings: {0}" -f $findingList.Count)
foreach ($finding in $findingList) {
    Write-Output ("[{0}] {1}: {2}" -f $finding.severity, $finding.code, $finding.message)
    Write-Output ("  Path: {0}" -f $finding.path)
    Write-Output ("  Action: {0}" -f $finding.action)
}
if ($proposal) {
    Write-Output ("Proposal: {0}" -f $proposal)
}
if ($null -ne $applyResult) {
    Write-Output ("Project language: {0}" -f $applyResult.project_language)
    if (-not [string]::IsNullOrWhiteSpace($applyResult.language_warning)) {
        Write-Output ("Warning: {0}" -f $applyResult.language_warning)
    }
    Write-Output ("Backup: {0}" -f $applyResult.backup_dir)
    Write-Output ("Result: {0}" -f $applyResult.result)
}
