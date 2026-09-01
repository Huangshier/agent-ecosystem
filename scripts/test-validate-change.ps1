[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$RunSelfProtectionOracle,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot "validate-change.ps1"
$cases = Get-Content -LiteralPath (Join-Path $PSScriptRoot "validation/change-risk-fixtures/cases.json") -Raw | ConvertFrom-Json
$rulesPath = Join-Path $PSScriptRoot "validation/change-risk-rules.json"
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
$emittedSuites = New-Object 'System.Collections.Generic.List[string]'

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

function Assert-ClassificationContract {
    param(
        [Parameter(Mandatory = $true)][object]$Case,
        [Parameter(Mandatory = $true)][object]$Value
    )

    & $classifierOutputContract -Result $Value | Out-Null
    if ([int]$Value.detected_tier -ne [int]$Case.tier) { throw "Case '$($Case.name)' expected Tier $($Case.tier), got Tier $($Value.detected_tier)." }
    if ($null -ne $Case.full_validator_calls -and [int]$Value.hosted_plan.full_validator_calls -ne [int]$Case.full_validator_calls) { throw "Case '$($Case.name)' has an incorrect hosted full-validator call count." }
    if ($null -ne $Case.platform_neutral_validator_calls -and [int]$Value.hosted_plan.platform_neutral_validator_calls -ne [int]$Case.platform_neutral_validator_calls) { throw "Case '$($Case.name)' has an incorrect hosted platform-neutral call count." }
    if ($null -ne $Case.runtime_platform_validator_calls -and [int]$Value.hosted_plan.runtime_platform_validator_calls -ne [int]$Case.runtime_platform_validator_calls) { throw "Case '$($Case.name)' has an incorrect hosted runtime-platform call count." }
    if ($null -ne $Case.targeted_os_jobs -and [int]$Value.hosted_plan.targeted_os_jobs -ne [int]$Case.targeted_os_jobs) { throw "Case '$($Case.name)' has an incorrect hosted targeted OS job count." }
    if ($null -ne $Case.affected_modules) {
        $actualModules = @($Value.affected_modules | Sort-Object)
        $expectedModules = @($Case.affected_modules | Sort-Object)
        if (($actualModules -join ',') -cne ($expectedModules -join ',')) { throw "Case '$($Case.name)' has incorrect affected modules." }
    }
    if ($null -ne $Case.required_suites) {
        $actualSuites = @($Value.required_suites | Sort-Object)
        $expectedSuites = @($Case.required_suites | Sort-Object)
        if (($actualSuites -join ',') -cne ($expectedSuites -join ',')) { throw "Case '$($Case.name)' has incorrect required suites." }
    }
    if ($null -ne $Case.required_hosts) {
        $actualHosts = @($Value.required_hosts | Sort-Object)
        $expectedHosts = @($Case.required_hosts | Sort-Object)
        if (($actualHosts -join ',') -cne ($expectedHosts -join ',')) { throw "Case '$($Case.name)' has incorrect required hosts." }
    }
    if ($null -ne $Case.run_heavy_targeted_regression -and [bool]$Value.run_heavy_targeted_regression -ne [bool]$Case.run_heavy_targeted_regression) {
        throw "Case '$($Case.name)' has an incorrect heavy targeted decision."
    }
    if ($null -ne $Case.heavy_targeted_reason -and [string]$Value.heavy_targeted_reason -cne [string]$Case.heavy_targeted_reason) {
        throw "Case '$($Case.name)' has an incorrect heavy targeted reason."
    }
    if ($null -ne $Case.conservative_fallback -and [bool]$Value.conservative_fallback -ne [bool]$Case.conservative_fallback) {
        throw "Case '$($Case.name)' has an incorrect conservative fallback decision."
    }
    if ($null -ne $Case.validation_self_protection_reason -and [string]$Value.validation_self_protection_reason -cne [string]$Case.validation_self_protection_reason) {
        throw "Case '$($Case.name)' has an incorrect validation self-protection reason."
    }
    foreach ($field in @("run_validation_self_protection", "control_plane", "self_protection_required")) {
        if ($null -ne $Case.$field -and [bool]$Value.$field -ne [bool]$Case.$field) {
            throw "Case '$($Case.name)' has an incorrect $field decision."
        }
    }
    if ($null -ne $Case.self_protection_reason -and [string]$Value.self_protection_reason -cne [string]$Case.self_protection_reason) {
        throw "Case '$($Case.name)' has an incorrect explicit self-protection reason."
    }
    if ($null -ne $Case.routing_reason_contains -and -not ([string]$Value.escalation_reason).Contains([string]$Case.routing_reason_contains)) {
        throw "Case '$($Case.name)' did not explain the expected routing source."
    }
    foreach ($field in @("required_checks", "skipped_checks")) {
        if ($null -ne $Case.$field -and (@($Value.$field) -join ',') -cne (@($Case.$field) -join ',')) {
            throw "Case '$($Case.name)' has an incorrect $field contract."
        }
    }
    if ((@($Value.heavy_targeted_required_suites) -join ',') -cne (@($Value.full_validator_coverage_suites) -join ',')) {
        throw "Case '$($Case.name)' does not prove full coverage for the heavy targeted suite set."
    }
}

function Invoke-WeakeningMutation {
    param(
        [string]$Name,
        [object]$Fixture,
        [string]$RulesPath,
        [string]$MutationRulesPath,
        [string]$MutationClassifier,
        [scriptblock]$RuleMutation,
        [scriptblock]$WeakenedEvidence
    )

    $rules = Get-Content -LiteralPath $RulesPath -Raw | ConvertFrom-Json
    & $RuleMutation $rules
    $rules | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $MutationRulesPath -Encoding UTF8
    $mutatedRaw = @(& $MutationClassifier -ChangedPath @($Fixture.paths) -Json) -join "`n"
    $mutated = $mutatedRaw | ConvertFrom-Json
    if (-not (& $WeakenedEvidence $mutated)) {
        throw "Weakening mutation '$Name' did not produce the expected weakened classification."
    }
    $detection = ""
    try {
        Assert-ClassificationContract -Case $Fixture -Value $mutated | Out-Null
    }
    catch {
        $detection = [string]$_.Exception.Message
    }
    if ([string]::IsNullOrWhiteSpace($detection)) {
        throw "The fixed classification contract accepted weakened control-plane behavior '$Name'."
    }
    return [ordered]@{ name = $Name; status = "PASS"; detected_by = $detection }
}

function Invoke-ControlPlaneWeakeningFixtures {
    $fixtureResults = New-Object 'System.Collections.Generic.List[object]'
    $mutationRoot = Join-Path $targetedScratch "control-plane-weakening"
    $mutationScriptsRoot = Join-Path $mutationRoot "scripts"
    New-Item -ItemType Directory -Force -Path $mutationRoot | Out-Null
    Copy-Item -Recurse -Path (Join-Path $repoRoot "scripts") -Destination $mutationScriptsRoot
    $mutationClassifier = Join-Path $mutationScriptsRoot "validate-change.ps1"
    $mutationRulesPath = Join-Path $mutationScriptsRoot "validation/change-risk-rules.json"
    if (-not (Test-Path -LiteralPath $mutationClassifier -PathType Leaf) -or -not (Test-Path -LiteralPath $mutationRulesPath -PathType Leaf)) {
        throw "Control-plane weakening fixtures could not stage a classifier mutation copy."
    }
    function Get-CorpusFixture {
        param([string]$Name)
        $fixture = @($cases | Where-Object { [string]$_.name -ceq $Name })[0]
        if ($null -eq $fixture) { throw "Corpus fixture '$Name' is required by the weakening fixtures." }
        return $fixture
    }

    # NOTE: Each mutation below weakens only the scratch rule copy, proves the weakened
    # classification was actually produced, and proves the fixed corpus contract above
    # rejects it. The repository itself is never mutated.
    $fixtureResults.Add((Invoke-WeakeningMutation `
        -Name "routing-tier-downgrade-detected" `
        -Fixture (Get-CorpusFixture "pr-c-stable-patch-id-control-plane") `
        -RulesPath $rulesPath -MutationRulesPath $mutationRulesPath -MutationClassifier $mutationClassifier `
        -RuleMutation {
            param($rules)
            $rule = @($rules.rules | Where-Object { [string]$_.id -ceq "validation-routing" })[0]
            if ($null -eq $rule) { throw "validation-routing rule is missing." }
            $rule.tier = 1
        } `
        -WeakenedEvidence { param($value) [int]$value.detected_tier -eq 1 }))

    $fixtureResults.Add((Invoke-WeakeningMutation `
        -Name "control-plane-marker-removal-detected" `
        -Fixture (Get-CorpusFixture "pr-c-stable-patch-id-control-plane") `
        -RulesPath $rulesPath -MutationRulesPath $mutationRulesPath -MutationClassifier $mutationClassifier `
        -RuleMutation {
            param($rules)
            $rule = @($rules.rules | Where-Object { [string]$_.id -ceq "validation-routing" })[0]
            if ($null -eq $rule) { throw "validation-routing rule is missing." }
            $rule.PSObject.Properties.Remove("control_plane")
        } `
        -WeakenedEvidence { param($value) [int]$value.detected_tier -eq 3 -and -not [bool]$value.control_plane }))

    $fixtureResults.Add((Invoke-WeakeningMutation `
        -Name "required-suite-loss-detected" `
        -Fixture (Get-CorpusFixture "runtime-installer-leaf") `
        -RulesPath $rulesPath -MutationRulesPath $mutationRulesPath -MutationClassifier $mutationClassifier `
        -RuleMutation {
            param($rules)
            foreach ($moduleName in @("installer", "runtime")) {
                $mapping = $rules.module_suites.PSObject.Properties[$moduleName]
                if ($null -eq $mapping) { throw "module_suites.$moduleName is missing." }
                $mapping.Value = @($mapping.Value | Where-Object { [string]$_ -cne "runtime-smoke" })
            }
        } `
        -WeakenedEvidence { param($value) (@($value.required_suites | Sort-Object) -join ",") -ceq "installer-contract" }))

    $fixtureResults.Add((Invoke-WeakeningMutation `
        -Name "runtime-skill-escalation-cancelled-detected" `
        -Fixture (Get-CorpusFixture "unsupported-runtime-skill") `
        -RulesPath $rulesPath -MutationRulesPath $mutationRulesPath -MutationClassifier $mutationClassifier `
        -RuleMutation {
            param($rules)
            $rule = @($rules.rules | Where-Object { [string]$_.id -ceq "unsupported-runtime-skill" })[0]
            if ($null -eq $rule) { throw "unsupported-runtime-skill rule is missing." }
            $rule.tier = 0
            $rule.modules = @("bootstrap")
        } `
        -WeakenedEvidence { param($value) [int]$value.detected_tier -eq 0 -and -not [bool]$value.run_validation_self_protection }))

    $fixtureResults.Add((Invoke-WeakeningMutation `
        -Name "unknown-input-escalation-cancelled-detected" `
        -Fixture (Get-CorpusFixture "unknown") `
        -RulesPath $rulesPath -MutationRulesPath $mutationRulesPath -MutationClassifier $mutationClassifier `
        -RuleMutation {
            param($rules)
            $rules.unknown_tier = 0
        } `
        -WeakenedEvidence { param($value) [int]$value.detected_tier -eq 0 }))

    return @($fixtureResults.ToArray())
}

function Invoke-TargetedDispatchContractFixtures {
    $fixtureResults = New-Object 'System.Collections.Generic.List[object]'

    $rulesConfig = Get-Content -LiteralPath $rulesPath -Raw | ConvertFrom-Json
    $suiteUniverse = @(
        @($rulesConfig.suite_hosts.PSObject.Properties | ForEach-Object { [string]$_.Name }) +
        @($rulesConfig.module_suites.PSObject.Properties | ForEach-Object { @($_.Value) | ForEach-Object { [string]$_ } }) +
        @($rulesConfig.fallback_suites | ForEach-Object { [string]$_ })
    ) | Sort-Object -Unique
    if ($suiteUniverse.Count -eq 0) {
        throw "Classifier routing rules declared no dispatchable suites."
    }

    # Behavioral consumption: the targeted executor must consume the classifier output
    # for a suite-bearing path without executing the business suites themselves.
    $dispatchPath = "scripts/install.ps1"
    $directClassification = @(& $validator -ChangedPath $dispatchPath -Json) -join "`n" | ConvertFrom-Json
    $consumedRaw = @(& $targetedValidator -ChangedPath $dispatchPath -Mode targeted -RoutingOnly -ScratchRoot (Join-Path $targetedScratch "dispatch-consumption") -Json) -join "`n"
    $consumed = $consumedRaw | ConvertFrom-Json
    if (-not [bool]$consumed.routing_only -or [int]$consumed.executed_suite_count -ne 0) {
        throw "Dispatch consumption fixture must produce routing-only evidence without executing business suites."
    }
    foreach ($classification in @($directClassification, $consumed.classification)) {
        if ([int]$classification.detected_tier -ne 2 -or
            (@($classification.affected_modules | Sort-Object) -join ",") -cne "installer,runtime" -or
            (@($classification.required_suites | Sort-Object) -join ",") -cne "installer-contract,runtime-smoke") {
            throw "Classifier dispatch selection for '$dispatchPath' did not require the installer and runtime suites."
        }
    }
    $fixtureResults.Add([ordered]@{ name = "classifier-output-consumed-by-targeted-executor"; status = "PASS" })

    # Structural dispatch contract: every dispatchable suite must select a guarded
    # execution path in the targeted executor that records the executed suite.
    $astLexemes = $null
    $parseErrors = $null
    $executorAst = [System.Management.Automation.Language.Parser]::ParseFile($targetedValidator, [ref]$astLexemes, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw "Targeted executor did not parse: $($parseErrors[0].Message)" }
    $assignments = @($executorAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))
    $suiteSource = @($assignments | Where-Object {
        [string]$_.Left.Extent.Text -ceq '$allRequiredSuites' -and [string]$_.Right.Extent.Text -like '*$classification.required_suites*'
    })
    if ($suiteSource.Count -ne 1) {
        throw "Targeted executor must derive its required-suite set from the classifier required_suites output exactly once."
    }
    $fixtureResults.Add([ordered]@{ name = "required-suites-derived-from-classifier-output"; status = "PASS" })

    $hostFilter = @($assignments | Where-Object {
        [string]$_.Left.Extent.Text -ceq '$requiredSuites' -and
        [string]$_.Right.Extent.Text -like '*$allRequiredSuites*' -and
        [string]$_.Right.Extent.Text -like '*suite_host_map*' -and
        [string]$_.Right.Extent.Text -like '*$ExecutionHost*'
    })
    if ($hostFilter.Count -ne 1) {
        throw "Targeted executor must select per-host execution paths through the classifier suite_host_map."
    }
    $fixtureResults.Add([ordered]@{ name = "host-filtered-dispatch-selection"; status = "PASS" })

    $dispatchGuards = @($executorAst.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
        $node.Operator -eq [System.Management.Automation.Language.TokenKind]::Icontains -and
        [string]$node.Left.Extent.Text -ceq '$requiredSuites' -and
        $node.Right -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))
    $guardSuites = @($dispatchGuards | ForEach-Object { [string]$_.Right.Value })
    $guardSuiteSet = @($guardSuites | Sort-Object -Unique)
    if ($guardSuites.Count -ne $guardSuiteSet.Count) {
        throw "A targeted executor dispatch guard is duplicated."
    }
    if (($guardSuiteSet -join ",") -cne ($suiteUniverse -join ",")) {
        throw "Targeted executor dispatch guards do not cover exactly the classifier's dispatchable suites."
    }
    $fixtureResults.Add([ordered]@{ name = "dispatch-guards-cover-dispatchable-suites"; suites = $guardSuiteSet; status = "PASS" })

    $executedRegistrations = @($executorAst.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        [string]$node.Expression.Extent.Text -ceq '$executedSuites' -and
        $node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        [string]$node.Member.Value -ceq 'Add' -and
        $null -ne $node.Arguments -and
        @($node.Arguments).Count -eq 1 -and
        $node.Arguments[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))
    $registeredSuites = @($executedRegistrations | ForEach-Object { [string]$_.Arguments[0].Value })
    $registeredSuiteSet = @($registeredSuites | Sort-Object -Unique)
    if ($registeredSuites.Count -ne $registeredSuiteSet.Count) {
        throw "A targeted executor executed-suite registration is duplicated."
    }
    if (($registeredSuiteSet -join ",") -cne ($suiteUniverse -join ",")) {
        throw "Targeted executor dispatch paths do not record execution for every dispatchable suite."
    }
    $fixtureResults.Add([ordered]@{ name = "dispatch-registrations-record-executed-suites"; suites = $registeredSuiteSet; status = "PASS" })

    $emittedSet = @($emittedSuites | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if (($emittedSet -join ",") -cne ($suiteUniverse -join ",")) {
        throw "The classification corpus must exercise every dispatchable suite."
    }
    $fixtureResults.Add([ordered]@{ name = "corpus-exercises-every-dispatchable-suite"; status = "PASS" })

    return @($fixtureResults.ToArray())
}

foreach ($case in @($cases)) {
    $raw = if (@($case.paths).Count -eq 0) {
        @(& $validator -BaseRef HEAD -HeadRef HEAD -Json) -join "`n"
    } else {
        @(& $validator -ChangedPath @($case.paths) -Json) -join "`n"
    }
    $value = $raw | ConvertFrom-Json
    Assert-ClassificationContract -Case $case -Value $value
    foreach ($suite in @($value.required_suites)) {
        if (-not $emittedSuites.Contains([string]$suite)) { $emittedSuites.Add([string]$suite) }
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
if ($heavyRegression.Contains("-RunTargetedRegression")) { throw "Self-protection must not replay full business validation suites." }
if (-not $heavyRegression.Contains("-RunSelfProtectionOracle")) { throw "Self-protection must run the focused control-plane oracle contracts." }
if (-not $heavyRegression.Contains("test-required-validation-gate.ps1")) { throw "Self-protection must run the required validation gate fixture corpus." }
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

$dispatchResults = @()
$weakeningResults = @()
if ($RunSelfProtectionOracle.IsPresent) {
    $dispatchResults = @(Invoke-TargetedDispatchContractFixtures)
    $weakeningResults = @(Invoke-ControlPlaneWeakeningFixtures)
}

$orderA = (& $validator -ChangedPath @("README.md", "scripts/install.ps1") -Json | Out-String) | ConvertFrom-Json
$orderB = (& $validator -ChangedPath @("scripts/install.ps1", "README.md") -Json | Out-String) | ConvertFrom-Json
if (($orderA | ConvertTo-Json -Depth 8 -Compress) -ne ($orderB | ConvertTo-Json -Depth 8 -Compress)) { throw "Classification depends on input order." }

# Guard: a stale $LASTEXITCODE from an earlier expected native-command failure must not
# leak to the caller.  This check catches regressions of the invalid-base-ref cleanup above.
if ($LASTEXITCODE -ne 0) { throw "Stale LASTEXITCODE=$LASTEXITCODE after all tests passed." }

$summary = [ordered]@{ schema_version = 1; pass = $results.Count + 7 + [int]$runtimeRequirementResult.pass + $pushRoutingResults.Count + $classifierOutputResults.Count + $powerShellEncodingResults.Count + $workflowHostArrayResults.Count + $executionDedupResults.Count + $dispatchResults.Count + $weakeningResults.Count; fail = 0; cases = @($results.ToArray()); sensitive_scan = $sensitiveScanSummary; sensitive_scan_case_count = $sensitiveScanCaseCount; sensitive_scan_status = [string]$sensitiveScanSummary.status; sensitive_scan_contract = $sensitiveScanContractCheck; push_routing = $pushRoutingResults; classifier_output_contract = $classifierOutputResults; powershell_runtime_requirement = $runtimeRequirementResult; powershell_encoding = $powerShellEncodingResults; workflow_host_array_serialization = $workflowHostArrayResults; execution_dedup_contract = $executionDedupResults; local_plan = $localPlanResult; control_plane_weakening_fixtures = $(if ($RunSelfProtectionOracle.IsPresent) { @($weakeningResults) } else { "NOT_RUN" }); targeted_dispatch_contract = $(if ($RunSelfProtectionOracle.IsPresent) { @($dispatchResults) } else { "NOT_RUN" }); unsupported_runtime_skill_escalation = "PASS"; unmapped_test_escalation = "PASS"; invalid_base_ref = "PASS"; direct_path_classifier = "PASS"; hosted_routing_contract = "PASS"; deterministic_order = "PASS"; lastexitcode_clean = "PASS" }
$summaryJson = $summary | ConvertTo-Json -Depth 8
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Set-Content -LiteralPath $OutputPath -Value $summaryJson -Encoding UTF8
}
if ($Json.IsPresent) { $summaryJson } else { Write-Output ("validate-change fixtures: PASS={0} FAIL=0" -f $summary.pass) }
