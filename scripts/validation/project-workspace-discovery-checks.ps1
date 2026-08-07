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
    # NOTE: The checked-in Slice A fixture intentionally names a historical
    # Spec that is not present. Slice B baseline cases normalize only their
    # scratch copy; the dedicated broken-reference case injects adversarial IDs.
    $specPath = Join-Path $destination "docs/specs/fixture-spec/spec.md"
    $specText = [System.IO.File]::ReadAllText($specPath, [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $specText = [regex]::Replace($specText, '(?m)^supersedes:\n(?:  - .*\n)*', "supersedes: []`n")
    [System.IO.File]::WriteAllText($specPath, $specText, [Text.UTF8Encoding]::new($false))
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
        [string]$Worktree = "fixture-worktree",
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
    $anchorLines = @("git:", ("  branch: {0}" -f $Branch), ("  worktree: {0}" -f $Worktree))
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
        "      - public fixture metadata",
        "  - canonical: alpha-source",
        "    aliases:",
        "    symbols:",
        "    relations:",
        "      - shared-target",
        "    evidence:",
        "      - public fixture metadata",
        "  - canonical: beta-source",
        "    aliases:",
        "    symbols:",
        "    relations:",
        "      - shared-target",
        "    evidence:",
        "      - public fixture metadata",
        "  - canonical: shared-target",
        "    aliases:",
        "    symbols:",
        "    relations:",
        "    evidence:",
        "      - public fixture metadata"
    ) -join "`n"
    Write-Utf8 -Path $path -Text ($text + "`n")
}

function Set-SpecReferences {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$RelatedWork,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Supersedes
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @(
            "---",
            "schema: agent-ecosystem/spec/v1",
            "id: fixture-spec",
            "title: Fixture project specification",
            "status: draft",
            "updated: 2026-01-01T00:00:00Z",
            "summary: Exercise the canonical Spec fixture."
        )) { [void]$lines.Add($line) }
    if (@($RelatedWork).Count -eq 0) { [void]$lines.Add("related_work: []") }
    else {
        [void]$lines.Add("related_work:")
        foreach ($value in @($RelatedWork)) { [void]$lines.Add(("  - {0}" -f $value)) }
    }
    if (@($Supersedes).Count -eq 0) { [void]$lines.Add("supersedes: []") }
    else {
        [void]$lines.Add("supersedes:")
        foreach ($value in @($Supersedes)) { [void]$lines.Add(("  - {0}" -f $value)) }
    }
    foreach ($line in @("---", "", "This body documents fixture acceptance criteria and has no execution semantics.")) { [void]$lines.Add($line) }
    Write-Utf8 -Path (Join-Path $ProjectRoot "docs/specs/fixture-spec/spec.md") -Text ($lines.ToArray() -join "`n")
}

function Add-ContextFixture {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Updated,
        [Parameter(Mandatory = $true)][string]$Keyword
    )

    $text = @(
        "---",
        "schema: agent-ecosystem/context/v1",
        ("id: {0}" -f $Id),
        ("title: {0}" -f $Id),
        "status: active",
        ("updated: {0}" -f $Updated),
        ("summary: Deterministic ordering fixture for {0}." -f $Keyword),
        "keywords:",
        ("  - {0}" -f $Keyword),
        "evidence:",
        "  - Self-contained public fixture",
        "---",
        "",
        "This body is inert fixture documentation."
    ) -join "`n"
    Write-Utf8 -Path (Join-Path $ProjectRoot (".agents/context/{0}.md" -f $Id)) -Text $text
}

function Add-SpecFixture {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Updated,
        [Parameter(Mandatory = $true)][string]$SearchText
    )

    $text = @(
        "---",
        "schema: agent-ecosystem/spec/v1",
        ("id: {0}" -f $Id),
        ("title: {0} {1}" -f $Id, $SearchText),
        "status: draft",
        ("updated: {0}" -f $Updated),
        ("summary: Deterministic ordering fixture for {0}." -f $SearchText),
        "related_work:",
        "  - fixture-work-item",
        "supersedes: []",
        "---",
        "",
        "This body is inert fixture documentation."
    ) -join "`n"
    Write-Utf8 -Path (Join-Path $ProjectRoot ("docs/specs/{0}/spec.md" -f $Id)) -Text $text
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

function Get-ProjectFileMap {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$ExcludeGit
    )

    $map = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($file in @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force | Sort-Object FullName)) {
        $relative = [System.IO.Path]::GetRelativePath($ProjectRoot, $file.FullName).Replace('\', '/')
        if ($ExcludeGit.IsPresent -and ($relative -ceq ".git" -or $relative.StartsWith(".git/", [StringComparison]::Ordinal))) { continue }
        $map[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return ,$map
}

function Get-ChangedProjectPaths {
    param(
        [Parameter(Mandatory = $true)][object]$Before,
        [Parameter(Mandatory = $true)][object]$After
    )

    $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($key in $Before.Keys) { [void]$keys.Add([string]$key) }
    foreach ($key in $After.Keys) { [void]$keys.Add([string]$key) }
    $changed = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in $keys) {
        if (-not $Before.ContainsKey($key) -or -not $After.ContainsKey($key) -or [string]$Before[$key] -cne [string]$After[$key]) {
            [void]$changed.Add($key)
        }
    }
    $changed.Sort([StringComparer]::Ordinal)
    return @($changed.ToArray())
}

function Get-CanonicalSourceFingerprint {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $map = Get-ProjectFileMap -ProjectRoot $ProjectRoot -ExcludeGit
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($path in @($map.Keys | Where-Object {
                $_ -match '^(?:\.agents/(?:work|context|procedures)/|docs/specs/)' -or $_ -ceq '.agents/glossary.yaml'
            } | Sort-Object)) {
        [void]$lines.Add(("{0}|{1}" -f $path, $map[$path]))
    }
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($lines.ToArray() -join "`n")))).Replace('-', '').ToLowerInvariant()
}

function Get-WorktreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $map = Get-ProjectFileMap -ProjectRoot $ProjectRoot -ExcludeGit
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in $map.Keys) { [void]$keys.Add([string]$key) }
    $keys.Sort([StringComparer]::Ordinal)
    $lines = @($keys.ToArray() | ForEach-Object { "{0}|{1}" -f $_, $map[$_] })
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($lines -join "`n")))).Replace('-', '').ToLowerInvariant()
}

function Get-FileFingerprintOrMissing {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "missing" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-GitFingerprint {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ".git"))) { return "unavailable" }
    $hadOptionalLocks = Test-Path Env:GIT_OPTIONAL_LOCKS
    $previousOptionalLocks = $env:GIT_OPTIONAL_LOCKS
    try {
        $env:GIT_OPTIONAL_LOCKS = "0"
        $branch = (@(& git -C $ProjectRoot symbolic-ref --quiet --short HEAD 2>$null) -join "`n").Trim()
        $head = (@(& git -C $ProjectRoot rev-parse HEAD 2>$null) -join "`n").Trim()
        $status = (@(& git -C $ProjectRoot status --porcelain --untracked-files=all 2>$null) -join "`n").Trim()
        $text = "branch={0}`nhead={1}`nstatus={2}" -f $branch, $head, $status
        return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($text)))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($hadOptionalLocks) { $env:GIT_OPTIONAL_LOCKS = $previousOptionalLocks }
        else { Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue }
    }
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
    $canonicalBeforeDiscover = Get-CanonicalSourceFingerprint -ProjectRoot $project
    $filesBeforeDiscover = Get-ProjectFileMap -ProjectRoot $project -ExcludeGit
    $first = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "串口统计"
    $filesAfterDiscover = Get-ProjectFileMap -ProjectRoot $project -ExcludeGit
    $discoverChangedPaths = @(Get-ChangedProjectPaths -Before $filesBeforeDiscover -After $filesAfterDiscover)
    Assert-Condition ($first.payload.status -ceq "PASS" -and $first.payload.catalog.action -ceq "written" -and [int]$first.payload.catalog.asset_count -eq 5) "Initial catalog build did not discover all canonical assets."
    Assert-Condition (($discoverChangedPaths -join "`n") -ceq ".agents/.cache/catalog.json") "Discover wrote outside the disposable Catalog cache."
    Assert-Condition ($canonicalBeforeDiscover -ceq (Get-CanonicalSourceFingerprint -ProjectRoot $project)) "Discover changed canonical source files."
    Assert-Condition ($first.payload.glossary.state -ceq "valid") "Valid evidence-backed glossary was not accepted."
    Assert-Condition (@($first.payload.results[0].reason_codes) -contains "alias_match") "Alias query did not return alias_match."
    $catalogBefore = [System.IO.File]::ReadAllText((Join-Path $project ".agents/.cache/catalog.json"), [Text.UTF8Encoding]::new($false, $true))
    $second = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "串口统计"
    $catalogAfter = [System.IO.File]::ReadAllText((Join-Path $project ".agents/.cache/catalog.json"), [Text.UTF8Encoding]::new($false, $true))
    Assert-Condition ($second.payload.status -ceq "PASS" -and $second.payload.catalog.action -ceq "reused" -and [bool]$second.payload.catalog.fresh) "Unchanged discovery did not reuse a fresh catalog."
    Assert-Condition ($catalogBefore -ceq $catalogAfter) "Repeated discovery changed deterministic catalog bytes."
    $symbol = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "serial_stats"
    Assert-Condition (@($symbol.payload.results[0].reason_codes) -contains "symbol_match") "Symbol query did not return symbol_match."
    $direct = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "fixture context"
    Assert-Condition ([string]$direct.payload.results[0].reason_codes[0] -ceq "direct_match") "Reason-code precedence did not place direct_match first."
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
    $project = New-FixtureProject -Name "deterministic-order-dedup"
    Set-ValidWorkRevision -ProjectRoot $project
    Add-ValidGlossary -ProjectRoot $project
    foreach ($fixture in @(
            [ordered]@{ id = "tie-alpha"; updated = "2026-01-01T00:00:00Z" },
            [ordered]@{ id = "tie-beta"; updated = "2026-01-01T00:00:00Z" },
            [ordered]@{ id = "tie-delta"; updated = "2026-01-01T00:00:00Z" },
            [ordered]@{ id = "tie-epsilon"; updated = "2026-01-01T00:00:00Z" },
            [ordered]@{ id = "tie-gamma"; updated = "2026-01-01T00:00:00Z" },
            [ordered]@{ id = "tie-zeta"; updated = "2026-01-01T00:00:00Z" },
            [ordered]@{ id = "tie-newer"; updated = "2026-02-01T00:00:00Z" }
        )) {
        Add-ContextFixture -ProjectRoot $project -Id $fixture.id -Updated $fixture.updated -Keyword "tie-marker"
    }
    Add-ContextFixture -ProjectRoot $project -Id "shared-target-context" -Updated "2026-01-01T00:00:00Z" -Keyword "shared-target"
    Add-SpecFixture -ProjectRoot $project -Id "tie-draft" -Updated "2027-01-01T00:00:00Z" -SearchText "tie-marker"

    $defaultLimit = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "tie-marker"
    $defaultIds = @($defaultLimit.payload.results | ForEach-Object { [string]$_.id })
    Assert-Condition ([int]$defaultLimit.payload.limit -eq 5 -and [int]$defaultLimit.payload.result_count -eq 5) "Default discovery limit is not exactly 5."
    Assert-Condition (($defaultIds -join ",") -ceq "tie-newer,tie-alpha,tie-beta,tie-delta,tie-epsilon") "Updated/status/path ordinal ordering did not produce the exact default first five results."

    $allTies = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "tie-marker" -Limit 20
    $allIds = @($allTies.payload.results | ForEach-Object { [string]$_.id })
    Assert-Condition (($allIds -join ",") -ceq "tie-newer,tie-alpha,tie-beta,tie-delta,tie-epsilon,tie-gamma,tie-zeta,tie-draft") "Complete deterministic sort key did not order score/status/updated/path/type/id exactly."
    $repeat = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "tie-marker" -Limit 20
    Assert-Condition (($allTies.payload.results | ConvertTo-Json -Depth 20 -Compress) -ceq ($repeat.payload.results | ConvertTo-Json -Depth 20 -Compress)) "Repeated discovery changed deterministic result ordering."

    $deduplicated = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "alpha-source beta-source" -Limit 20
    Assert-Condition ([int]$deduplicated.payload.result_count -eq 1 -and [string]$deduplicated.payload.results[0].id -ceq "shared-target-context") "Repeated Glossary expansion produced duplicate candidates."
    Assert-Condition ((@($deduplicated.payload.results[0].reason_codes) -join ",") -ceq "relation_match") "Repeated Glossary expansion did not retain one stable relation_match reason."
    Add-CheckResult -Name "deterministic-order-and-dedup" -Status "PASS" -Detail "Default limit 5, score/status/updated/path/type/id ordering, ordinal ties, reason precedence, and Glossary/candidate deduplication passed."
}
catch { Add-CheckResult -Name "deterministic-order-and-dedup" -Status "FAIL" -Detail (Get-SafeDetail $_.Exception.Message) }

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
    $project = New-FixtureProject -Name "catalog-shape-invalid"
    Set-ValidWorkRevision -ProjectRoot $project
    $initial = Invoke-Workspace -Operation discover -ProjectRoot $project
    Assert-Condition ($initial.payload.status -ceq "PASS" -and $initial.payload.catalog.action -ceq "written") "Catalog shape fixture did not create a valid baseline cache."
    $catalogPath = Join-Path $project ".agents/.cache/catalog.json"
    $baselineText = [System.IO.File]::ReadAllText($catalogPath, [Text.UTF8Encoding]::new($false, $true))
    $shapeCases = @(
        [ordered]@{ name = "extra-field"; code = "catalog-schema"; mutate = { param($catalog) $catalog | Add-Member -NotePropertyName "unexpected" -NotePropertyValue $true } },
        [ordered]@{ name = "wrong-schema"; code = "catalog-schema"; mutate = { param($catalog) $catalog.schema = "agent-ecosystem/catalog/v2" } },
        [ordered]@{ name = "wrong-version"; code = "catalog-schema"; mutate = { param($catalog) $catalog.schema_version = 2 } },
        [ordered]@{ name = "duplicate-path"; code = "catalog-duplicate"; mutate = { param($catalog) $catalog.assets[1].path = [string]$catalog.assets[0].path } },
        [ordered]@{ name = "duplicate-id"; code = "catalog-duplicate"; mutate = {
                param($catalog)
                $clone = (($catalog.assets[0] | ConvertTo-Json -Depth 20) | ConvertFrom-Json -Depth 20 -DateKind String)
                $catalog.assets = @($catalog.assets) + @($clone)
                $catalog.asset_count = @($catalog.assets).Count
            } },
        [ordered]@{ name = "wrong-asset-count"; code = "catalog-schema"; mutate = { param($catalog) $catalog.asset_count = 999 } },
        [ordered]@{ name = "wrong-hash"; code = "catalog-schema"; mutate = { param($catalog) $catalog.assets[0].content_hash = "sha256:not-a-hash" } },
        [ordered]@{ name = "wrong-type"; code = "catalog-schema"; mutate = { param($catalog) $catalog.assets[0].type = 7 } },
        [ordered]@{ name = "wrong-list"; code = "catalog-schema"; mutate = { param($catalog) $catalog.assets[0].keywords = ('[["nested"]]' | ConvertFrom-Json -Depth 20 -NoEnumerate) } },
        [ordered]@{ name = "wrong-git-shape"; code = "catalog-schema"; mutate = {
                param($catalog)
                $work = @($catalog.assets | Where-Object type -eq "work")[0]
                $work | Add-Member -NotePropertyName "git" -NotePropertyValue @("not-an-object") -Force
            } },
        [ordered]@{ name = "wrong-path"; code = "catalog-path"; mutate = { param($catalog) $catalog.assets[0].path = "../outside.md" } },
        [ordered]@{ name = "object-as-assets"; code = "catalog-schema"; mutate = { param($catalog) $catalog.assets = $catalog.assets[0] } },
        [ordered]@{ name = "nested-assets"; code = "catalog-schema"; mutate = {
                param($catalog)
                $assetJson = $catalog.assets[0] | ConvertTo-Json -Depth 20 -Compress
                $catalog.assets = (("[[{0}]]" -f $assetJson) | ConvertFrom-Json -Depth 20 -NoEnumerate)
                $catalog.asset_count = 1
            } }
    )
    foreach ($case in $shapeCases) {
        Write-Utf8 -Path $catalogPath -Text $baselineText
        $catalog = $baselineText | ConvertFrom-Json -Depth 50 -DateKind String -NoEnumerate
        $mutator = $case.mutate
        & $mutator $catalog
        Write-Utf8 -Path $catalogPath -Text ($catalog | ConvertTo-Json -Depth 50)
        $invalidBytesBeforeCheck = [System.IO.File]::ReadAllText($catalogPath, [Text.UTF8Encoding]::new($false, $true))
        $projectBeforeCheck = Get-ProjectFingerprint -ProjectRoot $project
        $canonicalBeforeCheck = Get-CanonicalSourceFingerprint -ProjectRoot $project
        $check = Invoke-Workspace -Operation check -ProjectRoot $project
        Assert-Condition ($check.payload.status -ceq "FAIL" -and @($check.payload.findings | Where-Object code -eq $case.code).Count -ge 1) ("Shape-invalid check finding was missing: {0}" -f $case.name)
        Assert-Condition ($invalidBytesBeforeCheck -ceq [System.IO.File]::ReadAllText($catalogPath, [Text.UTF8Encoding]::new($false, $true))) ("Check rewrote shape-invalid Catalog bytes: {0}" -f $case.name)
        Assert-Condition ($projectBeforeCheck -ceq (Get-ProjectFingerprint -ProjectRoot $project) -and $canonicalBeforeCheck -ceq (Get-CanonicalSourceFingerprint -ProjectRoot $project)) ("Check changed project state for shape-invalid Catalog: {0}" -f $case.name)

        $beforeRebuild = Get-ProjectFileMap -ProjectRoot $project -ExcludeGit
        $rebuilt = Invoke-Workspace -Operation discover -ProjectRoot $project
        $afterRebuild = Get-ProjectFileMap -ProjectRoot $project -ExcludeGit
        Assert-Condition ($rebuilt.payload.status -ceq "PASS" -and $rebuilt.payload.catalog.action -ceq "written" -and $rebuilt.payload.catalog.reason -ceq "schema_invalid") ("Discover reused or failed to safely rebuild shape-invalid Catalog: {0}" -f $case.name)
        Assert-Condition (((Get-ChangedProjectPaths -Before $beforeRebuild -After $afterRebuild) -join "`n") -ceq ".agents/.cache/catalog.json") ("Shape-invalid rebuild wrote outside Catalog cache: {0}" -f $case.name)
    }
    Add-CheckResult -Name "catalog-shape-invalid" -Status "PASS" -Detail ("{0} parseable contract-invalid Catalog cases failed check read-only and forced discover rebuilds." -f $shapeCases.Count)
}
catch { Add-CheckResult -Name "catalog-shape-invalid" -Status "FAIL" -Detail (Get-SafeDetail $_.Exception.Message) }

try {
    $project = New-FixtureProject -Name "broken-canonical-references"
    Set-ValidWorkRevision -ProjectRoot $project
    Set-SpecReferences -ProjectRoot $project -RelatedWork @("missing-work", "fixture-context", "fixture-work-item", "fixture-work-item") -Supersedes @("fixture-spec", "fixture-work-item")
    $discover = Invoke-Workspace -Operation discover -ProjectRoot $project
    Assert-Condition ($discover.payload.status -ceq "PASS" -and $discover.payload.catalog.action -ceq "written") "Broken-reference fixture could not build its disposable Catalog."
    $catalogPath = Join-Path $project ".agents/.cache/catalog.json"
    $canonicalBeforeCheck = Get-CanonicalSourceFingerprint -ProjectRoot $project
    $catalogBeforeCheck = Get-FileFingerprintOrMissing -Path $catalogPath
    $projectBeforeCheck = Get-ProjectFingerprint -ProjectRoot $project
    $check = Invoke-Workspace -Operation check -ProjectRoot $project
    foreach ($code in @("reference-missing", "reference-wrong-type", "reference-self", "reference-duplicate")) {
        Assert-Condition (@($check.payload.findings | Where-Object code -eq $code).Count -ge 1) ("Broken-reference finding was missing: {0}" -f $code)
    }
    $referenceStates = @($check.payload.references | ForEach-Object { [string]$_.state } | Sort-Object -Unique)
    foreach ($state in @("resolved", "missing", "wrong_type", "self_reference", "duplicate")) {
        Assert-Condition ($referenceStates -contains $state) ("Broken-reference state was missing: {0}" -f $state)
    }
    $actualReferenceMatrix = @($check.payload.references | ForEach-Object {
            "{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f $_.path, $_.field, $_.ordinal, $_.target_id, $_.expected_type, $_.state, (@($_.finding_codes) -join ",")
        })
    $expectedReferenceMatrix = @(
        "docs/specs/fixture-spec/spec.md|related_work|0|missing-work|work|missing|reference-missing",
        "docs/specs/fixture-spec/spec.md|related_work|1|fixture-context|work|wrong_type|reference-wrong-type",
        "docs/specs/fixture-spec/spec.md|related_work|2|fixture-work-item|work|resolved|",
        "docs/specs/fixture-spec/spec.md|related_work|3|fixture-work-item|work|duplicate|reference-duplicate",
        "docs/specs/fixture-spec/spec.md|supersedes|0|fixture-spec|spec|self_reference|reference-self",
        "docs/specs/fixture-spec/spec.md|supersedes|1|fixture-work-item|spec|wrong_type|reference-wrong-type"
    )
    Assert-Condition (($actualReferenceMatrix -join "`n") -ceq ($expectedReferenceMatrix -join "`n")) "Canonical reference output path, field, ordinal, target, type, state, or finding order drifted."
    $repeatCheck = Invoke-Workspace -Operation check -ProjectRoot $project
    $referenceFindings = @($check.payload.findings | Where-Object { [string]$_.code -like "reference-*" })
    $repeatReferenceFindings = @($repeatCheck.payload.findings | Where-Object { [string]$_.code -like "reference-*" })
    Assert-Condition (($check.payload.references | ConvertTo-Json -Depth 20 -Compress) -ceq ($repeatCheck.payload.references | ConvertTo-Json -Depth 20 -Compress) -and ($referenceFindings | ConvertTo-Json -Depth 20 -Compress) -ceq ($repeatReferenceFindings | ConvertTo-Json -Depth 20 -Compress)) "Canonical reference findings or output changed across identical read-only checks."
    Assert-Condition ($check.payload.status -ceq "FAIL" -and [bool]$check.payload.read_only) "Broken canonical references did not fail read-only check."
    Assert-Condition ($canonicalBeforeCheck -ceq (Get-CanonicalSourceFingerprint -ProjectRoot $project) -and $catalogBeforeCheck -ceq (Get-FileFingerprintOrMissing -Path $catalogPath) -and $projectBeforeCheck -ceq (Get-ProjectFingerprint -ProjectRoot $project)) "Broken-reference check repaired or rewrote project state."
    Add-CheckResult -Name "broken-canonical-references" -Status "PASS" -Detail "Missing, wrong-type, self, duplicate, and resolved canonical IDs returned stable read-only findings and states."
}
catch { Add-CheckResult -Name "broken-canonical-references" -Status "FAIL" -Detail (Get-SafeDetail $_.Exception.Message) }

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
    $noGitProject = New-FixtureProject -Name "git-unavailable-anchor"
    New-Item -ItemType Directory -Path (Join-Path $noGitProject "fixture-worktree") -Force | Out-Null
    Write-Utf8 -Path (Join-Path $noGitProject "fixture-worktree/.keep") -Text "fixture`n"
    Set-WorkGitAnchor -ProjectRoot $noGitProject -Branch "fixture" -LastVerifiedCommit ("a" * 40)
    $noGit = Invoke-Workspace -Operation check -ProjectRoot $noGitProject
    Assert-Condition ($noGit.payload.git.state -ceq "unavailable" -and @($noGit.payload.findings | Where-Object code -eq "git-unavailable").Count -eq 1) "No-Git fixture did not degrade with a stable warning."
    Assert-Condition (@($noGit.payload.anchors | Where-Object { $_.commit_presence -eq "unknown" -and $_.commit_state -eq "git_unavailable" -and $_.worktree_present -eq $true -and $_.worktree_state -eq "present" }).Count -eq 1) "Git-unavailable anchor did not preserve public-safe worktree/commit states."
    $noGitDiscover = Invoke-Workspace -Operation discover -ProjectRoot $noGitProject -Query "fixture work item"
    Assert-Condition ($noGitDiscover.payload.status -ceq "PASS" -and $noGitDiscover.payload.git.state -ceq "unavailable" -and @($noGitDiscover.payload.results | Where-Object id -eq "fixture-work-item").Count -eq 1) "No-Git discover did not remain filesystem-based and usable."

    $project = New-FixtureProject -Name "git-anchors"
    New-Item -ItemType Directory -Path (Join-Path $project "fixture-worktree") -Force | Out-Null
    Write-Utf8 -Path (Join-Path $project "fixture-worktree/.keep") -Text "fixture`n"
    & git -C $project init --initial-branch=fixture 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { & git -C $project init 2>&1 | Out-Null; & git -C $project branch -M fixture 2>&1 | Out-Null }
    Assert-Condition ($LASTEXITCODE -eq 0) "Git anchor fixture initialization failed."
    & git -C $project config user.name "fixture" 2>&1 | Out-Null
    & git -C $project config user.email "fixture@example.invalid" 2>&1 | Out-Null
    $branch = (& git -C $project symbolic-ref --short HEAD).Trim()
    Set-WorkGitAnchor -ProjectRoot $project -Branch $branch
    & git -C $project add . 2>&1 | Out-Null
    & git -C $project commit -m "fixture base" 2>&1 | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "Git anchor base commit failed."
    $reachableCommit = (& git -C $project rev-parse HEAD).Trim()
    Set-WorkGitAnchor -ProjectRoot $project -Branch $branch -LastVerifiedCommit $reachableCommit
    & git -C $project add .agents/work/fixture-work-item.md 2>&1 | Out-Null
    & git -C $project commit -m "fixture reachable anchor" 2>&1 | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "Git reachable anchor commit failed."
    Add-Content -LiteralPath (Join-Path $project ".git/info/exclude") -Value ".agents/.cache/" -Encoding utf8

    $matched = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "fixture work item"
    $catalogPath = Join-Path $project ".agents/.cache/catalog.json"
    $projectBeforeCheck = Get-ProjectFingerprint -ProjectRoot $project
    $canonicalBeforeCheck = Get-CanonicalSourceFingerprint -ProjectRoot $project
    $catalogBeforeCheck = Get-FileFingerprintOrMissing -Path $catalogPath
    $branchBeforeCheck = Get-GitFingerprint -ProjectRoot $project
    $worktreeBeforeCheck = Get-WorktreeFingerprint -ProjectRoot $project
    $matchedCheck = Invoke-Workspace -Operation check -ProjectRoot $project
    Assert-Condition ($matchedCheck.payload.git.state -ceq "available" -and @($matchedCheck.payload.anchors | Where-Object { $_.branch_state -eq "branch_match" -and $_.commit_presence -eq "existing" -and $_.commit_state -eq "reachable" -and $_.worktree_present -eq $true -and $_.worktree_state -eq "present" }).Count -eq 1) "Matching reachable Git anchor was not reported."
    Assert-Condition ($projectBeforeCheck -ceq (Get-ProjectFingerprint -ProjectRoot $project) -and $canonicalBeforeCheck -ceq (Get-CanonicalSourceFingerprint -ProjectRoot $project) -and $catalogBeforeCheck -ceq (Get-FileFingerprintOrMissing -Path $catalogPath) -and $branchBeforeCheck -ceq (Get-GitFingerprint -ProjectRoot $project) -and $worktreeBeforeCheck -ceq (Get-WorktreeFingerprint -ProjectRoot $project)) "Check changed project, Catalog, branch, or worktree fingerprints."
    Assert-Condition (-not $matchedCheck.text.Contains($project, [StringComparison]::OrdinalIgnoreCase)) "Git anchor check emitted an absolute fixture path."

    & git -C $project checkout -b fixture-unreachable 2>&1 | Out-Null
    Write-Utf8 -Path (Join-Path $project "side.txt") -Text "unreachable fixture`n"
    & git -C $project add side.txt 2>&1 | Out-Null
    & git -C $project commit -m "fixture unreachable commit" 2>&1 | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "Existing-unreachable fixture commit failed."
    $unreachableCommit = (& git -C $project rev-parse HEAD).Trim()
    & git -C $project checkout $branch 2>&1 | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "Could not restore the fixture branch."
    Set-WorkGitAnchor -ProjectRoot $project -Branch $branch -LastVerifiedCommit $unreachableCommit
    & git -C $project add .agents/work/fixture-work-item.md 2>&1 | Out-Null
    & git -C $project commit -m "fixture existing unreachable anchor" 2>&1 | Out-Null
    $unreachable = Invoke-Workspace -Operation check -ProjectRoot $project
    Assert-Condition (@($unreachable.payload.anchors | Where-Object { $_.commit_presence -eq "existing" -and $_.commit_state -eq "unreachable" }).Count -eq 1 -and @($unreachable.payload.findings | Where-Object code -eq "git-anchor-unreachable").Count -eq 1) "Existing-but-unreachable anchor was not distinguished."

    Set-WorkGitAnchor -ProjectRoot $project -Branch "other-branch" -LastVerifiedCommit $unreachableCommit
    $mismatch = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "fixture work item"
    $mismatchCheck = Invoke-Workspace -Operation check -ProjectRoot $project
    Assert-Condition (@($mismatchCheck.payload.anchors | Where-Object { $_.branch_state -eq "branch_mismatch" -and $_.commit_presence -eq "existing" -and $_.commit_state -eq "unreachable" }).Count -eq 1) "Branch mismatch and existing-unreachable anchor were not reported together."
    Assert-Condition (@($mismatch.payload.findings | Where-Object code -eq "branch_mismatch").Count -ge 1) "Discover did not expose branch_mismatch."
    Assert-Condition ([bool]$mismatchCheck.payload.git.dirty -and @($mismatchCheck.payload.findings | Where-Object code -eq "git-dirty").Count -eq 1) "Dirty Git worktree state was not preserved from the original degradation matrix."
    $currentOnly = Invoke-Workspace -Operation discover -ProjectRoot $project -Query "fixture work item" -CurrentBranchOnly
    Assert-Condition ([int]$currentOnly.payload.result_count -eq 0) "current-branch-only did not exclude mismatched anchor."

    $missingCommit = (("missing-{0}" -f ([guid]::NewGuid().ToString("N"))) | & git -C $project hash-object --stdin).Trim()
    & git -C $project cat-file -e ($missingCommit + "^{commit}") 2>$null
    Assert-Condition ($LASTEXITCODE -ne 0) "Missing-commit fixture unexpectedly exists in the repository."
    Set-WorkGitAnchor -ProjectRoot $project -Branch $branch -LastVerifiedCommit $missingCommit
    $missing = Invoke-Workspace -Operation check -ProjectRoot $project
    Assert-Condition (@($missing.payload.anchors | Where-Object { $_.commit_presence -eq "missing" -and $_.commit_state -eq "missing" }).Count -eq 1 -and @($missing.payload.findings | Where-Object code -eq "git-anchor-missing").Count -eq 1) "Non-existing anchor was not distinguished from unreachable history."
    Set-WorkGitAnchor -ProjectRoot $project -Branch $branch -Worktree "missing-worktree" -LastVerifiedCommit $reachableCommit
    $missingWorktree = Invoke-Workspace -Operation check -ProjectRoot $project
    Assert-Condition (@($missingWorktree.payload.anchors | Where-Object { $_.worktree_present -eq $false -and $_.worktree_state -eq "missing" }).Count -eq 1 -and @($missingWorktree.payload.findings | Where-Object code -eq "git-worktree-missing").Count -eq 1) "Missing Git worktree anchor was not exposed as presence/state."

    $seed = New-FixtureProject -Name "git-shallow-seed"
    New-Item -ItemType Directory -Path (Join-Path $seed "fixture-worktree") -Force | Out-Null
    Write-Utf8 -Path (Join-Path $seed "fixture-worktree/.keep") -Text "fixture`n"
    & git -C $seed init --initial-branch=fixture 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { & git -C $seed init 2>&1 | Out-Null; & git -C $seed branch -M fixture 2>&1 | Out-Null }
    & git -C $seed config user.name "fixture" 2>&1 | Out-Null
    & git -C $seed config user.email "fixture@example.invalid" 2>&1 | Out-Null
    $seedBranch = (& git -C $seed symbolic-ref --short HEAD).Trim()
    Set-WorkGitAnchor -ProjectRoot $seed -Branch $seedBranch
    & git -C $seed add . 2>&1 | Out-Null
    & git -C $seed commit -m "shallow base" 2>&1 | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "Shallow seed base commit failed."
    $shallowAnchorCommit = (& git -C $seed rev-parse HEAD).Trim()
    Set-WorkGitAnchor -ProjectRoot $seed -Branch $seedBranch -LastVerifiedCommit $shallowAnchorCommit
    & git -C $seed add .agents/work/fixture-work-item.md 2>&1 | Out-Null
    & git -C $seed commit -m "shallow head" 2>&1 | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "Shallow seed head commit failed."
    $shallowProject = Join-Path $scratchRootFull "git-shallow-clone"
    & git clone --depth 1 --no-local $seed $shallowProject 2>&1 | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "Real depth-1 fixture clone failed."
    $shallow = Invoke-Workspace -Operation check -ProjectRoot $shallowProject
    Assert-Condition ([bool]$shallow.payload.git.shallow -and @($shallow.payload.anchors | Where-Object { $_.commit_presence -eq "unknown" -and $_.commit_state -eq "shallow_unknown" }).Count -eq 1 -and @($shallow.payload.findings | Where-Object code -eq "git-shallow").Count -eq 1 -and @($shallow.payload.findings | Where-Object code -eq "git-anchor-shallow-unknown").Count -eq 1) "Shallow history did not degrade anchor existence/reachability to unknown."

    Add-CheckResult -Name "git-anchors-and-degradation" -Status "PASS" -Detail "Reachable, existing-unreachable, missing, shallow-unknown, Git-unavailable, branch policy, and worktree presence/state passed."
}
catch { Add-CheckResult -Name "git-anchors-and-degradation" -Status "FAIL" -Detail (Get-SafeDetail $_.Exception.Message) }

try {
    $unsafeGlossaryPath = [string]::Concat([char]67, [char]58, [char]92, "Users", [char]92, "private")
    $invalidCases = [ordered]@{
        "unknown-relation" = @("schema: agent-ecosystem/glossary/v1", "terms:", "  - canonical: telemetry", "    aliases:", "    symbols:", "    relations:", "      - not-declared", "    evidence:", "      - public fixture")
        "relation-cycle" = @("schema: agent-ecosystem/glossary/v1", "terms:", "  - canonical: alpha", "    aliases:", "    symbols:", "    relations:", "      - beta", "    evidence:", "      - public fixture", "  - canonical: beta", "    aliases:", "    symbols:", "    relations:", "      - alpha", "    evidence:", "      - public fixture")
        "alias-conflict" = @("schema: agent-ecosystem/glossary/v1", "terms:", "  - canonical: alpha", "    aliases:", "      - same-name", "    symbols:", "    relations:", "    evidence:", "      - public fixture", "  - canonical: beta", "    aliases:", "      - same-name", "    symbols:", "    relations:", "    evidence:", "      - public fixture")
        "malicious-value" = @("schema: agent-ecosystem/glossary/v1", "terms:", ("  - canonical: {0}" -f $unsafeGlossaryPath), "    aliases:", "    symbols:", "    relations:", "    evidence:", "      - public fixture")
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
$allChecksPassed = ($failures.Count -eq 0)
$summary = [ordered]@{
    schema_version = 1
    status = if ($allChecksPassed) { "PASS" } else { "FAIL" }
    scenario_count = $results.Count
    pass = @($results.ToArray() | Where-Object status -eq "PASS").Count
    fail = $failures.Count
    canonical_sources_read_only = $allChecksPassed
    check_read_only = $allChecksPassed
    discover_writes_only_catalog_cache = $allChecksPassed
    cases = @($results.ToArray())
}

if ($Json.IsPresent) { $summary | ConvertTo-Json -Depth 20 }
else {
    Write-Output ("project-workspace discovery fixtures: PASS={0} FAIL={1}" -f $summary.pass, $summary.fail)
    foreach ($failure in $failures) { Write-Output ("[FAIL] {0}: {1}" -f $failure.name, $failure.detail) }
}

if ($summary.status -ne "PASS") { exit 1 }
exit 0
