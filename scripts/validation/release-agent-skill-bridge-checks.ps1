function Assert-AgentSkillBridgeCondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Test-AgentSkillBridgeReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $false
    }
    return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-AgentSkillBridgeLinkTarget {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    $targetValue = @($item.PSObject.Properties["Target"].Value | Select-Object -First 1)
    if ($targetValue.Count -eq 0) {
        return ""
    }
    $target = [string]$targetValue[0]
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path -Parent $Path) $target
    }
    return [System.IO.Path]::GetFullPath($target).TrimEnd('\', '/')
}

function New-AgentSkillBridgeFixtureRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$Installer,
        [Parameter(Mandatory = $true)][string]$Root,
        [ValidateSet("minimal", "recommended")][string]$Profile = "minimal",
        [switch]$DevLink
    )

    $installArguments = @{
        Profile = $Profile
        TargetDir = $Root
    }
    if ($DevLink.IsPresent) {
        $installArguments.DevLink = $true
    }
    & $Installer @installArguments | Out-Host
    return $Root
}

function Invoke-AgentSkillBridgeFixtureFailure {
    param(
        [Parameter(Mandatory = $true)][string]$BridgeScript,
        [Parameter(Mandatory = $true)][string]$Runtime,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$SkillName
    )

    $output = @()
    $exitCode = 0
    try {
        $output = @(& $BridgeScript `
                -RuntimeDir $Runtime `
                -AgentSkillsDir $Target `
                -Skill $SkillName `
                -Json 2>&1 | ForEach-Object { [string]$_ })
    }
    catch {
        $exitCode = 1
        $output = @([string]$_.Exception.Message)
    }
    return [ordered]@{
        exit_code = $exitCode
        output = @($output)
    }
}

function Invoke-AgentSkillBridgeFixtureChecks {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ScratchRoot
    )

    $installer = Join-PathParts $RepositoryRoot "scripts" "install.ps1"
    $bridgeScript = Join-PathParts $RepositoryRoot "scripts" "link-agent-skills.ps1"
    $fixtureRoot = Join-PathParts $ScratchRoot "agent-skill-bridge-fixtures"
    New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null

    $evidence = New-Object 'System.Collections.Generic.List[object]'

    # Ordinary installs have no agent-specific target parameter and must leave an
    # explicitly isolated agent directory unchanged.
    $ordinaryRuntime = Join-PathParts $fixtureRoot "ordinary-runtime"
    $ordinaryAgentDir = Join-PathParts $fixtureRoot "ordinary-agent-skills"
    New-Item -ItemType Directory -Force -Path $ordinaryAgentDir | Out-Null
    [System.IO.File]::WriteAllText((Join-PathParts $ordinaryAgentDir "sentinel.txt"), "unchanged")
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $ordinaryRuntime | Out-Null
    $ordinaryEntries = @(Get-ChildItem -LiteralPath $ordinaryAgentDir -Force | ForEach-Object { $_.Name })
    Assert-AgentSkillBridgeCondition -Condition (Test-ExactArray -Actual $ordinaryEntries -Expected @("sentinel.txt")) -Message "Ordinary install modified the isolated agent-specific skills directory."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $ordinaryRuntime "agent-skill-bridge-manifest.json"))) -Message "Ordinary install wrote bridge metadata without opt-in."
    $evidence.Add([ordered]@{ scenario = "ordinary-install-isolation"; status = "PASS" })

    # Valid schema-2 copy runtime, human-readable output, structured manifest,
    # and an unchanged rerun.
    $validRuntime = Join-PathParts $fixtureRoot "valid-copy-runtime"
    $validTarget = Join-PathParts $fixtureRoot "valid-agent-skills"
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $validRuntime | Out-Null
    $installManifestPath = Join-PathParts $validRuntime "install-manifest.json"
    $installManifestHashBefore = (Get-FileHash -LiteralPath $installManifestPath -Algorithm SHA256).Hash
    $humanRun = Invoke-IsolatedPowerShellScript -ScriptPath $bridgeScript -Arguments @(
        "-RuntimeDir", $validRuntime,
        "-AgentSkillsDir", $validTarget,
        "-Skill", "project-bootstrap"
    )
    Assert-AgentSkillBridgeCondition -Condition ($humanRun.exit_code -eq 0) -Message ("Valid copy runtime bridge failed: {0}" -f ($humanRun.output -join "`n"))

    $validSource = [System.IO.Path]::GetFullPath((Join-PathParts $validRuntime "skills" "project-bootstrap")).TrimEnd('\', '/')
    $validLink = [System.IO.Path]::GetFullPath((Join-PathParts $validTarget "project-bootstrap")).TrimEnd('\', '/')
    $bridgeManifestPath = Join-PathParts $validRuntime "agent-skill-bridge-manifest.json"
    Assert-AgentSkillBridgeCondition -Condition (Test-AgentSkillBridgeReparsePoint -Path $validLink) -Message "Valid bridge target is not a link."
    Assert-AgentSkillBridgeCondition -Condition ((Get-AgentSkillBridgeLinkTarget -Path $validLink).Equals($validSource, [System.StringComparison]::OrdinalIgnoreCase)) -Message "Valid bridge link does not target the installed runtime copy."
    Assert-AgentSkillBridgeCondition -Condition ((Get-FileHash -LiteralPath $installManifestPath -Algorithm SHA256).Hash -eq $installManifestHashBefore) -Message "Bridge modified the installer schema-2 manifest."
    Assert-AgentSkillBridgeCondition -Condition (Test-Path -LiteralPath $bridgeManifestPath -PathType Leaf) -Message "Bridge manifest was not written."

    $bridgeManifest = Get-Content -LiteralPath $bridgeManifestPath -Raw | ConvertFrom-Json
    $bridgeRecord = @($bridgeManifest.bridges | Where-Object { [string]$_.skill -eq "project-bootstrap" -and [string]$_.target -eq $validLink })
    Assert-AgentSkillBridgeCondition -Condition ([int]$bridgeManifest.schema_version -eq 1) -Message "Bridge manifest schema version is incorrect."
    Assert-AgentSkillBridgeCondition -Condition ([string]$bridgeManifest.metadata_kind -eq "agent-specific-skill-link-bridge") -Message "Bridge manifest metadata kind is incorrect."
    Assert-AgentSkillBridgeCondition -Condition ([bool]$bridgeManifest.local_runtime_metadata -and [string]$bridgeManifest.commit_policy -eq "do-not-commit") -Message "Bridge manifest does not identify itself as uncommitted local runtime metadata."
    Assert-AgentSkillBridgeCondition -Condition ($bridgeRecord.Count -eq 1) -Message "Bridge manifest does not contain exactly one matching skill record."
    Assert-AgentSkillBridgeCondition -Condition ([string]$bridgeRecord[0].source -eq $validSource -and [string]$bridgeRecord[0].target -eq $validLink -and [string]$bridgeRecord[0].result -eq "created") -Message "Bridge manifest source, target, or result does not match the real link."

    $humanText = $humanRun.output -join "`n"
    Assert-AgentSkillBridgeCondition -Condition ($humanText.Contains("[created] project-bootstrap: $validSource -> $validLink")) -Message "Human-readable bridge result does not match the structured created record."
    Assert-AgentSkillBridgeCondition -Condition ($humanText.Contains("local runtime metadata; do not commit")) -Message "Human-readable output omitted the local-only manifest warning."

    $rerun = Invoke-IsolatedPowerShellScript -ScriptPath $bridgeScript -Arguments @(
        "-RuntimeDir", $validRuntime,
        "-AgentSkillsDir", $validTarget,
        "-Skill", "project-bootstrap",
        "-Json"
    )
    Assert-AgentSkillBridgeCondition -Condition ($rerun.exit_code -eq 0) -Message ("Idempotent bridge rerun failed: {0}" -f ($rerun.output -join "`n"))
    $rerunResult = ($rerun.output -join "`n") | ConvertFrom-Json
    Assert-AgentSkillBridgeCondition -Condition ([string]$rerunResult.results[0].result -eq "unchanged") -Message "Idempotent rerun did not report unchanged."
    Assert-AgentSkillBridgeCondition -Condition ([string]$rerunResult.results[0].source -eq $validSource -and [string]$rerunResult.results[0].target -eq $validLink) -Message "Structured rerun source or target disagrees with the real link."
    Assert-AgentSkillBridgeCondition -Condition (Test-AgentSkillBridgeReparsePoint -Path $validLink) -Message "Idempotent rerun replaced or removed the link."
    $evidence.Add([ordered]@{ scenario = "copy-runtime-create-and-rerun"; first_result = "created"; second_result = "unchanged"; manifest = $bridgeManifestPath })

    # Existing non-link targets fail before metadata or links are written.
    $nonLinkRuntime = Join-PathParts $fixtureRoot "non-link-runtime"
    $nonLinkTarget = Join-PathParts $fixtureRoot "non-link-agent-skills"
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $nonLinkRuntime | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-PathParts $nonLinkTarget "project-bootstrap") | Out-Null
    $nonLinkRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $nonLinkRuntime -Target $nonLinkTarget -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($nonLinkRun.exit_code -ne 0) -Message "Existing non-link target was accepted."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $nonLinkRuntime "agent-skill-bridge-manifest.json"))) -Message "Non-link conflict wrote bridge metadata."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-AgentSkillBridgeReparsePoint -Path (Join-PathParts $nonLinkTarget "project-bootstrap"))) -Message "Non-link conflict replaced the existing directory."
    $evidence.Add([ordered]@{ scenario = "existing-non-link-fail-fast"; exit_code = $nonLinkRun.exit_code })

    # Existing links to another source also fail without mutation.
    $unexpectedRuntime = Join-PathParts $fixtureRoot "unexpected-link-runtime"
    $unexpectedTarget = Join-PathParts $fixtureRoot "unexpected-link-agent-skills"
    $unexpectedSource = Join-PathParts $fixtureRoot "unexpected-source"
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $unexpectedRuntime | Out-Null
    New-Item -ItemType Directory -Force -Path $unexpectedTarget | Out-Null
    New-Item -ItemType Directory -Force -Path $unexpectedSource | Out-Null
    $fixtureLinkType = "SymbolicLink"
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        $fixtureLinkType = "Junction"
    }
    New-Item -ItemType $fixtureLinkType -Path (Join-PathParts $unexpectedTarget "project-bootstrap") -Target $unexpectedSource | Out-Null
    $unexpectedRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $unexpectedRuntime -Target $unexpectedTarget -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($unexpectedRun.exit_code -ne 0) -Message "Unexpected link target was accepted."
    Assert-AgentSkillBridgeCondition -Condition ((Get-AgentSkillBridgeLinkTarget -Path (Join-PathParts $unexpectedTarget "project-bootstrap")).Equals([System.IO.Path]::GetFullPath($unexpectedSource).TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase)) -Message "Unexpected link conflict modified the existing link."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $unexpectedRuntime "agent-skill-bridge-manifest.json"))) -Message "Unexpected link conflict wrote bridge metadata."
    $evidence.Add([ordered]@{ scenario = "unexpected-link-target-fail-fast"; exit_code = $unexpectedRun.exit_code })

    # A source checkout and an explicit dev-link runtime cannot be used as bridge sources.
    $checkoutTarget = Join-PathParts $fixtureRoot "checkout-agent-skills"
    $checkoutRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $RepositoryRoot -Target $checkoutTarget -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($checkoutRun.exit_code -ne 0 -and -not (Test-Path -LiteralPath $checkoutTarget)) -Message "Source checkout was accepted or modified the target."

    $devLinkRuntime = Join-PathParts $fixtureRoot "dev-link-runtime"
    $devLinkTarget = Join-PathParts $fixtureRoot "dev-link-agent-skills"
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $devLinkRuntime -DevLink | Out-Null
    $devLinkRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $devLinkRuntime -Target $devLinkTarget -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($devLinkRun.exit_code -ne 0 -and -not (Test-Path -LiteralPath $devLinkTarget)) -Message "Dev-link runtime was accepted or modified the target."
    $evidence.Add([ordered]@{ scenario = "source-checkout-and-dev-link-rejected"; checkout_exit_code = $checkoutRun.exit_code; dev_link_exit_code = $devLinkRun.exit_code })

    # A directory outside manifest ownership and a manifest item outside skills/
    # are both rejected.
    $unlistedRuntime = Join-PathParts $fixtureRoot "unlisted-runtime"
    $unlistedTarget = Join-PathParts $fixtureRoot "unlisted-agent-skills"
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $unlistedRuntime | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-PathParts $unlistedRuntime "skills" "private-skill") | Out-Null
    $unlistedRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $unlistedRuntime -Target $unlistedTarget -SkillName "private-skill"
    Assert-AgentSkillBridgeCondition -Condition ($unlistedRun.exit_code -ne 0 -and -not (Test-Path -LiteralPath $unlistedTarget)) -Message "Skill outside manifest ownership was accepted or modified the target."

    $outsideSkillsRuntime = Join-PathParts $fixtureRoot "outside-skills-runtime"
    $outsideSkillsTarget = Join-PathParts $fixtureRoot "outside-skills-agent-skills"
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $outsideSkillsRuntime | Out-Null
    $outsideManifestPath = Join-PathParts $outsideSkillsRuntime "install-manifest.json"
    $outsideManifest = Get-Content -LiteralPath $outsideManifestPath -Raw | ConvertFrom-Json
    $outsideItem = @($outsideManifest.items | Where-Object { [string]$_.name -eq "skills/project-bootstrap" })[0]
    $outsideItem.destination = "knowledge-hub"
    $outsideManifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outsideManifestPath -Encoding UTF8
    $outsideRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $outsideSkillsRuntime -Target $outsideSkillsTarget -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($outsideRun.exit_code -ne 0 -and -not (Test-Path -LiteralPath $outsideSkillsTarget)) -Message "Manifest item outside skills/ was accepted or modified the target."
    $evidence.Add([ordered]@{ scenario = "unmanaged-and-non-skills-source-rejected"; unmanaged_exit_code = $unlistedRun.exit_code; outside_skills_exit_code = $outsideRun.exit_code })

    # Preflight must cover the full requested set before any link is created.
    $multiRuntime = Join-PathParts $fixtureRoot "multi-runtime"
    $multiTarget = Join-PathParts $fixtureRoot "multi-agent-skills"
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $multiRuntime -Profile recommended | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-PathParts $multiTarget "project-context-gate") | Out-Null
    $multiFailed = $false
    try {
        & $bridgeScript -RuntimeDir $multiRuntime -AgentSkillsDir $multiTarget -Skill @("project-bootstrap", "project-context-gate") -Json | Out-Null
    }
    catch {
        $multiFailed = $true
    }
    Assert-AgentSkillBridgeCondition -Condition $multiFailed -Message "Multi-skill conflict did not fail."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $multiTarget "project-bootstrap"))) -Message "Multi-skill preflight left a partial bridge."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-AgentSkillBridgeReparsePoint -Path (Join-PathParts $multiTarget "project-context-gate"))) -Message "Multi-skill preflight replaced the conflicting path."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $multiRuntime "agent-skill-bridge-manifest.json"))) -Message "Multi-skill preflight conflict wrote bridge metadata."
    $evidence.Add([ordered]@{ scenario = "multi-skill-preflight-zero-partial-write"; status = "PASS" })

    return @($evidence.ToArray())
}
