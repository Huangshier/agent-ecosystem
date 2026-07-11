[CmdletBinding(DefaultParameterSetName = "GitDiff")]
param(
    [Parameter(ParameterSetName = "Paths", Mandatory = $true)]
    [Alias("Paths")]
    [string[]]$ChangedPath,
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$BaseRef = "HEAD~1",
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$HeadRef = "HEAD",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptDir
$rulesPath = Join-Path $scriptDir "validation/change-risk-rules.json"

function New-ConservativeResult {
    param([string]$Reason, [string[]]$Paths = @())
    return New-ChangeResult -Tier 3 -Paths $Paths -Reasons @($Reason) -Modules @("validation-routing")
}

function New-ChangeResult {
    param([int]$Tier, [string[]]$Paths, [string[]]$Reasons, [string[]]$Modules)
    $tierContract = $config.tiers.PSObject.Properties[[string]$Tier].Value
    $moduleSuiteMap = [ordered]@{}
    $requiredSuites = New-Object 'System.Collections.Generic.List[string]'
    foreach ($module in @($Modules | Sort-Object -Unique)) {
        $property = $config.module_suites.PSObject.Properties[[string]$module]
        $suites = if ($null -eq $property) { @() } else { @($property.Value) }
        $moduleSuiteMap[[string]$module] = @($suites)
        foreach ($suite in $suites) { $requiredSuites.Add([string]$suite) }
    }
    return [ordered]@{
        schema_version = 1
        detected_tier = $Tier
        changed_paths = @($Paths | Sort-Object -Unique)
        affected_modules = @($Modules | Sort-Object -Unique)
        required_suites = @($requiredSuites.ToArray() | Sort-Object -Unique)
        module_suite_map = $moduleSuiteMap
        required_checks = @($tierContract.required_checks)
        skipped_checks = @($tierContract.skipped_checks)
        hosted_plan = $tierContract.hosted_plan
        escalation_reason = (@($Reasons | Sort-Object -Unique) -join "; ")
    }
}

function Get-GitChangedPaths {
    param([string]$Base, [string]$Head)
    & git -C $repoRoot rev-parse --verify "$Base^{commit}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Base ref cannot be resolved: $Base" }
    & git -C $repoRoot rev-parse --verify "$Head^{commit}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Head ref cannot be resolved: $Head" }
    $lines = @(& git -C $repoRoot diff --name-status -M "$Base...$Head")
    if ($LASTEXITCODE -ne 0) { throw "Git diff failed for $Base...$Head" }
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = @($line -split "`t")
        if ($parts.Count -lt 2) { throw "Unrecognized git diff record: $line" }
        if ($parts[0] -match '^R|^C') {
            if ($parts.Count -ne 3) { throw "Unrecognized rename/copy record: $line" }
            $paths.Add($parts[1])
            $paths.Add($parts[2])
        } else {
            $paths.Add($parts[1])
        }
    }
    return @($paths.ToArray())
}

if (-not (Test-Path -LiteralPath $rulesPath)) { throw "Risk rules not found: $rulesPath" }
$config = Get-Content -LiteralPath $rulesPath -Raw | ConvertFrom-Json

try {
    $paths = if ($PSCmdlet.ParameterSetName -eq "Paths") {
        @($ChangedPath | ForEach-Object { @(([string]$_) -split ',') })
    } else { @(Get-GitChangedPaths -Base $BaseRef -Head $HeadRef) }
    $normalized = @($paths | ForEach-Object { (([string]$_).Trim().Replace('\', '/')) -replace '^\./', '' } | Where-Object { $_ } | Sort-Object -Unique)
    if ($normalized.Count -eq 0) {
        $result = New-ConservativeResult -Reason "No changed paths were available; conservatively escalated to Tier 3."
    } else {
        $maxTier = -1
        $reasons = New-Object 'System.Collections.Generic.List[string]'
        $modules = New-Object 'System.Collections.Generic.List[string]'
        foreach ($path in $normalized) {
            $matched = $false
            foreach ($rule in @($config.rules)) {
                if ($path -match [string]$rule.pattern) {
                    $matched = $true
                    $tier = [int]$rule.tier
                    if ($tier -gt $maxTier) { $maxTier = $tier }
                    $reasons.Add("$path matched $($rule.id) (Tier $tier)")
                    foreach ($module in @($rule.modules)) { $modules.Add([string]$module) }
                    break
                }
            }
            if (-not $matched) {
                $maxTier = [Math]::Max($maxTier, [int]$config.unknown_tier)
                $modules.Add("unknown")
                $reasons.Add("$path is unknown; conservatively escalated to Tier $($config.unknown_tier)")
            }
        }
        $result = New-ChangeResult -Tier $maxTier -Paths $normalized -Reasons @($reasons.ToArray()) -Modules @($modules.ToArray())
    }
} catch {
    $result = New-ConservativeResult -Reason ("Classification input could not be resolved: {0}" -f $_.Exception.Message)
}

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 8
} else {
    Write-Output ("Detected tier: Tier {0}" -f $result.detected_tier)
    Write-Output ("Required checks: {0}" -f (@($result.required_checks) -join ", "))
    Write-Output ("Skipped checks (not required; not PASS): {0}" -f ($(if (@($result.skipped_checks).Count) { @($result.skipped_checks) -join ", " } else { "none" })))
    Write-Output ("Escalation reason: {0}" -f $result.escalation_reason)
    Write-Output ("Affected modules: {0}" -f (@($result.affected_modules) -join ", "))
    Write-Output ("Hosted plan: {0} full validator call(s), {1} targeted OS job(s)" -f $result.hosted_plan.full_validator_calls, $result.hosted_plan.targeted_os_jobs)
}
