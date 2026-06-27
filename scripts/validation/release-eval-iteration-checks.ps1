# release-eval-iteration-checks.ps1
# Contains validation checks for eval iteration fixtures, report artifact, and baseline recording artifact.
# Part of the release validator thin-entrypoint refactor.
# Authoritative check names: "eval iteration fixtures", "eval report artifact", "eval baseline artifact".

<#
.SYNOPSIS
    Invoke-ReleaseEvalIterationChecks
    Validates eval iteration fixture suite, report artifact shape, and baseline recording artifact.
.PARAMETER RepositoryRoot
    Absolute path to the repository root.
.PARAMETER ScratchRootFull
    Absolute path to the scratch root directory.
#>
function Invoke-ReleaseEvalIterationChecks {
    param(
        [string]$RepositoryRoot,
        [string]$ScratchRootFull
    )

    # Slice 1: eval iteration fixture checks
    try {
        $evalFixtureRoot = Join-PathParts $RepositoryRoot "scripts" "validation" "eval-iteration-fixtures"
        $evalReadme = Get-FileText -RelativePath "scripts/validation/eval-iteration-fixtures/README.md"
        foreach ($token in @("workflow-spec-lite", "Eval Iteration Fixtures", "evals.json", "expected.json", "trigger-accuracy", "safety-boundary", "Non-Goals")) {
            if (-not $evalReadme.Contains($token)) {
                throw "Eval iteration fixture README is missing token: $token"
            }
        }

        $evalsJsonPath = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "evals.json"
        if (-not (Test-Path -LiteralPath $evalsJsonPath)) {
            throw "Missing workflow-spec-lite/evals.json."
        }
        $evalsContent = Get-Content -LiteralPath $evalsJsonPath -Raw | ConvertFrom-Json
        if ([string]$evalsContent.skill -ne "workflow-spec-lite") {
            throw "evals.json skill field must be 'workflow-spec-lite', got: $($evalsContent.skill)"
        }
        foreach ($field in @("skill", "version", "evals")) {
            if ($null -eq $evalsContent.$field) {
                throw "evals.json is missing required top-level field: $field"
            }
        }
        $evalCases = @($evalsContent.evals)
        if ($evalCases.Count -lt 1) {
            throw "evals.json must contain at least one eval case."
        }
        $allowedTypes = @("skill_should_trigger", "skill_should_not_trigger", "output_contains", "output_not_contains", "output_exact_match", "output_regex", "output_token_count_below", "output_file_created", "output_file_not_created")
        $totalAssertions = 0
        foreach ($evalCase in $evalCases) {
            foreach ($field in @("id", "input", "assertions")) {
                if ($null -eq $evalCase.$field) {
                    throw "Eval case is missing required field: $field"
                }
            }
            $caseAssertions = @($evalCase.assertions)
            $totalAssertions += $caseAssertions.Count
            foreach ($assertion in $caseAssertions) {
                if ($null -eq $assertion.type -or $null -eq $assertion.expected) {
                    throw "Assertion in eval case '$($evalCase.id)' is missing 'type' or 'expected'."
                }
                if ([string]$assertion.type -notin $allowedTypes) {
                    throw "Assertion type '$($assertion.type)' is not in the allowed enum."
                }
            }
        }

        $expectedPath = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "expected.json"
        $expectedContent = Get-Content -LiteralPath $expectedPath -Raw | ConvertFrom-Json
        if ([string]$expectedContent.fixture -ne "workflow-spec-lite") {
            throw "Eval fixture expected.json fixture name mismatch."
        }
        if ([string]$expectedContent.family -ne "eval-iteration") {
            throw "Eval fixture expected.json family mismatch."
        }
        if ([string]$expectedContent.role -ne "positive") {
            throw "Eval fixture expected.json role mismatch."
        }
        if ($evalCases.Count -ne [int]$expectedContent.expected_eval_count) {
            throw "Eval case count mismatch: expected $($expectedContent.expected_eval_count), got $($evalCases.Count)."
        }
        if ($totalAssertions -ne [int]$expectedContent.expected_assertion_count) {
            throw "Assertion count mismatch: expected $($expectedContent.expected_assertion_count), got $totalAssertions."
        }
        $expectedEvalIds = @($expectedContent.expected_eval_ids | ForEach-Object { [string]$_ })
        $actualEvalIds = @($evalCases | ForEach-Object { [string]$_.id })
        if (-not (Test-ExactArray -Actual $actualEvalIds -Expected $expectedEvalIds)) {
            throw "Eval ID mismatch. Expected: $($expectedEvalIds -join ', '). Actual: $($actualEvalIds -join ', ')."
        }
        foreach ($readmeToken in @($expectedContent.required_readme_tokens | ForEach-Object { [string]$_ })) {
            if (-not $evalReadme.Contains($readmeToken)) {
                throw "Eval README is missing expected token: $readmeToken"
            }
        }

        $script:evidence.eval_iteration_fixtures = [ordered]@{
            family = "eval-iteration"
            fixture = "workflow-spec-lite"
            skill = [string]$evalsContent.skill
            eval_count = $evalCases.Count
            assertion_count = $totalAssertions
            allowed_types = @($allowedTypes)
        }
        Add-Check "eval iteration fixtures" "PASS" "Workflow-spec-lite eval pilot fixture is public-safe, JSON-valid, and conforms to the evals schema shape." $evidence.eval_iteration_fixtures
    }
    catch {
        Add-Check "eval iteration fixtures" "FAIL" $_.Exception.Message
    }

    # Slice 2: verify eval report artifact shape
    try {
        $reportPath = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "report.json"
        if (-not (Test-Path -LiteralPath $reportPath)) {
            throw "Missing workflow-spec-lite/report.json."
        }
        $reportContent = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json

        foreach ($field in @("skill", "version", "fixture", "report_type", "eval_results", "failure_reason_shape", "summary")) {
            if ($null -eq $reportContent.$field) {
                throw "report.json is missing required top-level field: $field"
            }
        }
        if ([string]$reportContent.report_type -ne "static") {
            throw "report.json report_type must be 'static', got: $($reportContent.report_type)"
        }

        $reportResults = @($reportContent.eval_results)
        foreach ($result in $reportResults) {
            foreach ($field in @("eval_id", "status", "assertions_total", "assertions_passed", "assertions_failed")) {
                if ($null -eq $result.$field) {
                    throw "report.json eval_result is missing required field: $field"
                }
            }
        }

        # Verify eval IDs match evals.json
        $reportEvalIds = @($reportResults | ForEach-Object { [string]$_.eval_id })
        if (-not (Test-ExactArray -Actual $reportEvalIds -Expected $expectedEvalIds)) {
            throw "Report eval ID mismatch. Expected: $($expectedEvalIds -join ', '). Actual: $($reportEvalIds -join ', ')."
        }

        # Verify failure_reason_shape contains required example fields
        $failureExample = $reportContent.failure_reason_shape.example
        foreach ($field in @("eval_id", "assertion_type", "expected", "actual")) {
            if ($null -eq $failureExample.$field) {
                throw "report.json failure_reason_shape.example is missing required field: $field"
            }
        }

        # Verify summary totals are consistent
        $summary = $reportContent.summary
        foreach ($field in @("eval_count", "evals_passed", "evals_failed", "assertions_total", "assertions_passed", "assertions_failed", "status")) {
            if ($null -eq $summary.$field) {
                throw "report.json summary is missing required field: $field"
            }
        }
        $totalReportAssertions = 0
        $totalReportAssertionsPassed = 0
        foreach ($result in $reportResults) {
            $totalReportAssertions += [int]$result.assertions_total
            $totalReportAssertionsPassed += [int]$result.assertions_passed
        }
        if ([int]$summary.eval_count -ne $reportResults.Count) {
            throw "report.json summary.eval_count ($($summary.eval_count)) does not match eval_results count ($($reportResults.Count))."
        }
        if ([int]$summary.assertions_total -ne $totalReportAssertions) {
            throw "report.json summary.assertions_total ($($summary.assertions_total)) does not match sum of eval_results ($totalReportAssertions)."
        }
        if ([int]$summary.assertions_passed -ne $totalReportAssertionsPassed) {
            throw "report.json summary.assertions_passed ($($summary.assertions_passed)) does not match sum of eval_results ($totalReportAssertionsPassed)."
        }
        if ([int]$summary.assertions_total -ne $totalAssertions) {
            throw "report.json summary.assertions_total ($($summary.assertions_total)) does not match evals.json assertion count ($totalAssertions)."
        }

        # Verify PASS/FAIL status semantics
        $allowedStatuses = @("PASS", "FAIL")
        $evalsPassedCount = 0
        $evalsFailedCount = 0
        $totalReportAssertionsFailed = 0
        foreach ($result in $reportResults) {
            if ([string]$result.status -notin $allowedStatuses) {
                throw "report.json eval_result '$($result.eval_id)' has invalid status '$($result.status)'; must be PASS or FAIL."
            }
            if ([string]$result.status -eq "PASS") { $evalsPassedCount++ }
            else { $evalsFailedCount++ }
            $totalReportAssertionsFailed += [int]$result.assertions_failed
            $perEvalTotal = [int]$result.assertions_total
            $perEvalPassed = [int]$result.assertions_passed
            $perEvalFailed = [int]$result.assertions_failed
            if ($perEvalTotal -ne ($perEvalPassed + $perEvalFailed)) {
                throw "report.json eval_result '$($result.eval_id)' assertions_total ($perEvalTotal) does not equal assertions_passed ($perEvalPassed) + assertions_failed ($perEvalFailed)."
            }
        }

        # summary.status must match expected_status from expected.json
        $expectedStatus = [string]$expectedContent.report_artifact.expected_status
        if ([string]$summary.status -ne $expectedStatus) {
            throw "report.json summary.status ($($summary.status)) does not match expected_status ($expectedStatus) from expected.json."
        }

        # summary.evals_passed / evals_failed must match per-eval status counts
        if ([int]$summary.evals_passed -ne $evalsPassedCount) {
            throw "report.json summary.evals_passed ($($summary.evals_passed)) does not match per-eval PASS count ($evalsPassedCount)."
        }
        if ([int]$summary.evals_failed -ne $evalsFailedCount) {
            throw "report.json summary.evals_failed ($($summary.evals_failed)) does not match per-eval FAIL count ($evalsFailedCount)."
        }

        # summary.assertions_failed must match per-eval sum and equal assertions_total - assertions_passed
        if ([int]$summary.assertions_failed -ne $totalReportAssertionsFailed) {
            throw "report.json summary.assertions_failed ($($summary.assertions_failed)) does not match sum of per-eval assertions_failed ($totalReportAssertionsFailed)."
        }
        if ([int]$summary.assertions_failed -ne ([int]$summary.assertions_total - [int]$summary.assertions_passed)) {
            throw "report.json summary.assertions_failed ($($summary.assertions_failed)) does not equal assertions_total ($($summary.assertions_total)) - assertions_passed ($($summary.assertions_passed))."
        }

        $script:evidence.eval_report_artifact = [ordered]@{
            path = "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/report.json"
            eval_count = $reportResults.Count
            assertion_count = [int]$summary.assertions_total
            overall_status = [string]$summary.status
            failure_reason_example_fields = @($failureExample.PSObject.Properties.Name)
        }
        Add-Check "eval report artifact" "PASS" "Workflow-spec-lite eval report artifact is public-safe, JSON-valid, eval IDs match, summary totals are consistent, failure reason shape is stable, and PASS/FAIL status semantics are locked." $evidence.eval_report_artifact
    }
    catch {
        Add-Check "eval report artifact" "FAIL" $_.Exception.Message
    }

    # Slice 3: verify eval baseline recording artifact
    try {
        $baselinePath = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "baseline.json"
        if (-not (Test-Path -LiteralPath $baselinePath)) {
            throw "Missing workflow-spec-lite/baseline.json."
        }
        $baselineContent = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json

        foreach ($field in @("skill", "version", "fixture", "baseline_type", "baseline_identity", "baseline_source", "eval_ids", "assertion_totals", "status_summary", "comparison_fields")) {
            if ($null -eq $baselineContent.$field) {
                throw "baseline.json is missing required top-level field: $field"
            }
        }
        if ([string]$baselineContent.baseline_type -ne "static") {
            throw "baseline.json baseline_type must be 'static', got: $($baselineContent.baseline_type)"
        }

        # Verify baseline_identity fields
        $identity = $baselineContent.baseline_identity
        foreach ($field in @("name", "version", "scope")) {
            if ($null -eq $identity.$field) {
                throw "baseline.json baseline_identity is missing required field: $field"
            }
        }

        # Verify baseline_source fields
        $source = $baselineContent.baseline_source
        foreach ($field in @("evals_path", "report_path", "expected_path")) {
            if ($null -eq $source.$field) {
                throw "baseline.json baseline_source is missing required field: $field"
            }
        }

        # Verify eval_ids match evals.json
        $baselineEvalIds = @($baselineContent.eval_ids | ForEach-Object { [string]$_ })
        if (-not (Test-ExactArray -Actual $baselineEvalIds -Expected $expectedEvalIds)) {
            throw "Baseline eval ID mismatch. Expected: $($expectedEvalIds -join ', '). Actual: $($baselineEvalIds -join ', ')."
        }

        # Verify assertion_totals
        $assertionTotals = $baselineContent.assertion_totals
        foreach ($field in @("eval_count", "assertions_total", "assertions_per_eval")) {
            if ($null -eq $assertionTotals.$field) {
                throw "baseline.json assertion_totals is missing required field: $field"
            }
        }
        if ([int]$assertionTotals.eval_count -ne $evalCases.Count) {
            throw "baseline.json assertion_totals.eval_count ($($assertionTotals.eval_count)) does not match evals.json eval count ($($evalCases.Count))."
        }
        if ([int]$assertionTotals.assertions_total -ne $totalAssertions) {
            throw "baseline.json assertion_totals.assertions_total ($($assertionTotals.assertions_total)) does not match evals.json assertion count ($totalAssertions)."
        }
        # Verify per-eval assertion counts match evals.json
        $perEvalCounts = $assertionTotals.assertions_per_eval
        foreach ($evalCase in $evalCases) {
            $evalId = [string]$evalCase.id
            $expectedCount = @($evalCase.assertions).Count
            if ($null -eq $perEvalCounts.$evalId) {
                throw "baseline.json assertion_totals.assertions_per_eval is missing eval_id: $evalId"
            }
            if ([int]$perEvalCounts.$evalId -ne $expectedCount) {
                throw "baseline.json assertions_per_eval.$evalId ($($perEvalCounts.$evalId)) does not match evals.json assertion count ($expectedCount)."
            }
        }

        # Verify status_summary fields
        $statusSummary = $baselineContent.status_summary
        foreach ($field in @("evals_passed", "evals_failed", "assertions_passed", "assertions_failed", "status")) {
            if ($null -eq $statusSummary.$field) {
                throw "baseline.json status_summary is missing required field: $field"
            }
        }
        # Verify status_summary is consistent with report.json (not conflicting)
        if ([int]$statusSummary.assertions_passed + [int]$statusSummary.assertions_failed -ne [int]$assertionTotals.assertions_total) {
            throw "baseline.json status_summary assertions_passed + assertions_failed does not equal assertions_total."
        }
        if ([int]$statusSummary.evals_passed + [int]$statusSummary.evals_failed -ne [int]$assertionTotals.eval_count) {
            throw "baseline.json status_summary evals_passed + evals_failed does not equal eval_count."
        }

        # Verify comparison_fields shape
        $comparisonFields = $baselineContent.comparison_fields
        foreach ($field in @("baseline_pass_rate", "with_skill_pass_rate", "delta", "iteration_count")) {
            if ($null -eq $comparisonFields.$field) {
                throw "baseline.json comparison_fields is missing required field: $field"
            }
        }

        # Verify baseline_source path values match expected strings
        $expectedSourcePaths = [ordered]@{
            evals_path = "workflow-spec-lite/evals.json"
            report_path = "workflow-spec-lite/report.json"
            expected_path = "workflow-spec-lite/expected.json"
        }
        foreach ($key in $expectedSourcePaths.Keys) {
            if ([string]$source.$key -ne $expectedSourcePaths[$key]) {
                throw "baseline.json baseline_source.$key is '$($source.$key)', expected '$($expectedSourcePaths[$key])'."
            }
        }

        # Verify status_summary matches report.json summary (cross-artifact consistency)
        $reportSummary = $reportContent.summary
        $statusSummaryReportPairs = [ordered]@{
            evals_passed = [int]$reportSummary.evals_passed
            evals_failed = [int]$reportSummary.evals_failed
            assertions_passed = [int]$reportSummary.assertions_passed
            assertions_failed = [int]$reportSummary.assertions_failed
        }
        foreach ($key in $statusSummaryReportPairs.Keys) {
            if ([int]$statusSummary.$key -ne $statusSummaryReportPairs[$key]) {
                throw "baseline.json status_summary.$key ($($statusSummary.$key)) conflicts with report.json summary.$key ($($statusSummaryReportPairs[$key]))."
            }
        }
        if ([string]$statusSummary.status -ne [string]$reportSummary.status) {
            throw "baseline.json status_summary.status ($($statusSummary.status)) conflicts with report.json summary.status ($($reportSummary.status))."
        }

        # Verify comparison_fields numeric types and range
        foreach ($field in @("baseline_pass_rate", "with_skill_pass_rate", "delta")) {
            $val = $comparisonFields.$field
            if ($val -isnot [double] -and $val -isnot [decimal] -and $val -isnot [int] -and $val -isnot [long]) {
                throw "baseline.json comparison_fields.$field must be a number, got type $($val.GetType().Name)."
            }
        }
        if ($comparisonFields.iteration_count -isnot [int] -and $comparisonFields.iteration_count -isnot [long]) {
            throw "baseline.json comparison_fields.iteration_count must be an integer, got type $($comparisonFields.iteration_count.GetType().Name)."
        }
        foreach ($field in @("baseline_pass_rate", "with_skill_pass_rate")) {
            $val = [double]$comparisonFields.$field
            if ($val -lt 0.0 -or $val -gt 1.0) {
                throw "baseline.json comparison_fields.$field ($val) must be in range 0..1."
            }
        }

        $script:evidence.eval_baseline_artifact = [ordered]@{
            path = "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/baseline.json"
            baseline_name = [string]$identity.name
            eval_count = [int]$assertionTotals.eval_count
            assertion_count = [int]$assertionTotals.assertions_total
            overall_status = [string]$statusSummary.status
            comparison_field_count = @($comparisonFields.PSObject.Properties.Name).Count
        }
        Add-Check "eval baseline artifact" "PASS" "Workflow-spec-lite eval baseline recording artifact is public-safe, JSON-valid, eval IDs match, assertion totals match, baseline-source paths are pinned, status summary matches report.json, and comparison field numeric shape is locked." $evidence.eval_baseline_artifact
    }
    catch {
        Add-Check "eval baseline artifact" "FAIL" $_.Exception.Message
    }
}
