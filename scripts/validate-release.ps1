[CmdletBinding()]
param(
    [string]$ScratchRoot = "",
    [switch]$SkipLinkMode,
    [string]$TargetVersion = "v0.5.1",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir "lib/path-guard.ps1")
. (Join-Path $scriptDir "validation/release-test-helper.ps1")
. (Join-Path $scriptDir "validation/workflow-spec-lite-fixture-helper.ps1")
. (Join-Path $scriptDir "validation/release-repository-checks.ps1")
. (Join-Path $scriptDir "validation/release-parser-safety-checks.ps1")
. (Join-Path $scriptDir "validation/release-documentation-checks.ps1")
. (Join-Path $scriptDir "validation/release-knowledge-hub-checks.ps1")
. (Join-Path $scriptDir "validation/release-template-language-checks.ps1")
. (Join-Path $scriptDir "validation/release-runtime-smoke-checks.ps1")
. (Join-Path $scriptDir "validation/release-bootstrap-checks.ps1")
. (Join-Path $scriptDir "validation/release-project-template-checks.ps1")
$runStamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")

if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-release-validation-{0}" -f $runStamp)
}

$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
$liveRuntimeCandidates = @(Get-AgentLiveRuntimeCandidates)

Assert-NotLiveRuntime -Path $scratchRootFull
New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null

$checks = New-Object 'System.Collections.Generic.List[object]'
$evidence = [ordered]@{
    profile_matrix = @()
    runtime_smoke = [ordered]@{}
    audit = [ordered]@{}
    knowledge_hub = [ordered]@{}
    duplicate_helpers = @()
    memory_metadata = [ordered]@{}
    language_policy = [ordered]@{}
    language_migration = [ordered]@{}
    memory_language_audit = [ordered]@{}
    bootstrap_command_boundary = [ordered]@{}
    routing = [ordered]@{}
    scratch_retention = [ordered]@{}
    spec_lite = [ordered]@{}
    agent_template_guidance = [ordered]@{}
    structural_diagnostics_design = [ordered]@{}
    structural_diagnostics_fixtures = [ordered]@{}
    memory_boundary = [ordered]@{}
    spec_state_boundary = [ordered]@{}
}

$targetReleaseVersion = $TargetVersion.Trim()
if ([string]::IsNullOrWhiteSpace($targetReleaseVersion)) {
    $targetReleaseVersion = "v0.5.1"
}
if ($targetReleaseVersion -notmatch '^v\d+\.\d+\.\d+$') {
    throw "TargetVersion must look like vMAJOR.MINOR.PATCH."
}

# Invoke-ReleaseValidationRepositoryChecks: Delegates to Invoke-ReleaseRepositoryChecks for all
# repository, documentation boundary, helper ownership, skill metadata, and hub init checks.
function Invoke-ReleaseValidationRepositoryChecks {

Invoke-ReleaseRepositoryChecks

}

# Invoke-ReleaseValidationSpecAndDocumentationChecks: No parameters; runs workflow-spec-lite fixture, template guidance, README, and release notes checks in the original order.
function Invoke-ReleaseValidationSpecAndDocumentationChecks {

try {
    $specValidator = Join-PathParts $repoRoot "skills" "workflow-spec-lite" "scripts" "validate_spec.ps1"
    $fixtureDir = Join-PathParts $scratchRootFull "spec-lite-fixtures"
    $script:evidence.spec_lite = Invoke-WorkflowSpecLiteValidatorFixtureSuite `
        -RepositoryRoot $repoRoot `
        -SpecValidator $specValidator `
        -FixtureDir $fixtureDir `
        -ScratchRoot $scratchRootFull
    Add-Check "spec-lite validator" "PASS" "workflow-spec-lite validator accepts complete English, zh-CN bilingual, UTF-8 no-BOM zh-CN, and optional-sections specs and rejects missing metadata, goals, non-goals, acceptance, risks, and execution contract fixtures." $evidence.spec_lite
}
catch {
    Add-Check "spec-lite validator" "FAIL" $_.Exception.Message
}

Invoke-ReleaseDocumentationBoundaryChecks

try {
    $fixtureRoot = Join-PathParts $repoRoot "scripts" "validation" "memory-diagnose-structural-fixtures" "completed-list-growth"
    $fixtureReadme = Get-FileText -RelativePath "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/README.md"
    foreach ($token in @("Completed List Growth", "compact-active-phase", "process-history-backlog", "process_completed_list_growth")) {
        if (-not $fixtureReadme.Contains($token)) {
            throw "Completed list growth fixture README is missing token: $token"
        }
    }

    $memoryDiagnoseScript = Join-PathParts $repoRoot "skills" "memory-governance" "scripts" "memory_diagnose.ps1"
    $fixtureCases = @(
        [ordered]@{ name = "compact-active-phase"; role = "negative" },
        [ordered]@{ name = "process-history-backlog"; role = "positive" }
    )

    $fixtureEvidence = New-Object 'System.Collections.Generic.List[object]'
    foreach ($fixtureCase in $fixtureCases) {
        $fixtureName = [string]$fixtureCase.name
        $fixtureRole = [string]$fixtureCase.role
        $projectRoot = Join-PathParts $fixtureRoot $fixtureName
        $expectedPath = Join-PathParts $projectRoot "expected.json"
        $processPath = Join-PathParts $projectRoot ".agents" "process.txt"

        $expected = Get-Content -LiteralPath $expectedPath -Raw | ConvertFrom-Json
        if ([string]$expected.fixture -ne $fixtureName) {
            throw "Fixture expected.json name mismatch for $fixtureName."
        }
        if ([string]$expected.family -ne "completed-list-growth") {
            throw "Fixture expected.json family mismatch for $fixtureName."
        }
        if ([string]$expected.role -ne $fixtureRole) {
            throw "Fixture expected.json role mismatch for $fixtureName."
        }
        if ([string]$expected.future_structural_diagnosis.expected_path_suffix -ne ".agents/process.txt") {
            throw "Fixture expected path suffix mismatch for $fixtureName."
        }

        $processLines = @(Get-Content -LiteralPath $processPath)
        $completedLines = New-Object 'System.Collections.Generic.List[string]'
        $inCompletedSection = $false
        foreach ($line in $processLines) {
            if ($line -eq "Completed") {
                $inCompletedSection = $true
                continue
            }
            if ($inCompletedSection -and $line -match '^[A-Za-z].*$') {
                break
            }
            if ($inCompletedSection) {
                $completedLines.Add([string]$line)
            }
        }
        $completedEntryCount = ([regex]::Matches(($completedLines -join "`n"), '(?m)^-\s+')).Count

        $entryExpectation = $expected.completed_entry_expectation
        $entryExpectationFields = @($entryExpectation.PSObject.Properties.Name)
        if ("minimum" -in $entryExpectationFields -and $completedEntryCount -lt [int]$entryExpectation.minimum) {
            throw "Positive completed-list fixture has too few entries: $completedEntryCount"
        }
        if ("maximum" -in $entryExpectationFields -and $completedEntryCount -gt [int]$entryExpectation.maximum) {
            throw "Negative completed-list fixture has too many entries: $completedEntryCount"
        }

        $shouldReport = [bool]$expected.future_structural_diagnosis.should_report
        $acceptableCodes = @($expected.future_structural_diagnosis.acceptable_finding_codes | ForEach-Object { [string]$_ })
        if ($fixtureRole -eq "positive") {
            if (-not $shouldReport) {
                throw "Positive completed-list fixture does not expect a future structural finding."
            }
            if ("process_completed_list_growth" -notin $acceptableCodes) {
                throw "Positive completed-list fixture does not document the future finding code."
            }
            if ([string]$expected.future_structural_diagnosis.expected_severity -ne "info") {
                throw "Positive completed-list fixture does not document info severity."
            }
            foreach ($recommendationToken in @("compress", "summarize", "process.txt")) {
                if ($recommendationToken -notin @($expected.future_structural_diagnosis.recommendation_must_include | ForEach-Object { [string]$_ })) {
                    throw "Positive completed-list fixture recommendation shape is missing: $recommendationToken"
                }
            }
        }
        else {
            if ($shouldReport) {
                throw "Negative completed-list fixture unexpectedly expects a future structural finding."
            }
        }

        $diagnose = & $memoryDiagnoseScript -ProjectRoot $projectRoot -Json | ConvertFrom-Json
        $currentCodes = @($diagnose.findings | ForEach-Object { [string]$_.code })
        $expectedCurrentCodes = @($expected.current_diagnosis.expected_finding_codes | ForEach-Object { [string]$_ })
        if (-not (Test-ExactArray -Actual $currentCodes -Expected $expectedCurrentCodes)) {
            throw "Current memory diagnosis findings for $fixtureName did not match fixture expectations. Actual: $($currentCodes -join ', ')"
        }
        if ($fixtureRole -eq "positive") {
            $growthFindings = @($diagnose.findings | Where-Object { [string]$_.code -eq "process_completed_list_growth" })
            if ($growthFindings.Count -ne 1) {
                throw "Positive completed-list fixture did not produce exactly one process_completed_list_growth finding."
            }
            $growthFinding = $growthFindings[0]
            if ([string]$growthFinding.severity -ne "info") {
                throw "Completed-list finding severity should be info."
            }
            $growthPath = ([string]$growthFinding.path).Replace('\', '/')
            if (-not $growthPath.EndsWith(".agents/process.txt")) {
                throw "Completed-list finding path should point to .agents/process.txt."
            }
            $growthRecommendation = [string]$growthFinding.recommendation
            foreach ($recommendationToken in @($expected.future_structural_diagnosis.recommendation_must_include | ForEach-Object { [string]$_ })) {
                if ($growthRecommendation.IndexOf($recommendationToken, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    throw "Completed-list finding recommendation is missing token: $recommendationToken"
                }
            }
        }
        elseif ("process_completed_list_growth" -in $currentCodes) {
            throw "Negative completed-list fixture unexpectedly produced process_completed_list_growth."
        }

        $fixtureEvidence.Add([ordered]@{
            fixture = $fixtureName
            role = $fixtureRole
            completed_entries = $completedEntryCount
            current_finding_codes = @($currentCodes)
            future_should_report = $shouldReport
            future_acceptable_codes = @($acceptableCodes)
        })
    }

    $script:evidence.structural_diagnostics_fixtures = [ordered]@{
        family = "completed-list-growth"
        fixtures = @($fixtureEvidence.ToArray())
    }
    Add-Check "structural memory diagnostics fixtures" "PASS" "Completed list growth positive and negative fixtures are public-safe, readable, and cover current memory_diagnose behavior." $evidence.structural_diagnostics_fixtures
}
catch {
    Add-Check "structural memory diagnostics fixtures" "FAIL" $_.Exception.Message
}

try {
    $hotFixtureRoot = Join-PathParts $repoRoot "scripts" "validation" "memory-diagnose-structural-fixtures" "hot-memory-soft-length"
    $hotFixtureReadme = Get-FileText -RelativePath "scripts/validation/memory-diagnose-structural-fixtures/hot-memory-soft-length/README.md"
    foreach ($token in @("Hot Memory Soft-Length", "concise-current-state", "overloaded-hot-memory", "hot_memory_process_long", "hot_memory_plan_long")) {
        if (-not $hotFixtureReadme.Contains($token)) {
            throw "Hot memory soft-length fixture README is missing token: $token"
        }
    }

    $memoryDiagnoseScript = Join-PathParts $repoRoot "skills" "memory-governance" "scripts" "memory_diagnose.ps1"
    $hotFixtureCases = @(
        [ordered]@{ name = "concise-current-state"; role = "negative" },
        [ordered]@{ name = "overloaded-hot-memory"; role = "positive" }
    )

    $hotFixtureEvidence = New-Object 'System.Collections.Generic.List[object]'
    foreach ($hotCase in $hotFixtureCases) {
        $fixtureName = [string]$hotCase.name
        $fixtureRole = [string]$hotCase.role
        $projectRoot = Join-PathParts $hotFixtureRoot $fixtureName
        $expectedPath = Join-PathParts $projectRoot "expected.json"
        $processPath = Join-PathParts $projectRoot ".agents" "process.txt"
        $planPath = Join-PathParts $projectRoot ".agents" "plan.md"

        $expected = Get-Content -LiteralPath $expectedPath -Raw | ConvertFrom-Json
        if ([string]$expected.fixture -ne $fixtureName) {
            throw "Hot memory fixture expected.json name mismatch for $fixtureName."
        }
        if ([string]$expected.family -ne "hot-memory-soft-length") {
            throw "Hot memory fixture expected.json family mismatch for $fixtureName."
        }
        if ([string]$expected.role -ne $fixtureRole) {
            throw "Hot memory fixture expected.json role mismatch for $fixtureName."
        }

        $processLineCount = @(Get-Content -LiteralPath $processPath).Count
        $planLineCount = @(Get-Content -LiteralPath $planPath).Count

        $softExpectation = $expected.soft_line_expectation
        $softFields = @($softExpectation.PSObject.Properties.Name)
        if ("process_max" -in $softFields -and $processLineCount -gt [int]$softExpectation.process_max) {
            throw "Negative hot memory fixture process.txt has too many lines: $processLineCount"
        }
        if ("plan_max" -in $softFields -and $planLineCount -gt [int]$softExpectation.plan_max) {
            throw "Negative hot memory fixture plan.md has too many lines: $planLineCount"
        }
        if ("process_min" -in $softFields -and $processLineCount -lt [int]$softExpectation.process_min) {
            throw "Positive hot memory fixture process.txt has too few lines: $processLineCount"
        }
        if ("plan_min" -in $softFields -and $planLineCount -lt [int]$softExpectation.plan_min) {
            throw "Positive hot memory fixture plan.md has too few lines: $planLineCount"
        }

        $shouldReport = [bool]$expected.future_structural_diagnosis.should_report
        $acceptableCodes = @($expected.future_structural_diagnosis.acceptable_finding_codes | ForEach-Object { [string]$_ })
        if ($fixtureRole -eq "positive") {
            if (-not $shouldReport) {
                throw "Positive hot memory fixture does not expect future structural findings."
            }
            if ("hot_memory_process_long" -notin $acceptableCodes) {
                throw "Positive hot memory fixture does not document hot_memory_process_long finding code."
            }
            if ("hot_memory_plan_long" -notin $acceptableCodes) {
                throw "Positive hot memory fixture does not document hot_memory_plan_long finding code."
            }
            if ([string]$expected.future_structural_diagnosis.expected_severity -ne "info") {
                throw "Positive hot memory fixture does not document info severity."
            }
            foreach ($recommendationToken in @("compress", "hot session memory", "docs/specs")) {
                if ($recommendationToken -notin @($expected.future_structural_diagnosis.recommendation_must_include | ForEach-Object { [string]$_ })) {
                    throw "Positive hot memory fixture recommendation shape is missing: $recommendationToken"
                }
            }
        }
        else {
            if ($shouldReport) {
                throw "Negative hot memory fixture unexpectedly expects future structural findings."
            }
        }

        $diagnose = & $memoryDiagnoseScript -ProjectRoot $projectRoot -Json | ConvertFrom-Json
        $currentCodes = @($diagnose.findings | ForEach-Object { [string]$_.code })
        $expectedCurrentCodes = @($expected.current_diagnosis.expected_finding_codes | ForEach-Object { [string]$_ })
        if (-not (Test-ExactArray -Actual $currentCodes -Expected $expectedCurrentCodes)) {
            throw "Current memory diagnosis findings for $fixtureName did not match hot memory fixture expectations. Actual: $($currentCodes -join ', ')"
        }
        if ($fixtureRole -eq "positive") {
            $processFindings = @($diagnose.findings | Where-Object { [string]$_.code -eq "hot_memory_process_long" })
            $planFindings = @($diagnose.findings | Where-Object { [string]$_.code -eq "hot_memory_plan_long" })
            if ($processFindings.Count -ne 1) {
                throw "Positive hot memory fixture did not produce exactly one hot_memory_process_long finding."
            }
            if ($planFindings.Count -ne 1) {
                throw "Positive hot memory fixture did not produce exactly one hot_memory_plan_long finding."
            }
            if ([string]$processFindings[0].severity -ne "info") {
                throw "hot_memory_process_long severity should be info."
            }
            if ([string]$planFindings[0].severity -ne "info") {
                throw "hot_memory_plan_long severity should be info."
            }
            $processPathNorm = ([string]$processFindings[0].path).Replace('\', '/')
            if (-not $processPathNorm.EndsWith(".agents/process.txt")) {
                throw "hot_memory_process_long path should point to .agents/process.txt."
            }
            $planPathNorm = ([string]$planFindings[0].path).Replace('\', '/')
            if (-not $planPathNorm.EndsWith(".agents/plan.md")) {
                throw "hot_memory_plan_long path should point to .agents/plan.md."
            }
            foreach ($recommendationToken in @($expected.future_structural_diagnosis.recommendation_must_include | ForEach-Object { [string]$_ })) {
                $processRec = [string]$processFindings[0].recommendation
                $planRec = [string]$planFindings[0].recommendation
                $foundInProcess = $processRec.IndexOf($recommendationToken, [StringComparison]::OrdinalIgnoreCase) -ge 0
                $foundInPlan = $planRec.IndexOf($recommendationToken, [StringComparison]::OrdinalIgnoreCase) -ge 0
                if (-not $foundInProcess -and -not $foundInPlan) {
                    throw "Hot memory findings recommendation is missing token in both findings: $recommendationToken"
                }
            }
        }
        elseif ("hot_memory_process_long" -in $currentCodes -or "hot_memory_plan_long" -in $currentCodes) {
            throw "Negative hot memory fixture unexpectedly produced a soft-length finding."
        }

        $hotFixtureEvidence.Add([ordered]@{
            fixture = $fixtureName
            role = $fixtureRole
            process_lines = $processLineCount
            plan_lines = $planLineCount
            current_finding_codes = @($currentCodes)
            future_should_report = $shouldReport
            future_acceptable_codes = @($acceptableCodes)
        })
    }

    $script:evidence.hot_memory_soft_length_fixtures = [ordered]@{
        family = "hot-memory-soft-length"
        fixtures = @($hotFixtureEvidence.ToArray())
    }
    Add-Check "hot memory soft-length fixtures" "PASS" "Hot memory soft-length positive and negative fixtures are public-safe, readable, and cover current memory_diagnose soft-length behavior." $evidence.hot_memory_soft_length_fixtures
}
catch {
    Add-Check "hot memory soft-length fixtures" "FAIL" $_.Exception.Message
}

try {
    $evalFixtureRoot = Join-PathParts $repoRoot "scripts" "validation" "eval-iteration-fixtures"
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
        if ($val -isnot [double] -and $val -isnot [int] -and $val -isnot [long]) {
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

try {
    $triageWorkflow = Get-FileText -RelativePath ".github/workflows/issue-triage-label-sync.yml"
    $decisionCommandWorkflow = Get-FileText -RelativePath ".github/workflows/issue-triage-decision-command.yml"
    $decisionCommandHelper = Get-FileText -RelativePath ".github/scripts/issue-triage-decision-command.js"
    $decisionCommandTest = Get-FileText -RelativePath "scripts/test-issue-triage-decision-command.ps1"
    $governance = Get-FileText -RelativePath "docs/agent-governance.md"
    $issueTemplate = Get-FileText -RelativePath ".github/ISSUE_TEMPLATE/agent-candidate.md"
    $triageExpectations = [ordered]@{
        ".github/workflows/issue-triage-label-sync.yml" = @(
            "issues:",
            "issues: write",
            "contents: read",
            "source:agent",
            "Human Triage Decision",
            "concurrency:",
            "Decision:",
            "legacy checklist",
            "agent-ecosystem-bot[bot]",
            "getCollaboratorPermissionLevel",
            "Actor is not trusted",
            "triage:accepted",
            "triage:rejected",
            "triage:deferred",
            "triage:needs-human",
            "review:needs-human",
            "core.setFailed"
        )
        ".github/workflows/issue-triage-decision-command.yml" = @(
            "issue_comment:",
            "issues: write",
            "contents: read",
            "source:agent",
            "pull_request == null",
            "concurrency:",
            "actions/checkout@v6",
            "actions/github-script@v8",
            "issue-triage-decision-command.js"
        )
        ".github/scripts/issue-triage-decision-command.js" = @(
            "parseDecisionCommand",
            "/decision accepted",
            "/accept",
            "TRUSTED_REPOSITORY_ROLES",
            '"admin", "maintain", "write"',
            "getCollaboratorPermissionLevel",
            "updateDecisionInBody",
            "buildNormalizedTriageSection",
            "DEFAULT_ALLOWED_VALUES_LINE",
            "formatActorLogin",
            "convergeTriageLabels",
            "review:needs-human",
            "Pull request comments are ignored"
        )
        "scripts/test-issue-triage-decision-command.ps1" = @(
            "/decision accepted",
            "/decision maybe",
            "countOccurrences",
            'assert(!updated.body.includes("@maintainer"))',
            "Allowed values: accepted, rejected, deferred, needs-human",
            'permission: "triage"',
            "pull_request",
            "triage:accepted",
            "triage:needs-human",
            "missingSection",
            "appended"
        )
        "docs/agent-governance.md" = @(
            "Issue Triage Label Sync",
            "Issue Triage Decision Commands",
            "mirrors the explicit",
            "does not make triage decisions",
            "source:agent",
            "trusted automation",
            "appends a normalized section",
            "maintainer-authorized",
            "Decision: needs-human",
            "/decision accepted",
            "admin",
            "maintain",
            "write",
            "review:needs-human"
        )
        ".github/ISSUE_TEMPLATE/agent-candidate.md" = @(
            "issue triage label sync workflow",
            "Decision: needs-human",
            "Allowed values: accepted, rejected, deferred, needs-human"
        )
    }

    $triageMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $triageExpectations.Keys) {
        $text = switch ($relativePath) {
            ".github/workflows/issue-triage-label-sync.yml" { $triageWorkflow }
            ".github/workflows/issue-triage-decision-command.yml" { $decisionCommandWorkflow }
            ".github/scripts/issue-triage-decision-command.js" { $decisionCommandHelper }
            "scripts/test-issue-triage-decision-command.ps1" { $decisionCommandTest }
            "docs/agent-governance.md" { $governance }
            default { $issueTemplate }
        }
        foreach ($token in $triageExpectations[$relativePath]) {
            if (-not $text.Contains($token)) {
                $triageMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    $triageUnexpected = New-Object 'System.Collections.Generic.List[string]'
    $triageUnexpectedTokens = [ordered]@{
        ".github/workflows/issue-triage-label-sync.yml" = @(
            "- unlabeled"
        )
        ".github/ISSUE_TEMPLATE/agent-candidate.md" = @(
            "- [ ] Accepted",
            "- [ ] Rejected",
            "- [ ] Deferred",
            "- [ ] Needs human investigation",
            "Leave only one checked"
        )
    }
    foreach ($relativePath in $triageUnexpectedTokens.Keys) {
        $text = switch ($relativePath) {
            ".github/workflows/issue-triage-label-sync.yml" { $triageWorkflow }
            default { $issueTemplate }
        }
        foreach ($token in $triageUnexpectedTokens[$relativePath]) {
            if ($text.Contains($token)) {
                $triageUnexpected.Add("$relativePath still contains legacy token: $token")
            }
        }
    }

    if ($triageMissing.Count -gt 0 -or $triageUnexpected.Count -gt 0) {
        $triageFindings = @($triageMissing.ToArray()) + @($triageUnexpected.ToArray())
        Add-Check "issue triage label sync" "FAIL" "Issue triage label sync workflow or docs are incomplete." $triageFindings
    }
    else {
        $decisionCommandTestScript = Join-PathParts $repoRoot "scripts" "test-issue-triage-decision-command.ps1"
        $decisionCommandTestResult = & $decisionCommandTestScript -RepoRoot $repoRoot -Json | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            throw "Issue triage decision command tests exited with code $LASTEXITCODE."
        }
        Add-Check "issue triage label sync" "PASS" "Authorized agent candidate issue triage decisions are mirrored to labels by a scoped workflow." ([ordered]@{
            workflow = ".github/workflows/issue-triage-label-sync.yml"
            command_workflow = ".github/workflows/issue-triage-decision-command.yml"
            command_helper = ".github/scripts/issue-triage-decision-command.js"
            command_test = $decisionCommandTestResult
            docs = @("docs/agent-governance.md", ".github/ISSUE_TEMPLATE/agent-candidate.md")
        })
    }
}
catch {
    Add-Check "issue triage label sync" "FAIL" $_.Exception.Message
}

try {
    $identityWorkflow = Get-FileText -RelativePath ".github/workflows/pr-identity-guard.yml"
    $identityHelper = Get-FileText -RelativePath ".github/scripts/pr-identity-guard.js"
    $identityTest = Get-FileText -RelativePath "scripts/test-pr-identity-guard.ps1"
    $governance = Get-FileText -RelativePath "docs/agent-governance.md"
    $identityExpectations = [ordered]@{
        ".github/workflows/pr-identity-guard.yml" = @(
            "pull_request:",
            "contents: read",
            "pull-requests: read",
            "verify agent PR commit identity",
            "actions/checkout@v6",
            "actions/github-script@v8",
            "pr-identity-guard.js"
        )
        ".github/scripts/pr-identity-guard.js" = @(
            "ACCEPTED_BOT_SIGNATURES",
            "agent-ecosystem-bot[bot]@users.noreply.github.com",
            "resolveAgentSignals",
            "source:agent",
            "codex|agent",
            "evaluatePullRequestIdentity",
            "evaluateCommitIdentity",
            "Actor Boundary",
            "listCommits"
        )
        "scripts/test-pr-identity-guard.ps1" = @(
            "source:agent",
            "codex/issue-145-pr-identity-guard",
            "Actor Boundary",
            "agent-ecosystem-bot[bot]@users.noreply.github.com",
            "committer is Local User"
        )
        "docs/agent-governance.md" = @(
            "Pull Request Identity Guard",
            "source:agent",
            "codex/",
            "agent/",
            "scans every commit",
            "commit author and committer",
            "Actor Boundary",
            "bot-backed public write flow"
        )
    }

    $identityMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $identityExpectations.Keys) {
        $text = switch ($relativePath) {
            ".github/workflows/pr-identity-guard.yml" { $identityWorkflow }
            ".github/scripts/pr-identity-guard.js" { $identityHelper }
            "scripts/test-pr-identity-guard.ps1" { $identityTest }
            default { $governance }
        }
        foreach ($token in $identityExpectations[$relativePath]) {
            if (-not $text.Contains($token)) {
                $identityMissing.Add("$relativePath missing token: $token")
            }
        }
    }

    if ($identityMissing.Count -gt 0) {
        Add-Check "PR identity guard" "FAIL" "PR identity guard workflow, helper, tests, or docs are incomplete." @($identityMissing.ToArray())
    }
    else {
        $identityTestScript = Join-PathParts $repoRoot "scripts" "test-pr-identity-guard.ps1"
        $identityTestResult = & $identityTestScript -RepoRoot $repoRoot -Json | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            throw "PR identity guard tests exited with code $LASTEXITCODE."
        }
        Add-Check "PR identity guard" "PASS" "Hosted PR checks validate bot commit identity for explicitly agent-authored pull requests." ([ordered]@{
            workflow = ".github/workflows/pr-identity-guard.yml"
            helper = ".github/scripts/pr-identity-guard.js"
            focused_test = $identityTestResult
            docs = "docs/agent-governance.md"
        })
    }
}
catch {
    Add-Check "PR identity guard" "FAIL" $_.Exception.Message
}


}

# Invoke-ReleaseValidationParserSafetyChecks: Delegates to Invoke-ReleaseParserSafetyChecks for git diff,
# encoding, PowerShell/JSON parser, and public safety scan checks.
function Invoke-ReleaseValidationParserSafetyChecks {

Invoke-ReleaseParserSafetyChecks

}

try {
    Invoke-ReleaseValidationRepositoryChecks
    Invoke-ReleaseValidationInstallerRuntimeChecks
    Invoke-ReleaseValidationSpecAndDocumentationChecks
    Invoke-ReleaseValidationRuntimeAndKnowledgeHubChecks
    Invoke-ReleaseKnowledgeHubChecks
    Invoke-ReleaseValidationParserSafetyChecks
    Invoke-ReleaseValidationLanguageTemplateChecks
    Invoke-ReleaseTemplateLanguageChecks
}
catch {
    Add-Check "validator execution" "FAIL" ("Unhandled validator error: {0}" -f $_.Exception.Message)
}

try {
    $thinRoadmapPath = Join-PathParts $repoRoot "docs" "roadmap" "release-validator-thin-entrypoint-plan.md"
    $thinRoadmapExists = Test-Path -LiteralPath $thinRoadmapPath
    $thinRoadmapTokens = @(
        "1,500 lines or less",
        "scripts/validation/**"
    )
    $thinRoadmapMissing = @()
    if ($thinRoadmapExists) {
        $thinRoadmapText = Get-Content -LiteralPath $thinRoadmapPath -Raw
        foreach ($token in $thinRoadmapTokens) {
            if ($thinRoadmapText -notlike "*$token*") {
                $thinRoadmapMissing += $token
            }
        }
    }

    $script:evidence.thin_entrypoint_roadmap = [ordered]@{
        path = "docs/roadmap/release-validator-thin-entrypoint-plan.md"
        exists = [bool]$thinRoadmapExists
        missing_tokens = @($thinRoadmapMissing)
    }

    if ($thinRoadmapExists -and $thinRoadmapMissing.Count -eq 0) {
        Add-Check "thin entrypoint roadmap" "PASS" "The thin entrypoint roadmap document exists and contains the target threshold and growth rule tokens." $evidence.thin_entrypoint_roadmap
    }
    elseif (-not $thinRoadmapExists) {
        Add-Check "thin entrypoint roadmap" "FAIL" "Missing docs/roadmap/release-validator-thin-entrypoint-plan.md." $evidence.thin_entrypoint_roadmap
    }
    else {
        Add-Check "thin entrypoint roadmap" "FAIL" ("Roadmap document is missing required tokens: {0}" -f ($thinRoadmapMissing -join ", ")) $evidence.thin_entrypoint_roadmap
    }
}
catch {
    Add-Check "thin entrypoint roadmap" "FAIL" $_.Exception.Message
}

try {
    $compatAuditPath = Join-PathParts $repoRoot "docs" "roadmap" "cross-runtime-skill-compatibility-audit.md"
    $compatAuditExists = Test-Path -LiteralPath $compatAuditPath
    $compatAuditTokens = @(
        "safe-to-align",
        "requires-adapter",
        "do-not-change",
        "needs-follow-up",
        "agentskills.io",
        "Claude Code",
        "OpenAI Codex"
    )
    $compatAuditMissing = @()
    if ($compatAuditExists) {
        $compatAuditText = Get-Content -LiteralPath $compatAuditPath -Raw
        foreach ($token in $compatAuditTokens) {
            if ($compatAuditText -notlike "*$token*") {
                $compatAuditMissing += $token
            }
        }
    }

    $script:evidence.cross_runtime_compatibility_audit = [ordered]@{
        path = "docs/roadmap/cross-runtime-skill-compatibility-audit.md"
        exists = [bool]$compatAuditExists
        missing_tokens = @($compatAuditMissing)
    }

    if ($compatAuditExists -and $compatAuditMissing.Count -eq 0) {
        Add-Check "cross-runtime compatibility audit" "PASS" "The cross-runtime skill compatibility audit document exists and contains all required alignment category and runtime tokens." $evidence.cross_runtime_compatibility_audit
    }
    elseif (-not $compatAuditExists) {
        Add-Check "cross-runtime compatibility audit" "FAIL" "Missing docs/roadmap/cross-runtime-skill-compatibility-audit.md." $evidence.cross_runtime_compatibility_audit
    }
    else {
        Add-Check "cross-runtime compatibility audit" "FAIL" ("Compatibility audit document is missing required tokens: {0}" -f ($compatAuditMissing -join ", ")) $evidence.cross_runtime_compatibility_audit
    }
}
catch {
    Add-Check "cross-runtime compatibility audit" "FAIL" $_.Exception.Message
}

$result = [ordered]@{
    schema_version = 1
    validated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    repo_root = $repoRoot
    scratch_root = $scratchRootFull
    live_runtime_candidates = @($liveRuntimeCandidates)
    skip_link_mode = [bool]$SkipLinkMode.IsPresent
    checks = @($checks.ToArray())
    evidence = $evidence
    summary = [ordered]@{
        pass = @($checks | Where-Object { $_.status -eq "PASS" }).Count
        fail = @($checks | Where-Object { $_.status -eq "FAIL" }).Count
        warn = @($checks | Where-Object { $_.status -eq "WARN" }).Count
        deferred = @($checks | Where-Object { $_.status -eq "DEFERRED" }).Count
    }
}

$resultPath = Join-PathParts $scratchRootFull "validation-result.json"
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 12
}
else {
    Write-Output ""
    Write-Output "Release validation summary"
    Write-Output ("Scratch root: {0}" -f $scratchRootFull)
    Write-Output ("Result: {0}" -f $resultPath)
    Write-Output ("PASS={0} FAIL={1} WARN={2} DEFERRED={3}" -f $result.summary.pass, $result.summary.fail, $result.summary.warn, $result.summary.deferred)
    foreach ($check in $result.checks) {
        Write-Output ("[{0}] {1} - {2}" -f $check.status, $check.name, $check.detail)
    }
}

if ($result.summary.fail -gt 0) {
    exit 1
}

exit 0
