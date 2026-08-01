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
    param(
        [int]$Tier,
        [bool]$RunSelfProtection,
        [string]$SelfProtectionReason,
        [bool]$RequiresWindowsPowerShell
    )

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
    $iterationActions.Add($targeted)
    if ($RunSelfProtection) {
        $iterationActions.Add((New-LocalValidationAction -Id "validation-self-protection" -Script "scripts/test-heavy-targeted-regression.ps1" -Arguments @() -HostName "current" -Suite "validation-self-protection" -Reason $SelfProtectionReason))
    }
    else {
        $iterationSkips.Add((New-LocalValidationSkip -Id "validation-self-protection" -Reason $SelfProtectionReason))
    }
    $iterationSkips.Add((New-LocalValidationSkip -Id "full-release-validation" -Reason "Iteration runs affected suites and independent oracles, not a release checkpoint."))

    $prePushActions = New-Object 'System.Collections.Generic.List[object]'
    $prePushSkips = New-Object 'System.Collections.Generic.List[object]'
    $prePushActions.Add($lightweight)
    $prePushActions.Add($targeted)
    if ($RequiresWindowsPowerShell) {
        $prePushActions.Add((New-LocalValidationAction -Id "affected-change-validation-windows-powershell" -Script "scripts/validate-targeted-change.ps1" -Arguments @("-Mode", $targetedMode, "-ExecutionHost", "windows-powershell") -HostName "windows-powershell" -Suite "affected-windows-powershell-oracle" -Reason "The affected suite set contains PowerShell 5.1 compatibility semantics."))
    }
    else {
        $prePushSkips.Add((New-LocalValidationSkip -Id "affected-windows-powershell-oracle" -Reason "No affected suite requires Windows PowerShell 5.1 semantics."))
    }
    if ($RunSelfProtection) {
        $prePushActions.Add((New-LocalValidationAction -Id "validation-self-protection" -Script "scripts/test-heavy-targeted-regression.ps1" -Arguments @() -HostName "current" -Suite "validation-self-protection" -Reason $SelfProtectionReason))
    }
    else {
        $prePushSkips.Add((New-LocalValidationSkip -Id "validation-self-protection" -Reason $SelfProtectionReason))
    }
    $prePushSkips.Add((New-LocalValidationSkip -Id "full-release-validation" -Reason "Pre-push is satisfied by affected suites, the necessary WinPS oracle, and independent self-protection."))

    $releaseActions = New-Object 'System.Collections.Generic.List[object]'
    $releaseSkips = New-Object 'System.Collections.Generic.List[object]'
    $releaseActions.Add($lightweight)
    if ($RunSelfProtection) {
        $releaseActions.Add((New-LocalValidationAction -Id "validation-self-protection" -Script "scripts/test-heavy-targeted-regression.ps1" -Arguments @() -HostName "pwsh" -Suite "validation-self-protection" -Reason $SelfProtectionReason))
    }
    else {
        $releaseSkips.Add((New-LocalValidationSkip -Id "validation-self-protection" -Reason $SelfProtectionReason))
    }
    foreach ($hostName in @("pwsh", "windows-powershell")) {
        $releaseActions.Add((New-LocalValidationAction -Id ("full-release-validation-{0}" -f $hostName) -Script "scripts/validate-release.ps1" -Arguments @("-ValidationShard", "RepositoryCheckpoint") -HostName $hostName -Suite "full-release-validation" -Reason "Release validation always preserves the complete dual-host repository checkpoint boundary."))
    }

    return [ordered]@{
        schema_version = 2
        stages = [ordered]@{
            iteration = [ordered]@{ actions = @($iterationActions.ToArray()); skipped = @($iterationSkips.ToArray()) }
            pre_push = [ordered]@{ actions = @($prePushActions.ToArray()); skipped = @($prePushSkips.ToArray()) }
            release = [ordered]@{ actions = @($releaseActions.ToArray()); skipped = @($releaseSkips.ToArray()) }
        }
    }
}

function New-ConservativeResult {
    param([string]$Reason, [string[]]$Paths = @(), [string]$Base = "", [string]$Head = "")
    return New-ChangeResult -Tier 3 -Paths $Paths -Reasons @($Reason) -Modules @("unknown") -Base $Base -Head $Head -ConservativeFallback
}

function New-ChangeResult {
    param(
        [int]$Tier,
        [string[]]$Paths,
        [string[]]$Reasons,
        [string[]]$Modules,
        [string]$Base = "",
        [string]$Head = "",
        [switch]$ConservativeFallback,
        [switch]$ControlPlane
    )
    $moduleSuiteMap = [ordered]@{}
    $requiredSuites = New-Object 'System.Collections.Generic.List[string]'
    foreach ($module in @($Modules | Sort-Object -Unique)) {
        $property = $config.module_suites.PSObject.Properties[[string]$module]
        $suites = if ($null -eq $property) { @() } else { @($property.Value) }
        $moduleSuiteMap[[string]$module] = @($suites)
        foreach ($suite in $suites) { $requiredSuites.Add([string]$suite) }
    }
    if ($ConservativeFallback.IsPresent -or @($Modules | Where-Object { [string]$_ -match '^(unknown|unsupported-)' }).Count -gt 0) {
        foreach ($suite in @($config.fallback_suites)) { $requiredSuites.Add([string]$suite) }
        foreach ($module in @($Modules | Sort-Object -Unique)) { $moduleSuiteMap[[string]$module] = @($config.fallback_suites) }
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
    $hasSelfProtectionPath = $ControlPlane.IsPresent
    $hasAmbiguousModule = @($Modules | Where-Object {
        [string]$_ -match '^(unknown|unsupported-)'
    }).Count -gt 0
    $runSelfProtection = $hasSelfProtectionPath -or $hasAmbiguousModule -or $coverageDifference.Count -gt 0
    $selfProtectionReason = if ($coverageDifference.Count -gt 0) {
        "full-coverage-unproven"
    } elseif ($hasAmbiguousModule) {
        "unknown-or-ambiguous-input"
    } elseif ($hasSelfProtectionPath) {
        "self-protection-control-surface"
    } elseif ($Tier -lt 3) {
        "not-tier-3"
    } else {
        "no-control-plane-change"
    }
    $suiteHostMap = [ordered]@{}
    $requiredHosts = New-Object 'System.Collections.Generic.List[string]'
    $requiresWindowsPowerShell = $false
    $requiredWindowsPowerShellSuites = New-Object 'System.Collections.Generic.List[string]'
    foreach ($suite in @($requiredSuites.ToArray() | Sort-Object -Unique)) {
        $hostProperty = $config.suite_hosts.PSObject.Properties[[string]$suite]
        if ($null -eq $hostProperty -or @($hostProperty.Value).Count -eq 0) {
            $runSelfProtection = $true
            $selfProtectionReason = "unknown-suite-host-dependency"
            foreach ($hostName in @("windows-latest", "ubuntu-latest", "macos-latest")) { $requiredHosts.Add($hostName) }
            $suiteHostMap[[string]$suite] = @("windows-latest", "ubuntu-latest", "macos-latest")
        } else {
            $suiteHostMap[[string]$suite] = @($hostProperty.Value)
            foreach ($hostName in @($hostProperty.Value)) { $requiredHosts.Add([string]$hostName) }
        }
        if (@($config.windows_powershell_suites) -contains [string]$suite) {
            $requiresWindowsPowerShell = $true
            $requiredWindowsPowerShellSuites.Add([string]$suite)
        }
    }
    if ($runSelfProtection) {
        foreach ($hostName in @($config.self_protection_hosts)) { $requiredHosts.Add([string]$hostName) }
    }
    $localPlan = New-LocalValidationPlan -Tier $Tier -RunSelfProtection $runSelfProtection -SelfProtectionReason $selfProtectionReason -RequiresWindowsPowerShell $requiresWindowsPowerShell
    $requiredChecks = New-Object 'System.Collections.Generic.List[string]'
    $skippedChecks = New-Object 'System.Collections.Generic.List[string]'
    foreach ($check in @("change-classification", "diff-check", "document-and-data-parse", "public-safe-scan", "base-guard", "identity-guard")) {
        $requiredChecks.Add($check)
    }
    if ($Tier -le 1) { $requiredChecks.Add("quick-repository-checks") } else { $skippedChecks.Add("quick-repository-checks") }
    $sortedRequiredSuites = @($requiredSuites.ToArray() | Sort-Object -Unique)
    if ($sortedRequiredSuites.Count -gt 0) {
        $requiredChecks.Add("targeted-module-checks")
        foreach ($suite in $sortedRequiredSuites) { $requiredChecks.Add("affected-suite:$suite") }
    }
    else {
        $skippedChecks.Add("targeted-module-checks")
    }
    if ($requiresWindowsPowerShell) { $requiredChecks.Add("affected-windows-powershell") } else { $skippedChecks.Add("affected-windows-powershell") }
    if ($runSelfProtection) { $requiredChecks.Add("validation-self-protection") } else { $skippedChecks.Add("validation-self-protection") }
    $skippedChecks.Add("full-release-matrix")
    $hostedPlan = [ordered]@{
        validation_jobs = @("classify") + $(if ($Tier -le 1) { @("quick-validation") } else { @("affected-validation") }) + $(if ($runSelfProtection) { @("validation-self-protection") } else { @() })
        full_validator_calls = 0
        platform_neutral_validator_calls = 0
        runtime_platform_validator_calls = 0
        targeted_os_jobs = @($requiredHosts.ToArray() | Sort-Object -Unique).Count
    }
    return [ordered]@{
        schema_version = 2
        detected_tier = $Tier
        base_ref = $Base
        head_ref = $Head
        changed_paths = @($Paths | Sort-Object -Unique)
        affected_modules = @($Modules | Sort-Object -Unique)
        base_check_modules = @($Modules | Where-Object { @($config.base_check_modules) -contains [string]$_ } | Sort-Object -Unique)
        required_suites = $sortedRequiredSuites
        module_suite_map = $moduleSuiteMap
        required_hosts = @($requiredHosts.ToArray() | Sort-Object -Unique)
        suite_host_map = $suiteHostMap
        requires_windows_powershell = [bool]$requiresWindowsPowerShell
        required_windows_powershell_suites = @($requiredWindowsPowerShellSuites.ToArray() | Sort-Object -Unique)
        run_validation_self_protection = [bool]$runSelfProtection
        validation_self_protection_reason = $selfProtectionReason
        control_plane = [bool]$ControlPlane.IsPresent
        self_protection_required = [bool]$runSelfProtection
        self_protection_reason = $selfProtectionReason
        conservative_fallback = [bool]($ConservativeFallback.IsPresent -or $hasAmbiguousModule)
        required_checks = @($requiredChecks.ToArray())
        skipped_checks = @($skippedChecks.ToArray())
        hosted_plan = $hostedPlan
        local_plan = $localPlan
        run_heavy_targeted_regression = [bool]$runSelfProtection
        heavy_targeted_reason = $selfProtectionReason
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

function Invoke-ChangeSensitiveScan {
    param([string]$Base, [string]$Head)

    $scanScript = Join-Path $scriptDir "validation/pr-secret-keyword-scan.ps1"
    if (-not (Test-Path -LiteralPath $scanScript)) {
        throw "Sensitive scan failure: scan script is missing: $scanScript"
    }
    $previousLocation = Get-Location
    try {
        Set-Location -LiteralPath $repoRoot
        $global:LASTEXITCODE = 0
    $scanOutput = @(& $scanScript -BaseRef $Base -HeadRef $Head 2>&1)
    $scanExit = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($scanExit -ne 0) {
        $scanText = ($scanOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        throw "Sensitive scan failure:$([Environment]::NewLine)$scanText"
        }
    }
    finally {
        Set-Location $previousLocation
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
        Invoke-ChangeSensitiveScan -Base $normalizedBase -Head $normalizedHead
        @($boundary.paths)
    }
    $normalized = @($paths | ForEach-Object { (([string]$_).Trim().Replace('\', '/')) -replace '^\./', '' } | Where-Object { $_ } | Sort-Object -Unique)
    if ($normalized.Count -eq 0) {
        $result = New-ConservativeResult -Reason "No changed paths were available; conservatively escalated to Tier 3." -Base $normalizedBase -Head $normalizedHead
    } else {
        $maxTier = -1
        $reasons = New-Object 'System.Collections.Generic.List[string]'
        $modules = New-Object 'System.Collections.Generic.List[string]'
        $hasControlPlane = $false
        foreach ($path in $normalized) {
            $matched = $false
            foreach ($rule in @($config.rules)) {
                if ($path -match [string]$rule.pattern) {
                    $matched = $true
                    $tier = [int]$rule.tier
                    if ($tier -gt $maxTier) { $maxTier = $tier }
                    $reasons.Add("$path matched $($rule.id) (Tier $tier)")
                    foreach ($module in @($rule.modules)) { $modules.Add([string]$module) }
                    $controlPlaneProperty = @($rule.PSObject.Properties | Where-Object { $_.Name -ceq "control_plane" })
                    if ($controlPlaneProperty.Count -eq 1) {
                        if ($controlPlaneProperty[0].Value -isnot [bool]) {
                            throw "Routing rule '$($rule.id)' has an invalid control_plane marker."
                        }
                        if ([bool]$controlPlaneProperty[0].Value) { $hasControlPlane = $true }
                    }
                    break
                }
            }
            if (-not $matched) {
                $maxTier = [Math]::Max($maxTier, [int]$config.unknown_tier)
                $modules.Add("unknown")
                $reasons.Add("$path is unknown; conservatively escalated to Tier $($config.unknown_tier)")
            }
        }
        $result = New-ChangeResult -Tier $maxTier -Paths $normalized -Reasons @($reasons.ToArray()) -Modules @($modules.ToArray()) -Base $normalizedBase -Head $normalizedHead -ControlPlane:$hasControlPlane
    }
} catch {
    if ([string]$_.Exception.Message -like "Sensitive scan failure:*") {
        throw
    }
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
