[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ScratchRoot,
    [Parameter(Mandatory = $true)][ValidateSet("success", "failure")][string]$Outcome,
    [Parameter(Mandatory = $true)][string]$CommitSha,
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$RunAttempt,
    [Parameter(Mandatory = $true)][string]$JobName,
    [Parameter(Mandatory = $true)][string]$HostIdentity,
    [string]$Repository = "Huangshier/agent-ecosystem",
    [ValidateSet("pull_request", "push", "workflow_dispatch", "schedule", "fixture")][string]$EventName = "fixture",
    [string]$WorkflowIdentity = ".github/workflows/release-validation.yml",
    [string]$RoutingContractIdentity = "scripts/validation/change-risk-rules.json",
    [string]$GateContractIdentity = "scripts/validation/required-validation-gate.ps1",
    [string]$CandidateContractPath = "",
    [ValidateSet("executed", "skipped", "not-applicable")][string]$HeavyTargetedStatus = "not-applicable",
    [string]$HeavyTargetedReason = "not-applicable",
    [Parameter(Mandatory = $true)][string[]]$SuccessAllowlist,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
if (-not [System.IO.Directory]::Exists($scratchRootFull)) {
    throw "ScratchRoot does not exist."
}

if ($CommitSha -notmatch '^[0-9a-fA-F]{40}$') {
    throw "CommitSha must be a 40-character Git commit ID."
}
if ([string]::IsNullOrWhiteSpace($RunId) -or [string]::IsNullOrWhiteSpace($RunAttempt) -or
    [string]::IsNullOrWhiteSpace($JobName) -or [string]::IsNullOrWhiteSpace($HostIdentity)) {
    throw "Run, job, and host identity fields must be non-empty."
}
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
    [string]::IsNullOrWhiteSpace($WorkflowIdentity) -or
    [string]::IsNullOrWhiteSpace($RoutingContractIdentity) -or
    [string]::IsNullOrWhiteSpace($GateContractIdentity)) {
    throw "Repository and contract identity fields must be valid and non-empty."
}
$candidateContract = $null
if ($CandidateContractPath) {
    $candidateContractFull = [System.IO.Path]::GetFullPath($CandidateContractPath)
    if (-not [System.IO.File]::Exists($candidateContractFull)) { throw "CandidateContractPath does not exist." }
    $candidateContract = [System.IO.File]::ReadAllText($candidateContractFull) | ConvertFrom-Json
    if ([int]$candidateContract.schema_version -ne 1 -or
        [string]$candidateContract.repository -cne $Repository -or
        [string]$candidateContract.candidate.sha -cne $CommitSha.ToLowerInvariant()) {
        throw "Candidate contract does not match the repository or validated commit."
    }
}
elseif ($EventName -ceq "pull_request") {
    throw "Pull request evidence requires an exact candidate contract."
}

$normalizedAllowlist = New-Object 'System.Collections.Generic.List[string]'
foreach ($item in @($SuccessAllowlist)) {
    $fileName = [System.IO.Path]::GetFileName([string]$item)
    if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -cne [string]$item -or $fileName -in @(".", "..")) {
        throw "Success allowlist entries must be explicit top-level file names."
    }
    if (-not $normalizedAllowlist.Contains($fileName)) {
        $normalizedAllowlist.Add($fileName)
    }
}
if (-not $normalizedAllowlist.Contains("evidence-manifest.json")) {
    $normalizedAllowlist.Add("evidence-manifest.json")
}

if ($Outcome -eq "success") {
    foreach ($fileName in @($normalizedAllowlist)) {
        if ($fileName -eq "evidence-manifest.json") { continue }
        if (-not [System.IO.File]::Exists((Join-Path $scratchRootFull $fileName))) {
            throw "Success allowlist file '$fileName' does not exist."
        }
    }
}

function Read-OptionalJson([string]$FileName) {
    $path = Join-Path $scratchRootFull $FileName
    if (-not [System.IO.File]::Exists($path)) { return $null }
    return [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
}

$releaseResult = Read-OptionalJson -FileName "validation-result.json"
$targetedResult = Read-OptionalJson -FileName "targeted-validation-result.json"
$routingResult = Read-OptionalJson -FileName "change-routing-tests.json"

if ([string]::IsNullOrWhiteSpace($HeavyTargetedReason)) {
    throw "HeavyTargetedReason must be non-empty."
}
$actualUniqueCoverage = @()
if ($HeavyTargetedStatus -eq "executed") {
    if ($null -eq $routingResult -or -not [bool]$routingResult.targeted_regression_executed -or @($routingResult.targeted_execution).Count -eq 0) {
        throw "Executed heavy targeted regression requires complete routing evidence."
    }
    if (@($routingResult.targeted_execution | Where-Object {
        [string]$_.status -ne "PASS" -or [string]::IsNullOrWhiteSpace([string]$_.unique_coverage_category)
    }).Count -gt 0) {
        throw "Executed heavy targeted routing evidence is incomplete or failed."
    }
    if (-not $normalizedAllowlist.Contains("change-routing-tests.json")) {
        throw "Executed heavy targeted regression requires change-routing-tests.json in the success allowlist."
    }
    $actualUniqueCoverage = @($routingResult.targeted_execution | ForEach-Object {
        [string]$_.unique_coverage_category
    } | Sort-Object -Unique)
}
elseif ($null -ne $routingResult) {
    throw "Skipped or not-applicable heavy targeted regression must not include routing execution evidence."
}
elseif ($normalizedAllowlist.Contains("change-routing-tests.json")) {
    throw "Skipped or not-applicable heavy targeted regression must not require change-routing-tests.json."
}

$releaseChecks = @()
$validationShard = "not-applicable"
if ($null -ne $releaseResult) {
    $validationShard = [string]$releaseResult.validation_shard
    $shardContractPath = Join-Path $PSScriptRoot "release-shard-contract.json"
    $shardContract = [System.IO.File]::ReadAllText($shardContractPath) | ConvertFrom-Json
    $recognizedValidationShards = @(
        @($shardContract.profiles.PSObject.Properties | ForEach-Object { [string]$_.Name }) +
        @($shardContract.shards.PSObject.Properties | ForEach-Object { [string]$_.Name })
    )
    if ($validationShard -notin $recognizedValidationShards) {
        throw "validation-result.json is missing a recognized validation_shard."
    }
    if ($Outcome -eq "success" -and [string]$releaseResult.shard_coverage.status -cne "PASS") {
        throw "Successful release evidence requires a passing shard coverage contract."
    }
    $releaseChecks = @($releaseResult.checks | ForEach-Object {
        [ordered]@{
            name = [string]$_.name
            status = [string]$_.status
            duration_ms = $(if ($null -eq $_.duration_ms) { $null } else { [long]$_.duration_ms })
        }
    })
}

$targetedTelemetry = @()
if ($null -ne $targetedResult) {
    $targetedTelemetry = @($targetedResult.telemetry)
}

$routingRegressions = @()
if ($null -ne $routingResult) {
    $routingRegressions = @($routingResult.targeted_execution)
}

$coverageCategories = New-Object 'System.Collections.Generic.List[string]'
foreach ($record in @($targetedTelemetry) + @($routingRegressions)) {
    $category = [string]$record.unique_coverage_category
    if (-not [string]::IsNullOrWhiteSpace($category) -and -not $coverageCategories.Contains($category)) {
        $coverageCategories.Add($category)
    }
}
if ($releaseChecks.Count -gt 0) {
    $categoryShard = switch ($validationShard) {
        "PlatformNeutral" { "platform-neutral" }
        "RuntimePlatform" { "runtime-platform" }
        default { "full" }
    }
    $coverageCategories.Add(("release-validator:{0}" -f $categoryShard))
}

$availableTopLevelFiles = @(
    @(Get-ChildItem -LiteralPath $scratchRootFull -File | ForEach-Object { $_.Name }) + @("evidence-manifest.json") |
        Sort-Object -Unique
)
$artifactDigests = @(
    $normalizedAllowlist.ToArray() |
        Where-Object { $_ -cne "evidence-manifest.json" } |
        Sort-Object |
        ForEach-Object {
            $path = Join-Path $scratchRootFull $_
            if ([System.IO.File]::Exists($path)) {
                [ordered]@{ file = [string]$_; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
            }
        }
)
$manifest = [ordered]@{
    schema_version = 2
    proof_kind = "validation-fragment"
    generated_at_utc = [DateTimeOffset]::UtcNow.ToString("o")
    repository = $Repository
    event_name = $EventName
    identity = [ordered]@{
        commit_sha = $CommitSha.ToLowerInvariant()
        run_id = $RunId
        run_attempt = $RunAttempt
        job = $JobName
        host = $HostIdentity
    }
    contracts = [ordered]@{
        workflow = $WorkflowIdentity
        routing = $RoutingContractIdentity
        gate = $GateContractIdentity
    }
    candidate = $candidateContract
    outcome = $Outcome
    validation_shard = $validationShard
    heavy_targeted = [ordered]@{
        status = $HeavyTargetedStatus
        reason = $HeavyTargetedReason
        actual_unique_coverage = $actualUniqueCoverage
    }
    executed = [ordered]@{
        release_checks = $releaseChecks
        validation_shard = $validationShard
        targeted_suites = $targetedTelemetry
        routing_regressions = $routingRegressions
        coverage_categories = @($coverageCategories.ToArray())
    }
    artifact_contract = [ordered]@{
        success = [ordered]@{
            mode = "explicit-top-level-allowlist"
            files = @($normalizedAllowlist.ToArray())
        }
        failure = [ordered]@{
            mode = "full-scratch"
            recursive = $true
            preserve_all_generated_files = $true
        }
    }
    available_top_level_files = $availableTopLevelFiles
    artifact_digests = $artifactDigests
}

$manifestPath = Join-Path $scratchRootFull "evidence-manifest.json"
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
if ($Json.IsPresent) {
    $manifest | ConvertTo-Json -Depth 12
}
else {
    Write-Output "Evidence manifest written."
}
