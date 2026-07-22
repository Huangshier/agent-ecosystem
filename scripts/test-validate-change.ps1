[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$RunTargetedRegression,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot "validate-change.ps1"
$cases = Get-Content -LiteralPath (Join-Path $PSScriptRoot "validation/change-risk-fixtures/cases.json") -Raw | ConvertFrom-Json
$classifierOutputContract = Join-Path $PSScriptRoot "validation/release-classifier-output-contract.ps1"
$classifierOutputCases = Get-Content -LiteralPath (Join-Path $PSScriptRoot "validation/release-classifier-output-fixtures/cases.json") -Raw | ConvertFrom-Json
$localPlanValidator = Join-Path $PSScriptRoot "test-local-validation-plan.ps1"
$results = New-Object 'System.Collections.Generic.List[object]'
$targetedValidator = Join-Path $PSScriptRoot "validate-targeted-change.ps1"
$targetedScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-targeted-regression-{0}" -f ([Guid]::NewGuid().ToString("N")))

function Invoke-FixtureGit {
    param([string]$Root, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git -C $Root @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Fixture git failed in '$Root': git $($Arguments -join ' ')" }
    return @($output)
}

function New-GitFixtureRepository {
    param([string]$Root)
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    & git -C $Root init -b main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not initialize fixture repository '$Root'." }
    Invoke-FixtureGit $Root config user.name "Validation Fixture" | Out-Null
    Invoke-FixtureGit $Root config user.email "validation-fixture@example.invalid" | Out-Null
}

function Add-GitFixtureCommit {
    param([string]$Root, [string]$Path, [string]$Content, [string]$Message)
    $fullPath = Join-Path $Root $Path
    $parent = Split-Path -Parent $fullPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Set-Content -LiteralPath $fullPath -Value $Content -Encoding utf8
    Invoke-FixtureGit $Root add -- $Path | Out-Null
    Invoke-FixtureGit $Root commit -m $Message | Out-Null
    return [string](@(Invoke-FixtureGit $Root rev-parse HEAD)[-1])
}

function Assert-GitBoundaryCase {
    param(
        [string]$Name,
        [string]$Root,
        [string]$Base,
        [string]$Head,
        [int]$Tier,
        [switch]$ForcePush,
        [switch]$ExpectNormalizedBoundary
    )
    $raw = @(& $validator -RepositoryRoot $Root -BaseRef $Base -HeadRef $Head -ForcePush:$ForcePush -Json) -join "`n"
    $value = $raw | ConvertFrom-Json
    if ([int]$value.detected_tier -ne $Tier) { throw "Git boundary case '$Name' expected Tier $Tier, got Tier $($value.detected_tier): $($value.escalation_reason)" }
    if ($ExpectNormalizedBoundary.IsPresent) {
        $expectedBase = [string](@(Invoke-FixtureGit $Root rev-parse "$Base^{commit}")[-1])
        $expectedHead = [string](@(Invoke-FixtureGit $Root rev-parse "$Head^{commit}")[-1])
        if ([string]$value.base_ref -cne $expectedBase.ToLowerInvariant() -or [string]$value.head_ref -cne $expectedHead.ToLowerInvariant()) {
            throw "Git boundary case '$Name' did not return normalized base/head commit IDs."
        }
    }
    return [ordered]@{ name = $Name; tier = $Tier; status = "PASS" }
}

function Invoke-PushRoutingFixtures {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-push-routing-{0}" -f ([Guid]::NewGuid().ToString("N")))
    $fixtureResults = New-Object 'System.Collections.Generic.List[object]'
    try {
        $linear = Join-Path $root "linear"
        New-GitFixtureRepository $linear
        $base = Add-GitFixtureCommit $linear "README.md" "base" "base"
        $tierZero = Add-GitFixtureCommit $linear "README.md" "tier zero" "tier zero"
        $tierOne = Add-GitFixtureCommit $linear "knowledge-hub/knowledge/catalog.md" "tier one" "tier one"
        $tierTwo = Add-GitFixtureCommit $linear "scripts/install.ps1" "Write-Output 'tier two'" "tier two"
        $tierThree = Add-GitFixtureCommit $linear ".github/workflows/release-validation.yml" "name: tier-three" "tier three"

        $fixtureResults.Add((Assert-GitBoundaryCase "push-tier-0" $linear $base $tierZero 0 -ExpectNormalizedBoundary))
        $fixtureResults.Add((Assert-GitBoundaryCase "push-tier-1" $linear $tierZero $tierOne 1 -ExpectNormalizedBoundary))
        $fixtureResults.Add((Assert-GitBoundaryCase "push-tier-2" $linear $tierOne $tierTwo 2 -ExpectNormalizedBoundary))
        $fixtureResults.Add((Assert-GitBoundaryCase "multi-commit-push" $linear $base $tierTwo 2 -ExpectNormalizedBoundary))
        $fixtureResults.Add((Assert-GitBoundaryCase "push-tier-3" $linear $tierTwo $tierThree 3 -ExpectNormalizedBoundary))
        $fixtureResults.Add((Assert-GitBoundaryCase "all-zero-before" $linear ("0" * 40) $tierThree 3))
        $fixtureResults.Add((Assert-GitBoundaryCase "missing-before" $linear "refs/heads/definitely-missing" $tierThree 3))
        $fixtureResults.Add((Assert-GitBoundaryCase "forced-push" $linear $base $tierZero 3 -ForcePush))

        Invoke-FixtureGit $linear switch --quiet --orphan unrelated | Out-Null
        $unrelated = Add-GitFixtureCommit $linear "future-surface/value.bin" "unrelated" "unrelated root"
        $fixtureResults.Add((Assert-GitBoundaryCase "non-ancestor-push" $linear $base $unrelated 3))

        $shallow = Join-Path $root "shallow"
        $linearUri = ([System.Uri]::new(($linear.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar))).AbsoluteUri
        & git clone --quiet --depth 1 --branch main $linearUri $shallow 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not create shallow history fixture." }
        $fixtureResults.Add((Assert-GitBoundaryCase "shallow-history" $shallow $tierTwo $tierThree 3))

        $merge = Join-Path $root "merge"
        New-GitFixtureRepository $merge
        $mergeBase = Add-GitFixtureCommit $merge "README.md" "base" "base"
        Invoke-FixtureGit $merge switch --quiet -c feature | Out-Null
        Add-GitFixtureCommit $merge "knowledge-hub/knowledge/catalog.md" "feature" "feature" | Out-Null
        Invoke-FixtureGit $merge switch --quiet main | Out-Null
        $beforeMerge = Add-GitFixtureCommit $merge "README.md" "main" "main"
        Invoke-FixtureGit $merge merge --no-ff feature -m "merge feature" | Out-Null
        $mergeHead = [string](@(Invoke-FixtureGit $merge rev-parse HEAD)[-1])
        $fixtureResults.Add((Assert-GitBoundaryCase "merge-commit-push" $merge $beforeMerge $mergeHead 1 -ExpectNormalizedBoundary))

        $squash = Join-Path $root "squash"
        New-GitFixtureRepository $squash
        $squashBase = Add-GitFixtureCommit $squash "README.md" "base" "base"
        Invoke-FixtureGit $squash switch --quiet -c feature | Out-Null
        Add-GitFixtureCommit $squash "scripts/install.ps1" "Write-Output 'feature'" "feature" | Out-Null
        Invoke-FixtureGit $squash switch --quiet main | Out-Null
        Invoke-FixtureGit $squash merge --squash feature | Out-Null
        Invoke-FixtureGit $squash commit -m "squash feature" | Out-Null
        $squashHead = [string](@(Invoke-FixtureGit $squash rev-parse HEAD)[-1])
        $fixtureResults.Add((Assert-GitBoundaryCase "squash-commit-push" $squash $squashBase $squashHead 2 -ExpectNormalizedBoundary))

        return @($fixtureResults.ToArray())
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

function Invoke-ClassifierOutputContractFixtures {
    $fixtureResults = New-Object 'System.Collections.Generic.List[object]'
    foreach ($case in @($classifierOutputCases)) {
        $accepted = $false
        try {
            $validated = & $classifierOutputContract -Result $case.result
            $accepted = $true
            if (-not [bool]$case.valid) {
                throw "Invalid classifier output fixture '$($case.name)' produced a skippable decision."
            }
            if ($validated.run_heavy_targeted_regression -isnot [bool] -or [bool]$validated.run_heavy_targeted_regression) {
                throw "Valid classifier output fixture '$($case.name)' did not preserve the Boolean false decision."
            }
        }
        catch {
            if ([bool]$case.valid -or $accepted) { throw }
        }
        $fixtureResults.Add([ordered]@{ name = [string]$case.name; status = "PASS" })
    }
    return @($fixtureResults.ToArray())
}

function Invoke-TargetedRegression {
    param([string]$Name, [string[]]$Path, [string[]]$ExpectedModule, [string[]]$ExpectedSuite, [string]$Mode)
    $caseScratch = Join-Path $targetedScratch $Name
    $startedAt = [DateTimeOffset]::UtcNow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = @(& $targetedValidator -ChangedPath $Path -Mode $Mode -ScratchRoot $caseScratch -Json) -join "`n"
    $stopwatch.Stop()
    $completedAt = [DateTimeOffset]::UtcNow
    $value = $raw | ConvertFrom-Json
    if ([int]$value.executed_suite_count -lt 1) { throw "Targeted case '$Name' executed no actual module suite." }
    foreach ($suite in $ExpectedSuite) { if (@($value.executed_suites) -notcontains $suite) { throw "Targeted case '$Name' did not execute '$suite'." } }
    foreach ($module in $ExpectedModule) {
        $coverage = @($value.module_coverage | Where-Object module -eq $module)
        if ($coverage.Count -ne 1 -or [int]$coverage[0].executed_check_count -lt 1) { throw "Targeted case '$Name' has no actual check coverage for '$module'." }
        $expectedCoverage = if ($module -eq "documentation") { "base-checks" } else { "targeted-suite" }
        if ([string]$coverage[0].coverage -ne $expectedCoverage) { throw "Targeted case '$Name' used '$($coverage[0].coverage)' coverage for '$module', expected '$expectedCoverage'." }
    }
    if (@($value.checks.name) -contains "skill-metadata" -or @($value.checks.name) -contains "targeted-module-matrix") { throw "Targeted case '$Name' emitted a forbidden empty/generic PASS." }
    $telemetry = @($value.telemetry)
    if ($telemetry.Count -lt 2) { throw "Targeted case '$Name' emitted incomplete suite telemetry." }
    foreach ($record in $telemetry) {
        if ([string]::IsNullOrWhiteSpace([string]$record.suite) -or
            [string]::IsNullOrWhiteSpace([string]$record.case) -or
            [string]::IsNullOrWhiteSpace([string]$record.host) -or
            [string]::IsNullOrWhiteSpace([string]$record.started_at_utc) -or
            [string]::IsNullOrWhiteSpace([string]$record.completed_at_utc) -or
            [long]$record.duration_ms -lt 0 -or
            [string]::IsNullOrWhiteSpace([string]$record.unique_coverage_category)) {
            throw "Targeted case '$Name' emitted an invalid suite telemetry record."
        }
    }
    return [ordered]@{
        name = $Name
        case = $Name
        modules = $ExpectedModule
        suite = $ExpectedSuite
        suites = $ExpectedSuite
        host = [string]$telemetry[0].host
        started_at_utc = $startedAt.ToString("o")
        completed_at_utc = $completedAt.ToString("o")
        duration_ms = [long]$stopwatch.ElapsedMilliseconds
        unique_coverage_category = ("routing-regression:{0}" -f $Name)
        check_count = [int]$value.summary.pass
        status = "PASS"
    }
}

foreach ($case in @($cases)) {
    $raw = if (@($case.paths).Count -eq 0) {
        @(& $validator -BaseRef HEAD -HeadRef HEAD -Json) -join "`n"
    } else {
        @(& $validator -ChangedPath @($case.paths) -Json) -join "`n"
    }
    $value = $raw | ConvertFrom-Json
    & $classifierOutputContract -Result $value | Out-Null
    if ([int]$value.detected_tier -ne [int]$case.tier) { throw "Case '$($case.name)' expected Tier $($case.tier), got Tier $($value.detected_tier)." }
    if ($null -ne $case.full_validator_calls -and [int]$value.hosted_plan.full_validator_calls -ne [int]$case.full_validator_calls) { throw "Case '$($case.name)' has an incorrect hosted full-validator call count." }
    if ($null -ne $case.platform_neutral_validator_calls -and [int]$value.hosted_plan.platform_neutral_validator_calls -ne [int]$case.platform_neutral_validator_calls) { throw "Case '$($case.name)' has an incorrect hosted platform-neutral call count." }
    if ($null -ne $case.runtime_platform_validator_calls -and [int]$value.hosted_plan.runtime_platform_validator_calls -ne [int]$case.runtime_platform_validator_calls) { throw "Case '$($case.name)' has an incorrect hosted runtime-platform call count." }
    if ($null -ne $case.targeted_os_jobs -and [int]$value.hosted_plan.targeted_os_jobs -ne [int]$case.targeted_os_jobs) { throw "Case '$($case.name)' has an incorrect hosted targeted OS job count." }
    if ($null -ne $case.affected_modules) {
        $actualModules = @($value.affected_modules | Sort-Object)
        $expectedModules = @($case.affected_modules | Sort-Object)
        if (($actualModules -join ',') -cne ($expectedModules -join ',')) { throw "Case '$($case.name)' has incorrect affected modules." }
    }
    if ($null -ne $case.required_suites) {
        $actualSuites = @($value.required_suites | Sort-Object)
        $expectedSuites = @($case.required_suites | Sort-Object)
        if (($actualSuites -join ',') -cne ($expectedSuites -join ',')) { throw "Case '$($case.name)' has incorrect required suites." }
    }
    if ($null -ne $case.run_heavy_targeted_regression -and [bool]$value.run_heavy_targeted_regression -ne [bool]$case.run_heavy_targeted_regression) {
        throw "Case '$($case.name)' has an incorrect heavy targeted decision."
    }
    if ($null -ne $case.heavy_targeted_reason -and [string]$value.heavy_targeted_reason -cne [string]$case.heavy_targeted_reason) {
        throw "Case '$($case.name)' has an incorrect heavy targeted reason."
    }
    if ($null -ne $case.conservative_fallback -and [bool]$value.conservative_fallback -ne [bool]$case.conservative_fallback) {
        throw "Case '$($case.name)' has an incorrect conservative fallback decision."
    }
    if ($null -ne $case.validation_self_protection_reason -and [string]$value.validation_self_protection_reason -cne [string]$case.validation_self_protection_reason) {
        throw "Case '$($case.name)' has an incorrect validation self-protection reason."
    }
    foreach ($field in @("required_checks", "skipped_checks")) {
        if ($null -ne $case.$field -and (@($value.$field) -join ',') -cne (@($case.$field) -join ',')) {
            throw "Case '$($case.name)' has an incorrect $field contract."
        }
    }
    if ((@($value.heavy_targeted_required_suites) -join ',') -cne (@($value.full_validator_coverage_suites) -join ',')) {
        throw "Case '$($case.name)' does not prove full coverage for the heavy targeted suite set."
    }
    $text = if (@($case.paths).Count -eq 0) {
        @(& $validator -BaseRef HEAD -HeadRef HEAD) -join "`n"
    } else {
        @(& $validator -ChangedPath @($case.paths)) -join "`n"
    }
    if ($text -notmatch ("Detected tier: Tier {0}" -f $case.tier)) { throw "Text output disagrees for '$($case.name)'." }
    if ($text -notmatch "Skipped checks \(not required; not PASS\):") { throw "Text output does not distinguish skipped checks for '$($case.name)'." }
    foreach ($check in @($value.required_checks)) { if (-not $text.Contains([string]$check)) { throw "Text output omitted required check '$check' for '$($case.name)'." } }
    foreach ($check in @($value.skipped_checks)) { if (-not $text.Contains([string]$check)) { throw "Text output omitted skipped check '$check' for '$($case.name)'." } }
    if (-not $text.Contains([string]$value.escalation_reason)) { throw "Text output omitted the JSON escalation reason for '$($case.name)'." }
    $results.Add([ordered]@{ name = [string]$case.name; tier = [int]$value.detected_tier; status = "PASS" })
}

$invalidRaw = @(& $validator -BaseRef "refs/heads/definitely-missing" -HeadRef HEAD -Json) -join "`n"
$invalid = $invalidRaw | ConvertFrom-Json
if ([int]$invalid.detected_tier -ne 3 -or [string]$invalid.escalation_reason -notmatch "Classification input") { throw "Invalid base ref did not conservatively escalate." }
if ($LASTEXITCODE -ne 0) { throw "Invalid base ref leaked LASTEXITCODE=$LASTEXITCODE instead of returning a clean Tier 3 fallback." }

# Regression: a direct-path Tier 3 classification after the expected invalid-ref
# fallback must also leave a clean native-command exit status.
$directPathRaw = @(
    & $validator `
        -ChangedPath ".github/workflows/release-validation.yml" `
        -Json
) -join "`n"
$directPath = $directPathRaw | ConvertFrom-Json
if ([int]$directPath.detected_tier -ne 3) {
    throw "Direct-path classifier scenario did not produce Tier 3."
}
if ($LASTEXITCODE -ne 0) {
    throw "Direct-path classifier scenario leaked LASTEXITCODE=$LASTEXITCODE."
}

$pushRoutingResults = @(Invoke-PushRoutingFixtures)
$classifierOutputResults = @(Invoke-ClassifierOutputContractFixtures)
$classifierFixtureValues = Get-Content -Raw (Join-Path $PSScriptRoot "validation/release-classifier-output-fixtures/cases.json") | ConvertFrom-Json
$invalidClassifier = $classifierFixtureValues[0].result
$invalidClassifier.required_suites = @("future-unknown-suite")
$invalidClassifier.suite_host_map = [pscustomobject]@{ "future-unknown-suite" = @("windows-latest") }
$invalidClassifier.required_hosts = @("windows-latest")
$rejected = $false
try { & $classifierOutputContract -Result $invalidClassifier | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Classifier output contract accepted an unknown suite." }
$classifierOutputResults += [ordered]@{ name = "unknown-suite-fails-closed"; status = "PASS" }

$invalidHostClassifier = (& $validator -ChangedPath "scripts/install.ps1" -Json | Out-String) | ConvertFrom-Json
$invalidHostClassifier.suite_host_map.'installer-contract' = @("future-host")
$rejected = $false
try { & $classifierOutputContract -Result $invalidHostClassifier | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Classifier output contract accepted an unknown host dependency." }
$classifierOutputResults += [ordered]@{ name = "unknown-host-dependency-fails-closed"; status = "PASS" }
$localPlanRaw = @(& $localPlanValidator -Json) -join "`n"
$localPlanResult = $localPlanRaw | ConvertFrom-Json
if ([int]$localPlanResult.fail -ne 0 -or [int]$localPlanResult.pass -lt 9) { throw "Local validation plan fixtures returned incomplete evidence." }

$workflow = Get-Content -LiteralPath (Join-Path $repoRoot ".github/workflows/release-validation.yml") -Raw
$workflowMarkers = @(
    "needs.classify.outputs.tier == '0'",
    "needs.classify.outputs.tier == '1'",
    "needs.classify.outputs.tier == '2'",
    "needs.classify.outputs.tier == '3'",
    "github.event.before",
    "github.event.forced",
    "needs.classify.outputs.base",
    "needs.classify.outputs.head",
    "needs.classify.outputs.required_hosts_json",
    "needs.classify.outputs.requires_windows_powershell",
    "needs.classify.outputs.run_validation_self_protection",
    "release-classifier-output-contract.ps1 -Result `$result",
    "needs.classify.result != 'success'",
    "./scripts/validate-targeted-change.ps1",
    "./scripts/validate-release.ps1"
)
foreach ($marker in $workflowMarkers) { if (-not $workflow.Contains($marker)) { throw "Hosted routing workflow is missing contract marker: $marker" } }
$classifierContractIndex = $workflow.IndexOf("release-classifier-output-contract.ps1 -Result `$result", [System.StringComparison]::Ordinal)
$firstClassifierOutputIndex = $workflow.IndexOf('"tier=$($result.detected_tier)" >> $env:GITHUB_OUTPUT', [System.StringComparison]::Ordinal)
if ($classifierContractIndex -lt 0 -or $firstClassifierOutputIndex -lt 0 -or $classifierContractIndex -gt $firstClassifierOutputIndex) {
    throw "Classifier schema validation must complete before the first GITHUB_OUTPUT write."
}
$releaseValidatorCallSites = @([regex]::Matches($workflow, "validate-release\.ps1")).Count
if ($releaseValidatorCallSites -ne 3) { throw "Expected one platform-neutral and two runtime/full validator workflow call sites, found $releaseValidatorCallSites." }
foreach ($duplicatedRuleToken in @("knowledge-hub/", "skills/", "docs/releases/", "scripts/install.ps1")) {
    if ($workflow.Contains($duplicatedRuleToken)) { throw "Workflow duplicates a path-routing rule: $duplicatedRuleToken" }
}
if (@([regex]::Matches($workflow, "test-validate-change\.ps1 -Json")).Count -ne 1) { throw "Classifier must have exactly one lightweight classification-test invocation." }
if (@([regex]::Matches($workflow, "test-heavy-targeted-regression\.ps1 -Json")).Count -ne 1) { throw "Hosted control-plane changes must run one independent self-protection oracle." }
if (@([regex]::Matches($workflow, '-BaseRef "\$\{\{ needs\.classify\.outputs\.base \}\}"')).Count -ne 3) { throw "Quick, affected, and WinPS jobs must reuse the classifier base boundary." }
if (@([regex]::Matches($workflow, '-HeadRef "\$\{\{ needs\.classify\.outputs\.head \}\}"')).Count -ne 3) { throw "Quick, affected, and WinPS jobs must reuse the classifier head boundary." }
if (@([regex]::Matches($workflow, "outputs\.run_validation_self_protection != 'false'")).Count -ne 1) { throw "Self-protection job must use the fail-closed classifier decision." }
if (-not $workflow.Contains("fromJSON(needs.classify.outputs.required_hosts_json")) { throw "Affected Hosted execution must use the classifier host matrix." }
if (-not $workflow.Contains('group: ${{ github.workflow }}-${{ github.event_name }}-${{ github.head_ref || github.ref }}') -or -not $workflow.Contains("cancel-in-progress: true")) {
    throw "Hosted concurrency must isolate events while preserving same-event, same-ref cancellation."
}

$unsupported = (& $validator -ChangedPath "skills/removed-skill/SKILL.md" -Json | Out-String) | ConvertFrom-Json
if ([int]$unsupported.detected_tier -ne 3 -or -not [bool]$unsupported.run_heavy_targeted_regression) { throw "Runtime skill without a reliable targeted suite did not fail closed to Tier 3 heavy execution." }
$unmappedTest = (& $validator -ChangedPath "scripts/test-future-runtime.ps1" -Json | Out-String) | ConvertFrom-Json
if ([int]$unmappedTest.detected_tier -ne 3 -or -not [bool]$unmappedTest.run_heavy_targeted_regression) { throw "Unmapped future test path did not fail closed to Tier 3 heavy execution." }

$targetedResults = @()
if ($RunTargetedRegression.IsPresent) {
    $tierZeroRaw = @(& $targetedValidator -ChangedPath "README.md" -Mode quick -ScratchRoot (Join-Path $targetedScratch "tier-zero") -Json) -join "`n"
    $tierZero = $tierZeroRaw | ConvertFrom-Json
    if ([int]$tierZero.executed_suite_count -ne 0 -or @($tierZero.checks.name) -contains "quick-repository-checks") { throw "Tier 0 incorrectly executed heavy or module checks." }
    $targetedResults = @(
        Invoke-TargetedRegression -Name "knowledge" -Path "knowledge-hub/knowledge/catalog.md" -ExpectedModule "knowledge" -ExpectedSuite "knowledge-contracts" -Mode "quick"
        Invoke-TargetedRegression -Name "bootstrap" -Path "skills/project-bootstrap/scripts/bootstrap_project.ps1" -ExpectedModule "bootstrap" -ExpectedSuite "bootstrap-safety" -Mode "targeted"
        Invoke-TargetedRegression -Name "bridge" -Path "scripts/link-agent-skills.ps1" -ExpectedModule "bridge" -ExpectedSuite "agent-skill-bridge" -Mode "targeted"
        Invoke-TargetedRegression -Name "context-gate" -Path "skills/project-context-gate/scripts/context_gate.ps1" -ExpectedModule "context-gate" -ExpectedSuite "project-context-gate" -Mode "targeted"
        Invoke-TargetedRegression -Name "context-gate-check" -Path "scripts/validation/project-context-gate-checks.ps1" -ExpectedModule "context-gate" -ExpectedSuite "project-context-gate" -Mode "targeted"
        Invoke-TargetedRegression -Name "docs-knowledge" -Path @("README.md", "knowledge-hub/knowledge/catalog.md") -ExpectedModule @("documentation", "knowledge") -ExpectedSuite "knowledge-contracts" -Mode "quick"
        Invoke-TargetedRegression -Name "docs-installer" -Path @("README.md", "scripts/install.ps1") -ExpectedModule @("documentation", "installer", "runtime") -ExpectedSuite @("installer-contract", "runtime-smoke") -Mode "targeted"
        Invoke-TargetedRegression -Name "docs-context-gate" -Path @("README.md", "skills/project-context-gate/scripts/context_gate.ps1") -ExpectedModule @("documentation", "context-gate") -ExpectedSuite "project-context-gate" -Mode "targeted"
    )
    $tierZeroText = @(& $targetedValidator -ChangedPath "README.md" -Mode quick -ScratchRoot (Join-Path $targetedScratch "tier-zero-text")) -join "`n"
    if ($tierZeroText -notmatch "0 actual module suites") { throw "Targeted text output disagrees with Tier 0 JSON evidence." }
}

$orderA = (& $validator -ChangedPath @("README.md", "scripts/install.ps1") -Json | Out-String) | ConvertFrom-Json
$orderB = (& $validator -ChangedPath @("scripts/install.ps1", "README.md") -Json | Out-String) | ConvertFrom-Json
if (($orderA | ConvertTo-Json -Depth 8 -Compress) -ne ($orderB | ConvertTo-Json -Depth 8 -Compress)) { throw "Classification depends on input order." }

# Guard: a stale $LASTEXITCODE from an earlier expected native-command failure must not
# leak to the caller.  This check catches regressions of the invalid-base-ref cleanup above.
if ($LASTEXITCODE -ne 0) { throw "Stale LASTEXITCODE=$LASTEXITCODE after all tests passed." }

$summary = [ordered]@{ schema_version = 1; pass = $results.Count + 8 + $pushRoutingResults.Count + $classifierOutputResults.Count + $targetedResults.Count; fail = 0; cases = @($results.ToArray()); push_routing = $pushRoutingResults; classifier_output_contract = $classifierOutputResults; local_plan = $localPlanResult; targeted_regression_executed = $RunTargetedRegression.IsPresent; targeted_execution = $targetedResults; tier_zero_no_heavy_checks = $(if ($RunTargetedRegression.IsPresent) { "PASS" } else { "NOT_RUN" }); unsupported_runtime_skill_escalation = "PASS"; unmapped_test_escalation = "PASS"; text_json_evidence = $(if ($RunTargetedRegression.IsPresent) { "PASS" } else { "NOT_RUN" }); invalid_base_ref = "PASS"; direct_path_classifier = "PASS"; hosted_routing_contract = "PASS"; deterministic_order = "PASS"; lastexitcode_clean = "PASS" }
$summaryJson = $summary | ConvertTo-Json -Depth 8
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Set-Content -LiteralPath $OutputPath -Value $summaryJson -Encoding UTF8
}
if ($Json.IsPresent) { $summaryJson } else { Write-Output ("validate-change fixtures: PASS={0} FAIL=0" -f $summary.pass) }
