# Get-WorkflowSpecLiteFixtureRoot: RepositoryRoot is the checkout root; returns the tracked fixture source directory.
function Get-WorkflowSpecLiteFixtureRoot {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    return Join-PathParts $RepositoryRoot "scripts" "validation" "workflow-spec-lite-fixtures"
}

# Get-WorkflowSpecLiteFixtureText: FixtureRoot is the tracked fixture directory and Name is a fixture file name; reads deterministic UTF-8 fixture text.
function Get-WorkflowSpecLiteFixtureText {
    param(
        [Parameter(Mandatory = $true)][string]$FixtureRoot,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $path = Join-PathParts $FixtureRoot $Name
    if (-not [System.IO.File]::Exists($path)) {
        throw "workflow-spec-lite fixture is missing: $path"
    }

    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    return [System.IO.File]::ReadAllText($path, $strictUtf8)
}

# Write-WorkflowSpecLiteScratchFixture: Path is a scratch fixture path and Text is fixture Markdown; writes with the release validator's existing UTF-8 behavior.
function Write-WorkflowSpecLiteScratchFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

# Invoke-WorkflowSpecLiteFixtureValidation: SpecValidator is validate_spec.ps1 and SpecPath is the fixture; runs the validator and returns JSON output.
function Invoke-WorkflowSpecLiteFixtureValidation {
    param(
        [Parameter(Mandatory = $true)][string]$SpecValidator,
        [Parameter(Mandatory = $true)][string]$SpecPath,
        [switch]$RequireExecutionContract
    )

    if ($RequireExecutionContract.IsPresent) {
        return (& $SpecValidator -SpecPath $SpecPath -RequireExecutionContract -Json | ConvertFrom-Json)
    }

    return (& $SpecValidator -SpecPath $SpecPath -Json | ConvertFrom-Json)
}

# Get-WorkflowSpecLiteNegativeFixtureCases: CompleteSpecText is the passing English fixture; returns deterministic negative cases and expected findings.
function Get-WorkflowSpecLiteNegativeFixtureCases {
    param([Parameter(Mandatory = $true)][string]$CompleteSpecText)

    return @(
        [ordered]@{
            name = "missing-title"
            expected_finding = "metadata_title_missing"
            text = [regex]::Replace($CompleteSpecText, '(?m)^\-\s+\*\*Title\*\*:\s+.*\r?\n', '')
        },
        [ordered]@{
            name = "missing-goals"
            expected_finding = "section_goals_missing"
            text = [regex]::Replace($CompleteSpecText, '(?ms)^## 4\. Goals\s*\r?\n.*?(?=^## 5\.)', '')
        },
        [ordered]@{
            name = "missing-non-goals"
            expected_finding = "section_non_goals_missing"
            text = [regex]::Replace($CompleteSpecText, '(?ms)^## 5\. Non-Goals\s*\r?\n.*?(?=^## 6\.)', '')
        },
        [ordered]@{
            name = "missing-acceptance"
            expected_finding = "section_acceptance_missing"
            text = [regex]::Replace($CompleteSpecText, '(?ms)^## 10\. Acceptance / Evidence\s*\r?\n.*?(?=^## 11\.)', '')
        },
        [ordered]@{
            name = "missing-risks"
            expected_finding = "section_risks_missing"
            text = [regex]::Replace($CompleteSpecText, '(?ms)^## 8\. Risks\s*\r?\n.*?(?=^## 9\.)', '')
        },
        [ordered]@{
            name = "missing-stop-rule"
            expected_finding = "execution_stop_rule_missing"
            text = [regex]::Replace($CompleteSpecText, '(?m)^\-\s+\*\*Stop rule\*\*:\s+.*\r?$', '- **Stop rule**:')
        },
        [ordered]@{
            name = "missing-autonomy-level"
            expected_finding = "execution_autonomy_level_missing"
            text = [regex]::Replace($CompleteSpecText, '(?m)^\-\s+\*\*Autonomy level\*\*:\s+.*\r?$', '- **Autonomy level**:')
        }
    )
}

# Invoke-WorkflowSpecLiteValidatorFixtureSuite: RepositoryRoot, SpecValidator, FixtureDir, and ScratchRoot define the release-validation fixture boundary; returns spec_lite evidence.
function Invoke-WorkflowSpecLiteValidatorFixtureSuite {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$SpecValidator,
        [Parameter(Mandatory = $true)][string]$FixtureDir,
        [Parameter(Mandatory = $true)][string]$ScratchRoot
    )

    New-Item -ItemType Directory -Force -Path $FixtureDir | Out-Null
    Assert-PathInsideRoot -Path $FixtureDir -Root $ScratchRoot

    $fixtureRoot = Get-WorkflowSpecLiteFixtureRoot -RepositoryRoot $RepositoryRoot
    $strictUtf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)

    $completeSpec = Get-WorkflowSpecLiteFixtureText -FixtureRoot $fixtureRoot -Name "complete-spec.md"
    $positivePath = Join-PathParts $FixtureDir "complete-spec.md"
    Write-WorkflowSpecLiteScratchFixture -Path $positivePath -Text $completeSpec
    $positive = Invoke-WorkflowSpecLiteFixtureValidation -SpecValidator $SpecValidator -SpecPath $positivePath -RequireExecutionContract
    if (-not [bool]$positive.pass) {
        throw ("Complete spec fixture failed: {0}" -f (($positive.findings | ConvertTo-Json -Compress -Depth 5)))
    }

    $loopSpec = Get-WorkflowSpecLiteFixtureText -FixtureRoot $fixtureRoot -Name "loop-contract-spec.md"
    $loopPath = Join-PathParts $FixtureDir "loop-contract-spec.md"
    Write-WorkflowSpecLiteScratchFixture -Path $loopPath -Text $loopSpec
    $loopPositive = Invoke-WorkflowSpecLiteFixtureValidation -SpecValidator $SpecValidator -SpecPath $loopPath
    if (-not [bool]$loopPositive.pass) {
        throw ("Loop Contract spec fixture failed: {0}" -f (($loopPositive.findings | ConvertTo-Json -Compress -Depth 5)))
    }

    $chineseSpec = Get-WorkflowSpecLiteFixtureText -FixtureRoot $fixtureRoot -Name "chinese-section-spec.md"
    $chinesePath = Join-PathParts $FixtureDir "chinese-section-spec.md"
    Write-WorkflowSpecLiteScratchFixture -Path $chinesePath -Text $chineseSpec
    $chinesePositive = Invoke-WorkflowSpecLiteFixtureValidation -SpecValidator $SpecValidator -SpecPath $chinesePath -RequireExecutionContract
    if (-not [bool]$chinesePositive.pass) {
        throw ("Chinese section spec fixture failed: {0}" -f (($chinesePositive.findings | ConvertTo-Json -Compress -Depth 5)))
    }

    $chineseNoBomPath = Join-PathParts $FixtureDir "chinese-section-spec-utf8-no-bom.md"
    [System.IO.File]::WriteAllText($chineseNoBomPath, $chineseSpec, $strictUtf8NoBom)
    $chineseNoBomBytes = [System.IO.File]::ReadAllBytes($chineseNoBomPath)
    if ($chineseNoBomBytes.Length -ge 3 -and $chineseNoBomBytes[0] -eq 0xEF -and $chineseNoBomBytes[1] -eq 0xBB -and $chineseNoBomBytes[2] -eq 0xBF) {
        throw "UTF-8 no-BOM Chinese spec fixture unexpectedly contains a BOM."
    }
    $chineseNoBomPositive = Invoke-WorkflowSpecLiteFixtureValidation -SpecValidator $SpecValidator -SpecPath $chineseNoBomPath -RequireExecutionContract
    if (-not [bool]$chineseNoBomPositive.pass) {
        throw ("UTF-8 no-BOM Chinese section spec fixture failed: {0}" -f (($chineseNoBomPositive.findings | ConvertTo-Json -Compress -Depth 5)))
    }

    # Positive fixture: optional Requirements Clarification and Decision Validation sections do not affect validation.
    $optionalSpec = Get-WorkflowSpecLiteFixtureText -FixtureRoot $fixtureRoot -Name "optional-sections-spec.md"
    $optionalPath = Join-PathParts $FixtureDir "optional-sections-spec.md"
    Write-WorkflowSpecLiteScratchFixture -Path $optionalPath -Text $optionalSpec
    $optionalPositive = Invoke-WorkflowSpecLiteFixtureValidation -SpecValidator $SpecValidator -SpecPath $optionalPath
    if (-not [bool]$optionalPositive.pass) {
        throw ("Optional sections spec fixture failed: {0}" -f (($optionalPositive.findings | ConvertTo-Json -Compress -Depth 5)))
    }

    $negativeEvidence = New-Object 'System.Collections.Generic.List[object]'
    foreach ($fixture in @(Get-WorkflowSpecLiteNegativeFixtureCases -CompleteSpecText $completeSpec)) {
        $path = Join-PathParts $FixtureDir ("{0}.md" -f $fixture.name)
        Write-WorkflowSpecLiteScratchFixture -Path $path -Text $fixture.text
        $result = Invoke-WorkflowSpecLiteFixtureValidation -SpecValidator $SpecValidator -SpecPath $path -RequireExecutionContract
        $findingIds = @($result.findings | ForEach-Object { [string]$_.id })
        if ([bool]$result.pass) {
            throw ("Negative fixture unexpectedly passed: {0}" -f $fixture.name)
        }
        if ([string]$fixture.expected_finding -notin $findingIds) {
            throw ("Negative fixture {0} did not report expected finding {1}. Findings: {2}" -f $fixture.name, $fixture.expected_finding, ($findingIds -join ", "))
        }
        $negativeEvidence.Add([ordered]@{
            name = [string]$fixture.name
            expected_finding = [string]$fixture.expected_finding
            findings = @($findingIds)
        })
    }

    return [ordered]@{
        validator = $SpecValidator
        positive_fixture = $positivePath
        positive_variants = @(
            [ordered]@{ name = "loop-contract"; path = $loopPath },
            [ordered]@{ name = "chinese-sections"; path = $chinesePath },
            [ordered]@{ name = "chinese-sections-utf8-no-bom"; path = $chineseNoBomPath },
            [ordered]@{ name = "optional-sections"; path = $optionalPath }
        )
        negative_fixtures = @($negativeEvidence.ToArray())
    }
}
