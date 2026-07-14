[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $PSScriptRoot "validation/release-body-contract-fixtures"
. (Join-Path $PSScriptRoot "validation/release-body-contract.ps1")

$results = New-Object 'System.Collections.Generic.List[object]'

function Assert-Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$ShouldPass,
        [string[]]$ExpectedCodes = @()
    )

    $path = Join-Path $fixtureRoot ($Name + ".md")
    $result = Get-ReleaseBodyContractResult -Text ([IO.File]::ReadAllText($path)) -SourceName $Name
    if ([bool]$result.passed -ne $ShouldPass) {
        throw "Fixture '$Name' passed=$($result.passed), expected $ShouldPass."
    }
    $actualCodes = @($result.errors | ForEach-Object { [string]$_.code })
    foreach ($code in $ExpectedCodes) {
        if ($code -notin $actualCodes) {
            throw "Fixture '$Name' did not report expected code '$code'."
        }
    }
    $results.Add([ordered]@{ name = $Name; expected = $(if ($ShouldPass) { "PASS" } else { "FAIL" }); codes = $actualCodes; status = "PASS" })
}

Assert-Fixture -Name "valid-user-body" -ShouldPass $true
Assert-Fixture -Name "valid-maintainer-record" -ShouldPass $true
Assert-Fixture -Name "valid-governance-outside-markers" -ShouldPass $true
Assert-Fixture -Name "valid-bilingual-user-body" -ShouldPass $true
Assert-Fixture -Name "invalid-issue-pr-mapping" -ShouldPass $false -ExpectedCodes "issue_pr_mapping"
Assert-Fixture -Name "invalid-exact-pass-count" -ShouldPass $false -ExpectedCodes "exact_validation_counts"
Assert-Fixture -Name "invalid-hosted-run-id" -ShouldPass $false -ExpectedCodes "hosted_run_identity"
Assert-Fixture -Name "invalid-platform-matrix" -ShouldPass $false -ExpectedCodes "hosted_platform_matrix"
Assert-Fixture -Name "invalid-waiting-for-merge" -ShouldPass $false -ExpectedCodes "merge_instruction"
Assert-Fixture -Name "invalid-create-tag" -ShouldPass $false -ExpectedCodes "tag_instruction"
Assert-Fixture -Name "invalid-publish-release" -ShouldPass $false -ExpectedCodes "publish_instruction"
Assert-Fixture -Name "invalid-candidate-governance" -ShouldPass $false -ExpectedCodes "candidate_governance"
Assert-Fixture -Name "invalid-zh-after-merge" -ShouldPass $false -ExpectedCodes "merge_instruction"
Assert-Fixture -Name "invalid-zh-waiting-for-merge" -ShouldPass $false -ExpectedCodes "merge_instruction"
Assert-Fixture -Name "invalid-zh-create-tag" -ShouldPass $false -ExpectedCodes "tag_instruction"
Assert-Fixture -Name "invalid-zh-publish-github-release" -ShouldPass $false -ExpectedCodes "publish_instruction"
Assert-Fixture -Name "invalid-zh-release-candidate" -ShouldPass $false -ExpectedCodes "candidate_governance"
Assert-Fixture -Name "invalid-zh-publish-candidate" -ShouldPass $false -ExpectedCodes "candidate_governance"
Assert-Fixture -Name "invalid-zh-release-draft" -ShouldPass $false -ExpectedCodes "candidate_governance"
Assert-Fixture -Name "invalid-zh-maintainer-record" -ShouldPass $false -ExpectedCodes "maintainer_governance"
Assert-Fixture -Name "invalid-zh-maintainer-recommendation" -ShouldPass $false -ExpectedCodes "maintainer_governance"
Assert-Fixture -Name "invalid-zh-before-maintainer-confirmation" -ShouldPass $false -ExpectedCodes "maintainer_governance"
Assert-Fixture -Name "invalid-zh-before-maintainer-review" -ShouldPass $false -ExpectedCodes "maintainer_governance"
Assert-Fixture -Name "invalid-zh-no-additional-commits" -ShouldPass $false -ExpectedCodes "candidate_governance"
Assert-Fixture -Name "invalid-bilingual-hosted-checks" -ShouldPass $false -ExpectedCodes "maintainer_governance"
Assert-Fixture -Name "invalid-marker-missing" -ShouldPass $false -ExpectedCodes "marker_start_count"
Assert-Fixture -Name "invalid-marker-missing-end" -ShouldPass $false -ExpectedCodes "marker_end_count"
Assert-Fixture -Name "invalid-marker-duplicate" -ShouldPass $false -ExpectedCodes "marker_start_count"
Assert-Fixture -Name "invalid-marker-order" -ShouldPass $false -ExpectedCodes "marker_order"

$templatePath = Join-Path $repoRoot "docs/releases/template.md"
$templateResult = Test-ReleaseNoteDocument -Text ([IO.File]::ReadAllText($templatePath)) -RelativePath "docs/releases/template.md"
if (-not $templateResult.passed -or $templateResult.mode -ne "strict-v1") {
    throw "The future release-note template did not pass the strict-v1 contract."
}
$results.Add([ordered]@{ name = "future-template-strict-v1"; expected = "PASS"; codes = @(); status = "PASS" })

$historicalPath = Join-Path $repoRoot "docs/releases/v0.6.0.md"
$historicalResult = Test-ReleaseNoteDocument -Text ([IO.File]::ReadAllText($historicalPath)) -RelativePath "docs/releases/v0.6.0.md"
if (-not $historicalResult.passed -or $historicalResult.mode -ne "legacy-published-through-v0.6.0") {
    throw "Historical v0.6.0 compatibility was not applied explicitly."
}
$results.Add([ordered]@{ name = "historical-v0.6.0-explicit-compatibility"; expected = "PASS"; codes = @(); status = "PASS" })

$releaseRoot = Join-Path $repoRoot "docs/releases"
foreach ($releaseFile in @(Get-ChildItem -LiteralPath $releaseRoot -File -Filter "v*.md" | Sort-Object Name)) {
    $relativePath = "docs/releases/$($releaseFile.Name)"
    $releaseResult = Test-ReleaseNoteDocument -Text ([IO.File]::ReadAllText($releaseFile.FullName)) -RelativePath $relativePath
    if (-not $releaseResult.passed) {
        throw "Release note '$relativePath' failed its '$($releaseResult.mode)' contract."
    }
    $results.Add([ordered]@{ name = "tracked-$($releaseFile.BaseName)"; expected = "PASS"; codes = @(); mode = $releaseResult.mode; status = "PASS" })
}

$futureFixture = [IO.File]::ReadAllText((Join-Path $fixtureRoot "invalid-exact-pass-count.md"))
$futureResult = Test-ReleaseNoteDocument -Text $futureFixture -RelativePath "docs/releases/v0.6.1.md"
if ($futureResult.passed -or $futureResult.mode -ne "strict-v1") {
    throw "A future release note escaped strict validation."
}
$results.Add([ordered]@{ name = "future-version-cannot-use-legacy-compatibility"; expected = "FAIL"; codes = @($futureResult.errors.code); status = "PASS" })

$backdatedResult = Test-ReleaseNoteDocument -Text $futureFixture -RelativePath "docs/releases/v0.5.99.md"
if ($backdatedResult.passed -or $backdatedResult.mode -ne "strict-v1") {
    throw "An unlisted backdated release note escaped strict validation."
}
$results.Add([ordered]@{ name = "unlisted-version-cannot-use-legacy-compatibility"; expected = "FAIL"; codes = @($backdatedResult.errors.code); status = "PASS" })

$summary = [ordered]@{
    schema_version = 1
    pass = $results.Count
    fail = 0
    historical_compatibility = "explicit-published-note-allowlist-through-v0.6.0"
    cases = @($results.ToArray())
}
if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-Output ("release body contract fixtures: PASS={0} FAIL=0" -f $summary.pass)
}
