# release-eval-report-generator.ps1
# Deterministic eval report generator for eval-driven skill iteration fixtures.
# Reads evals.json + expected.json, validates shape, and computes report.json content.
# No eval runner, LLM calls, or network access. Part of the release validator ecosystem.

<#
.SYNOPSIS
    New-EvalReportArtifact
    Computes a deterministic eval report artifact from evals.json and expected.json.
.PARAMETER EvalsJsonPath
    Absolute path to evals.json.
.PARAMETER ExpectedJsonPath
    Absolute path to expected.json.
#>
function New-EvalReportArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$EvalsJsonPath,
        [Parameter(Mandatory = $true)][string]$ExpectedJsonPath
    )

    # Read and parse evals.json
    if (-not [System.IO.File]::Exists($EvalsJsonPath)) {
        throw "evals.json not found: $EvalsJsonPath"
    }
    $evalsContent = [System.IO.File]::ReadAllText($EvalsJsonPath) | ConvertFrom-Json

    # Read and parse expected.json
    if (-not [System.IO.File]::Exists($ExpectedJsonPath)) {
        throw "expected.json not found: $ExpectedJsonPath"
    }
    $expectedContent = [System.IO.File]::ReadAllText($ExpectedJsonPath) | ConvertFrom-Json

    # Validate evals.json has required top-level fields
    foreach ($field in @("skill", "version", "evals")) {
        if ($null -eq $evalsContent.$field) {
            throw "evals.json is missing required top-level field: $field"
        }
    }

    $skill = [string]$evalsContent.skill
    $version = [int]$evalsContent.version
    $evalCases = @($evalsContent.evals)

    if ($evalCases.Count -lt 1) {
        throw "evals.json must contain at least one eval case."
    }

    # Validate expected.json required fields
    foreach ($field in @("expected_eval_count", "expected_assertion_count", "expected_eval_ids", "schema_validation")) {
        if ($null -eq $expectedContent.$field) {
            throw "expected.json is missing required field: $field"
        }
    }
    if ($null -eq $expectedContent.schema_validation.allowed_assertion_types) {
        throw "expected.json is missing schema_validation.allowed_assertion_types."
    }

    $allowedTypes = @($expectedContent.schema_validation.allowed_assertion_types | ForEach-Object { [string]$_ })

    # Validate and count each eval case
    $evalResults = New-Object 'System.Collections.Generic.List[object]'
    $totalAssertions = 0
    $totalPassed = 0
    $totalFailed = 0
    $evalsPassed = 0
    $evalsFailed = 0
    $evalIds = New-Object 'System.Collections.Generic.List[string]'

    foreach ($evalCase in $evalCases) {
        # Validate required fields
        foreach ($field in @("id", "input", "assertions")) {
            if ($null -eq $evalCase.$field) {
                throw "Eval case is missing required field: $field"
            }
        }

        $evalId = [string]$evalCase.id
        $evalIds.Add($evalId)
        $caseAssertions = @($evalCase.assertions)
        $assertionCount = $caseAssertions.Count

        if ($assertionCount -lt 1) {
            throw "Eval case '$evalId' has no assertions."
        }

        # Validate assertion types
        foreach ($assertion in $caseAssertions) {
            if ($null -eq $assertion.type -or $null -eq $assertion.expected) {
                throw "Assertion in eval case '$evalId' is missing 'type' or 'expected'."
            }
            if ([string]$assertion.type -notin $allowedTypes) {
                throw "Assertion type '$($assertion.type)' in eval case '$evalId' is not in the allowed enum."
            }
        }

        # Deterministic: fixture-based evals with valid structure are PASS
        $evalResults.Add([ordered]@{
            eval_id = $evalId
            status = "PASS"
            assertions_total = $assertionCount
            assertions_passed = $assertionCount
            assertions_failed = 0
        })

        $totalAssertions += $assertionCount
        $totalPassed += $assertionCount
        $evalsPassed++
    }

    # Cross-validate with expected.json
    $expectedIds = @($expectedContent.expected_eval_ids | ForEach-Object { [string]$_ })
    $sortedActual = @($evalIds.ToArray() | Sort-Object)
    $sortedExpected = @($expectedIds | Sort-Object)
    if ($sortedActual.Count -ne $sortedExpected.Count) {
        throw "Eval count mismatch: expected $($sortedExpected.Count), got $($sortedActual.Count)."
    }
    for ($i = 0; $i -lt $sortedActual.Count; $i++) {
        if ($sortedActual[$i] -ne $sortedExpected[$i]) {
            throw "Eval ID mismatch at index ${i}: expected '$($sortedExpected[$i])', got '$($sortedActual[$i])'."
        }
    }
    if ($evalCases.Count -ne [int]$expectedContent.expected_eval_count) {
        throw "Eval count mismatch: expected $($expectedContent.expected_eval_count), got $($evalCases.Count)."
    }
    if ($totalAssertions -ne [int]$expectedContent.expected_assertion_count) {
        throw "Assertion count mismatch: expected $($expectedContent.expected_assertion_count), got $totalAssertions."
    }

    # Build report artifact with deterministic key ordering matching committed report.json
    return [ordered]@{
        skill = $skill
        version = $version
        fixture = $skill
        report_type = "static"
        description = "Deterministic static eval report artifact for $skill. This file represents the expected report shape; no eval runner or LLM is invoked."
        eval_results = @($evalResults.ToArray())
        failure_reason_shape = [ordered]@{
            description = "When an assertion fails, the finding includes these fields."
            example = [ordered]@{
                eval_id = "<eval-case-id>"
                assertion_type = "<assertion-type>"
                expected = "<expected-value>"
                actual = "<actual-value>"
            }
        }
        summary = [ordered]@{
            eval_count = $evalCases.Count
            evals_passed = $evalsPassed
            evals_failed = $evalsFailed
            assertions_total = $totalAssertions
            assertions_passed = $totalPassed
            assertions_failed = $totalFailed
            status = "PASS"
        }
    }
}

<#
.SYNOPSIS
    Test-EvalReportRegeneration
    Verifies that the committed report.json is deterministically reproducible
    from evals.json and expected.json. Returns regeneration evidence.
.PARAMETER EvalsJsonPath
    Absolute path to evals.json.
.PARAMETER ExpectedJsonPath
    Absolute path to expected.json.
.PARAMETER CommittedReportPath
    Absolute path to the committed report.json.
#>
function Test-EvalReportRegeneration {
    param(
        [Parameter(Mandatory = $true)][string]$EvalsJsonPath,
        [Parameter(Mandatory = $true)][string]$ExpectedJsonPath,
        [Parameter(Mandatory = $true)][string]$CommittedReportPath
    )

    # Generate the report from source fixtures
    $generated = New-EvalReportArtifact -EvalsJsonPath $EvalsJsonPath -ExpectedJsonPath $ExpectedJsonPath

    # Read committed report
    if (-not [System.IO.File]::Exists($CommittedReportPath)) {
        throw "Committed report.json not found: $CommittedReportPath"
    }
    $committed = [System.IO.File]::ReadAllText($CommittedReportPath) | ConvertFrom-Json

    # Deterministic key-by-key comparison using JSON serialization for nested objects
    $generatedJson = $generated | ConvertTo-Json -Depth 10 -Compress
    $committedJson = $committed | ConvertTo-Json -Depth 10 -Compress

    if ($generatedJson -ne $committedJson) {
        throw "Regeneration mismatch: generated report does not match committed report.json."
    }

    return [ordered]@{
        generated_eval_count = @($generated.eval_results).Count
        generated_assertion_count = [int]$generated.summary.assertions_total
        generated_status = [string]$generated.summary.status
        match = $true
    }
}
