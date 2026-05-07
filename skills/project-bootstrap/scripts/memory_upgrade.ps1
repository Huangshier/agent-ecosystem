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
            if (-not ($preview -match '^\s*##\s+Summary\s*$') -or -not ($preview -match '^\s*##\s+Keywords\s*$')) {
                Add-Finding $findings "info" "context_metadata_missing" $file.FullName "Context file lacks discovery metadata." "Add ## Summary and ## Keywords near the top."
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

    if ($approvedActions.normalize_process -and (Test-Path -LiteralPath $processPath)) {
        $old = Get-Content -LiteralPath $processPath -Raw
        $specRef = ([regex]::Match($old, 'docs/specs/[A-Za-z0-9._-]+/spec\.md')).Value
        $lines = @()
        $lines += "Current State"
        $lines += "- Memory upgraded from legacy layout on $today."
        if ($specRef) { $lines += "- Active spec: $specRef" } else { $lines += "- Active spec: none" }
        $lines += ""
        $lines += "Next Actions"
        $lines += "- Continue from .agents/plan.md and active docs/specs tasks."
        $lines += ""
        $lines += "Blocking Issues"
        $lines += "- none recorded"
        $lines += ""
        $lines += "Last Updated"
        $lines += "- $today"
        Set-Content -LiteralPath $processPath -Value $lines -Encoding UTF8
    }

    if ($approvedActions.normalize_plan -and (Test-Path -LiteralPath $planPath)) {
        $old = Get-Content -LiteralPath $planPath -Raw
        $specRef = ([regex]::Match($old, 'docs/specs/[A-Za-z0-9._-]+/spec\.md')).Value
        $lines = @()
        $lines += "# Active Plan"
        $lines += ""
        $lines += "Active Spec"
        if ($specRef) { $lines += "- $specRef" } else { $lines += "- none" }
        $lines += ""
        $lines += "Current Task"
        $lines += "- none"
        $lines += ""
        $lines += "This Session"
        $lines += "- [ ] Review memory upgrade backup at .agents/_backup/$stamp/"
        $lines += "- [ ] Move any remaining durable work into docs/specs/"
        Set-Content -LiteralPath $planPath -Value $lines -Encoding UTF8
    }

    if ($approvedActions.normalize_notes -and (Test-Path -LiteralPath $notesPath)) {
        $lines = @(
            "# Confirmed Notes",
            "",
            "- Memory upgraded on $today; original files backed up at .agents/_backup/$stamp/.",
            "- Keep this file limited to stable verified facts with evidence."
        )
        Set-Content -LiteralPath $notesPath -Value $lines -Encoding UTF8
    }

    $resultPath = Join-Path (Split-Path -Parent $resolvedPlanPath) "result.md"
    $result = @(
        "# Memory Upgrade Result",
        "",
        "- Applied UTC: $((Get-Date).ToUniversalTime().ToString("o"))",
        "- Backup: .agents/_backup/$stamp/",
        "- Proposal: $resolvedPlanPath",
        "- Applied actions: $((@($approvedActions.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key }) -join ', '))",
        "",
        "Approved hot memory actions were applied. Review backup before deleting or further condensing old material."
    )
    Set-Content -LiteralPath $resultPath -Value $result -Encoding UTF8

    return [ordered]@{
        backup_dir = $backupDir
        result = $resultPath
        approved_actions = $approvedActions
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
    Write-Output ("Backup: {0}" -f $applyResult.backup_dir)
    Write-Output ("Result: {0}" -f $applyResult.result)
}
