param(
    [string]$ProjectRoot = (Get-Location).Path,
    [ValidateSet("start", "phase", "resume")]
    [string]$Gate = "start",
    [switch]$Json,
    [switch]$IncludeTemplates
)

$ErrorActionPreference = "Stop"

function Resolve-ProjectRoot {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "ProjectRoot does not exist: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Add-FileIfExists {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Path,
        [string]$Tier,
        [string]$Reason
    )

    if (Test-Path -LiteralPath $Path) {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        if (-not ($List | Where-Object { $_.path -eq $resolved })) {
            $List.Add([ordered]@{
                tier = $Tier
                path = $resolved
                reason = $Reason
            })
        }
    }
}

function Find-SpecReferences {
    param(
        [string]$Root,
        [string[]]$SourceFiles
    )

    $refs = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($file in $SourceFiles) {
        if (-not (Test-Path -LiteralPath $file)) {
            continue
        }
        $text = Get-Content -LiteralPath $file -Raw
        $matches = [regex]::Matches($text, 'docs/specs/[A-Za-z0-9._-]+/(spec|tasks)\.md')
        foreach ($match in $matches) {
            [void]$refs.Add($match.Value)
        }
    }

    return $refs | ForEach-Object {
        $candidate = Join-Path $Root ($_ -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $candidate) {
            (Resolve-Path -LiteralPath $candidate).Path
        }
    }
}

function Get-GitState {
    param([string]$Root)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        return [ordered]@{
            state = "git_unavailable"
            branch = ""
            status = @()
            root = ""
        }
    }

    $inside = ""
    try {
        $inside = (& git -C $Root rev-parse --is-inside-work-tree 2>$null)
    } catch {}

    if ($LASTEXITCODE -ne 0 -or $inside.Trim() -ne "true") {
        return [ordered]@{
            state = "not_git"
            branch = ""
            status = @()
            root = ""
        }
    }

    $repoRoot = ""
    $branch = ""
    $status = @()
    try { $repoRoot = ((& git -C $Root rev-parse --show-toplevel 2>$null) | Select-Object -First 1).Trim() } catch {}
    try { $branch = ((& git -C $Root rev-parse --abbrev-ref HEAD 2>$null) | Select-Object -First 1).Trim() } catch {}
    try { $status = @(& git -C $Root status --short 2>$null) } catch {}

    return [ordered]@{
        state = if ($status.Count -gt 0) { "dirty" } else { "clean" }
        branch = $branch
        status = @($status)
        root = $repoRoot
    }
}

function Get-ContextDiscoveryFiles {
    param(
        [string]$ContextDir,
        [bool]$IncludeAllTemplates
    )

    if (-not (Test-Path -LiteralPath $ContextDir)) {
        return @()
    }

    $files = Get-ChildItem -LiteralPath $ContextDir -Recurse -File | Sort-Object FullName
    if ($IncludeAllTemplates) {
        return @($files)
    }

    return @(
        $files | Where-Object {
            $_.Name -in @("README.md", "index.md", "index.json") -and
            $_.Name -ne "case_template.md"
        }
    )
}

$root = Resolve-ProjectRoot $ProjectRoot
$contextItems = New-Object 'System.Collections.Generic.List[object]'
$warnings = New-Object 'System.Collections.Generic.List[string]'

$rootAgents = Join-Path $root "AGENTS.md"
$agentGuide = Join-Path $root ".agents\AGENTS.md"
$processPath = Join-Path $root ".agents\process.txt"
$planPath = Join-Path $root ".agents\plan.md"
$notesPath = Join-Path $root ".agents\notes.md"

Add-FileIfExists $contextItems $rootAgents "hot" "Root project guidance"
Add-FileIfExists $contextItems $agentGuide "hot" "Primary project agent guide"
Add-FileIfExists $contextItems $processPath "hot" "Current operational state"
Add-FileIfExists $contextItems $planPath "hot" "Current active plan pointer"

$specRefs = Find-SpecReferences -Root $root -SourceFiles @($processPath, $planPath)
foreach ($spec in $specRefs) {
    Add-FileIfExists $contextItems $spec "warm" "Active spec referenced by project memory"
    $specDir = Split-Path -Parent $spec
    foreach ($pairedName in @("spec.md", "tasks.md")) {
        Add-FileIfExists $contextItems (Join-Path $specDir $pairedName) "warm" "Paired active spec artifact"
    }
}

$contextDir = Join-Path $root ".agents\context"
foreach ($file in Get-ContextDiscoveryFiles -ContextDir $contextDir -IncludeAllTemplates $IncludeTemplates.IsPresent) {
    $reason = if ($IncludeTemplates.IsPresent) { "Full context audit requested" } else { "Context discovery index; open matching entries on demand" }
    Add-FileIfExists $contextItems $file.FullName "cold" $reason
}

if (Test-Path -LiteralPath $notesPath) {
    Add-FileIfExists $contextItems $notesPath "cold" "Stable notes; read on demand when relevant"
}

if (-not (Test-Path -LiteralPath $agentGuide) -and -not (Test-Path -LiteralPath $rootAgents)) {
    $warnings.Add("No AGENTS.md or .agents/AGENTS.md found for this project root.")
}
if ((Test-Path -LiteralPath $contextDir) -and -not $IncludeTemplates.IsPresent) {
    $warnings.Add("Context files are listed as cold discovery only. Open specific entries when the task keywords match.")
}

$gitState = Get-GitState -Root $root
$allFiles = @($contextItems.ToArray())
$hotFiles = @($allFiles | Where-Object { $_.tier -eq "hot" })
$warmFiles = @($allFiles | Where-Object { $_.tier -eq "warm" })
$coldFiles = @($allFiles | Where-Object { $_.tier -eq "cold" })
$warningList = @($warnings.ToArray())
$payload = [ordered]@{
    gate = $Gate
    project_root = $root
    files = $allFiles
    hot_files = $hotFiles
    warm_files = $warmFiles
    cold_files = $coldFiles
    git = $gitState
    warnings = $warningList
}

if ($Json.IsPresent) {
    $payload | ConvertTo-Json -Depth 8
    return
}

Write-Host "Project Context Gate: $Gate"
Write-Host "ProjectRoot: $root"
Write-Host ""

foreach ($tier in @("hot", "warm", "cold")) {
    $label = switch ($tier) {
        "hot" { "Hot files (load now)" }
        "warm" { "Warm files (active work package)" }
        default { "Cold files (discovery; open on demand)" }
    }
    Write-Host "${label}:"
    $tierFiles = @($contextItems | Where-Object { $_.tier -eq $tier })
    if ($tierFiles.Count -eq 0) {
        Write-Host "- (none)"
    } else {
        foreach ($item in $tierFiles) {
            Write-Host ("- {0} [{1}]" -f $item.path, $item.reason)
        }
    }
    Write-Host ""
}

Write-Host "Git state:"
Write-Host ("- state: {0}" -f $gitState.state)
if ($gitState.root) { Write-Host ("- root: {0}" -f $gitState.root) }
if ($gitState.branch) { Write-Host ("- branch: {0}" -f $gitState.branch) }
if ($gitState.status.Count -gt 0) {
    $gitState.status | ForEach-Object { Write-Host ("  {0}" -f $_) }
}
Write-Host ""

if ($warnings.Count -gt 0) {
    Write-Host "Warnings:"
    $warnings | ForEach-Object { Write-Host ("- {0}" -f $_) }
    Write-Host ""
}

Write-Host "Next: read hot files first, warm files for the active task, and cold files only when their index/README matches the task."
