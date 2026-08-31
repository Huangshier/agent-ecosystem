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

function Test-RequiredProperty {
    param([object]$InputObject, [string]$Name)
    return [bool]($null -ne $InputObject -and $null -ne $InputObject.PSObject.Properties[$Name])
}

function Get-LocalValidationReuseBinding {
    param([object]$Classification)
    try {
        $checkoutHead = ([string](@(Invoke-LocalGit rev-parse --verify "HEAD^{commit}")[0])).Trim().ToLowerInvariant()
        $headCommit = if ($script:inputParameterSet -eq "Paths") { $checkoutHead } else { ([string]$Classification.head_ref).Trim().ToLowerInvariant() }
        $baseCommit = if ($script:inputParameterSet -eq "Paths") { $null } else { ([string]$Classification.base_ref).Trim().ToLowerInvariant() }
        if ($headCommit -notmatch '^[0-9a-f]{40,64}$' -or ($null -ne $baseCommit -and $baseCommit -notmatch '^[0-9a-f]{40,64}$')) {
            throw "Candidate commit identity is unavailable."
        }
        $tree = ([string](@(Invoke-LocalGit rev-parse --verify "$headCommit^{tree}")[0])).Trim().ToLowerInvariant()
        if ($tree -notmatch '^[0-9a-f]{40,64}$') { throw "Candidate tree identity is unavailable." }
        $candidate = [ordered]@{
            mode = $script:inputParameterSet
            base = $baseCommit
            head = $headCommit
            tree = $tree
            checkout_head = $checkoutHead
            clean = [bool](@(Invoke-LocalGit status --porcelain=v1 --untracked-files=all).Count -eq 0)
        }

        $plannedActions = @($Classification.local_plan.stages.iteration.actions) + @($Classification.local_plan.stages.pre_push.actions)
        $authorityPaths = @(
            "scripts/invoke-local-validation.ps1"
            "scripts/validate-change.ps1"
            "scripts/validation/change-risk-rules.json"
            "scripts/validation/release-classifier-output-contract.ps1"
            "scripts/validation/local-validation-plan-contract.ps1"
            "scripts/validation/powershell-runtime-requirement.ps1"
            $plannedActions | ForEach-Object { [string]$_.script }
        ) | Sort-Object -Unique
        $authorityParts = @(
            foreach ($relativePath in $authorityPaths) {
                $fullPath = Join-Path $repoRoot $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
                if (-not [System.IO.File]::Exists($fullPath)) { throw "Validation authority file is missing: $relativePath" }
                "{0}={1}" -f $relativePath, (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        )

        $hostParts = @(
            foreach ($hostName in @($plannedActions | ForEach-Object { [string]$_.host } | Sort-Object -Unique)) {
                $executable = Get-HostExecutable -HostName $hostName
                if ([string]::IsNullOrWhiteSpace($executable) -or -not [System.IO.File]::Exists($executable)) {
                    throw "Required validation host '$hostName' is unavailable."
                }
                "{0}={1}" -f $hostName, (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        )
        $runtimeParts = @(
            [Environment]::MachineName
            [Runtime.InteropServices.RuntimeInformation]::OSDescription
            [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
            [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
            [string]$PSVersionTable.PSEdition
            $PSVersionTable.PSVersion.ToString()
        ) + $hostParts
        $binding = [ordered]@{
            schema_version = 1
            candidate = $candidate
            routing_sha256 = ConvertTo-Sha256Hex -Value ($Classification | ConvertTo-Json -Depth 14 -Compress)
            authority_sha256 = ConvertTo-Sha256Hex -Value ($authorityParts -join [Environment]::NewLine)
            runtime_sha256 = ConvertTo-Sha256Hex -Value ($runtimeParts -join [Environment]::NewLine)
        }
        $binding["key"] = ConvertTo-Sha256Hex -Value ($binding | ConvertTo-Json -Depth 5 -Compress)
        return $binding
    }
    catch {
        return $null
    }
}

function Get-UnusableBindingReason {
    param([object]$Binding)
    if ($null -eq $Binding -or $null -eq $Binding.candidate -or [string]$Binding.key -notmatch '^[0-9a-f]{64}$') {
        return "candidate-identity-unavailable"
    }
    if ([string]$Binding.candidate.head -cne [string]$Binding.candidate.checkout_head) {
        return "candidate-head-does-not-match-checkout"
    }
    if ($Binding.candidate.clean -isnot [bool] -or -not [bool]$Binding.candidate.clean) {
        return "candidate-worktree-not-clean"
    }
    return $null
}

function New-ReuseDecision {
    param([string]$Disposition, [string]$Reason, [string]$EvidenceSource)
    return [ordered]@{
        disposition = $Disposition
        reason = $Reason
        evidence_source = $EvidenceSource
    }
}

function Get-PrePushReuseDecision {
    param([string]$EvidencePath, [string]$EvidenceSource, [object]$CurrentBinding, [object]$CurrentPlan)
    $currentBindingReason = Get-UnusableBindingReason -Binding $CurrentBinding
    if (-not [string]::IsNullOrWhiteSpace($currentBindingReason)) {
        return New-ReuseDecision "re-executed" $currentBindingReason $EvidenceSource
    }
    if ([string]::IsNullOrWhiteSpace($EvidencePath) -or -not [System.IO.File]::Exists($EvidencePath)) {
        return New-ReuseDecision "re-executed" "iteration-evidence-missing" $EvidenceSource
    }
    try {
        $source = [System.IO.File]::ReadAllText($EvidencePath) | ConvertFrom-Json
    }
    catch {
        return New-ReuseDecision "re-executed" "iteration-evidence-malformed" $EvidenceSource
    }
    if ($null -eq $source -or $source -is [string] -or $source -is [System.Array] -or
        [string]$source.schema_version -cne "2" -or [string]$source.stage -cne "iteration" -or
        -not (Test-RequiredProperty $source "dry_run") -or $source.dry_run -isnot [bool] -or [bool]$source.dry_run -or
        -not (Test-RequiredProperty $source "reuse_evidence")) {
        return New-ReuseDecision "re-executed" "iteration-evidence-incomplete" $EvidenceSource
    }
    if (-not (Test-RequiredProperty $source "status") -or [string]$source.status -cne "PASS") {
        return New-ReuseDecision "re-executed" "iteration-evidence-not-successful" $EvidenceSource
    }
    $evidence = $source.reuse_evidence
    if ($null -eq $evidence -or -not (Test-RequiredProperty $evidence "complete") -or
        $evidence.complete -isnot [bool] -or -not [bool]$evidence.complete -or
        -not (Test-RequiredProperty $evidence "binding") -or $null -eq $evidence.binding) {
        return New-ReuseDecision "re-executed" "iteration-evidence-incomplete" $EvidenceSource
    }
    $previous = $evidence.binding
    $requiredBindingFields = @("schema_version", "candidate", "routing_sha256", "authority_sha256", "runtime_sha256", "key")
    $requiredCandidateFields = @("mode", "base", "head", "tree", "checkout_head", "clean")
    if (@($requiredBindingFields | Where-Object { -not (Test-RequiredProperty $previous $_) }).Count -gt 0 -or
        [string]$previous.schema_version -cne "1" -or $null -eq $previous.candidate -or
        @($requiredCandidateFields | Where-Object { -not (Test-RequiredProperty $previous.candidate $_) }).Count -gt 0 -or
        $previous.candidate.clean -isnot [bool] -or -not [bool]$previous.candidate.clean -or
        [string]$previous.key -notmatch '^[0-9a-f]{64}$') {
        return New-ReuseDecision "re-executed" "iteration-evidence-incomplete" $EvidenceSource
    }
    if ([string]$previous.candidate.mode -cne [string]$CurrentBinding.candidate.mode -or
        [string]$previous.candidate.base -cne [string]$CurrentBinding.candidate.base -or
        [string]$previous.candidate.head -cne [string]$CurrentBinding.candidate.head -or
        [string]$previous.candidate.checkout_head -cne [string]$CurrentBinding.candidate.checkout_head) {
        return New-ReuseDecision "re-executed" "candidate-commit-identity-changed" $EvidenceSource
    }
    if ([string]$previous.candidate.tree -cne [string]$CurrentBinding.candidate.tree) {
        return New-ReuseDecision "re-executed" "candidate-tree-changed" $EvidenceSource
    }
    $bindingComparisons = [ordered]@{
        authority_sha256 = "validation-authority-changed"
        routing_sha256 = "validation-routing-changed"
        runtime_sha256 = "host-runtime-identity-changed"
    }
    foreach ($comparison in $bindingComparisons.GetEnumerator()) {
        if ([string]$previous.($comparison.Key) -cne [string]$CurrentBinding.($comparison.Key)) {
            return New-ReuseDecision "re-executed" $comparison.Value $EvidenceSource
        }
    }
    if ([string]$previous.key -cne [string]$CurrentBinding.key) {
        return New-ReuseDecision "re-executed" "reuse-binding-changed" $EvidenceSource
    }

    $currentActions = @($CurrentPlan.actions)
    $previousActions = @($source.actions)
    if ($previousActions.Count -ne $currentActions.Count) {
        return New-ReuseDecision "re-executed" "iteration-evidence-incomplete" $EvidenceSource
    }
    for ($index = 0; $index -lt $currentActions.Count; $index++) {
        $previousAction = $previousActions[$index]
        if (@("id", "status", "exit_code", "disposition" | Where-Object { -not (Test-RequiredProperty $previousAction $_) }).Count -gt 0 -or
            [string]$previousAction.id -cne [string]$currentActions[$index].id -or
            [string]$previousAction.disposition -cne "executed" -or
            ($previousAction.exit_code -isnot [int] -and $previousAction.exit_code -isnot [long])) {
            return New-ReuseDecision "re-executed" "iteration-evidence-incomplete" $EvidenceSource
        }
        if ([string]$previousAction.status -cne "PASS" -or [int]$previousAction.exit_code -ne 0) {
            return New-ReuseDecision "re-executed" "iteration-evidence-not-successful" $EvidenceSource
        }
    }
    return New-ReuseDecision "reused" "equivalent-successful-iteration-evidence" $EvidenceSource
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
    param([string]$Status, [DateTimeOffset]$StageStartedAt, [System.Diagnostics.Stopwatch]$StageStopwatch, [object[]]$Results, [object[]]$Skipped, [object]$ReuseEvidence, [object]$ReuseDecision)
    if ($DryRun.IsPresent) { return }
    $checkpoint = [ordered]@{
        schema_version = 2
        stage = $Stage
        status = $Status
        updated_at_utc = [DateTimeOffset]::UtcNow.ToString("o")
        duration_ms = [long]$StageStopwatch.ElapsedMilliseconds
        stage_started_at_utc = $StageStartedAt.ToString("o")
        actions = @($Results)
        skipped = @($Skipped)
        reuse_evidence = $ReuseEvidence
        reuse_decision = $ReuseDecision
    }
    $checkpoint | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

if ($script:inputParameterSet -eq "Paths") {
    $classificationRaw = @(& (Join-Path $scriptDir "validate-change.ps1") -ChangedPath $ChangedPath -Json) -join [Environment]::NewLine
}
else {
    $classificationRaw = @(& (Join-Path $scriptDir "validate-change.ps1") -BaseRef $BaseRef -HeadRef $HeadRef -RepositoryRoot $repoRoot -Json) -join [Environment]::NewLine
}
$classification = $classificationRaw | ConvertFrom-Json
& (Join-Path $scriptDir "validation/release-classifier-output-contract.ps1") -Result $classification | Out-Null
& (Join-Path $scriptDir "validation/local-validation-plan-contract.ps1") -Result $classification | Out-Null
$stagePlan = $classification.local_plan.stages.$stageKey
if ($null -eq $stagePlan) { throw "Classifier local plan is missing stage '$stageKey'." }
if ($Stage -cne "pre-push" -and -not [string]::IsNullOrWhiteSpace($IterationEvidencePath)) {
    throw "IterationEvidencePath is only valid for the pre-push stage."
}

$initialBinding = if (-not $DryRun.IsPresent -and $Stage -in @("iteration", "pre-push")) {
    Get-LocalValidationReuseBinding -Classification $classification
}
else {
    $null
}
$evidencePathFull = ""
$evidenceSource = "none"
if ($Stage -ceq "pre-push") {
    if (-not [string]::IsNullOrWhiteSpace($IterationEvidencePath)) {
        $evidencePathFull = [System.IO.Path]::GetFullPath($IterationEvidencePath)
        $evidenceSource = "explicit"
    }
    elseif ([System.IO.File]::Exists($resultPath)) {
        # NOTE: 在 pre-push checkpoint 覆盖同一路径前读取 iteration evidence。
        $evidencePathFull = $resultPath
        $evidenceSource = "same-scratch-root"
    }
}
$reuseDecision = if ($DryRun.IsPresent) {
    [ordered]@{ disposition = $null; reason = "dry-run-does-not-consume-evidence"; evidence_source = $evidenceSource }
}
elseif ($Stage -ceq "pre-push") {
    Get-PrePushReuseDecision -EvidencePath $evidencePathFull -EvidenceSource $evidenceSource -CurrentBinding $initialBinding -CurrentPlan $stagePlan
}
else {
    [ordered]@{
        disposition = "executed"
        reason = $(if ($Stage -ceq "iteration") { "iteration-stage-execution" } else { "release-stage-execution" })
        evidence_source = "not-applicable"
    }
}
if (-not $DryRun.IsPresent) { New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null }

$startedAt = [DateTimeOffset]::UtcNow
$stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$actionResults = New-Object 'System.Collections.Generic.List[object]'
$failed = $false
$unavailable = $false
$actions = @($stagePlan.actions)
Write-ActionCheckpoint -Status "RUNNING" -StageStartedAt $startedAt -StageStopwatch $stageStopwatch -Results @() -Skipped @($stagePlan.skipped) -ReuseEvidence $null -ReuseDecision $reuseDecision
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
    if (-not $DryRun.IsPresent -and [string]$reuseDecision.disposition -ceq "reused") {
        $status = "PASS"
        $disposition = "reused"
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
    })
    Write-ActionCheckpoint -Status $(if ($status -eq "FAIL") { "FAIL" } else { "RUNNING" }) -StageStartedAt $startedAt -StageStopwatch $stageStopwatch -Results @($actionResults.ToArray()) -Skipped @($stagePlan.skipped) -ReuseEvidence $null -ReuseDecision $reuseDecision
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
            })
        }
        Write-ActionCheckpoint -Status "FAIL" -StageStartedAt $startedAt -StageStopwatch $stageStopwatch -Results @($actionResults.ToArray()) -Skipped @($stagePlan.skipped) -ReuseEvidence $null -ReuseDecision $reuseDecision
        break
    }
}
$stageStopwatch.Stop()
$completedAt = [DateTimeOffset]::UtcNow
$stageStatus = if ($failed -or $unavailable) { "FAIL" } else { "PASS" }
$finalBinding = if (-not $DryRun.IsPresent -and $Stage -in @("iteration", "pre-push")) {
    Get-LocalValidationReuseBinding -Classification $classification
}
else {
    $null
}
$initialBindingReason = Get-UnusableBindingReason -Binding $initialBinding
$finalBindingReason = Get-UnusableBindingReason -Binding $finalBinding
$bindingStable = [bool](
    [string]::IsNullOrWhiteSpace($initialBindingReason) -and
    [string]::IsNullOrWhiteSpace($finalBindingReason) -and
    [string]$initialBinding.key -ceq [string]$finalBinding.key
)
$iterationActionsComplete = [bool](
    $actionResults.Count -eq $actions.Count -and
    @($actionResults | Where-Object {
        [string]$_.status -cne "PASS" -or [string]$_.disposition -cne "executed" -or
        ($_.exit_code -isnot [int] -and $_.exit_code -isnot [long]) -or [int]$_.exit_code -ne 0
    }).Count -eq 0
)
$reuseEvidenceComplete = [bool](
    $Stage -ceq "iteration" -and -not $DryRun.IsPresent -and $stageStatus -ceq "PASS" -and
    $bindingStable -and $iterationActionsComplete
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
elseif (-not [string]::IsNullOrWhiteSpace($initialBindingReason)) {
    $initialBindingReason
}
elseif (-not [string]::IsNullOrWhiteSpace($finalBindingReason)) {
    $finalBindingReason
}
elseif (-not $bindingStable) {
    "reuse-binding-changed-during-iteration"
}
elseif (-not $iterationActionsComplete) {
    "iteration-actions-incomplete"
}
else {
    "complete-successful-iteration-evidence"
}
$reuseEvidence = [ordered]@{
    schema_version = 1
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
