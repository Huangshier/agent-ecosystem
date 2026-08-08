[CmdletBinding()]
param(
    [string]$BaseRef = "HEAD~1",
    [string]$HeadRef = "HEAD",
    [string[]]$ChangedPath = @(),
    [ValidateSet("quick", "targeted")]
    [string]$Mode = "quick",
    [ValidateSet("current", "windows-latest", "ubuntu-latest", "macos-latest")]
    [string]$ExecutionHost = "current",
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir "validation/powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime
$repoRoot = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir "validation/release-test-helper.ps1")
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-change-validation-{0}" -f ([Guid]::NewGuid().ToString("N")))
}
$ScratchRoot = [System.IO.Path]::GetFullPath($ScratchRoot)
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

$classification = if (@($ChangedPath).Count -gt 0) {
    (& (Join-Path $scriptDir "validate-change.ps1") -ChangedPath $ChangedPath -Json | Out-String) | ConvertFrom-Json
} else {
    (& (Join-Path $scriptDir "validate-change.ps1") -BaseRef $BaseRef -HeadRef $HeadRef -Json | Out-String) | ConvertFrom-Json
}
& (Join-Path $scriptDir "validation/release-classifier-output-contract.ps1") -Result $classification | Out-Null

$checks = New-Object 'System.Collections.Generic.List[object]'
$telemetry = New-Object 'System.Collections.Generic.List[object]'
$script:targetedCheckStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:targetedCheckCheckpointMs = 0L
$script:targetedCheckCheckpointUtc = [DateTimeOffset]::UtcNow
$hostIdentity = "{0}-{1}-{2}" -f [System.Environment]::OSVersion.Platform, $PSVersionTable.PSEdition, $PSVersionTable.PSVersion.ToString()

function Get-CoverageCategory([string]$Name) {
    switch ($Name) {
        "diff-check" { return "repository-diff-integrity" }
        "changed-file-parse" { return "changed-file-syntax-public-safety" }
        "quick-repository-checks" { return "repository-syntax" }
        default { return ("targeted-suite:{0}" -f $Name) }
    }
}

function Add-Result([string]$Name, [string]$Status, [string]$Detail) {
    $completedAt = [DateTimeOffset]::UtcNow
    $elapsedMs = [long]$script:targetedCheckStopwatch.ElapsedMilliseconds
    $durationMs = [Math]::Max(0L, ($elapsedMs - [long]$script:targetedCheckCheckpointMs))
    $startedAt = $script:targetedCheckCheckpointUtc
    $script:targetedCheckCheckpointMs = $elapsedMs
    $script:targetedCheckCheckpointUtc = $completedAt
    $coverageCategory = Get-CoverageCategory -Name $Name
    $checks.Add([ordered]@{ name = $Name; status = $Status; detail = $Detail; duration_ms = [long]$durationMs })
    $telemetry.Add([ordered]@{
        suite = $Name
        case = ("{0}:{1}" -f $Mode, $Name)
        host = $hostIdentity
        started_at_utc = $startedAt.ToString("o")
        completed_at_utc = $completedAt.ToString("o")
        duration_ms = [long]$durationMs
        unique_coverage_category = $coverageCategory
    })
}

if (@($ChangedPath).Count -gt 0) { & git -C $repoRoot diff --check } else { & git -C $repoRoot diff --check "$BaseRef...$HeadRef" }
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }
Add-Result "diff-check" "PASS" "No whitespace errors in the selected diff."

foreach ($path in @($classification.changed_paths)) {
    $fullPath = Join-Path $repoRoot ([string]$path).Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
    $extension = [IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    if ($extension -eq ".ps1" -or $extension -eq ".psm1") {
        $astLexemes = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$astLexemes, [ref]$errors)
        if (@($errors).Count -gt 0) { throw "PowerShell parse failed for $path`: $($errors[0].Message)" }
    } elseif ($extension -eq ".json") {
        Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json | Out-Null
    }
    if ($extension -in @(".md", ".txt", ".json", ".yml", ".yaml", ".ps1", ".psm1", ".js")) {
        $text = Get-Content -LiteralPath $fullPath -Raw
        $privateOverlayToken = "agent-ecosystem" + "-private"
        $hiddenDirectory = ".sec" + "rets"
        $keyMarker = "PRIVATE" + " KEY"
        $unsafePattern = '(?i)(' + [regex]::Escape($privateOverlayToken) + '|[A-Z]:\\Projects\\|' + [regex]::Escape($hiddenDirectory) + '[/\\]|BEGIN (RSA |EC |OPENSSH )?' + $keyMarker + ')'
        if ($text -match $unsafePattern) {
            throw "Public-safe scan rejected $path."
        }
    }
}
Add-Result "changed-file-parse" "PASS" "Changed PowerShell files parse; JSON files parse; public-safe text scan passed."

if ([int]$classification.detected_tier -ge 1) {
    foreach ($scriptPath in @(Get-ChildItem -LiteralPath $scriptDir -Recurse -File | Where-Object { $_.Extension -in @(".ps1", ".psm1") })) {
        $astLexemes = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($scriptPath.FullName, [ref]$astLexemes, [ref]$parseErrors)
        if (@($parseErrors).Count -gt 0) { throw "Quick repository PowerShell parse failed for $($scriptPath.FullName): $($parseErrors[0].Message)" }
    }
    $knowledgeRoot = Join-Path $repoRoot "knowledge-hub/knowledge"
    foreach ($jsonPath in @(Get-ChildItem -LiteralPath $knowledgeRoot -Recurse -File -Filter *.json)) {
        Get-Content -LiteralPath $jsonPath.FullName -Raw | ConvertFrom-Json | Out-Null
    }
    Add-Result "quick-repository-checks" "PASS" "Repository PowerShell and knowledge JSON parse checks passed."
}

if ([int]$classification.detected_tier -ge 1) {
    $modules = @($classification.affected_modules)
    $allRequiredSuites = @($classification.required_suites)
    $requiredSuites = if ($ExecutionHost -ceq "current") {
        @($allRequiredSuites)
    }
    else {
        @($allRequiredSuites | Where-Object {
            $hostProperty = $classification.suite_host_map.PSObject.Properties[[string]$_]
            $null -ne $hostProperty -and @($hostProperty.Value) -ccontains $ExecutionHost
        })
    }
    $baseCheckModules = @($classification.base_check_modules)
    $executedSuites = New-Object 'System.Collections.Generic.List[string]'
    if ($requiredSuites.Count -eq 0 -and -not [bool]$classification.run_validation_self_protection -and @($baseCheckModules).Count -eq 0) {
        throw "Affected validation produced no suite, base check, or independent self-protection oracle."
    }
    if ($requiredSuites -contains "knowledge-contracts") {
        . (Join-Path $scriptDir "lib/path-guard.ps1")
        . (Join-Path $scriptDir "validation/release-test-helper.ps1")
        $script:checks = $checks
        $script:evidence = [ordered]@{
            knowledge_hub = [ordered]@{}
            duplicate_helpers = @()
        }
        $script:repoRoot = $repoRoot
        $script:scratchRootFull = Join-Path $ScratchRoot "knowledge"
        New-Item -ItemType Directory -Force -Path $script:scratchRootFull | Out-Null
        . (Join-Path $scriptDir "validation/release-knowledge-hub-checks.ps1")
        $before = $checks.Count
        Invoke-ReleaseKnowledgeHubChecks
        $added = @($checks.ToArray())[$before..($checks.Count - 1)]
        $knowledgeFailures = @($added | Where-Object status -eq "FAIL")
        if ($knowledgeFailures.Count) { throw ("Knowledge contract checks failed: {0}" -f (($knowledgeFailures | ForEach-Object { "{0}: {1}" -f $_.name, $_.detail }) -join "; ")) }
        Add-Result "knowledge-contracts" "PASS" ("Executed {0} catalog, metadata, public-safe, search, regeneration, and knowledge contract checks." -f $added.Count)
        $executedSuites.Add("knowledge-contracts")
    }
    if ($requiredSuites -contains "hooks-runtime") {
        & (Join-Path $scriptDir "validation/test-claude-hooks-runtime.ps1") -RepositoryRoot $repoRoot -Json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Hooks runtime fixtures failed." }
        Add-Result "hooks-runtime" "PASS" "Executable hooks runtime fixtures passed."
        $executedSuites.Add("hooks-runtime")
    }
    if ($requiredSuites -contains "repository-guards") {
        & (Join-Path $scriptDir "test-pr-identity-guard.ps1") -RepoRoot $repoRoot -Json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "PR identity guard fixtures failed." }
        & (Join-Path $scriptDir "test-issue-triage-decision-command.ps1") -RepoRoot $repoRoot -Json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Issue decision fixtures failed." }
        Add-Result "repository-guards" "PASS" "Repository guard fixtures passed."
        $executedSuites.Add("repository-guards")
    }
    if ($requiredSuites -contains "release-checkpoint") {
        & (Join-Path $scriptDir "validate-release.ps1") -ValidationShard RepositoryCheckpointNeutral -ScratchRoot (Join-Path $ScratchRoot "release-checkpoint") -Json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Repository checkpoint validation failed." }
        Add-Result "release-checkpoint" "PASS" "Repository, governance, historical release, eval, and benchmark artifact checkpoint passed."
        $executedSuites.Add("release-checkpoint")
    }
    if ($requiredSuites -contains "installer-contract") {
        . (Join-Path $scriptDir "lib/path-guard.ps1")
        . (Join-Path $scriptDir "validation/release-test-helper.ps1")
        . (Join-Path $scriptDir "validation/release-installer-contract-checks.ps1")
        $contractEvidence = Invoke-InstallerContractFixtureChecks -RepositoryRoot $repoRoot -ScratchRoot (Join-Path $ScratchRoot "installer-contract")
        Add-Result "installer-contract" "PASS" ("Executed {0} installer contract fixture result(s)." -f @($contractEvidence).Count)
        $executedSuites.Add("installer-contract")
    }
    if ($requiredSuites -contains "runtime-smoke") {
        $runtimeRoot = Join-Path $ScratchRoot "runtime"
        & (Join-Path $scriptDir "install.ps1") -Profile minimal -TargetDir $runtimeRoot | Out-Null
        $installSucceeded = $?
        if (-not $installSucceeded -or -not (Test-Path -LiteralPath (Join-Path $runtimeRoot "install-manifest.json"))) { throw "Minimal copy-first install smoke failed." }
        & (Join-Path $scriptDir "uninstall.ps1") -TargetDir $runtimeRoot -Json | Out-Null
        $uninstallSucceeded = $?
        if (-not $uninstallSucceeded) { throw "Manifest uninstall smoke failed." }
        Add-Result "installer-runtime-smoke" "PASS" "Minimal copy-first install and manifest uninstall completed in scratch space."
        $executedSuites.Add("runtime-smoke")
    }
    if ($requiredSuites -contains "workspace-assets") {
        $workspaceOutput = @(
            & (Join-Path $scriptDir "test-project-workspace-parser.ps1") -Json
        ) -join "`n"
        if ($LASTEXITCODE -ne 0) {
            throw "Project workspace parser fixtures failed.`n$workspaceOutput"
        }
        $workspaceEvidence = $workspaceOutput | ConvertFrom-Json
        if ([int]$workspaceEvidence.schema_version -ne 1 -or
            [string]$workspaceEvidence.status -cne "PASS" -or
            [int]$workspaceEvidence.scenario_count -lt 16 -or
            [int]$workspaceEvidence.pass -lt 1 -or
            [int]$workspaceEvidence.fail -ne 0 -or
            $workspaceEvidence.canonical_sources_read_only -isnot [bool] -or
            -not [bool]$workspaceEvidence.canonical_sources_read_only -or
            $workspaceEvidence.command_inert -isnot [bool] -or
            -not [bool]$workspaceEvidence.command_inert -or
            [int]$workspaceEvidence.template_count -ne 4 -or
            [int]$workspaceEvidence.asset_type_count -ne 4) {
            throw "Project workspace parser fixtures returned incomplete evidence."
        }
        $workspaceDiscoveryOutput = @(
            & (Join-Path $scriptDir "validation/project-workspace-discovery-checks.ps1") `
                -RepositoryRoot $repoRoot `
                -ScratchRoot (Join-Path $ScratchRoot "workspace-discovery") `
                -Json
        ) -join "`n"
        if ($LASTEXITCODE -ne 0) {
            throw "Project workspace discovery fixtures failed.`n$workspaceDiscoveryOutput"
        }
        $workspaceDiscoveryEvidence = $workspaceDiscoveryOutput | ConvertFrom-Json
        if ([int]$workspaceDiscoveryEvidence.schema_version -ne 1 -or
            [string]$workspaceDiscoveryEvidence.status -cne "PASS" -or
            [int]$workspaceDiscoveryEvidence.scenario_count -lt 8 -or
            [int]$workspaceDiscoveryEvidence.pass -lt 8 -or
            [int]$workspaceDiscoveryEvidence.fail -ne 0 -or
            $workspaceDiscoveryEvidence.canonical_sources_read_only -isnot [bool] -or
            -not [bool]$workspaceDiscoveryEvidence.canonical_sources_read_only -or
            $workspaceDiscoveryEvidence.check_read_only -isnot [bool] -or
            -not [bool]$workspaceDiscoveryEvidence.check_read_only -or
            $workspaceDiscoveryEvidence.discover_writes_only_catalog_cache -isnot [bool] -or
            -not [bool]$workspaceDiscoveryEvidence.discover_writes_only_catalog_cache) {
            throw "Project workspace discovery fixtures returned incomplete evidence."
        }
        $workspaceContinuityOutput = @(
            & (Join-Path $scriptDir "validation/project-workspace-continuity-checks.ps1") `
                -RepositoryRoot $repoRoot `
                -ScratchRoot (Join-Path $ScratchRoot "workspace-continuity") `
                -Json
        ) -join "`n"
        if ($LASTEXITCODE -ne 0) {
            throw "Project workspace continuity fixtures failed.`n$workspaceContinuityOutput"
        }
        $workspaceContinuityEvidence = $workspaceContinuityOutput | ConvertFrom-Json
        if ([int]$workspaceContinuityEvidence.schema_version -ne 1 -or
            [string]$workspaceContinuityEvidence.status -cne "PASS" -or
            [int]$workspaceContinuityEvidence.scenario_count -lt 1 -or
            [int]$workspaceContinuityEvidence.pass -ne [int]$workspaceContinuityEvidence.scenario_count -or
            [int]$workspaceContinuityEvidence.fail -ne 0) {
            throw "Project workspace continuity fixtures returned an invalid summary."
        }
        $workspaceAuthoringOutput = @(
            & (Join-Path $scriptDir "validation/project-workspace-authoring-checks.ps1") `
                -RepositoryRoot $repoRoot `
                -ScratchRoot (Join-Path $ScratchRoot "workspace-authoring") `
                -Json
        ) -join "`n"
        if ($LASTEXITCODE -ne 0) {
            throw "Project workspace authoring fixtures failed.`n$workspaceAuthoringOutput"
        }
        $workspaceAuthoringEvidence = $workspaceAuthoringOutput | ConvertFrom-Json
        if ([int]$workspaceAuthoringEvidence.schema_version -ne 1 -or
            [string]$workspaceAuthoringEvidence.status -cne "PASS" -or
            [int]$workspaceAuthoringEvidence.scenario_count -lt 6 -or
            [int]$workspaceAuthoringEvidence.pass -ne [int]$workspaceAuthoringEvidence.scenario_count -or
            [int]$workspaceAuthoringEvidence.fail -ne 0 -or
            -not [bool]$workspaceAuthoringEvidence.catalog_written_only_by_discover -or
            -not [bool]$workspaceAuthoringEvidence.analyze_read_only -or
            -not [bool]$workspaceAuthoringEvidence.apply_no_dual_authority -or
            -not [bool]$workspaceAuthoringEvidence.public_safe) {
            throw "Project workspace authoring fixtures returned incomplete evidence."
        }
        Add-Result "workspace-assets" "PASS" ("Executed {0} parser scenarios across {1} asset types and {2} canonical templates, {3} discovery scenarios, {4} continuity scenarios, and {5} Slice D authoring scenarios proving canonical-only writes, Analyze read-only behavior, single-authority promotion, and Catalog-only discover writes." -f [int]$workspaceEvidence.scenario_count, [int]$workspaceEvidence.asset_type_count, [int]$workspaceEvidence.template_count, [int]$workspaceDiscoveryEvidence.scenario_count, [int]$workspaceContinuityEvidence.scenario_count, [int]$workspaceAuthoringEvidence.scenario_count)
        $executedSuites.Add("workspace-assets")
    }
    if ($requiredSuites -contains "project-context-gate") {
        $contextGateOutput = @(
            & (Join-Path $scriptDir "validation/project-context-gate-checks.ps1") `
                -RepositoryRoot $repoRoot `
                -ScratchRoot (Join-Path $ScratchRoot "project-context-gate") `
                -Json
        ) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "Project context gate checks failed." }
        $contextGateEvidence = $contextGateOutput | ConvertFrom-Json
        if ([string]$contextGateEvidence.status -ne "PASS" -or
            [int]$contextGateEvidence.scenario_count -lt 2 -or
            -not [bool]$contextGateEvidence.project_read_only) {
            throw "Project context gate checks returned incomplete evidence."
        }
        Add-Result "project-context-gate" "PASS" ("Executed {0} source/copy-install layout scenarios with text, JSON, brief, inventory, git-state, and read-only assertions." -f [int]$contextGateEvidence.scenario_count)
        $executedSuites.Add("project-context-gate")
    }
    if ($requiredSuites -contains "agent-skill-bridge") {
        . (Join-Path $scriptDir "lib/path-guard.ps1")
        . (Join-Path $scriptDir "validation/release-test-helper.ps1")
        . (Join-Path $scriptDir "validation/release-agent-skill-bridge-checks.ps1")
        $bridgeEvidence = Invoke-AgentSkillBridgeFixtureChecks -RepositoryRoot $repoRoot -ScratchRoot (Join-Path $ScratchRoot "bridge")
        Add-Result "agent-skill-bridge" "PASS" ("Executed {0} bridge fixture result(s)." -f @($bridgeEvidence).Count)
        $executedSuites.Add("agent-skill-bridge")
    }
    if ($requiredSuites -contains "bootstrap-safety") {
        & (Join-Path $scriptDir "validation/project-bootstrap-safety-fixture.ps1") `
            -RepositoryRoot $repoRoot `
            -ScratchRoot (Join-Path $ScratchRoot "bootstrap") `
            -Json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Project bootstrap safety fixtures failed." }
        Add-Result "bootstrap-safety" "PASS" "Project bootstrap proposal, backup, and write-boundary fixtures passed."
        $executedSuites.Add("bootstrap-safety")
    }
    if ($requiredSuites -contains "template-consistency") {
        . (Join-Path $scriptDir "lib/path-guard.ps1")
        . (Join-Path $scriptDir "validation/release-test-helper.ps1")
        . (Join-Path $scriptDir "validation/release-project-template-checks.ps1")
        $script:checks = $checks
        $script:repoRoot = $repoRoot
        $script:scratchRootFull = Join-Path $ScratchRoot "template-consistency"
        New-Item -ItemType Directory -Force -Path $script:scratchRootFull | Out-Null
        $script:evidence = [ordered]@{ runtime_smoke = @() }
        $script:recommendedCopyRuntime = Join-Path $script:scratchRootFull "recommended-runtime"
        & (Join-Path $scriptDir "install.ps1") -Profile recommended -TargetDir $script:recommendedCopyRuntime | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Recommended runtime install for template consistency failed." }
        $templateSmokeProject = Join-Path $script:scratchRootFull "runtime-smoke-project"
        New-Item -ItemType Directory -Force -Path $templateSmokeProject | Out-Null
        & (Join-Path $script:recommendedCopyRuntime "skills/project-bootstrap/scripts/bootstrap_project.ps1") `
            -ProjectDir $templateSmokeProject `
            -HubDir (Join-Path $script:recommendedCopyRuntime "knowledge-hub") `
            -SkipMemoryUpgradeAnalysis | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Template runtime bootstrap smoke failed." }
        $script:evidence.runtime_smoke = @([ordered]@{ name = "template-targeted"; project = $templateSmokeProject })
        $before = $checks.Count
        Invoke-ReleaseValidationLanguageTemplateChecks
        $added = if ($checks.Count -gt $before) { @($checks.ToArray())[$before..($checks.Count - 1)] } else { @() }
        $templateFailures = @($added | Where-Object status -eq "FAIL")
        if ($templateFailures.Count) { throw ("Template consistency checks failed: {0}" -f (($templateFailures | ForEach-Object { "{0}: {1}" -f $_.name, $_.detail }) -join "; ")) }
        if ($added.Count -eq 0) { throw "Template consistency suite executed zero checks." }
        Add-Result "template-consistency" "PASS" ("Executed {0} template/bootstrap consistency checks." -f $added.Count)
        $executedSuites.Add("template-consistency")
    }
    $moduleCoverage = New-Object 'System.Collections.Generic.List[object]'
    foreach ($module in $modules) {
        $mapped = @($classification.module_suite_map.$module)
        $hostMapped = if ($ExecutionHost -ceq "current") { @($mapped) } else { @($mapped | Where-Object { $requiredSuites -ccontains [string]$_ }) }
        $actual = @($hostMapped | Where-Object { $executedSuites.Contains([string]$_) })
        if ($actual.Count -gt 0) {
            $moduleCoverage.Add([ordered]@{ module = $module; coverage = "targeted-suite"; mapped_suites = $mapped; executed_suites = $actual; executed_checks = @($actual); executed_check_count = $actual.Count })
            continue
        }
        if ($baseCheckModules -contains $module) {
            $baseChecks = @("diff-check", "changed-file-parse")
            $moduleCoverage.Add([ordered]@{ module = $module; coverage = "base-checks"; mapped_suites = @(); executed_suites = @(); executed_checks = $baseChecks; executed_check_count = $baseChecks.Count })
            continue
        }
        if ([string]$module -ceq "validation-routing" -and [bool]$classification.run_validation_self_protection) {
            $moduleCoverage.Add([ordered]@{ module = $module; coverage = "independent-oracle"; mapped_suites = @(); executed_suites = @(); executed_checks = @("validation-self-protection"); executed_check_count = 1 })
            continue
        }
        if ($ExecutionHost -cne "current" -and $hostMapped.Count -eq 0) {
            $moduleCoverage.Add([ordered]@{ module = $module; coverage = "not-required-on-host"; mapped_suites = $mapped; executed_suites = @(); executed_checks = @(); executed_check_count = 0 })
            continue
        }
        throw "Affected runtime module '$module' executed zero actual module checks."
    }
}

$result = [ordered]@{
    schema_version = 2
    mode = $Mode
    execution_host = $ExecutionHost
    classification = $classification
    checks = @($checks.ToArray())
    telemetry = @($telemetry.ToArray())
    executed_suites = $(if ($null -eq $executedSuites) { @() } else { @($executedSuites.ToArray()) })
    module_coverage = $(if ($null -eq $moduleCoverage) { @() } else { @($moduleCoverage.ToArray()) })
    executed_suite_count = $(if ($null -eq $executedSuites) { 0 } else { $executedSuites.Count })
    summary = [ordered]@{ pass = @($checks | Where-Object status -eq "PASS").Count; fail = 0 }
}
$resultPath = Join-Path $ScratchRoot "targeted-validation-result.json"
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
if ($Json.IsPresent) { $result | ConvertTo-Json -Depth 10 } else { Write-Output ("Targeted validation PASS ({0} checks; {1} actual module suites: {2})." -f $result.summary.pass, $result.executed_suite_count, (@($result.executed_suites) -join ", ")) }
