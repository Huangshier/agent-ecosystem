[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ScratchRoot,
    [Parameter(Mandatory = $true)][ValidateSet("success", "failure")][string]$Outcome,
    [Parameter(Mandatory = $true)][string]$CommitSha,
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$RunAttempt,
    [Parameter(Mandatory = $true)][string]$JobName,
    [Parameter(Mandatory = $true)][string]$HostIdentity,
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
    if ($validationShard -notin @("Full", "PlatformNeutral", "RuntimePlatform")) {
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
$manifest = [ordered]@{
    schema_version = 1
    generated_at_utc = [DateTimeOffset]::UtcNow.ToString("o")
    identity = [ordered]@{
        commit_sha = $CommitSha.ToLowerInvariant()
        run_id = $RunId
        run_attempt = $RunAttempt
        job = $JobName
        host = $HostIdentity
    }
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
}

$manifestPath = Join-Path $scratchRootFull "evidence-manifest.json"
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
if ($Json.IsPresent) {
    $manifest | ConvertTo-Json -Depth 12
}
else {
    Write-Output "Evidence manifest written."
}
