[CmdletBinding()]
param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion -lt [version]"7.6") {
    throw "C3.3 Slice E lifecycle checks require PowerShell 7.6 or newer."
}

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
$installScript = Join-Path $repositoryRoot "scripts/install.ps1"
$statusScript = Join-Path $repositoryRoot "scripts/status.ps1"
$uninstallScript = Join-Path $repositoryRoot "scripts/uninstall.ps1"
$bridgeScript = Join-Path $repositoryRoot "scripts/link-agent-skills.ps1"
$bootstrapScript = Join-Path $repositoryRoot "skills/project-bootstrap/scripts/bootstrap_project.ps1"
$memoryUpgradeScript = Join-Path $repositoryRoot "skills/project-bootstrap/scripts/memory_upgrade.ps1"

function Assert-SliceE {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-PwshScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @()
    )

    $global:LASTEXITCODE = 0
    $output = @(& $pwshPath -NoProfile -NonInteractive -File $Path @Arguments 2>&1)
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    return [ordered]@{
        exit_code = $exitCode
        output = @($output | ForEach-Object { [string]$_ })
    }
}

function Convert-OutputToJson {
    param([Parameter(Mandatory = $true)][object]$Invocation)

    Assert-SliceE -Condition ([int]$Invocation.exit_code -eq 0) -Message ("Child script failed: {0}" -f (@($Invocation.output) -join "`n"))
    $text = @($Invocation.output) -join "`n"
    Assert-SliceE -Condition (-not [string]::IsNullOrWhiteSpace($text)) -Message "Child script returned no JSON output."
    return $text | ConvertFrom-Json -Depth 40
}

function Convert-BlockedOutputToJson {
    param([Parameter(Mandatory = $true)][object]$Invocation)

    Assert-SliceE -Condition ([int]$Invocation.exit_code -eq 2) -Message ("Blocked child script returned the wrong exit code: {0}" -f (@($Invocation.output) -join "`n"))
    $text = @($Invocation.output) -join "`n"
    Assert-SliceE -Condition (-not [string]::IsNullOrWhiteSpace($text)) -Message "Blocked child script returned no JSON output."
    return $text | ConvertFrom-Json -Depth 40
}

function Get-ProjectFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return @()
    }
    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            Sort-Object FullName |
            ForEach-Object {
                $relative = [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')
                "{0}|{1}|{2}" -f $relative, $_.Length, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
    )
}

function Get-RelativeFileCount {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return -1
    }
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force).Count
}

$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-c33-slice-e-{0}" -f ([Guid]::NewGuid().ToString("N")))
$runtimeRoot = Join-Path $scratchRoot "runtime"
$legacyRuntimeRoot = Join-Path $scratchRoot "legacy-runtime"
$projectRoot = Join-Path $scratchRoot "project"
$legacyProjectRoot = Join-Path $scratchRoot "legacy-project"
$bridgeTargetRoot = Join-Path $scratchRoot "client-skills"
$evidence = [ordered]@{
    profile = "c3-3-candidate"
    bootstrap = "pass"
    runtime_ownership = "pass"
    schema_authority = "pass"
    bridge = "pass"
    status = "pass"
    uninstall = "pass"
    fail_closed = @("stale-bridge-ownership", "nested-unknown-runtime-file", "locally-modified-runtime-file")
    scope = "pass"
}

try {
    New-Item -ItemType Directory -Force -Path $runtimeRoot, $legacyRuntimeRoot, $projectRoot, $legacyProjectRoot | Out-Null

    $install = Invoke-PwshScript -Path $installScript -Arguments @(
        "-Profile", "c3-3-candidate",
        "-TargetDir", $runtimeRoot
    )
    Assert-SliceE -Condition ([int]$install.exit_code -eq 0) -Message "Candidate profile install failed: $(@($install.output) -join "`n")"

    $legacyInstall = Invoke-PwshScript -Path $installScript -Arguments @(
        "-Profile", "recommended",
        "-TargetDir", $legacyRuntimeRoot
    )
    Assert-SliceE -Condition ([int]$legacyInstall.exit_code -eq 0) -Message "Recommended profile install failed: $(@($legacyInstall.output) -join "`n")"

    $manifestPath = Join-Path $runtimeRoot "install-manifest.json"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 40
    Assert-SliceE -Condition ([string]$manifest.profile -ceq "c3-3-candidate") -Message "Candidate profile was not recorded."
    Assert-SliceE -Condition ([string]$manifest.workspace.architecture -ceq "c3.3" -and [string]$manifest.workspace.lifecycle -ceq "dormant") -Message "C3.3 runtime workspace was not recorded as dormant."
    Assert-SliceE -Condition ([bool]$manifest.workspace.default_cutover -eq $false) -Message "Candidate profile changed default cutover state."
    Assert-SliceE -Condition (@($manifest.skills) -contains "project-workspace") -Message "Candidate runtime does not own packaged project-workspace."
    Assert-SliceE -Condition (@($manifest.items | Where-Object { [string]$_.destination -eq "templates/project" }).Count -eq 1) -Message "Candidate runtime template ownership is missing."
    $schemaItem = @($manifest.items | Where-Object { [string]$_.destination -ceq "schemas/project-workspace" })
    Assert-SliceE -Condition ($schemaItem.Count -eq 1 -and [string]$schemaItem[0].name -ceq "schemas/project-workspace" -and [bool]$schemaItem[0].managed) -Message "Candidate runtime schema ownership is missing."
    Assert-SliceE -Condition (@($schemaItem[0].files).Count -eq @(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot "schemas/project-workspace") -Recurse -File).Count) -Message "Candidate runtime schema ownership does not cover the canonical schema files."
    $runtimeProviderItem = @($manifest.items | Where-Object { [string]$_.name -ceq "runtime-status-provider" })
    Assert-SliceE -Condition ($runtimeProviderItem.Count -eq 1 -and @($runtimeProviderItem[0].files | Where-Object { [string]$_.path -ceq "validation/powershell-runtime-requirement.ps1" }).Count -eq 1) -Message "Candidate runtime does not own the PowerShell requirement used by project-workspace."
    Assert-SliceE -Condition (@($manifest.workspace.packaged_content | Where-Object { [string]$_ -ceq "schemas/project-workspace" }).Count -eq 1) -Message "Candidate runtime schema authority is missing from the workspace contract."
    Assert-SliceE -Condition (@($manifest.workspace.packaged_content | Where-Object { [string]$_ -ceq "scripts/migrate-project.ps1" }).Count -eq 1) -Message "Candidate runtime migration entrypoint is missing from the workspace contract."
    Assert-SliceE -Condition (Test-Path -LiteralPath (Join-Path $runtimeRoot "schemas/project-workspace/work-item.v1.schema.json") -PathType Leaf) -Message "Candidate runtime did not install the canonical project-workspace schemas."
    Assert-SliceE -Condition (Test-Path -LiteralPath (Join-Path $runtimeRoot "scripts/validation/powershell-runtime-requirement.ps1") -PathType Leaf) -Message "Candidate runtime did not install the PowerShell requirement used by project-workspace."
    Assert-SliceE -Condition (Test-Path -LiteralPath (Join-Path $runtimeRoot "scripts/migrate-project.ps1") -PathType Leaf) -Message "Candidate runtime did not install the migration entrypoint."
    Assert-SliceE -Condition (@($manifest.items | Where-Object { [string]$_.destination -in @("AGENTS.md", ".agents", "docs/specs") }).Count -eq 0) -Message "Runtime manifest owns a project-local path."

    $legacyManifest = Get-Content -LiteralPath (Join-Path $legacyRuntimeRoot "install-manifest.json") -Raw | ConvertFrom-Json -Depth 40
    Assert-SliceE -Condition ([string]$legacyManifest.profile -ceq "recommended") -Message "Recommended profile was not recorded."
    Assert-SliceE -Condition ([string]$legacyManifest.workspace.architecture -ceq "legacy-runtime" -and [string]$legacyManifest.workspace.lifecycle -ceq "not-enabled") -Message "Recommended runtime did not retain the legacy workspace contract."
    Assert-SliceE -Condition ([bool]$legacyManifest.workspace.default_cutover -eq $false) -Message "Recommended runtime changed default cutover state."
    Assert-SliceE -Condition (-not (Test-Path -LiteralPath (Join-Path $legacyRuntimeRoot "schemas/project-workspace"))) -Message "Recommended runtime gained the dormant C3.3 schema authority."
    Assert-SliceE -Condition (-not (Test-Path -LiteralPath (Join-Path $legacyRuntimeRoot "scripts/migrate-project.ps1"))) -Message "Recommended runtime gained the dormant C3.3 migration entrypoint."

    $reinstall = Invoke-PwshScript -Path $installScript -Arguments @(
        "-Profile", "c3-3-candidate",
        "-TargetDir", $runtimeRoot
    )
    Assert-SliceE -Condition ([int]$reinstall.exit_code -eq 0) -Message "Candidate profile reinstall failed: $(@($reinstall.output) -join "`n")"
    $reinstallReport = Get-Content -LiteralPath (Join-Path $runtimeRoot "install-report.json") -Raw | ConvertFrom-Json -Depth 40
    $reinstallManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 40
    $reinstalledSchemaItem = @($reinstallManifest.items | Where-Object { [string]$_.destination -ceq "schemas/project-workspace" })
    Assert-SliceE -Condition ([string]$reinstallReport.status -ceq "success" -and [int]$reinstallReport.counts.conflicts -eq 0 -and [int]$reinstallReport.counts.skipped_locally_modified -eq 0) -Message "Candidate profile reinstall did not preserve current managed ownership."
    Assert-SliceE -Condition ($reinstalledSchemaItem.Count -eq 1 -and [string]$reinstalledSchemaItem[0].installed_hash -ceq [string]$schemaItem[0].installed_hash) -Message "Candidate profile reinstall lost or changed current schema ownership."
    Assert-SliceE -Condition (@($reinstallReport.unchanged | Where-Object { [string]$_ -clike "schemas/project-workspace/*" }).Count -eq @($reinstalledSchemaItem[0].files).Count) -Message "Candidate profile reinstall did not report every packaged schema as unchanged."

    $bootstrapScript = Join-Path $runtimeRoot "skills/project-bootstrap/scripts/bootstrap_project.ps1"
    $legacyBootstrapScript = Join-Path $legacyRuntimeRoot "skills/project-bootstrap/scripts/bootstrap_project.ps1"
    $memoryUpgradeScript = Join-Path $runtimeRoot "skills/project-bootstrap/scripts/memory_upgrade.ps1"

    $legacyBootstrap = Invoke-PwshScript -Path $legacyBootstrapScript -Arguments @(
        "-ProjectDir", $legacyProjectRoot,
        "-ProjectLanguage", "zh-CN",
        "-SkipMemoryUpgradeAnalysis"
    )
    Assert-SliceE -Condition ([int]$legacyBootstrap.exit_code -eq 0) -Message "Fresh recommended bootstrap failed: $(@($legacyBootstrap.output) -join "`n")"
    foreach ($relative in @("AGENTS.md", ".agents/AGENTS.md", ".agents/process.txt", ".agents/plan.md", ".agents/notes.md", ".agents/hub.lock.json", ".agents/context/README.md", ".agents/commands/README.md", "docs/specs/_templates/spec-lite.md")) {
        Assert-SliceE -Condition (Test-Path -LiteralPath (Join-Path $legacyProjectRoot $relative) -PathType Leaf) -Message "Fresh recommended bootstrap did not create legacy scaffold file $relative."
    }
    foreach ($relative in @(".agents/work", ".agents/procedures", ".agents/skills")) {
        Assert-SliceE -Condition (-not (Test-Path -LiteralPath (Join-Path $legacyProjectRoot $relative))) -Message "Fresh recommended bootstrap created C3.3-only path $relative."
    }
    $legacyLock = Get-Content -LiteralPath (Join-Path $legacyProjectRoot ".agents/hub.lock.json") -Raw | ConvertFrom-Json -Depth 40
    Assert-SliceE -Condition ([string]$legacyLock.project_language -ceq "zh-CN" -and [string]$legacyLock.workspace_model -ceq "legacy" -and [string]$legacyLock.workspace_state -ceq "not-enabled") -Message "Fresh recommended bootstrap did not retain zh-CN legacy metadata."
    $legacyGuideText = Get-Content -LiteralPath (Join-Path $legacyProjectRoot ".agents/AGENTS.md") -Raw
    Assert-SliceE -Condition ($legacyGuideText -match "项目记忆语言：简体中文") -Message "Fresh recommended bootstrap did not retain the zh-CN legacy language scaffold."

    $bootstrap = Invoke-PwshScript -Path $bootstrapScript -Arguments @(
        "-ProjectDir", $projectRoot,
        "-ProjectLanguage", "zh-CN",
        "-SkipMemoryUpgradeAnalysis"
    )
    Assert-SliceE -Condition ([int]$bootstrap.exit_code -eq 0) -Message "Fresh C3.3 bootstrap failed: $(@($bootstrap.output) -join "`n")"

    foreach ($relative in @("AGENTS.md", ".agents/README.md", ".agents/.gitignore", ".agents/hub.lock.json")) {
        Assert-SliceE -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf) -Message "Fresh bootstrap did not create $relative."
    }
    foreach ($relative in @(".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")) {
        Assert-SliceE -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Container) -Message "Fresh bootstrap did not create $relative."
        Assert-SliceE -Condition ((Get-RelativeFileCount -Root (Join-Path $projectRoot $relative)) -eq 0) -Message "Fresh bootstrap created a placeholder asset under $relative."
    }
    Assert-SliceE -Condition (@(Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Force | Where-Object { $_.Name -match 'glossary' }).Count -eq 0) -Message "Fresh bootstrap created glossary data."
    $lock = Get-Content -LiteralPath (Join-Path $projectRoot ".agents/hub.lock.json") -Raw | ConvertFrom-Json -Depth 40
    Assert-SliceE -Condition ([string]$lock.project_language -ceq "zh-CN" -and [string]$lock.workspace_model -ceq "c3.3" -and [string]$lock.workspace_state -ceq "dormant") -Message "Fresh bootstrap language or workspace metadata is incorrect."
    $agentsText = Get-Content -LiteralPath (Join-Path $projectRoot "AGENTS.md") -Raw
    Assert-SliceE -Condition ($agentsText -notmatch '(?i)current branch|checks|next step') -Message "Fresh bootstrap wrote transient run-state text."

    $installedWorkspaceScript = Join-Path $runtimeRoot "skills/project-workspace/scripts/project-workspace.ps1"
    $beforeInstalledCheck = Get-ProjectFingerprint -Root $projectRoot
    $installedCheck = Convert-OutputToJson -Invocation (Invoke-PwshScript -Path $installedWorkspaceScript -Arguments @(
        "-Operation", "check",
        "-ProjectRoot", $projectRoot,
        "-Json"
    ))
    $afterInstalledCheck = Get-ProjectFingerprint -Root $projectRoot
    Assert-SliceE -Condition ([string]$installedCheck.status -ceq "PASS" -and [bool]$installedCheck.read_only) -Message "Installed project-workspace check did not pass against the packaged schema authority."
    Assert-SliceE -Condition ((@($beforeInstalledCheck) -join "`n") -ceq (@($afterInstalledCheck) -join "`n")) -Message "Installed project-workspace check changed project state."

    $installedSchemaPath = Join-Path $runtimeRoot "schemas/project-workspace/work-item.v1.schema.json"
    $installedSchemaBytes = [System.IO.File]::ReadAllBytes($installedSchemaPath)
    try {
        Write-Utf8NoBom -Path $installedSchemaPath -Text "{ invalid installed schema`n"
        $invalidInstalledCheck = Invoke-PwshScript -Path $installedWorkspaceScript -Arguments @(
            "-Operation", "check",
            "-ProjectRoot", $projectRoot,
            "-Json"
        )
        Assert-SliceE -Condition ([int]$invalidInstalledCheck.exit_code -eq 1) -Message "Installed project-workspace check did not reject its modified installed schema."
        $invalidInstalledPayload = (@($invalidInstalledCheck.output) -join "`n") | ConvertFrom-Json -Depth 40
        Assert-SliceE -Condition ([string]$invalidInstalledPayload.status -ceq "FAIL" -and @($invalidInstalledPayload.findings | Where-Object { [string]$_.code -ceq "canonical-schema-load-failed" -and [string]$_.path -ceq "work-item.v1.schema.json" }).Count -ge 1) -Message "Installed project-workspace check did not report the installed schema failure."
    }
    finally {
        [System.IO.File]::WriteAllBytes($installedSchemaPath, $installedSchemaBytes)
    }
    $restoredInstalledCheck = Convert-OutputToJson -Invocation (Invoke-PwshScript -Path $installedWorkspaceScript -Arguments @(
        "-Operation", "check",
        "-ProjectRoot", $projectRoot,
        "-Json"
    ))
    Assert-SliceE -Condition ([string]$restoredInstalledCheck.status -ceq "PASS") -Message "Installed project-workspace check did not recover after restoring its packaged schema."

    $localAgentsText = "# local project edit`n"
    Write-Utf8NoBom -Path (Join-Path $projectRoot "AGENTS.md") -Text $localAgentsText
    $rerun = Invoke-PwshScript -Path $legacyBootstrapScript -Arguments @(
        "-ProjectDir", $projectRoot,
        "-SkipMemoryUpgradeAnalysis"
    )
    Assert-SliceE -Condition ([int]$rerun.exit_code -eq 0) -Message "Existing C3.3 bootstrap rerun failed: $(@($rerun.output) -join "`n")"
    Assert-SliceE -Condition ((Get-Content -LiteralPath (Join-Path $projectRoot "AGENTS.md") -Raw) -ceq $localAgentsText) -Message "C3.3 bootstrap overwrote a project-local edit."
    $rerunLock = Get-Content -LiteralPath (Join-Path $projectRoot ".agents/hub.lock.json") -Raw | ConvertFrom-Json -Depth 40
    Assert-SliceE -Condition ([string]$rerunLock.project_language -ceq "zh-CN" -and [string]$rerunLock.workspace_model -ceq "c3.3" -and [string]$rerunLock.workspace_state -ceq "dormant") -Message "Existing workspace_model=c3.3 did not keep the C3.3 rerun path."
    foreach ($relative in @(".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")) {
        Assert-SliceE -Condition ((Get-RelativeFileCount -Root (Join-Path $projectRoot $relative)) -eq 0) -Message "Existing C3.3 rerun created a placeholder asset under $relative."
    }

    $beforeAnalyze = Get-ProjectFingerprint -Root $projectRoot
    $analysis = Convert-OutputToJson -Invocation (Invoke-PwshScript -Path $memoryUpgradeScript -Arguments @(
        "-ProjectDir", $projectRoot,
        "-Mode", "Analyze",
        "-Json"
    ))
    $afterAnalyze = Get-ProjectFingerprint -Root $projectRoot
    Assert-SliceE -Condition ($null -ne $analysis -and (@($beforeAnalyze) -join "`n") -ceq (@($afterAnalyze) -join "`n")) -Message "Strict memory Analyze changed the project."

    foreach ($fixture in @(
            @{ relative = ".agents/work/real-work.md"; text = "# Work`n" },
            @{ relative = ".agents/context/real-context.md"; text = "# Context`n" },
            @{ relative = ".agents/procedures/real-procedure.md"; text = "# Procedure`n" },
            @{ relative = "docs/specs/real-spec/spec.md"; text = "# Spec`n" },
            @{ relative = ".agents/skills/promoted-local/SKILL.md"; text = "---`nname: promoted-local`ndescription: local project Skill`n---`n" }
        )) {
        Write-Utf8NoBom -Path (Join-Path $projectRoot $fixture.relative) -Text $fixture.text
    }

    $beforeStatus = Get-ProjectFingerprint -Root $projectRoot
    $status = Convert-OutputToJson -Invocation (Invoke-PwshScript -Path $statusScript -Arguments @(
        "-RuntimeDir", $runtimeRoot,
        "-ProjectDir", $projectRoot,
        "-Json"
    ))
    $afterStatus = Get-ProjectFingerprint -Root $projectRoot
    Assert-SliceE -Condition ((@($beforeStatus) -join "`n") -ceq (@($afterStatus) -join "`n")) -Message "Status wrote project state."
    Assert-SliceE -Condition ([string]$status.runtime.manifest_status -ceq "current" -and [string]$status.runtime.profile -ceq "c3-3-candidate") -Message "Status did not report the current candidate runtime."
    Assert-SliceE -Condition ([string]$status.runtime.workspace.architecture -ceq "c3.3" -and [string]$status.runtime.workspace.lifecycle -ceq "dormant" -and [bool]$status.runtime.workspace.default_cutover -eq $false) -Message "Status did not preserve dormant/default-cutover semantics."
    Assert-SliceE -Condition (@($status.runtime.workspace.packaged_content | Where-Object { [string]$_ -ceq "schemas/project-workspace" }).Count -eq 1) -Message "Status did not report the packaged schema authority."
    Assert-SliceE -Condition (@($status.runtime.workspace.packaged_content | Where-Object { [string]$_ -ceq "scripts/migrate-project.ps1" }).Count -eq 1) -Message "Status did not report the packaged migration entrypoint."
    Assert-SliceE -Condition ([string]$status.project.workspace.status -ceq "current" -and [string]$status.project.workspace.layout -ceq "complete" -and [string]$status.project.workspace.runtime_boundary -ceq "separate" -and [string]$status.project.workspace.readiness -ceq "candidate-dormant-ready") -Message "Status did not distinguish project workspace lifecycle facts."
    Assert-SliceE -Condition (@($manifest.skills | Where-Object { [string]$_ -eq "promoted-local" }).Count -eq 0) -Message "Project-local Skill was merged into packaged runtime authority."

    $bridge = Invoke-PwshScript -Path $bridgeScript -Arguments @(
        "-RuntimeDir", $runtimeRoot,
        "-AgentSkillsDir", $bridgeTargetRoot,
        "-Skill", "project-workspace",
        "-Json"
    )
    $bridgePayload = Convert-OutputToJson -Invocation $bridge
    Assert-SliceE -Condition (@($bridgePayload.results | Where-Object { [string]$_.skill -ceq "project-workspace" -and [string]$_.result -in @("created", "unchanged") }).Count -eq 1) -Message "Packaged project-workspace was not exposed through the supported bridge."
    $statusWithBridge = Convert-OutputToJson -Invocation (Invoke-PwshScript -Path $statusScript -Arguments @(
        "-RuntimeDir", $runtimeRoot,
        "-ProjectDir", $projectRoot,
        "-Json"
    ))
    Assert-SliceE -Condition ([string]$statusWithBridge.bridge.status -ceq "current" -and @($statusWithBridge.bridge.skills | Where-Object { [string]$_.skill -ceq "project-workspace" -and [string]$_.status -ceq "current" }).Count -eq 1) -Message "Supported bridge status is not current."

    $bridgeManifestPath = Join-Path $runtimeRoot "agent-skill-bridge-manifest.json"
    $originalBridgeManifest = Get-Content -LiteralPath $bridgeManifestPath -Raw
    $staleBridge = $originalBridgeManifest | ConvertFrom-Json -Depth 20
    $staleBridge.runtime = Join-Path $scratchRoot "stale-runtime"
    Write-Utf8NoBom -Path $bridgeManifestPath -Text ($staleBridge | ConvertTo-Json -Depth 20)
    $staleUninstall = Invoke-PwshScript -Path $uninstallScript -Arguments @("-TargetDir", $runtimeRoot, "-Json")
    Assert-SliceE -Condition ([int]$staleUninstall.exit_code -eq 2) -Message "Stale bridge ownership did not fail closed."
    Assert-SliceE -Condition ((Test-Path -LiteralPath (Join-Path $runtimeRoot "install-manifest.json") -PathType Leaf) -and (Test-Path -LiteralPath $bridgeTargetRoot -PathType Container)) -Message "Stale bridge uninstall removed runtime or bridge content."
    Write-Utf8NoBom -Path $bridgeManifestPath -Text $originalBridgeManifest

    Write-Utf8NoBom -Path (Join-Path $runtimeRoot "schemas/project-workspace/local-runtime-schema.json") -Text "unknown runtime content`n"
    $unknownHumanUninstall = Invoke-PwshScript -Path $uninstallScript -Arguments @("-TargetDir", $runtimeRoot)
    $unknownHumanOutput = @($unknownHumanUninstall.output) -join "`n"
    Assert-SliceE -Condition ([int]$unknownHumanUninstall.exit_code -eq 2) -Message "Unknown runtime content human uninstall did not return the blocked exit code."
    foreach ($expectedLine in @(
            "Uninstall blocked. No files were removed.",
            "Nested unknown files: 1",
            "The install manifest and install report were preserved."
        )) {
        Assert-SliceE -Condition ($unknownHumanOutput.Contains($expectedLine)) -Message "Unknown runtime content human uninstall omitted: $expectedLine"
    }
    $unknownUninstall = Invoke-PwshScript -Path $uninstallScript -Arguments @("-TargetDir", $runtimeRoot, "-Json")
    Assert-SliceE -Condition ([int]$unknownUninstall.exit_code -eq 2) -Message "Unknown runtime content did not fail closed."
    $unknownBlocked = Convert-BlockedOutputToJson -Invocation $unknownUninstall
    $expectedBlockedFields = @(
        "schema_version", "target_dir", "manifest_path", "status", "reason", "removed", "missing",
        "preserved_unknown", "protection_scope", "ownership_errors", "nested_unknown", "locally_modified"
    )
    Assert-SliceE -Condition ((@($unknownBlocked.PSObject.Properties.Name) -join "`n") -ceq ($expectedBlockedFields -join "`n")) -Message "Blocked uninstall JSON fields changed."
    Assert-SliceE -Condition (
        [int]$unknownBlocked.schema_version -eq 1 -and
        [string]$unknownBlocked.status -ceq "blocked" -and
        [string]$unknownBlocked.reason -ceq "schema2_copy_item_safety_check" -and
        [bool]$unknownBlocked.preserved_unknown -and
        [string]$unknownBlocked.protection_scope -ceq "fail-closed-ownership" -and
        @($unknownBlocked.nested_unknown).Count -eq 1 -and
        @($unknownBlocked.locally_modified).Count -eq 0
    ) -Message "Blocked uninstall JSON contract changed."
    Assert-SliceE -Condition (Test-Path -LiteralPath (Join-Path $runtimeRoot "install-manifest.json") -PathType Leaf) -Message "Unknown runtime content uninstall removed the manifest."
    Remove-Item -LiteralPath (Join-Path $runtimeRoot "schemas/project-workspace/local-runtime-schema.json") -Force

    $managedRuntimeFile = Join-Path $runtimeRoot "schemas/project-workspace/work-item.v1.schema.json"
    $managedRuntimeBytes = [System.IO.File]::ReadAllBytes($managedRuntimeFile)
    try {
        [System.IO.File]::AppendAllText($managedRuntimeFile, "`nlocal modification`n", (New-Object System.Text.UTF8Encoding($false)))
        $modifiedBytes = [System.IO.File]::ReadAllBytes($managedRuntimeFile)
        $modifiedReinstall = Invoke-PwshScript -Path $installScript -Arguments @(
            "-Profile", "c3-3-candidate",
            "-TargetDir", $runtimeRoot
        )
        $modifiedReinstallReport = Get-Content -LiteralPath (Join-Path $runtimeRoot "install-report.json") -Raw | ConvertFrom-Json -Depth 40
        Assert-SliceE -Condition ([int]$modifiedReinstall.exit_code -eq 0 -and [string]$modifiedReinstallReport.status -ceq "warning" -and @($modifiedReinstallReport.skipped_locally_modified | Where-Object { [string]$_ -ceq "schemas/project-workspace/work-item.v1.schema.json" }).Count -eq 1) -Message "Candidate profile reinstall did not preserve the locally modified managed schema."
        Assert-SliceE -Condition (([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($managedRuntimeFile))) -ceq ([Convert]::ToBase64String($modifiedBytes))) -Message "Candidate profile reinstall overwrote the locally modified managed schema."
        $modifiedHumanUninstall = Invoke-PwshScript -Path $uninstallScript -Arguments @("-TargetDir", $runtimeRoot)
        $modifiedHumanOutput = @($modifiedHumanUninstall.output) -join "`n"
        Assert-SliceE -Condition ([int]$modifiedHumanUninstall.exit_code -eq 2) -Message "Locally modified runtime content human uninstall did not return the blocked exit code."
        Assert-SliceE -Condition ($modifiedHumanOutput.Contains("Locally modified managed files: 1")) -Message "Locally modified runtime content human uninstall omitted its count."
    }
    finally {
        [System.IO.File]::WriteAllBytes($managedRuntimeFile, $managedRuntimeBytes)
    }

    $uninstall = Convert-OutputToJson -Invocation (Invoke-PwshScript -Path $uninstallScript -Arguments @("-TargetDir", $runtimeRoot, "-Json"))
    Assert-SliceE -Condition ([string]$uninstall.status -ceq "uninstalled" -and @($uninstall.bridge_removed).Count -ge 2) -Message "Manifest-owned runtime/bridge uninstall did not complete."
    Assert-SliceE -Condition (-not (Test-Path -LiteralPath (Join-Path $runtimeRoot "install-manifest.json")) -and -not (Test-Path -LiteralPath $bridgeManifestPath) -and -not (Test-Path -LiteralPath (Join-Path $runtimeRoot "schemas/project-workspace")) -and -not (Test-Path -LiteralPath (Join-Path $runtimeRoot "scripts/migrate-project.ps1")) -and -not (Test-Path -LiteralPath (Join-Path $bridgeTargetRoot "project-workspace"))) -Message "Uninstall left owned runtime or bridge content."
    foreach ($relative in @("AGENTS.md", ".agents/README.md", ".agents/work/real-work.md", ".agents/context/real-context.md", ".agents/procedures/real-procedure.md", ".agents/skills/promoted-local/SKILL.md", "docs/specs/real-spec/spec.md")) {
        Assert-SliceE -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf) -Message "Uninstall deleted project-local asset $relative."
    }

    foreach ($legacySkill in @("project-context-gate", "workflow-spec-lite", "memory-governance")) {
        Assert-SliceE -Condition (Test-Path -LiteralPath (Join-Path $repositoryRoot "skills/$legacySkill") -PathType Container) -Message "Slice E retired a later-slice Skill: $legacySkill"
    }

    $summary = [ordered]@{
        schema_version = 1
        status = "pass"
        profile = "c3-3-candidate"
        verifier = "c3-3-slice-e-lifecycle-checks"
        evidence = $evidence
    }
    if ($Json.IsPresent) {
        $summary | ConvertTo-Json -Depth 12
    }
    else {
        Write-Output "C3.3 Slice E lifecycle checks passed."
        Write-Output "Profile: c3-3-candidate (dormant)"
        Write-Output "Bootstrap, ownership/profile, bridge, status, uninstall, and fail-closed scope checks: PASS"
    }
}
finally {
    if (Test-Path -LiteralPath $scratchRoot) {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force
    }
}
