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
<#
.SYNOPSIS
    Compare-EvalReportFields
    Compares generated and committed report objects field-by-field.
    Returns $true if all fields match, throws on first mismatch.
    Uses structured field comparison (not JSON string comparison) to avoid
    property-order sensitivity across PowerShell versions.
.PARAMETER Generated
    Generated report object from New-EvalReportArtifact.
.PARAMETER Committed
    Committed report object parsed from report.json.
#>
function Compare-EvalReportFields {
    param(
        [Parameter(Mandatory = $true)]$Generated,
        [Parameter(Mandatory = $true)]$Committed
    )

    # Scalar top-level fields
    foreach ($field in @("skill", "version", "fixture", "report_type", "description")) {
        if ([string]$Generated.$field -ne [string]$Committed.$field) {
            throw "Regeneration mismatch on field '$field': generated='$($Generated.$field)', committed='$($Committed.$field)'."
        }
    }

    # eval_results array: compare count, then each entry by eval_id
    $genResults = @($Generated.eval_results)
    $comResults = @($Committed.eval_results)
    if ($genResults.Count -ne $comResults.Count) {
        throw "Regeneration mismatch: eval_results count differs (generated=$($genResults.Count), committed=$($comResults.Count))."
    }
    $comById = @{}
    foreach ($r in $comResults) { $comById[[string]$r.eval_id] = $r }
    foreach ($gen in $genResults) {
        $evalId = [string]$gen.eval_id
        $com = $comById[$evalId]
        if ($null -eq $com) {
            throw "Regeneration mismatch: eval_id '$evalId' present in generated but missing from committed."
        }
        foreach ($f in @("status", "assertions_total", "assertions_passed", "assertions_failed")) {
            if ([string]$gen.$f -ne [string]$com.$f) {
                throw "Regeneration mismatch on eval '${evalId}' field '${f}': generated='$($gen.${f})', committed='$($com.${f})'."
            }
        }
    }

    # failure_reason_shape: compare example fields by name
    $genExample = $Generated.failure_reason_shape.example
    $comExample = $Committed.failure_reason_shape.example
    foreach ($f in @("eval_id", "assertion_type", "expected", "actual")) {
        if ([string]$genExample.$f -ne [string]$comExample.$f) {
            throw "Regeneration mismatch on failure_reason_shape.example.$f."
        }
    }

    # summary: compare all fields
    foreach ($f in @("eval_count", "evals_passed", "evals_failed", "assertions_total", "assertions_passed", "assertions_failed", "status")) {
        if ([string]$Generated.summary.$f -ne [string]$Committed.summary.$f) {
            throw "Regeneration mismatch on summary field '${f}': generated='$($Generated.summary.${f})', committed='$($Committed.summary.${f})'."
        }
    }

    return $true
}

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

    # Structured field-by-field comparison (deterministic across PS versions)
    [void](Compare-EvalReportFields -Generated $generated -Committed $committed)

    return [ordered]@{
        generated_eval_count = @($generated.eval_results).Count
        generated_assertion_count = [int]$generated.summary.assertions_total
        generated_status = [string]$generated.summary.status
        match = $true
    }
}

<#
.SYNOPSIS
    Direct invocation entry point.
    When invoked with -File and -EvalsJsonPath / -ExpectedJsonPath,
    generates the eval report artifact and writes JSON to stdout.
    When dot-sourced (InvocationName is '.'), does nothing.
#>
$isDirectInvocation = $MyInvocation.InvocationName -ne '.'
if ($isDirectInvocation) {
    # Parse named arguments from $args (safe: dot-source sets InvocationName to '.')
    $evalsPath = ""
    $expectedPath = ""
    for ($ai = 0; $ai -lt $args.Count; $ai++) {
        if ($args[$ai] -eq '-EvalsJsonPath' -and ($ai + 1) -lt $args.Count) {
            $evalsPath = [string]$args[$ai + 1]; $ai++
        }
        elseif ($args[$ai] -eq '-ExpectedJsonPath' -and ($ai + 1) -lt $args.Count) {
            $expectedPath = [string]$args[$ai + 1]; $ai++
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($evalsPath) -and -not [string]::IsNullOrWhiteSpace($expectedPath)) {
        # Resolve relative paths against caller's working directory
        if (-not [System.IO.Path]::IsPathRooted($evalsPath)) {
            $evalsPath = [System.IO.Path]::GetFullPath((Join-Path $PWD $evalsPath))
        }
        if (-not [System.IO.Path]::IsPathRooted($expectedPath)) {
            $expectedPath = [System.IO.Path]::GetFullPath((Join-Path $PWD $expectedPath))
        }

        $report = New-EvalReportArtifact -EvalsJsonPath $evalsPath -ExpectedJsonPath $expectedPath
        $report | ConvertTo-Json -Depth 10
    }
    else {
        Write-Error "Direct invocation requires -EvalsJsonPath and -ExpectedJsonPath."
    }
}
