# test-sensitive-scan.ps1
# Persistent regression tests for the PR sensitive scan and shared contract.
# Called from test-heavy-targeted-regression.ps1 for validation self-protection.
[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$scanScript = Join-Path $scriptDir "pr-secret-keyword-scan.ps1"
$contractPath = Join-Path $scriptDir "sensitive-scan-contract.ps1"
$validatorSource = Join-Path (Split-Path -Parent $scriptDir) "validate-change.ps1"
$rulesSource = Join-Path $scriptDir "change-risk-rules.json"
$runtimeRequirementSource = Join-Path $scriptDir "powershell-runtime-requirement.ps1"

$pass = 0
$fail = 0
$cases = New-Object 'System.Collections.Generic.List[object]'

function Assert-ScanCase {
    param([string]$Name, [bool]$Condition, [string]$Detail)
    if ($Condition) {
        $script:pass++
        $cases.Add([ordered]@{ name = $Name; status = "PASS" })
    } else {
        $script:fail++
        $cases.Add([ordered]@{ name = $Name; status = "FAIL"; detail = $Detail })
    }
}

function Invoke-FixtureGit {
    param([string]$Root, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git -C $Root @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Fixture git failed in '$Root': git $($Arguments -join ' ')" }
    return @($output)
}

function New-GitFixtureRepository {
    param([string]$Root)
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    & git -C $Root init -b main --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not initialize fixture repository '$Root'." }
    Invoke-FixtureGit $Root config user.name "Sensitive Scan Fixture" | Out-Null
    Invoke-FixtureGit $Root config user.email "sensitive-scan-fixture@example.invalid" | Out-Null
}

function Add-GitFixtureCommit {
    param([string]$Root, [string]$Path, [string]$Content, [string]$Message)
    $fullPath = Join-Path $Root $Path
    $parent = Split-Path -Parent $fullPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Set-Content -LiteralPath $fullPath -Value $Content -Encoding utf8
    Invoke-FixtureGit $Root add --all | Out-Null
    Invoke-FixtureGit $Root commit --quiet -m $Message | Out-Null
    return [string](@(Invoke-FixtureGit $Root rev-parse HEAD)[-1])
}

function Remove-GitFixtureCommit {
    param([string]$Root, [string]$Path, [string]$Message)
    Remove-Item -LiteralPath (Join-Path $Root $Path) -Force
    Invoke-FixtureGit $Root add --all | Out-Null
    Invoke-FixtureGit $Root commit --quiet -m $Message | Out-Null
    return [string](@(Invoke-FixtureGit $Root rev-parse HEAD)[-1])
}

function Invoke-ScanFixture {
    param([string]$ScriptPath, [string]$Base, [string]$Head)
    $global:LASTEXITCODE = 0
    $raw = @(& pwsh -NoProfile -File $ScriptPath -BaseRef $Base -HeadRef $Head -Json 2>$null)
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $value = (($raw | ForEach-Object { [string]$_ }) -join "`n") | ConvertFrom-Json
    return [pscustomobject]@{ output = $value; exit_code = $exitCode; raw = $raw }
}

function Invoke-ValidatorFixture {
    param([string]$ScriptPath, [string]$Root, [string]$Base, [string]$Head)
    $global:LASTEXITCODE = 0
    $raw = @(& pwsh -NoProfile -File $ScriptPath -RepositoryRoot $Root -BaseRef $Base -HeadRef $Head -Json 2>&1)
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    return [pscustomobject]@{ output = $raw; exit_code = $exitCode; raw = $raw }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("sensitive-scan-test-{0}" -f ([Guid]::NewGuid().ToString("N")))
$previousLocation = Get-Location
New-GitFixtureRepository $scratch

try {
    # Keep scanner and contract in the baseline so every test diff exercises the same copy.
    Set-Content -LiteralPath (Join-Path $scratch "baseline.md") -Value "# Baseline`nExisting content with token in history." -Encoding UTF8
    New-Item -ItemType Directory -Force -Path (Join-Path $scratch "scripts" "validation") | Out-Null
    Copy-Item -LiteralPath $contractPath -Destination (Join-Path $scratch "scripts" "validation" "sensitive-scan-contract.ps1")
    Copy-Item -LiteralPath $scanScript -Destination (Join-Path $scratch "scripts" "validation" "pr-secret-keyword-scan.ps1")
    Invoke-FixtureGit $scratch add --all | Out-Null
    Invoke-FixtureGit $scratch commit --quiet -m "baseline" | Out-Null
    $baseline = [string](@(Invoke-FixtureGit $scratch rev-parse HEAD)[-1])
    $scanInRepo = Join-Path $scratch "scripts" "validation" "pr-secret-keyword-scan.ps1"
    $contractInRepo = Join-Path $scratch "scripts" "validation" "sensitive-scan-contract.ps1"

    Set-Location $scratch

    # --- Case 1: New non-allowed keyword in an added line -> FAIL ---
    $keywordHead = Add-GitFixtureCommit $scratch "new-file.ps1" '$token = "leaked"' "add keyword"
    $out = Invoke-ScanFixture $scanInRepo $baseline $keywordHead
    Assert-ScanCase -Name "new-keyword-fail" -Condition ([string]$out.output.status -ceq "FAIL" -and [int]$out.output.violation_count -ge 1 -and [int]$out.exit_code -ne 0) -Detail "Expected non-zero FAIL for a new keyword, got $($out.output.status) with exit $($out.exit_code)"

    # --- Case 2: A real deleted line is not scanned -> PASS ---
    $deletedHead = Remove-GitFixtureCommit $scratch "new-file.ps1" "delete keyword"
    $out2 = Invoke-ScanFixture $scanInRepo $keywordHead $deletedHead
    Assert-ScanCase -Name "deleted-line-pass" -Condition ([string]$out2.output.status -ceq "PASS" -and [int]$out2.output.violation_count -eq 0) -Detail "Expected PASS for a real deletion diff, got $($out2.output.status)"

    # --- Case 3: A real context-only keyword is not scanned -> PASS ---
    $contextBase = Add-GitFixtureCommit $scratch "context-file.ps1" "safe line 1`n`$token = 'historical'`nsafe line 3" "context baseline"
    $contextHead = Add-GitFixtureCommit $scratch "context-file.ps1" "safe line 1`n`$token = 'historical'`nsafe line changed" "change nearby line"
    $out3 = Invoke-ScanFixture $scanInRepo $contextBase $contextHead
    Assert-ScanCase -Name "context-line-pass" -Condition ([string]$out3.output.status -ceq "PASS" -and [int]$out3.output.violation_count -eq 0) -Detail "Expected PASS for a real context-only keyword, got $($out3.output.status)"

    # --- Case 4: Keyword in unmodified history -> PASS ---
    $historyHead = Add-GitFixtureCommit $scratch "unrelated.ps1" "Write-Output 'clean'" "unrelated change"
    $out4 = Invoke-ScanFixture $scanInRepo $contextHead $historyHead
    Assert-ScanCase -Name "history-unmodified-pass" -Condition ([string]$out4.output.status -ceq "PASS" -and [int]$out4.output.violation_count -eq 0) -Detail "Expected PASS for an unmodified historical keyword, got $($out4.output.status)"

    # --- Case 5: Allowed path -> PASS ---
    $allowedHead = Add-GitFixtureCommit $scratch "AGENTS.md" "# Guide`nUse token auth." "allowed path"
    $out5 = Invoke-ScanFixture $scanInRepo $historyHead $allowedHead
    Assert-ScanCase -Name "allowed-path-pass" -Condition ([string]$out5.output.status -ceq "PASS") -Detail "Expected PASS for a keyword in an allowed path, got $($out5.output.status)"

    # --- Case 6: Exact allowed reference -> PASS ---
    $workflowText = '  LINEAGE_GITHUB_AUTH: ${{ github.' + 'token }}'
    $exactHead = Add-GitFixtureCommit $scratch ".github/workflows/release-validation.yml" $workflowText "exact reference"
    $out6 = Invoke-ScanFixture $scanInRepo $allowedHead $exactHead
    Assert-ScanCase -Name "exact-reference-pass" -Condition ([string]$out6.output.status -ceq "PASS") -Detail "Expected PASS for an exact allowed reference, got $($out6.output.status)"

    # --- Case 7: Added content beginning with +++ is still scanned -> FAIL ---
    $plusHead = Add-GitFixtureCommit $scratch "plus.txt" "+++ token" "add plus content"
    $out7 = Invoke-ScanFixture $scanInRepo $exactHead $plusHead
    Assert-ScanCase -Name "triple-plus-added-line-fail" -Condition ([string]$out7.output.status -ceq "FAIL" -and [int]$out7.output.violation_count -ge 1 -and [int]$out7.exit_code -ne 0) -Detail "Expected FAIL for added content beginning with +++, got $($out7.output.status) with exit $($out7.exit_code)"

    # --- Case 8: Added content beginning with ++++ is still scanned -> FAIL ---
    $plus4Head = Add-GitFixtureCommit $scratch "plus4.txt" "++++ token" "add four-plus content"
    $out8 = Invoke-ScanFixture $scanInRepo $plusHead $plus4Head
    Assert-ScanCase -Name "four-plus-added-line-fail" -Condition ([string]$out8.output.status -ceq "FAIL" -and [int]$out8.output.violation_count -ge 1 -and [int]$out8.exit_code -ne 0) -Detail "Expected FAIL for added content beginning with ++++, got $($out8.output.status) with exit $($out8.exit_code)"

    # --- Case 9: Missing shared contract remains a scanner failure ---
    $contractBackup = Join-Path $scratch "sensitive-scan-contract.backup.ps1"
    Copy-Item -LiteralPath $contractInRepo -Destination $contractBackup
    Remove-Item -LiteralPath $contractInRepo -Force
    $out9 = Invoke-ScanFixture $scanInRepo $plusHead $plus4Head
    Assert-ScanCase -Name "contract-missing-fail" -Condition ([string]$out9.output.status -ceq "FAIL" -and [string]$out9.output.reason -ceq "contract-missing" -and [int]$out9.exit_code -ne 0) -Detail "Expected contract-missing failure, got $($out9.output.reason) with exit $($out9.exit_code)"
    Copy-Item -LiteralPath $contractBackup -Destination $contractInRepo
    Remove-Item -LiteralPath $contractBackup -Force

    # --- Case 10: Unavailable diff remains a scanner failure ---
    $out10 = Invoke-ScanFixture $scanInRepo "nonexistent-ref-abc" $plus4Head
    Assert-ScanCase -Name "diff-unavailable-fail" -Condition ([string]$out10.output.status -ceq "FAIL" -and [string]$out10.output.reason -ceq "diff-unavailable" -and [int]$out10.exit_code -ne 0) -Detail "Expected diff-unavailable failure, got $($out10.output.reason) with exit $($out10.exit_code)"

    # Build an isolated copy of validate-change.ps1 so missing-file cases do not touch the source checkout.
    $integration = Join-Path $scratch "validate-change-integration"
    New-GitFixtureRepository $integration
    New-Item -ItemType Directory -Force -Path (Join-Path $integration "scripts" "validation") | Out-Null
    Copy-Item -LiteralPath $validatorSource -Destination (Join-Path $integration "scripts" "validate-change.ps1")
    Copy-Item -LiteralPath $rulesSource -Destination (Join-Path $integration "scripts" "validation" "change-risk-rules.json")
    Copy-Item -LiteralPath $runtimeRequirementSource -Destination (Join-Path $integration "scripts" "validation" "powershell-runtime-requirement.ps1")
    Copy-Item -LiteralPath $scanScript -Destination (Join-Path $integration "scripts" "validation" "pr-secret-keyword-scan.ps1")
    Copy-Item -LiteralPath $contractPath -Destination (Join-Path $integration "scripts" "validation" "sensitive-scan-contract.ps1")
    Set-Content -LiteralPath (Join-Path $integration "baseline.md") -Value "clean baseline" -Encoding UTF8
    Invoke-FixtureGit $integration add --all | Out-Null
    Invoke-FixtureGit $integration commit --quiet -m "baseline" | Out-Null
    $integrationBase = [string](@(Invoke-FixtureGit $integration rev-parse HEAD)[-1])
    $integrationHead = Add-GitFixtureCommit $integration "new-file.ps1" '$token = "leaked"' "add violating keyword"
    $validatorInRepo = Join-Path $integration "scripts" "validate-change.ps1"

    # --- Case 11: validate-change propagates a real scanner violation ---
    $validatorViolation = Invoke-ValidatorFixture $validatorInRepo $integration $integrationBase $integrationHead
    $validatorViolationText = ($validatorViolation.raw | ForEach-Object { [string]$_ }) -join "`n"
    Assert-ScanCase -Name "validate-change-keyword-fails" -Condition ($validatorViolation.exit_code -ne 0 -and $validatorViolationText -match "Sensitive scan failure" -and $validatorViolationText -notmatch 'detected_tier.{0,20}3') -Detail "Expected validate-change to fail on scanner violation, got exit $($validatorViolation.exit_code): $validatorViolationText"

    # --- Case 12: validate-change propagates a missing scan script ---
    $integrationScan = Join-Path $integration "scripts" "validation" "pr-secret-keyword-scan.ps1"
    $scanBackup = Join-Path $integration "scan-script.backup.ps1"
    Move-Item -LiteralPath $integrationScan -Destination $scanBackup
    $validatorMissingScan = Invoke-ValidatorFixture $validatorInRepo $integration $integrationBase $integrationHead
    $validatorMissingScanText = ($validatorMissingScan.raw | ForEach-Object { [string]$_ }) -join "`n"
    Assert-ScanCase -Name "validate-change-scan-script-missing-fails" -Condition ($validatorMissingScan.exit_code -ne 0 -and $validatorMissingScanText -match "scan script is missing") -Detail "Expected validate-change to fail when the scan script is missing, got exit $($validatorMissingScan.exit_code): $validatorMissingScanText"
    Move-Item -LiteralPath $scanBackup -Destination $integrationScan

    # --- Case 13: validate-change propagates a missing shared contract ---
    $integrationContract = Join-Path $integration "scripts" "validation" "sensitive-scan-contract.ps1"
    $contractIntegrationBackup = Join-Path $integration "contract.backup.ps1"
    Move-Item -LiteralPath $integrationContract -Destination $contractIntegrationBackup
    $validatorMissingContract = Invoke-ValidatorFixture $validatorInRepo $integration $integrationBase $integrationHead
    $validatorMissingContractText = ($validatorMissingContract.raw | ForEach-Object { [string]$_ }) -join "`n"
    Assert-ScanCase -Name "validate-change-contract-missing-fails" -Condition ($validatorMissingContract.exit_code -ne 0 -and ($validatorMissingContractText -match "contract-missing" -or ($validatorMissingContractText -match "contract" -and $validatorMissingContractText -match "not found"))) -Detail "Expected validate-change to fail when the contract is missing, got exit $($validatorMissingContract.exit_code): $validatorMissingContractText"
    Move-Item -LiteralPath $contractIntegrationBackup -Destination $integrationContract

    # Shared contract remains the only source for scan rules.
    . $contractPath
    $contractKeywords = $SensitiveScanKeywordPattern
    $contractPaths = $SensitiveScanAllowedPaths
    $contractRefs = $SensitiveScanAllowedReferences
    $contractHighRisk = $SensitiveScanHighRiskPatterns
    Assert-ScanCase -Name "shared-contract-keyword" -Condition ($contractKeywords -match 'token') -Detail "Shared contract must define the keyword pattern"
    Assert-ScanCase -Name "shared-contract-paths" -Condition ($contractPaths.Count -gt 30) -Detail "Shared contract must define the allowed paths"
    Assert-ScanCase -Name "shared-contract-refs" -Condition ($contractRefs.ContainsKey(".github/workflows/release-validation.yml")) -Detail "Shared contract must define allowed references"
    Assert-ScanCase -Name "shared-contract-highrisk" -Condition ($contractHighRisk.Count -eq 7) -Detail "Shared contract must define 7 high-risk patterns"
}
finally {
    Set-Location $previousLocation
    if (Test-Path -LiteralPath $scratch) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$status = if ($fail -eq 0) { "PASS" } else { "FAIL" }
$summary = [ordered]@{
    schema_version = 1
    status = $status
    case_count = $cases.Count
    pass = $pass
    fail = $fail
    cases = @($cases.ToArray())
}
if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Output ("sensitive scan fixtures: PASS={0} FAIL={1} CASES={2}" -f $pass, $fail, $cases.Count)
}
if ($fail -gt 0) { exit 1 }
exit 0
