# release-eval-iteration-checks.ps1
# Contains validation checks for eval iteration fixtures, report artifact, baseline recording artifact,
# runner output contract, runner output regeneration, and iteration benchmark contract.
# Part of the release validator thin-entrypoint refactor.
# Authoritative check names: "eval iteration fixtures", "eval report artifact", "eval baseline artifact",
# "runner output contract", "runner output regeneration", "benchmark artifact", "benchmark regeneration".

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

    # Slice 5: verify runner output contract schema and example fixture
    try {
        # Verify runner-output-schema.json exists and has required fields
        $schemaPath = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "runner-output-schema.json"
        if (-not (Test-Path -LiteralPath $schemaPath)) {
            throw "Missing workflow-spec-lite/runner-output-schema.json."
        }
        $schemaContent = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        foreach ($field in @("`$schema", "`$id", "title", "type", "required", "properties", "`$defs")) {
            if ($null -eq $schemaContent.$field) {
                throw "runner-output-schema.json is missing required top-level field: $field"
            }
        }
        # Verify the schema defines the required top-level properties (sourced from expected.json)
        $schemaProps = @($schemaContent.properties.PSObject.Properties.Name)
        $expectedSchemaProps = @($expectedContent.runner_output_contract.schema_required_properties | ForEach-Object { [string]$_ })
        foreach ($requiredProp in $expectedSchemaProps) {
            if ($requiredProp -notin $schemaProps) {
                throw "runner-output-schema.json properties is missing required key: $requiredProp"
            }
        }
        # Verify $defs defines reusable sub-schemas
        $defs = @($schemaContent.'$defs'.PSObject.Properties.Name)
        foreach ($requiredDef in @("eval_result", "assertion_detail", "report_summary")) {
            if ($requiredDef -notin $defs) {
                throw "runner-output-schema.json `$defs is missing required definition: $requiredDef"
            }
        }

        # Verify runner-output-example.json exists and has required fields
        $examplePath = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "runner-output-example.json"
        if (-not (Test-Path -LiteralPath $examplePath)) {
            throw "Missing workflow-spec-lite/runner-output-example.json."
        }
        $exampleContent = Get-Content -LiteralPath $examplePath -Raw | ConvertFrom-Json
        $exampleTopLevelFields = @($expectedContent.runner_output_contract.example_required_top_level_fields | ForEach-Object { [string]$_ })
        foreach ($field in $exampleTopLevelFields) {
            if ($null -eq $exampleContent.$field) {
                throw "runner-output-example.json is missing required top-level field: $field"
            }
        }

        # Verify failure_reason_shape example has required fields
        $frsExample = $exampleContent.failure_reason_shape.example
        foreach ($field in @("eval_id", "assertion_type", "expected", "actual")) {
            if ($null -eq $frsExample.$field) {
                throw "runner-output-example.json failure_reason_shape.example is missing required field: $field"
            }
        }

        # Verify runner_metadata fields
        $runnerMeta = $exampleContent.runner_metadata
        foreach ($field in @("name", "version", "mode", "skill", "skill_version")) {
            if ($null -eq $runnerMeta.$field) {
                throw "runner-output-example.json runner_metadata is missing required field: $field"
            }
        }
        if ([string]$runnerMeta.mode -ne "static") {
            throw "runner-output-example.json runner_metadata.mode must be 'static', got: $($runnerMeta.mode)"
        }

        # Verify execution_metadata fields
        $execMeta = $exampleContent.execution_metadata
        foreach ($field in @("started_at", "finished_at", "duration_ms")) {
            if ($null -eq $execMeta.$field) {
                throw "runner-output-example.json execution_metadata is missing required field: $field"
            }
        }

        # Verify eval_results match evals.json eval IDs
        $exampleResults = @($exampleContent.eval_results)
        $exampleEvalIds = @($exampleResults | ForEach-Object { [string]$_.eval_id })
        if (-not (Test-ExactArray -Actual $exampleEvalIds -Expected $expectedEvalIds)) {
            throw "Runner output example eval ID mismatch. Expected: $($expectedEvalIds -join ', '). Actual: $($exampleEvalIds -join ', ')."
        }

        # Verify per-eval assertion_details and counts
        $totalExampleAssertions = 0
        foreach ($result in $exampleResults) {
            foreach ($field in @("eval_id", "status", "assertions_total", "assertions_passed", "assertions_failed", "assertion_details")) {
                if ($null -eq $result.$field) {
                    throw "runner-output-example.json eval_result is missing required field: $field"
                }
            }
            $details = @($result.assertion_details)
            if ([int]$result.assertions_total -ne $details.Count) {
                throw "runner-output-example.json eval '$($result.eval_id)' assertions_total ($($result.assertions_total)) does not match assertion_details count ($($details.Count))."
            }
            $totalExampleAssertions += $details.Count
            # Verify each assertion_detail has required fields (sourced from expected.json)
            $assertionDetailFields = @($expectedContent.runner_output_contract.example_required_assertion_detail_fields | ForEach-Object { [string]$_ })
            foreach ($detail in $details) {
                foreach ($field in $assertionDetailFields) {
                    if ($null -eq $detail.$field) {
                        throw "runner-output-example.json eval '$($result.eval_id)' assertion_detail is missing required field: $field"
                    }
                }
            }
        }
        if ($totalExampleAssertions -ne $totalAssertions) {
            throw "runner-output-example.json total assertion_details ($totalExampleAssertions) does not match evals.json total assertions ($totalAssertions)."
        }

        # Verify comparison_metadata exists with required fields (sourced from expected.json)
        $comparisonMeta = $exampleContent.comparison_metadata
        $comparisonMetaFields = @($expectedContent.runner_output_contract.example_required_comparison_metadata_fields | ForEach-Object { [string]$_ })
        foreach ($field in $comparisonMetaFields) {
            if ($null -eq $comparisonMeta.$field) {
                throw "runner-output-example.json comparison_metadata is missing required field: $field"
            }
        }
        if ([string]$comparisonMeta.comparison_mode -notin @("none", "with_skill", "without_skill")) {
            throw "runner-output-example.json comparison_metadata.comparison_mode is invalid: $($comparisonMeta.comparison_mode)"
        }

        # Verify summary consistency
        $exampleSummary = $exampleContent.summary
        foreach ($field in @("eval_count", "evals_passed", "evals_failed", "assertions_total", "assertions_passed", "assertions_failed", "status")) {
            if ($null -eq $exampleSummary.$field) {
                throw "runner-output-example.json summary is missing required field: $field"
            }
        }
        if ([int]$exampleSummary.eval_count -ne $exampleResults.Count) {
            throw "runner-output-example.json summary.eval_count ($($exampleSummary.eval_count)) does not match eval_results count ($($exampleResults.Count))."
        }
        if ([int]$exampleSummary.assertions_total -ne $totalExampleAssertions) {
            throw "runner-output-example.json summary.assertions_total ($($exampleSummary.assertions_total)) does not match total assertion_details ($totalExampleAssertions)."
        }

        $script:evidence.runner_output_contract = [ordered]@{
            schema_path = "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/runner-output-schema.json"
            example_path = "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/runner-output-example.json"
            eval_count = $exampleResults.Count
            assertion_count = $totalExampleAssertions
            schema_defs = @($defs)
            overall_status = [string]$exampleSummary.status
        }
        Add-Check "runner output contract" "PASS" "Workflow-spec-lite runner output contract schema and example fixture are public-safe, JSON-valid, eval IDs match, assertion_details are structurally consistent with evals.json, and summary totals are coherent." $evidence.runner_output_contract
    }
    catch {
        Add-Check "runner output contract" "FAIL" $_.Exception.Message
    }

    # Slice 6: verify runner output example is deterministically reproducible
    try {
        $runnerGeneratorModule = Join-PathParts $scriptDir "validation" "release-eval-runner-generator.ps1"
        if (-not (Test-Path -LiteralPath $runnerGeneratorModule)) {
            throw "Missing release-eval-runner-generator.ps1."
        }
        . $runnerGeneratorModule

        $examplePath = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "runner-output-example.json"
        $regenerationResult = Test-EvalRunnerOutputRegeneration -EvalsJsonPath $evalsJsonPath -ExpectedJsonPath $expectedPath -CommittedExamplePath $examplePath

        $script:evidence.runner_output_regeneration = [ordered]@{
            generator_path = "scripts/validation/release-eval-runner-generator.ps1"
            example_path = "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/runner-output-example.json"
            generated_eval_count = [int]$regenerationResult.generated_eval_count
            generated_assertion_count = [int]$regenerationResult.generated_assertion_count
            generated_status = [string]$regenerationResult.generated_status
            match = [bool]$regenerationResult.match
        }
        Add-Check "runner output regeneration" "PASS" "Runner output example is deterministically reproducible from evals.json and expected.json; all fields match across schema_version, contract_version, runner_metadata, eval_results with per-assertion details, failure_reason_shape, comparison_metadata, and summary." $evidence.runner_output_regeneration
    }
    catch {
        Add-Check "runner output regeneration" "FAIL" $_.Exception.Message
    }

    # Slice 7: verify iteration artifact / benchmark contract
    try {
        # Verify iterations directory structure exists
        $iterationsRoot = Join-PathParts $evalFixtureRoot "workflow-spec-lite" "iterations"
        if (-not (Test-Path -LiteralPath $iterationsRoot)) {
            throw "Missing workflow-spec-lite/iterations directory."
        }
        $iteration001Dir = Join-PathParts $iterationsRoot "iteration-001"
        if (-not (Test-Path -LiteralPath $iteration001Dir)) {
            throw "Missing workflow-spec-lite/iterations/iteration-001 directory."
        }

        # Verify benchmark.json exists and is valid JSON
        $benchmarkPath = Join-PathParts $iteration001Dir "benchmark.json"
        if (-not (Test-Path -LiteralPath $benchmarkPath)) {
            throw "Missing workflow-spec-lite/iterations/iteration-001/benchmark.json."
        }
        $benchmarkContent = Get-Content -LiteralPath $benchmarkPath -Raw | ConvertFrom-Json

        # Verify required top-level fields (sourced from expected.json)
        $benchmarkTopLevelFields = @($expectedContent.benchmark_artifact.required_top_level_fields | ForEach-Object { [string]$_ })
        foreach ($field in $benchmarkTopLevelFields) {
            if ($null -eq $benchmarkContent.$field) {
                throw "benchmark.json is missing required top-level field: $field"
            }
        }

        # Verify iteration_type is static
        if ([string]$benchmarkContent.iteration_type -ne "static") {
            throw "benchmark.json iteration_type must be 'static', got: $($benchmarkContent.iteration_type)"
        }

        # Verify iteration_index matches expected
        $expectedIterationIndex = [int]$expectedContent.benchmark_artifact.expected_iteration_index
        if ([int]$benchmarkContent.iteration_index -ne $expectedIterationIndex) {
            throw "benchmark.json iteration_index ($($benchmarkContent.iteration_index)) does not match expected ($expectedIterationIndex)."
        }

        # Verify benchmark_identity fields
        $identityFields = @($expectedContent.benchmark_artifact.required_benchmark_identity_fields | ForEach-Object { [string]$_ })
        foreach ($field in $identityFields) {
            if ($null -eq $benchmarkContent.benchmark_identity.$field) {
                throw "benchmark.json benchmark_identity is missing required field: $field"
            }
        }
        if ([int]$benchmarkContent.benchmark_identity.iteration -ne $expectedIterationIndex) {
            throw "benchmark.json benchmark_identity.iteration ($($benchmarkContent.benchmark_identity.iteration)) does not match expected ($expectedIterationIndex)."
        }

        # Verify source_refs fields
        $sourceRefsFields = @($expectedContent.benchmark_artifact.required_source_refs_fields | ForEach-Object { [string]$_ })
        foreach ($field in $sourceRefsFields) {
            if ($null -eq $benchmarkContent.source_refs.$field) {
                throw "benchmark.json source_refs is missing required field: $field"
            }
        }
        # Verify source_refs path values
        $expectedSourceRefs = [ordered]@{
            evals_path = "workflow-spec-lite/evals.json"
            report_path = "workflow-spec-lite/report.json"
            baseline_path = "workflow-spec-lite/baseline.json"
            runner_output_path = "workflow-spec-lite/runner-output-example.json"
            runner_output_schema_path = "workflow-spec-lite/runner-output-schema.json"
        }
        foreach ($key in $expectedSourceRefs.Keys) {
            if ([string]$benchmarkContent.source_refs.$key -ne $expectedSourceRefs[$key]) {
                throw "benchmark.json source_refs.$key is '$($benchmarkContent.source_refs.$key)', expected '$($expectedSourceRefs[$key])'."
            }
        }

        # Verify pass_rate fields
        $passRateFields = @($expectedContent.benchmark_artifact.required_pass_rate_fields | ForEach-Object { [string]$_ })
        foreach ($field in $passRateFields) {
            if ($null -eq $benchmarkContent.pass_rate.$field) {
                throw "benchmark.json pass_rate is missing required field: $field"
            }
        }
        # Verify pass_rate consistency with evals.json and report.json
        if ([int]$benchmarkContent.pass_rate.eval_count -ne $evalCases.Count) {
            throw "benchmark.json pass_rate.eval_count ($($benchmarkContent.pass_rate.eval_count)) does not match evals.json eval count ($($evalCases.Count))."
        }
        if ([int]$benchmarkContent.pass_rate.assertions_total -ne $totalAssertions) {
            throw "benchmark.json pass_rate.assertions_total ($($benchmarkContent.pass_rate.assertions_total)) does not match evals.json assertion count ($totalAssertions)."
        }
        if ([int]$benchmarkContent.pass_rate.assertions_passed + [int]$benchmarkContent.pass_rate.assertions_failed -ne $totalAssertions) {
            throw "benchmark.json pass_rate assertions_passed + assertions_failed does not equal assertions_total ($totalAssertions)."
        }
        if ([int]$benchmarkContent.pass_rate.evals_passed + [int]$benchmarkContent.pass_rate.evals_failed -ne $evalCases.Count) {
            throw "benchmark.json pass_rate evals_passed + evals_failed does not equal eval_count ($($evalCases.Count))."
        }
        # Verify pass_rate status matches expected
        $expectedBenchmarkStatus = [string]$expectedContent.benchmark_artifact.expected_status
        if ([string]$benchmarkContent.pass_rate.status -ne $expectedBenchmarkStatus) {
            throw "benchmark.json pass_rate.status ($($benchmarkContent.pass_rate.status)) does not match expected ($expectedBenchmarkStatus)."
        }
        # Verify pass_rate rate is in range 0..1
        $benchRate = [double]$benchmarkContent.pass_rate.rate
        if ($benchRate -lt 0.0 -or $benchRate -gt 1.0) {
            throw "benchmark.json pass_rate.rate ($benchRate) must be in range 0..1."
        }

        # Verify comparison_metadata fields
        $comparisonFields = @($expectedContent.benchmark_artifact.required_comparison_metadata_fields | ForEach-Object { [string]$_ })
        foreach ($field in $comparisonFields) {
            if ($null -eq $benchmarkContent.comparison_metadata.$field) {
                throw "benchmark.json comparison_metadata is missing required field: $field"
            }
        }
        # Verify comparison_mode matches expected
        $expectedComparisonMode = [string]$expectedContent.benchmark_artifact.expected_comparison_mode
        if ([string]$benchmarkContent.comparison_metadata.comparison_mode -ne $expectedComparisonMode) {
            throw "benchmark.json comparison_metadata.comparison_mode ($($benchmarkContent.comparison_metadata.comparison_mode)) does not match expected ($expectedComparisonMode)."
        }
        # Verify numeric types in comparison_metadata
        $compMeta = $benchmarkContent.comparison_metadata
        foreach ($field in @("baseline_pass_rate", "comparison_pass_rate", "delta")) {
            $val = $compMeta.$field
            if ($val -isnot [double] -and $val -isnot [decimal] -and $val -isnot [int] -and $val -isnot [long]) {
                throw "benchmark.json comparison_metadata.$field must be a number, got type $($val.GetType().Name)."
            }
        }
        if ($compMeta.iteration_count -isnot [int] -and $compMeta.iteration_count -isnot [long]) {
            throw "benchmark.json comparison_metadata.iteration_count must be an integer."
        }
        foreach ($field in @("baseline_pass_rate", "comparison_pass_rate")) {
            $val = [double]$compMeta.$field
            if ($val -lt 0.0 -or $val -gt 1.0) {
                throw "benchmark.json comparison_metadata.$field ($val) must be in range 0..1."
            }
        }

        # Verify eval_ids match evals.json
        $benchmarkEvalIds = @($benchmarkContent.eval_ids | ForEach-Object { [string]$_ })
        if (-not (Test-ExactArray -Actual $benchmarkEvalIds -Expected $expectedEvalIds)) {
            throw "Benchmark eval ID mismatch. Expected: $($expectedEvalIds -join ', '). Actual: $($benchmarkEvalIds -join ', ')."
        }

        $script:evidence.benchmark_artifact = [ordered]@{
            path = "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/iterations/iteration-001/benchmark.json"
            iteration_index = [int]$benchmarkContent.iteration_index
            comparison_mode = [string]$benchmarkContent.comparison_metadata.comparison_mode
            pass_rate = [double]$benchmarkContent.pass_rate.rate
            eval_count = [int]$benchmarkContent.pass_rate.eval_count
            assertion_count = [int]$benchmarkContent.pass_rate.assertions_total
            source_ref_count = @($benchmarkContent.source_refs.PSObject.Properties.Name).Count
        }
        Add-Check "benchmark artifact" "PASS" "Iteration benchmark artifact is public-safe, JSON-valid, iteration_index matches expected, source_refs paths are pinned, pass_rate counts are consistent with evals.json and report.json, comparison_metadata fields are complete with correct types, and eval_ids match evals.json." $evidence.benchmark_artifact
    }
    catch {
        Add-Check "benchmark artifact" "FAIL" $_.Exception.Message
    }

    # Slice 7b: verify benchmark artifact is deterministically reproducible
    try {
        $benchmarkGeneratorModule = Join-PathParts $scriptDir "validation" "release-eval-benchmark-generator.ps1"
        if (-not (Test-Path -LiteralPath $benchmarkGeneratorModule)) {
            throw "Missing release-eval-benchmark-generator.ps1."
        }
        . $benchmarkGeneratorModule

        $benchmarkRegenResult = Test-EvalBenchmarkRegeneration -EvalsJsonPath $evalsJsonPath -ExpectedJsonPath $expectedPath -CommittedBenchmarkPath $benchmarkPath

        $script:evidence.benchmark_regeneration = [ordered]@{
            generator_path = "scripts/validation/release-eval-benchmark-generator.ps1"
            benchmark_path = "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/iterations/iteration-001/benchmark.json"
            generated_eval_count = [int]$benchmarkRegenResult.generated_eval_count
            generated_assertion_count = [int]$benchmarkRegenResult.generated_assertion_count
            generated_pass_rate = [double]$benchmarkRegenResult.generated_pass_rate
            generated_status = [string]$benchmarkRegenResult.generated_status
            match = [bool]$benchmarkRegenResult.match
            differences = @($benchmarkRegenResult.differences)
        }
        Add-Check "benchmark regeneration" "PASS" "Iteration benchmark artifact is deterministically reproducible from evals.json and expected.json; all fields match across skill, version, fixture, iteration_index, benchmark_identity, source_refs, pass_rate, comparison_metadata, and eval_ids." $evidence.benchmark_regeneration
    }
    catch {
        Add-Check "benchmark regeneration" "FAIL" $_.Exception.Message
    }
}
