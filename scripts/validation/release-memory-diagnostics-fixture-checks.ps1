# release-memory-diagnostics-fixture-checks.ps1
# Contains validation checks for memory structural diagnostics fixtures
# (completed-list-growth and hot-memory-soft-length).
# Part of the release validator thin-entrypoint refactor.
# Authoritative check names: "structural memory diagnostics fixtures", "hot memory soft-length fixtures".

<#
.SYNOPSIS
    Invoke-ReleaseMemoryDiagnosticsFixtureChecks
    Validates completed-list-growth and hot-memory-soft-length memory diagnostics fixture suites.
.PARAMETER RepositoryRoot
    Absolute path to the repository root.
#>
function Invoke-ReleaseMemoryDiagnosticsFixtureChecks {
    param(
        [string]$RepositoryRoot
    )

    # Completed list growth fixture checks
    try {
        $fixtureRoot = Join-PathParts $RepositoryRoot "scripts" "validation" "memory-diagnose-structural-fixtures" "completed-list-growth"
        $fixtureReadme = Get-FileText -RelativePath "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/README.md"
        foreach ($token in @("Completed List Growth", "compact-active-phase", "process-history-backlog", "process_completed_list_growth")) {
            if (-not $fixtureReadme.Contains($token)) {
                throw "Completed list growth fixture README is missing token: $token"
            }
        }

        $memoryDiagnoseScript = Join-PathParts $RepositoryRoot "skills" "memory-governance" "scripts" "memory_diagnose.ps1"
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

    # Hot memory soft-length fixture checks
    try {
        $hotFixtureRoot = Join-PathParts $RepositoryRoot "scripts" "validation" "memory-diagnose-structural-fixtures" "hot-memory-soft-length"
        $hotFixtureReadme = Get-FileText -RelativePath "scripts/validation/memory-diagnose-structural-fixtures/hot-memory-soft-length/README.md"
        foreach ($token in @("Hot Memory Soft-Length", "concise-current-state", "overloaded-hot-memory", "hot_memory_process_long", "hot_memory_plan_long")) {
            if (-not $hotFixtureReadme.Contains($token)) {
                throw "Hot memory soft-length fixture README is missing token: $token"
            }
        }

        $memoryDiagnoseScript = Join-PathParts $RepositoryRoot "skills" "memory-governance" "scripts" "memory_diagnose.ps1"
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
}
