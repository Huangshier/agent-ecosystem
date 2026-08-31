[CmdletBinding(DefaultParameterSetName = "GitDiff")]
param(
    [ValidateSet("iteration", "pre-push", "release")]
    [string]$Stage = "iteration",
    [Parameter(ParameterSetName = "Paths", Mandatory = $true)]
    [Alias("Paths")]
    [string[]]$ChangedPath,
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$BaseRef = "HEAD~1",
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$HeadRef = "HEAD",
    [Parameter(ParameterSetName = "GitDiff")]
    [string]$RepositoryRoot = "",
    [string]$ScratchRoot = "",
    [string]$IterationEvidencePath = "",
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir "validation/powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime
$defaultRepoRoot = Split-Path -Parent $scriptDir
$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $defaultRepoRoot } else { [System.IO.Path]::GetFullPath($RepositoryRoot) }
$script:inputParameterSet = $PSCmdlet.ParameterSetName
$stageKey = $Stage.Replace('-', '_')
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-local-validation-{0}" -f ([Guid]::NewGuid().ToString("N")))
}
$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
$resultPath = Join-Path $scratchRootFull "local-validation-result.json"

function Get-HostExecutable {
    param([string]$HostName)
    if ($HostName -eq "current") {
        return [string](Get-Process -Id $PID).Path
    }
    return Resolve-AgentEcosystemPwshExecutable
}

function Format-CommandArgument {
    param([string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return ('"{0}"' -f $Value.Replace('"', '\"'))
}

function ConvertTo-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Value)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Invoke-LocalGit {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git -C $repoRoot @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($exitCode -ne 0) { throw "git $($Arguments -join ' ') failed." }
    return @($output)
}

function Get-LocalValidationAuthorityIdentity {
    param([object]$Classification)
    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($path in @(
        "scripts/invoke-local-validation.ps1",
        "scripts/validate-change.ps1",
        "scripts/validation/change-risk-rules.json",
        "scripts/validation/release-classifier-output-contract.ps1",
        "scripts/validation/local-validation-plan-contract.ps1",
        "scripts/validation/powershell-runtime-requirement.ps1"
    )) {
        [void]$paths.Add($path)
    }
    foreach ($action in @($Classification.local_plan.stages.iteration.actions) + @($Classification.local_plan.stages.pre_push.actions)) {
        [void]$paths.Add([string]$action.script)
    }
    $orderedPaths = @($paths)
    [Array]::Sort($orderedPaths, [StringComparer]::Ordinal)
    $files = @(
        foreach ($relativePath in $orderedPaths) {
            $fullPath = Join-Path $repoRoot $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
            if (-not [System.IO.File]::Exists($fullPath)) { throw "Validation authority file is missing: $relativePath" }
            [ordered]@{
                path = $relativePath
                sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    )
    return [ordered]@{
        sha256 = ConvertTo-Sha256Hex -Value ($files | ConvertTo-Json -Depth 5 -Compress)
        files = $files
    }
}

function Get-LocalValidationRoutingIdentity {
    param([object]$Classification)
    $routing = [ordered]@{
        schema_version = [int]$Classification.schema_version
        detected_tier = [int]$Classification.detected_tier
        base_ref = [string]$Classification.base_ref
        head_ref = [string]$Classification.head_ref
        changed_paths = @($Classification.changed_paths)
        affected_modules = @($Classification.affected_modules)
        base_check_modules = @($Classification.base_check_modules)
        required_suites = @($Classification.required_suites)
        module_suite_map = $Classification.module_suite_map
        required_hosts = @($Classification.required_hosts)
        suite_host_map = $Classification.suite_host_map
        run_validation_self_protection = [bool]$Classification.run_validation_self_protection
        validation_self_protection_reason = [string]$Classification.validation_self_protection_reason
        control_plane = [bool]$Classification.control_plane
        conservative_fallback = [bool]$Classification.conservative_fallback
        iteration = $Classification.local_plan.stages.iteration
        pre_push = $Classification.local_plan.stages.pre_push
    }
    return [ordered]@{
        sha256 = ConvertTo-Sha256Hex -Value ($routing | ConvertTo-Json -Depth 14 -Compress)
    }
}

function Get-LocalValidationRuntimeIdentity {
    param([object]$Classification)
    $hostNames = @(
        @($Classification.local_plan.stages.iteration.actions.host) +
        @($Classification.local_plan.stages.pre_push.actions.host) |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
    )
    $hosts = @(
        foreach ($hostName in $hostNames) {
            $executable = Get-HostExecutable -HostName $hostName
            if ([string]::IsNullOrWhiteSpace($executable) -or -not [System.IO.File]::Exists($executable)) {
                throw "Required validation host '$hostName' is unavailable."
            }
            [ordered]@{
                name = $hostName
                executable_sha256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    )
    $runtime = [ordered]@{
        machine_sha256 = ConvertTo-Sha256Hex -Value ([Environment]::MachineName)
        os_description = [Runtime.InteropServices.RuntimeInformation]::OSDescription
        os_architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        process_architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        framework = [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
        powershell_edition = [string]$PSVersionTable.PSEdition
        powershell_version = $PSVersionTable.PSVersion.ToString()
        powershell_platform = [string]$PSVersionTable.Platform
        powershell_os = [string]$PSVersionTable.OS
        culture = [Globalization.CultureInfo]::CurrentCulture.Name
        ui_culture = [Globalization.CultureInfo]::CurrentUICulture.Name
        hosts = $hosts
    }
    return [ordered]@{
        sha256 = ConvertTo-Sha256Hex -Value ($runtime | ConvertTo-Json -Depth 6 -Compress)
        details = $runtime
    }
}

function Get-LocalValidationEvidenceBinding {
    param([object]$Classification)
    try {
        $checkoutHead = ([string](@(Invoke-LocalGit rev-parse --verify "HEAD^{commit}")[0])).Trim().ToLowerInvariant()
        $headCommit = if ($script:inputParameterSet -eq "Paths") {
            $checkoutHead
        }
        else {
            ([string]$Classification.head_ref).Trim().ToLowerInvariant()
        }
        $baseCommit = if ($script:inputParameterSet -eq "Paths") { $null } else { ([string]$Classification.base_ref).Trim().ToLowerInvariant() }
        if ($headCommit -notmatch '^[0-9a-f]{40,64}$' -or ($null -ne $baseCommit -and $baseCommit -notmatch '^[0-9a-f]{40,64}$')) {
            throw "Candidate commit identity is unavailable."
        }
        $tree = ([string](@(Invoke-LocalGit rev-parse --verify "$headCommit^{tree}")[0])).Trim().ToLowerInvariant()
        if ($tree -notmatch '^[0-9a-f]{40,64}$') { throw "Candidate tree identity is unavailable." }
        $worktreeStatus = @(Invoke-LocalGit status --porcelain=v1 --untracked-files=all)
        $candidate = [ordered]@{
            input_mode = $script:inputParameterSet
            base_commit = $baseCommit
            head_commit = $headCommit
            tree = $tree
            checkout_head_commit = $checkoutHead
            head_matches_checkout = [bool]($headCommit -ceq $checkoutHead)
            worktree_clean = [bool]($worktreeStatus.Count -eq 0)
        }
        $authority = Get-LocalValidationAuthorityIdentity -Classification $Classification
        $routing = Get-LocalValidationRoutingIdentity -Classification $Classification
        $runtime = Get-LocalValidationRuntimeIdentity -Classification $Classification
        $identity = [ordered]@{
            candidate = $candidate
            validation_authority = $authority
            routing = $routing
            runtime = $runtime
        }
        $provable = [bool]($candidate.head_matches_checkout -and $candidate.worktree_clean)
        $reason = if (-not $candidate.head_matches_checkout) {
            "candidate-head-does-not-match-checkout"
        }
        elseif (-not $candidate.worktree_clean) {
            "candidate-worktree-not-clean"
        }
        else {
            "identity-complete"
        }
        return [ordered]@{
            schema_version = 1
            provable = $provable
            reason = $reason
            candidate = $candidate
            validation_authority = $authority
            routing = $routing
            runtime = $runtime
            binding_sha256 = ConvertTo-Sha256Hex -Value ($identity | ConvertTo-Json -Depth 12 -Compress)
        }
    }
    catch {
        return [ordered]@{
            schema_version = 1
            provable = $false
            reason = "identity-unavailable"
            candidate = $null
            validation_authority = $null
            routing = $null
            runtime = $null
            binding_sha256 = $null
        }
    }
}

function Get-ActionOutputEvidence {
    param([object]$Action, [string]$Status, [string[]]$OutputLines)
    $text = (@($OutputLines | ForEach-Object { [string]$_ }) -join "`n").Trim()
    $result = [ordered]@{
        schema_version = 1
        complete = $false
        sha256 = $(if ($text) { ConvertTo-Sha256Hex -Value $text } else { $null })
        reason = "action-not-successful"
    }
    if ($Status -cne "PASS") { return $result }
    if ([string]::IsNullOrWhiteSpace($text)) {
        $result.reason = "action-output-missing"
        return $result
    }
    try {
        $payload = $text | ConvertFrom-Json
        if ($null -eq $payload -or $payload -is [string] -or $payload -is [System.Array]) {
            throw "Action output must be one JSON object."
        }
        switch ([string]$Action.id) {
            "classifier-contracts" {
                if (-not (Test-RequiredProperty $payload "schema_version") -or -not (Test-RequiredProperty $payload "pass") -or
                    -not (Test-RequiredProperty $payload "fail") -or [int]$payload.schema_version -ne 1 -or
                    [int]$payload.pass -lt 1 -or [int]$payload.fail -ne 0) {
                    throw "Classifier contract evidence is incomplete."
                }
            }
            "affected-change-validation" {
                $missing = @(@("schema_version", "classification", "summary", "checks", "executed_suites", "executed_suite_count", "module_coverage") | Where-Object {
                    -not (Test-RequiredProperty $payload $_)
                })
                if ($missing.Count -gt 0 -or [int]$payload.schema_version -ne 2 -or $null -eq $payload.classification -or $null -eq $payload.summary -or
                    [int]$payload.summary.pass -lt 1 -or [int]$payload.summary.fail -ne 0 -or @($payload.checks).Count -lt 1 -or
                    @($payload.checks | Where-Object { [string]$_.status -cne "PASS" }).Count -gt 0 -or
                    [int]$payload.executed_suite_count -ne @($payload.executed_suites).Count -or $null -eq $payload.module_coverage) {
                    throw "Affected validation evidence is incomplete."
                }
            }
            "validation-self-protection" {
                $missing = @(@("schema_version", "status", "routing", "sensitive_scan") | Where-Object {
                    -not (Test-RequiredProperty $payload $_)
                })
                if ($missing.Count -gt 0 -or [int]$payload.schema_version -ne 2 -or [string]$payload.status -cne "PASS" -or
                    $null -eq $payload.routing -or $null -eq $payload.sensitive_scan) {
                    throw "Self-protection evidence is incomplete."
                }
            }
            default {
                throw "Unknown action evidence cannot be reused."
            }
        }
        $result.complete = $true
        $result.reason = "complete-success-evidence"
    }
    catch {
        $result.reason = "action-output-malformed-or-incomplete"
    }
    return $result
}

function Test-RequiredProperty {
    param([object]$InputObject, [string]$Name)
    return [bool]($null -ne $InputObject -and @($InputObject.PSObject.Properties | Where-Object { $_.Name -ceq $Name }).Count -eq 1)
}

function Get-PrePushReuseDecision {
    param([string]$EvidencePath, [string]$EvidenceSource, [object]$CurrentBinding, [object]$CurrentPlan)
    $decision = [ordered]@{
        disposition = "re-executed"
        reason = "iteration-evidence-missing"
        evidence_source = $EvidenceSource
        source_result = $null
    }
    if ([string]::IsNullOrWhiteSpace($EvidencePath) -or -not [System.IO.File]::Exists($EvidencePath)) { return $decision }
    try {
        $source = [System.IO.File]::ReadAllText($EvidencePath) | ConvertFrom-Json
    }
    catch {
        $decision.reason = "iteration-evidence-malformed"
        return $decision
    }
    if ($null -eq $source -or $source -is [string] -or $source -is [System.Array] -or
        -not (Test-RequiredProperty -InputObject $source -Name "schema_version") -or
        ($source.schema_version -isnot [int] -and $source.schema_version -isnot [long]) -or [int]$source.schema_version -ne 2 -or
        -not (Test-RequiredProperty -InputObject $source -Name "stage") -or [string]$source.stage -cne "iteration" -or
        -not (Test-RequiredProperty -InputObject $source -Name "dry_run") -or $source.dry_run -isnot [bool] -or [bool]$source.dry_run -or
        -not (Test-RequiredProperty -InputObject $source -Name "reuse_evidence")) {
        $decision.reason = "iteration-evidence-incomplete"
        return $decision
    }
    if (-not (Test-RequiredProperty -InputObject $source -Name "status") -or [string]$source.status -cne "PASS") {
        $decision.reason = "iteration-evidence-not-successful"
        return $decision
    }
    if (-not (Test-RequiredProperty $source.reuse_evidence "schema_version") -or
        ($source.reuse_evidence.schema_version -isnot [int] -and $source.reuse_evidence.schema_version -isnot [long]) -or
        [int]$source.reuse_evidence.schema_version -ne 1 -or
        -not (Test-RequiredProperty $source.reuse_evidence "proof_kind") -or
        [string]$source.reuse_evidence.proof_kind -cne "local-validation-stage" -or
        -not (Test-RequiredProperty $source.reuse_evidence "complete") -or $source.reuse_evidence.complete -isnot [bool] -or
        -not [bool]$source.reuse_evidence.complete -or -not (Test-RequiredProperty $source.reuse_evidence "binding") -or
        $null -eq $source.reuse_evidence.binding) {
        $decision.reason = "iteration-evidence-incomplete"
        return $decision
    }
    $previousBinding = $source.reuse_evidence.binding
    $bindingFields = @("schema_version", "provable", "candidate", "validation_authority", "routing", "runtime", "binding_sha256")
    if (@($bindingFields | Where-Object { -not (Test-RequiredProperty $previousBinding $_) }).Count -gt 0 -or
        ($previousBinding.schema_version -isnot [int] -and $previousBinding.schema_version -isnot [long]) -or
        [int]$previousBinding.schema_version -ne 1 -or
        $previousBinding.provable -isnot [bool] -or [string]$previousBinding.binding_sha256 -notmatch '^[0-9a-f]{64}$') {
        $decision.reason = "iteration-evidence-incomplete"
        return $decision
    }
    if ($null -eq $previousBinding.candidate -or $null -eq $CurrentBinding.candidate) {
        $decision.reason = "candidate-identity-unavailable"
        return $decision
    }
    $candidateFields = @("input_mode", "base_commit", "head_commit", "tree", "checkout_head_commit", "head_matches_checkout", "worktree_clean")
    if (@($candidateFields | Where-Object { -not (Test-RequiredProperty $previousBinding.candidate $_) }).Count -gt 0 -or
        $previousBinding.candidate.head_matches_checkout -isnot [bool] -or $previousBinding.candidate.worktree_clean -isnot [bool] -or
        $null -eq $previousBinding.validation_authority -or $null -eq $previousBinding.routing -or $null -eq $previousBinding.runtime -or
        [string]$previousBinding.validation_authority.sha256 -notmatch '^[0-9a-f]{64}$' -or
        [string]$previousBinding.routing.sha256 -notmatch '^[0-9a-f]{64}$' -or [string]$previousBinding.runtime.sha256 -notmatch '^[0-9a-f]{64}$') {
        $decision.reason = "iteration-evidence-incomplete"
        return $decision
    }
    if ([string]$previousBinding.candidate.input_mode -cne [string]$CurrentBinding.candidate.input_mode -or
        [string]$previousBinding.candidate.base_commit -cne [string]$CurrentBinding.candidate.base_commit -or
        [string]$previousBinding.candidate.head_commit -cne [string]$CurrentBinding.candidate.head_commit -or
        [string]$previousBinding.candidate.checkout_head_commit -cne [string]$CurrentBinding.candidate.checkout_head_commit) {
        $decision.reason = "candidate-commit-identity-changed"
        return $decision
    }
    if ([string]$previousBinding.candidate.tree -cne [string]$CurrentBinding.candidate.tree) {
        $decision.reason = "candidate-tree-changed"
        return $decision
    }
    if ([string]$previousBinding.validation_authority.sha256 -cne [string]$CurrentBinding.validation_authority.sha256) {
        $decision.reason = "validation-authority-changed"
        return $decision
    }
    if ([string]$previousBinding.routing.sha256 -cne [string]$CurrentBinding.routing.sha256) {
        $decision.reason = "validation-routing-changed"
        return $decision
    }
    if ([string]$previousBinding.runtime.sha256 -cne [string]$CurrentBinding.runtime.sha256) {
        $decision.reason = "host-runtime-identity-changed"
        return $decision
    }
    if ([string]$previousBinding.binding_sha256 -cne [string]$CurrentBinding.binding_sha256) {
        $decision.reason = "identity-binding-changed"
        return $decision
    }
    if (-not [bool]$CurrentBinding.provable -or -not [bool]$previousBinding.provable) {
        $decision.reason = if ([string]::IsNullOrWhiteSpace([string]$CurrentBinding.reason)) { "identity-not-provable" } else { [string]$CurrentBinding.reason }
        return $decision
    }
    $currentActions = @($CurrentPlan.actions)
    $previousActions = @($source.actions)
    if ($previousActions.Count -ne $currentActions.Count) {
        $decision.reason = "iteration-evidence-incomplete"
        return $decision
    }
    foreach ($action in $currentActions) {
        $matches = @($previousActions | Where-Object { [string]$_.id -ceq [string]$action.id })
        if ($matches.Count -ne 1) {
            $decision.reason = "iteration-evidence-incomplete"
            return $decision
        }
        $previousAction = $matches[0]
        $actionFields = @("id", "status", "exit_code", "disposition", "evidence")
        if (@($actionFields | Where-Object { -not (Test-RequiredProperty $previousAction $_) }).Count -gt 0) {
            $decision.reason = "iteration-evidence-incomplete"
            return $decision
        }
        if ([string]$previousAction.status -cne "PASS" -or [string]$previousAction.disposition -cne "executed" -or
            ($previousAction.exit_code -isnot [int] -and $previousAction.exit_code -isnot [long]) -or [int]$previousAction.exit_code -ne 0) {
            $decision.reason = "iteration-evidence-not-successful"
            return $decision
        }
        if ($null -eq $previousAction.evidence -or -not (Test-RequiredProperty $previousAction.evidence "complete") -or
            $previousAction.evidence.complete -isnot [bool] -or -not [bool]$previousAction.evidence.complete -or
            -not (Test-RequiredProperty $previousAction.evidence "schema_version") -or
            ($previousAction.evidence.schema_version -isnot [int] -and $previousAction.evidence.schema_version -isnot [long]) -or
            [int]$previousAction.evidence.schema_version -ne 1 -or
            -not (Test-RequiredProperty $previousAction.evidence "sha256") -or [string]$previousAction.evidence.sha256 -notmatch '^[0-9a-f]{64}$' -or
            -not (Test-RequiredProperty $previousAction.evidence "reason") -or
            [string]$previousAction.evidence.reason -cne "complete-success-evidence") {
            $decision.reason = "iteration-evidence-incomplete"
            return $decision
        }
    }
    $decision.disposition = "reused"
    $decision.reason = "equivalent-successful-iteration-evidence"
    $decision.source_result = $source
    return $decision
}

function Get-ActionInvocation {
    param([object]$Action, [int]$Index)
    $scriptPath = Join-Path $repoRoot ([string]$Action.script).Replace('/', [IO.Path]::DirectorySeparatorChar)
    $scriptArguments = @($Action.arguments)
    if ([string]$Action.script -eq "scripts/validate-targeted-change.ps1") {
        if ($script:inputParameterSet -eq "Paths") {
            $scriptArguments += "-ChangedPath"
            # -File cannot bind multiple command-line arguments to one array parameter reliably.
            $scriptArguments += (@($ChangedPath) -join ',')
        }
        else {
            $scriptArguments += @("-BaseRef", $BaseRef, "-HeadRef", $HeadRef)
        }
    }
    if ([string]$Action.script -eq "scripts/validate-release.ps1") {
        $scriptArguments += @("-ScratchRoot", (Join-Path $scratchRootFull ("{0:D2}-{1}" -f $Index, [string]$Action.id)))
    }
    $scriptArguments += "-Json"

    $hostExecutable = Get-HostExecutable -HostName ([string]$Action.host)
    $hostArguments = @("-NoProfile", "-NonInteractive")
    $hostArguments += @("-File", $scriptPath)
    $hostArguments += $scriptArguments
    $displayExecutable = if ([string]::IsNullOrWhiteSpace($hostExecutable)) { "<unavailable:$($Action.host)>" } else { $hostExecutable }
    $commandLine = ((@($displayExecutable) + $hostArguments | ForEach-Object { Format-CommandArgument -Value ([string]$_) }) -join ' ')
    return [ordered]@{
        executable = $hostExecutable
        arguments = @($hostArguments)
        command_line = $commandLine
    }
}

function Write-ActionCheckpoint {
    param(
        [string]$Status,
        [DateTimeOffset]$StageStartedAt,
        [System.Diagnostics.Stopwatch]$StageStopwatch,
        [object[]]$Results,
        [object[]]$Skipped,
        [object]$Classification,
        [object]$ReuseEvidence,
        [object]$ReuseDecision
    )
    if ($DryRun.IsPresent) { return }
    $checkpoint = [ordered]@{
        schema_version = 2
        stage = $Stage
        status = $Status
        dry_run = $false
        updated_at_utc = [DateTimeOffset]::UtcNow.ToString("o")
        duration_ms = [long]$StageStopwatch.ElapsedMilliseconds
        stage_started_at_utc = $StageStartedAt.ToString("o")
        classification = $Classification
        actions = @($Results)
        skipped = @($Skipped)
        reuse_evidence = $ReuseEvidence
        reuse_decision = $ReuseDecision
    }
    $checkpoint | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

if ($script:inputParameterSet -eq "Paths") {
    $classificationRaw = @(& (Join-Path $scriptDir "validate-change.ps1") -ChangedPath $ChangedPath -Json) -join "`n"
}
else {
    $classificationRaw = @(& (Join-Path $scriptDir "validate-change.ps1") -BaseRef $BaseRef -HeadRef $HeadRef -RepositoryRoot $repoRoot -Json) -join "`n"
}
$classification = $classificationRaw | ConvertFrom-Json
& (Join-Path $scriptDir "validation/release-classifier-output-contract.ps1") -Result $classification | Out-Null
& (Join-Path $scriptDir "validation/local-validation-plan-contract.ps1") -Result $classification | Out-Null
$stagePlan = $classification.local_plan.stages.$stageKey
if ($null -eq $stagePlan) { throw "Classifier local plan is missing stage '$stageKey'." }
if ($Stage -cne "pre-push" -and -not [string]::IsNullOrWhiteSpace($IterationEvidencePath)) {
    throw "IterationEvidencePath is only valid for the pre-push stage."
}

$initialBinding = Get-LocalValidationEvidenceBinding -Classification $classification
$evidencePathFull = ""
$evidenceSource = "none"
if ($Stage -ceq "pre-push") {
    if (-not [string]::IsNullOrWhiteSpace($IterationEvidencePath)) {
        $evidencePathFull = [System.IO.Path]::GetFullPath($IterationEvidencePath)
        $evidenceSource = "explicit"
    }
    elseif ([System.IO.File]::Exists($resultPath)) {
        # NOTE: 读取必须发生在 pre-push 首个 checkpoint 覆盖同一路径之前。
        $evidencePathFull = $resultPath
        $evidenceSource = "same-scratch-root"
    }
}
$rawReuseDecision = if ($DryRun.IsPresent) {
    [ordered]@{ disposition = $null; reason = "dry-run-does-not-consume-evidence"; evidence_source = $evidenceSource; source_result = $null }
}
elseif ($Stage -ceq "pre-push") {
    Get-PrePushReuseDecision -EvidencePath $evidencePathFull -EvidenceSource $evidenceSource -CurrentBinding $initialBinding -CurrentPlan $stagePlan
}
else {
    [ordered]@{
        disposition = "executed"
        reason = $(if ($Stage -ceq "iteration") { "iteration-stage-execution" } else { "release-stage-execution" })
        evidence_source = "not-applicable"
        source_result = $null
    }
}
$sourceIterationResult = $rawReuseDecision.source_result
$reuseDecision = [ordered]@{
    disposition = $rawReuseDecision.disposition
    reason = [string]$rawReuseDecision.reason
    evidence_source = [string]$rawReuseDecision.evidence_source
}
$runningReuseEvidence = [ordered]@{
    schema_version = 1
    proof_kind = "local-validation-stage"
    complete = $false
    reason = "stage-running"
    binding = $initialBinding
}
if (-not $DryRun.IsPresent) { New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null }

$startedAt = [DateTimeOffset]::UtcNow
$stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$actionResults = New-Object 'System.Collections.Generic.List[object]'
$failed = $false
$unavailable = $false
$actions = @($stagePlan.actions)
Write-ActionCheckpoint -Status "RUNNING" -StageStartedAt $startedAt -StageStopwatch $stageStopwatch -Results @() -Skipped @($stagePlan.skipped) -Classification $classification -ReuseEvidence $runningReuseEvidence -ReuseDecision $reuseDecision
for ($index = 0; $index -lt $actions.Count; $index++) {
    $action = $actions[$index]
    $invocation = Get-ActionInvocation -Action $action -Index ($index + 1)
    $actionStartedAt = [DateTimeOffset]::UtcNow
    $actionStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $status = "PLANNED"
    $exitCode = $null
    $outputLines = @()
    $disposition = $null
    $dispositionReason = if ($DryRun.IsPresent) { "dry-run-only" } else { [string]$reuseDecision.reason }
    $actionEvidence = $null
    if (-not $DryRun.IsPresent -and [string]$reuseDecision.disposition -ceq "reused") {
        $sourceAction = @($sourceIterationResult.actions | Where-Object { [string]$_.id -ceq [string]$action.id })[0]
        $status = "PASS"
        $disposition = "reused"
        $actionEvidence = $sourceAction.evidence
    }
    elseif ($DryRun.IsPresent -and [string]::IsNullOrWhiteSpace([string]$invocation.executable)) {
        $status = "UNAVAILABLE"
        $exitCode = 127
        $outputLines = @("Required host '$($action.host)' is unavailable.")
        $unavailable = $true
    }
    elseif (-not $DryRun.IsPresent) {
        if ([string]::IsNullOrWhiteSpace([string]$invocation.executable)) {
            $status = "FAIL"
            $exitCode = 127
            $outputLines = @("Required host '$($action.host)' is unavailable.")
        }
        else {
            $outputLines = @(& $invocation.executable @($invocation.arguments) 2>&1 | ForEach-Object { [string]$_ })
            $exitCode = [int]$LASTEXITCODE
            $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
        }
        $disposition = if ($Stage -ceq "pre-push") { "re-executed" } else { "executed" }
    }
    if ($null -eq $actionEvidence) { $actionEvidence = Get-ActionOutputEvidence -Action $action -Status $status -OutputLines $outputLines }
    $actionStopwatch.Stop()
    $actionCompletedAt = [DateTimeOffset]::UtcNow
    $actionResults.Add([ordered]@{
        id = [string]$action.id
        host = [string]$action.host
        suite = [string]$action.suite
        reason = [string]$action.reason
        command_line = [string]$invocation.command_line
        status = $status
        exit_code = $exitCode
        disposition = $disposition
        disposition_reason = $dispositionReason
        started_at_utc = $actionStartedAt.ToString("o")
        completed_at_utc = $actionCompletedAt.ToString("o")
        duration_ms = [long]$actionStopwatch.ElapsedMilliseconds
        output_line_count = @($outputLines).Count
        failure_output = $(if ($status -in @("FAIL", "UNAVAILABLE")) { @($outputLines | Select-Object -Last 20) } else { @() })
        evidence = $actionEvidence
    })
    Write-ActionCheckpoint -Status $(if ($status -eq "FAIL") { "FAIL" } else { "RUNNING" }) -StageStartedAt $startedAt -StageStopwatch $stageStopwatch -Results @($actionResults.ToArray()) -Skipped @($stagePlan.skipped) -Classification $classification -ReuseEvidence $runningReuseEvidence -ReuseDecision $reuseDecision
    if ($status -eq "FAIL") {
        $failed = $true
        for ($remaining = $index + 1; $remaining -lt $actions.Count; $remaining++) {
            $remainingAction = $actions[$remaining]
            $remainingInvocation = Get-ActionInvocation -Action $remainingAction -Index ($remaining + 1)
            $actionResults.Add([ordered]@{
                id = [string]$remainingAction.id
                host = [string]$remainingAction.host
                suite = [string]$remainingAction.suite
                reason = [string]$remainingAction.reason
                command_line = [string]$remainingInvocation.command_line
                status = "SKIPPED"
                exit_code = $null
                disposition = $null
                disposition_reason = "not-run-after-failure"
                started_at_utc = $null
                completed_at_utc = $null
                duration_ms = 0L
                output_line_count = 0
                failure_output = @()
                evidence = [ordered]@{ schema_version = 1; complete = $false; sha256 = $null; reason = "action-not-executed" }
            })
        }
        Write-ActionCheckpoint -Status "FAIL" -StageStartedAt $startedAt -StageStopwatch $stageStopwatch -Results @($actionResults.ToArray()) -Skipped @($stagePlan.skipped) -Classification $classification -ReuseEvidence $runningReuseEvidence -ReuseDecision $reuseDecision
        break
    }
}
$stageStopwatch.Stop()
$completedAt = [DateTimeOffset]::UtcNow
$stageStatus = if ($failed -or $unavailable) { "FAIL" } else { "PASS" }
$finalBinding = Get-LocalValidationEvidenceBinding -Classification $classification
$bindingStable = (
    -not [string]::IsNullOrWhiteSpace([string]$initialBinding.binding_sha256) -and
    [string]$initialBinding.binding_sha256 -ceq [string]$finalBinding.binding_sha256
)
$iterationActionsComplete = @($actionResults | Where-Object {
    [string]$_.status -cne "PASS" -or [string]$_.disposition -cne "executed" -or -not [bool]$_.evidence.complete
}).Count -eq 0
$reuseEvidenceComplete = [bool](
    $Stage -ceq "iteration" -and -not $DryRun.IsPresent -and $stageStatus -ceq "PASS" -and
    [bool]$initialBinding.provable -and [bool]$finalBinding.provable -and $bindingStable -and $iterationActionsComplete
)
$reuseEvidenceReason = if ($Stage -cne "iteration") {
    "stage-is-not-iteration"
}
elseif ($DryRun.IsPresent) {
    "dry-run-is-not-execution-evidence"
}
elseif ($stageStatus -cne "PASS") {
    "iteration-stage-not-successful"
}
elseif (-not [bool]$finalBinding.provable) {
    [string]$finalBinding.reason
}
elseif (-not $bindingStable) {
    "identity-changed-during-iteration"
}
elseif (-not $iterationActionsComplete) {
    "iteration-actions-incomplete"
}
else {
    "complete-successful-iteration-evidence"
}
$reuseEvidence = [ordered]@{
    schema_version = 1
    proof_kind = "local-validation-stage"
    complete = $reuseEvidenceComplete
    reason = $reuseEvidenceReason
    binding = $finalBinding
}
$result = [ordered]@{
    schema_version = 2
    stage = $Stage
    status = $stageStatus
    dry_run = [bool]$DryRun.IsPresent
    result_path = $(if ($DryRun.IsPresent) { $null } else { $resultPath })
    classification = $classification
    actions = @($actionResults.ToArray())
    skipped = @($stagePlan.skipped)
    reuse_evidence = $reuseEvidence
    reuse_decision = $reuseDecision
    timing = [ordered]@{
        started_at_utc = $startedAt.ToString("o")
        completed_at_utc = $completedAt.ToString("o")
        duration_ms = [long]$stageStopwatch.ElapsedMilliseconds
    }
    summary = [ordered]@{
        planned = @($actionResults | Where-Object status -eq "PLANNED").Count
        pass = @($actionResults | Where-Object status -eq "PASS").Count
        fail = @($actionResults | Where-Object status -in @("FAIL", "UNAVAILABLE")).Count
        skipped = @($stagePlan.skipped).Count + @($actionResults | Where-Object status -eq "SKIPPED").Count
        executed = @($actionResults | Where-Object disposition -eq "executed").Count
        reused = @($actionResults | Where-Object disposition -eq "reused").Count
        re_executed = @($actionResults | Where-Object disposition -eq "re-executed").Count
    }
}
if (-not $DryRun.IsPresent) {
    $result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 14
}
else {
    Write-Output ("Local validation stage: {0} (Tier {1})" -f $Stage, $classification.detected_tier)
    foreach ($action in $result.actions) {
        $displayDisposition = if ([string]::IsNullOrWhiteSpace([string]$action.disposition)) { "planned" } else { [string]$action.disposition }
        Write-Output ("[{0}] {1} | disposition={2} | reason={3} | host={4} | suite={5} | {6}" -f $action.status, $action.id, $displayDisposition, $action.disposition_reason, $action.host, $action.suite, $action.command_line)
    }
    foreach ($skip in $result.skipped) {
        Write-Output ("[SKIPPED] {0} | {1}" -f $skip.id, $skip.reason)
    }
    $displayDecision = if ([string]::IsNullOrWhiteSpace([string]$result.reuse_decision.disposition)) { "planned" } else { [string]$result.reuse_decision.disposition }
    Write-Output ("Reuse decision: disposition={0} | reason={1}" -f $displayDecision, $result.reuse_decision.reason)
    Write-Output ("Stage duration: {0} ms" -f $result.timing.duration_ms)
    if (-not $DryRun.IsPresent) { Write-Output ("Result: {0}" -f $resultPath) }
}

if ($failed -or $unavailable) { throw "Local validation stage '$Stage' failed." }
