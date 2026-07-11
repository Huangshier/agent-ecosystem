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
    $invalidVersionManifest.release_version = "C:" + "\Users\private-user\v9"
    Write-StatusManifest -RuntimeRoot $invalidVersionRuntime -Value $invalidVersionManifest
    $invalidVersionText = @((Invoke-Status -RuntimeRoot $invalidVersionRuntime).output) -join "`n"
    $invalidVersionPayload = $invalidVersionText | ConvertFrom-Json
    Assert-StatusCondition -Condition ([string]$invalidVersionPayload.runtime.manifest_status -eq "invalid" -and [string]$invalidVersionPayload.runtime.release_version.reason -eq "invalid-value" -and $null -eq $invalidVersionPayload.runtime.release_version.value) -Message "Invalid release version was trusted."
    Assert-StatusCondition -Condition (-not $invalidVersionText.Contains("private-user")) -Message "Invalid release version was echoed."
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

    $invalidFieldsRuntime = Join-PathParts $fixtureRoot "invalid-fields"
    $invalidFieldsManifest = New-CurrentManifest
    $invalidFieldsManifest.install_strategy = "C:" + "\Users\private-user\link"
    $invalidFieldsManifest.profile = @("recommended")
    Write-StatusManifest -RuntimeRoot $invalidFieldsRuntime -Value $invalidFieldsManifest
    $invalidFieldsText = @((Invoke-Status -RuntimeRoot $invalidFieldsRuntime).output) -join "`n"
    $invalidFieldsPayload = $invalidFieldsText | ConvertFrom-Json
    Assert-StatusCondition -Condition ([string]$invalidFieldsPayload.runtime.manifest_status -eq "invalid" -and $null -eq $invalidFieldsPayload.runtime.install_strategy -and $null -eq $invalidFieldsPayload.runtime.profile) -Message "Invalid strategy or profile was trusted."
    Assert-StatusCondition -Condition (-not $invalidFieldsText.Contains("private-user")) -Message "Invalid runtime field was echoed."
    $evidence.Add([ordered]@{ scenario = "invalid-strategy-profile"; status = [string]$invalidFieldsPayload.runtime.manifest_status })

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
