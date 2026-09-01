[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$gate = Join-Path $PSScriptRoot "validation/required-validation-gate.ps1"
$fixturePath = Join-Path $PSScriptRoot "validation/required-validation-gate-fixtures/cases.json"
$workflowPath = Join-Path $repoRoot ".github/workflows/release-validation.yml"
$cases = @((Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
$results = New-Object 'System.Collections.Generic.List[object]'

function Get-GateFixtureArguments {
    param([object]$Case)

    return @{
        EventName = [string]$Case.event_name
        Tier = [string]$Case.tier
        ClassifyResult = [string]$Case.classify
        QuickResult = [string]$Case.quick
        TargetedResult = [string]$Case.targeted
        SelfProtectionResult = [string]$Case.self_protection
        SelfProtectionRequired = [string]$Case.self_protection_required
        MainHealthResult = if ($Case.PSObject.Properties.Name -contains "main_health") {
            [string]$Case.main_health
        }
        elseif ([string]$Case.event_name -ceq "push") {
            "success"
        }
        else {
            "skipped"
        }
        PlatformNeutralResult = [string]$Case.platform_neutral
        PwshMatrixResult = [string]$Case.pwsh_matrix
        Json = $true
    }
}

foreach ($case in $cases) {
    $arguments = Get-GateFixtureArguments -Case $case
    $passed = $false
    $failure = ""
    try {
        $raw = @(& $gate @arguments) -join "`n"
        $value = $raw | ConvertFrom-Json
        if ([string]$value.status -cne "PASS") {
            throw "Gate returned status '$($value.status)'."
        }
        $passed = $true
    }
    catch {
        $failure = $_.Exception.Message
    }

    if ([bool]$case.should_pass -ne $passed) {
        throw "Fixture '$($case.name)' expected should_pass=$($case.should_pass), observed pass=$passed. $failure"
    }
    $results.Add([ordered]@{ name = [string]$case.name; expected = $(if ([bool]$case.should_pass) { "PASS" } else { "FAIL" }); status = "PASS" })
}

$workflow = Get-Content -LiteralPath $workflowPath -Raw
$jobMatch = [regex]::Match($workflow, '(?ms)^  validation-gate:\s*\r?\n(?<body>.*?)(?=^  [a-zA-Z0-9_-]+:\s*\r?$|\z)')
if (-not $jobMatch.Success) { throw "Workflow is missing the validation-gate job." }
$job = $jobMatch.Groups['body'].Value
foreach ($marker in @(
    "name: validation gate",
    "if: always()",
    'EVENT_NAME: ${{ github.event_name }}',
    'TIER: ${{ needs.classify.outputs.tier }}',
    'MAIN_HEALTH_RESULT: ${{ needs.main-health.result }}',
    "./scripts/validation/required-validation-gate.ps1"
)) {
    if (-not $job.Contains($marker)) { throw "validation-gate job is missing contract marker: $marker" }
}
$needsMatch = [regex]::Match($job, '(?ms)^    needs:\s*\r?\n(?<body>(?:      - [^\r\n]+\r?\n)+)')
if (-not $needsMatch.Success) { throw "validation-gate job is missing its needs list." }
$actualNeeds = @([regex]::Matches($needsMatch.Groups['body'].Value, '(?m)^      - (?<name>[^\r\n]+)$') | ForEach-Object { $_.Groups['name'].Value })
$expectedNeeds = @("classify", "quick-validation", "targeted-validation", "validation-self-protection", "validate-platform-neutral", "validate", "main-health")
if (($actualNeeds -join ',') -cne ($expectedNeeds -join ',')) {
    throw "validation-gate needs must be exactly: $($expectedNeeds -join ', ')."
}
if ($job -match '(?m)^\s+matrix:') { throw "validation-gate must not use a matrix." }
if (@([regex]::Matches($job, '(?m)^\s+name: validation gate\s*$')).Count -ne 1) { throw "validation-gate must expose exactly one fixed check name." }
if (@([regex]::Matches($job, '(?m)^\s+if: always\(\)\s*$')).Count -ne 1) { throw "validation-gate must use exactly one unconditional always() job guard." }

$mainHealthJobMatch = [regex]::Match($workflow, '(?ms)^  main-health:\s*\r?\n(?<body>.*?)(?=^  [a-zA-Z0-9_-]+:\s*\r?$|\z)')
if (-not $mainHealthJobMatch.Success) { throw "Workflow is missing the main-health job." }
$mainHealthJob = $mainHealthJobMatch.Groups['body'].Value
if (-not $mainHealthJob.Contains("name: main health") -or
    -not $mainHealthJob.Contains("needs: classify") -or
    -not $mainHealthJob.Contains("if: always() && (github.event_name == 'push' || (github.event_name == 'pull_request' && contains(needs.classify.outputs.modules, 'validation-routing')))") -or
    -not $mainHealthJob.Contains("scripts/validate-main-health.ps1")) {
    throw "main-health job does not expose the thin push and validation-routing health contract."
}

# Weakening fixture: a gate that stops requiring self-protection success must be
# rejected by the fixed fixture corpus above. The mutation weakens a scratch copy of
# the gate and proves the corpus case "self-protection-missing" (should_pass=false)
# would pass against it, so the corpus fails closed on this weakening.
$weakeningRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-gate-weakening-{0}" -f ([Guid]::NewGuid().ToString("N")))
try {
    New-Item -ItemType Directory -Force -Path $weakeningRoot | Out-Null
    $gateSource = Get-Content -LiteralPath $gate -Raw
    $selfProtectionRequirement = 'if ($SelfProtectionRequired -ceq "true" -and $EventName -ceq "pull_request") { "success" } else { "skipped" }'
    if (-not $gateSource.Contains($selfProtectionRequirement)) {
        throw "Gate weakening fixture cannot find the required self-protection contract condition."
    }
    $weakenedGatePath = Join-Path $weakeningRoot "required-validation-gate-weakened.ps1"
    Set-Content -LiteralPath $weakenedGatePath -Value $gateSource.Replace($selfProtectionRequirement, '"skipped"') -Encoding UTF8
    $missingProtectionCase = @($cases | Where-Object { [string]$_.name -ceq "self-protection-missing" })[0]
    if ($null -eq $missingProtectionCase) {
        throw "Gate fixture corpus is missing the self-protection-missing case."
    }
    $weakenedArguments = Get-GateFixtureArguments -Case $missingProtectionCase
    $weakenedPassed = $false
    try {
        $weakenedRaw = @(& $weakenedGatePath @weakenedArguments) -join "`n"
        $weakenedValue = $weakenedRaw | ConvertFrom-Json
        if ([string]$weakenedValue.status -ceq "PASS") { $weakenedPassed = $true }
    }
    catch { }
    if (-not $weakenedPassed) {
        throw "Weakened gate still rejected the missing self-protection case; weakening detection cannot be proven."
    }
    $results.Add([ordered]@{ name = "gate-self-protection-requirement-weakening-detected"; expected = "FAIL"; status = "PASS" }) | Out-Null
}
finally {
    if (Test-Path -LiteralPath $weakeningRoot) { Remove-Item -LiteralPath $weakeningRoot -Recurse -Force }
}

$summary = [ordered]@{
    schema_version = 1
    pass = $results.Count + 6
    fail = 0
    cases = @($results.ToArray())
    workflow_job_name = "PASS"
    workflow_always = "PASS"
    workflow_needs = "PASS"
    workflow_no_matrix = "PASS"
    workflow_main_health = "PASS"
    gate_weakening_detected = "PASS"
}
if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 5
}
else {
    Write-Output ("required-validation-gate fixtures: PASS={0} FAIL=0" -f $summary.pass)
}
