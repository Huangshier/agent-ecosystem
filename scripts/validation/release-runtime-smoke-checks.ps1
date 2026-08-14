function Invoke-InstallerProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $targetDir = Join-PathParts $scratchRootFull ("runtime-{0}-{1}" -f $Profile, $Mode)
    Assert-NotLiveRuntime -Path $targetDir
    Assert-PathInsideRoot -Path $targetDir -Root $scratchRootFull

    $installer = Join-PathParts $repoRoot "scripts" "install.ps1"
    $installParams = @{
        Profile = $Profile
        TargetDir = $targetDir
    }
    if ($Mode -eq "dev-link") {
        $installParams.DevLink = $true
    }

    & $installer @installParams | Out-Host

    $manifestPath = Join-PathParts $targetDir "install-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Install manifest missing: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    return [ordered]@{
        profile = $Profile
        mode = $Mode
        target_dir = $targetDir
        manifest_path = $manifestPath
        manifest = $manifest
    }
}

function Test-Manifest {
    param(
        [Parameter(Mandatory = $true)][object]$InstallResult,
        [Parameter(Mandatory = $true)][object[]]$ExpectedSkills
    )

    $manifest = $InstallResult.manifest
    $targetDir = $InstallResult.target_dir
    $mode = $InstallResult.mode
    $errors = New-Object 'System.Collections.Generic.List[string]'

    if ([string]$manifest.profile -ne [string]$InstallResult.profile) {
        $errors.Add("profile field mismatch")
    }
    if (-not (Test-ExactArray -Actual @($manifest.skills) -Expected $ExpectedSkills)) {
        $errors.Add("skills field mismatch")
    }
    if ([int]$manifest.schema_version -ne 2) {
        $errors.Add("manifest schema_version should be 2")
    }
    if ([string]$manifest.target_dir -ne ".") {
        $errors.Add("manifest target_dir should be runtime-relative")
    }
    if ($mode -eq "copy" -and [string]$manifest.install_strategy -ne "copy") {
        $errors.Add("copy mode did not record copy strategy")
    }
    if ($mode -eq "dev-link" -and [string]$manifest.install_strategy -ne "dev-link") {
        $errors.Add("dev-link mode did not record dev-link strategy")
    }

    $items = @($manifest.items)
    $expectsStatusProvider = $mode -eq "copy" -and "project-workspace" -in $ExpectedSkills
    $expectsWorkspacePackage = "project-workspace" -in $ExpectedSkills
    $expectedItemCount = 1 + $ExpectedSkills.Count + $(if ($expectsStatusProvider) { 1 } else { 0 }) + $(if ($expectsWorkspacePackage) { 2 } else { 0 })
    if ($items.Count -ne $expectedItemCount) {
        $errors.Add(("item count mismatch: expected {0}, got {1}" -f $expectedItemCount, $items.Count))
    }

    foreach ($item in $items) {
        foreach ($field in @("name", "source", "destination", "mode", "source_hash", "installed_hash")) {
            if ([string]::IsNullOrWhiteSpace([string]$item.$field)) {
                $errors.Add("manifest item missing field: $field")
            }
        }
        if ([System.IO.Path]::IsPathRooted([string]$item.source) -or [System.IO.Path]::IsPathRooted([string]$item.destination)) {
            $errors.Add("manifest item paths should be relative")
        }
        if ($mode -eq "copy" -and [string]$item.mode -ne "copy") {
            $errors.Add(("copy install item used mode {0}" -f $item.mode))
        }
        if ($mode -eq "dev-link" -and [string]$item.mode -notin @("junction", "symboliclink")) {
            $errors.Add(("dev-link install item used unexpected mode {0}" -f $item.mode))
        }
        foreach ($file in @($item.files)) {
            if ([string]::IsNullOrWhiteSpace([string]$file.path) -or [string]::IsNullOrWhiteSpace([string]$file.installed_sha256)) {
                $errors.Add("manifest managed file record is incomplete")
            }
        }
    }

    $statusProviderItems = @($items | Where-Object { [string]$_.name -eq "runtime-status-provider" })
    if ($expectsStatusProvider) {
        if ($statusProviderItems.Count -ne 1) {
            $errors.Add("copy install did not record exactly one runtime status provider item")
        }
        elseif (-not (Test-ExactArray -Actual @($statusProviderItems[0].files | ForEach-Object { [string]$_.path }) -Expected @("lib/path-guard.ps1", "lib/runtime-status-action.ps1", "status.ps1", "migrate-project.ps1", "validation/powershell-runtime-requirement.ps1"))) {
            $errors.Add("runtime status provider item did not contain the exact dependency closure")
        }
    }
    elseif ($statusProviderItems.Count -ne 0) {
        $errors.Add("non-copy or minimal install unexpectedly recorded a runtime status provider item")
    }

    return @($errors.ToArray())
}

# Invoke-ReleaseValidationInstallerRuntimeChecks: No parameters; runs installer matrix, runtime smoke, and temporary project support checks in the original order.
function Invoke-ReleaseValidationInstallerRuntimeChecks {

$script:profileExpectations = [ordered]@{
    minimal = @("project-bootstrap")
    recommended = @("project-bootstrap", "project-workspace")
    full = @("project-bootstrap", "project-workspace")
    dev = @("project-bootstrap", "project-workspace")
}

$script:installModes = @("copy")
if (-not $SkipLinkMode.IsPresent) {
    $script:installModes += "dev-link"
}

$installFailures = New-Object 'System.Collections.Generic.List[string]'
$script:recommendedCopyRuntime = $null
$script:recommendedLinkRuntime = $null
foreach ($profile in $script:profileExpectations.Keys) {
    foreach ($mode in $script:installModes) {
        try {
            $result = Invoke-InstallerProfile -Profile $profile -Mode $mode
            $errors = @(Test-Manifest -InstallResult $result -ExpectedSkills $script:profileExpectations[$profile])
            $manifest = $result.manifest
            $itemModes = @($manifest.items | ForEach-Object { [string]$_.mode })
            $script:evidence.profile_matrix += [ordered]@{
                profile = $profile
                mode = $mode
                target_dir = $result.target_dir
                manifest_path = $result.manifest_path
                skills = @($manifest.skills)
                item_modes = @($itemModes)
            }
            if ($errors.Count -gt 0) {
                $installFailures.Add(("{0}/{1}: {2}" -f $profile, $mode, ($errors -join "; ")))
            }
            if ($profile -eq "recommended" -and $mode -eq "copy") {
                $script:recommendedCopyRuntime = $result.target_dir
            }
            if ($profile -eq "recommended" -and $mode -eq "dev-link") {
                $script:recommendedLinkRuntime = $result.target_dir
            }
        }
        catch {
            $installFailures.Add(("{0}/{1}: {2}" -f $profile, $mode, $_.Exception.Message))
        }
    }
}

try {
    $script:evidence.installer_contract = Invoke-InstallerContractFixtureChecks `
        -RepositoryRoot $repoRoot `
        -ScratchRoot $scratchRootFull `
        -SkipDevLink:$SkipLinkMode.IsPresent
    Add-Check "installer contract fixtures" "PASS" "Copy-first, incremental rerun, conflict, replacement, report, legacy manifest, and explicit development-link scenarios passed." $evidence.installer_contract
}
catch {
    Add-Check "installer contract fixtures" "FAIL" $_.Exception.Message
}
try {
    $script:evidence.runtime_status = Invoke-RuntimeStatusFixtureChecks `
        -RepositoryRoot $repoRoot `
        -ScratchRoot $scratchRootFull
    Add-Check "runtime status fixtures" "PASS" "Read-only runtime manifest status payload fixtures passed." $evidence.runtime_status
}
catch {
    Add-Check "runtime status fixtures" "FAIL" $_.Exception.Message
}
try {
    $script:evidence.agent_skill_bridge = Invoke-AgentSkillBridgeFixtureChecks `
        -RepositoryRoot $repoRoot `
        -ScratchRoot $scratchRootFull
    Add-Check "agent skill bridge fixtures" "PASS" "Explicit opt-in, exact canonical ownership, physical ancestor alias resolution, platform path semantics, runtime/source containment, full preflight, idempotence, transaction rollback, local bridge metadata, and conflict isolation scenarios passed." $evidence.agent_skill_bridge
}
catch {
    Add-Check "agent skill bridge fixtures" "FAIL" $_.Exception.Message
}
if ($installFailures.Count -eq 0) {
    Add-Check "installer profile matrix" "PASS" "All requested profiles and install modes produced valid manifests." $evidence.profile_matrix
}
else {
    Add-Check "installer profile matrix" "FAIL" "Profile or install mode validation failed." @($installFailures.ToArray())
}

function Invoke-RuntimeSmoke {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeDir,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$CheckHubLock,
        [switch]$SkipWorkspaceCheck
    )

    $projectDir = Join-PathParts $scratchRootFull ("runtime-smoke-project-{0}" -f $Name)
    New-Item -ItemType Directory -Force -Path $projectDir | Out-Null
    Assert-PathInsideRoot -Path $projectDir -Root $scratchRootFull

    $hubDir = Join-PathParts $RuntimeDir "knowledge-hub"
    $bootstrapScript = Join-PathParts $RuntimeDir "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
    & $bootstrapScript -ProjectDir $projectDir -HubDir $hubDir -SkipMemoryUpgradeAnalysis | Out-Host

    $lockPath = Join-PathParts $projectDir ".agents" "hub.lock.json"
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        throw "$Name bootstrap did not write .agents/hub.lock.json."
    }
    $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
    if ([string]$lock.workspace_model -cne "c3.3" -or [string]$lock.workspace_state -cne "active") {
        throw ("$Name bootstrap did not produce the active C3.3 workspace contract: {0}/{1}" -f $lock.workspace_model, $lock.workspace_state)
    }

    $expectedLayout = @("AGENTS.md", ".agents/README.md", ".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")
    foreach ($relative in $expectedLayout) {
        if (-not (Test-Path -LiteralPath (Join-PathParts $projectDir $relative))) {
            throw "$Name bootstrap did not create the C3.3 workspace path: $relative"
        }
    }

    # project-workspace check is strictly read-only and must accept the fresh
    # canonical C3.3 workspace. It depends on the copy-installed scripts closure
    # (`scripts/validation/powershell-runtime-requirement.ps1`), which a source
    # dev-link runtime resolves from the repository instead of a copied scripts
    # item; skip it there.
    $checkResult = "skipped"
    if (-not $SkipWorkspaceCheck.IsPresent) {
        $checkScript = Join-PathParts $RuntimeDir "skills" "project-workspace" "scripts" "check-project-workspace.ps1"
        if (-not (Test-Path -LiteralPath $checkScript -PathType Leaf)) {
            throw "$Name runtime did not install project-workspace check."
        }
        $checkJson = (& $checkScript -ProjectRoot $projectDir -Json) | ConvertFrom-Json
        if ([string]$checkJson.status -cne "PASS") {
            throw "$Name project-workspace check did not report status=PASS."
        }
        $checkResult = [string]$checkJson.status

        $discoverScript = Join-PathParts $RuntimeDir "skills" "project-workspace" "scripts" "discover-project-assets.ps1"
        if (-not (Test-Path -LiteralPath $discoverScript -PathType Leaf)) {
            throw "$Name runtime did not install project-workspace discover."
        }
        & $discoverScript -ProjectRoot $projectDir -Query "work" -Json | Out-Null
    }

    $hubLockStatus = "not_checked"
    if ($CheckHubLock.IsPresent) {
        $checkHubLockScript = Join-PathParts $RuntimeDir "skills" "project-bootstrap" "scripts" "check_hub_lock.ps1"
        $hubLockOutput = @(& $checkHubLockScript -ProjectDir $projectDir -HubDir $hubDir)
        $hubLockStatusLine = @($hubLockOutput | Where-Object { $_ -match '^Status:\s+' } | Select-Object -Last 1)
        if ($hubLockStatusLine.Count -lt 1 -or $hubLockStatusLine[0] -notmatch 'Status:\s+in_sync') {
            throw ("hub.lock drift check did not report in_sync. Output: {0}" -f ($hubLockOutput -join " | "))
        }
        $hubLockStatus = "in_sync"
    }

    return [ordered]@{
        name = $Name
        runtime = $RuntimeDir
        project = $projectDir
        bootstrap = "passed"
        workspace_model = [string]$lock.workspace_model
        workspace_state = [string]$lock.workspace_state
        project_workspace_check = $checkResult
        project_workspace_discover = if ($SkipWorkspaceCheck.IsPresent) { "skipped" } else { "passed" }
        hub_lock_status = $hubLockStatus
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $runtimeSmokeResults = New-Object 'System.Collections.Generic.List[object]'
    $copySmoke = Invoke-RuntimeSmoke -RuntimeDir $script:recommendedCopyRuntime -Name "copy"
    $runtimeSmokeResults.Add($copySmoke)

    $sourceStatusScript = Join-PathParts $repoRoot "scripts" "status.ps1"
    $installedStatusScript = Join-PathParts $script:recommendedCopyRuntime "scripts" "status.ps1"
    $sourceRuntimeStatus = (& $sourceStatusScript -RuntimeDir $script:recommendedCopyRuntime -Json | ConvertFrom-Json)
    $installedRuntimeStatus = (& $installedStatusScript -RuntimeDir $script:recommendedCopyRuntime -Json | ConvertFrom-Json)
    foreach ($payload in @($sourceRuntimeStatus, $installedRuntimeStatus)) {
        if ([string]$payload.runtime.workspace.architecture -cne "c3.3" -or
            [string]$payload.runtime.workspace.lifecycle -cne "active" -or
            -not [bool]$payload.runtime.workspace.default_cutover) {
            throw "Status did not report the active C3.3 default runtime workspace contract."
        }
    }
    $runtimeSmokeResults.Add([ordered]@{
            name = "active-c3-3-runtime-status"
            architecture = [string]$sourceRuntimeStatus.runtime.workspace.architecture
            lifecycle = [string]$sourceRuntimeStatus.runtime.workspace.lifecycle
            default_cutover = [bool]$sourceRuntimeStatus.runtime.workspace.default_cutover
        })

    if (-not $SkipLinkMode.IsPresent) {
        if ([string]::IsNullOrWhiteSpace($script:recommendedLinkRuntime)) {
            throw "Recommended link runtime was not created."
        }
        $runtimeSmokeResults.Add((Invoke-RuntimeSmoke -RuntimeDir $script:recommendedLinkRuntime -Name "dev-link" -SkipWorkspaceCheck))
    }

    $script:evidence.runtime_smoke = @($runtimeSmokeResults.ToArray())
    Add-Check "runtime smoke" "PASS" "Bootstrap, project-workspace check/discover, hub-lock drift, and active C3.3 runtime status smoke checks passed for recommended runtime installs." $evidence.runtime_smoke
}
catch {
    Add-Check "runtime smoke" "FAIL" $_.Exception.Message
}

try {
    $contextGateSuite = Join-PathParts $repoRoot "scripts" "validation" "project-context-gate-checks.ps1"
    $contextGateJson = @(
        & $contextGateSuite `
            -RepositoryRoot $repoRoot `
            -ScratchRoot (Join-PathParts $scratchRootFull "project-context-gate-targeted") `
            -Json
    ) -join [Environment]::NewLine
    $contextGateEvidence = $contextGateJson | ConvertFrom-Json
    if ([string]$contextGateEvidence.status -ne "PASS" -or
        [int]$contextGateEvidence.scenario_count -lt 2 -or
        -not [bool]$contextGateEvidence.project_read_only) {
        throw "Project context gate targeted suite returned incomplete evidence."
    }
    $script:evidence.project_context_gate = $contextGateEvidence
    Add-Check "project context gate targeted suite" "PASS" "Source and copy-install layouts preserve text, JSON, brief, inventory, git-state, and read-only behavior." $contextGateEvidence
}
catch {
    Add-Check "project context gate targeted suite" "FAIL" $_.Exception.Message
}

try {
    if ([string]::IsNullOrWhiteSpace($script:recommendedCopyRuntime)) {
        throw "Recommended copy runtime was not created."
    }

    $auditScript = Join-PathParts $script:recommendedCopyRuntime "skills" "project-bootstrap" "scripts" "audit_memory_language.ps1"
    if (-not (Test-Path -LiteralPath $auditScript)) {
        throw "audit_memory_language.ps1 was not installed into the recommended runtime."
    }

    $auditProject = Join-PathParts $scratchRootFull "body-level-memory-language-audit"
    New-Item -ItemType Directory -Force -Path $auditProject | Out-Null
    Assert-PathInsideRoot -Path $auditProject -Root $scratchRootFull

    $contextDir = Join-PathParts $auditProject ".agents" "context" "experience"
    $commandsDir = Join-PathParts $auditProject ".agents" "commands"
    $specDir = Join-PathParts $auditProject "docs" "specs" "body-mixed"
    New-Item -ItemType Directory -Force -Path $contextDir | Out-Null
    New-Item -ItemType Directory -Force -Path $commandsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $specDir | Out-Null

    $zhSummary = [regex]::Unescape('\u8fd9\u662f\u4e2d\u6587\u6458\u8981\u3002')
    $zhKeywords = [regex]::Unescape('\u8bed\u8a00, \u5ba1\u8ba1')
    $zhBody = [regex]::Unescape('\u8fd9\u4e2a\u9879\u76ee\u7684\u6b63\u6587\u5df2\u7ecf\u662f\u4e2d\u6587\u3002\u540e\u7eed\u5ba1\u8ba1\u5e94\u8be5\u6309\u7167\u6b63\u6587\u8bed\u8a00\u5224\u65ad\uff0c\u800c\u4e0d\u662f\u6309\u7167\u5143\u6570\u636e\u5224\u65ad\u3002')
    $zhCode = [regex]::Unescape('\u4ee3\u7801\u5757')
    $zhSpecPrefix = [regex]::Unescape('\u8fd9\u4e2a\u89c4\u683c\u4fdd\u7559\u4e2d\u6587\u53d9\u8ff0\uff0c\u540c\u65f6')
    $zhMixedSuffix = [regex]::Unescape('\u5e94\u8be5\u4f5c\u4e3a\u6df7\u5408\u8bed\u8a00\u8bc1\u636e\u88ab\u62a5\u544a\u3002')
    $zhCommandHeading = [regex]::Unescape('\u8fd0\u884c\u547d\u4ee4')
    $zhProtectedBody = [regex]::Unescape('\u8fd9\u91cc\u4ec5\u5305\u542b\u547d\u4ee4\u3001\u8def\u5f84\u3001API\u3001\u6587\u4ef6\u540d\u548c\u539f\u59cb\u9519\u8bef\u6587\u672c\uff0c\u4e0d\u5e94\u89e6\u53d1\u6b63\u6587\u8bed\u8a00\u53d1\u73b0\u3002')

    $metadataZhBodyEnPath = Join-PathParts $contextDir "metadata-zh-body-en.md"
    Set-Content -LiteralPath $metadataZhBodyEnPath -Value @(
        "## Summary",
        $zhSummary,
        "",
        "## Keywords",
        $zhKeywords,
        "",
        "## Notes",
        "The rollout remains paused until review. The project should preserve this operational lesson for future migrations."
    ) -Encoding UTF8

    $metadataEnBodyZhPath = Join-PathParts $contextDir "metadata-en-body-zh.md"
    Set-Content -LiteralPath $metadataEnBodyZhPath -Value @(
        "## Summary",
        "English metadata summary.",
        "",
        "## Keywords",
        "language, audit",
        "",
        "## Notes",
        $zhBody
    ) -Encoding UTF8

    $fencedCodePath = Join-PathParts $contextDir "fenced-code-only.md"
    Set-Content -LiteralPath $fencedCodePath -Value @(
        "## Summary",
        $zhSummary,
        "",
        "## Keywords",
        $zhCode,
        "",
        '```text',
        "This English text is inside a fenced code block and should not count.",
        "The command git status and path src/app.py should stay ignored here.",
        '```'
    ) -Encoding UTF8

    $protectedLiteralsPath = Join-PathParts $commandsDir "protected-literals.md"
    Set-Content -LiteralPath $protectedLiteralsPath -Value @(
        "# $zhCommandHeading",
        "",
        $zhProtectedBody,
        "",
        "powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-release.ps1 -ScratchRoot C:\Temp\audit",
        "Keep `Get-FooBar`, `src/app.py`, `AGENTS.md`, `feat`, `ERROR_PATH_NOT_FOUND`, and `CustomThing` unchanged."
    ) -Encoding UTF8

    $mixedSpecPath = Join-PathParts $specDir "spec.md"
    Set-Content -LiteralPath $mixedSpecPath -Value @(
        "# Body Mixed Spec",
        "",
        ("{0} this English narrative remains in the body and should be flagged as mixed language evidence. {1}" -f $zhSpecPrefix, $zhMixedSuffix)
    ) -Encoding UTF8

    function Get-AuditFixtureHashes {
        param([string]$Root)

        $hashes = @{}
        foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File)) {
            $relative = ConvertTo-DisplayPath -Path $file.FullName -Root $Root
            $hashes[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
        return $hashes
    }

    $hashesBefore = Get-AuditFixtureHashes -Root $auditProject
    $audit = & $auditScript -ProjectDir $auditProject -ExpectedLanguage "zh-CN" -IncludeSpecs -IncludeCommands -Json | ConvertFrom-Json
    $humanOutput = @(& $auditScript -ProjectDir $auditProject -ExpectedLanguage "zh-CN" -IncludeSpecs -IncludeCommands)
    $hashesAfter = Get-AuditFixtureHashes -Root $auditProject

    $changedFiles = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in @($hashesBefore.Keys)) {
        if (-not $hashesAfter.ContainsKey($key) -or $hashesBefore[$key] -ne $hashesAfter[$key]) {
            $changedFiles.Add($key)
        }
    }
    foreach ($key in @($hashesAfter.Keys)) {
        if (-not $hashesBefore.ContainsKey($key)) {
            $changedFiles.Add($key)
        }
    }
    if ($changedFiles.Count -gt 0) {
        throw ("Body-level audit helper changed project files: {0}" -f ($changedFiles.ToArray() -join "; "))
    }

    $findingPaths = @($audit.findings | ForEach-Object { [string]$_.path })
    $expectedFindingPaths = @(
        ".agents/context/experience/metadata-zh-body-en.md",
        "docs/specs/body-mixed/spec.md"
    )
    foreach ($expectedPath in $expectedFindingPaths) {
        if ($expectedPath -notin $findingPaths) {
            throw "Body-level audit helper missed expected finding: $expectedPath"
        }
    }
    foreach ($unexpectedPath in @(
        ".agents/context/experience/metadata-en-body-zh.md",
        ".agents/context/experience/fenced-code-only.md",
        ".agents/commands/protected-literals.md"
    )) {
        if ($unexpectedPath -in $findingPaths) {
            throw "Body-level audit helper reported an ignored fixture: $unexpectedPath"
        }
    }

    $metadataOnly = @($audit.findings | Where-Object { [string]$_.path -eq ".agents/context/experience/metadata-zh-body-en.md" -and [string]$_.code -eq "metadata_only_localization" })
    $mixedBody = @($audit.findings | Where-Object { [string]$_.path -eq "docs/specs/body-mixed/spec.md" -and [string]$_.code -eq "mixed_language_body" })
    if ($metadataOnly.Count -ne 1 -or $mixedBody.Count -ne 1) {
        throw "Body-level audit helper reported unexpected finding codes."
    }
    if ([int]$audit.summary.finding_count -ne 2) {
        throw ("Body-level audit helper returned unexpected finding count: {0}" -f $audit.summary.finding_count)
    }
    if (@($humanOutput | Where-Object { $_ -like "WARN .agents/context/experience/metadata-zh-body-en.md:*" }).Count -ne 1) {
        throw "Body-level audit helper human output did not include the metadata/body warning."
    }

    $script:evidence.memory_language_audit = [ordered]@{
        project = $auditProject
        scanned_files = [int]$audit.scanned_files
        findings = @($audit.findings | ForEach-Object { [ordered]@{ path = [string]$_.path; code = [string]$_.code; reason = [string]$_.reason } })
        non_findings = @(
            ".agents/context/experience/metadata-en-body-zh.md",
            ".agents/context/experience/fenced-code-only.md",
            ".agents/commands/protected-literals.md"
        )
        read_only_hash_check = "passed"
    }

    Add-Check "body-level memory language audit" "PASS" "Read-only audit helper detects metadata-only localization and mixed narrative body language while ignoring metadata, fenced code, commands, paths, APIs, filenames, raw errors, and code identifiers." $evidence.memory_language_audit
}
catch {
    Add-Check "body-level memory language audit" "FAIL" $_.Exception.Message
}

if ($script:includeCheckpointChecks) {
try {
    $benchmarkScript = Join-PathParts $repoRoot "scripts" "benchmark-context-gate.ps1"
    $benchmarkScratch = Join-PathParts $scratchRootFull "context-gate-benchmark"
    Assert-PathInsideRoot -Path $benchmarkScratch -Root $scratchRootFull
    $benchmarkJsonText = & $benchmarkScript -ScratchRoot $benchmarkScratch -ContextFileCount 500 -MaxSeconds 30 -Json
    $benchmark = $benchmarkJsonText | ConvertFrom-Json
    if (-not [bool]$benchmark.passed) {
        throw ("Benchmark did not pass. Elapsed={0}s, threshold={1}s, included={2}" -f $benchmark.elapsed_seconds, $benchmark.max_seconds, $benchmark.included_context_files)
    }
    Add-Check "context gate large context benchmark" "PASS" ("Context gate JSON handled {0} context files in {1}s." -f $benchmark.included_context_files, $benchmark.elapsed_seconds) $benchmark
}
catch {
    Add-Check "context gate large context benchmark" "FAIL" $_.Exception.Message
}

try {
    $pruneScript = Join-PathParts $repoRoot "scripts" "prune-validation-scratch.ps1"
    $pruneFixture = Join-PathParts $scratchRootFull "validation-scratch-retention"
    New-Item -ItemType Directory -Force -Path $pruneFixture | Out-Null
    Assert-PathInsideRoot -Path $pruneFixture -Root $scratchRootFull

    foreach ($index in 1..4) {
        $runDir = Join-PathParts $pruneFixture ("run-{0}" -f $index)
        New-Item -ItemType Directory -Force -Path $runDir | Out-Null
        Assert-PathInsideRoot -Path $runDir -Root $pruneFixture
        [ordered]@{
            run = $index
            status = "fixture"
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-PathParts $runDir "validation-result.json") -Encoding UTF8
        (Get-Item -LiteralPath $runDir).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes($index)
    }

    $dryRunJson = & $pruneScript -ScratchRoot $pruneFixture -RetainLatest 2 -Json
    $dryRun = $dryRunJson | ConvertFrom-Json
    if ([bool]$dryRun.apply) {
        throw "Dry run reported apply=true."
    }
    if ([int]$dryRun.summary.candidate_count -ne 4 -or
        [int]$dryRun.summary.retained_count -ne 2 -or
        [int]$dryRun.summary.prunable_count -ne 2) {
        throw "Dry run retention counts were incorrect."
    }
    foreach ($index in 1..4) {
        if (-not (Test-Path -LiteralPath (Join-PathParts $pruneFixture ("run-{0}" -f $index)))) {
            throw "Dry run removed run-$index."
        }
    }

    $applyJson = & $pruneScript -ScratchRoot $pruneFixture -RetainLatest 2 -Apply -Json
    $apply = $applyJson | ConvertFrom-Json
    if (-not [bool]$apply.apply) {
        throw "Apply run reported apply=false."
    }
    foreach ($index in 1..2) {
        if (Test-Path -LiteralPath (Join-PathParts $pruneFixture ("run-{0}" -f $index))) {
            throw "Apply run did not prune run-$index."
        }
    }
    foreach ($index in 3..4) {
        if (-not (Test-Path -LiteralPath (Join-PathParts $pruneFixture ("run-{0}" -f $index)))) {
            throw "Apply run pruned retained run-$index."
        }
    }

    $script:evidence.scratch_retention = [ordered]@{
        fixture_root = $pruneFixture
        dry_run = $dryRun
        apply = $apply
    }
    Add-Check "validation scratch retention pruning" "PASS" "Scratch pruning helper is dry-run by default and prunes only older evidence-marked run directories when -Apply is supplied." $evidence.scratch_retention
}
catch {
    Add-Check "validation scratch retention pruning" "FAIL" $_.Exception.Message
}
}

}
