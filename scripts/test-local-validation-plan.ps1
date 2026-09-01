[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$classifier = Join-Path $PSScriptRoot "validate-change.ps1"
$orchestrator = Join-Path $PSScriptRoot "invoke-local-validation.ps1"
$planContract = Join-Path $PSScriptRoot "validation/local-validation-plan-contract.ps1"
$results = New-Object 'System.Collections.Generic.List[object]'

function Get-Classification([string[]]$Path) {
    return ((@(& $classifier -ChangedPath $Path -Json) -join "`n") | ConvertFrom-Json)
}

function Assert-PlanCase {
    param([string]$Name, [string[]]$Path, [int]$Tier, [bool]$ExpectPrePushHeavy)
    $value = Get-Classification -Path $Path
    if ([int]$value.detected_tier -ne $Tier) { throw "$Name expected Tier $Tier." }
    if ([int]$value.local_plan.schema_version -ne 2) { throw "$Name has no schema-2 local plan." }
    & $planContract -Result $value | Out-Null
    $iterationScripts = @($value.local_plan.stages.iteration.actions.script)
    if ($iterationScripts -contains "scripts/validate-release.ps1") {
        throw "$Name iteration plan includes a release checkpoint."
    }
    $releaseFullHosts = @($value.local_plan.stages.release.actions | Where-Object script -eq "scripts/validate-release.ps1" | ForEach-Object host)
    if (($releaseFullHosts -join ',') -cne "pwsh") { throw "$Name release plan does not preserve the pwsh host." }
    $releaseFullActions = @($value.local_plan.stages.release.actions | Where-Object script -eq "scripts/validate-release.ps1")
    foreach ($action in $releaseFullActions) {
        if ((@($action.arguments) -join ',') -cne "-ValidationShard,RepositoryCheckpoint") { throw "$Name release plan does not explicitly select the RepositoryCheckpoint shard." }
    }
    $prePushHeavy = @($value.local_plan.stages.pre_push.actions | Where-Object script -eq "scripts/test-heavy-targeted-regression.ps1")
    if (($prePushHeavy.Count -gt 0) -ne $ExpectPrePushHeavy) { throw "$Name has an incorrect pre-push heavy decision." }
    $results.Add([ordered]@{ name = $Name; status = "PASS" })
}

function Invoke-LocalEvidenceReuseFixtures {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-local-evidence-{0}" -f [Guid]::NewGuid().ToString("N"))
    $fixtureRepo = Join-Path $fixtureRoot "repository"
    $counterRoot = Join-Path $fixtureRoot "counters"
    $fixtureOrchestrator = Join-Path $fixtureRepo "scripts/invoke-local-validation.ps1"
    $fixtureResults = New-Object 'System.Collections.Generic.List[object]'
    $hadCounterRoot = Test-Path Env:AGENT_ECOSYSTEM_LOCAL_EVIDENCE_COUNTER_ROOT
    $previousCounterRoot = $env:AGENT_ECOSYSTEM_LOCAL_EVIDENCE_COUNTER_ROOT

    function Invoke-FixtureGit {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
        $output = @(& git -C $fixtureRepo @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Fixture git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)" }
        return @($output)
    }

    function Write-FixtureFile {
        param([string]$RelativePath, [string]$Content)
        $path = Join-Path $fixtureRepo $RelativePath
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path)) | Out-Null
        [System.IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
    }

    function Get-ExecutionCount {
        $total = 0
        foreach ($path in @(Get-ChildItem -LiteralPath $counterRoot -Filter "*.count" -File -ErrorAction SilentlyContinue)) {
            $total += [int]([System.IO.File]::ReadAllText($path))
        }
        return $total
    }

    function Invoke-FixtureJson {
        param([string]$Stage, [string]$Base, [string]$Head, [string]$Scratch, [string]$Evidence = "")
        $output = if ([string]::IsNullOrWhiteSpace($Evidence)) {
            @(& $fixtureOrchestrator -Stage $Stage -BaseRef $Base -HeadRef $Head -RepositoryRoot $fixtureRepo -ScratchRoot $Scratch -Json)
        }
        else {
            @(& $fixtureOrchestrator -Stage $Stage -BaseRef $Base -HeadRef $Head -RepositoryRoot $fixtureRepo -ScratchRoot $Scratch -IterationEvidencePath $Evidence -Json)
        }
        return (($output -join [Environment]::NewLine) | ConvertFrom-Json)
    }

    function New-EvidenceVariant {
        param([string]$Name, [scriptblock]$Mutate)
        $path = Join-Path $fixtureRoot "$Name.json"
        $value = [System.IO.File]::ReadAllText($iterationEvidencePath) | ConvertFrom-Json
        & $Mutate $value
        $value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
        return $path
    }

    function Assert-Reexecuted {
        param([string]$Name, [string]$Evidence, [string]$ExpectedReason, [string]$Head)
        $value = Invoke-FixtureJson -Stage "pre-push" -Base $baseCommit -Head $Head -Scratch (Join-Path $fixtureRoot "run-$Name") -Evidence $Evidence
        if ([string]$value.status -cne "PASS" -or [string]$value.reuse_decision.disposition -cne "re-executed" -or
            [string]$value.reuse_decision.reason -cne $ExpectedReason -or
            @($value.actions | Where-Object { [string]$_.disposition -cne "re-executed" }).Count -ne 0) {
            throw "Evidence fixture '$Name' did not re-execute for '$ExpectedReason'."
        }
        $fixtureResults.Add([ordered]@{ name = $Name; status = "PASS"; disposition = "re-executed"; reason = $ExpectedReason }) | Out-Null
    }

    try {
        [System.IO.Directory]::CreateDirectory($fixtureRepo) | Out-Null
        [System.IO.Directory]::CreateDirectory($counterRoot) | Out-Null
        [System.IO.Directory]::CreateDirectory((Join-Path $fixtureRepo "scripts/validation")) | Out-Null
        $env:AGENT_ECOSYSTEM_LOCAL_EVIDENCE_COUNTER_ROOT = $counterRoot
        Copy-Item -LiteralPath $orchestrator -Destination $fixtureOrchestrator
        Copy-Item -LiteralPath $planContract -Destination (Join-Path $fixtureRepo "scripts/validation/local-validation-plan-contract.ps1")

        Write-FixtureFile "scripts/validation/powershell-runtime-requirement.ps1" @'
function Assert-AgentEcosystemPowerShellRuntime {}
function Resolve-AgentEcosystemPwshExecutable { return [string](Get-Process -Id $PID).Path }
'@
        Write-FixtureFile "scripts/validation/release-classifier-output-contract.ps1" @'
param([object]$Result)
if ($null -eq $Result) { throw "Fixture classifier result is missing." }
Write-Output $Result
'@
        Write-FixtureFile "scripts/validation/change-risk-rules.json" "{}"
        Write-FixtureFile "scripts/validate-change.ps1" @'
[CmdletBinding(DefaultParameterSetName = "GitDiff")]
param(
    [Parameter(ParameterSetName = "Paths", Mandatory = $true)][string[]]$ChangedPath,
    [Parameter(ParameterSetName = "GitDiff")][string]$BaseRef = "HEAD~1",
    [Parameter(ParameterSetName = "GitDiff")][string]$HeadRef = "HEAD",
    [Parameter(ParameterSetName = "GitDiff")][string]$RepositoryRoot = "",
    [switch]$Json
)
$root = if ($RepositoryRoot) { $RepositoryRoot } else { Split-Path -Parent $PSScriptRoot }
$base = if ($PSCmdlet.ParameterSetName -eq "Paths") { "" } else { ([string]@(& git -C $root rev-parse --verify "$BaseRef^{commit}")[-1]).Trim().ToLowerInvariant() }
$head = if ($PSCmdlet.ParameterSetName -eq "Paths") { "" } else { ([string]@(& git -C $root rev-parse --verify "$HeadRef^{commit}")[-1]).Trim().ToLowerInvariant() }
$paths = if ($PSCmdlet.ParameterSetName -eq "Paths") { @($ChangedPath) } else { @(& git -C $root diff --name-only $base $head) }
$classifierAction = [ordered]@{ id = "classifier-contracts"; script = "scripts/test-validate-change.ps1"; arguments = @(); host = "current"; suite = "classification-and-routing-contracts"; reason = "fixture classifier contracts" }
$targetedAction = [ordered]@{ id = "affected-change-validation"; script = "scripts/validate-targeted-change.ps1"; arguments = @("-Mode", "targeted"); host = "current"; suite = "tier-3-targeted"; reason = "fixture affected validation" }
$oracleAction = [ordered]@{ id = "validation-self-protection"; script = "scripts/test-heavy-targeted-regression.ps1"; arguments = @(); host = "current"; suite = "validation-self-protection"; reason = "fixture self-protection" }
$oracleRelease = [ordered]@{ id = "validation-self-protection"; script = "scripts/test-heavy-targeted-regression.ps1"; arguments = @(); host = "pwsh"; suite = "validation-self-protection"; reason = "fixture self-protection" }
$releaseAction = [ordered]@{ id = "full-release-validation-pwsh"; script = "scripts/validate-release.ps1"; arguments = @("-ValidationShard", "RepositoryCheckpoint"); host = "pwsh"; suite = "full-release-validation"; reason = "fixture release" }
$skip = [ordered]@{ id = "full-release-validation"; status = "SKIPPED"; reason = "fixture skip" }
$result = [ordered]@{
    schema_version = 2; detected_tier = 3; base_ref = $base; head_ref = $head
    changed_paths = @($paths); affected_modules = @("validation-routing"); base_check_modules = @()
    required_suites = @(); module_suite_map = [ordered]@{ "validation-routing" = @() }
    required_hosts = @("windows-latest"); suite_host_map = [ordered]@{}
    run_validation_self_protection = $true; validation_self_protection_reason = "self-protection-control-surface"
    control_plane = $true; conservative_fallback = $false; run_heavy_targeted_regression = $true
    local_plan = [ordered]@{
        schema_version = 2
        stages = [ordered]@{
            iteration = [ordered]@{ actions = @($classifierAction, $targetedAction, $oracleAction); skipped = @($skip) }
            pre_push = [ordered]@{ actions = @($classifierAction, $targetedAction, $oracleAction); skipped = @($skip) }
            release = [ordered]@{ actions = @($classifierAction, $oracleRelease, $releaseAction); skipped = @() }
        }
    }
}
$result | ConvertTo-Json -Depth 12
'@
        Write-FixtureFile "scripts/test-validate-change.ps1" @'
param([switch]$Json)
$path = Join-Path $env:AGENT_ECOSYSTEM_LOCAL_EVIDENCE_COUNTER_ROOT "classifier.count"
$count = if (Test-Path -LiteralPath $path) { [int]([IO.File]::ReadAllText($path)) } else { 0 }
[IO.File]::WriteAllText($path, [string]($count + 1))
[ordered]@{ status = "PASS" } | ConvertTo-Json
'@
        Write-FixtureFile "scripts/validate-targeted-change.ps1" @'
param([string]$Mode, [string[]]$ChangedPath, [string]$BaseRef, [string]$HeadRef, [switch]$Json)
$path = Join-Path $env:AGENT_ECOSYSTEM_LOCAL_EVIDENCE_COUNTER_ROOT "targeted.count"
$count = if (Test-Path -LiteralPath $path) { [int]([IO.File]::ReadAllText($path)) } else { 0 }
[IO.File]::WriteAllText($path, [string]($count + 1))
[ordered]@{ status = "PASS" } | ConvertTo-Json
'@
        Write-FixtureFile "scripts/test-heavy-targeted-regression.ps1" @'
param([switch]$Json)
$path = Join-Path $env:AGENT_ECOSYSTEM_LOCAL_EVIDENCE_COUNTER_ROOT "oracle.count"
$count = if (Test-Path -LiteralPath $path) { [int]([IO.File]::ReadAllText($path)) } else { 0 }
[IO.File]::WriteAllText($path, [string]($count + 1))
[ordered]@{ status = "PASS" } | ConvertTo-Json
'@
        Write-FixtureFile "scripts/validate-release.ps1" 'param([switch]$Json)'

        & git -C $fixtureRepo init -b main | Out-Null
        & git -C $fixtureRepo config user.name "Local Evidence Fixture"
        & git -C $fixtureRepo config user.email "local-evidence@example.invalid"
        & git -C $fixtureRepo config core.autocrlf false
        & git -C $fixtureRepo add .
        & git -C $fixtureRepo commit -m "fixture base" | Out-Null
        $baseCommit = ([string]@(Invoke-FixtureGit rev-parse HEAD)[0]).Trim()
        Write-FixtureFile "candidate.txt" "candidate one"
        & git -C $fixtureRepo add candidate.txt
        & git -C $fixtureRepo commit -m "fixture candidate" | Out-Null
        $candidateCommit = ([string]@(Invoke-FixtureGit rev-parse HEAD)[0]).Trim()

        $iterationScratch = Join-Path $fixtureRoot "iteration"
        $iteration = Invoke-FixtureJson -Stage "iteration" -Base $baseCommit -Head $candidateCommit -Scratch $iterationScratch
        $iterationEvidencePath = [string]$iteration.result_path
        if ([string]$iteration.status -cne "PASS" -or -not [bool]$iteration.reuse_evidence.complete -or
            @($iteration.actions | Where-Object { [string]$_.disposition -cne "executed" -or [string]$_.status -cne "PASS" -or [int]$_.exit_code -ne 0 }).Count -ne 0) {
            throw "Iteration did not produce complete successful execution evidence."
        }
        $fixtureResults.Add([ordered]@{ name = "iteration-complete-executed-evidence"; status = "PASS"; disposition = "executed" }) | Out-Null

        $countAfterIteration = Get-ExecutionCount
        $unchanged = Invoke-FixtureJson -Stage "pre-push" -Base $baseCommit -Head $candidateCommit -Scratch (Join-Path $fixtureRoot "unchanged") -Evidence $iterationEvidencePath
        if ([string]$unchanged.reuse_decision.disposition -cne "reused" -or
            [string]$unchanged.reuse_decision.reason -cne "equivalent-successful-iteration-evidence" -or
            @($unchanged.actions | Where-Object { [string]$_.disposition -cne "reused" }).Count -ne 0 -or
            (Get-ExecutionCount) -ne $countAfterIteration) {
            throw "Equivalent iteration evidence was not reused without execution."
        }
        $fixtureResults.Add([ordered]@{ name = "unchanged-candidate-reused"; status = "PASS"; disposition = "reused" }) | Out-Null

        $sameScratch = Join-Path $fixtureRoot "same-scratch"
        Invoke-FixtureJson -Stage "iteration" -Base $baseCommit -Head $candidateCommit -Scratch $sameScratch | Out-Null
        $countBeforeSameScratchPrePush = Get-ExecutionCount
        $sameScratchPrePush = Invoke-FixtureJson -Stage "pre-push" -Base $baseCommit -Head $candidateCommit -Scratch $sameScratch
        if ([string]$sameScratchPrePush.reuse_decision.disposition -cne "reused" -or
            [string]$sameScratchPrePush.reuse_decision.evidence_source -cne "same-scratch-root" -or
            (Get-ExecutionCount) -ne $countBeforeSameScratchPrePush) {
            throw "Same-ScratchRoot iteration evidence was not reused before checkpoint replacement."
        }
        $fixtureResults.Add([ordered]@{ name = "same-scratch-checkpoint-reused"; status = "PASS"; disposition = "reused" }) | Out-Null

        $textOutput = @(& $fixtureOrchestrator -Stage pre-push -BaseRef $baseCommit -HeadRef $candidateCommit -RepositoryRoot $fixtureRepo -ScratchRoot (Join-Path $fixtureRoot "text") -IterationEvidencePath $iterationEvidencePath)
        $text = $textOutput -join [Environment]::NewLine
        if ($text -notmatch 'disposition=reused' -or $text -notmatch 'reason=equivalent-successful-iteration-evidence') {
            throw "Text output did not report reused disposition and reason."
        }
        $fixtureResults.Add([ordered]@{ name = "json-text-dispositions"; status = "PASS" }) | Out-Null

        $treeVariant = New-EvidenceVariant -Name "tree-changed" -Mutate { param($value) $value.reuse_evidence.binding.candidate.tree = "0" * 40 }
        Assert-Reexecuted -Name "candidate-tree-changed" -Evidence $treeVariant -ExpectedReason "candidate-tree-changed" -Head $candidateCommit

        $routingVariant = New-EvidenceVariant -Name "routing-changed" -Mutate { param($value) $value.reuse_evidence.binding.routing_sha256 = "0" * 64 }
        Assert-Reexecuted -Name "validation-routing-changed" -Evidence $routingVariant -ExpectedReason "validation-routing-changed" -Head $candidateCommit

        $runtimeVariant = New-EvidenceVariant -Name "runtime-changed" -Mutate { param($value) $value.reuse_evidence.binding.runtime_sha256 = "0" * 64 }
        Assert-Reexecuted -Name "host-runtime-changed" -Evidence $runtimeVariant -ExpectedReason "host-runtime-identity-changed" -Head $candidateCommit

        $authorityVariant = New-EvidenceVariant -Name "authority-changed" -Mutate { param($value) $value.reuse_evidence.binding.authority_sha256 = "0" * 64 }
        Assert-Reexecuted -Name "validation-authority-changed" -Evidence $authorityVariant -ExpectedReason "validation-authority-changed" -Head $candidateCommit

        $failedVariant = New-EvidenceVariant -Name "failed" -Mutate { param($value) $value.status = "FAIL" }
        Assert-Reexecuted -Name "failed-evidence" -Evidence $failedVariant -ExpectedReason "iteration-evidence-not-successful" -Head $candidateCommit

        $incompleteVariant = New-EvidenceVariant -Name "incomplete" -Mutate { param($value) $value.reuse_evidence.complete = $false }
        Assert-Reexecuted -Name "incomplete-evidence" -Evidence $incompleteVariant -ExpectedReason "iteration-evidence-incomplete" -Head $candidateCommit

        $incompleteActionVariant = New-EvidenceVariant -Name "incomplete-action" -Mutate { param($value) $value.actions[0].PSObject.Properties.Remove("exit_code") }
        Assert-Reexecuted -Name "incomplete-action-evidence" -Evidence $incompleteActionVariant -ExpectedReason "iteration-evidence-incomplete" -Head $candidateCommit

        $malformedVariant = Join-Path $fixtureRoot "malformed.json"
        [System.IO.File]::WriteAllText($malformedVariant, "{")
        Assert-Reexecuted -Name "malformed-evidence" -Evidence $malformedVariant -ExpectedReason "iteration-evidence-malformed" -Head $candidateCommit
        Assert-Reexecuted -Name "missing-evidence" -Evidence (Join-Path $fixtureRoot "missing.json") -ExpectedReason "iteration-evidence-missing" -Head $candidateCommit

        $authorityPath = Join-Path $fixtureRepo "scripts/validate-targeted-change.ps1"
        $authorityBytes = [System.IO.File]::ReadAllBytes($authorityPath)
        Add-Content -LiteralPath $authorityPath -Value "# fixture authority drift"
        Assert-Reexecuted -Name "dirty-worktree" -Evidence $iterationEvidencePath -ExpectedReason "candidate-worktree-not-clean" -Head $candidateCommit
        [System.IO.File]::WriteAllBytes($authorityPath, $authorityBytes)
        if (@(Invoke-FixtureGit status --porcelain=v1).Count -ne 0) { throw "Authority fixture did not restore the committed tree." }

        Write-FixtureFile "candidate.txt" "candidate two"
        & git -C $fixtureRepo add candidate.txt
        & git -C $fixtureRepo commit -m "fixture candidate changed" | Out-Null
        $changedCandidate = ([string]@(Invoke-FixtureGit rev-parse HEAD)[0]).Trim()
        Assert-Reexecuted -Name "candidate-commit-changed" -Evidence $iterationEvidencePath -ExpectedReason "candidate-commit-identity-changed" -Head $changedCandidate
    }
    finally {
        if ($hadCounterRoot) { $env:AGENT_ECOSYSTEM_LOCAL_EVIDENCE_COUNTER_ROOT = $previousCounterRoot }
        else { Remove-Item Env:AGENT_ECOSYSTEM_LOCAL_EVIDENCE_COUNTER_ROOT -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $fixtureRoot) {
            $resolvedFixtureRoot = [System.IO.Path]::GetFullPath($fixtureRoot)
            $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
            if (-not $resolvedFixtureRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove fixture path outside the temporary root."
            }
            Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
        }
    }
    return @($fixtureResults.ToArray())
}

Assert-PlanCase -Name "tier-zero" -Path "README.md" -Tier 0 -ExpectPrePushHeavy $false
Assert-PlanCase -Name "examples-namespace-default" -Path "examples/future-adoption/config.json" -Tier 0 -ExpectPrePushHeavy $false
Assert-PlanCase -Name "ordinary-content-default" -Path "future-surface/notes.txt" -Tier 0 -ExpectPrePushHeavy $false
Assert-PlanCase -Name "tier-one" -Path "knowledge-hub/knowledge/catalog.md" -Tier 1 -ExpectPrePushHeavy $false
Assert-PlanCase -Name "tier-two" -Path "scripts/install.ps1" -Tier 2 -ExpectPrePushHeavy $false
Assert-PlanCase -Name "tier-three-covered" -Path "CHANGELOG.md" -Tier 3 -ExpectPrePushHeavy $false
Assert-PlanCase -Name "tier-three-self-protection" -Path "scripts/validate-change.ps1" -Tier 3 -ExpectPrePushHeavy $true
Assert-PlanCase -Name "tier-three-unknown" -Path "future-surface/value.bin" -Tier 3 -ExpectPrePushHeavy $true
Assert-PlanCase -Name "tier-three-unresolved" -Path "src/future.c" -Tier 3 -ExpectPrePushHeavy $true

$iterationDryRun = ((@(& $orchestrator -Stage iteration -ChangedPath "scripts/validate-change.ps1" -DryRun -Json) -join "`n") | ConvertFrom-Json)
if (@($iterationDryRun.actions | Where-Object suite -eq "full-release-validation").Count -ne 0) { throw "Tier 3 iteration dry-run planned full validation." }
if (@($iterationDryRun.actions | Where-Object status -eq "PLANNED").Count -ne @($iterationDryRun.actions).Count) { throw "Dry-run actions were not reported as PLANNED." }

$prePushDryRun = ((@(& $orchestrator -Stage pre-push -ChangedPath "scripts/validate-change.ps1" -DryRun -Json) -join "`n") | ConvertFrom-Json)
if (@($prePushDryRun.actions | Where-Object suite -eq "validation-self-protection").Count -ne 1) { throw "Control-surface pre-push dry-run did not plan one independent self-protection oracle." }
if (@($prePushDryRun.actions | Where-Object suite -eq "full-release-validation").Count -ne 0) { throw "Affected pre-push dry-run planned a release checkpoint." }
foreach ($action in @($prePushDryRun.actions)) {
    if ([string]::IsNullOrWhiteSpace([string]$action.command_line) -or [string]::IsNullOrWhiteSpace([string]$action.host) -or [string]::IsNullOrWhiteSpace([string]$action.suite) -or [string]::IsNullOrWhiteSpace([string]$action.reason)) {
        throw "Pre-push dry-run omitted command, host, suite, or reason."
    }
    if ([long]$action.duration_ms -lt 0) { throw "Pre-push dry-run emitted negative timing." }
}
if ([long]$prePushDryRun.timing.duration_ms -lt 0) { throw "Pre-push stage emitted negative timing." }
$results.Add([ordered]@{ name = "orchestrator-dry-run"; status = "PASS" })

foreach ($fixtureResult in @(Invoke-LocalEvidenceReuseFixtures)) {
    $results.Add($fixtureResult)
}

$processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processStartInfo.FileName = [string](Get-Process -Id $PID).Path
$processStartInfo.UseShellExecute = $false
$processStartInfo.RedirectStandardOutput = $true
$processStartInfo.RedirectStandardError = $true
$escapedOrchestrator = $orchestrator.Replace("'", "''")
$missingPwshCommand = @"
function global:Get-Command {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]`$Name, [object]`$CommandType)
    if (`$Name -ceq 'pwsh') { return `$null }
    return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
}
& '$escapedOrchestrator' -Stage release -ChangedPath README.md -DryRun -Json
"@
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($missingPwshCommand))
foreach ($argument in @("-NoProfile", "-NonInteractive", "-EncodedCommand", $encodedCommand)) {
    [void]$processStartInfo.ArgumentList.Add([string]$argument)
}
$missingPwshProcess = [System.Diagnostics.Process]::Start($processStartInfo)
$missingPwshStdout = $missingPwshProcess.StandardOutput.ReadToEnd()
$missingPwshStderr = $missingPwshProcess.StandardError.ReadToEnd()
$missingPwshProcess.WaitForExit()
if ($missingPwshProcess.ExitCode -eq 0) {
    throw "Release dry-run with missing pwsh returned a successful process exit."
}
$missingPwshDryRun = $missingPwshStdout | ConvertFrom-Json
$unavailablePwshActions = @($missingPwshDryRun.actions | Where-Object {
    $_.host -eq "pwsh" -and $_.status -eq "UNAVAILABLE" -and [int]$_.exit_code -eq 127
})
if ([string]$missingPwshDryRun.status -cne "FAIL" -or $unavailablePwshActions.Count -lt 1 -or [int]$missingPwshDryRun.summary.fail -lt 1) {
    throw "Release dry-run reported missing pwsh as executable success."
}
if (@($missingPwshDryRun.actions | Where-Object { $_.host -eq "pwsh" -and $_.status -in @("PASS", "PLANNED") }).Count -ne 0) {
    throw "Release dry-run left a missing pwsh action in a successful or executable state."
}
if ($missingPwshStderr -notmatch "Local validation stage 'release' failed\.") {
    throw "Release dry-run with missing pwsh did not emit the stable stage failure."
}
$results.Add([ordered]@{ name = "missing-pwsh-fails-closed"; status = "PASS" })

$invalid = Get-Classification -Path "README.md"
$invalid.local_plan.stages.iteration.actions[0].script = "scripts/validate-release.ps1"
$rejected = $false
try { & $planContract -Result $invalid | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Local plan contract accepted full validation during iteration." }
$results.Add([ordered]@{ name = "invalid-plan-fails-closed"; status = "PASS" })

$missingAction = Get-Classification -Path "README.md"
$missingAction.local_plan.stages.pre_push.actions = @($missingAction.local_plan.stages.pre_push.actions | Where-Object script -ne "scripts/validate-targeted-change.ps1")
$rejected = $false
try { & $planContract -Result $missingAction | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Local plan contract accepted a pre-push plan with no affected-suite action." }
$results.Add([ordered]@{ name = "missing-action-fails-closed"; status = "PASS" })

$invalidShard = Get-Classification -Path "README.md"
$invalidShard.local_plan.stages.release.actions[1].arguments = @("-ValidationShard", "Full")
$rejected = $false
try { & $planContract -Result $invalidShard | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Local plan contract accepted a release action without the RepositoryCheckpoint shard." }
$results.Add([ordered]@{ name = "release-shard-fails-closed"; status = "PASS" })

$summary = [ordered]@{ schema_version = 2; pass = $results.Count; fail = 0; cases = @($results.ToArray()) }
if ($Json.IsPresent) { $summary | ConvertTo-Json -Depth 6 } else { Write-Output ("local validation plan fixtures: PASS={0} FAIL=0" -f $summary.pass) }
