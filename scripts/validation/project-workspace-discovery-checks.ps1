#requires -Version 7.6

[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$defaultRepositoryRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { [System.IO.Path]::GetFullPath($defaultRepositoryRoot) } else { [System.IO.Path]::GetFullPath($RepositoryRoot) }
. (Join-Path $repoRoot "scripts/validation/powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime

if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-workspace-discovery-{0}" -f ([guid]::NewGuid().ToString("N")))
}
$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null

$fixtureRoot = Join-Path $scriptDir "project-workspace-fixtures/new-project"
$discoveryPath = Join-Path $repoRoot "skills/project-workspace/scripts/project-workspace.ps1"
$results = New-Object 'System.Collections.Generic.List[object]'

function Add-CheckResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet("PASS", "FAIL")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    [void]$results.Add([ordered]@{ name = $Name; status = $Status; detail = $Detail })
}

function Get-SafeDetail {
    param([AllowEmptyString()][string]$Message)

    return $Message.Replace($scratchRootFull, "<scratch>").Replace($repoRoot, "<repository>")
}

function New-FixtureProject {
    param([Parameter(Mandatory = $true)][string]$Name)

    $destination = Join-Path $scratchRootFull $Name
    Copy-Item -LiteralPath $fixtureRoot -Destination $destination -Recurse
    return $destination
}

function Write-Utf8 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Get-NormalizedRevisionHash {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = @($text -split "`n")
    $output = New-Object 'System.Collections.Generic.List[string]'
    $inFrontMatter = ($lines.Count -gt 0 -and [string]$lines[0] -ceq "---")
    $closed = $false
    $removed = $false
    foreach ($line in $lines) {
        if ($inFrontMatter -and -not $closed -and [string]$line -ceq "---" -and $output.Count -gt 0) { $closed = $true }
        if ($inFrontMatter -and -not $closed -and -not $removed -and [string]$line -match '^revision:') { $removed = $true; continue }
        [void]$output.Add([string]$line)
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($output.ToArray() -join "`n")
    return "sha256:" + ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bytes))).Replace('-', '').ToLowerInvariant()
}

function Set-ValidWorkRevision {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $path = Join-Path $ProjectRoot ".agents/work/fixture-work-item.md"
    $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $hash = Get-NormalizedRevisionHash -Path $path
    Write-Utf8 -Path $path -Text ($text -replace '(?m)^revision:.*$', ("revision: {0}" -f $hash))
}

function Set-WorkGitAnchor {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Branch,
        [string]$LastVerifiedCommit = ""
    )

    $path = Join-Path $ProjectRoot ".agents/work/fixture-work-item.md"
    $text = [System.IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.AddRange([string[]]@($text -split "`n"))
    $closing = -1
    for ($index = 1; $index -lt $lines.Count; $index++) { if ([string]$lines[$index] -ceq "---") { $closing = $index; break } }
    if ($closing -lt 0) { throw "work fixture frontmatter is malformed" }
    for ($index = $closing - 1; $index -ge 0; $index--) {
        if ([string]$lines[$index] -match '^git:') {
            $lines.RemoveAt($index)
            while ($index -lt $lines.Count -and [string]$lines[$index] -match '^  (?:branch|worktree|last_verified_commit):') { $lines.RemoveAt($index) }
        }
    }
    $closing = -1
    for ($index = 1; $index -lt $lines.Count; $index++) { if ([string]$lines[$index] -ceq "---") { $closing = $index; break } }
    if ($closing -lt 0) { throw "work fixture frontmatter is malformed after anchor replacement" }
    $anchorLines = @("git:", ("  branch: {0}" -f $Branch), "  worktree: fixture-worktree")
    if (-not [string]::IsNullOrWhiteSpace($LastVerifiedCommit)) { $anchorLines += ("  last_verified_commit: {0}" -f $LastVerifiedCommit) }
    for ($index = 0; $index -lt $anchorLines.Count; $index++) { $lines.Insert($closing + $index, $anchorLines[$index]) }
    Write-Utf8 -Path $path -Text ($lines.ToArray() -join "`n")
    Set-ValidWorkRevision -ProjectRoot $ProjectRoot
}

function Add-ArchivedContext {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $source = Join-Path $ProjectRoot ".agents/context/fixture-context.md"
    $text = [System.IO.File]::ReadAllText($source, [Text.UTF8Encoding]::new($false, $true))
    $text = $text -replace '(?m)^id:.*$', 'id: archived-context'
    $text = $text -replace '(?m)^title:.*$', 'title: Archived context'
    $text = $text -replace '(?m)^status:.*$', 'status: archived'
    $text = $text -replace '(?m)^summary:.*$', 'summary: Archived metadata excluded from default discovery.'
    Write-Utf8 -Path (Join-Path $ProjectRoot ".agents/context/archived-context.md") -Text $text
}

function Add-ValidGlossary {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $path = Join-Path $ProjectRoot ".agents/glossary.yaml"
    $text = @(
        "schema: agent-ecosystem/glossary/v1",
        "terms:",
        "  - canonical: telemetry",
        "    aliases:",
        "      - 串口统计",
        "    symbols:",
        "      - serial_stats",
        "    relations:",
        "      - fixture context",
        "    evidence:",
        "      - public fixture metadata",
        "  - canonical: fixture context",
        "    aliases:",
        "      - 项目上下文",
        "    symbols:",
        "      - fixture_context",
        "    relations:",
        "    evidence:",
        "      - public fixture metadata"
    ) -join "`n"
    Write-Utf8 -Path $path -Text ($text + "`n")
}

function Invoke-Workspace {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("discover", "check")][string]$Operation,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [AllowEmptyString()][string]$Query = "",
        [int]$Limit = 5,
        [string[]]$Status = @(),
        [switch]$CurrentBranchOnly
    )

    $arguments = @("-NoProfile", "-NonInteractive", "-File", $discoveryPath, "-Operation", $Operation, "-ProjectRoot", $ProjectRoot, "-Json")
    if ($Operation -eq "discover") {
        $arguments += @("-Query", $Query, "-Limit", [string]$Limit)
        if (@($Status).Count -gt 0) { $arguments += @("-Status") + @($Status) }
        if ($CurrentBranchOnly.IsPresent) { $arguments += "-CurrentBranchOnly" }
    }
    $output = @(& pwsh @arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = [int]$LASTEXITCODE
    $text = $output -join "`n"
    try { $payload = $text | ConvertFrom-Json -Depth 50 -ErrorAction Stop }
    catch { throw "workspace operation did not return JSON: $($Operation)" }
    return [ordered]@{ exit_code = $exitCode; payload = $payload; text = $text }
}

function Get-ProjectFingerprint {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force | Sort-Object FullName)) {
        $relative = [System.IO.Path]::GetRelativePath($ProjectRoot, $file.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [void]$lines.Add("$relative|$hash")
    }
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($lines.ToArray() -join "`n")))).Replace('-', '').ToLowerInvariant()
}

function Assert-Condition {
    param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)

    if (-not $Condition) { throw $Message }
}

try {
    $project = New-FixtureProject -Name "catalog-and-search"
    Add-ArchivedContext -ProjectRoot $project
    $contextPath = Join-Path $project ".agents/context/fixture-context.md"
    $contextText = [System.IO.File]::ReadAllText($contextPath, [Text.UTF8Encoding]::new($false, $true)).Replace("- project-workspace", "- project-workspace`n  - telemetry")
    Write-Utf8 -Path $contextPath -Text $contextText
    Add-ValidGlossary -ProjectRoot $project
    Set-ValidWorkRevision -ProjectRoot $project
    $first = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "串口统计"
    Assert-Condition ($first.payload.status -ceq "PASS" -and $first.payload.catalog.action -ceq "written" -and [int]$first.payload.catalog.asset_count -eq 5) "Initial catalog build did not discover all canonical assets."
    Assert-Condition ($first.payload.glossary.state -ceq "valid") "Valid evidence-backed glossary was not accepted."
    Assert-Condition (@($first.payload.results[0].reason_codes) -contains "alias_match") "Alias query did not return alias_match."
    $catalogBefore = [System.IO.File]::ReadAllText((Join-Path $project ".agents/.cache/catalog.json"), [Text.UTF8Encoding]::new($false, $true))
    $second = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "串口统计"
    $catalogAfter = [System.IO.File]::ReadAllText((Join-Path $project ".agents/.cache/catalog.json"), [Text.UTF8Encoding]::new($false, $true))
    Assert-Condition ($second.payload.status -ceq "PASS" -and $second.payload.catalog.action -ceq "reused" -and [bool]$second.payload.catalog.fresh) "Unchanged discovery did not reuse a fresh catalog."
    Assert-Condition ($catalogBefore -ceq $catalogAfter) "Repeated discovery changed deterministic catalog bytes."
    $symbol = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "serial_stats"
    Assert-Condition (@($symbol.payload.results[0].reason_codes) -contains "symbol_match") "Symbol query did not return symbol_match."
    $limited = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "fixture" -Limit 2
    Assert-Condition ([int]$limited.payload.result_count -eq 2) "Discover limit was not enforced."
    $default = Invoke-Workspace -Operation discover -ProjectRoot $project
    Assert-Condition (@($default.payload.results | Where-Object { $_.status -ceq "archived" }).Count -eq 0) "Archived assets were not excluded by default."
    $archived = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "archived" -Status @("archived")
    Assert-Condition ([int]$archived.payload.result_count -eq 1) "Explicit status filter did not expose archived asset."
    Add-CheckResult -Name "catalog-search-determinism" -Status "PASS" -Detail "Catalog build/reuse, glossary alias/symbol expansion, filters, default exclusion, and limit passed."
}
catch { Add-CheckResult -Name "catalog-search-determinism" -Status "FAIL" -Detail (Get-SafeDetail $_.Exception.Message) }

try {
    $project = New-FixtureProject -Name "cache-invalidation"
    Set-ValidWorkRevision -ProjectRoot $project
    $initial = Invoke-Workspace -Operation discover -ProjectRoot $project
    Assert-Condition ($initial.payload.catalog.action -ceq "written") "Cache matrix fixture did not create its catalog."
    $catalogPath = Join-Path $project ".agents/.cache/catalog.json"
    Write-Utf8 -Path $catalogPath -Text ""
    $empty = Invoke-Workspace -Operation discover -ProjectRoot $project
    Assert-Condition ($empty.payload.status -ceq "PASS" -and $empty.payload.catalog.action -ceq "written") "Empty catalog was not rebuilt."
    Write-Utf8 -Path $catalogPath -Text "not-json"
    $corrupt = Invoke-Workspace -Operation discover -ProjectRoot $project
    Assert-Condition ($corrupt.payload.status -ceq "PASS" -and $corrupt.payload.catalog.action -ceq "written") "Corrupt catalog was not rebuilt."
    $contextPath = Join-Path $project ".agents/context/fixture-context.md"
    $contextText = [System.IO.File]::ReadAllText($contextPath, [Text.UTF8Encoding]::new($false, $true)).Replace("canonical Context fixture", "changed canonical Context fixture")
    Write-Utf8 -Path $contextPath -Text $contextText
    $catalogFingerprintBeforeCheck = (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash
    $stale = Invoke-Workspace -Operation check -ProjectRoot $project
    $catalogFingerprintAfterCheck = (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash
    Assert-Condition ($stale.payload.status -ceq "FAIL" -and @($stale.payload.findings | Where-Object code -eq "catalog-stale").Count -eq 1) "Read-only check did not report stale catalog."
    Assert-Condition ($catalogFingerprintBeforeCheck -ceq $catalogFingerprintAfterCheck) "Check changed the catalog cache."
    $rebuilt = Invoke-Workspace -Operation discover -ProjectRoot $project
    Assert-Condition ($rebuilt.payload.status -ceq "PASS" -and $rebuilt.payload.catalog.action -ceq "written") "Stale catalog was not rebuilt."
    Remove-Item -LiteralPath (Join-Path $project ".agents/context/fixture-context.md") -Force
    $deleted = Invoke-Workspace -Operation discover -ProjectRoot $project
    Assert-Condition ([int]$deleted.payload.catalog.asset_count -eq 3) "Deleted canonical asset remained in catalog."
    $procedurePath = Join-Path $project ".agents/procedures/fixture-procedure.md"
    $renamedPath = Join-Path $project ".agents/procedures/renamed-procedure.md"
    Move-Item -LiteralPath $procedurePath -Destination $renamedPath
    $renamedText = [System.IO.File]::ReadAllText($renamedPath, [Text.UTF8Encoding]::new($false, $true)) -replace '(?m)^id:.*$', 'id: renamed-procedure'
    Write-Utf8 -Path $renamedPath -Text $renamedText
    $renamed = Invoke-Workspace -Operation discover -ProjectRoot $project
    $catalog = Get-Content -Raw $catalogPath | ConvertFrom-Json -Depth 50
    Assert-Condition (@($catalog.assets | Where-Object path -eq ".agents/procedures/renamed-procedure.md").Count -eq 1 -and @($catalog.assets | Where-Object path -eq ".agents/procedures/fixture-procedure.md").Count -eq 0) "Renamed canonical asset was not reflected in catalog."
    Add-CheckResult -Name "cache-invalidation-matrix" -Status "PASS" -Detail "Missing/empty/corrupt/stale cache, deletion, rename, and read-only stale check passed."
}
catch { Add-CheckResult -Name "cache-invalidation-matrix" -Status "FAIL" -Detail (Get-SafeDetail $_.Exception.Message) }

try {
    $project = New-FixtureProject -Name "revision-read-only"
    Set-ValidWorkRevision -ProjectRoot $project
    $lf = Invoke-Workspace -Operation discover -ProjectRoot $project
    $lfCheck = Invoke-Workspace -Operation check -ProjectRoot $project
    Assert-Condition ($lfCheck.payload.status -ceq "PASS" -and $lfCheck.payload.revisions[0].state -ceq "revision_match") "LF revision did not validate."
    $workPath = Join-Path $project ".agents/work/fixture-work-item.md"
    $workText = [System.IO.File]::ReadAllText($workPath, [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    Write-Utf8 -Path $workPath -Text ($workText -replace "`n", "`r`n")
    $crlfDiscover = Invoke-Workspace -Operation discover -ProjectRoot $project
    $crlfCheck = Invoke-Workspace -Operation check -ProjectRoot $project
    Assert-Condition ($crlfCheck.payload.status -ceq "PASS" -and $crlfCheck.payload.revisions[0].state -ceq "revision_match" -and $lfCheck.payload.revisions[0].actual_revision -ceq $crlfCheck.payload.revisions[0].actual_revision) "CRLF/LF revision equivalence failed."
    $before = Get-ProjectFingerprint -ProjectRoot $project
    $catalogBefore = Get-ProjectFingerprint -ProjectRoot (Join-Path $project ".agents/.cache")
    $readOnly = Invoke-Workspace -Operation check -ProjectRoot $project
    $after = Get-ProjectFingerprint -ProjectRoot $project
    $catalogAfter = Get-ProjectFingerprint -ProjectRoot (Join-Path $project ".agents/.cache")
    Assert-Condition ($readOnly.payload.read_only -and $before -ceq $after -and $catalogBefore -ceq $catalogAfter) "Check changed project or catalog fingerprints."
    $missingCatalogProject = New-FixtureProject -Name "check-without-catalog"
    $missingCheck = Invoke-Workspace -Operation check -ProjectRoot $missingCatalogProject
    Assert-Condition ($missingCheck.payload.read_only -and -not (Test-Path -LiteralPath (Join-Path $missingCatalogProject ".agents/.cache/catalog.json"))) "Check created a missing catalog."
    Add-CheckResult -Name "revision-and-read-only" -Status "PASS" -Detail "Revision match, CRLF/LF equivalence, check fingerprints, and missing-cache read-only behavior passed."
}
catch { Add-CheckResult -Name "revision-and-read-only" -Status "FAIL" -Detail (Get-SafeDetail $_.Exception.Message) }

try {
    if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { throw "git executable is required for the Git anchor fixture" }
    $project = New-FixtureProject -Name "git-anchors"
    Set-ValidWorkRevision -ProjectRoot $project
    $noGit = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "fixture work item"
    Assert-Condition ($noGit.payload.git.state -ceq "unavailable" -and @($noGit.payload.findings | Where-Object code -eq "git-unavailable").Count -eq 1) "No-Git fixture did not degrade with a stable warning."
    & git -C $project init --initial-branch=fixture 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { & git -C $project init 2>&1 | Out-Null; & git -C $project branch -M fixture 2>&1 | Out-Null }
    $branch = (& git -C $project symbolic-ref --short HEAD).Trim()
    Set-WorkGitAnchor -ProjectRoot $project -Branch $branch
    & git -C $project add . 2>&1 | Out-Null
    & git -C $project -c user.name="fixture" -c user.email="fixture@example.invalid" commit -m "fixture" 2>&1 | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "Git anchor fixture commit failed."
    $commit = (& git -C $project rev-parse HEAD).Trim()
    Set-WorkGitAnchor -ProjectRoot $project -Branch $branch -LastVerifiedCommit $commit
    $matched = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "fixture work item"
    $matchedCheck = Invoke-Workspace -Operation check -ProjectRoot $project
    Assert-Condition ($matchedCheck.payload.git.state -ceq "available" -and @($matchedCheck.payload.anchors | Where-Object { $_.branch_state -eq "branch_match" -and $_.commit_state -eq "reachable" }).Count -eq 1) "Matching reachable Git anchor was not reported."
    Set-WorkGitAnchor -ProjectRoot $project -Branch "other-branch" -LastVerifiedCommit ("f" * 40)
    $mismatch = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "fixture work item"
    $mismatchCheck = Invoke-Workspace -Operation check -ProjectRoot $project
    Assert-Condition (@($mismatchCheck.payload.anchors | Where-Object { $_.branch_state -eq "branch_mismatch" -and $_.commit_state -eq "unreachable" }).Count -eq 1) "Branch mismatch or unreachable anchor was not reported."
    Assert-Condition (@($mismatch.payload.findings | Where-Object code -eq "branch_mismatch").Count -ge 1) "Discover did not expose branch_mismatch."
    $currentOnly = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "fixture work item" -CurrentBranchOnly
    Assert-Condition ([int]$currentOnly.payload.result_count -eq 0) "current-branch-only did not exclude mismatched anchor."
    $head = (& git -C $project rev-parse HEAD).Trim()
    Write-Utf8 -Path (Join-Path $project ".git/shallow") -Text ($head + "`n")
    $shallow = Invoke-Workspace -Operation check -ProjectRoot $project
    Assert-Condition ([bool]$shallow.payload.git.shallow -and [bool]$shallow.payload.git.dirty) "Shallow/dirty Git fixture was not observed."
    Add-CheckResult -Name "git-anchors-and-degradation" -Status "PASS" -Detail "No-Git, branch match/mismatch, reachable/unreachable, current-branch-only, dirty, and shallow states passed."
}
catch { Add-CheckResult -Name "git-anchors-and-degradation" -Status "FAIL" -Detail (Get-SafeDetail $_.Exception.Message) }

try {
    $invalidCases = [ordered]@{
        "unknown-relation" = @("schema: agent-ecosystem/glossary/v1", "terms:", "  - canonical: telemetry", "    aliases:", "    symbols:", "    relations:", "      - not-declared", "    evidence:", "      - public fixture")
        "relation-cycle" = @("schema: agent-ecosystem/glossary/v1", "terms:", "  - canonical: alpha", "    aliases:", "    symbols:", "    relations:", "      - beta", "    evidence:", "      - public fixture", "  - canonical: beta", "    aliases:", "    symbols:", "    relations:", "      - alpha", "    evidence:", "      - public fixture")
        "alias-conflict" = @("schema: agent-ecosystem/glossary/v1", "terms:", "  - canonical: alpha", "    aliases:", "      - same-name", "    symbols:", "    relations:", "    evidence:", "      - public fixture", "  - canonical: beta", "    aliases:", "      - same-name", "    symbols:", "    relations:", "    evidence:", "      - public fixture")
        "malicious-value" = @("schema: agent-ecosystem/glossary/v1", "terms:", "  - canonical: C:\\Users\\private", "    aliases:", "    symbols:", "    relations:", "    evidence:", "      - public fixture")
        "format-error" = @("schema: agent-ecosystem/glossary/v1", " terms:", "  - canonical: malformed", "    aliases:", "    symbols:", "    relations:", "    evidence:", "      - public fixture")
    }
    foreach ($case in $invalidCases.Keys) {
        $project = New-FixtureProject -Name ("glossary-{0}" -f $case)
        $glossary = Join-Path $project ".agents/glossary.yaml"
        Write-Utf8 -Path $glossary -Text (($invalidCases[$case] -join "`n") + "`n")
        $run = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "telemetry"
        Assert-Condition ($run.payload.status -ceq "FAIL" -and $run.payload.glossary.state -ceq "invalid" -and -not (Test-Path -LiteralPath (Join-Path $project ".agents/.cache/catalog.json"))) ("Glossary case failed open: {0}" -f $case)
    }
    Add-CheckResult -Name "glossary-fail-closed" -Status "PASS" -Detail "Unknown relation, cycle, alias conflict, unsafe value, and malformed glossary inputs fail closed without cache writes."
}
catch { Add-CheckResult -Name "glossary-fail-closed" -Status "FAIL" -Detail (Get-SafeDetail $_.Exception.Message) }

$failures = @($results.ToArray() | Where-Object status -eq "FAIL")
$summary = [ordered]@{
    schema_version = 1
    status = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }
    scenario_count = $results.Count
    pass = @($results.ToArray() | Where-Object status -eq "PASS").Count
    fail = $failures.Count
    project_read_only = $true
    cases = @($results.ToArray())
}

if ($Json.IsPresent) { $summary | ConvertTo-Json -Depth 20 }
else {
    Write-Output ("project-workspace discovery fixtures: PASS={0} FAIL={1}" -f $summary.pass, $summary.fail)
    foreach ($failure in $failures) { Write-Output ("[FAIL] {0}: {1}" -f $failure.name, $failure.detail) }
}

if ($summary.status -ne "PASS") { exit 1 }
exit 0
