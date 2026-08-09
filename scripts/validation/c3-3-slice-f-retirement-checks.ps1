[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Assert-Retirement {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

function Invoke-PwshScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @()
    )

    $output = @(& pwsh -NoProfile -NonInteractive -File $Path @Arguments 2>&1)
    return [ordered]@{ exit_code = $LASTEXITCODE; output = @($output) }
}

function Convert-InvocationJson {
    param([Parameter(Mandatory = $true)][object]$Invocation)

    Assert-Retirement -Condition ([int]$Invocation.exit_code -eq 0) -Message (@($Invocation.output) -join "`n")
    return (@($Invocation.output) -join "`n") | ConvertFrom-Json -Depth 40
}

function Assert-ExactList {
    param(
        [AllowEmptyCollection()][object[]]$Actual,
        [AllowEmptyCollection()][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $actualText = @($Actual | ForEach-Object { [string]$_ }) -join "`n"
    $expectedText = @($Expected) -join "`n"
    Assert-Retirement -Condition ($actualText -ceq $expectedText) -Message $Message
}

$repositoryRootFull = [System.IO.Path]::GetFullPath($RepositoryRoot)
$installScript = Join-Path $repositoryRootFull "scripts/install.ps1"
$bridgeScript = Join-Path $repositoryRootFull "scripts/link-agent-skills.ps1"
$statusScript = Join-Path $repositoryRootFull "scripts/status.ps1"
$retiredSkills = @("project-context-gate", "memory-governance", "workflow-spec-lite")
$candidateAuthority = @("project-bootstrap", "project-workspace")
$legacySkills = @("project-bootstrap", "project-context-gate", "workflow-spec-lite", "memory-governance")
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-c33-retirement-{0}" -f [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null

    $candidateRuntime = Join-Path $scratchRoot "candidate-runtime"
    $candidateBridge = Join-Path $scratchRoot "candidate-bridge"
    $candidateInstall = Invoke-PwshScript -Path $installScript -Arguments @("-Profile", "c3-3-candidate", "-TargetDir", $candidateRuntime)
    Assert-Retirement -Condition ([int]$candidateInstall.exit_code -eq 0) -Message "c3-3-candidate install failed."
    $candidateManifest = Get-Content -LiteralPath (Join-Path $candidateRuntime "install-manifest.json") -Raw | ConvertFrom-Json -Depth 40

    Assert-ExactList -Actual @($candidateManifest.skills) -Expected $candidateAuthority -Message "Candidate installed Skill set is not the frozen C3.3 authority set."
    Assert-ExactList -Actual @($candidateManifest.workspace.c3_3_authority) -Expected $candidateAuthority -Message "Candidate manifest C3.3 authority is incorrect."
    Assert-ExactList -Actual @($candidateManifest.workspace.retired_from_c3_3_authority) -Expected $retiredSkills -Message "Candidate retirement mapping is incorrect."
    Assert-ExactList -Actual @($candidateManifest.workspace.legacy_only_compatibility_payload) -Expected @() -Message "Candidate gained a legacy compatibility payload."
    Assert-Retirement -Condition (-not [bool]$candidateManifest.workspace.compatibility_aliases -and -not [bool]$candidateManifest.workspace.automatic_forwarding -and -not [bool]$candidateManifest.workspace.dual_write) -Message "Candidate enabled alias, forwarding, or dual-write compatibility."
    Assert-Retirement -Condition (-not [bool]$candidateManifest.workspace.default_cutover -and [string]$candidateManifest.workspace.lifecycle -ceq "dormant") -Message "Candidate changed the dormant/default cutover boundary."
    foreach ($skill in $retiredSkills) {
        Assert-Retirement -Condition (-not (Test-Path -LiteralPath (Join-Path $candidateRuntime "skills/$skill"))) -Message "Candidate installed retired Skill: $skill"
        $blockedBridge = Invoke-PwshScript -Path $bridgeScript -Arguments @("-RuntimeDir", $candidateRuntime, "-AgentSkillsDir", $candidateBridge, "-Skill", $skill, "-Json")
        Assert-Retirement -Condition ([int]$blockedBridge.exit_code -ne 0) -Message "Candidate bridged retired Skill: $skill"
        Assert-Retirement -Condition (-not (Test-Path -LiteralPath (Join-Path $candidateBridge $skill))) -Message "Candidate created a retired Skill bridge target: $skill"
    }

    $candidateBridgeResult = Invoke-PwshScript -Path $bridgeScript -Arguments @("-RuntimeDir", $candidateRuntime, "-AgentSkillsDir", $candidateBridge, "-Skill", "project-workspace", "-Json")
    Assert-Retirement -Condition ([int]$candidateBridgeResult.exit_code -eq 0) -Message "Candidate project-workspace bridge failed."
    $candidateStatus = Convert-InvocationJson -Invocation (Invoke-PwshScript -Path $statusScript -Arguments @("-RuntimeDir", $candidateRuntime, "-Json"))
    Assert-ExactList -Actual @($candidateStatus.runtime.workspace.c3_3_authority) -Expected $candidateAuthority -Message "Status did not report the C3.3 authority set."
    Assert-ExactList -Actual @($candidateStatus.runtime.workspace.legacy_only_compatibility_payload) -Expected @() -Message "Status reported candidate legacy authority."
    Assert-Retirement -Condition (@($candidateStatus.bridge.skills | Where-Object { [string]$_.skill -in $retiredSkills }).Count -eq 0) -Message "Status exposed a retired Skill bridge for the candidate."

    foreach ($profile in @("recommended", "full", "dev")) {
        $legacyRuntime = Join-Path $scratchRoot "$profile-runtime"
        $legacyInstall = Invoke-PwshScript -Path $installScript -Arguments @("-Profile", $profile, "-TargetDir", $legacyRuntime)
        Assert-Retirement -Condition ([int]$legacyInstall.exit_code -eq 0) -Message "$profile install failed."
        $legacyManifest = Get-Content -LiteralPath (Join-Path $legacyRuntime "install-manifest.json") -Raw | ConvertFrom-Json -Depth 40
        Assert-ExactList -Actual @($legacyManifest.skills) -Expected $legacySkills -Message "$profile legacy install contract changed."
        Assert-ExactList -Actual @($legacyManifest.workspace.c3_3_authority) -Expected @() -Message "$profile was marked as C3.3 authority."
        Assert-ExactList -Actual @($legacyManifest.workspace.legacy_only_compatibility_payload) -Expected $retiredSkills -Message "$profile legacy-only payload is incorrect."
        foreach ($skill in $retiredSkills) {
            Assert-Retirement -Condition (Test-Path -LiteralPath (Join-Path $legacyRuntime "skills/$skill") -PathType Container) -Message "$profile no longer installs legacy Skill: $skill"
        }
    }

    $legacyBridge = Join-Path $scratchRoot "legacy-bridge"
    $recommendedRuntime = Join-Path $scratchRoot "recommended-runtime"
    foreach ($skill in $retiredSkills) {
        $legacyBridgeResult = Invoke-PwshScript -Path $bridgeScript -Arguments @("-RuntimeDir", $recommendedRuntime, "-AgentSkillsDir", $legacyBridge, "-Skill", $skill, "-Json")
        Assert-Retirement -Condition ([int]$legacyBridgeResult.exit_code -eq 0) -Message ("Legacy-only Skill bridge contract was broken for ${skill}:`n" + (@($legacyBridgeResult.output) -join "`n"))
    }
    $legacyStatus = Convert-InvocationJson -Invocation (Invoke-PwshScript -Path $statusScript -Arguments @("-RuntimeDir", $recommendedRuntime, "-Json"))
    Assert-ExactList -Actual @($legacyStatus.runtime.workspace.c3_3_authority) -Expected @() -Message "Legacy status reported C3.3 authority."
    Assert-ExactList -Actual @($legacyStatus.runtime.workspace.legacy_only_compatibility_payload) -Expected $retiredSkills -Message "Legacy status lost compatibility lifecycle semantics."

    $preRetirementManifestPath = Join-Path $recommendedRuntime "install-manifest.json"
    $preRetirementManifest = Get-Content -LiteralPath $preRetirementManifestPath -Raw | ConvertFrom-Json -Depth 40
    foreach ($field in @("c3_3_authority", "legacy_only_compatibility_payload", "retired_from_c3_3_authority", "compatibility_aliases", "automatic_forwarding", "dual_write")) {
        $preRetirementManifest.workspace.PSObject.Properties.Remove($field)
    }
    [System.IO.File]::WriteAllText($preRetirementManifestPath, (($preRetirementManifest | ConvertTo-Json -Depth 40) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    $preRetirementStatus = Convert-InvocationJson -Invocation (Invoke-PwshScript -Path $statusScript -Arguments @("-RuntimeDir", $recommendedRuntime, "-Json"))
    Assert-ExactList -Actual @($preRetirementStatus.runtime.workspace.c3_3_authority) -Expected @() -Message "Pre-retirement legacy manifest was reclassified as C3.3 authority."
    Assert-ExactList -Actual @($preRetirementStatus.runtime.workspace.legacy_only_compatibility_payload) -Expected $retiredSkills -Message "Pre-retirement legacy manifest lost derived compatibility semantics."

    $summary = [ordered]@{
        schema_version = 1
        status = "pass"
        verifier = "c3-3-slice-f-retirement-checks"
        candidate_authority = $candidateAuthority
        retired_from_c3_3_authority = $retiredSkills
        legacy_profiles = @("recommended", "full", "dev")
        default_cutover = $false
    }
    if ($Json.IsPresent) { $summary | ConvertTo-Json -Depth 8 }
    else { Write-Output "C3.3 Slice F retirement checks passed." }
}
finally {
    if (Test-Path -LiteralPath $scratchRoot) {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force
    }
}
