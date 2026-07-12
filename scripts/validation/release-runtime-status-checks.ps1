function Invoke-RuntimeStatusFixtureChecks {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ScratchRoot
    )

    function Assert-StatusCondition {
        param(
            [Parameter(Mandatory = $true)][bool]$Condition,
            [Parameter(Mandatory = $true)][string]$Message
        )
        if (-not $Condition) { throw $Message }
    }

    function Write-StatusText {
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

    function Write-StatusManifest {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeRoot,
            [Parameter(Mandatory = $true)][object]$Value
        )
        Write-StatusText -Path (Join-PathParts $RuntimeRoot "install-manifest.json") -Text ($Value | ConvertTo-Json -Depth 8)
    }

    function Get-StatusTreeState {
        param([Parameter(Mandatory = $true)][string]$RuntimeRoot)

        if (-not (Test-Path -LiteralPath $RuntimeRoot)) { return @() }
        return @(
            Get-ChildItem -LiteralPath $RuntimeRoot -Recurse -File -Force |
                Sort-Object FullName |
                ForEach-Object {
                    "{0}|{1}" -f (ConvertTo-DisplayPath -Path $_.FullName -Root $RuntimeRoot), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                }
        )
    }

    function Get-BridgeFixtureState {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeRoot,
            [Parameter(Mandatory = $true)][string]$TargetRoot,
            [Parameter(Mandatory = $true)][string]$TargetPath
        )

        $targetItem = Get-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue
        return [ordered]@{
            install_manifest_hash = (Get-FileHash -LiteralPath (Join-PathParts $RuntimeRoot "install-manifest.json") -Algorithm SHA256).Hash
            bridge_manifest_hash = (Get-FileHash -LiteralPath (Join-PathParts $RuntimeRoot "agent-skill-bridge-manifest.json") -Algorithm SHA256).Hash
            link_type = if ($null -eq $targetItem) { $null } else { [string]$targetItem.LinkType }
            link_target = if ($null -eq $targetItem) { $null } else { @($targetItem.Target) -join "|" }
            client_tree = @(Get-StatusTreeState -RuntimeRoot $TargetRoot)
            runtime_tree = @(Get-StatusTreeState -RuntimeRoot $RuntimeRoot)
        }
    }

    function Invoke-Status {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeRoot,
            [switch]$Text
        )
        $arguments = @("-RuntimeDir", $RuntimeRoot)
        if (-not $Text.IsPresent) { $arguments += "-Json" }
        return Invoke-IsolatedPowerShellScript -ScriptPath $statusScript -Arguments $arguments
    }

    function Read-StatusPayload {
        param([Parameter(Mandatory = $true)][object]$Run)
        Assert-StatusCondition -Condition ([int]$Run.exit_code -eq 0) -Message "Runtime status fixture returned non-zero."
        return (@($Run.output) -join [System.Environment]::NewLine) | ConvertFrom-Json
    }

    function New-CurrentManifest {
        return [ordered]@{
            schema_version = 2
            source_identity = "agent-ecosystem"
            release_version = "v0.6.0"
            source_commit = "0123456789abcdef0123456789abcdef01234567"
            install_strategy = "copy"
            profile = "recommended"
            installed_at_utc = "2026-07-12T00:00:00.0000000Z"
            items = @()
        }
    }

    function Write-BridgeStatusManifest {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeRoot,
            [Parameter(Mandatory = $true)][object[]]$Records,
            [string]$RecordedRuntime = $RuntimeRoot
        )
        $value = [ordered]@{
            schema_version = 1
            metadata_kind = "agent-specific-skill-link-bridge"
            local_runtime_metadata = $true
            commit_policy = "do-not-commit"
            runtime = [System.IO.Path]::GetFullPath($RecordedRuntime)
            updated_at_utc = "2026-07-12T00:00:00.0000000Z"
            bridges = @($Records)
        }
        Write-StatusText -Path (Join-PathParts $RuntimeRoot "agent-skill-bridge-manifest.json") -Text ($value | ConvertTo-Json -Depth 8)
    }

    function New-BridgeStatusFixture {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [string[]]$Skills = @("project-bootstrap")
        )
        $runtime = Join-PathParts $fixtureRoot $Name "runtime"
        $targetRoot = Join-PathParts $fixtureRoot $Name "agent-skills"
        $manifest = New-CurrentManifest
        $manifest.skills = @($Skills)
        $manifest.items = @($Skills | ForEach-Object {
                [ordered]@{ name = "skills/$_"; destination = "skills/$_"; mode = "copy"; managed = $true }
            })
        Write-StatusManifest -RuntimeRoot $runtime -Value $manifest
        New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
        $records = @()
        foreach ($skill in $Skills) {
            $source = Join-PathParts $runtime "skills" $skill
            $target = Join-PathParts $targetRoot $skill
            New-Item -ItemType Directory -Force -Path $source | Out-Null
            if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
                New-Item -ItemType Junction -Path $target -Target $source | Out-Null
            }
            else {
                $relative = [System.IO.Path]::GetRelativePath((Split-Path -Parent $target), $source)
                New-Item -ItemType SymbolicLink -Path $target -Target $relative | Out-Null
            }
            $records += [ordered]@{ skill = $skill; source = [System.IO.Path]::GetFullPath($source); target = [System.IO.Path]::GetFullPath($target); result = "created"; link_mode = if ($isWindowsPlatform) { "junction" } else { "symboliclink" } }
        }
        Write-BridgeStatusManifest -RuntimeRoot $runtime -Records $records
        return [ordered]@{ runtime = $runtime; target_root = $targetRoot; records = $records }
    }

    function Remove-BridgeStatusFixtureItem {
        param([Parameter(Mandatory = $true)][string]$Path)
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { return }
        if ($item.PSIsContainer -or $isWindowsPlatform) { [System.IO.Directory]::Delete($item.FullName, $false) }
        else { [System.IO.File]::Delete($item.FullName) }
    }

    $statusScript = Join-PathParts $RepositoryRoot "scripts" "status.ps1"
    $fixtureRoot = Join-PathParts $ScratchRoot "runtime-status-fixtures"
    Assert-PathInsideRoot -Path $fixtureRoot -Root $ScratchRoot
    New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
    $evidence = New-Object 'System.Collections.Generic.List[object]'

    $validRuntime = Join-PathParts $fixtureRoot "valid"
    $validManifest = New-CurrentManifest
    Write-StatusManifest -RuntimeRoot $validRuntime -Value $validManifest
    $beforeState = @(Get-StatusTreeState -RuntimeRoot $validRuntime)
    $validRun = Invoke-Status -RuntimeRoot $validRuntime
    $validPayload = Read-StatusPayload -Run $validRun
    $afterState = @(Get-StatusTreeState -RuntimeRoot $validRuntime)
    Assert-StatusCondition -Condition ([int]$validPayload.schema_version -eq 1 -and [string]$validPayload.runtime.manifest_status -eq "current") -Message "Valid schema-2 manifest did not report current."
    Assert-StatusCondition -Condition ([string]$validPayload.runtime.release_version.value -eq "v0.6.0" -and [string]$validPayload.runtime.release_version.reason -eq "recorded") -Message "Valid release provenance was not reported."
    Assert-StatusCondition -Condition ([string]$validPayload.runtime.source_commit.value -eq "0123456789abcdef0123456789abcdef01234567" -and [string]$validPayload.runtime.source_commit.reason -eq "recorded") -Message "Valid commit provenance was not reported."
    Assert-StatusCondition -Condition (@($validPayload.findings).Count -eq 0) -Message "Valid schema-2 manifest produced findings."
    Assert-StatusCondition -Condition ((@($beforeState) -join "`n") -ceq (@($afterState) -join "`n")) -Message "Runtime status changed the runtime tree."
    $evidence.Add([ordered]@{ scenario = "schema-2-valid-provenance"; status = [string]$validPayload.runtime.manifest_status; findings = @($validPayload.findings).Count })

    $nullRuntime = Join-PathParts $fixtureRoot "null-provenance"
    $nullManifest = New-CurrentManifest
    $nullManifest.release_version = $null
    $nullManifest.source_commit = $null
    Write-StatusManifest -RuntimeRoot $nullRuntime -Value $nullManifest
    $nullPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $nullRuntime)
    Assert-StatusCondition -Condition ([string]$nullPayload.runtime.manifest_status -eq "current") -Message "Null provenance invalidated an otherwise current manifest."
    Assert-StatusCondition -Condition ([string]$nullPayload.runtime.release_version.reason -eq "not-recorded" -and [string]$nullPayload.runtime.source_commit.reason -eq "not-recorded") -Message "Null provenance reasons were incorrect."
    Assert-StatusCondition -Condition ((@($nullPayload.findings | ForEach-Object code) -join ",") -eq "runtime.provenance.release_not_recorded,runtime.provenance.commit_not_recorded") -Message "Null provenance findings were incomplete or unstable."
    $evidence.Add([ordered]@{ scenario = "schema-2-null-provenance"; status = [string]$nullPayload.runtime.manifest_status; findings = @($nullPayload.findings).Count })

    $oldSchemaTwoRuntime = Join-PathParts $fixtureRoot "old-schema-2"
    $oldSchemaTwoManifest = New-CurrentManifest
    $oldSchemaTwoManifest.Remove("release_version")
    $oldSchemaTwoManifest.Remove("source_commit")
    Write-StatusManifest -RuntimeRoot $oldSchemaTwoRuntime -Value $oldSchemaTwoManifest
    $oldSchemaTwoPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $oldSchemaTwoRuntime)
    Assert-StatusCondition -Condition ([string]$oldSchemaTwoPayload.runtime.manifest_status -eq "current" -and [string]$oldSchemaTwoPayload.runtime.release_version.reason -eq "not-recorded" -and [string]$oldSchemaTwoPayload.runtime.source_commit.reason -eq "not-recorded") -Message "Old schema-2 manifest was not backward compatible."
    $evidence.Add([ordered]@{ scenario = "schema-2-missing-provenance"; status = [string]$oldSchemaTwoPayload.runtime.manifest_status })

    $legacyRuntime = Join-PathParts $fixtureRoot "legacy"
    Write-StatusManifest -RuntimeRoot $legacyRuntime -Value ([ordered]@{ schema_version = 1; profile = "minimal" })
    $legacyPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $legacyRuntime)
    Assert-StatusCondition -Condition ([string]$legacyPayload.runtime.manifest_status -eq "legacy" -and [string]$legacyPayload.runtime.release_version.reason -eq "legacy-manifest") -Message "Schema-1 manifest did not report legacy."
    $evidence.Add([ordered]@{ scenario = "schema-1-legacy"; status = [string]$legacyPayload.runtime.manifest_status })

    $missingRuntime = Join-PathParts $fixtureRoot "missing"
    $missingPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $missingRuntime)
    Assert-StatusCondition -Condition ([string]$missingPayload.runtime.manifest_status -eq "missing" -and [string]$missingPayload.runtime.release_version.reason -eq "manifest-missing") -Message "Missing runtime did not fail soft."
    Assert-StatusCondition -Condition (-not (Test-Path -LiteralPath $missingRuntime)) -Message "Runtime status created a missing runtime directory."
    $evidence.Add([ordered]@{ scenario = "missing-runtime"; status = [string]$missingPayload.runtime.manifest_status })

    $malformedRuntime = Join-PathParts $fixtureRoot "malformed"
    Write-StatusText -Path (Join-PathParts $malformedRuntime "install-manifest.json") -Text '{"schema_version":'
    $malformedPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $malformedRuntime)
    Assert-StatusCondition -Condition ([string]$malformedPayload.runtime.manifest_status -eq "invalid" -and [string]$malformedPayload.findings[0].code -eq "runtime.manifest.invalid_json") -Message "Malformed JSON did not fail soft."
    $evidence.Add([ordered]@{ scenario = "malformed-json"; status = [string]$malformedPayload.runtime.manifest_status })

    foreach ($invalidTopLevel in @(
            [ordered]@{ name = "null"; json = "null" },
            [ordered]@{ name = "string"; json = '"invalid"' },
            [ordered]@{ name = "number"; json = "123" },
            [ordered]@{ name = "array"; json = "[]" }
        )) {
        $invalidTopLevelFixture = New-BridgeStatusFixture -Name ("install-manifest-{0}" -f $invalidTopLevel.name)
        Write-StatusText -Path (Join-PathParts $invalidTopLevelFixture.runtime "install-manifest.json") -Text ([string]$invalidTopLevel.json)
        $invalidTopLevelText = @((Invoke-Status -RuntimeRoot $invalidTopLevelFixture.runtime).output) -join "`n"
        $invalidTopLevelPayload = $invalidTopLevelText | ConvertFrom-Json
        Assert-StatusCondition -Condition ([string]$invalidTopLevelPayload.runtime.manifest_status -eq "invalid" -and [string]$invalidTopLevelPayload.bridge.status -eq "unknown" -and [string]$invalidTopLevelPayload.bridge.manifest_status -ne "missing") -Message "Invalid install manifest top-level type did not fail soft with bridge evidence."
        Assert-StatusCondition -Condition (-not $invalidTopLevelText.Contains("ParameterBinding") -and -not $invalidTopLevelText.Contains("Cannot bind argument")) -Message "Invalid install manifest output exposed an exception."
        $evidence.Add([ordered]@{ scenario = "install-manifest-$($invalidTopLevel.name)"; status = [string]$invalidTopLevelPayload.runtime.manifest_status })
    }

    $unsupportedRuntime = Join-PathParts $fixtureRoot "unsupported"
    Write-StatusManifest -RuntimeRoot $unsupportedRuntime -Value ([ordered]@{ schema_version = 3 })
    $unsupportedPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $unsupportedRuntime)
    Assert-StatusCondition -Condition ([string]$unsupportedPayload.runtime.manifest_status -eq "unsupported" -and [string]$unsupportedPayload.runtime.source_commit.reason -eq "unsupported-schema") -Message "Unsupported schema did not fail soft."
    $evidence.Add([ordered]@{ scenario = "unsupported-schema"; status = [string]$unsupportedPayload.runtime.manifest_status })

    $identityRuntime = Join-PathParts $fixtureRoot "identity"
    $identityManifest = New-CurrentManifest
    $identityManifest.source_identity = "C:" + "\Users\private-user\overlay"
    Write-StatusManifest -RuntimeRoot $identityRuntime -Value $identityManifest
    $identityText = (@((Invoke-Status -RuntimeRoot $identityRuntime).output) -join "`n")
    $identityPayload = $identityText | ConvertFrom-Json
    Assert-StatusCondition -Condition ([string]$identityPayload.runtime.manifest_status -eq "invalid" -and $null -eq $identityPayload.runtime.source_identity) -Message "Source identity mismatch was trusted."
    Assert-StatusCondition -Condition (-not $identityText.Contains("private-user") -and -not $identityText.Contains([System.IO.Path]::GetFullPath($identityRuntime))) -Message "Identity mismatch output leaked untrusted or absolute data."
    $evidence.Add([ordered]@{ scenario = "source-identity-mismatch"; status = [string]$identityPayload.runtime.manifest_status })

    $invalidVersionRuntime = Join-PathParts $fixtureRoot "invalid-version"
    $invalidVersionManifest = New-CurrentManifest
    $invalidVersionManifest.release_version = "V0.6.0"
    Write-StatusManifest -RuntimeRoot $invalidVersionRuntime -Value $invalidVersionManifest
    $invalidVersionText = @((Invoke-Status -RuntimeRoot $invalidVersionRuntime).output) -join "`n"
    $invalidVersionPayload = $invalidVersionText | ConvertFrom-Json
    Assert-StatusCondition -Condition ([string]$invalidVersionPayload.runtime.manifest_status -eq "invalid" -and [string]$invalidVersionPayload.runtime.release_version.reason -eq "invalid-value" -and $null -eq $invalidVersionPayload.runtime.release_version.value) -Message "Invalid release version was trusted."
    Assert-StatusCondition -Condition (-not $invalidVersionText.Contains("V0.6.0")) -Message "Non-canonical release version was echoed."
    $evidence.Add([ordered]@{ scenario = "invalid-release-version"; status = [string]$invalidVersionPayload.runtime.manifest_status })

    $invalidCommitRuntime = Join-PathParts $fixtureRoot "invalid-commit"
    $invalidCommitManifest = New-CurrentManifest
    $invalidCommitManifest.source_commit = "not-a-commit-private-user"
    Write-StatusManifest -RuntimeRoot $invalidCommitRuntime -Value $invalidCommitManifest
    $invalidCommitText = @((Invoke-Status -RuntimeRoot $invalidCommitRuntime).output) -join "`n"
    $invalidCommitPayload = $invalidCommitText | ConvertFrom-Json
    Assert-StatusCondition -Condition ([string]$invalidCommitPayload.runtime.source_commit.reason -eq "invalid-value" -and $null -eq $invalidCommitPayload.runtime.source_commit.value) -Message "Invalid commit SHA was trusted."
    Assert-StatusCondition -Condition (-not $invalidCommitText.Contains("private-user")) -Message "Invalid commit SHA was echoed."
    $evidence.Add([ordered]@{ scenario = "invalid-source-commit"; status = [string]$invalidCommitPayload.runtime.manifest_status })

    $invalidStrategyRuntime = Join-PathParts $fixtureRoot "invalid-strategy"
    $invalidStrategyManifest = New-CurrentManifest
    $invalidStrategyManifest.install_strategy = "COPY"
    Write-StatusManifest -RuntimeRoot $invalidStrategyRuntime -Value $invalidStrategyManifest
    $invalidStrategyText = @((Invoke-Status -RuntimeRoot $invalidStrategyRuntime).output) -join "`n"
    $invalidStrategyPayload = $invalidStrategyText | ConvertFrom-Json
    Assert-StatusCondition -Condition ([string]$invalidStrategyPayload.runtime.manifest_status -eq "invalid" -and $null -eq $invalidStrategyPayload.runtime.install_strategy -and [string]$invalidStrategyPayload.findings[0].code -eq "runtime.manifest.install_strategy_invalid") -Message "Non-canonical install strategy was trusted."
    Assert-StatusCondition -Condition (-not $invalidStrategyText.Contains("COPY")) -Message "Non-canonical install strategy was echoed."
    $evidence.Add([ordered]@{ scenario = "non-canonical-install-strategy"; status = [string]$invalidStrategyPayload.runtime.manifest_status })

    $invalidProfileRuntime = Join-PathParts $fixtureRoot "invalid-profile"
    $invalidProfileManifest = New-CurrentManifest
    $invalidProfileManifest.profile = "RECOMMENDED"
    Write-StatusManifest -RuntimeRoot $invalidProfileRuntime -Value $invalidProfileManifest
    $invalidProfileText = @((Invoke-Status -RuntimeRoot $invalidProfileRuntime).output) -join "`n"
    $invalidProfilePayload = $invalidProfileText | ConvertFrom-Json
    Assert-StatusCondition -Condition ([string]$invalidProfilePayload.runtime.manifest_status -eq "invalid" -and $null -eq $invalidProfilePayload.runtime.profile -and [string]$invalidProfilePayload.findings[0].code -eq "runtime.manifest.profile_invalid") -Message "Non-canonical profile was trusted."
    Assert-StatusCondition -Condition (-not $invalidProfileText.Contains("RECOMMENDED")) -Message "Non-canonical profile was echoed."
    $evidence.Add([ordered]@{ scenario = "non-canonical-profile"; status = [string]$invalidProfilePayload.runtime.manifest_status })

    $invalidTimestampRuntime = Join-PathParts $fixtureRoot "invalid-timestamp"
    $invalidTimestampManifest = New-CurrentManifest
    $invalidTimestampManifest.installed_at_utc = "private-user yesterday"
    Write-StatusManifest -RuntimeRoot $invalidTimestampRuntime -Value $invalidTimestampManifest
    $invalidTimestampText = @((Invoke-Status -RuntimeRoot $invalidTimestampRuntime).output) -join "`n"
    $invalidTimestampPayload = $invalidTimestampText | ConvertFrom-Json
    Assert-StatusCondition -Condition ([string]$invalidTimestampPayload.runtime.manifest_status -eq "invalid" -and $null -eq $invalidTimestampPayload.runtime.installed_at_utc) -Message "Invalid timestamp was trusted."
    Assert-StatusCondition -Condition (-not $invalidTimestampText.Contains("private-user")) -Message "Invalid timestamp was echoed."
    $evidence.Add([ordered]@{ scenario = "invalid-timestamp"; status = [string]$invalidTimestampPayload.runtime.manifest_status })

    $textRun = Invoke-Status -RuntimeRoot $nullRuntime -Text
    Assert-StatusCondition -Condition ([int]$textRun.exit_code -eq 0) -Message "Text runtime status returned non-zero."
    $textOutput = @($textRun.output) -join "`n"
    foreach ($expectedLine in @(
            "Runtime manifest: current",
            "Manifest contract: current",
            "Release version: unknown (not recorded)",
            "Source commit: unknown (not recorded)",
            "Install strategy: copy",
            "Profile: recommended",
            "Installed at: 2026-07-12T00:00:00.0000000Z",
            "Findings: 2"
        )) {
        Assert-StatusCondition -Condition ($textOutput.Contains($expectedLine)) -Message "Text output did not match the JSON payload: $expectedLine"
    }
    Assert-StatusCondition -Condition (-not $textOutput.Contains([System.IO.Path]::GetFullPath($nullRuntime)) -and -not $textOutput.Contains([System.Environment]::UserName)) -Message "Text status leaked an absolute path or username."
    $evidence.Add([ordered]@{ scenario = "text-json-semantic-parity"; status = "current" })

    $bridgeCurrent = New-BridgeStatusFixture -Name "bridge-current"
    $currentStateBefore = Get-BridgeFixtureState -RuntimeRoot $bridgeCurrent.runtime -TargetRoot $bridgeCurrent.target_root -TargetPath ([string]$bridgeCurrent.records[0].target)
    $currentPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $bridgeCurrent.runtime)
    Assert-StatusCondition -Condition ([string]$currentPayload.bridge.status -eq "current" -and [string]$currentPayload.bridge.manifest_status -eq "current" -and [int]$currentPayload.bridge.configured_count -eq 1 -and [int]$currentPayload.bridge.counts.current -eq 1) -Message "Live bridge did not report current."
    Assert-StatusCondition -Condition ([string]$currentPayload.bridge.skills[0].skill -eq "project-bootstrap" -and [string]$currentPayload.bridge.skills[0].link_mode -in @("junction", "symboliclink")) -Message "Live bridge skill shape is incorrect."
    $currentStateAfter = Get-BridgeFixtureState -RuntimeRoot $bridgeCurrent.runtime -TargetRoot $bridgeCurrent.target_root -TargetPath ([string]$bridgeCurrent.records[0].target)
    Assert-StatusCondition -Condition (($currentStateBefore | ConvertTo-Json -Depth 8 -Compress) -ceq ($currentStateAfter | ConvertTo-Json -Depth 8 -Compress)) -Message "Status modified a valid bridge fixture."
    $evidence.Add([ordered]@{ scenario = "bridge-current-live-link"; status = [string]$currentPayload.bridge.status })

    $unexpectedTarget = New-BridgeStatusFixture -Name "bridge-target-unexpected"
    $unexpectedDirectory = Join-PathParts $fixtureRoot "bridge-target-unexpected" "other-skill"
    New-Item -ItemType Directory -Force -Path $unexpectedDirectory | Out-Null
    Remove-BridgeStatusFixtureItem -Path ([string]$unexpectedTarget.records[0].target)
    if ($isWindowsPlatform) { New-Item -ItemType Junction -Path ([string]$unexpectedTarget.records[0].target) -Target $unexpectedDirectory | Out-Null }
    else { New-Item -ItemType SymbolicLink -Path ([string]$unexpectedTarget.records[0].target) -Target $unexpectedDirectory | Out-Null }
    $unexpectedStateBefore = Get-BridgeFixtureState -RuntimeRoot $unexpectedTarget.runtime -TargetRoot $unexpectedTarget.target_root -TargetPath ([string]$unexpectedTarget.records[0].target)
    $unexpectedPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $unexpectedTarget.runtime)
    Assert-StatusCondition -Condition ([string]$unexpectedPayload.bridge.status -eq "conflict" -and @($unexpectedPayload.findings | Where-Object code -eq "bridge.target.unexpected").Count -eq 1) -Message "Unexpected live bridge target did not report conflict."
    $unexpectedStateAfter = Get-BridgeFixtureState -RuntimeRoot $unexpectedTarget.runtime -TargetRoot $unexpectedTarget.target_root -TargetPath ([string]$unexpectedTarget.records[0].target)
    Assert-StatusCondition -Condition (($unexpectedStateBefore | ConvertTo-Json -Depth 8 -Compress) -ceq ($unexpectedStateAfter | ConvertTo-Json -Depth 8 -Compress)) -Message "Status modified an anomalous bridge fixture."
    $evidence.Add([ordered]@{ scenario = "bridge-target-unexpected"; status = [string]$unexpectedPayload.bridge.status })

    $danglingTarget = New-BridgeStatusFixture -Name "bridge-target-broken"
    $danglingDirectory = Join-PathParts $fixtureRoot "bridge-target-broken" "temporary-target"
    New-Item -ItemType Directory -Force -Path $danglingDirectory | Out-Null
    Remove-BridgeStatusFixtureItem -Path ([string]$danglingTarget.records[0].target)
    if ($isWindowsPlatform) { New-Item -ItemType Junction -Path ([string]$danglingTarget.records[0].target) -Target $danglingDirectory | Out-Null }
    else { New-Item -ItemType SymbolicLink -Path ([string]$danglingTarget.records[0].target) -Target $danglingDirectory | Out-Null }
    Remove-Item -LiteralPath $danglingDirectory -Force
    $danglingPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $danglingTarget.runtime)
    Assert-StatusCondition -Condition ([string]$danglingPayload.bridge.status -eq "broken" -and @($danglingPayload.findings | Where-Object code -eq "bridge.target.broken").Count -eq 1) -Message "Dangling live bridge target did not report broken."
    $evidence.Add([ordered]@{ scenario = "bridge-target-broken"; status = [string]$danglingPayload.bridge.status })

    $runtimeMismatch = New-BridgeStatusFixture -Name "bridge-runtime-mismatch"
    Write-BridgeStatusManifest -RuntimeRoot $runtimeMismatch.runtime -Records $runtimeMismatch.records -RecordedRuntime (Join-PathParts $fixtureRoot "old-runtime")
    $runtimeMismatchPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $runtimeMismatch.runtime)
    Assert-StatusCondition -Condition ([string]$runtimeMismatchPayload.bridge.status -eq "stale" -and @($runtimeMismatchPayload.findings | Where-Object code -eq "bridge.manifest.runtime_mismatch").Count -eq 1) -Message "Bridge runtime mismatch did not report stale."
    $evidence.Add([ordered]@{ scenario = "bridge-runtime-mismatch"; status = [string]$runtimeMismatchPayload.bridge.status })

    $duplicateBridge = New-BridgeStatusFixture -Name "bridge-record-duplicate"
    Write-BridgeStatusManifest -RuntimeRoot $duplicateBridge.runtime -Records @($duplicateBridge.records[0], $duplicateBridge.records[0])
    $duplicatePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $duplicateBridge.runtime)
    Assert-StatusCondition -Condition ([string]$duplicatePayload.bridge.status -eq "unknown" -and @($duplicatePayload.findings | Where-Object code -eq "bridge.record.duplicate").Count -eq 1) -Message "Duplicate bridge record did not report unknown."
    $evidence.Add([ordered]@{ scenario = "bridge-record-duplicate"; status = [string]$duplicatePayload.bridge.status })

    $unresolvableBridge = New-BridgeStatusFixture -Name "bridge-target-unresolvable-alias"
    Remove-BridgeStatusFixtureItem -Path ([string]$unresolvableBridge.records[0].target)
    $missingAliasTarget = Join-PathParts $fixtureRoot "bridge-target-unresolvable-alias" "missing-target"
    $aliasPath = Join-PathParts $fixtureRoot "bridge-target-unresolvable-alias" "broken-alias"
    New-Item -ItemType Directory -Path $missingAliasTarget | Out-Null
    New-Item -ItemType SymbolicLink -Path $aliasPath -Target $missingAliasTarget | Out-Null
    New-Item -ItemType SymbolicLink -Path ([string]$unresolvableBridge.records[0].target) -Target $aliasPath | Out-Null
    Remove-Item -LiteralPath $missingAliasTarget -Force
    $unresolvablePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $unresolvableBridge.runtime)
    Assert-StatusCondition -Condition ([string]$unresolvablePayload.bridge.status -eq "unknown" -and @($unresolvablePayload.findings | Where-Object code -eq "bridge.target.unresolvable").Count -eq 1) -Message "Unresolvable bridge alias did not fail soft as unknown."
    $evidence.Add([ordered]@{ scenario = "bridge-target-unresolvable-alias"; status = [string]$unresolvablePayload.bridge.status })

    $missingTarget = New-BridgeStatusFixture -Name "bridge-target-missing"
    Remove-BridgeStatusFixtureItem -Path ([string]$missingTarget.records[0].target)
    $missingTargetPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $missingTarget.runtime)
    Assert-StatusCondition -Condition ([string]$missingTargetPayload.bridge.status -eq "stale" -and [string]$missingTargetPayload.findings[-1].code -eq "bridge.target.missing") -Message "Missing bridge target did not report stale."
    $evidence.Add([ordered]@{ scenario = "bridge-target-missing"; status = [string]$missingTargetPayload.bridge.status })

    $nonLink = New-BridgeStatusFixture -Name "bridge-target-not-link"
    Remove-BridgeStatusFixtureItem -Path ([string]$nonLink.records[0].target)
    New-Item -ItemType Directory -Path ([string]$nonLink.records[0].target) | Out-Null
    $nonLinkPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $nonLink.runtime)
    Assert-StatusCondition -Condition ([string]$nonLinkPayload.bridge.status -eq "conflict" -and [string]$nonLinkPayload.findings[-1].code -eq "bridge.target.not_link") -Message "Non-link bridge target did not report conflict."
    $evidence.Add([ordered]@{ scenario = "bridge-target-not-link"; status = [string]$nonLinkPayload.bridge.status })

    $brokenSource = New-BridgeStatusFixture -Name "bridge-source-missing"
    Remove-BridgeStatusFixtureItem -Path ([string]$brokenSource.records[0].target)
    Remove-Item -LiteralPath ([string]$brokenSource.records[0].source) -Force
    $brokenSourcePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $brokenSource.runtime)
    Assert-StatusCondition -Condition ([string]$brokenSourcePayload.bridge.status -eq "broken" -and [string]$brokenSourcePayload.findings[-1].code -eq "bridge.source.missing") -Message "Missing runtime skill source did not report broken."
    $evidence.Add([ordered]@{ scenario = "bridge-source-missing"; status = [string]$brokenSourcePayload.bridge.status })

    $staleSource = New-BridgeStatusFixture -Name "bridge-source-stale"
    $staleSource.records[0].source = [System.IO.Path]::GetFullPath((Join-PathParts $fixtureRoot "old-runtime" "skills" "project-bootstrap"))
    Write-BridgeStatusManifest -RuntimeRoot $staleSource.runtime -Records $staleSource.records
    $staleSourcePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $staleSource.runtime)
    Assert-StatusCondition -Condition ([string]$staleSourcePayload.bridge.status -eq "stale" -and [string]$staleSourcePayload.findings[-1].code -eq "bridge.source.stale") -Message "Historical bridge source did not report stale."
    $evidence.Add([ordered]@{ scenario = "bridge-source-stale"; status = [string]$staleSourcePayload.bridge.status })

    $unmanaged = New-BridgeStatusFixture -Name "bridge-skill-unmanaged"
    $unmanagedManifest = Get-Content -LiteralPath (Join-PathParts $unmanaged.runtime "install-manifest.json") -Raw | ConvertFrom-Json
    $unmanagedManifest.skills = @()
    $unmanagedManifest.items = @()
    Write-StatusManifest -RuntimeRoot $unmanaged.runtime -Value $unmanagedManifest
    $unmanagedPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $unmanaged.runtime)
    Assert-StatusCondition -Condition ([string]$unmanagedPayload.bridge.status -eq "stale" -and [string]$unmanagedPayload.findings[-1].code -eq "bridge.skill.not_managed") -Message "Unmanaged bridge skill did not report stale."
    $evidence.Add([ordered]@{ scenario = "bridge-skill-unmanaged"; status = [string]$unmanagedPayload.bridge.status })

    $malformedBridge = New-BridgeStatusFixture -Name "bridge-manifest-malformed"
    Write-StatusText -Path (Join-PathParts $malformedBridge.runtime "agent-skill-bridge-manifest.json") -Text '{"schema_version":'
    $malformedBridgePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $malformedBridge.runtime)
    Assert-StatusCondition -Condition ([string]$malformedBridgePayload.bridge.status -eq "unknown" -and [string]$malformedBridgePayload.bridge.manifest_status -eq "invalid") -Message "Malformed bridge manifest did not fail soft as unknown."
    $evidence.Add([ordered]@{ scenario = "bridge-manifest-malformed"; status = [string]$malformedBridgePayload.bridge.status })

    $unsupportedBridge = New-BridgeStatusFixture -Name "bridge-manifest-unsupported"
    $unsupportedValue = Get-Content -LiteralPath (Join-PathParts $unsupportedBridge.runtime "agent-skill-bridge-manifest.json") -Raw | ConvertFrom-Json
    $unsupportedValue.schema_version = 2
    Write-StatusText -Path (Join-PathParts $unsupportedBridge.runtime "agent-skill-bridge-manifest.json") -Text ($unsupportedValue | ConvertTo-Json -Depth 8)
    $unsupportedBridgePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $unsupportedBridge.runtime)
    Assert-StatusCondition -Condition ([string]$unsupportedBridgePayload.bridge.status -eq "unknown" -and [string]$unsupportedBridgePayload.bridge.manifest_status -eq "unsupported") -Message "Unsupported bridge manifest did not report unknown."
    $evidence.Add([ordered]@{ scenario = "bridge-manifest-unsupported"; status = [string]$unsupportedBridgePayload.bridge.status })

    $invalidRecord = New-BridgeStatusFixture -Name "bridge-record-invalid"
    Write-BridgeStatusManifest -RuntimeRoot $invalidRecord.runtime -Records @("invalid-record")
    $invalidRecordPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $invalidRecord.runtime)
    Assert-StatusCondition -Condition ([string]$invalidRecordPayload.bridge.status -eq "unknown" -and [string]$invalidRecordPayload.findings[-1].code -eq "bridge.record.invalid") -Message "Invalid bridge record did not fail soft as unknown."
    $evidence.Add([ordered]@{ scenario = "bridge-record-invalid"; status = [string]$invalidRecordPayload.bridge.status })

    $invalidOwnership = New-BridgeStatusFixture -Name "bridge-ownership-invalid"
    Write-StatusText -Path (Join-PathParts $invalidOwnership.runtime "install-manifest.json") -Text '{"schema_version":'
    $invalidOwnershipPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $invalidOwnership.runtime)
    Assert-StatusCondition -Condition ([string]$invalidOwnershipPayload.bridge.status -eq "unknown" -and @($invalidOwnershipPayload.findings | Where-Object code -eq "bridge.record.invalid").Count -eq 1) -Message "Unavailable runtime ownership did not report unknown."
    $evidence.Add([ordered]@{ scenario = "bridge-ownership-unavailable"; status = [string]$invalidOwnershipPayload.bridge.status })

    $invalidIdentityBridge = New-BridgeStatusFixture -Name "bridge-source-identity-invalid"
    $invalidIdentityManifest = Get-Content -LiteralPath (Join-PathParts $invalidIdentityBridge.runtime "install-manifest.json") -Raw | ConvertFrom-Json
    $invalidIdentityManifest.source_identity = "untrusted-runtime"
    Write-StatusManifest -RuntimeRoot $invalidIdentityBridge.runtime -Value $invalidIdentityManifest
    $invalidIdentityPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $invalidIdentityBridge.runtime)
    Assert-StatusCondition -Condition ([string]$invalidIdentityPayload.runtime.manifest_status -eq "invalid" -and [string]$invalidIdentityPayload.bridge.status -eq "unknown" -and [string]$invalidIdentityPayload.bridge.manifest_status -eq "current" -and @($invalidIdentityPayload.findings | Where-Object code -eq "bridge.record.invalid").Count -eq 1) -Message "Invalid source identity suppressed existing bridge manifest status."
    $evidence.Add([ordered]@{ scenario = "bridge-source-identity-invalid"; status = [string]$invalidIdentityPayload.bridge.status })

    foreach ($invalidBridgeTopLevel in @(
            [ordered]@{ name = "null"; json = "null" },
            [ordered]@{ name = "string"; json = '"invalid"' },
            [ordered]@{ name = "number"; json = "123" },
            [ordered]@{ name = "array"; json = "[]" }
        )) {
        $invalidBridgeFixture = New-BridgeStatusFixture -Name ("bridge-manifest-{0}" -f $invalidBridgeTopLevel.name)
        Write-StatusText -Path (Join-PathParts $invalidBridgeFixture.runtime "agent-skill-bridge-manifest.json") -Text ([string]$invalidBridgeTopLevel.json)
        $invalidBridgeText = @((Invoke-Status -RuntimeRoot $invalidBridgeFixture.runtime).output) -join "`n"
        $invalidBridgePayload = $invalidBridgeText | ConvertFrom-Json
        Assert-StatusCondition -Condition ([string]$invalidBridgePayload.bridge.status -eq "unknown" -and [string]$invalidBridgePayload.bridge.manifest_status -eq "invalid" -and @($invalidBridgePayload.findings | Where-Object code -eq "bridge.manifest.invalid").Count -eq 1) -Message "Invalid bridge manifest top-level type did not fail soft."
        Assert-StatusCondition -Condition (-not $invalidBridgeText.Contains("ParameterBinding") -and -not $invalidBridgeText.Contains("Cannot bind argument")) -Message "Invalid bridge manifest output exposed an exception."
        $evidence.Add([ordered]@{ scenario = "bridge-manifest-$($invalidBridgeTopLevel.name)"; status = [string]$invalidBridgePayload.bridge.status })
    }

    $priorityBridge = New-BridgeStatusFixture -Name "bridge-priority" -Skills @("project-bootstrap", "project-context-gate")
    Remove-BridgeStatusFixtureItem -Path ([string]$priorityBridge.records[0].target)
    New-Item -ItemType Directory -Path ([string]$priorityBridge.records[0].target) | Out-Null
    Remove-BridgeStatusFixtureItem -Path ([string]$priorityBridge.records[1].target)
    $priorityPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $priorityBridge.runtime)
    Assert-StatusCondition -Condition ([string]$priorityPayload.bridge.status -eq "conflict" -and [int]$priorityPayload.bridge.counts.conflict -eq 1 -and [int]$priorityPayload.bridge.counts.stale -eq 1) -Message "Bridge overall status priority is unstable."
    Assert-StatusCondition -Condition ((@($priorityPayload.bridge.skills | ForEach-Object skill) -join ',') -eq 'project-bootstrap,project-context-gate') -Message "Bridge skills are not canonically sorted."
    $priorityText = @((Invoke-Status -RuntimeRoot $priorityBridge.runtime -Text).output) -join "`n"
    foreach ($secretValue in @([System.IO.Path]::GetFullPath($priorityBridge.runtime), [System.IO.Path]::GetFullPath($priorityBridge.target_root), [System.Environment]::UserName)) {
        Assert-StatusCondition -Condition (-not $priorityText.Contains($secretValue)) -Message "Bridge text output leaked local path data."
    }
    $priorityJson = @((Invoke-Status -RuntimeRoot $priorityBridge.runtime).output) -join "`n"
    Assert-StatusCondition -Condition (-not $priorityJson.Contains([System.IO.Path]::GetFullPath($priorityBridge.target_root))) -Message "Bridge JSON output leaked a target path."
    $evidence.Add([ordered]@{ scenario = "bridge-priority-public-safe"; status = [string]$priorityPayload.bridge.status })

    $allowedStatuses = @("current", "legacy", "missing", "invalid", "unsupported")
    $allowedReasons = @("recorded", "not-recorded", "legacy-manifest", "manifest-missing", "manifest-invalid", "unsupported-schema", "invalid-value")
    $allowedSeverities = @("info", "warning", "error")
    foreach ($runtimeDir in @(Get-ChildItem -LiteralPath $fixtureRoot -Directory)) {
        $run = Invoke-Status -RuntimeRoot $runtimeDir.FullName
        $payload = Read-StatusPayload -Run $run
        Assert-StatusCondition -Condition ([string]$payload.runtime.manifest_status -in $allowedStatuses) -Message "Unexpected manifest status enum."
        Assert-StatusCondition -Condition ([string]$payload.runtime.release_version.reason -in $allowedReasons -and [string]$payload.runtime.source_commit.reason -in $allowedReasons) -Message "Unexpected provenance reason enum."
        Assert-StatusCondition -Condition (@($payload.findings | Where-Object { [string]$_.severity -notin $allowedSeverities }).Count -eq 0) -Message "Unexpected finding severity enum."
    }

    return @($evidence.ToArray())
}
