param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$Json,
    [int]$LargeFileLineThreshold = 160,
    [int]$ProcessSoftLineLimit = 30,
    [int]$PlanSoftLineLimit = 20
)

$ErrorActionPreference = "Stop"

function Resolve-Root {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "ProjectRoot does not exist: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-TextFileInfo {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $lines = @(Get-Content -LiteralPath $Path)
    return [ordered]@{
        path = (Resolve-Path -LiteralPath $Path).Path
        line_count = $lines.Count
        char_count = ($lines -join "`n").Length
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
        [string]$Recommendation
    )
    $Findings.Add([ordered]@{
        severity = $Severity
        code = $Code
        path = $Path
        message = $Message
        recommendation = $Recommendation
    })
}

function Find-SpecRefs {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }
    return @(
        [regex]::Matches($Text, 'docs/specs/[A-Za-z0-9._-]+/(spec|tasks)\.md') |
            ForEach-Object { $_.Value } |
            Sort-Object -Unique
    )
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

function Get-CompletedSectionEntryCount {
    param([string]$Text)

    $localizedCompletedHeading = -join @([char]0x5DF2, [char]0x5B8C, [char]0x6210)
    $completedHeadingPattern = '^(#{1,6}\s*)?(' + [regex]::Escape($localizedCompletedHeading) + '|Completed)\s*:?\s*$'
    $entryCount = 0
    $inCompletedSection = $false
    foreach ($line in @($Text -split "`n")) {
        $trimmedLine = ([string]$line).Trim()
        if ($trimmedLine -match $completedHeadingPattern) {
            $inCompletedSection = $true
            continue
        }
        if (-not $inCompletedSection) {
            continue
        }
        if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
            continue
        }
        if ($line -match '^\s*-\s+\S') {
            $entryCount++
            continue
        }
        if ($line -match '^\s{2,}\S') {
            continue
        }
        break
    }

    return $entryCount
}

$completedListGrowthThreshold = 5
$localizedSummaryHeading = -join @([char]0x6458, [char]0x8981)
$localizedKeywordsHeading = -join @([char]0x5173, [char]0x952E, [char]0x8BCD)
$discoveryHeadingAliases = [ordered]@{
    summary = @("Summary", $localizedSummaryHeading)
    keywords = @("Keywords", $localizedKeywordsHeading)
}

$root = Resolve-Root $ProjectRoot
$agentDir = Join-Path $root ".agents"
$findings = New-Object 'System.Collections.Generic.List[object]'

if (-not (Test-Path -LiteralPath $agentDir)) {
    Add-Finding $findings "warning" "missing_agents_dir" $agentDir "Project has no .agents directory." "Run project-bootstrap before memory governance."
}

$memoryPaths = [ordered]@{
    process = Join-Path $agentDir "process.txt"
    plan = Join-Path $agentDir "plan.md"
    notes = Join-Path $agentDir "notes.md"
}

$infos = @{}
foreach ($key in $memoryPaths.Keys) {
    $info = Get-TextFileInfo -Path $memoryPaths[$key]
    if ($null -ne $info) {
        $infos[$key] = $info
        if ($info.line_count -gt $LargeFileLineThreshold) {
            Add-Finding $findings "warning" "large_memory_file" $info.path ("{0} has {1} lines." -f $key, $info.line_count) "Compress this file to its routing role; move long-lived work into docs/specs or context."
        }
    } else {
        Add-Finding $findings "info" "missing_memory_file" $memoryPaths[$key] ("{0} is missing." -f $key) "Bootstrap can restore the default file when needed."
    }
}

if ($infos.ContainsKey("process") -and $infos["process"].line_count -gt $ProcessSoftLineLimit) {
    Add-Finding $findings "info" "hot_memory_process_long" $infos["process"].path ("process.txt has {0} lines, exceeding the {1}-line soft limit for hot session memory." -f $infos["process"].line_count, $ProcessSoftLineLimit) "Compress hot session memory; move long-term history and completed tasks to docs/specs or context."
}

if ($infos.ContainsKey("plan") -and $infos["plan"].line_count -gt $PlanSoftLineLimit) {
    Add-Finding $findings "info" "hot_memory_plan_long" $infos["plan"].path ("plan.md has {0} lines, exceeding the {1}-line soft limit for hot session memory." -f $infos["plan"].line_count, $PlanSoftLineLimit) "Compress hot session memory; move long-lived tasks and detailed descriptions to docs/specs or context."
}

if ($infos.ContainsKey("process") -and $infos["process"].text -match '(?i)(history|timeline|chronology|session\s+\d+|previous session)') {
    Add-Finding $findings "warning" "process_contains_history" $infos["process"].path "process.txt appears to contain historical timeline language." "Keep process.txt to current state, blockers, next actions, and last updated."
}

if ($infos.ContainsKey("process")) {
    $completedEntryCount = Get-CompletedSectionEntryCount -Text $infos["process"].text
    if ($completedEntryCount -gt $completedListGrowthThreshold) {
        Add-Finding $findings "info" "process_completed_list_growth" $infos["process"].path ("process.txt has {0} completed entries under Completed." -f $completedEntryCount) "Compress and summarize completed history in process.txt; keep only current state, blockers, next actions, and last updated."
    }
}

if ($infos.ContainsKey("notes") -and $infos["notes"].text -match '(?i)(today|yesterday|I tried|session|todo|\[ \]|\[x\])') {
    Add-Finding $findings "warning" "notes_may_contain_session_log" $infos["notes"].path "notes.md appears to contain session log or task-list language." "Keep only stable verified facts with evidence; move task state to plan/tasks."
}

if ($infos.ContainsKey("plan")) {
    $planText = $infos["plan"].text
    $checkboxCount = ([regex]::Matches($planText, '-\s+\[[ xX]\]')).Count
    if ($planText -match '(?m)^##\s+Tasks\s*$' -or $planText -match 'T\d{2}:' -or $checkboxCount -gt 5) {
        Add-Finding $findings "warning" "plan_may_duplicate_tasks" $infos["plan"].path "plan.md appears to contain a durable task checklist." "Keep plan.md as an active pointer; move long-lived tasks to docs/specs/<slug>/tasks.md."
    }
}

$allSpecRefs = @()
foreach ($info in $infos.Values) {
    $allSpecRefs += Find-SpecRefs -Text $info.text
}
$allSpecRefs = @($allSpecRefs | Sort-Object -Unique)

foreach ($ref in $allSpecRefs) {
    $specPath = Join-Path $root ($ref -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $specPath)) {
        Add-Finding $findings "warning" "missing_active_spec_ref" $specPath "Memory references a docs/specs file that does not exist." "Create the referenced spec/task file or remove the stale pointer."
    }
}

if ($infos.ContainsKey("plan") -and $infos.ContainsKey("process")) {
    $planRefs = @(Find-SpecRefs -Text $infos["plan"].text)
    $processRefs = @(Find-SpecRefs -Text $infos["process"].text)
    if ($planRefs.Count -gt 0 -and $processRefs.Count -gt 0) {
        $missingFromPlan = @($processRefs | Where-Object { $_ -notin $planRefs })
        if ($missingFromPlan.Count -gt 0) {
            Add-Finding $findings "info" "spec_pointer_mismatch" $infos["process"].path "process.txt and plan.md do not point to the same active spec set." "Align active spec pointers before continuing long-running work."
        }
    }
}

$contextDir = Join-Path $agentDir "context"
if (Test-Path -LiteralPath $contextDir) {
    $contextFiles = @(Get-ChildItem -LiteralPath $contextDir -Recurse -File -Filter "*.md" | Where-Object { $_.Name -notin @("README.md", "case_template.md") })
    foreach ($file in $contextFiles) {
        $preview = Get-Content -LiteralPath $file.FullName -TotalCount 30
        $hasSummary = Test-DiscoveryHeading -Lines $preview -Aliases $discoveryHeadingAliases.summary
        $hasKeywords = Test-DiscoveryHeading -Lines $preview -Aliases $discoveryHeadingAliases.keywords
        if (-not $hasSummary -or -not $hasKeywords) {
            Add-Finding $findings "info" "context_missing_discovery_metadata" $file.FullName "Context file lacks recognized discovery metadata near the top." "Add concise Summary/Keywords discovery metadata so agents can load context progressively."
        }
    }
}

$findingList = @($findings.ToArray())
$warningCount = @($findingList | Where-Object { $_.severity -eq "warning" }).Count
$infoCount = @($findingList | Where-Object { $_.severity -eq "info" }).Count

$payload = [ordered]@{
    project_root = $root
    checked_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    findings = $findingList
    summary = [ordered]@{
        finding_count = $findingList.Count
        warnings = $warningCount
        infos = $infoCount
    }
}

if ($Json.IsPresent) {
    $payload | ConvertTo-Json -Depth 8
    return
}

Write-Output ("Memory diagnosis: {0}" -f $root)
Write-Output ("Findings: {0} (warnings={1}, info={2})" -f $payload.summary.finding_count, $payload.summary.warnings, $payload.summary.infos)
foreach ($finding in $findings) {
    Write-Output ("[{0}] {1}: {2}" -f $finding.severity, $finding.code, $finding.message)
    Write-Output ("  Path: {0}" -f $finding.path)
    Write-Output ("  Recommendation: {0}" -f $finding.recommendation)
}
