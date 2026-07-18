[CmdletBinding(DefaultParameterSetName = "GitDiff")]
param(
    [Parameter(ParameterSetName = "Paths", Mandatory = $true)]
    [Alias("Paths")]
    [string[]]$ChangedPath,
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$BaseRef = "HEAD~1",
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$HeadRef = "HEAD",
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$RepositoryRoot = "",
    [Parameter(ParameterSetName = "GitDiff")]
    [switch]$ForcePush,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$defaultRepoRoot = Split-Path -Parent $scriptDir
$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $defaultRepoRoot } else { [System.IO.Path]::GetFullPath($RepositoryRoot) }
$rulesPath = Join-Path $scriptDir "validation/change-risk-rules.json"

function New-LocalValidationAction {
    param(
        [string]$Id,
        [string]$Script,
        [string[]]$Arguments,
        [string]$HostName,
        [string]$Suite,
        [string]$Reason
    )
    return [ordered]@{
        id = $Id
        script = $Script
        arguments = @($Arguments)
        host = $HostName
        suite = $Suite
        reason = $Reason
    }
}

function New-LocalValidationSkip {
    param([string]$Id, [string]$Reason)
    return [ordered]@{ id = $Id; status = "SKIPPED"; reason = $Reason }
}

function New-LocalValidationPlan {
    param([int]$Tier, [bool]$RunHeavyTargeted, [string]$HeavyTargetedReason)

    $lightweight = New-LocalValidationAction `
        -Id "classifier-contracts" `
        -Script "scripts/test-validate-change.ps1" `
        -Arguments @() `
        -HostName "current" `
        -Suite "classification-and-routing-contracts" `
        -Reason "Always verify deterministic classification and routing before costlier validation."
    $targetedMode = if ($Tier -le 1) { "quick" } else { "targeted" }
    $targeted = New-LocalValidationAction `
        -Id "affected-change-validation" `
        -Script "scripts/validate-targeted-change.ps1" `
        -Arguments @("-Mode", $targetedMode) `
        -HostName "current" `
        -Suite ("tier-{0}-{1}" -f $Tier, $targetedMode) `
        -Reason "Run the affected-module checks selected by the classifier."

    $iterationActions = New-Object 'System.Collections.Generic.List[object]'
    $iterationSkips = New-Object 'System.Collections.Generic.List[object]'
    $iterationActions.Add($lightweight)
    if ($Tier -lt 3) {
        $iterationActions.Add($targeted)
        $iterationSkips.Add((New-LocalValidationSkip -Id "full-release-validation" -Reason "Tier 0-2 iteration uses affected checks instead of full validation."))
    }
    else {
        $iterationSkips.Add((New-LocalValidationSkip -Id "affected-change-validation" -Reason "Tier 3 cannot be represented by targeted validation."))
        $iterationSkips.Add((New-LocalValidationSkip -Id "heavy-targeted-regression" -Reason "Iteration never runs heavy targeted regression; defer it to pre-push."))
        $iterationSkips.Add((New-LocalValidationSkip -Id "full-release-validation" -Reason "Iteration never runs full validation; defer it to pre-push."))
    }

    $prePushActions = New-Object 'System.Collections.Generic.List[object]'
    $prePushSkips = New-Object 'System.Collections.Generic.List[object]'
    $prePushActions.Add($lightweight)
    if ($Tier -lt 3) {
        $prePushActions.Add($targeted)
        $prePushSkips.Add((New-LocalValidationSkip -Id "full-release-validation" -Reason "Tier 0-2 pre-push validation is satisfied by affected checks."))
    }
    else {
        $prePushSkips.Add((New-LocalValidationSkip -Id "affected-change-validation" -Reason "Tier 3 requires the complete validator."))
        if ($RunHeavyTargeted) {
            foreach ($hostName in @("pwsh", "windows-powershell")) {
                $prePushActions.Add((New-LocalValidationAction -Id ("heavy-targeted-regression-{0}" -f $hostName) -Script "scripts/test-heavy-targeted-regression.ps1" -Arguments @() -HostName $hostName -Suite "heavy-targeted-regression" -Reason $HeavyTargetedReason))
            }
        }
        else {
            $prePushSkips.Add((New-LocalValidationSkip -Id "heavy-targeted-regression" -Reason $HeavyTargetedReason))
        }
        foreach ($hostName in @("pwsh", "windows-powershell")) {
            $prePushActions.Add((New-LocalValidationAction -Id ("full-release-validation-{0}" -f $hostName) -Script "scripts/validate-release.ps1" -Arguments @() -HostName $hostName -Suite "full-release-validation" -Reason "Tier 3 pre-push preserves the complete dual-host local boundary."))
        }
    }

    $releaseActions = New-Object 'System.Collections.Generic.List[object]'
    $releaseSkips = New-Object 'System.Collections.Generic.List[object]'
    $releaseActions.Add($lightweight)
    if ($Tier -eq 3 -and $RunHeavyTargeted) {
        foreach ($hostName in @("pwsh", "windows-powershell")) {
            $releaseActions.Add((New-LocalValidationAction -Id ("heavy-targeted-regression-{0}" -f $hostName) -Script "scripts/test-heavy-targeted-regression.ps1" -Arguments @() -HostName $hostName -Suite "heavy-targeted-regression" -Reason $HeavyTargetedReason))
        }
    }
    else {
        $releaseSkips.Add((New-LocalValidationSkip -Id "heavy-targeted-regression" -Reason $(if ($Tier -eq 3) { $HeavyTargetedReason } else { "Heavy targeted regression is a Tier 3 self-protection check." })))
    }
    foreach ($hostName in @("pwsh", "windows-powershell")) {
        $releaseActions.Add((New-LocalValidationAction -Id ("full-release-validation-{0}" -f $hostName) -Script "scripts/validate-release.ps1" -Arguments @() -HostName $hostName -Suite "full-release-validation" -Reason "Release validation always preserves the complete dual-host local boundary."))
    }

    return [ordered]@{
        schema_version = 1
        stages = [ordered]@{
            iteration = [ordered]@{ actions = @($iterationActions.ToArray()); skipped = @($iterationSkips.ToArray()) }
            pre_push = [ordered]@{ actions = @($prePushActions.ToArray()); skipped = @($prePushSkips.ToArray()) }
            release = [ordered]@{ actions = @($releaseActions.ToArray()); skipped = @($releaseSkips.ToArray()) }
        }
    }
}

function New-ConservativeResult {
    param([string]$Reason, [string[]]$Paths = @(), [string]$Base = "", [string]$Head = "")
    return New-ChangeResult -Tier 3 -Paths $Paths -Reasons @($Reason) -Modules @("validation-routing") -Base $Base -Head $Head
}

function New-ChangeResult {
    param([int]$Tier, [string[]]$Paths, [string[]]$Reasons, [string[]]$Modules, [string]$Base = "", [string]$Head = "")
    $tierContract = $config.tiers.PSObject.Properties[[string]$Tier].Value
    $moduleSuiteMap = [ordered]@{}
    $requiredSuites = New-Object 'System.Collections.Generic.List[string]'
    foreach ($module in @($Modules | Sort-Object -Unique)) {
        $property = $config.module_suites.PSObject.Properties[[string]$module]
        $suites = if ($null -eq $property) { @() } else { @($property.Value) }
        $moduleSuiteMap[[string]$module] = @($suites)
        foreach ($suite in $suites) { $requiredSuites.Add([string]$suite) }
    }
    $heavyTargetedRequiredSuites = @(
        "agent-skill-bridge",
        "bootstrap-safety",
        "installer-contract",
        "knowledge-contracts",
        "project-context-gate",
        "runtime-smoke"
    )
    $fullValidatorCoverageSuites = @(
        "agent-skill-bridge",
        "bootstrap-safety",
        "installer-contract",
        "knowledge-contracts",
        "project-context-gate",
        "runtime-smoke"
    )
    $coverageDifference = @(
        Compare-Object -ReferenceObject $heavyTargetedRequiredSuites -DifferenceObject $fullValidatorCoverageSuites
    )
    $selfProtectionPatterns = @(
        '^\.github/workflows/',
        '^scripts/validate-(change|targeted-change|release)\.ps1$',
        '^scripts/test-validate-change\.ps1$',
        '^scripts/test-validation-evidence-contract\.ps1$',
        '^scripts/validation/change-risk-rules\.json$',
        '^scripts/validation/change-risk-fixtures/',
        '^scripts/validation/required-validation-gate\.ps1$',
        '^scripts/validation/write-evidence-manifest\.ps1$',
        '^scripts/validation/release-.*\.ps1$',
        '^scripts/validation/release-.+-fixtures/'
    )
    $hasSelfProtectionPath = @($Paths | Where-Object {
        $candidate = [string]$_
        @($selfProtectionPatterns | Where-Object { $candidate -match $_ }).Count -gt 0
    }).Count -gt 0
    $hasAmbiguousModule = @($Modules | Where-Object {
        [string]$_ -match '^(unknown|unsupported-|validation-routing)'
    }).Count -gt 0
    $runHeavyTargeted = $false
    $heavyTargetedReason = "not-tier-3"
    if ($Tier -eq 3) {
        if ($coverageDifference.Count -gt 0) {
            $runHeavyTargeted = $true
            $heavyTargetedReason = "full-coverage-unproven"
        }
        elseif ($hasSelfProtectionPath) {
            $runHeavyTargeted = $true
            $heavyTargetedReason = "self-protection-control-surface"
        }
        elseif ($hasAmbiguousModule) {
            $runHeavyTargeted = $true
            $heavyTargetedReason = "unknown-or-ambiguous-input"
        }
        else {
            $heavyTargetedReason = "tier-3-full-covers-required-suites"
        }
    }
    $localPlan = New-LocalValidationPlan -Tier $Tier -RunHeavyTargeted $runHeavyTargeted -HeavyTargetedReason $heavyTargetedReason
    return [ordered]@{
        schema_version = 1
        detected_tier = $Tier
        base_ref = $Base
        head_ref = $Head
        changed_paths = @($Paths | Sort-Object -Unique)
        affected_modules = @($Modules | Sort-Object -Unique)
        base_check_modules = @($Modules | Where-Object { @($config.base_check_modules) -contains [string]$_ } | Sort-Object -Unique)
        required_suites = @($requiredSuites.ToArray() | Sort-Object -Unique)
        module_suite_map = $moduleSuiteMap
        required_checks = @($tierContract.required_checks)
        skipped_checks = @($tierContract.skipped_checks)
        hosted_plan = $tierContract.hosted_plan
        local_plan = $localPlan
        run_heavy_targeted_regression = [bool]$runHeavyTargeted
        heavy_targeted_reason = $heavyTargetedReason
        heavy_targeted_required_suites = $heavyTargetedRequiredSuites
        full_validator_coverage_suites = $fullValidatorCoverageSuites
        escalation_reason = (@($Reasons | Sort-Object -Unique) -join "; ")
    }
}

function Get-GitChangedPaths {
    param([string]$Base, [string]$Head)
    $resolvedBase = @(& git -C $repoRoot rev-parse --verify "$Base^{commit}" 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Base ref cannot be resolved: $Base" }
    $resolvedHead = @(& git -C $repoRoot rev-parse --verify "$Head^{commit}" 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Head ref cannot be resolved: $Head" }
    $normalizedBase = ([string]$resolvedBase[-1]).Trim()
    $normalizedHead = ([string]$resolvedHead[-1]).Trim()
    if ($normalizedBase -notmatch '^[0-9a-fA-F]{40,64}$' -or $normalizedHead -notmatch '^[0-9a-fA-F]{40,64}$') {
        throw "Resolved refs were not commit object IDs."
    }
    & git -C $repoRoot merge-base --is-ancestor $normalizedBase $normalizedHead 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Base ref is not an ancestor of head: $Base -> $Head" }
    $lines = @(& git -C $repoRoot diff --name-status -M $normalizedBase $normalizedHead)
    if ($LASTEXITCODE -ne 0) { throw "Git diff failed for $normalizedBase..$normalizedHead" }
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
    return [ordered]@{
        base_ref = $normalizedBase.ToLowerInvariant()
        head_ref = $normalizedHead.ToLowerInvariant()
        paths = @($paths.ToArray())
    }
}

if (-not (Test-Path -LiteralPath $rulesPath)) { throw "Risk rules not found: $rulesPath" }
$config = Get-Content -LiteralPath $rulesPath -Raw | ConvertFrom-Json

try {
    $normalizedBase = ""
    $normalizedHead = ""
    if ($PSCmdlet.ParameterSetName -eq "GitDiff" -and $ForcePush.IsPresent) {
        throw "Push event was marked as forced."
    }
    if ($PSCmdlet.ParameterSetName -eq "GitDiff" -and $BaseRef -match '^0+$') {
        throw "Base ref is the all-zero object ID."
    }
    $paths = if ($PSCmdlet.ParameterSetName -eq "Paths") {
        @($ChangedPath | ForEach-Object { @(([string]$_) -split ',') })
    } else {
        $boundary = Get-GitChangedPaths -Base $BaseRef -Head $HeadRef
        $normalizedBase = [string]$boundary.base_ref
        $normalizedHead = [string]$boundary.head_ref
        @($boundary.paths)
    }
    $normalized = @($paths | ForEach-Object { (([string]$_).Trim().Replace('\', '/')) -replace '^\./', '' } | Where-Object { $_ } | Sort-Object -Unique)
    if ($normalized.Count -eq 0) {
        $result = New-ConservativeResult -Reason "No changed paths were available; conservatively escalated to Tier 3." -Base $normalizedBase -Head $normalizedHead
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
        $result = New-ChangeResult -Tier $maxTier -Paths $normalized -Reasons @($reasons.ToArray()) -Modules @($modules.ToArray()) -Base $normalizedBase -Head $normalizedHead
    }
} catch {
    $result = New-ConservativeResult -Reason ("Classification input could not be resolved: {0}" -f $_.Exception.Message)
}

# Expected conservative fallbacks can follow a failed native git command. Do not
# leak that command's exit code after the classifier has returned a valid Tier 3 result.
$global:LASTEXITCODE = 0

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 12
} else {
    Write-Output ("Detected tier: Tier {0}" -f $result.detected_tier)
    Write-Output ("Required checks: {0}" -f (@($result.required_checks) -join ", "))
    Write-Output ("Skipped checks (not required; not PASS): {0}" -f ($(if (@($result.skipped_checks).Count) { @($result.skipped_checks) -join ", " } else { "none" })))
    Write-Output ("Escalation reason: {0}" -f $result.escalation_reason)
    Write-Output ("Affected modules: {0}" -f (@($result.affected_modules) -join ", "))
    Write-Output ("Run heavy targeted regression: {0} ({1})" -f $result.run_heavy_targeted_regression, $result.heavy_targeted_reason)
    Write-Output ("Hosted plan: full={0}, platform-neutral={1}, runtime-platform={2}, targeted OS jobs={3}" -f $result.hosted_plan.full_validator_calls, $result.hosted_plan.platform_neutral_validator_calls, $result.hosted_plan.runtime_platform_validator_calls, $result.hosted_plan.targeted_os_jobs)
    Write-Output ("Local plan: iteration={0}, pre-push={1}, release={2} action(s)" -f @($result.local_plan.stages.iteration.actions).Count, @($result.local_plan.stages.pre_push.actions).Count, @($result.local_plan.stages.release.actions).Count)
}
