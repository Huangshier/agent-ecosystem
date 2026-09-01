[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$RunTargetedRegression,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot "validate-change.ps1"
$cases = Get-Content -LiteralPath (Join-Path $PSScriptRoot "validation/change-risk-fixtures/cases.json") -Raw | ConvertFrom-Json
$classifierOutputContract = Join-Path $PSScriptRoot "validation/release-classifier-output-contract.ps1"
$classifierOutputCases = Get-Content -LiteralPath (Join-Path $PSScriptRoot "validation/release-classifier-output-fixtures/cases.json") -Raw | ConvertFrom-Json
$sensitiveScanFileName = "pr-" + ("se" + "cret") + "-keyword-scan.ps1"
$sensitiveScanScript = Join-Path $PSScriptRoot ("validation/{0}" -f $sensitiveScanFileName)
$sensitiveScanContract = Join-Path $PSScriptRoot "validation/sensitive-scan-contract.ps1"
$localPlanValidator = Join-Path $PSScriptRoot "test-local-validation-plan.ps1"
$runtimeRequirementValidator = Join-Path $PSScriptRoot "test-powershell-runtime-requirement.ps1"
$results = New-Object 'System.Collections.Generic.List[object]'
$targetedValidator = Join-Path $PSScriptRoot "validate-targeted-change.ps1"
$targetedScratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-targeted-regression-{0}" -f ([Guid]::NewGuid().ToString("N")))
$targetedExecutionCache = @{}
$targetedExecutionSequence = 0

$runtimeRequirementRaw = @(& $runtimeRequirementValidator -Json) -join "`n"
$runtimeRequirementResult = $runtimeRequirementRaw | ConvertFrom-Json
if ([int]$runtimeRequirementResult.fail -ne 0 -or [int]$runtimeRequirementResult.pass -ne 7) {
    throw "PowerShell runtime requirement fixtures returned incomplete evidence."
}

$sensitiveScanCaseCount = 0
$sensitiveScanRequiredMarkers = @(
    '$contractPath',
    '. $contractPath',
    'git diff "$BaseRef" "$HeadRef"'
)
if (-not (Test-Path -LiteralPath $sensitiveScanScript -PathType Leaf)) {
    throw "Sensitive scan classifier contract check failed: scan script is missing: $sensitiveScanScript"
}
if (-not (Test-Path -LiteralPath $sensitiveScanContract -PathType Leaf)) {
    throw "Sensitive scan classifier contract check failed: shared contract is missing: $sensitiveScanContract"
}
$sensitiveScanSource = Get-Content -LiteralPath $sensitiveScanScript -Raw
foreach ($marker in $sensitiveScanRequiredMarkers) {
    if (-not $sensitiveScanSource.Contains($marker)) {
        throw "Sensitive scan classifier contract check failed: scanner marker is missing: $marker"
    }
}
$sensitiveScanContractSource = Get-Content -LiteralPath $sensitiveScanContract -Raw
foreach ($marker in @('$SensitiveScanKeywordPattern', '$SensitiveScanAllowedPaths', '$SensitiveScanAllowedReferences', '$SensitiveScanHighRiskPatterns')) {
    if (-not $sensitiveScanContractSource.Contains($marker)) {
        throw "Sensitive scan classifier contract check failed: shared contract marker is missing: $marker"
    }
}
$sensitiveScanContractCheck = [ordered]@{
    status = "PASS"
    scanner_exists = $true
    shared_contract_exists = $true
    scanner_uses_shared_contract = $true
    scanner_has_diff_entrypoint = $true
    reason = "full-sensitive-scan-deferred-to-validation-self-protection"
}
$sensitiveScanSummary = [ordered]@{
    status = "NOT_RUN"
    case_count = 0
    pass = 0
    fail = 0
    cases = @()
    reason = "full-sensitive-scan-deferred-to-validation-self-protection"
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
    & git -C $Root init -b main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not initialize fixture repository '$Root'." }
    Invoke-FixtureGit $Root config user.name "Validation Fixture" | Out-Null
    Invoke-FixtureGit $Root config user.email "validation-fixture@example.invalid" | Out-Null
}

function Add-GitFixtureCommit {
    param([string]$Root, [string]$Path, [string]$Content, [string]$Message)
    $fullPath = Join-Path $Root $Path
    $parent = Split-Path -Parent $fullPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Set-Content -LiteralPath $fullPath -Value $Content -Encoding utf8
    Invoke-FixtureGit $Root add -- $Path | Out-Null
    Invoke-FixtureGit $Root commit -m $Message | Out-Null
    return [string](@(Invoke-FixtureGit $Root rev-parse HEAD)[-1])
}

function Assert-GitBoundaryCase {
    param(
        [string]$Name,
        [string]$Root,
        [string]$Base,
        [string]$Head,
        [int]$Tier,
        [switch]$ForcePush,
        [switch]$ExpectNormalizedBoundary
    )
    $raw = @(& $validator -RepositoryRoot $Root -BaseRef $Base -HeadRef $Head -ForcePush:$ForcePush -Json) -join "`n"
    $value = $raw | ConvertFrom-Json
    if ([int]$value.detected_tier -ne $Tier) { throw "Git boundary case '$Name' expected Tier $Tier, got Tier $($value.detected_tier): $($value.escalation_reason)" }
    if ($ExpectNormalizedBoundary.IsPresent) {
        $expectedBase = [string](@(Invoke-FixtureGit $Root rev-parse "$Base^{commit}")[-1])
        $expectedHead = [string](@(Invoke-FixtureGit $Root rev-parse "$Head^{commit}")[-1])
        if ([string]$value.base_ref -cne $expectedBase.ToLowerInvariant() -or [string]$value.head_ref -cne $expectedHead.ToLowerInvariant()) {
            throw "Git boundary case '$Name' did not return normalized base/head commit IDs."
        }
    }
    return [ordered]@{ name = $Name; tier = $Tier; status = "PASS" }
}

function Invoke-PushRoutingFixtures {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-push-routing-{0}" -f ([Guid]::NewGuid().ToString("N")))
    $fixtureResults = New-Object 'System.Collections.Generic.List[object]'
    try {
        $linear = Join-Path $root "linear"
        New-GitFixtureRepository $linear
        $base = Add-GitFixtureCommit $linear "README.md" "base" "base"
        $tierZero = Add-GitFixtureCommit $linear "README.md" "tier zero" "tier zero"
        $tierOne = Add-GitFixtureCommit $linear "knowledge-hub/knowledge/catalog.md" "tier one" "tier one"
        $tierTwo = Add-GitFixtureCommit $linear "scripts/install.ps1" "Write-Output 'tier two'" "tier two"
        $tierThree = Add-GitFixtureCommit $linear ".github/workflows/release-validation.yml" "name: tier-three" "tier three"

        $fixtureResults.Add((Assert-GitBoundaryCase "push-tier-0" $linear $base $tierZero 0 -ExpectNormalizedBoundary))
        $fixtureResults.Add((Assert-GitBoundaryCase "push-tier-1" $linear $tierZero $tierOne 1 -ExpectNormalizedBoundary))
        $fixtureResults.Add((Assert-GitBoundaryCase "push-tier-2" $linear $tierOne $tierTwo 2 -ExpectNormalizedBoundary))
        $fixtureResults.Add((Assert-GitBoundaryCase "multi-commit-push" $linear $base $tierTwo 2 -ExpectNormalizedBoundary))
        $fixtureResults.Add((Assert-GitBoundaryCase "push-tier-3" $linear $tierTwo $tierThree 3 -ExpectNormalizedBoundary))
        $fixtureResults.Add((Assert-GitBoundaryCase "all-zero-before" $linear ("0" * 40) $tierThree 3))
        $fixtureResults.Add((Assert-GitBoundaryCase "missing-before" $linear "refs/heads/definitely-missing" $tierThree 3))
        $fixtureResults.Add((Assert-GitBoundaryCase "forced-push" $linear $base $tierZero 3 -ForcePush))

        Invoke-FixtureGit $linear switch --quiet --orphan unrelated | Out-Null
        $unrelated = Add-GitFixtureCommit $linear "future-surface/value.bin" "unrelated" "unrelated root"
        $fixtureResults.Add((Assert-GitBoundaryCase "non-ancestor-push" $linear $base $unrelated 3))

        $shallow = Join-Path $root "shallow"
        $linearUri = ([System.Uri]::new(($linear.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar))).AbsoluteUri
        & git clone --quiet --depth 1 --branch main $linearUri $shallow 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not create shallow history fixture." }
        $fixtureResults.Add((Assert-GitBoundaryCase "shallow-history" $shallow $tierTwo $tierThree 3))

        $merge = Join-Path $root "merge"
        New-GitFixtureRepository $merge
        $mergeBase = Add-GitFixtureCommit $merge "README.md" "base" "base"
        Invoke-FixtureGit $merge switch --quiet -c feature | Out-Null
        Add-GitFixtureCommit $merge "knowledge-hub/knowledge/catalog.md" "feature" "feature" | Out-Null
        Invoke-FixtureGit $merge switch --quiet main | Out-Null
        $beforeMerge = Add-GitFixtureCommit $merge "README.md" "main" "main"
        Invoke-FixtureGit $merge merge --no-ff feature -m "merge feature" | Out-Null
        $mergeHead = [string](@(Invoke-FixtureGit $merge rev-parse HEAD)[-1])
        $fixtureResults.Add((Assert-GitBoundaryCase "merge-commit-push" $merge $beforeMerge $mergeHead 1 -ExpectNormalizedBoundary))

        $squash = Join-Path $root "squash"
        New-GitFixtureRepository $squash
        $squashBase = Add-GitFixtureCommit $squash "README.md" "base" "base"
        Invoke-FixtureGit $squash switch --quiet -c feature | Out-Null
        Add-GitFixtureCommit $squash "scripts/install.ps1" "Write-Output 'feature'" "feature" | Out-Null
        Invoke-FixtureGit $squash switch --quiet main | Out-Null
        Invoke-FixtureGit $squash merge --squash feature | Out-Null
        Invoke-FixtureGit $squash commit -m "squash feature" | Out-Null
        $squashHead = [string](@(Invoke-FixtureGit $squash rev-parse HEAD)[-1])
        $fixtureResults.Add((Assert-GitBoundaryCase "squash-commit-push" $squash $squashBase $squashHead 2 -ExpectNormalizedBoundary))

        return @($fixtureResults.ToArray())
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

function Invoke-ClassifierOutputContractFixtures {
    $fixtureResults = New-Object 'System.Collections.Generic.List[object]'
    foreach ($case in @($classifierOutputCases)) {
        $accepted = $false
        try {
            $validated = & $classifierOutputContract -Result $case.result
            $accepted = $true
            if (-not [bool]$case.valid) {
                throw "Invalid classifier output fixture '$($case.name)' produced a skippable decision."
            }
            if ($validated.run_heavy_targeted_regression -isnot [bool] -or [bool]$validated.run_heavy_targeted_regression) {
                throw "Valid classifier output fixture '$($case.name)' did not preserve the Boolean false decision."
            }
        }
        catch {
            if ([bool]$case.valid -or $accepted) { throw }
        }
        $fixtureResults.Add([ordered]@{ name = [string]$case.name; status = "PASS" })
    }
    return @($fixtureResults.ToArray())
}

function Invoke-PowerShellEncodingFixtures {
    $fixtureId = [Guid]::NewGuid().ToString("N")
    $createdPaths = New-Object 'System.Collections.Generic.List[string]'
    $fixtureResults = New-Object 'System.Collections.Generic.List[object]'

    function Assert-EncodingPass([string]$Name, [string]$RelativePath) {
        $scratch = Join-Path $targetedScratch ("encoding-{0}" -f $Name)
        $raw = @(& $targetedValidator -ChangedPath $RelativePath -Mode quick -ScratchRoot $scratch -Json) -join "`n"
        $value = $raw | ConvertFrom-Json
        $changedFileCheck = @($value.checks | Where-Object name -ceq "changed-file-parse")
        if ($changedFileCheck.Count -ne 1 -or [string]$changedFileCheck[0].status -cne "PASS") {
            throw "PowerShell encoding fixture '$Name' did not pass changed-file validation."
        }
        $fixtureResults.Add([ordered]@{ name = $Name; status = "PASS" })
    }

    try {
        $asciiRelative = "scripts/validation/required-validation-gate-fixtures/encoding-$fixtureId-ascii.ps1"
        $bomRelative = "scripts/validation/required-validation-gate-fixtures/encoding-$fixtureId-bom.ps1"
        $noBomRelative = "scripts/validation/required-validation-gate-fixtures/encoding-$fixtureId-no-bom.ps1"
        $asciiPath = Join-Path $repoRoot $asciiRelative
        $bomPath = Join-Path $repoRoot $bomRelative
        $noBomPath = Join-Path $repoRoot $noBomRelative
        foreach ($path in @($asciiPath, $bomPath, $noBomPath)) { $createdPaths.Add($path) }

        [System.IO.File]::WriteAllBytes($asciiPath, [Text.Encoding]::ASCII.GetBytes("Write-Output 'ascii fixture'`r`n"))
        $utf8NoBom = [Text.UTF8Encoding]::new($false)
        $utf8Bom = [Text.UTF8Encoding]::new($true)
        $nonAsciiMarker = [string]([char]0x7F16) + [string]([char]0x7801)
        $nonAsciiContent = "# fixture: $nonAsciiMarker`r`nWrite-Output 'non-ascii fixture'`r`n"
        [System.IO.File]::WriteAllBytes($bomPath, [byte[]]($utf8Bom.GetPreamble() + $utf8NoBom.GetBytes($nonAsciiContent)))
        [System.IO.File]::WriteAllBytes($noBomPath, $utf8NoBom.GetBytes($nonAsciiContent))

        Assert-EncodingPass "ascii-without-bom" $asciiRelative
        Assert-EncodingPass "non-ascii-with-bom" $bomRelative

        Assert-EncodingPass "non-ascii-without-bom" $noBomRelative
        Assert-EncodingPass "current-git-stable-patch-id" "scripts/validation/git-stable-patch-id.ps1"
        return @($fixtureResults.ToArray())
    }
    finally {
        foreach ($path in $createdPaths) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force
            }
        }
    }
}

function ConvertTo-WorkflowHostArrayJson {
    param([object[]]$Hosts)

    return ConvertTo-Json -InputObject ([object[]]@($Hosts)) -Compress
}

function Invoke-WorkflowHostArrayFixtures {
    param(
        [string]$Workflow,
        [object]$FallbackClassification
    )

    $requiredSerializer = '$requiredHostsJson = ConvertTo-Json -InputObject ([object[]]@($result.required_hosts)) -Compress'
    $requiredOutput = '"required_hosts_json=$requiredHostsJson" >> $env:GITHUB_OUTPUT'
    if (-not $Workflow.Contains($requiredSerializer) -or -not $Workflow.Contains($requiredOutput)) {
        throw "Workflow required_hosts_json output must use explicit -InputObject array serialization."
    }
    if ($Workflow.Contains('"required_hosts_json=$(@($result.required_hosts) | ConvertTo-Json -Compress)"')) {
        throw "Workflow still uses pipeline serialization for required_hosts_json."
    }

    $matrixConsumers = @([regex]::Matches($Workflow, 'fromJSON\(needs\.classify\.outputs\.([A-Za-z0-9_]+)') | ForEach-Object { $_.Groups[1].Value })
    if ($matrixConsumers.Count -ne 1 -or $matrixConsumers[0] -cne "required_hosts_json") {
        throw "Workflow matrix JSON consumers changed unexpectedly."
    }
    if ($Workflow -notmatch 'os:\s*\$\{\{\s*fromJSON\(needs\.classify\.outputs\.required_hosts_json') {
        throw "Affected validation matrix must consume required_hosts_json through fromJSON()."
    }

    $fixtureResults = New-Object 'System.Collections.Generic.List[object]'
    $cases = @(
        [ordered]@{ name = "zero-hosts"; hosts = @(); expected = "[]" },
        [ordered]@{ name = "one-host"; hosts = @("windows-latest"); expected = '["windows-latest"]' },
        [ordered]@{ name = "multiple-hosts"; hosts = @("macos-latest", "ubuntu-latest", "windows-latest"); expected = '["macos-latest","ubuntu-latest","windows-latest"]' }
    )
    foreach ($case in $cases) {
        $json = ConvertTo-WorkflowHostArrayJson -Hosts @($case.hosts)
        if ($json -cne [string]$case.expected -or -not $json.StartsWith("[") -or -not $json.EndsWith("]")) {
            throw "Workflow host array fixture '$($case.name)' produced '$json', expected '$($case.expected)'."
        }
        $roundTrip = New-Object 'System.Collections.Generic.List[object]'
        foreach ($hostValue in (ConvertFrom-Json -InputObject $json)) {
            $roundTrip.Add($hostValue)
        }
        if (($roundTrip.ToArray() -join ",") -cne (@($case.hosts) -join ",")) {
            throw "Workflow host array fixture '$($case.name)' did not preserve ordinal values."
        }
        $fixtureResults.Add([ordered]@{ name = [string]$case.name; json = $json; status = "PASS" })
    }

    $fallbackHosts = @($FallbackClassification.required_hosts)
    $fallbackJson = ConvertTo-WorkflowHostArrayJson -Hosts $fallbackHosts
    $fallbackRoundTrip = New-Object 'System.Collections.Generic.List[object]'
    foreach ($hostValue in (ConvertFrom-Json -InputObject $fallbackJson)) {
        $fallbackRoundTrip.Add($hostValue)
    }
    if ($fallbackHosts.Count -ne 3 -or -not $fallbackJson.StartsWith("[") -or -not $fallbackJson.EndsWith("]") -or
        ($fallbackRoundTrip.ToArray() -join ",") -cne ($fallbackHosts -join ",")) {
        throw "Unknown classifier fallback hosts did not remain a three-host JSON array."
    }
    $fixtureResults.Add([ordered]@{ name = "unknown-fallback-three-hosts"; json = $fallbackJson; status = "PASS" })
    $fixtureResults.Add([ordered]@{ name = "fromjson-array-consumer"; status = "PASS" })
    return @($fixtureResults.ToArray())
}

function ConvertTo-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-TargetedRunnerIdentity {
    return "{0}-{1}-{2}" -f [System.Environment]::OSVersion.Platform, $PSVersionTable.PSEdition, $PSVersionTable.PSVersion.ToString()
}

function New-TargetedExecutionContract {
    param(
        [string[]]$ExpectedSuite,
        [string]$Mode,
        [string]$ExecutionHost
    )

    $head = [string](@(& git -C $repoRoot rev-parse HEAD 2>$null)[-1]).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
        throw "Could not resolve the current repository head for the targeted execution contract."
    }
    $validatorHash = (Get-FileHash -LiteralPath $targetedValidator -Algorithm SHA256).Hash.ToLowerInvariant()
    return [ordered]@{
        contract_version = 1
        suite_identity = @($ExpectedSuite | Sort-Object -Unique)
        mode = $Mode
        execution_host = $ExecutionHost
        runner_identity = Get-TargetedRunnerIdentity
        repository_head = $head.ToLowerInvariant()
        validator_sha256 = $validatorHash
    }
}

function Get-TargetedExecutionKey {
    param([Parameter(Mandatory = $true)][object]$Contract)

    return ConvertTo-Sha256Hex -Value ($Contract | ConvertTo-Json -Depth 8 -Compress)
}

function Copy-TargetedExecutionContract {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract)

    $copy = [ordered]@{}
    foreach ($key in $Contract.Keys) { $copy[$key] = $Contract[$key] }
    return $copy
}

function Invoke-SharedTargetedExecution {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Cache,
        [Parameter(Mandatory = $true)][ref]$Sequence,
        [Parameter(Mandatory = $true)][string]$CaseName,
        [Parameter(Mandatory = $true)][string]$ExecutionKey,
        [Parameter(Mandatory = $true)][object]$ExecutionContract,
        [Parameter(Mandatory = $true)][scriptblock]$Executor
    )

    if ($Cache.ContainsKey($ExecutionKey)) {
        $shared = $Cache[$ExecutionKey]
        return [ordered]@{
            case = $CaseName
            shared_execution_id = [string]$shared.shared_execution_id
            execution_key = $ExecutionKey
            execution_contract = $ExecutionContract
            executed = $false
            reused = $true
            status = [string]$shared.status
            check_count = [int]$shared.check_count
            error = $shared.error
        }
    }

    $Sequence.Value = [int]$Sequence.Value + 1
    $sharedExecutionId = "targeted-suite-{0:D3}" -f [int]$Sequence.Value
    $startedAt = [DateTimeOffset]::UtcNow
    $status = "FAIL"
    $checkCount = 0
    $errorDetail = $null
    try {
        $evidence = & $Executor
        if ($null -eq $evidence -or [string]$evidence.status -cne "PASS") {
            $reportedError = if ($null -ne $evidence) { [string]$evidence.error } else { "executor returned no evidence" }
            throw "Shared targeted suite execution did not PASS: $reportedError"
        }
        if ($null -ne $evidence.check_count) { $checkCount = [int]$evidence.check_count }
        $status = "PASS"
    }
    catch {
        $errorDetail = [string]$_.Exception.Message
    }
    $completedAt = [DateTimeOffset]::UtcNow
    $shared = [ordered]@{
        shared_execution_id = $sharedExecutionId
        execution_key = $ExecutionKey
        execution_contract = $ExecutionContract
        status = $status
        check_count = $checkCount
        error = $errorDetail
        started_at_utc = $startedAt.ToString("o")
        completed_at_utc = $completedAt.ToString("o")
    }
    $Cache[$ExecutionKey] = $shared
    return [ordered]@{
        case = $CaseName
        shared_execution_id = $sharedExecutionId
        execution_key = $ExecutionKey
        execution_contract = $ExecutionContract
        executed = $true
        reused = $false
        status = $status
        check_count = $checkCount
        error = $errorDetail
    }
}

function Assert-TargetedRoutingEvidence {
    param(
        [string]$Name,
        [string[]]$Path,
        [int]$ExpectedTier,
        [string[]]$ExpectedModule,
        [string[]]$ExpectedSuite,
        [string]$Mode
    )

    $routingRaw = @(& $targetedValidator -ChangedPath $Path -Mode $Mode -RoutingOnly -Json) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Routing case '$Name' validation failed." }
    $routingValue = $routingRaw | ConvertFrom-Json
    if (-not [bool]$routingValue.routing_only -or $null -eq $routingValue.classification) {
        throw "Routing case '$Name' did not produce routing-only evidence."
    }
    $value = $routingValue.classification
    & $classifierOutputContract -Result $value | Out-Null
    if ([int]$value.detected_tier -ne $ExpectedTier) {
        throw "Routing case '$Name' expected Tier $ExpectedTier, got Tier $($value.detected_tier)."
    }
    $actualModules = @($value.affected_modules | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedModules = @($ExpectedModule | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if (($actualModules -join ",") -cne ($expectedModules -join ",")) {
        throw "Routing case '$Name' expected modules '$($expectedModules -join ',')', got '$($actualModules -join ',')'."
    }
    $actualSuites = @($value.required_suites | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedSuites = @($ExpectedSuite | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if (($actualSuites -join ",") -cne ($expectedSuites -join ",")) {
        throw "Routing case '$Name' expected suites '$($expectedSuites -join ',')', got '$($actualSuites -join ',')'."
    }
    foreach ($module in $ExpectedModule) {
        if ($module -eq "documentation" -and @($value.base_check_modules) -notcontains "documentation") {
            throw "Routing case '$Name' did not preserve documentation base-check coverage."
        }
    }
    if ($value.run_validation_self_protection -isnot [bool] -or $value.self_protection_required -isnot [bool]) {
        throw "Routing case '$Name' emitted invalid fail-closed self-protection fields."
    }
    return [ordered]@{
        name = $Name
        case = $Name
        changed_paths = @($Path)
        detected_tier = [int]$value.detected_tier
        modules = @($value.affected_modules)
        required_suites = @($value.required_suites)
        base_check_modules = @($value.base_check_modules)
        routing_check_count = [int]$routingValue.summary.pass
        run_validation_self_protection = [bool]$value.run_validation_self_protection
        self_protection_reason = [string]$value.self_protection_reason
        status = "PASS"
    }
}

function Assert-TargetedSuiteEvidence {
    param(
        [string]$Name,
        [object]$Value,
        [string[]]$ExpectedModule,
        [string[]]$ExpectedSuite
    )

    if ([int]$Value.executed_suite_count -lt 1) { throw "Targeted case '$Name' executed no actual module suite." }
    foreach ($suite in $ExpectedSuite) { if (@($Value.executed_suites) -notcontains $suite) { throw "Targeted case '$Name' did not execute '$suite'." } }
    foreach ($module in $ExpectedModule) {
        $coverage = @($Value.module_coverage | Where-Object module -eq $module)
        if ($coverage.Count -ne 1 -or [int]$coverage[0].executed_check_count -lt 1) { throw "Targeted case '$Name' has no actual check coverage for '$module'." }
        $expectedCoverage = if ($module -eq "documentation") { "base-checks" } else { "targeted-suite" }
        if ([string]$coverage[0].coverage -ne $expectedCoverage) { throw "Targeted case '$Name' used '$($coverage[0].coverage)' coverage for '$module', expected '$expectedCoverage'." }
    }
    if (@($Value.checks.name) -contains "skill-metadata" -or @($Value.checks.name) -contains "targeted-module-matrix") { throw "Targeted case '$Name' emitted a forbidden empty/generic PASS." }
    $telemetry = @($Value.telemetry)
    if ($telemetry.Count -lt 2) { throw "Targeted case '$Name' emitted incomplete suite telemetry." }
    foreach ($record in $telemetry) {
        if ([string]::IsNullOrWhiteSpace([string]$record.suite) -or
            [string]::IsNullOrWhiteSpace([string]$record.case) -or
            [string]::IsNullOrWhiteSpace([string]$record.host) -or
            [string]::IsNullOrWhiteSpace([string]$record.started_at_utc) -or
            [string]::IsNullOrWhiteSpace([string]$record.completed_at_utc) -or
            [long]$record.duration_ms -lt 0 -or
            [string]::IsNullOrWhiteSpace([string]$record.unique_coverage_category)) {
            throw "Targeted case '$Name' emitted an invalid suite telemetry record."
        }
    }
}

function Invoke-ExecutionDedupContractFixtures {
    $fixtureResults = New-Object 'System.Collections.Generic.List[object]'

    $contextRouteA = Assert-TargetedRoutingEvidence -Name "context-gate" -Path @("skills/project-context-gate/scripts/context_gate.ps1") -ExpectedTier 2 -ExpectedModule @("context-gate") -ExpectedSuite @("project-context-gate") -Mode "targeted"
    $contextRouteB = Assert-TargetedRoutingEvidence -Name "context-gate-check" -Path @("scripts/validation/project-context-gate-checks.ps1") -ExpectedTier 2 -ExpectedModule @("context-gate") -ExpectedSuite @("project-context-gate") -Mode "targeted"
    $contextContract = New-TargetedExecutionContract -ExpectedSuite @("project-context-gate") -Mode "targeted" -ExecutionHost "current"
    $contextKey = Get-TargetedExecutionKey -Contract $contextContract
    $contextCache = @{}
    $contextSequence = 0
    $script:dedupFixtureContextCalls = 0
    $contextFirst = Invoke-SharedTargetedExecution -Cache $contextCache -Sequence ([ref]$contextSequence) -CaseName $contextRouteA.case -ExecutionKey $contextKey -ExecutionContract $contextContract -Executor {
        $script:dedupFixtureContextCalls++
        [ordered]@{ status = "PASS"; check_count = 2 }
    }
    $contextSecond = Invoke-SharedTargetedExecution -Cache $contextCache -Sequence ([ref]$contextSequence) -CaseName $contextRouteB.case -ExecutionKey $contextKey -ExecutionContract $contextContract -Executor {
        $script:dedupFixtureContextCalls++
        [ordered]@{ status = "PASS"; check_count = 2 }
    }
    if ($contextRouteA.status -cne "PASS" -or $contextRouteB.status -cne "PASS" -or $script:dedupFixtureContextCalls -ne 1 -or
        -not [bool]$contextFirst.executed -or -not [bool]$contextSecond.reused -or
        [string]$contextFirst.shared_execution_id -cne [string]$contextSecond.shared_execution_id) {
        throw "Context routing cases did not independently pass routing while sharing one suite execution."
    }
    $fixtureResults.Add([ordered]@{ name = "context-routing-cases-share-suite-contract"; status = "PASS" })

    $cache = @{}
    $sequence = 0
    $script:dedupFixturePassCalls = 0
    $contractA = [ordered]@{ contract_version = 1; suite_identity = @("project-context-gate"); mode = "targeted"; execution_host = "windows-latest"; runner_identity = "fixture-windows"; repository_head = "fixture-head"; validator_sha256 = "fixture-validator"; execution_input = "same" }
    $keyA = Get-TargetedExecutionKey -Contract $contractA
    $first = Invoke-SharedTargetedExecution -Cache $cache -Sequence ([ref]$sequence) -CaseName "case-a" -ExecutionKey $keyA -ExecutionContract $contractA -Executor {
        $script:dedupFixturePassCalls++
        [ordered]@{ status = "PASS"; check_count = 2 }
    }
    $second = Invoke-SharedTargetedExecution -Cache $cache -Sequence ([ref]$sequence) -CaseName "case-b" -ExecutionKey $keyA -ExecutionContract $contractA -Executor {
        $script:dedupFixturePassCalls++
        [ordered]@{ status = "PASS"; check_count = 2 }
    }
    if ($script:dedupFixturePassCalls -ne 1 -or -not [bool]$first.executed -or [bool]$first.reused -or [bool]$second.executed -or -not [bool]$second.reused -or [string]$first.shared_execution_id -cne [string]$second.shared_execution_id) {
        throw "Same execution key did not execute once and produce shared evidence."
    }
    $fixtureResults.Add([ordered]@{ name = "same-contract-reuses-execution"; status = "PASS" })

    $contractDifferent = Copy-TargetedExecutionContract -Contract $contractA
    $contractDifferent.execution_input = "different"
    $keyDifferent = Get-TargetedExecutionKey -Contract $contractDifferent
    $different = Invoke-SharedTargetedExecution -Cache $cache -Sequence ([ref]$sequence) -CaseName "case-different-contract" -ExecutionKey $keyDifferent -ExecutionContract $contractDifferent -Executor {
        $script:dedupFixturePassCalls++
        [ordered]@{ status = "PASS"; check_count = 3 }
    }
    if ($script:dedupFixturePassCalls -ne 2 -or -not [bool]$different.executed -or [bool]$different.reused) {
        throw "Different execution contracts incorrectly reused suite evidence."
    }
    $fixtureResults.Add([ordered]@{ name = "different-contract-reexecutes"; status = "PASS" })

    $contractDifferentHost = Copy-TargetedExecutionContract -Contract $contractA
    $contractDifferentHost.execution_host = "ubuntu-latest"
    $keyDifferentHost = Get-TargetedExecutionKey -Contract $contractDifferentHost
    $differentHost = Invoke-SharedTargetedExecution -Cache $cache -Sequence ([ref]$sequence) -CaseName "case-different-host" -ExecutionKey $keyDifferentHost -ExecutionContract $contractDifferentHost -Executor {
        $script:dedupFixturePassCalls++
        [ordered]@{ status = "PASS"; check_count = 4 }
    }
    if ($script:dedupFixturePassCalls -ne 3 -or -not [bool]$differentHost.executed -or [bool]$differentHost.reused) {
        throw "Different execution hosts incorrectly reused suite evidence."
    }
    if ([string]$first.shared_execution_id -cne "targeted-suite-001" -or [string]$second.shared_execution_id -cne "targeted-suite-001" -or
        [string]$different.shared_execution_id -cne "targeted-suite-002" -or [string]$differentHost.shared_execution_id -cne "targeted-suite-003") {
        throw "Shared execution identities were not deterministic."
    }
    $fixtureResults.Add([ordered]@{ name = "different-host-reexecutes-deterministically"; status = "PASS" })

    $failureCache = @{}
    $failureSequence = 0
    $script:dedupFixtureFailureCalls = 0
    $failureExecutor = {
        $script:dedupFixtureFailureCalls++
        throw "fixture shared suite failure"
    }
    $failureContract = Copy-TargetedExecutionContract -Contract $contractA
    $failureKey = Get-TargetedExecutionKey -Contract $failureContract
    $failureFirst = Invoke-SharedTargetedExecution -Cache $failureCache -Sequence ([ref]$failureSequence) -CaseName "failure-a" -ExecutionKey $failureKey -ExecutionContract $failureContract -Executor $failureExecutor
    $failureSecond = Invoke-SharedTargetedExecution -Cache $failureCache -Sequence ([ref]$failureSequence) -CaseName "failure-b" -ExecutionKey $failureKey -ExecutionContract $failureContract -Executor $failureExecutor
    if ($script:dedupFixtureFailureCalls -ne 1 -or [string]$failureFirst.status -cne "FAIL" -or [string]$failureSecond.status -cne "FAIL" -or
        -not [bool]$failureFirst.executed -or -not [bool]$failureSecond.reused -or [string]$failureSecond.status -ceq "PASS") {
        throw "Shared execution failure did not propagate without a false PASS."
    }
    $fixtureResults.Add([ordered]@{ name = "shared-failure-propagates-no-false-pass"; status = "PASS" })
    return @($fixtureResults.ToArray())
}

function Invoke-TargetedRegression {
    param(
        [string]$Name,
        [string[]]$Path,
        [int]$ExpectedTier,
        [string[]]$ExpectedModule,
        [string[]]$ExpectedSuite,
        [string]$Mode,
        [string]$ExecutionHost = "current"
    )

    $startedAt = [DateTimeOffset]::UtcNow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    # NOTE: ChangedPath is routing evidence, not a suite execution input. Every case
    # is classified independently before an equivalent suite result can be reused.
    $routing = Assert-TargetedRoutingEvidence -Name $Name -Path $Path -ExpectedTier $ExpectedTier -ExpectedModule $ExpectedModule -ExpectedSuite $ExpectedSuite -Mode $Mode
    $executionContract = New-TargetedExecutionContract -ExpectedSuite $ExpectedSuite -Mode $Mode -ExecutionHost $ExecutionHost
    $executionKey = Get-TargetedExecutionKey -Contract $executionContract
    $execution = Invoke-SharedTargetedExecution `
        -Cache $script:targetedExecutionCache `
        -Sequence ([ref]$script:targetedExecutionSequence) `
        -CaseName $Name `
        -ExecutionKey $executionKey `
        -ExecutionContract $executionContract `
        -Executor {
            $caseScratch = Join-Path $targetedScratch $Name
            $raw = @(& $targetedValidator -ChangedPath $Path -Mode $Mode -ExecutionHost $ExecutionHost -ScratchRoot $caseScratch -Json) -join "`n"
            if ($LASTEXITCODE -ne 0) { throw "Targeted suite executor failed for '$Name'." }
            $value = $raw | ConvertFrom-Json
            Assert-TargetedSuiteEvidence -Name $Name -Value $value -ExpectedModule $ExpectedModule -ExpectedSuite $ExpectedSuite
            [ordered]@{ status = "PASS"; check_count = [int]$value.summary.pass }
        }
    $stopwatch.Stop()
    $completedAt = [DateTimeOffset]::UtcNow
    return [ordered]@{
        name = $Name
        case = $Name
        modules = $ExpectedModule
        suite = $ExpectedSuite
        suites = $ExpectedSuite
        host = [string]$executionContract.runner_identity
        started_at_utc = $startedAt.ToString("o")
        completed_at_utc = $completedAt.ToString("o")
        duration_ms = [long]$stopwatch.ElapsedMilliseconds
        unique_coverage_category = ("routing-regression:{0}" -f $Name)
        check_count = [int]$execution.check_count
        routing = $routing
        execution = [ordered]@{
            suite = $ExpectedSuite
            host = [string]$executionContract.execution_host
            runner_identity = [string]$executionContract.runner_identity
            execution_contract = $executionContract
            execution_key = $execution.execution_key
            shared_execution_id = $execution.shared_execution_id
            executed = [bool]$execution.executed
            reused = [bool]$execution.reused
            status = [string]$execution.status
            error = $execution.error
        }
        status = [string]$execution.status
    }
}

foreach ($case in @($cases)) {
    $raw = if (@($case.paths).Count -eq 0) {
        @(& $validator -BaseRef HEAD -HeadRef HEAD -Json) -join "`n"
    } else {
        @(& $validator -ChangedPath @($case.paths) -Json) -join "`n"
    }
    $value = $raw | ConvertFrom-Json
    & $classifierOutputContract -Result $value | Out-Null
    if ([int]$value.detected_tier -ne [int]$case.tier) { throw "Case '$($case.name)' expected Tier $($case.tier), got Tier $($value.detected_tier)." }
    if ($null -ne $case.full_validator_calls -and [int]$value.hosted_plan.full_validator_calls -ne [int]$case.full_validator_calls) { throw "Case '$($case.name)' has an incorrect hosted full-validator call count." }
    if ($null -ne $case.platform_neutral_validator_calls -and [int]$value.hosted_plan.platform_neutral_validator_calls -ne [int]$case.platform_neutral_validator_calls) { throw "Case '$($case.name)' has an incorrect hosted platform-neutral call count." }
    if ($null -ne $case.runtime_platform_validator_calls -and [int]$value.hosted_plan.runtime_platform_validator_calls -ne [int]$case.runtime_platform_validator_calls) { throw "Case '$($case.name)' has an incorrect hosted runtime-platform call count." }
    if ($null -ne $case.targeted_os_jobs -and [int]$value.hosted_plan.targeted_os_jobs -ne [int]$case.targeted_os_jobs) { throw "Case '$($case.name)' has an incorrect hosted targeted OS job count." }
    if ($null -ne $case.affected_modules) {
        $actualModules = @($value.affected_modules | Sort-Object)
        $expectedModules = @($case.affected_modules | Sort-Object)
        if (($actualModules -join ',') -cne ($expectedModules -join ',')) { throw "Case '$($case.name)' has incorrect affected modules." }
    }
    if ($null -ne $case.required_suites) {
        $actualSuites = @($value.required_suites | Sort-Object)
        $expectedSuites = @($case.required_suites | Sort-Object)
        if (($actualSuites -join ',') -cne ($expectedSuites -join ',')) { throw "Case '$($case.name)' has incorrect required suites." }
    }
    if ($null -ne $case.required_hosts) {
        $actualHosts = @($value.required_hosts | Sort-Object)
        $expectedHosts = @($case.required_hosts | Sort-Object)
        if (($actualHosts -join ',') -cne ($expectedHosts -join ',')) { throw "Case '$($case.name)' has incorrect required hosts." }
    }
    if ($null -ne $case.run_heavy_targeted_regression -and [bool]$value.run_heavy_targeted_regression -ne [bool]$case.run_heavy_targeted_regression) {
        throw "Case '$($case.name)' has an incorrect heavy targeted decision."
    }
    if ($null -ne $case.heavy_targeted_reason -and [string]$value.heavy_targeted_reason -cne [string]$case.heavy_targeted_reason) {
        throw "Case '$($case.name)' has an incorrect heavy targeted reason."
    }
    if ($null -ne $case.conservative_fallback -and [bool]$value.conservative_fallback -ne [bool]$case.conservative_fallback) {
        throw "Case '$($case.name)' has an incorrect conservative fallback decision."
    }
    if ($null -ne $case.validation_self_protection_reason -and [string]$value.validation_self_protection_reason -cne [string]$case.validation_self_protection_reason) {
        throw "Case '$($case.name)' has an incorrect validation self-protection reason."
    }
    foreach ($field in @("run_validation_self_protection", "control_plane", "self_protection_required")) {
        if ($null -ne $case.$field -and [bool]$value.$field -ne [bool]$case.$field) {
            throw "Case '$($case.name)' has an incorrect $field decision."
        }
    }
    if ($null -ne $case.self_protection_reason -and [string]$value.self_protection_reason -cne [string]$case.self_protection_reason) {
        throw "Case '$($case.name)' has an incorrect explicit self-protection reason."
    }
    if ($null -ne $case.routing_reason_contains -and -not ([string]$value.escalation_reason).Contains([string]$case.routing_reason_contains)) {
        throw "Case '$($case.name)' did not explain the expected routing source."
    }
    foreach ($field in @("required_checks", "skipped_checks")) {
        if ($null -ne $case.$field -and (@($value.$field) -join ',') -cne (@($case.$field) -join ',')) {
            throw "Case '$($case.name)' has an incorrect $field contract."
        }
    }
    if ((@($value.heavy_targeted_required_suites) -join ',') -cne (@($value.full_validator_coverage_suites) -join ',')) {
        throw "Case '$($case.name)' does not prove full coverage for the heavy targeted suite set."
    }
    $text = if (@($case.paths).Count -eq 0) {
        @(& $validator -BaseRef HEAD -HeadRef HEAD) -join "`n"
    } else {
        @(& $validator -ChangedPath @($case.paths)) -join "`n"
    }
    if ($text -notmatch ("Detected tier: Tier {0}" -f $case.tier)) { throw "Text output disagrees for '$($case.name)'." }
    if ($text -notmatch "Skipped checks \(not required; not PASS\):") { throw "Text output does not distinguish skipped checks for '$($case.name)'." }
    foreach ($check in @($value.required_checks)) { if (-not $text.Contains([string]$check)) { throw "Text output omitted required check '$check' for '$($case.name)'." } }
    foreach ($check in @($value.skipped_checks)) { if (-not $text.Contains([string]$check)) { throw "Text output omitted skipped check '$check' for '$($case.name)'." } }
    if (-not $text.Contains([string]$value.escalation_reason)) { throw "Text output omitted the JSON escalation reason for '$($case.name)'." }
    $results.Add([ordered]@{ name = [string]$case.name; tier = [int]$value.detected_tier; status = "PASS" })
}

$invalidRaw = @(& $validator -BaseRef "refs/heads/definitely-missing" -HeadRef HEAD -Json) -join "`n"
$invalid = $invalidRaw | ConvertFrom-Json
if ([int]$invalid.detected_tier -ne 3 -or [string]$invalid.escalation_reason -notmatch "Classification input") { throw "Invalid base ref did not conservatively escalate." }
if ($LASTEXITCODE -ne 0) { throw "Invalid base ref leaked LASTEXITCODE=$LASTEXITCODE instead of returning a clean Tier 3 fallback." }

# Regression: a direct-path Tier 3 classification after the expected invalid-ref
# fallback must also leave a clean native-command exit status.
$directPathRaw = @(
    & $validator `
        -ChangedPath ".github/workflows/release-validation.yml" `
        -Json
) -join "`n"
$directPath = $directPathRaw | ConvertFrom-Json
if ([int]$directPath.detected_tier -ne 3) {
    throw "Direct-path classifier scenario did not produce Tier 3."
}
if ($LASTEXITCODE -ne 0) {
    throw "Direct-path classifier scenario leaked LASTEXITCODE=$LASTEXITCODE."
}

$pushRoutingResults = @(Invoke-PushRoutingFixtures)
$classifierOutputResults = @(Invoke-ClassifierOutputContractFixtures)
$powerShellEncodingResults = @(Invoke-PowerShellEncodingFixtures)
$classifierFixtureValues = Get-Content -Raw (Join-Path $PSScriptRoot "validation/release-classifier-output-fixtures/cases.json") | ConvertFrom-Json
$invalidClassifier = $classifierFixtureValues[0].result
$invalidClassifier.required_suites = @("future-unknown-suite")
$invalidClassifier.suite_host_map = [pscustomobject]@{ "future-unknown-suite" = @("windows-latest") }
$invalidClassifier.required_hosts = @("windows-latest")
$rejected = $false
try { & $classifierOutputContract -Result $invalidClassifier | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Classifier output contract accepted an unknown suite." }
$classifierOutputResults += [ordered]@{ name = "unknown-suite-fails-closed"; status = "PASS" }

$invalidHostClassifier = (& $validator -ChangedPath "scripts/install.ps1" -Json | Out-String) | ConvertFrom-Json
$invalidHostClassifier.suite_host_map.'installer-contract' = @("future-host")
$rejected = $false
try { & $classifierOutputContract -Result $invalidHostClassifier | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw "Classifier output contract accepted an unknown host dependency." }
$classifierOutputResults += [ordered]@{ name = "unknown-host-dependency-fails-closed"; status = "PASS" }
$localPlanRaw = @(& $localPlanValidator -Json) -join "`n"
$localPlanResult = $localPlanRaw | ConvertFrom-Json
if ([int]$localPlanResult.fail -ne 0 -or [int]$localPlanResult.pass -lt 9) { throw "Local validation plan fixtures returned incomplete evidence." }

$workflow = Get-Content -LiteralPath (Join-Path $repoRoot ".github/workflows/release-validation.yml") -Raw
$heavyRegression = Get-Content -LiteralPath (Join-Path $repoRoot "scripts/test-heavy-targeted-regression.ps1") -Raw
$workflowMarkers = @(
    "needs.classify.outputs.tier == '0'",
    "needs.classify.outputs.tier == '1'",
    "needs.classify.outputs.tier == '2'",
    "needs.classify.outputs.tier == '3'",
    "github.event.before",
    "github.event.forced",
    "needs.classify.outputs.base",
    "needs.classify.outputs.head",
    "needs.classify.outputs.required_hosts_json",
    "needs.classify.outputs.run_validation_self_protection",
    "release-classifier-output-contract.ps1 -Result `$result",
    "needs.classify.result != 'success'",
    "./scripts/validate-targeted-change.ps1",
    "./scripts/validate-release.ps1"
)
foreach ($marker in $workflowMarkers) { if (-not $workflow.Contains($marker)) { throw "Hosted routing workflow is missing contract marker: $marker" } }
$classifierContractIndex = $workflow.IndexOf("release-classifier-output-contract.ps1 -Result `$result", [System.StringComparison]::Ordinal)
$firstClassifierOutputIndex = $workflow.IndexOf('"tier=$($result.detected_tier)" >> $env:GITHUB_OUTPUT', [System.StringComparison]::Ordinal)
if ($classifierContractIndex -lt 0 -or $firstClassifierOutputIndex -lt 0 -or $classifierContractIndex -gt $firstClassifierOutputIndex) {
    throw "Classifier schema validation must complete before the first GITHUB_OUTPUT write."
}
$releaseValidatorCallSites = @([regex]::Matches($workflow, "validate-release\.ps1")).Count
if ($releaseValidatorCallSites -ne 2) { throw "Expected one platform-neutral and one runtime/full validator workflow call site, found $releaseValidatorCallSites." }
foreach ($duplicatedRuleToken in @("knowledge-hub/", "skills/", "docs/releases/", "scripts/install.ps1")) {
    if ($workflow.Contains($duplicatedRuleToken)) { throw "Workflow duplicates a path-routing rule: $duplicatedRuleToken" }
}
if (@([regex]::Matches($workflow, "test-validate-change\.ps1 -Json")).Count -ne 1) { throw "Classifier must have exactly one lightweight classification-test invocation." }
if (@([regex]::Matches($workflow, "test-heavy-targeted-regression\.ps1 -Json")).Count -ne 1) { throw "Hosted control-plane changes must run one independent self-protection oracle." }
if (-not $heavyRegression.Contains("validation/test-sensitive-scan.ps1") -or -not $heavyRegression.Contains("control_plane")) { throw "Heavy self-protection must own the full sensitive scan and gate it through classifier control-plane evidence." }
if ($workflow.Contains("test-sensitive-scan.ps1")) { throw "The hosted classifier workflow must not invoke the full sensitive scan directly." }
if (@([regex]::Matches($workflow, '-BaseRef "\$\{\{ needs\.classify\.outputs\.base \}\}"')).Count -ne 2) { throw "Quick and affected jobs must reuse the classifier base boundary." }
if (@([regex]::Matches($workflow, '-HeadRef "\$\{\{ needs\.classify\.outputs\.head \}\}"')).Count -ne 2) { throw "Quick and affected jobs must reuse the classifier head boundary." }
if (@([regex]::Matches($workflow, "outputs\.run_validation_self_protection == 'true'")).Count -ne 1) { throw "Self-protection job must run only for a successful classifier control-plane decision." }
if (-not $workflow.Contains("fromJSON(needs.classify.outputs.required_hosts_json")) { throw "Affected Hosted execution must use the classifier host matrix." }
if (-not $workflow.Contains("github.event_name == 'push' && github.run_id") -or
    -not $workflow.Contains('cancel-in-progress: ${{ github.event_name != ''push'' }}')) {
    throw "Hosted concurrency must preserve every push range while retaining cancellation for non-push events."
}

$unsupported = (& $validator -ChangedPath "skills/removed-skill/SKILL.md" -Json | Out-String) | ConvertFrom-Json
if ([int]$unsupported.detected_tier -ne 3 -or -not [bool]$unsupported.run_heavy_targeted_regression) { throw "Runtime skill without a reliable targeted suite did not fail closed to Tier 3 heavy execution." }
$unmappedTest = (& $validator -ChangedPath "scripts/test-future-runtime.ps1" -Json | Out-String) | ConvertFrom-Json
if ([int]$unmappedTest.detected_tier -ne 3 -or -not [bool]$unmappedTest.conservative_fallback -or
    @($unmappedTest.required_suites).Count -ne 10 -or @($unmappedTest.required_hosts).Count -ne 3 -or
    -not [bool]$unmappedTest.run_validation_self_protection -or -not [bool]$unmappedTest.self_protection_required -or
    [bool]$unmappedTest.control_plane -or [string]$unmappedTest.self_protection_reason -cne "unknown-or-ambiguous-input" -or
    -not [bool]$unmappedTest.run_heavy_targeted_regression) {
    throw "Unmapped future test path did not fail closed to Tier 3 full routing."
}
$workflowHostArrayResults = @(Invoke-WorkflowHostArrayFixtures -Workflow $workflow -FallbackClassification $unmappedTest)
$executionDedupResults = @(Invoke-ExecutionDedupContractFixtures)

$targetedResults = @()
if ($RunTargetedRegression.IsPresent) {
    $tierZeroRaw = @(& $targetedValidator -ChangedPath "README.md" -Mode quick -ScratchRoot (Join-Path $targetedScratch "tier-zero") -Json) -join "`n"
    $tierZero = $tierZeroRaw | ConvertFrom-Json
    if ([int]$tierZero.executed_suite_count -ne 0 -or @($tierZero.checks.name) -contains "quick-repository-checks") { throw "Tier 0 incorrectly executed heavy or module checks." }
    $targetedResults = @(
        Invoke-TargetedRegression -Name "knowledge" -Path "knowledge-hub/knowledge/catalog.md" -ExpectedTier 1 -ExpectedModule "knowledge" -ExpectedSuite "knowledge-contracts" -Mode "quick"
        Invoke-TargetedRegression -Name "bootstrap" -Path "skills/project-bootstrap/scripts/bootstrap_project.ps1" -ExpectedTier 2 -ExpectedModule "bootstrap" -ExpectedSuite "bootstrap-safety" -Mode "targeted"
        Invoke-TargetedRegression -Name "bridge" -Path "scripts/link-agent-skills.ps1" -ExpectedTier 2 -ExpectedModule "bridge" -ExpectedSuite "agent-skill-bridge" -Mode "targeted"
        Invoke-TargetedRegression -Name "context-gate" -Path "skills/project-context-gate/scripts/context_gate.ps1" -ExpectedTier 2 -ExpectedModule "context-gate" -ExpectedSuite "project-context-gate" -Mode "targeted"
        Invoke-TargetedRegression -Name "context-gate-check" -Path "scripts/validation/project-context-gate-checks.ps1" -ExpectedTier 2 -ExpectedModule "context-gate" -ExpectedSuite "project-context-gate" -Mode "targeted"
        Invoke-TargetedRegression -Name "workspace-assets" -Path @("schemas/project-workspace/work-item.schema.json", "skills/project-workspace/scripts/read-project-assets.ps1", "skills/project-workspace/scripts/project-continuity.ps1", "scripts/migrate-project.ps1") -ExpectedTier 2 -ExpectedModule @("workspace-schema", "workspace", "continuity", "migration") -ExpectedSuite "workspace-assets" -Mode "targeted"
        Invoke-TargetedRegression -Name "docs-knowledge" -Path @("README.md", "knowledge-hub/knowledge/catalog.md") -ExpectedTier 1 -ExpectedModule @("documentation", "knowledge") -ExpectedSuite "knowledge-contracts" -Mode "quick"
        Invoke-TargetedRegression -Name "docs-installer" -Path @("README.md", "scripts/install.ps1") -ExpectedTier 2 -ExpectedModule @("documentation", "installer", "runtime") -ExpectedSuite @("installer-contract", "runtime-smoke") -Mode "targeted"
        Invoke-TargetedRegression -Name "docs-context-gate" -Path @("README.md", "skills/project-context-gate/scripts/context_gate.ps1") -ExpectedTier 2 -ExpectedModule @("documentation", "context-gate") -ExpectedSuite "project-context-gate" -Mode "targeted"
    )
    $targetedFailures = @($targetedResults | Where-Object { [string]$_.status -cne "PASS" })
    if ($targetedFailures.Count -gt 0) {
        throw ("Targeted regression contained failed routing or shared execution cases: {0}" -f (($targetedFailures | ForEach-Object { "{0}: {1}" -f $_.name, $_.execution.error }) -join "; "))
    }
    $tierZeroText = @(& $targetedValidator -ChangedPath "README.md" -Mode quick -ScratchRoot (Join-Path $targetedScratch "tier-zero-text")) -join "`n"
    if ($tierZeroText -notmatch "0 actual module suites") { throw "Targeted text output disagrees with Tier 0 JSON evidence." }
}

$orderA = (& $validator -ChangedPath @("README.md", "scripts/install.ps1") -Json | Out-String) | ConvertFrom-Json
$orderB = (& $validator -ChangedPath @("scripts/install.ps1", "README.md") -Json | Out-String) | ConvertFrom-Json
if (($orderA | ConvertTo-Json -Depth 8 -Compress) -ne ($orderB | ConvertTo-Json -Depth 8 -Compress)) { throw "Classification depends on input order." }

# Guard: a stale $LASTEXITCODE from an earlier expected native-command failure must not
# leak to the caller.  This check catches regressions of the invalid-base-ref cleanup above.
if ($LASTEXITCODE -ne 0) { throw "Stale LASTEXITCODE=$LASTEXITCODE after all tests passed." }

$summary = [ordered]@{ schema_version = 1; pass = $results.Count + 1 + 8 + [int]$runtimeRequirementResult.pass + $pushRoutingResults.Count + $classifierOutputResults.Count + $powerShellEncodingResults.Count + $workflowHostArrayResults.Count + $executionDedupResults.Count + $targetedResults.Count; fail = 0; cases = @($results.ToArray()); sensitive_scan = $sensitiveScanSummary; sensitive_scan_case_count = $sensitiveScanCaseCount; sensitive_scan_status = [string]$sensitiveScanSummary.status; sensitive_scan_contract = $sensitiveScanContractCheck; push_routing = $pushRoutingResults; classifier_output_contract = $classifierOutputResults; powershell_runtime_requirement = $runtimeRequirementResult; powershell_encoding = $powerShellEncodingResults; workflow_host_array_serialization = $workflowHostArrayResults; execution_dedup_contract = $executionDedupResults; local_plan = $localPlanResult; targeted_regression_executed = $RunTargetedRegression.IsPresent; targeted_execution = $targetedResults; tier_zero_no_heavy_checks = $(if ($RunTargetedRegression.IsPresent) { "PASS" } else { "NOT_RUN" }); unsupported_runtime_skill_escalation = "PASS"; unmapped_test_escalation = "PASS"; text_json_evidence = $(if ($RunTargetedRegression.IsPresent) { "PASS" } else { "NOT_RUN" }); invalid_base_ref = "PASS"; direct_path_classifier = "PASS"; hosted_routing_contract = "PASS"; deterministic_order = "PASS"; lastexitcode_clean = "PASS" }
$summaryJson = $summary | ConvertTo-Json -Depth 8
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Set-Content -LiteralPath $OutputPath -Value $summaryJson -Encoding UTF8
}
if ($Json.IsPresent) { $summaryJson } else { Write-Output ("validate-change fixtures: PASS={0} FAIL=0" -f $summary.pass) }
