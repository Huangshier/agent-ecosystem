# release-memory-diagnostics-fixture-checks.ps1
# Contains validation checks for memory structural diagnostics fixtures
# (completed-list-growth, hot-memory-soft-length, and directory-index-health).
# Part of the release validator thin-entrypoint refactor.
# Authoritative check names: "structural memory diagnostics fixtures", "hot memory soft-length fixtures".

<#
.SYNOPSIS
    Invoke-ReleaseMemoryDiagnosticsFixtureChecks
    Validates completed-list-growth, hot-memory-soft-length, and directory-index-health memory diagnostics fixture suites.
.PARAMETER RepositoryRoot
    Absolute path to the repository root.
#>
function Invoke-ReleaseMemoryDiagnosticsFixtureChecks {
    param(
        [string]$RepositoryRoot
    )

    # Directory index reference, maintenance rules, and pilot index
    try {
        $directoryIndexReference = Get-FileText -RelativePath "skills/memory-governance/references/directory-index-template.md"
        foreach ($token in @(
            "initial navigation cost",
            "lifecycle status",
            "README.md",
            "INDEX.md",
            "Entry",
            "Summary",
            "Status",
            "Refs",
            "Last reviewed",
            "temporary branches",
            "waiting for checks",
            "next actions",
            "local machine paths",
            "private evidence"
        )) {
            if (-not $directoryIndexReference.Contains($token)) {
                throw "Directory index reference is missing token: $token"
            }
        }

        $memoryGovernanceSkill = Get-FileText -RelativePath "skills/memory-governance/SKILL.md"
        foreach ($token in @(
            "creating or moving an indexed entry",
            "parent directory index",
            "completed",
            "archived",
            "Last reviewed",
            "public-safe facts",
            "Do not automatically create or rewrite directory indexes",
            "directory_missing_index",
            "warning and recommendation only"
        )) {
            if (-not $memoryGovernanceSkill.Contains($token)) {
                throw "Memory governance directory index rules are missing token: $token"
            }
        }

        $memoryGovernanceReadme = Get-FileText -RelativePath "skills/memory-governance/README.md"
        foreach ($token in @("references/directory-index-template.md", "DirectoryIndexRoots", "directory_missing_index", "does not create or modify an index")) {
            if (-not $memoryGovernanceReadme.Contains($token)) {
                throw "Memory governance README directory index entry is missing token: $token"
            }
        }

        $fixtureFamiliesRoot = Join-PathParts $RepositoryRoot "scripts" "validation" "memory-diagnose-structural-fixtures"
        $fixturePilot = Get-FileText -RelativePath "scripts/validation/memory-diagnose-structural-fixtures/README.md"
        foreach ($token in @("Entry", "Summary", "Status", "Refs", "Last reviewed", "repository-relative links", "issue #217 remains open")) {
            if (-not $fixturePilot.Contains($token)) {
                throw "Structural fixture pilot index is missing token: $token"
            }
        }

        $actualFixtureFamilies = @(
            Get-ChildItem -LiteralPath $fixtureFamiliesRoot -Directory |
                Select-Object -ExpandProperty Name |
                Sort-Object
        )
        $indexedFixtureFamilies = @(
            [regex]::Matches($fixturePilot, '\]\((?<target>[a-z0-9][a-z0-9-]*/)\)') |
                ForEach-Object { $_.Groups["target"].Value.TrimEnd('/') } |
                Sort-Object -Unique
        )
        if (-not (Test-ExactArray -Actual $indexedFixtureFamilies -Expected $actualFixtureFamilies)) {
            throw "Structural fixture pilot index does not exactly cover direct fixture families. Indexed: $($indexedFixtureFamilies -join ', '); actual: $($actualFixtureFamilies -join ', ')"
        }

        $script:evidence.directory_index_governance = [ordered]@{
            reference = "skills/memory-governance/references/directory-index-template.md"
            pilot = "scripts/validation/memory-diagnose-structural-fixtures/README.md"
            fixture_families = @($actualFixtureFamilies)
            exact_family_coverage = $true
        }
        Add-Check "directory index governance" "PASS" "Directory index guidance, maintenance rules, public-safe boundaries, and exact pilot fixture-family coverage are present." $evidence.directory_index_governance
    }
    catch {
        Add-Check "directory index governance" "FAIL" $_.Exception.Message
    }

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

    # Directory index health fixture checks
    $directoryFixtureScratch = $null
    try {
        $directoryFixtureRoot = Join-PathParts $RepositoryRoot "scripts" "validation" "memory-diagnose-structural-fixtures" "directory-index-health"
        $directoryFixtureReadme = Get-FileText -RelativePath "scripts/validation/memory-diagnose-structural-fixtures/directory-index-health/README.md"
        foreach ($token in @("Directory Index Health", "directory_missing_index", "symbolic-link or junction", "unchanged fixture-tree")) {
            if (-not $directoryFixtureReadme.Contains($token)) {
                throw "Directory index health fixture README is missing token: $token"
            }
        }

        $directoryExpectedPath = Join-PathParts $directoryFixtureRoot "expected.json"
        $directoryExpected = Get-Content -LiteralPath $directoryExpectedPath -Raw | ConvertFrom-Json
        if ([string]$directoryExpected.family -ne "directory-index-health") {
            throw "Directory index health fixture family mismatch."
        }
        if ([int]$directoryExpected.default_threshold -ne 8) {
            throw "Directory index health fixture must document the default threshold of 8."
        }
        if ([string]$directoryExpected.finding.code -ne "directory_missing_index" -or [string]$directoryExpected.finding.severity -ne "warning") {
            throw "Directory index health fixture finding contract is invalid."
        }

        function Write-DirectoryFixtureFile {
            param(
                [string]$Path,
                [string]$Content = "fixture`n"
            )

            $parent = Split-Path -Parent $Path
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $parent -Force
            }
            [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
        }

        function Add-DirectoryFixtureFiles {
            param(
                [string]$Directory,
                [int]$Count
            )

            $null = New-Item -ItemType Directory -Path $Directory -Force
            for ($index = 1; $index -le $Count; $index++) {
                Write-DirectoryFixtureFile -Path (Join-Path $Directory ("file-{0:D2}.txt" -f $index))
            }
        }

        function Get-DirectoryFixtureSnapshot {
            param([string]$Root)

            $entries = New-Object 'System.Collections.Generic.List[string]'
            $pending = New-Object 'System.Collections.Generic.Stack[string]'
            $pending.Push($Root)
            while ($pending.Count -gt 0) {
                $directoryPath = $pending.Pop()
                foreach ($item in @(Get-ChildItem -LiteralPath $directoryPath -Force)) {
                    $relativePath = $item.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
                    $isReparsePoint = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
                    if ($item.PSIsContainer) {
                        $kind = if ($isReparsePoint) { "L" } else { "D" }
                        $entries.Add(("{0}|{1}|{2}" -f $kind, $relativePath, [int]$item.Attributes))
                        if (-not $isReparsePoint) {
                            $pending.Push($item.FullName)
                        }
                    }
                    else {
                        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
                        $entries.Add(("F|{0}|{1}|{2}|{3}" -f $relativePath, $item.Length, $hash, [int]$item.Attributes))
                    }
                }
            }
            return @($entries | Sort-Object)
        }

        $scratchParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
        $directoryFixtureScratch = Join-Path $scratchParent ("agent-ecosystem-directory-index-health-{0}" -f [guid]::NewGuid().ToString("N"))
        $null = New-Item -ItemType Directory -Path $directoryFixtureScratch
        Write-DirectoryFixtureFile -Path (Join-PathParts $directoryFixtureScratch ".agents" "process.txt") -Content "Current state`n- Fixture active.`n"
        Write-DirectoryFixtureFile -Path (Join-PathParts $directoryFixtureScratch ".agents" "plan.md") -Content "# Plan`n`n- Fixture active.`n"
        Write-DirectoryFixtureFile -Path (Join-PathParts $directoryFixtureScratch ".agents" "notes.md") -Content "# Notes`n`n- Stable fixture fact.`n"

        foreach ($fixtureCase in @($directoryExpected.cases)) {
            $caseRoot = Join-PathParts $directoryFixtureScratch "cases" ([string]$fixtureCase.name)
            Add-DirectoryFixtureFiles -Directory $caseRoot -Count ([int]$fixtureCase.direct_files)
            if ($null -ne $fixtureCase.index_file -and -not [string]::IsNullOrWhiteSpace([string]$fixtureCase.index_file)) {
                Write-DirectoryFixtureFile -Path (Join-Path $caseRoot ([string]$fixtureCase.index_file)) -Content "# Fixture index`n"
            }
            if ($fixtureCase.PSObject.Properties.Name -contains "child_direct_files") {
                $childRoot = Join-Path $caseRoot "child"
                Add-DirectoryFixtureFiles -Directory $childRoot -Count ([int]$fixtureCase.child_direct_files)
                Write-DirectoryFixtureFile -Path (Join-Path $childRoot ([string]$fixtureCase.child_index_file)) -Content "# Child fixture index`n"
            }
        }

        $reparseCase = @($directoryExpected.cases | Where-Object { [string]$_.name -eq "reparse-directory-not-followed" })[0]
        $reparseCaseRoot = Join-PathParts $directoryFixtureScratch "cases" "reparse-directory-not-followed"
        $reparseTarget = Join-PathParts $directoryFixtureScratch "linked-targets" "unindexed"
        Add-DirectoryFixtureFiles -Directory $reparseTarget -Count ([int]$reparseCase.linked_target_direct_files)
        $reparseLink = Join-Path $reparseCaseRoot "linked-unindexed-directory"
        if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
            $null = New-Item -ItemType Junction -Path $reparseLink -Target $reparseTarget
        }
        else {
            $null = New-Item -ItemType SymbolicLink -Path $reparseLink -Target $reparseTarget
        }
        $linkItem = Get-Item -LiteralPath $reparseLink -Force
        if (($linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
            throw "Directory index health fixture did not create a reparse-point directory."
        }

        $memoryDiagnoseScript = Join-PathParts $RepositoryRoot "skills" "memory-governance" "scripts" "memory_diagnose.ps1"
        $snapshotBefore = @(Get-DirectoryFixtureSnapshot -Root $directoryFixtureScratch)
        $baseline = & $memoryDiagnoseScript -ProjectRoot $directoryFixtureScratch -Json | ConvertFrom-Json
        $baselineCodes = @($baseline.findings | ForEach-Object { [string]$_.code })
        if ($baselineCodes.Count -ne 0) {
            throw "Directory index fixture baseline changed without opt-in roots. Actual: $($baselineCodes -join ', ')"
        }

        $caseEvidence = New-Object 'System.Collections.Generic.List[object]'
        foreach ($fixtureCase in @($directoryExpected.cases)) {
            $fixtureName = [string]$fixtureCase.name
            $relativeRoot = "cases/$fixtureName"
            $diagnose = & $memoryDiagnoseScript -ProjectRoot $directoryFixtureScratch -DirectoryIndexRoots $relativeRoot -Json | ConvertFrom-Json
            $indexFindings = @($diagnose.findings | Where-Object { [string]$_.code -eq "directory_missing_index" })
            $expectedCount = [int]$fixtureCase.expected_findings
            if ($indexFindings.Count -ne $expectedCount) {
                throw "Directory index fixture $fixtureName expected $expectedCount findings but got $($indexFindings.Count)."
            }
            if ($fixtureName -eq "missing-index") {
                $finding = $indexFindings[0]
                if ([string]$finding.severity -ne "warning") {
                    throw "directory_missing_index severity should be warning."
                }
                $findingPath = ([string]$finding.path).Replace('\', '/')
                if (-not $findingPath.EndsWith("cases/missing-index")) {
                    throw "directory_missing_index path should point to the diagnosed directory."
                }
                if ([string]$finding.message -notmatch '(^|\D)9(\D|$)') {
                    throw "directory_missing_index message should include the direct file count."
                }
                foreach ($token in @($directoryExpected.finding.recommendation_tokens | ForEach-Object { [string]$_ })) {
                    if ([string]$finding.recommendation -notmatch [regex]::Escape($token)) {
                        throw "directory_missing_index recommendation is missing token: $token"
                    }
                }
            }
            $caseEvidence.Add([ordered]@{
                fixture = $fixtureName
                expected_findings = $expectedCount
                actual_findings = $indexFindings.Count
            })
        }

        $configuredThreshold = & $memoryDiagnoseScript -ProjectRoot $directoryFixtureScratch -DirectoryIndexRoots "cases/missing-index" -DirectoryIndexFileThreshold 9 -Json | ConvertFrom-Json
        if (@($configuredThreshold.findings | Where-Object { [string]$_.code -eq "directory_missing_index" }).Count -ne 0) {
            throw "DirectoryIndexFileThreshold did not override the default threshold."
        }
        $linkedRootDiagnosis = & $memoryDiagnoseScript -ProjectRoot $directoryFixtureScratch -DirectoryIndexRoots "cases/reparse-directory-not-followed/linked-unindexed-directory" -Json | ConvertFrom-Json
        if (@($linkedRootDiagnosis.findings | Where-Object { [string]$_.code -eq "directory_missing_index" }).Count -ne 0) {
            throw "A reparse-point scan root should not be followed."
        }

        $absoluteRejected = $false
        try {
            $null = & $memoryDiagnoseScript -ProjectRoot $directoryFixtureScratch -DirectoryIndexRoots $reparseCaseRoot -Json
        }
        catch {
            $absoluteRejected = $_.Exception.Message -match "relative to ProjectRoot"
        }
        if (-not $absoluteRejected) {
            throw "DirectoryIndexRoots should reject absolute paths."
        }
        $outsideRejected = $false
        try {
            $null = & $memoryDiagnoseScript -ProjectRoot $directoryFixtureScratch -DirectoryIndexRoots "../outside" -Json
        }
        catch {
            $outsideRejected = $_.Exception.Message -match "outside ProjectRoot"
        }
        if (-not $outsideRejected) {
            throw "DirectoryIndexRoots should reject paths outside ProjectRoot."
        }

        $humanOutput = @(& $memoryDiagnoseScript -ProjectRoot $directoryFixtureScratch -DirectoryIndexRoots "cases/missing-index") -join "`n"
        if ($humanOutput -notmatch '\[warning\]\s+directory_missing_index:' -or $humanOutput -notmatch '9 direct files') {
            throw "Human directory index diagnosis output does not preserve the finding contract."
        }

        $snapshotAfter = @(Get-DirectoryFixtureSnapshot -Root $directoryFixtureScratch)
        if (-not (Test-ExactArray -Actual $snapshotAfter -Expected $snapshotBefore)) {
            throw "Directory index diagnosis changed the fixture tree."
        }

        $script:evidence.directory_index_health_fixtures = [ordered]@{
            family = "directory-index-health"
            default_threshold = [int]$directoryExpected.default_threshold
            opt_in_parameter = "DirectoryIndexRoots"
            threshold_parameter = "DirectoryIndexFileThreshold"
            baseline_finding_codes = @($baselineCodes)
            fixture_tree_unchanged = $true
            reparse_kind = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { "junction" } else { "symbolic-link" }
            host = $PSVersionTable.PSEdition
            fixtures = @($caseEvidence.ToArray())
        }
        Add-Check "directory index health fixtures" "PASS" "Opt-in directory index diagnostics cover thresholds, indexes, direct-file counting, reparse exclusion, read-only behavior, and unchanged default findings." $evidence.directory_index_health_fixtures
    }
    catch {
        Add-Check "directory index health fixtures" "FAIL" $_.Exception.Message
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($directoryFixtureScratch) -and (Test-Path -LiteralPath $directoryFixtureScratch)) {
            $resolvedScratch = [System.IO.Path]::GetFullPath($directoryFixtureScratch)
            $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
            if (-not $resolvedScratch.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Split-Path -Leaf $resolvedScratch).StartsWith("agent-ecosystem-directory-index-health-")) {
                throw "Refusing to remove unexpected directory index fixture scratch path: $resolvedScratch"
            }
            Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
        }
    }
}
