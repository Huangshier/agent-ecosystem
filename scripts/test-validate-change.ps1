[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot "validate-change.ps1"
$cases = Get-Content -LiteralPath (Join-Path $PSScriptRoot "validation/change-risk-fixtures/cases.json") -Raw | ConvertFrom-Json
$results = New-Object 'System.Collections.Generic.List[object]'
$targetedValidator = Join-Path $PSScriptRoot "validate-targeted-change.ps1"
$targetedScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-targeted-regression-{0}" -f ([Guid]::NewGuid().ToString("N")))

function Invoke-TargetedRegression {
    param([string]$Name, [string]$Path, [string]$ExpectedModule, [string]$ExpectedSuite, [string]$Mode)
    $caseScratch = Join-Path $targetedScratch $Name
    $raw = @(& $targetedValidator -ChangedPath $Path -Mode $Mode -ScratchRoot $caseScratch -Json) -join "`n"
    $value = $raw | ConvertFrom-Json
    if ([int]$value.executed_suite_count -lt 1) { throw "Targeted case '$Name' executed no actual module suite." }
    if (@($value.executed_suites) -notcontains $ExpectedSuite) { throw "Targeted case '$Name' did not execute '$ExpectedSuite'." }
    $coverage = @($value.module_coverage | Where-Object module -eq $ExpectedModule)
    if ($coverage.Count -ne 1 -or [int]$coverage[0].executed_check_count -lt 1) { throw "Targeted case '$Name' has no actual check coverage for '$ExpectedModule'." }
    if (@($value.checks.name) -contains "skill-metadata" -or @($value.checks.name) -contains "targeted-module-matrix") { throw "Targeted case '$Name' emitted a forbidden empty/generic PASS." }
    return [ordered]@{ name = $Name; module = $ExpectedModule; suite = $ExpectedSuite; check_count = [int]$value.summary.pass; status = "PASS" }
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

$tierZeroRaw = @(& $targetedValidator -ChangedPath "README.md" -Mode quick -ScratchRoot (Join-Path $targetedScratch "tier-zero") -Json) -join "`n"
$tierZero = $tierZeroRaw | ConvertFrom-Json
if ([int]$tierZero.executed_suite_count -ne 0 -or @($tierZero.checks.name) -contains "quick-repository-checks") { throw "Tier 0 incorrectly executed heavy or module checks." }
$targetedResults = @(
    Invoke-TargetedRegression -Name "knowledge" -Path "knowledge-hub/knowledge/catalog.md" -ExpectedModule "knowledge" -ExpectedSuite "knowledge-contracts" -Mode "quick"
    Invoke-TargetedRegression -Name "bootstrap" -Path "skills/project-bootstrap/scripts/bootstrap_project.ps1" -ExpectedModule "bootstrap" -ExpectedSuite "bootstrap-safety" -Mode "targeted"
    Invoke-TargetedRegression -Name "bridge" -Path "scripts/link-agent-skills.ps1" -ExpectedModule "bridge" -ExpectedSuite "agent-skill-bridge" -Mode "targeted"
)
$unsupported = (& $validator -ChangedPath "skills/project-context-gate/scripts/runtime.ps1" -Json | Out-String) | ConvertFrom-Json
if ([int]$unsupported.detected_tier -ne 3) { throw "Runtime skill without a reliable targeted suite did not escalate to Tier 3." }
$tierZeroText = @(& $targetedValidator -ChangedPath "README.md" -Mode quick -ScratchRoot (Join-Path $targetedScratch "tier-zero-text")) -join "`n"
if ($tierZeroText -notmatch "0 actual module suites") { throw "Targeted text output disagrees with Tier 0 JSON evidence." }

$orderA = (& $validator -ChangedPath @("README.md", "scripts/install.ps1") -Json | Out-String) | ConvertFrom-Json
$orderB = (& $validator -ChangedPath @("scripts/install.ps1", "README.md") -Json | Out-String) | ConvertFrom-Json
if (($orderA | ConvertTo-Json -Depth 8 -Compress) -ne ($orderB | ConvertTo-Json -Depth 8 -Compress)) { throw "Classification depends on input order." }

$summary = [ordered]@{ schema_version = 1; pass = $results.Count + 8; fail = 0; cases = @($results.ToArray()); targeted_execution = $targetedResults; tier_zero_no_heavy_checks = "PASS"; unsupported_runtime_skill_escalation = "PASS"; text_json_evidence = "PASS"; invalid_base_ref = "PASS"; hosted_routing_contract = "PASS"; deterministic_order = "PASS" }
if ($Json.IsPresent) { $summary | ConvertTo-Json -Depth 6 } else { Write-Output ("validate-change fixtures: PASS={0} FAIL=0" -f $summary.pass) }
