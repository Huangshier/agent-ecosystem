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
    return Get-NormalizedFullPath -Path $target
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

    $fileSystemRoot = [System.IO.Path]::GetPathRoot((Get-NormalizedFullPath -Path $fixtureRoot))
    $normalizedFileSystemRoot = Get-NormalizedFullPath -Path $fileSystemRoot
    Assert-AgentSkillBridgeCondition -Condition (-not [string]::IsNullOrEmpty($normalizedFileSystemRoot)) -Message "Filesystem root normalization returned an empty path."
    Assert-AgentSkillBridgeCondition -Condition (Test-IsFileSystemRoot -Path $normalizedFileSystemRoot) -Message "Filesystem root normalization no longer preserves the root path."
    Assert-AgentSkillBridgeCondition -Condition (Test-PlatformPathEqual -Left $normalizedFileSystemRoot -Right $fileSystemRoot) -Message "Filesystem root normalization changed the root path."
    $evidence.Add([ordered]@{ scenario = "filesystem-root-normalization"; status = "PASS" })

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

    $validSource = Get-NormalizedFullPath -Path (Join-PathParts $validRuntime "skills" "project-bootstrap")
    $validLink = Get-NormalizedFullPath -Path (Join-PathParts $validTarget "project-bootstrap")
    $bridgeManifestPath = Join-PathParts $validRuntime "agent-skill-bridge-manifest.json"
    Assert-AgentSkillBridgeCondition -Condition (Test-AgentSkillBridgeReparsePoint -Path $validLink) -Message "Valid bridge target is not a link."
    Assert-AgentSkillBridgeCondition -Condition (Test-PlatformPathEqual -Left (Get-AgentSkillBridgeLinkTarget -Path $validLink) -Right $validSource) -Message "Valid bridge link does not target the installed runtime copy."
    Assert-AgentSkillBridgeCondition -Condition ((Get-FileHash -LiteralPath $installManifestPath -Algorithm SHA256).Hash -eq $installManifestHashBefore) -Message "Bridge modified the installer schema-2 manifest."
    Assert-AgentSkillBridgeCondition -Condition (Test-Path -LiteralPath $bridgeManifestPath -PathType Leaf) -Message "Bridge manifest was not written."

    $bridgeManifest = Get-Content -LiteralPath $bridgeManifestPath -Raw | ConvertFrom-Json
    $bridgeRecord = @($bridgeManifest.bridges | Where-Object {
            [string]::Equals([string]$_.skill, "project-bootstrap", [System.StringComparison]::Ordinal) -and
            (Test-PlatformPathEqual -Left ([string]$_.target) -Right $validLink)
        })
    Assert-AgentSkillBridgeCondition -Condition ([int]$bridgeManifest.schema_version -eq 1) -Message "Bridge manifest schema version is incorrect."
    Assert-AgentSkillBridgeCondition -Condition ([string]$bridgeManifest.metadata_kind -eq "agent-specific-skill-link-bridge") -Message "Bridge manifest metadata kind is incorrect."
    Assert-AgentSkillBridgeCondition -Condition ([bool]$bridgeManifest.local_runtime_metadata -and [string]$bridgeManifest.commit_policy -eq "do-not-commit") -Message "Bridge manifest does not identify itself as uncommitted local runtime metadata."
    Assert-AgentSkillBridgeCondition -Condition ($bridgeRecord.Count -eq 1) -Message "Bridge manifest does not contain exactly one matching skill record."
    Assert-AgentSkillBridgeCondition -Condition ((Test-PlatformPathEqual -Left ([string]$bridgeRecord[0].source) -Right $validSource) -and (Test-PlatformPathEqual -Left ([string]$bridgeRecord[0].target) -Right $validLink) -and [string]$bridgeRecord[0].result -eq "created") -Message "Bridge manifest source, target, or result does not match the real link."

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
    Assert-AgentSkillBridgeCondition -Condition ((Test-PlatformPathEqual -Left ([string]$rerunResult.results[0].source) -Right $validSource) -and (Test-PlatformPathEqual -Left ([string]$rerunResult.results[0].target) -Right $validLink)) -Message "Structured rerun source or target disagrees with the real link."
    Assert-AgentSkillBridgeCondition -Condition (Test-AgentSkillBridgeReparsePoint -Path $validLink) -Message "Idempotent rerun replaced or removed the link."
    $evidence.Add([ordered]@{ scenario = "copy-runtime-create-and-rerun"; first_result = "created"; second_result = "unchanged"; manifest = $bridgeManifestPath })

    # Manifest ownership uses exact canonical skill, item, and destination names.
    # On case-sensitive platforms an unmanaged case variant is a distinct source.
    $caseRuntime = Join-PathParts $fixtureRoot "case-runtime"
    $caseTarget = Join-PathParts $fixtureRoot "case-agent-skills"
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $caseRuntime | Out-Null
    $caseInstallManifestPath = Join-PathParts $caseRuntime "install-manifest.json"
    $caseInstallManifestHash = (Get-FileHash -LiteralPath $caseInstallManifestPath -Algorithm SHA256).Hash
    $isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $caseVariantSource = Join-PathParts $caseRuntime "skills" "Project-Bootstrap"
    if (-not $isWindowsPlatform) {
        New-Item -ItemType Directory -Force -Path $caseVariantSource | Out-Null
    }
    $caseRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $caseRuntime -Target $caseTarget -SkillName "Project-Bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($caseRun.exit_code -ne 0) -Message "Case-variant skill borrowed canonical manifest ownership."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath $caseTarget)) -Message "Case-variant skill request created an agent target."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $caseRuntime "agent-skill-bridge-manifest.json"))) -Message "Case-variant skill request wrote bridge metadata."
    Assert-AgentSkillBridgeCondition -Condition ((Get-FileHash -LiteralPath $caseInstallManifestPath -Algorithm SHA256).Hash -eq $caseInstallManifestHash) -Message "Case-variant skill request modified the installer manifest."

    $duplicateCaseTarget = Join-PathParts $fixtureRoot "duplicate-case-agent-skills"
    $duplicateCaseFailed = $false
    try {
        & $bridgeScript -RuntimeDir $caseRuntime -AgentSkillsDir $duplicateCaseTarget -Skill @("project-bootstrap", "Project-Bootstrap") -Json | Out-Null
    }
    catch {
        $duplicateCaseFailed = $true
    }
    Assert-AgentSkillBridgeCondition -Condition $duplicateCaseFailed -Message "Case-variant duplicate request was accepted."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath $duplicateCaseTarget)) -Message "Case-variant duplicate request left a partial target."

    $caseRecordTargetRoot = Join-PathParts $fixtureRoot "case-record-agent-skills"
    $caseRecordTarget = Get-NormalizedFullPath -Path (Join-PathParts $caseRecordTargetRoot "project-bootstrap")
    $legacyCaseBridgeManifestPath = Join-PathParts $caseRuntime "agent-skill-bridge-manifest.json"
    $legacyCaseBridgeManifest = [ordered]@{
        schema_version = 1
        metadata_kind = "agent-specific-skill-link-bridge"
        local_runtime_metadata = $true
        commit_policy = "do-not-commit"
        runtime = Get-NormalizedFullPath -Path $caseRuntime
        updated_at_utc = "2000-01-01T00:00:00.0000000Z"
        bridges = @([ordered]@{
                skill = "Project-Bootstrap"
                source = Get-NormalizedFullPath -Path $caseVariantSource
                target = $caseRecordTarget
                result = "created"
                link_mode = $(if ($isWindowsPlatform) { "junction" } else { "symboliclink" })
            })
    }
    $legacyCaseBridgeManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $legacyCaseBridgeManifestPath -Encoding UTF8
    $caseRecordRun = Invoke-IsolatedPowerShellScript -ScriptPath $bridgeScript -Arguments @(
        "-RuntimeDir", $caseRuntime,
        "-AgentSkillsDir", $caseRecordTargetRoot,
        "-Skill", "project-bootstrap",
        "-Json"
    )
    Assert-AgentSkillBridgeCondition -Condition ($caseRecordRun.exit_code -eq 0) -Message ("Canonical rerun could not replace a case-variant bridge record: {0}" -f ($caseRecordRun.output -join "`n"))
    $caseRecordManifest = Get-Content -LiteralPath $legacyCaseBridgeManifestPath -Raw | ConvertFrom-Json
    $caseEquivalentRecords = @($caseRecordManifest.bridges | Where-Object {
            [string]::Equals([string]$_.skill, "project-bootstrap", [System.StringComparison]::OrdinalIgnoreCase) -and
            (Test-PlatformPathEqual -Left ([string]$_.target) -Right $caseRecordTarget)
        })
    Assert-AgentSkillBridgeCondition -Condition ($caseEquivalentRecords.Count -eq 1) -Message "Canonical rerun left duplicate case-variant bridge records."
    Assert-AgentSkillBridgeCondition -Condition ([string]::Equals([string]$caseEquivalentRecords[0].skill, "project-bootstrap", [System.StringComparison]::Ordinal)) -Message "Canonical rerun did not replace the case-variant record with the manifest name."

    $caseSensitiveLinkStatus = "platform-adjusted"
    if (-not $isWindowsPlatform) {
        $caseLinkTargetRoot = Join-PathParts $fixtureRoot "case-link-agent-skills"
        New-Item -ItemType Directory -Force -Path $caseLinkTargetRoot | Out-Null
        $caseLink = Join-PathParts $caseLinkTargetRoot "project-bootstrap"
        New-Item -ItemType SymbolicLink -Path $caseLink -Target $caseVariantSource | Out-Null
        $caseLinkRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $caseRuntime -Target $caseLinkTargetRoot -SkillName "project-bootstrap"
        Assert-AgentSkillBridgeCondition -Condition ($caseLinkRun.exit_code -ne 0) -Message "Case-sensitive platform accepted a link to a differently cased source."
        Assert-AgentSkillBridgeCondition -Condition (($caseLinkRun.output -join "`n").Contains("unexpected")) -Message "Case-sensitive wrong-source link did not report an unexpected target."
        Assert-AgentSkillBridgeCondition -Condition (Test-PlatformPathEqual -Left (Get-AgentSkillBridgeLinkTarget -Path $caseLink) -Right $caseVariantSource) -Message "Case-sensitive wrong-source conflict modified the existing link."
        $caseSensitiveLinkStatus = "rejected"
    }
    $evidence.Add([ordered]@{ scenario = "canonical-skill-case-ownership"; variant_exit_code = $caseRun.exit_code; case_sensitive_link = $caseSensitiveLinkStatus })

    # Agent target roots and final skill targets must stay outside the runtime
    # and every selected source. A sibling that only shares a string prefix is
    # not a child path and remains valid.
    $containmentRuntime = Join-PathParts $fixtureRoot "containment-runtime"
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $containmentRuntime | Out-Null
    $containmentManifestPath = Join-PathParts $containmentRuntime "install-manifest.json"
    $containmentManifestHash = (Get-FileHash -LiteralPath $containmentManifestPath -Algorithm SHA256).Hash
    $runtimeChildTarget = Join-PathParts $containmentRuntime "agent-skills"
    $runtimeChildRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $containmentRuntime -Target $runtimeChildTarget -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($runtimeChildRun.exit_code -ne 0 -and -not (Test-Path -LiteralPath $runtimeChildTarget)) -Message "AgentSkillsDir inside RuntimeDir was accepted or created."
    Assert-AgentSkillBridgeCondition -Condition (($runtimeChildRun.output -join "`n").Contains("outside RuntimeDir")) -Message "Runtime containment failure did not report its path boundary."

    $containmentSource = Join-PathParts $containmentRuntime "skills" "project-bootstrap"
    $sourceChildTarget = Join-PathParts $containmentSource "agent-skills"
    $sourceChildRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $containmentRuntime -Target $sourceChildTarget -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($sourceChildRun.exit_code -ne 0 -and -not (Test-Path -LiteralPath $sourceChildTarget)) -Message "AgentSkillsDir inside a selected source was accepted or created."
    Assert-AgentSkillBridgeCondition -Condition (($sourceChildRun.output -join "`n").Contains("outside selected skill source")) -Message "Source containment failure did not report its path boundary."

    $equalTargetRoot = Join-PathParts $containmentRuntime "skills"
    $equalTargetRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $containmentRuntime -Target $equalTargetRoot -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($equalTargetRun.exit_code -ne 0) -Message "Final target equal to the selected source was accepted."
    Assert-AgentSkillBridgeCondition -Condition (($equalTargetRun.output -join "`n").Contains("Final skill target must not equal")) -Message "Equal source/target failure did not report the recursive target boundary."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-AgentSkillBridgeReparsePoint -Path $containmentSource)) -Message "Equal source/target failure replaced the source directory."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $containmentRuntime "agent-skill-bridge-manifest.json"))) -Message "Containment failure wrote bridge metadata."
    Assert-AgentSkillBridgeCondition -Condition ((Get-FileHash -LiteralPath $containmentManifestPath -Algorithm SHA256).Hash -eq $containmentManifestHash) -Message "Containment failure modified the installer manifest."

    $prefixRoot = Join-PathParts $fixtureRoot "prefix-boundary"
    $prefixRuntime = Join-PathParts $prefixRoot "runtime"
    $prefixTarget = Join-PathParts $prefixRoot "runtime-client-skills"
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-PathIsEqualOrChild -Path $prefixTarget -Root $prefixRuntime)) -Message "Segment-aware path guard treated a shared string prefix as containment."
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $prefixRuntime | Out-Null
    $prefixRun = Invoke-IsolatedPowerShellScript -ScriptPath $bridgeScript -Arguments @(
        "-RuntimeDir", $prefixRuntime,
        "-AgentSkillsDir", $prefixTarget,
        "-Skill", "project-bootstrap",
        "-Json"
    )
    Assert-AgentSkillBridgeCondition -Condition ($prefixRun.exit_code -eq 0) -Message ("Shared-prefix sibling target was rejected: {0}" -f ($prefixRun.output -join "`n"))
    Assert-AgentSkillBridgeCondition -Condition (Test-AgentSkillBridgeReparsePoint -Path (Join-PathParts $prefixTarget "project-bootstrap")) -Message "Shared-prefix sibling target did not create the expected bridge."
    $evidence.Add([ordered]@{ scenario = "runtime-source-containment-boundaries"; runtime_child_exit_code = $runtimeChildRun.exit_code; source_child_exit_code = $sourceChildRun.exit_code; equal_target_exit_code = $equalTargetRun.exit_code; shared_prefix_result = "created" })

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
    Assert-AgentSkillBridgeCondition -Condition (Test-PlatformPathEqual -Left (Get-AgentSkillBridgeLinkTarget -Path (Join-PathParts $unexpectedTarget "project-bootstrap")) -Right $unexpectedSource) -Message "Unexpected link conflict modified the existing link."
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
    $outsideItem = @($outsideManifest.items | Where-Object { [string]::Equals([string]$_.name, "skills/project-bootstrap", [System.StringComparison]::Ordinal) })[0]

    $caseItemTarget = Join-PathParts $fixtureRoot "case-item-agent-skills"
    $outsideItem.name = "skills/Project-Bootstrap"
    $outsideManifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outsideManifestPath -Encoding UTF8
    $caseItemRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $outsideSkillsRuntime -Target $caseItemTarget -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($caseItemRun.exit_code -ne 0 -and -not (Test-Path -LiteralPath $caseItemTarget)) -Message "Case-variant manifest item name was accepted or modified the target."

    $caseDestinationTarget = Join-PathParts $fixtureRoot "case-destination-agent-skills"
    $outsideItem.name = "skills/project-bootstrap"
    $outsideItem.destination = "skills/Project-Bootstrap"
    $outsideManifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outsideManifestPath -Encoding UTF8
    $caseDestinationRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $outsideSkillsRuntime -Target $caseDestinationTarget -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($caseDestinationRun.exit_code -ne 0 -and -not (Test-Path -LiteralPath $caseDestinationTarget)) -Message "Case-variant manifest destination was accepted or modified the target."

    $outsideItem.destination = "knowledge-hub"
    $outsideManifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outsideManifestPath -Encoding UTF8
    $outsideRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $outsideSkillsRuntime -Target $outsideSkillsTarget -SkillName "project-bootstrap"
    Assert-AgentSkillBridgeCondition -Condition ($outsideRun.exit_code -ne 0 -and -not (Test-Path -LiteralPath $outsideSkillsTarget)) -Message "Manifest item outside skills/ was accepted or modified the target."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $outsideSkillsRuntime "agent-skill-bridge-manifest.json"))) -Message "Invalid canonical manifest ownership wrote bridge metadata."
    $evidence.Add([ordered]@{ scenario = "unmanaged-and-non-skills-source-rejected"; unmanaged_exit_code = $unlistedRun.exit_code; case_item_exit_code = $caseItemRun.exit_code; case_destination_exit_code = $caseDestinationRun.exit_code; outside_skills_exit_code = $outsideRun.exit_code })

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

    # Force a deterministic manifest commit failure after the valid link has
    # been created, without adding a production fault-injection parameter.
    # Windows locks the old manifest against replacement; Unix makes the local
    # runtime metadata directory read-only for the duration of the invocation.
    $rollbackRuntime = Join-PathParts $fixtureRoot "transaction-rollback-runtime"
    $rollbackTarget = Join-PathParts $fixtureRoot "transaction-rollback-agent-skills"
    New-AgentSkillBridgeFixtureRuntime -Installer $installer -Root $rollbackRuntime | Out-Null
    $rollbackInstallManifestPath = Join-PathParts $rollbackRuntime "install-manifest.json"
    $rollbackInstallManifestHash = (Get-FileHash -LiteralPath $rollbackInstallManifestPath -Algorithm SHA256).Hash
    $rollbackBridgeManifestPath = Join-PathParts $rollbackRuntime "agent-skill-bridge-manifest.json"
    $rollbackBridgeManifest = [ordered]@{
        schema_version = 1
        metadata_kind = "agent-specific-skill-link-bridge"
        local_runtime_metadata = $true
        commit_policy = "do-not-commit"
        runtime = Get-NormalizedFullPath -Path $rollbackRuntime
        updated_at_utc = "2000-01-01T00:00:00.0000000Z"
        bridges = @()
    }
    $rollbackBridgeManifestText = ($rollbackBridgeManifest | ConvertTo-Json -Depth 8) + [System.Environment]::NewLine
    [System.IO.File]::WriteAllText($rollbackBridgeManifestPath, $rollbackBridgeManifestText, (New-Object System.Text.UTF8Encoding($false)))

    $manifestLock = $null
    try {
        if ($isWindowsPlatform) {
            $manifestLock = [System.IO.File]::Open(
                $rollbackBridgeManifestPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read
            )
        }
        else {
            & chmod 0444 $rollbackBridgeManifestPath
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to make the rollback bridge manifest read-only."
            }
            & chmod 0555 $rollbackRuntime
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to make the rollback runtime read-only."
            }
        }

        $rollbackRun = Invoke-AgentSkillBridgeFixtureFailure -BridgeScript $bridgeScript -Runtime $rollbackRuntime -Target $rollbackTarget -SkillName "project-bootstrap"
    }
    finally {
        if ($null -ne $manifestLock) {
            $manifestLock.Dispose()
        }
        if (-not $isWindowsPlatform) {
            & chmod 0755 $rollbackRuntime
            & chmod 0644 $rollbackBridgeManifestPath
        }
    }

    Assert-AgentSkillBridgeCondition -Condition ($rollbackRun.exit_code -ne 0) -Message "Locked bridge manifest did not trigger a post-preflight failure."
    Assert-AgentSkillBridgeCondition -Condition (-not (($rollbackRun.output -join "`n").Contains("Bridge preflight failed"))) -Message "Transaction rollback fixture failed during preflight instead of manifest commit."
    Assert-AgentSkillBridgeCondition -Condition (-not (Test-Path -LiteralPath $rollbackTarget)) -Message "Post-preflight failure did not remove the newly created link and empty target root."
    Assert-AgentSkillBridgeCondition -Condition ([System.IO.File]::ReadAllText($rollbackBridgeManifestPath) -eq $rollbackBridgeManifestText) -Message "Post-preflight failure did not preserve or restore the old bridge manifest."
    Assert-AgentSkillBridgeCondition -Condition ((Get-FileHash -LiteralPath $rollbackInstallManifestPath -Algorithm SHA256).Hash -eq $rollbackInstallManifestHash) -Message "Post-preflight failure modified the installer manifest."
    Assert-AgentSkillBridgeCondition -Condition (@(Get-ChildItem -LiteralPath $rollbackRuntime -Filter ".agent-skill-bridge-manifest.*.tmp" -Force).Count -eq 0) -Message "Post-preflight failure left a temporary bridge manifest."
    $evidence.Add([ordered]@{ scenario = "post-preflight-transaction-rollback"; exit_code = $rollbackRun.exit_code; links_remaining = 0; target_root_removed = $true; old_manifest_restored = $true; installer_manifest_unchanged = $true })

    return @($evidence.ToArray())
}
