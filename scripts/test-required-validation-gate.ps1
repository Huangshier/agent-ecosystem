[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$gate = Join-Path $PSScriptRoot "validation/required-validation-gate.ps1"
$fixturePath = Join-Path $PSScriptRoot "validation/required-validation-gate-fixtures/cases.json"
$workflowPath = Join-Path $repoRoot ".github/workflows/release-validation.yml"
$cases = @((Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
$results = New-Object 'System.Collections.Generic.List[object]'

foreach ($case in $cases) {
    $arguments = @{
        EventName = [string]$case.event_name
        Tier = [string]$case.tier
        ClassifyResult = [string]$case.classify
        QuickResult = [string]$case.quick
        TargetedResult = [string]$case.targeted
        PlatformNeutralResult = [string]$case.platform_neutral
        PwshMatrixResult = [string]$case.pwsh_matrix
        WindowsPowerShellResult = [string]$case.windows_powershell
        Json = $true
    }
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
    "./scripts/validation/required-validation-gate.ps1"
)) {
    if (-not $job.Contains($marker)) { throw "validation-gate job is missing contract marker: $marker" }
}
$needsMatch = [regex]::Match($job, '(?ms)^    needs:\s*\r?\n(?<body>(?:      - [^\r\n]+\r?\n)+)')
if (-not $needsMatch.Success) { throw "validation-gate job is missing its needs list." }
$actualNeeds = @([regex]::Matches($needsMatch.Groups['body'].Value, '(?m)^      - (?<name>[^\r\n]+)$') | ForEach-Object { $_.Groups['name'].Value })
$expectedNeeds = @("classify", "quick-validation", "targeted-validation", "validate-platform-neutral", "validate", "validate-windows-powershell")
if (($actualNeeds -join ',') -cne ($expectedNeeds -join ',')) {
    throw "validation-gate needs must be exactly: $($expectedNeeds -join ', ')."
}
if ($job -match '(?m)^\s+matrix:') { throw "validation-gate must not use a matrix." }
if (@([regex]::Matches($job, '(?m)^\s+name: validation gate\s*$')).Count -ne 1) { throw "validation-gate must expose exactly one fixed check name." }
if (@([regex]::Matches($job, '(?m)^\s+if: always\(\)\s*$')).Count -ne 1) { throw "validation-gate must use exactly one unconditional always() job guard." }

$summary = [ordered]@{
    schema_version = 1
    pass = $results.Count + 4
    fail = 0
    cases = @($results.ToArray())
    workflow_job_name = "PASS"
    workflow_always = "PASS"
    workflow_needs = "PASS"
    workflow_no_matrix = "PASS"
}
if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 5
}
else {
    Write-Output ("required-validation-gate fixtures: PASS={0} FAIL=0" -f $summary.pass)
}
