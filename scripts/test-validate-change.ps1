[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$RunTargetedRegression
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot "validate-change.ps1"
$cases = Get-Content -LiteralPath (Join-Path $PSScriptRoot "validation/change-risk-fixtures/cases.json") -Raw | ConvertFrom-Json
$results = New-Object 'System.Collections.Generic.List[object]'
$targetedValidator = Join-Path $PSScriptRoot "validate-targeted-change.ps1"
$targetedScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-targeted-regression-{0}" -f ([Guid]::NewGuid().ToString("N")))

function Invoke-TargetedRegression {
    param([string]$Name, [string[]]$Path, [string[]]$ExpectedModule, [string[]]$ExpectedSuite, [string]$Mode)
    $caseScratch = Join-Path $targetedScratch $Name
    $raw = @(& $targetedValidator -ChangedPath $Path -Mode $Mode -ScratchRoot $caseScratch -Json) -join "`n"
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
    return [ordered]@{ name = $Name; modules = $ExpectedModule; suites = $ExpectedSuite; check_count = [int]$value.summary.pass; status = "PASS" }
}

foreach ($case in @($cases)) {
    $raw = if (@($case.paths).Count -eq 0) {
        @(& $validator -BaseRef HEAD -HeadRef HEAD -Json) -join "`n"
    } else {
        @(& $validator -ChangedPath @($case.paths) -Json) -join "`n"
    }
    $value = $raw | ConvertFrom-Json
    if ([int]$value.detected_tier -ne [int]$case.tier) { throw "Case '$($case.name)' expected Tier $($case.tier), got Tier $($value.detected_tier)." }
    if ($null -ne $case.full_validator_calls -and [int]$value.hosted_plan.full_validator_calls -ne [int]$case.full_validator_calls) { throw "Case '$($case.name)' has an incorrect hosted full-validator call count." }
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
# Clean up the stale $LASTEXITCODE left by the expected git failure inside the validator.
# Failing to reset this leaks a non-zero exit code to the caller (e.g. GitHub Actions step)
# even though every test passed, breaking push-only classification runs.
$global:LASTEXITCODE = 0

# Regression: simulate the push-only classify scenario where the test script
# is immediately followed by a -ChangedPath classifier call.  On PRs the
# classifier runs with -BaseRef (which calls successful git commands that
# overwrite $LASTEXITCODE), but on main push only -ChangedPath is used.
# This ensures the stale-code cleanup above prevents a leaked non-zero exit.
$pushLikeRaw = @(
    & $validator `
        -ChangedPath ".github/workflows/release-validation.yml" `
        -Json
) -join "`n"
$pushLike = $pushLikeRaw | ConvertFrom-Json
if ([int]$pushLike.detected_tier -ne 3) {
    throw "Push-like classifier scenario did not produce Tier 3."
}
if ($LASTEXITCODE -ne 0) {
    throw "Push-like classifier scenario leaked LASTEXITCODE=$LASTEXITCODE."
}

$workflow = Get-Content -LiteralPath (Join-Path $repoRoot ".github/workflows/release-validation.yml") -Raw
$workflowMarkers = @(
    "needs.classify.outputs.tier == '0'",
    "needs.classify.outputs.tier == '1'",
    "needs.classify.outputs.tier == '2'",
    "needs.classify.outputs.tier == '3'",
    "github.event_name != 'pull_request'",
    "needs.classify.result != 'success'",
    "./scripts/validate-targeted-change.ps1",
    "./scripts/validate-release.ps1"
)
foreach ($marker in $workflowMarkers) { if (-not $workflow.Contains($marker)) { throw "Hosted routing workflow is missing contract marker: $marker" } }
$fullCallSites = @([regex]::Matches($workflow, "validate-release\.ps1")).Count
if ($fullCallSites -ne 2) { throw "Expected two full-validator workflow call sites, found $fullCallSites." }
foreach ($duplicatedRuleToken in @("knowledge-hub/", "skills/", "docs/releases/", "scripts/install.ps1")) {
    if ($workflow.Contains($duplicatedRuleToken)) { throw "Workflow duplicates a path-routing rule: $duplicatedRuleToken" }
}
if (@([regex]::Matches($workflow, "test-validate-change\.ps1 -Json")).Count -ne 1) { throw "Classifier must have exactly one lightweight classification-test invocation." }
if (@([regex]::Matches($workflow, "test-validate-change\.ps1 -RunTargetedRegression")).Count -ne 2) { throw "Tier 3/full validation jobs must run targeted regressions under both PowerShell hosts." }
if (@([regex]::Matches($workflow, "if: \(github\.event_name != 'pull_request' \|\| needs\.classify\.outputs\.tier == '3'\) && matrix\.os == 'windows-latest'")).Count -ne 1) { throw "PowerShell 7 targeted regressions must be restricted to the Windows Tier 3/main/manual job." }
if (@([regex]::Matches($workflow, "if: github\.event_name != 'pull_request' \|\| needs\.classify\.outputs\.tier == '3'")).Count -ne 1) { throw "Windows PowerShell targeted regressions must be restricted to Tier 3, main, or manual jobs." }
if (@([regex]::Matches($workflow, "matrix\.os == 'windows-latest'")).Count -ne 1) { throw "PowerShell 7 targeted regressions must run once on the Windows full-validation job." }

$unsupported = (& $validator -ChangedPath "skills/removed-skill/SKILL.md" -Json | Out-String) | ConvertFrom-Json
if ([int]$unsupported.detected_tier -ne 3) { throw "Runtime skill without a reliable targeted suite did not escalate to Tier 3." }
$unmappedTest = (& $validator -ChangedPath "scripts/test-future-runtime.ps1" -Json | Out-String) | ConvertFrom-Json
if ([int]$unmappedTest.detected_tier -ne 3) { throw "Unmapped future test path did not conservatively escalate to Tier 3." }

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

$summary = [ordered]@{ schema_version = 1; pass = $results.Count + 7 + $targetedResults.Count; fail = 0; cases = @($results.ToArray()); targeted_regression_executed = $RunTargetedRegression.IsPresent; targeted_execution = $targetedResults; tier_zero_no_heavy_checks = $(if ($RunTargetedRegression.IsPresent) { "PASS" } else { "NOT_RUN" }); unsupported_runtime_skill_escalation = "PASS"; unmapped_test_escalation = "PASS"; text_json_evidence = $(if ($RunTargetedRegression.IsPresent) { "PASS" } else { "NOT_RUN" }); invalid_base_ref = "PASS"; push_like_classifier = "PASS"; hosted_routing_contract = "PASS"; deterministic_order = "PASS"; lastexitcode_clean = "PASS" }
if ($Json.IsPresent) { $summary | ConvertTo-Json -Depth 6 } else { Write-Output ("validate-change fixtures: PASS={0} FAIL=0" -f $summary.pass) }
