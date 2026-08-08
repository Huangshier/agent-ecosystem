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
$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { [IO.Path]::GetFullPath($defaultRepositoryRoot) } else { [IO.Path]::GetFullPath($RepositoryRoot) }
. (Join-Path $repoRoot "scripts/validation/powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime

if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([IO.Path]::GetTempPath()) ("agent-ecosystem-workspace-continuity-{0}" -f ([guid]::NewGuid().ToString("N")))
}
$scratchRootFull = [IO.Path]::GetFullPath($ScratchRoot)
$runRoot = Join-Path $scratchRootFull ("run-{0}" -f ([guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

$workspacePath = Join-Path $repoRoot "skills/project-workspace/scripts/project-workspace.ps1"
$parserPath = Join-Path $repoRoot "skills/project-workspace/scripts/read-project-assets.ps1"
$fixtureContractPath = Join-Path $scriptDir "project-workspace-continuity-fixtures/cases.json"
$fixtureContract = Get-Content -LiteralPath $fixtureContractPath -Raw | ConvertFrom-Json -Depth 30
$results = New-Object 'System.Collections.Generic.List[object]'
$script:classificationCounts = [ordered]@{ exact = 0; advanced = 0; dirty = 0; diverged = 0 }
$script:degradedCount = 0
$script:onlyFrozenClassifications = $true
$script:conflictFieldsObserved = $false
$script:changedFieldsOrderObserved = $false
$script:staleByteIdentical = $false
$script:noAutomaticRetry = $false
$script:recoveryReadOnly = $false
$script:checkReadOnly = $false
$script:catalogDiscoverOnly = $false
$script:canonicalWorkOnly = $false

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Get-SafeDetail {
    param([AllowEmptyString()][string]$Message)

    $safe = [string]$Message
    foreach ($path in @($runRoot, $scratchRootFull, $repoRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) { $safe = $safe.Replace($path, "<scratch>", [StringComparison]::OrdinalIgnoreCase) }
    }
    return $safe
}

function Invoke-Scenario {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    try {
        & $Action
        [void]$results.Add([ordered]@{ name = $Name; status = "PASS"; detail = "Deterministic Slice C assertions passed." })
    }
    catch {
        [void]$results.Add([ordered]@{ name = $Name; status = "FAIL"; detail = Get-SafeDetail -Message $_.Exception.Message })
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function New-FixtureProject {
    param([Parameter(Mandatory = $true)][string]$Name)

    $root = Join-Path $runRoot $Name
    foreach ($path in @(".agents/work", ".agents/context", ".agents/procedures", "docs/specs")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $root $path) | Out-Null
    }
    return $root
}

function Get-FileHashText {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "missing" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StateFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    $records = New-Object 'System.Collections.Generic.List[string]'
    foreach ($directory in @(Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($Root, $directory.FullName).Replace('\', '/')
        # Directory timestamps can be lazily materialized by the filesystem
        # immediately after fixture setup. The exact directory set plus every
        # file's bytes, size, and mtime still detects persistent writes.
        [void]$records.Add(("D|{0}" -f $relative))
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
        [void]$records.Add(("F|{0}|{1}|{2}|{3}" -f $relative, $file.Length, $file.LastWriteTimeUtc.Ticks, (Get-FileHashText -Path $file.FullName)))
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($records.ToArray() -join "`n")
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bytes))).Replace('-', '').ToLowerInvariant()
}

function Get-ReferenceRevision {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = @($text -split "`n")
    $output = New-Object 'System.Collections.Generic.List[string]'
    $frontMatter = ($lines.Count -gt 0 -and [string]$lines[0] -ceq "---")
    $closed = $false
    $removed = $false
    foreach ($line in $lines) {
        if ($frontMatter -and -not $closed -and [string]$line -ceq "---" -and $output.Count -gt 0) { $closed = $true }
        if ($frontMatter -and -not $closed -and -not $removed -and [string]$line -match '^revision:') { $removed = $true; continue }
        [void]$output.Add([string]$line)
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($output.ToArray() -join "`n")
    return "sha256:" + ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bytes))).Replace('-', '').ToLowerInvariant()
}

function Set-WorkTextWithValidRevision {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    Assert-Condition -Condition ([regex]::Matches($normalized, '(?m)^revision:').Count -eq 1) -Message "Fixture Work must contain exactly one revision field."
    $placeholder = [regex]::Replace($normalized, '(?m)^revision:.*$', ('revision: sha256:' + ('0' * 64)), 1)
    Write-Utf8NoBom -Path $Path -Text $placeholder
    $revision = Get-ReferenceRevision -Path $Path
    Write-Utf8NoBom -Path $Path -Text ([regex]::Replace($placeholder, '(?m)^revision:.*$', ("revision: {0}" -f $revision), 1))
}

function Set-WorkBody {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Body
    )

    $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $match = [regex]::Match($text, '(?s)\A(---\n.*?\n---)(?:\n.*)?\z')
    Assert-Condition -Condition $match.Success -Message "Fixture Work frontmatter could not be isolated."
    Set-WorkTextWithValidRevision -Path $Path -Text ($match.Groups[1].Value + "`n`n" + $Body.TrimEnd() + "`n")
}

function Test-PublicSafeOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    $privateOverlayToken = "agent-ecosystem" + "-private"
    $hiddenDirectory = ".sec" + "rets"
    $keyMarker = "PRIVATE" + " KEY"
    $unsafePattern = '(?i)(' + [regex]::Escape($privateOverlayToken) + '|' + [regex]::Escape($hiddenDirectory) + '[/\\]|BEGIN (RSA |EC |OPENSSH )?' + $keyMarker + ')'
    return (-not $Text.Contains($ProjectRoot, [StringComparison]::OrdinalIgnoreCase) -and
        -not $Text.Contains($runRoot, [StringComparison]::OrdinalIgnoreCase) -and
        -not $Text.Contains($repoRoot, [StringComparison]::OrdinalIgnoreCase) -and
        $Text -notmatch $unsafePattern)
}

function Invoke-Workspace {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("discover", "check", "create-work", "checkpoint", "set-status", "complete", "recover-work")][string]$Operation,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [System.Collections.IDictionary]$Parameters = [ordered]@{}
    )

    $invocation = [ordered]@{ Operation = $Operation; ProjectRoot = $ProjectRoot; Json = $true; NoExit = $true }
    foreach ($entry in $Parameters.GetEnumerator()) {
        if ($null -eq $entry.Value) { continue }
        if ($entry.Value -is [bool]) {
            if ([bool]$entry.Value) { $invocation[[string]$entry.Key] = $true }
            continue
        }
        $values = @($entry.Value)
        if ($values.Count -eq 0) { continue }
        $invocation[[string]$entry.Key] = if ($entry.Value -is [System.Array]) { @($entry.Value) } else { $entry.Value }
    }
    $output = @(& $workspacePath @invocation 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = [int]$global:LASTEXITCODE
    $text = $output -join "`n"
    Assert-Condition -Condition (Test-PublicSafeOutput -Text $text -ProjectRoot $ProjectRoot) -Message ("{0} emitted non-public-safe material." -f $Operation)
    try { $payload = $text | ConvertFrom-Json -Depth 50 -ErrorAction Stop }
    catch { throw ("{0} did not return structured JSON." -f $Operation) }
    return [ordered]@{ exit_code = $exitCode; payload = $payload; text = $text }
}

function Invoke-Parser {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$AssetPath
    )

    $output = @(& $parserPath -ProjectRoot $ProjectRoot -AssetPath $AssetPath -IncludeMetadata -Json -NoExit 2>&1 | ForEach-Object { [string]$_ })
    $text = $output -join "`n"
    Assert-Condition -Condition (Test-PublicSafeOutput -Text $text -ProjectRoot $ProjectRoot) -Message "Canonical parser emitted non-public-safe material."
    try { return $text | ConvertFrom-Json -Depth 50 -ErrorAction Stop }
    catch { throw "Canonical parser did not return JSON." }
}

function Get-WorkState {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Id
    )

    $relative = ".agents/work/{0}.md" -f $Id
    $parsed = Invoke-Parser -ProjectRoot $ProjectRoot -AssetPath $relative
    Assert-Condition -Condition ([string]$parsed.status -ceq "PASS" -and [int]$parsed.asset_count -eq 1 -and [bool]$parsed.assets[0].valid) -Message "Canonical parser rejected the Work item."
    return [ordered]@{ path = Join-Path $ProjectRoot $relative; relative_path = $relative; metadata = $parsed.assets[0].metadata; parser = $parsed }
}

function Assert-RevisionValid {
    param([Parameter(Mandatory = $true)][object]$State)

    Assert-Condition -Condition ([string]$State.metadata.revision -ceq (Get-ReferenceRevision -Path $State.path)) -Message "Persisted revision does not match normalized Work content."
}

function Assert-Success {
    param(
        [Parameter(Mandatory = $true)][object]$Run,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    Assert-Condition -Condition ([int]$Run.exit_code -eq 0 -and [string]$Run.payload.status -ceq "PASS" -and [string]$Run.payload.operation -ceq $Operation) -Message ("{0} did not return PASS." -f $Operation)
}

function Assert-FailClosed {
    param(
        [Parameter(Mandatory = $true)][object]$Run,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    Assert-Condition -Condition ([int]$Run.exit_code -ne 0 -and [string]$Run.payload.status -cne "PASS" -and [string]$Run.payload.operation -ceq $Operation) -Message ("{0} did not fail closed." -f $Operation)
}

function New-Work {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Title = "Fixture continuity work",
        [string]$Summary = "Track a bounded public fixture change.",
        [string]$Next = "Run the next deterministic fixture step.",
        [string]$Status = "active",
        [string]$ContinuityReason = "unfinished",
        [string]$Updated = "2026-08-07T00:00:00Z",
        [string]$GitBranch = "",
        [string]$GitWorktree = "",
        [string]$GitLastVerifiedCommit = ""
    )

    $parameters = [ordered]@{ Id = $Id; Title = $Title; Summary = $Summary; Next = $Next; Status = @($Status); ContinuityReason = $ContinuityReason; Updated = $Updated }
    if ($GitBranch) { $parameters.GitBranch = $GitBranch }
    if ($GitWorktree) { $parameters.GitWorktree = $GitWorktree }
    if ($GitLastVerifiedCommit) { $parameters.GitLastVerifiedCommit = $GitLastVerifiedCommit }
    $run = Invoke-Workspace -Operation create-work -ProjectRoot $ProjectRoot -Parameters $parameters
    Assert-Success -Run $run -Operation "create-work"
    $state = Get-WorkState -ProjectRoot $ProjectRoot -Id $Id
    Assert-RevisionValid -State $state
    return [ordered]@{ run = $run; state = $state }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = @(& git -C $ProjectRoot @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = [int]$LASTEXITCODE
    if (-not $AllowFailure.IsPresent -and $exitCode -ne 0) { throw ("Git fixture command failed: {0}" -f ($Arguments -join " ")) }
    return [ordered]@{ exit_code = $exitCode; text = $output -join "`n" }
}

function Initialize-GitFixture {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $init = Invoke-Git -ProjectRoot $ProjectRoot -Arguments @("init", "--initial-branch=fixture") -AllowFailure
    if ($init.exit_code -ne 0) {
        Invoke-Git -ProjectRoot $ProjectRoot -Arguments @("init") | Out-Null
        Invoke-Git -ProjectRoot $ProjectRoot -Arguments @("branch", "-M", "fixture") | Out-Null
    }
    # NOTE: Deep Windows scratch roots can exceed MAX_PATH while Git writes .git/objects.
    Invoke-Git -ProjectRoot $ProjectRoot -Arguments @("config", "core.longpaths", "true") | Out-Null
    Invoke-Git -ProjectRoot $ProjectRoot -Arguments @("config", "user.name", "continuity-fixture") | Out-Null
    Invoke-Git -ProjectRoot $ProjectRoot -Arguments @("config", "user.email", "continuity-fixture@example.invalid") | Out-Null
    Write-Utf8NoBom -Path (Join-Path $ProjectRoot ".gitignore") -Text ".agents/work/`n.agents/.cache/`n"
    Write-Utf8NoBom -Path (Join-Path $ProjectRoot "tracked.txt") -Text "fixture base`n"
    Invoke-Git -ProjectRoot $ProjectRoot -Arguments @("add", ".gitignore", "tracked.txt") | Out-Null
    Invoke-Git -ProjectRoot $ProjectRoot -Arguments @("commit", "-m", "fixture base") | Out-Null
    return [ordered]@{
        branch = (Invoke-Git -ProjectRoot $ProjectRoot -Arguments @("symbolic-ref", "--short", "HEAD")).text.Trim()
        head = (Invoke-Git -ProjectRoot $ProjectRoot -Arguments @("rev-parse", "HEAD")).text.Trim()
    }
}

function New-RecoveryFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Summary = "Work summary is descriptive and not recovery authority."
    )

    $project = New-FixtureProject -Name $Name
    $git = Initialize-GitFixture -ProjectRoot $project
    $work = New-Work -ProjectRoot $project -Id "recovery-work" -Summary $Summary -GitBranch $git.branch -GitLastVerifiedCommit $git.head
    return [ordered]@{ project = $project; git = $git; work = $work }
}

function Record-RecoveryEvidence {
    param([Parameter(Mandatory = $true)][object]$Run)

    $classification = $Run.payload.classification
    if ($null -eq $classification) {
        $script:degradedCount++
        Assert-Condition -Condition ([bool]$Run.payload.degraded -and -not [string]::IsNullOrWhiteSpace([string]$Run.payload.reason_code) -and [string]$Run.payload.reason_code -cne "none") -Message "Degraded recovery omitted its stable reason code."
        return
    }
    $value = [string]$classification
    if (-not (@($fixtureContract.recovery_classifications) -ccontains $value)) {
        $script:onlyFrozenClassifications = $false
        throw "Recovery emitted a classification outside the frozen four-value set."
    }
    $script:classificationCounts[$value] = [int]$script:classificationCounts[$value] + 1
    Assert-Condition -Condition (-not [bool]$Run.payload.degraded) -Message "A classified recovery was incorrectly marked degraded."
}

function Invoke-Recovery {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$Id = "recovery-work"
    )

    $before = Get-StateFingerprint -Root $ProjectRoot
    $run = Invoke-Workspace -Operation recover-work -ProjectRoot $ProjectRoot -Parameters ([ordered]@{ Id = $Id })
    Assert-Success -Run $run -Operation "recover-work"
    $after = Get-StateFingerprint -Root $ProjectRoot
    Assert-Condition -Condition ($before -ceq $after -and [bool]$run.payload.read_only) -Message "recover-work changed project state."
    $script:recoveryReadOnly = $true
    Record-RecoveryEvidence -Run $run
    return $run
}

function Assert-NoLifecycleArtifacts {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $unsafePaths = @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Force | ForEach-Object {
            [IO.Path]::GetRelativePath($ProjectRoot, $_.FullName).Replace('\', '/')
        } | Where-Object { $_ -match '(?i)(^|/)(?:archive|history|tombstone)(?:/|$)|(^|/)completed(?:[./-]|$)' })
    Assert-Condition -Condition ($unsafePaths.Count -eq 0) -Message "Completion created an archive, history, tombstone, or completed artifact."
}

function Assert-CheckReadOnly {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $before = Get-StateFingerprint -Root $ProjectRoot
    $run = Invoke-Workspace -Operation check -ProjectRoot $ProjectRoot
    $after = Get-StateFingerprint -Root $ProjectRoot
    Assert-Condition -Condition ($before -ceq $after -and [bool]$run.payload.read_only) -Message "check changed project state."
    $script:checkReadOnly = $true
    return $run
}

$expectedScenarioNames = @($fixtureContract.scenarios | ForEach-Object { [string]$_.name })
Assert-Condition -Condition ([int]$fixtureContract.schema_version -eq 1 -and $expectedScenarioNames.Count -gt 0) -Message "Continuity fixture contract is invalid."
Assert-Condition -Condition (($expectedScenarioNames | Select-Object -Unique).Count -eq $expectedScenarioNames.Count) -Message "Continuity fixture scenario names are not unique."
Assert-Condition -Condition ((@($fixtureContract.recovery_classifications) -join ',') -ceq 'exact,advanced,dirty,diverged') -Message "Recovery classification fixture order drifted."
Assert-Condition -Condition ((@($fixtureContract.revision_conflict_fields) -join ',') -ceq 'status,expected_revision,current_revision,changed_fields,current_path') -Message "Revision conflict fixture fields drifted."

Invoke-Scenario -Name "create-canonical-work" -Action {
    $project = New-FixtureProject -Name "create-canonical"
    $created = New-Work -ProjectRoot $project -Id "canonical-work"
    $bytes = [IO.File]::ReadAllBytes($created.state.path)
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    Assert-Condition -Condition ($bytes.Length -gt 3 -and -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) -Message "create-work emitted a UTF-8 BOM."
    Assert-Condition -Condition (-not $text.Contains("`r", [StringComparison]::Ordinal)) -Message "create-work did not emit canonical LF content."
    Assert-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $project ".agents/.cache/catalog.json"))) -Message "create-work wrote Catalog."
    Assert-NoLifecycleArtifacts -ProjectRoot $project
    $script:canonicalWorkOnly = $true
}

Invoke-Scenario -Name "create-stable-id-and-duplicate" -Action {
    $project = New-FixtureProject -Name "create-duplicate"
    $created = New-Work -ProjectRoot $project -Id "stable-work-id"
    $before = Get-FileHashText -Path $created.state.path
    $duplicate = Invoke-Workspace -Operation create-work -ProjectRoot $project -Parameters ([ordered]@{
            Id = "stable-work-id"; Title = "Duplicate title"; Summary = "Duplicate writes must fail closed."; Next = "Do not overwrite."; Status = @("active"); ContinuityReason = "unfinished"; Updated = "2026-08-07T00:00:01Z"
        })
    Assert-FailClosed -Run $duplicate -Operation "create-work"
    Assert-Condition -Condition ($before -ceq (Get-FileHashText -Path $created.state.path)) -Message "Duplicate create changed the canonical Work."
    Assert-Condition -Condition (@(Get-ChildItem -LiteralPath (Join-Path $project ".agents/work") -File).Count -eq 1) -Message "Duplicate create produced another Work file."
}

Invoke-Scenario -Name "create-invalid-id-and-traversal" -Action {
    $project = New-FixtureProject -Name "create-invalid-id"
    foreach ($id in @("Bad_ID", "../escape", "bad/id", ".", "-bad", "bad-")) {
        $before = Get-StateFingerprint -Root $project
        $run = Invoke-Workspace -Operation create-work -ProjectRoot $project -Parameters ([ordered]@{
                Id = $id; Title = "Invalid ID"; Summary = "Reject unsafe or non-canonical IDs."; Next = "Leave the project unchanged."; Status = @("active"); ContinuityReason = "unfinished"; Updated = "2026-08-07T00:00:02Z"
            })
        Assert-FailClosed -Run $run -Operation "create-work"
        Assert-Condition -Condition ($before -ceq (Get-StateFingerprint -Root $project)) -Message ("Invalid ID changed project state: {0}" -f $id)
    }
    Assert-Condition -Condition (@(Get-ChildItem -LiteralPath (Join-Path $project ".agents/work") -File -Force).Count -eq 0) -Message "Invalid IDs created a canonical Work."
}

Invoke-Scenario -Name "create-continuity-reason-gate" -Action {
    $project = New-FixtureProject -Name "create-reason"
    $common = [ordered]@{ Id = "missing-reason"; Title = "Missing reason"; Summary = "A caller must declare continuity risk."; Next = "Fail closed."; Status = @("active"); Updated = "2026-08-07T00:00:03Z" }
    $missing = Invoke-Workspace -Operation create-work -ProjectRoot $project -Parameters $common
    Assert-FailClosed -Run $missing -Operation "create-work"
    $invalid = [ordered]@{}
    foreach ($key in $common.Keys) { $invalid[$key] = $common[$key] }
    $invalid.Id = "invalid-reason"
    $invalid.ContinuityReason = "routine"
    $invalidRun = Invoke-Workspace -Operation create-work -ProjectRoot $project -Parameters $invalid
    Assert-FailClosed -Run $invalidRun -Operation "create-work"
    $ordinal = 0
    foreach ($reason in @($fixtureContract.continuity_reasons)) {
        $ordinal++
        New-Work -ProjectRoot $project -Id ("reason-{0}" -f $ordinal) -ContinuityReason ([string]$reason) | Out-Null
    }
    Assert-Condition -Condition (@(Get-ChildItem -LiteralPath (Join-Path $project ".agents/work") -File).Count -eq @($fixtureContract.continuity_reasons).Count) -Message "Continuity reason allowlist drifted."
}

Invoke-Scenario -Name "checkpoint-valid-cas-and-revision" -Action {
    $project = New-FixtureProject -Name "checkpoint-cas"
    $created = New-Work -ProjectRoot $project -Id "checkpoint-work"
    $base = [string]$created.state.metadata.revision
    $run = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{
            Id = "checkpoint-work"; BaseRevision = $base; Summary = "Persist the verified checkpoint."; Next = "Continue from canonical evidence."; Verified = @("parser suite passed"); Boundary = @("no runtime cutover"); Blocker = @("none"); Updated = "2026-08-07T00:01:00Z"
        })
    Assert-Success -Run $run -Operation "checkpoint"
    $current = Get-WorkState -ProjectRoot $project -Id "checkpoint-work"
    Assert-RevisionValid -State $current
    Assert-Condition -Condition ([string]$current.metadata.revision -cne $base -and [string]$current.metadata.summary -ceq "Persist the verified checkpoint.") -Message "checkpoint did not update canonical metadata and revision."
}

Invoke-Scenario -Name "checkpoint-line-ending-normalization" -Action {
    $left = New-FixtureProject -Name "checkpoint-lf"
    $right = New-FixtureProject -Name "checkpoint-crlf"
    $leftWork = New-Work -ProjectRoot $left -Id "line-ending-work"
    $rightWork = New-Work -ProjectRoot $right -Id "line-ending-work"
    $rightText = [IO.File]::ReadAllText($rightWork.state.path, [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    Write-Utf8NoBom -Path $rightWork.state.path -Text $rightText.Replace("`n", "`r`n")
    Assert-Condition -Condition ((Get-ReferenceRevision -Path $leftWork.state.path) -ceq (Get-ReferenceRevision -Path $rightWork.state.path)) -Message "LF and CRLF fixture revisions are not equivalent."
    $parameters = [ordered]@{ Id = "line-ending-work"; BaseRevision = [string]$leftWork.state.metadata.revision; Summary = "Normalize line endings deterministically."; Verified = @("line ending check passed"); Updated = "2026-08-07T00:01:01Z" }
    $leftRun = Invoke-Workspace -Operation checkpoint -ProjectRoot $left -Parameters $parameters
    $rightRun = Invoke-Workspace -Operation checkpoint -ProjectRoot $right -Parameters $parameters
    Assert-Success -Run $leftRun -Operation "checkpoint"
    Assert-Success -Run $rightRun -Operation "checkpoint"
    $leftBytes = [IO.File]::ReadAllBytes($leftWork.state.path)
    $rightBytes = [IO.File]::ReadAllBytes($rightWork.state.path)
    Assert-Condition -Condition (([Convert]::ToHexString($leftBytes)) -ceq ([Convert]::ToHexString($rightBytes))) -Message "LF and CRLF checkpoints did not converge to identical bytes."
    $normalizedText = [Text.UTF8Encoding]::new($false, $true).GetString($rightBytes)
    Assert-Condition -Condition (-not $normalizedText.Contains("`r", [StringComparison]::Ordinal)) -Message "checkpoint persisted non-canonical line endings."
}

Invoke-Scenario -Name "checkpoint-stale-byte-identical" -Action {
    $project = New-FixtureProject -Name "checkpoint-stale"
    $created = New-Work -ProjectRoot $project -Id "stale-work"
    $stale = [string]$created.state.metadata.revision
    $advance = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{ Id = "stale-work"; BaseRevision = $stale; Summary = "Another agent advanced this Work."; Updated = "2026-08-07T00:01:02Z" })
    Assert-Success -Run $advance -Operation "checkpoint"
    $path = (Get-WorkState -ProjectRoot $project -Id "stale-work").path
    $before = Get-FileHashText -Path $path
    $conflict = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{ Id = "stale-work"; BaseRevision = $stale; Title = "Stale overwrite"; Updated = "2026-08-07T00:01:03Z" })
    Assert-Condition -Condition ([int]$conflict.exit_code -ne 0 -and [string]$conflict.payload.status -ceq "revision-conflict") -Message "Stale checkpoint did not return revision-conflict."
    Assert-Condition -Condition ($before -ceq (Get-FileHashText -Path $path)) -Message "Stale checkpoint changed canonical bytes."
    $script:staleByteIdentical = $true
}

Invoke-Scenario -Name "checkpoint-malformed-fail-closed" -Action {
    $project = New-FixtureProject -Name "checkpoint-malformed-revision"
    $created = New-Work -ProjectRoot $project -Id "malformed-work"
    $path = $created.state.path
    $declared = [string]$created.state.metadata.revision
    $text = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false, $true)).Replace("bounded public fixture", "changed public fixture")
    Write-Utf8NoBom -Path $path -Text $text
    $before = Get-FileHashText -Path $path
    $mismatch = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{ Id = "malformed-work"; BaseRevision = $declared; Summary = "Must not overwrite mismatched content."; Updated = "2026-08-07T00:01:04Z" })
    Assert-FailClosed -Run $mismatch -Operation "checkpoint"
    Assert-Condition -Condition ($before -ceq (Get-FileHashText -Path $path)) -Message "Revision-mismatched Work was rewritten."

    $duplicateProject = New-FixtureProject -Name "checkpoint-duplicate-section"
    $duplicate = New-Work -ProjectRoot $duplicateProject -Id "duplicate-section-work"
    Set-WorkBody -Path $duplicate.state.path -Body "## Verified`n`n- first`n`n## Verified`n`n- second"
    $duplicateBefore = Get-FileHashText -Path $duplicate.state.path
    $duplicateRun = Invoke-Workspace -Operation checkpoint -ProjectRoot $duplicateProject -Parameters ([ordered]@{ Id = "duplicate-section-work"; BaseRevision = (Get-WorkState -ProjectRoot $duplicateProject -Id "duplicate-section-work").metadata.revision; Verified = @("replacement"); Updated = "2026-08-07T00:01:05Z" })
    Assert-FailClosed -Run $duplicateRun -Operation "checkpoint"
    Assert-Condition -Condition ($duplicateBefore -ceq (Get-FileHashText -Path $duplicate.state.path)) -Message "Ambiguous managed sections were rewritten."
}

Invoke-Scenario -Name "checkpoint-body-preservation" -Action {
    $project = New-FixtureProject -Name "checkpoint-body"
    $created = New-Work -ProjectRoot $project -Id "body-work"
    Set-WorkBody -Path $created.state.path -Body "Human introduction remains exact.`n`n## Notes`n`nUnmanaged sentinel remains exact.`n`n## Verified`n`n- verified-old`n`n## Boundaries`n`n- boundary-old`n`n## Blockers`n`n- blocker-old"
    $base = [string](Get-WorkState -ProjectRoot $project -Id "body-work").metadata.revision
    $run = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{ Id = "body-work"; BaseRevision = $base; Verified = @("verified-new"); Boundary = @("boundary-new"); Updated = "2026-08-07T00:01:06Z" })
    Assert-Success -Run $run -Operation "checkpoint"
    $text = [IO.File]::ReadAllText($created.state.path, [Text.UTF8Encoding]::new($false, $true))
    Assert-Condition -Condition ($text.Contains("Human introduction remains exact.", [StringComparison]::Ordinal) -and $text.Contains("Unmanaged sentinel remains exact.", [StringComparison]::Ordinal)) -Message "checkpoint discarded unmanaged Work body content."
    foreach ($heading in @("Verified", "Boundaries", "Blockers")) {
        Assert-Condition -Condition ([regex]::Matches($text, ("(?m)^## {0}$" -f [regex]::Escape($heading))).Count -eq 1) -Message ("checkpoint did not preserve exactly one managed heading: {0}" -f $heading)
    }
    foreach ($value in @("verified-new", "boundary-new", "blocker-old")) { Assert-Condition -Condition $text.Contains($value, [StringComparison]::Ordinal) -Message ("checkpoint omitted an updated or unprovided managed value: {0}" -f $value) }
    foreach ($value in @("verified-old", "boundary-old")) { Assert-Condition -Condition (-not $text.Contains($value, [StringComparison]::Ordinal)) -Message ("checkpoint retained a replaced managed value: {0}" -f $value) }
}

Invoke-Scenario -Name "set-status-four-values" -Action {
    $project = New-FixtureProject -Name "status-valid"
    $created = New-Work -ProjectRoot $project -Id "status-work"
    $revision = [string]$created.state.metadata.revision
    $ordinal = 10
    foreach ($status in @($fixtureContract.work_statuses)) {
        $run = Invoke-Workspace -Operation set-status -ProjectRoot $project -Parameters ([ordered]@{ Id = "status-work"; BaseRevision = $revision; Status = @([string]$status); Updated = ("2026-08-07T00:02:{0:D2}Z" -f $ordinal) })
        Assert-Success -Run $run -Operation "set-status"
        $state = Get-WorkState -ProjectRoot $project -Id "status-work"
        Assert-RevisionValid -State $state
        Assert-Condition -Condition ([string]$state.metadata.status -ceq [string]$status -and [string]$state.metadata.revision -cne $revision) -Message ("set-status did not persist {0}." -f $status)
        $revision = [string]$state.metadata.revision
        $ordinal++
    }
    $path = (Get-WorkState -ProjectRoot $project -Id "status-work").path
    $beforeInvalid = Get-FileHashText -Path $path
    $invalid = Invoke-Workspace -Operation set-status -ProjectRoot $project -Parameters ([ordered]@{ Id = "status-work"; BaseRevision = $revision; Status = @("completed"); Updated = "2026-08-07T00:02:20Z" })
    Assert-FailClosed -Run $invalid -Operation "set-status"
    Assert-Condition -Condition ($beforeInvalid -ceq (Get-FileHashText -Path $path)) -Message "Invalid status changed canonical Work bytes."
}

Invoke-Scenario -Name "complete-confirmation-and-cas" -Action {
    $project = New-FixtureProject -Name "complete-contract"
    $created = New-Work -ProjectRoot $project -Id "complete-work"
    $base = [string]$created.state.metadata.revision
    $before = Get-FileHashText -Path $created.state.path
    $unconfirmed = Invoke-Workspace -Operation complete -ProjectRoot $project -Parameters ([ordered]@{ Id = "complete-work"; BaseRevision = $base })
    Assert-FailClosed -Run $unconfirmed -Operation "complete"
    Assert-Condition -Condition ($before -ceq (Get-FileHashText -Path $created.state.path)) -Message "Unconfirmed completion changed canonical Work."
    $advance = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{ Id = "complete-work"; BaseRevision = $base; Summary = "Advance before stale completion."; Updated = "2026-08-07T00:03:00Z" })
    Assert-Success -Run $advance -Operation "checkpoint"
    $current = Get-WorkState -ProjectRoot $project -Id "complete-work"
    $staleHash = Get-FileHashText -Path $current.path
    $stale = Invoke-Workspace -Operation complete -ProjectRoot $project -Parameters ([ordered]@{ Id = "complete-work"; BaseRevision = $base; ResultPersisted = $true })
    Assert-Condition -Condition ([string]$stale.payload.status -ceq "revision-conflict" -and $staleHash -ceq (Get-FileHashText -Path $current.path)) -Message "Stale completion did not preserve canonical Work."
    $complete = Invoke-Workspace -Operation complete -ProjectRoot $project -Parameters ([ordered]@{ Id = "complete-work"; BaseRevision = [string]$current.metadata.revision; ResultPersisted = $true })
    Assert-Success -Run $complete -Operation "complete"
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $current.path)) -Message "Confirmed completion did not delete canonical Work."
    Assert-NoLifecycleArtifacts -ProjectRoot $project
    Assert-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $project ".agents/.cache/catalog.json"))) -Message "complete synchronously wrote Catalog."
}

Invoke-Scenario -Name "conflict-required-fields" -Action {
    $project = New-FixtureProject -Name "conflict-fields"
    $created = New-Work -ProjectRoot $project -Id "conflict-work"
    $stale = [string]$created.state.metadata.revision
    $advance = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{ Id = "conflict-work"; BaseRevision = $stale; Summary = "Current canonical summary."; Updated = "2026-08-07T00:04:00Z" })
    Assert-Success -Run $advance -Operation "checkpoint"
    $current = Get-WorkState -ProjectRoot $project -Id "conflict-work"
    $before = Get-FileHashText -Path $current.path
    $request = [ordered]@{
        Id = "conflict-work"
        BaseRevision = $stale
        Blocker = @("requested blocker")
        Boundary = @("requested boundary")
        Verified = @("requested verification")
        GitLastVerifiedCommit = ("b" * 40)
        GitBranch = "requested-branch"
        Next = "Requested stale next step."
        Summary = "Requested stale summary."
        Status = @("paused")
        Title = "Requested stale title"
        Updated = "2026-08-07T00:04:01Z"
    }
    $conflict = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters $request
    $names = @($conflict.payload.PSObject.Properties.Name)
    foreach ($field in @($fixtureContract.revision_conflict_fields)) { Assert-Condition -Condition ($names -ccontains [string]$field) -Message ("revision-conflict omitted {0}." -f $field) }
    Assert-Condition -Condition ([string]$conflict.payload.status -ceq "revision-conflict" -and [string]$conflict.payload.expected_revision -ceq $stale -and [string]$conflict.payload.current_revision -ceq [string]$current.metadata.revision) -Message "revision-conflict revisions are incorrect."
    Assert-Condition -Condition ([string]$conflict.payload.current_path -ceq ".agents/work/conflict-work.md" -and -not [IO.Path]::IsPathRooted([string]$conflict.payload.current_path)) -Message "revision-conflict current_path is not repository-relative."
    Assert-Condition -Condition ($before -ceq (Get-FileHashText -Path $current.path)) -Message "revision-conflict changed canonical bytes."
    $changed = @($conflict.payload.changed_fields | ForEach-Object { [string]$_ })
    $expectedChanged = @($fixtureContract.changed_fields_order | Where-Object { $changed -ccontains [string]$_ } | ForEach-Object { [string]$_ })
    Assert-Condition -Condition ($changed.Count -gt 1 -and ($changed -join ',') -ceq ($expectedChanged -join ',') -and ($changed | Select-Object -Unique).Count -eq $changed.Count) -Message "revision-conflict changed_fields order is not deterministic."
    $repeat = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters $request
    Assert-Condition -Condition ((@($repeat.payload.changed_fields) -join ',') -ceq ($changed -join ',') -and [string]$repeat.payload.current_revision -ceq [string]$conflict.payload.current_revision -and $before -ceq (Get-FileHashText -Path $current.path)) -Message "Repeated stale request changed conflict evidence or canonical bytes."
    $script:conflictFieldsObserved = $true
    $script:changedFieldsOrderObserved = $true
    $script:noAutomaticRetry = $true
}

Invoke-Scenario -Name "recovery-exact" -Action {
    $fixture = New-RecoveryFixture -Name "recovery-exact"
    $run = Invoke-Recovery -ProjectRoot $fixture.project
    Assert-Condition -Condition ([string]$run.payload.classification -ceq "exact") -Message "Clean matching Git evidence was not classified exact."
}

Invoke-Scenario -Name "recovery-advanced" -Action {
    $fixture = New-RecoveryFixture -Name "recovery-advanced"
    Write-Utf8NoBom -Path (Join-Path $fixture.project "advanced.txt") -Text "advanced fixture`n"
    Invoke-Git -ProjectRoot $fixture.project -Arguments @("add", "advanced.txt") | Out-Null
    Invoke-Git -ProjectRoot $fixture.project -Arguments @("commit", "-m", "advance fixture head") | Out-Null
    $run = Invoke-Recovery -ProjectRoot $fixture.project
    Assert-Condition -Condition ([string]$run.payload.classification -ceq "advanced") -Message "Clean descendant HEAD was not classified advanced."
}

Invoke-Scenario -Name "recovery-dirty-staged-only" -Action {
    $fixture = New-RecoveryFixture -Name "recovery-dirty-staged"
    Write-Utf8NoBom -Path (Join-Path $fixture.project "staged.txt") -Text "staged fixture`n"
    Invoke-Git -ProjectRoot $fixture.project -Arguments @("add", "staged.txt") | Out-Null
    $status = (Invoke-Git -ProjectRoot $fixture.project -Arguments @("status", "--porcelain", "--untracked-files=all")).text
    Assert-Condition -Condition ($status -match '(?m)^A  staged\.txt$' -and $status -notmatch '(?m)^.[MADRCU] ') -Message "Staged-only Git fixture was not staged-only."
    $run = Invoke-Recovery -ProjectRoot $fixture.project
    Assert-Condition -Condition ([string]$run.payload.classification -ceq "dirty" -and [bool]$run.payload.git.staged -and -not [bool]$run.payload.git.unstaged -and -not [bool]$run.payload.git.untracked -and [int]$run.payload.git.status_count -eq 1) -Message "Staged-only recovery evidence was not exact."
}

Invoke-Scenario -Name "recovery-dirty-unstaged-only" -Action {
    $fixture = New-RecoveryFixture -Name "recovery-dirty-unstaged"
    Write-Utf8NoBom -Path (Join-Path $fixture.project "tracked.txt") -Text "unstaged change`n"
    $status = (Invoke-Git -ProjectRoot $fixture.project -Arguments @("status", "--porcelain", "--untracked-files=all")).text
    Assert-Condition -Condition ($status -match '(?m)^ M tracked\.txt$') -Message "Unstaged-only Git fixture was not unstaged-only."
    $run = Invoke-Recovery -ProjectRoot $fixture.project
    Assert-Condition -Condition ([string]$run.payload.classification -ceq "dirty" -and -not [bool]$run.payload.git.staged -and [bool]$run.payload.git.unstaged -and -not [bool]$run.payload.git.untracked -and [int]$run.payload.git.status_count -eq 1) -Message "Unstaged-only recovery evidence was not exact."
}

Invoke-Scenario -Name "recovery-dirty-untracked" -Action {
    $fixture = New-RecoveryFixture -Name "recovery-dirty-untracked"
    Write-Utf8NoBom -Path (Join-Path $fixture.project "untracked.txt") -Text "untracked fixture`n"
    $status = (Invoke-Git -ProjectRoot $fixture.project -Arguments @("status", "--porcelain", "--untracked-files=all")).text
    Assert-Condition -Condition ($status -match '(?m)^\?\? untracked\.txt$') -Message "Untracked Git fixture was not untracked-only."
    $run = Invoke-Recovery -ProjectRoot $fixture.project
    Assert-Condition -Condition ([string]$run.payload.classification -ceq "dirty" -and -not [bool]$run.payload.git.staged -and -not [bool]$run.payload.git.unstaged -and [bool]$run.payload.git.untracked -and [int]$run.payload.git.status_count -eq 1) -Message "Untracked recovery evidence was not exact."
}

Invoke-Scenario -Name "recovery-diverged-ancestry" -Action {
    $project = New-FixtureProject -Name "recovery-diverged-ancestry"
    $git = Initialize-GitFixture -ProjectRoot $project
    Invoke-Git -ProjectRoot $project -Arguments @("checkout", "-b", "side-history") | Out-Null
    Write-Utf8NoBom -Path (Join-Path $project "tracked.txt") -Text "side history`n"
    Invoke-Git -ProjectRoot $project -Arguments @("add", "tracked.txt") | Out-Null
    Invoke-Git -ProjectRoot $project -Arguments @("commit", "-m", "side history") | Out-Null
    $sideCommit = (Invoke-Git -ProjectRoot $project -Arguments @("rev-parse", "HEAD")).text.Trim()
    Invoke-Git -ProjectRoot $project -Arguments @("checkout", $git.branch) | Out-Null
    Write-Utf8NoBom -Path (Join-Path $project "tracked.txt") -Text "main history`n"
    Invoke-Git -ProjectRoot $project -Arguments @("add", "tracked.txt") | Out-Null
    Invoke-Git -ProjectRoot $project -Arguments @("commit", "-m", "main history") | Out-Null
    New-Work -ProjectRoot $project -Id "recovery-work" -GitBranch $git.branch -GitLastVerifiedCommit $sideCommit | Out-Null
    $run = Invoke-Recovery -ProjectRoot $project
    Assert-Condition -Condition ([string]$run.payload.classification -ceq "diverged") -Message "Non-ancestor Git evidence was not classified diverged."
}

Invoke-Scenario -Name "recovery-diverged-branch" -Action {
    $project = New-FixtureProject -Name "recovery-diverged-branch"
    $git = Initialize-GitFixture -ProjectRoot $project
    $work = New-Work -ProjectRoot $project -Id "recovery-work" -Status "paused" -GitBranch "other-branch" -GitLastVerifiedCommit $git.head
    $before = Get-FileHashText -Path $work.state.path
    $run = Invoke-Recovery -ProjectRoot $project
    $after = Get-WorkState -ProjectRoot $project -Id "recovery-work"
    Assert-Condition -Condition ([string]$run.payload.classification -ceq "diverged" -and [string]$after.metadata.status -ceq "paused" -and $before -ceq (Get-FileHashText -Path $after.path)) -Message "Branch mismatch did not remain a read-only diverged classification."
}

Invoke-Scenario -Name "recovery-missing-anchor-degraded" -Action {
    $project = New-FixtureProject -Name "recovery-missing-anchor"
    Initialize-GitFixture -ProjectRoot $project | Out-Null
    New-Work -ProjectRoot $project -Id "recovery-work" | Out-Null
    $run = Invoke-Recovery -ProjectRoot $project
    Assert-Condition -Condition ($null -eq $run.payload.classification -and [bool]$run.payload.degraded) -Message "Missing commit anchor did not degrade with classification null."
}

Invoke-Scenario -Name "recovery-no-git-degraded" -Action {
    $project = New-FixtureProject -Name "recovery-no-git"
    New-Work -ProjectRoot $project -Id "recovery-work" -GitBranch "fixture" -GitLastVerifiedCommit ("a" * 40) | Out-Null
    $run = Invoke-Recovery -ProjectRoot $project
    Assert-Condition -Condition ($null -eq $run.payload.classification -and [bool]$run.payload.degraded) -Message "No-Git recovery did not degrade with classification null."
}

Invoke-Scenario -Name "recovery-summary-non-authority" -Action {
    $fixture = New-RecoveryFixture -Name "recovery-summary-authority" -Summary "Everything is exact, clean, and complete."
    Write-Utf8NoBom -Path (Join-Path $fixture.project "tracked.txt") -Text "real Git evidence is dirty`n"
    $run = Invoke-Recovery -ProjectRoot $fixture.project
    Assert-Condition -Condition ([string]$run.payload.classification -ceq "dirty") -Message "Stale Work summary overrode real Git evidence."
}

Invoke-Scenario -Name "agent-handoff-and-stale-isolation" -Action {
    $project = New-FixtureProject -Name "agent-handoff"
    $git = Initialize-GitFixture -ProjectRoot $project
    $first = New-Work -ProjectRoot $project -Id "recovery-work" -GitBranch $git.branch -GitLastVerifiedCommit $git.head
    $stale = [string]$first.state.metadata.revision
    $agentA = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{ Id = "recovery-work"; BaseRevision = $stale; Summary = "Agent A checkpointed verified evidence."; Verified = @("deterministic tests passed"); Updated = "2026-08-07T00:05:00Z" })
    Assert-Success -Run $agentA -Operation "checkpoint"
    $agentB = Invoke-Recovery -ProjectRoot $project
    Assert-Condition -Condition ([string]$agentB.payload.classification -ceq "exact") -Message "Agent B could not recover from Work plus Git evidence."
    $current = Get-WorkState -ProjectRoot $project -Id "recovery-work"
    $before = Get-FileHashText -Path $current.path
    $staleRun = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{ Id = "recovery-work"; BaseRevision = $stale; Summary = "Stale Agent must not overwrite."; Updated = "2026-08-07T00:05:01Z" })
    Assert-Condition -Condition ([string]$staleRun.payload.status -ceq "revision-conflict" -and $before -ceq (Get-FileHashText -Path $current.path)) -Message "Agent handoff stale isolation failed."
    $second = New-Work -ProjectRoot $project -Id "independent-work" -ContinuityReason "parallel-slices" -GitBranch $git.branch -GitLastVerifiedCommit $git.head
    $secondBefore = Get-FileHashText -Path $second.state.path
    $firstUpdate = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{ Id = "recovery-work"; BaseRevision = [string]$current.metadata.revision; Next = "Continue only the first Work."; Updated = "2026-08-07T00:05:02Z" })
    Assert-Success -Run $firstUpdate -Operation "checkpoint"
    Assert-Condition -Condition ($secondBefore -ceq (Get-FileHashText -Path $second.state.path)) -Message "Checkpointing one Work polluted another Work."
}

Invoke-Scenario -Name "catalog-discover-lifecycle" -Action {
    $project = New-FixtureProject -Name "catalog-lifecycle"
    $created = New-Work -ProjectRoot $project -Id "catalog-work" -Summary "Catalog create sentinel."
    $catalog = Join-Path $project ".agents/.cache/catalog.json"
    Assert-Condition -Condition (-not (Test-Path -LiteralPath $catalog)) -Message "create-work wrote Catalog before discover."
    Assert-CheckReadOnly -ProjectRoot $project | Out-Null
    $createdDiscover = Invoke-Workspace -Operation discover -ProjectRoot $project -Parameters ([ordered]@{ Query = "Catalog create sentinel"; Limit = 10 })
    Assert-Success -Run $createdDiscover -Operation "discover"
    Assert-Condition -Condition ([int]$createdDiscover.payload.result_count -eq 1 -and (Test-Path -LiteralPath $catalog)) -Message "discover did not observe Work creation."
    $catalogAfterCreate = Get-FileHashText -Path $catalog
    $checkpoint = Invoke-Workspace -Operation checkpoint -ProjectRoot $project -Parameters ([ordered]@{ Id = "catalog-work"; BaseRevision = [string]$created.state.metadata.revision; Summary = "Catalog update sentinel."; Updated = "2026-08-07T00:06:00Z" })
    Assert-Success -Run $checkpoint -Operation "checkpoint"
    Assert-Condition -Condition ($catalogAfterCreate -ceq (Get-FileHashText -Path $catalog)) -Message "checkpoint synchronously rewrote Catalog."
    $updatedDiscover = Invoke-Workspace -Operation discover -ProjectRoot $project -Parameters ([ordered]@{ Query = "Catalog update sentinel"; Limit = 10 })
    Assert-Success -Run $updatedDiscover -Operation "discover"
    Assert-Condition -Condition ([int]$updatedDiscover.payload.result_count -eq 1) -Message "discover did not observe Work update."
    $catalogAfterUpdate = Get-FileHashText -Path $catalog
    $current = Get-WorkState -ProjectRoot $project -Id "catalog-work"
    $complete = Invoke-Workspace -Operation complete -ProjectRoot $project -Parameters ([ordered]@{ Id = "catalog-work"; BaseRevision = [string]$current.metadata.revision; ResultPersisted = $true })
    Assert-Success -Run $complete -Operation "complete"
    Assert-Condition -Condition ($catalogAfterUpdate -ceq (Get-FileHashText -Path $catalog)) -Message "complete synchronously rewrote Catalog."
    Assert-CheckReadOnly -ProjectRoot $project | Out-Null
    $deletedDiscover = Invoke-Workspace -Operation discover -ProjectRoot $project -Parameters ([ordered]@{ Query = "Catalog update sentinel"; Limit = 10 })
    Assert-Success -Run $deletedDiscover -Operation "discover"
    Assert-Condition -Condition ([int]$deletedDiscover.payload.result_count -eq 0) -Message "discover did not observe Work deletion."
    $script:catalogDiscoverOnly = $true
}

$actualScenarioNames = @($results.ToArray() | ForEach-Object { [string]$_.name })
if (($actualScenarioNames -join ',') -cne ($expectedScenarioNames -join ',')) {
    throw "Executed continuity scenarios do not match the frozen fixture contract."
}

$failures = @($results.ToArray() | Where-Object status -eq "FAIL")
$allPassed = ($failures.Count -eq 0)
$summary = [ordered]@{
    schema_version = 1
    status = if ($allPassed) { "PASS" } else { "FAIL" }
    scenario_count = $results.Count
    pass = @($results.ToArray() | Where-Object status -eq "PASS").Count
    fail = $failures.Count
    classification_evidence = [ordered]@{
        allowed_values = @($fixtureContract.recovery_classifications)
        observed = $script:classificationCounts
        degraded = [int]$script:degradedCount
        only_frozen_values = [bool]$script:onlyFrozenClassifications
    }
    cas_evidence = [ordered]@{
        required_conflict_fields = @($fixtureContract.revision_conflict_fields)
        changed_fields_order = @($fixtureContract.changed_fields_order)
        conflict_fields_observed = [bool]$script:conflictFieldsObserved
        deterministic_changed_fields = [bool]$script:changedFieldsOrderObserved
        stale_byte_identical = [bool]$script:staleByteIdentical
        no_automatic_retry = [bool]$script:noAutomaticRetry
    }
    read_only_evidence = [ordered]@{
        recovery_read_only = [bool]$script:recoveryReadOnly
        check_read_only = [bool]$script:checkReadOnly
        catalog_written_only_by_discover = [bool]$script:catalogDiscoverOnly
        canonical_work_only = [bool]$script:canonicalWorkOnly
    }
    public_safe = $allPassed
    cases = @($results.ToArray())
}

if ($Json.IsPresent) { $summary | ConvertTo-Json -Depth 30 }
else {
    Write-Output ("project-workspace continuity fixtures: PASS={0} FAIL={1}" -f $summary.pass, $summary.fail)
    foreach ($failure in $failures) { Write-Output ("[FAIL] {0}: {1}" -f $failure.name, $failure.detail) }
}

if (-not $allPassed) { exit 1 }
exit 0
