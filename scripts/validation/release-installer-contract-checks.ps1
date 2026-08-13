function Invoke-InstallerContractFixtureChecks {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ScratchRoot,
        [switch]$SkipDevLink
    )

    function Assert-InstallerCondition {
        param(
            [Parameter(Mandatory = $true)][bool]$Condition,
            [Parameter(Mandatory = $true)][string]$Message
        )
        if (-not $Condition) {
            throw $Message
        }
    }

    function Write-FixtureText {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Text
        )
        $parent = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
    }

    function Invoke-FixtureInstall {
        param(
            [Parameter(Mandatory = $true)][string]$Installer,
            [Parameter(Mandatory = $true)][string]$RuntimeRoot,
            [string]$Profile = "minimal",
            [string[]]$AdditionalArguments = @()
        )
        $arguments = @("-Profile", $Profile, "-TargetDir", $RuntimeRoot) + @($AdditionalArguments)
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            return Invoke-IsolatedPowerShellScript -ScriptPath $Installer -Arguments $arguments
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }

    function Invoke-FixtureUninstall {
        param(
            [Parameter(Mandatory = $true)][string]$Uninstaller,
            [Parameter(Mandatory = $true)][string]$RuntimeRoot,
            [string[]]$AdditionalArguments = @()
        )
        $arguments = @("-TargetDir", $RuntimeRoot) + @($AdditionalArguments)
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            return Invoke-IsolatedPowerShellScript -ScriptPath $Uninstaller -Arguments $arguments
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }

    function Read-InstallArtifact {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeRoot,
            [ValidateSet("install-manifest.json", "install-report.json")]
            [string]$Name
        )
        return Get-Content -LiteralPath (Join-PathParts $RuntimeRoot $Name) -Raw | ConvertFrom-Json
    }

    function Assert-ReportCountConsistency {
        param([Parameter(Mandatory = $true)][object]$Report)
        foreach ($field in @("updated", "unchanged", "preserved_unknown", "skipped_locally_modified", "conflicts")) {
            $actual = @($Report.$field).Count
            $recorded = [int]$Report.counts.$field
            if ($actual -ne $recorded) {
                throw "install-report count mismatch for ${field}: expected $actual, got $recorded."
            }
        }
    }

    function Test-ReportPath {
        param(
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Values,
            [Parameter(Mandatory = $true)][string]$Path
        )
        return @($Values | Where-Object { [string]$_ -eq $Path }).Count -gt 0
    }

    function Test-FixtureReparsePoint {
        param([Parameter(Mandatory = $true)][string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) {
            return $false
        }
        $item = Get-Item -LiteralPath $Path -Force
        return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
    }

    function Assert-ManifestFileHashes {
        param(
            [Parameter(Mandatory = $true)][object]$Manifest,
            [Parameter(Mandatory = $true)][string]$RuntimeRoot
        )
        foreach ($item in @($Manifest.items | Where-Object { [string]$_.mode -eq "copy" })) {
            foreach ($file in @($item.files)) {
                $installedPath = Join-PathParts $RuntimeRoot ([string]$item.destination) ([string]$file.path)
                Assert-InstallerCondition -Condition (Test-Path -LiteralPath $installedPath -PathType Leaf) -Message "Manifest managed file is missing."
                $actualHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash.ToLowerInvariant()
                Assert-InstallerCondition -Condition ($actualHash -eq [string]$file.installed_sha256) -Message "Manifest installed hash does not match runtime content."
            }
        }
    }

    function New-GitProvenanceFixture {
        param(
            [Parameter(Mandatory = $true)][string]$TemplateRoot,
            [Parameter(Mandatory = $true)][string]$SourceRoot,
            [AllowNull()][string]$VersionTag
        )

        Copy-Item -LiteralPath $TemplateRoot -Destination $SourceRoot -Recurse
        & git -C $SourceRoot init --quiet
        if ($LASTEXITCODE -ne 0) { throw "Unable to initialize provenance Git fixture." }
        & git -C $SourceRoot config user.name "Installer Fixture"
        & git -C $SourceRoot config user.email "installer-fixture@example.invalid"
        & git -C $SourceRoot add --all
        & git -C $SourceRoot commit --quiet -m "fixture"
        if ($LASTEXITCODE -ne 0) { throw "Unable to commit provenance Git fixture." }
        if (-not [string]::IsNullOrWhiteSpace($VersionTag)) {
            & git -C $SourceRoot tag $VersionTag
            if ($LASTEXITCODE -ne 0) { throw "Unable to tag provenance Git fixture." }
        }
        return @(& git -C $SourceRoot rev-parse HEAD)[0]
    }

    $fixtureSource = Join-PathParts $ScratchRoot "installer-contract-source"
    $runtimeRoot = Join-PathParts $ScratchRoot "installer-contract-runtime"
    $profileShrinkRuntime = Join-PathParts $ScratchRoot "installer-contract-profile-shrink-runtime"
    $rootConflictRuntime = Join-PathParts $ScratchRoot "installer-contract-root-conflict-runtime"
    $devLinkRuntime = Join-PathParts $ScratchRoot "installer-contract-dev-link-runtime"
    $legacyLinkRuntime = Join-PathParts $ScratchRoot "installer-contract-legacy-link-runtime"
    $legacyRuntime = Join-PathParts $ScratchRoot "installer-contract-legacy-runtime"
    $taggedSource = Join-PathParts $ScratchRoot "installer-provenance-tagged-source"
    $taggedRuntime = Join-PathParts $ScratchRoot "installer-provenance-tagged-runtime"
    $uppercaseTagSource = Join-PathParts $ScratchRoot "installer-provenance-uppercase-tag-source"
    $uppercaseTagRuntime = Join-PathParts $ScratchRoot "installer-provenance-uppercase-tag-runtime"
    $ambiguousTagRuntime = Join-PathParts $ScratchRoot "installer-provenance-ambiguous-tag-runtime"
    $untaggedSource = Join-PathParts $ScratchRoot "installer-provenance-untagged-source"
    $untaggedRuntime = Join-PathParts $ScratchRoot "installer-provenance-untagged-runtime"
    $dirtySource = Join-PathParts $ScratchRoot "installer-provenance-dirty-source"
    $dirtyRuntime = Join-PathParts $ScratchRoot "installer-provenance-dirty-runtime"
    foreach ($path in @($fixtureSource, $runtimeRoot, $profileShrinkRuntime, $rootConflictRuntime, $devLinkRuntime, $legacyLinkRuntime, $legacyRuntime, $taggedSource, $taggedRuntime, $uppercaseTagSource, $uppercaseTagRuntime, $ambiguousTagRuntime, $untaggedSource, $untaggedRuntime, $dirtySource, $dirtyRuntime)) {
        Assert-PathInsideRoot -Path $path -Root $ScratchRoot
    }

    New-Item -ItemType Directory -Force -Path (Join-PathParts $fixtureSource "scripts" "lib") | Out-Null
    Copy-Item -LiteralPath (Join-PathParts $RepositoryRoot "scripts" "install.ps1") -Destination (Join-PathParts $fixtureSource "scripts" "install.ps1") -Force
    Copy-Item -LiteralPath (Join-PathParts $RepositoryRoot "scripts" "uninstall.ps1") -Destination (Join-PathParts $fixtureSource "scripts" "uninstall.ps1") -Force
    Copy-Item -LiteralPath (Join-PathParts $RepositoryRoot "scripts" "lib" "path-guard.ps1") -Destination (Join-PathParts $fixtureSource "scripts" "lib" "path-guard.ps1") -Force
    Write-FixtureText -Path (Join-PathParts $fixtureSource "scripts" "status.ps1") -Text "Write-Output 'fixture status provider'"
    Write-FixtureText -Path (Join-PathParts $fixtureSource "scripts" "lib" "runtime-status-action.ps1") -Text "function Get-FixtureRuntimeStatusAction { return 'none' }"
    Write-FixtureText -Path (Join-PathParts $fixtureSource "scripts" "migrate-project.ps1") -Text "Write-Output 'fixture migrate project'"
    Write-FixtureText -Path (Join-PathParts $fixtureSource "scripts" "validation" "powershell-runtime-requirement.ps1") -Text "function Get-FixturePwshRequirement { return 'ok' }"

    $hubManagedSource = Join-PathParts $fixtureSource "knowledge-hub" "managed.txt"
    $hubStableSource = Join-PathParts $fixtureSource "knowledge-hub" "stable.txt"
    $skillManagedSource = Join-PathParts $fixtureSource "skills" "project-bootstrap" "managed.txt"
    Write-FixtureText -Path $hubManagedSource -Text "source-a"
    Write-FixtureText -Path $hubStableSource -Text "stable"
    Write-FixtureText -Path $skillManagedSource -Text "skill-a"
    Write-FixtureText -Path (Join-PathParts $fixtureSource "skills" "project-workspace" "managed.txt") -Text "workspace-a"
    Write-FixtureText -Path (Join-PathParts $fixtureSource "templates" "project" "assets" "spec.md") -Text "template-a"
    Write-FixtureText -Path (Join-PathParts $fixtureSource "schemas" "project-workspace" "spec.v1.schema.json") -Text "{ }"

    $installer = Join-PathParts $fixtureSource "scripts" "install.ps1"
    $uninstaller = Join-PathParts $fixtureSource "scripts" "uninstall.ps1"
    $scenarioEvidence = New-Object 'System.Collections.Generic.List[object]'

    $fresh = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot
    Assert-InstallerCondition -Condition ($fresh.exit_code -eq 0) -Message "Fresh default copy install failed."
    $manifestText = Get-Content -LiteralPath (Join-PathParts $runtimeRoot "install-manifest.json") -Raw
    $reportText = Get-Content -LiteralPath (Join-PathParts $runtimeRoot "install-report.json") -Raw
    $manifest = $manifestText | ConvertFrom-Json
    $report = $reportText | ConvertFrom-Json
    Assert-InstallerCondition -Condition ([int]$manifest.schema_version -eq 2) -Message "Fresh install did not write manifest schema 2."
    Assert-InstallerCondition -Condition ([string]$manifest.install_strategy -eq "copy") -Message "Fresh default install did not record copy strategy."
    Assert-InstallerCondition -Condition ([string]$manifest.target_dir -eq ".") -Message "Manifest target_dir is not runtime-relative."
    Assert-InstallerCondition -Condition ([string]$report.status -eq "success") -Message "Fresh default install did not report success."
    Assert-InstallerCondition -Condition (-not (Test-FixtureReparsePoint -Path (Join-PathParts $runtimeRoot "knowledge-hub"))) -Message "Default knowledge-hub install is a link."
    $runtimeFull = [System.IO.Path]::GetFullPath($runtimeRoot)
    $repositoryFull = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    Assert-InstallerCondition -Condition (-not $runtimeFull.StartsWith($repositoryFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) -Message "Default installed runtime is inside the source worktree."
    Assert-InstallerCondition -Condition (-not $manifestText.Contains([System.IO.Path]::GetFullPath($fixtureSource))) -Message "Manifest leaked the source fixture path."
    Assert-InstallerCondition -Condition (-not $manifestText.Contains($runtimeFull)) -Message "Manifest leaked the runtime path."
    Assert-InstallerCondition -Condition (-not $reportText.Contains([System.IO.Path]::GetFullPath($fixtureSource))) -Message "Install report leaked the source fixture path."
    Assert-InstallerCondition -Condition (-not $reportText.Contains($runtimeFull)) -Message "Install report leaked the runtime path."
    Assert-InstallerCondition -Condition ($null -eq $manifest.release_version -and $null -eq $manifest.source_commit) -Message "Non-Git source provenance was guessed."
    Assert-ReportCountConsistency -Report $report
    $scenarioEvidence.Add([ordered]@{ scenario = "fresh-default-copy"; exit_code = $fresh.exit_code; status = [string]$report.status; updated = [int]$report.counts.updated })

    $manifest.PSObject.Properties.Remove("release_version")
    $manifest.PSObject.Properties.Remove("source_commit")
    Write-FixtureText -Path (Join-PathParts $runtimeRoot "install-manifest.json") -Text ($manifest | ConvertTo-Json -Depth 12)
    $schemaTwoCompatibility = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot
    $manifest = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-manifest.json"
    Assert-InstallerCondition -Condition ($schemaTwoCompatibility.exit_code -eq 0) -Message "Schema-2 manifest without provenance fields was rejected."
    Assert-InstallerCondition -Condition ($null -ne $manifest.PSObject.Properties["release_version"] -and $null -ne $manifest.PSObject.Properties["source_commit"]) -Message "Schema-2 rerun did not add provenance fields."
    Assert-InstallerCondition -Condition ($null -eq $manifest.release_version -and $null -eq $manifest.source_commit) -Message "Schema-2 compatibility rerun guessed provenance."
    $scenarioEvidence.Add([ordered]@{ scenario = "schema-2-missing-provenance-compatible"; exit_code = $schemaTwoCompatibility.exit_code; schema_version = [int]$manifest.schema_version })

    $taggedCommit = New-GitProvenanceFixture -TemplateRoot $fixtureSource -SourceRoot $taggedSource -VersionTag "v9.8.7"
    $taggedRun = Invoke-FixtureInstall -Installer (Join-PathParts $taggedSource "scripts" "install.ps1") -RuntimeRoot $taggedRuntime
    $taggedManifestText = Get-Content -LiteralPath (Join-PathParts $taggedRuntime "install-manifest.json") -Raw
    $taggedManifest = $taggedManifestText | ConvertFrom-Json
    Assert-InstallerCondition -Condition ($taggedRun.exit_code -eq 0 -and [string]$taggedManifest.release_version -eq "v9.8.7") -Message "Exact version tag provenance was not recorded."
    Assert-InstallerCondition -Condition ([string]$taggedManifest.source_commit -eq [string]$taggedCommit -and [string]$taggedManifest.source_commit -match '^[0-9a-f]{40}$') -Message "Tagged source commit provenance was not recorded as a full SHA."
    Assert-InstallerCondition -Condition (-not $taggedManifestText.Contains([System.IO.Path]::GetFullPath($taggedSource)) -and -not $taggedManifestText.Contains([System.IO.Path]::GetFullPath($taggedRuntime))) -Message "Tagged provenance manifest leaked an absolute path."
    $scenarioEvidence.Add([ordered]@{ scenario = "clean-git-exact-version-tag"; exit_code = $taggedRun.exit_code; release_version = [string]$taggedManifest.release_version; source_commit = [string]$taggedManifest.source_commit })

    $uppercaseTagCommit = New-GitProvenanceFixture -TemplateRoot $fixtureSource -SourceRoot $uppercaseTagSource -VersionTag "V9.8.7"
    $uppercaseTagRun = Invoke-FixtureInstall -Installer (Join-PathParts $uppercaseTagSource "scripts" "install.ps1") -RuntimeRoot $uppercaseTagRuntime
    $uppercaseTagManifest = Read-InstallArtifact -RuntimeRoot $uppercaseTagRuntime -Name "install-manifest.json"
    Assert-InstallerCondition -Condition ($uppercaseTagRun.exit_code -eq 0 -and $null -eq $uppercaseTagManifest.release_version) -Message "Non-canonical uppercase version tag was recorded."
    Assert-InstallerCondition -Condition ([string]$uppercaseTagManifest.source_commit -eq [string]$uppercaseTagCommit -and [string]$uppercaseTagManifest.source_commit -match '^[0-9a-f]{40}$') -Message "Uppercase version tag discarded reliable source commit provenance."
    $scenarioEvidence.Add([ordered]@{ scenario = "clean-git-uppercase-version-tag"; exit_code = $uppercaseTagRun.exit_code; source_commit = [string]$uppercaseTagManifest.source_commit })

    & git -C $taggedSource tag "v9.8.8"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create ambiguous provenance tag fixture." }
    $ambiguousTagRun = Invoke-FixtureInstall -Installer (Join-PathParts $taggedSource "scripts" "install.ps1") -RuntimeRoot $ambiguousTagRuntime
    $ambiguousTagManifest = Read-InstallArtifact -RuntimeRoot $ambiguousTagRuntime -Name "install-manifest.json"
    Assert-InstallerCondition -Condition ($ambiguousTagRun.exit_code -eq 0 -and $null -eq $ambiguousTagManifest.release_version -and $null -eq $ambiguousTagManifest.source_commit) -Message "Ambiguous exact version tags produced guessed provenance."
    $scenarioEvidence.Add([ordered]@{ scenario = "clean-git-ambiguous-version-tags"; exit_code = $ambiguousTagRun.exit_code })

    $untaggedCommit = New-GitProvenanceFixture -TemplateRoot $fixtureSource -SourceRoot $untaggedSource -VersionTag $null
    $untaggedRun = Invoke-FixtureInstall -Installer (Join-PathParts $untaggedSource "scripts" "install.ps1") -RuntimeRoot $untaggedRuntime
    $untaggedManifest = Read-InstallArtifact -RuntimeRoot $untaggedRuntime -Name "install-manifest.json"
    Assert-InstallerCondition -Condition ($untaggedRun.exit_code -eq 0 -and $null -eq $untaggedManifest.release_version -and [string]$untaggedManifest.source_commit -eq [string]$untaggedCommit) -Message "Clean untagged Git provenance was incorrect."
    $scenarioEvidence.Add([ordered]@{ scenario = "clean-git-untagged"; exit_code = $untaggedRun.exit_code; source_commit = [string]$untaggedManifest.source_commit })

    $null = New-GitProvenanceFixture -TemplateRoot $fixtureSource -SourceRoot $dirtySource -VersionTag "v9.8.6"
    Write-FixtureText -Path (Join-PathParts $dirtySource "knowledge-hub" "managed.txt") -Text "dirty-source"
    $dirtyRun = Invoke-FixtureInstall -Installer (Join-PathParts $dirtySource "scripts" "install.ps1") -RuntimeRoot $dirtyRuntime
    $dirtyManifest = Read-InstallArtifact -RuntimeRoot $dirtyRuntime -Name "install-manifest.json"
    Assert-InstallerCondition -Condition ($dirtyRun.exit_code -eq 0 -and $null -eq $dirtyManifest.release_version -and $null -eq $dirtyManifest.source_commit) -Message "Dirty Git source provenance was guessed."
    $scenarioEvidence.Add([ordered]@{ scenario = "dirty-git-source"; exit_code = $dirtyRun.exit_code })

    $copyCompatibility = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot -AdditionalArguments @("-Copy")
    Assert-InstallerCondition -Condition ($copyCompatibility.exit_code -eq 0) -Message "Existing -Copy invocation failed."
    $report = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-report.json"
    Assert-InstallerCondition -Condition ([int]$report.counts.updated -eq 0) -Message "Unchanged -Copy rerun rewrote managed files."
    Assert-InstallerCondition -Condition ([int]$report.counts.unchanged -eq 3) -Message "Unchanged rerun did not report all managed files unchanged."
    $scenarioEvidence.Add([ordered]@{ scenario = "unchanged-rerun-copy-compat"; exit_code = $copyCompatibility.exit_code; status = [string]$report.status; unchanged = [int]$report.counts.unchanged })

    $missingTarget = Join-PathParts $runtimeRoot "knowledge-hub" "stable.txt"
    Remove-Item -LiteralPath $missingTarget -Force
    $missingRepair = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot
    $report = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-report.json"
    Assert-InstallerCondition -Condition ($missingRepair.exit_code -eq 0 -and (Test-Path -LiteralPath $missingTarget)) -Message "Missing managed file was not restored."
    Assert-InstallerCondition -Condition (Test-ReportPath -Values @($report.updated) -Path "knowledge-hub/stable.txt") -Message "Restored managed file was not reported as updated."
    $scenarioEvidence.Add([ordered]@{ scenario = "missing-managed-file"; exit_code = $missingRepair.exit_code; status = [string]$report.status })

    $stableTimestamp = [DateTime]::SpecifyKind([DateTime]"2020-01-02T03:04:05", [DateTimeKind]::Utc)
    [System.IO.File]::SetLastWriteTimeUtc($missingTarget, $stableTimestamp)
    Write-FixtureText -Path $hubManagedSource -Text "source-b"
    $sourceChanged = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot
    $report = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-report.json"
    Assert-InstallerCondition -Condition ($sourceChanged.exit_code -eq 0) -Message "Source-changed target-unchanged rerun failed."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath (Join-PathParts $runtimeRoot "knowledge-hub" "managed.txt") -Raw) -eq "source-b") -Message "Source-changed managed file was not updated."
    Assert-InstallerCondition -Condition ([System.IO.File]::GetLastWriteTimeUtc($missingTarget) -eq $stableTimestamp) -Message "Unchanged managed file was rewritten."
    Assert-InstallerCondition -Condition (Test-ReportPath -Values @($report.updated) -Path "knowledge-hub/managed.txt") -Message "Source-changed file missing from updated report."
    Assert-InstallerCondition -Condition (Test-ReportPath -Values @($report.unchanged) -Path "knowledge-hub/stable.txt") -Message "Stable file missing from unchanged report."
    $scenarioEvidence.Add([ordered]@{ scenario = "source-changed-target-unchanged"; exit_code = $sourceChanged.exit_code; status = [string]$report.status })

    $unknownFile = Join-PathParts $runtimeRoot "knowledge-hub" "user-note.txt"
    Write-FixtureText -Path $unknownFile -Text "preserve-me"
    $unknownRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot
    $report = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-report.json"
    Assert-InstallerCondition -Condition ($unknownRun.exit_code -eq 0) -Message "Unknown-file warning run returned non-zero."
    Assert-InstallerCondition -Condition ([string]$report.status -eq "warning") -Message "Unknown file did not produce warning status."
    Assert-InstallerCondition -Condition ((Test-Path -LiteralPath $unknownFile) -and (Test-ReportPath -Values @($report.preserved_unknown) -Path "knowledge-hub/user-note.txt")) -Message "Unknown file was not preserved and reported."
    $scenarioEvidence.Add([ordered]@{ scenario = "unknown-file-preserved"; exit_code = $unknownRun.exit_code; status = [string]$report.status; preserved_unknown = [int]$report.counts.preserved_unknown })

    $managedTarget = Join-PathParts $runtimeRoot "knowledge-hub" "managed.txt"
    Write-FixtureText -Path $managedTarget -Text "local-b"
    $localModified = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot
    $report = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-report.json"
    Assert-InstallerCondition -Condition ($localModified.exit_code -eq 0) -Message "Locally modified/source-unchanged rerun returned non-zero."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath $managedTarget -Raw) -eq "local-b") -Message "Locally modified managed file was overwritten."
    Assert-InstallerCondition -Condition ((Test-ReportPath -Values @($report.skipped_locally_modified) -Path "knowledge-hub/managed.txt") -and [int]$report.counts.conflicts -eq 0) -Message "Local modification was not reported as a non-conflicting skip."
    $scenarioEvidence.Add([ordered]@{ scenario = "locally-modified-source-unchanged"; exit_code = $localModified.exit_code; status = [string]$report.status })

    Write-FixtureText -Path $hubManagedSource -Text "source-c"
    $conflictRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot
    $report = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-report.json"
    Assert-InstallerCondition -Condition ($conflictRun.exit_code -ne 0) -Message "Default conflict did not return non-zero."
    Assert-InstallerCondition -Condition ([string]$report.status -eq "conflict") -Message "Default conflict did not write conflict status."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath $managedTarget -Raw) -eq "local-b") -Message "Default conflict overwrote the locally modified target."
    Assert-InstallerCondition -Condition ((Test-ReportPath -Values @($report.conflicts) -Path "knowledge-hub/managed.txt") -and (Test-ReportPath -Values @($report.skipped_locally_modified) -Path "knowledge-hub/managed.txt")) -Message "Default conflict was not recorded consistently."
    Assert-ReportCountConsistency -Report $report
    $scenarioEvidence.Add([ordered]@{ scenario = "source-and-target-conflict"; exit_code = $conflictRun.exit_code; status = [string]$report.status; conflicts = [int]$report.counts.conflicts })

    $allowPartialRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot -AdditionalArguments @("-AllowPartial")
    $report = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-report.json"
    Assert-InstallerCondition -Condition ($allowPartialRun.exit_code -eq 0) -Message "-AllowPartial conflict returned non-zero."
    Assert-InstallerCondition -Condition ([string]$report.status -eq "conflict" -and [bool]$report.allow_partial) -Message "-AllowPartial did not preserve conflict status."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath $managedTarget -Raw) -eq "local-b") -Message "-AllowPartial overwrote the conflict."
    $scenarioEvidence.Add([ordered]@{ scenario = "allow-partial-conflict"; exit_code = $allowPartialRun.exit_code; status = [string]$report.status })

    $replaceRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot -AdditionalArguments @("-ReplaceManaged")
    $report = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-report.json"
    Assert-InstallerCondition -Condition ($replaceRun.exit_code -eq 0) -Message "-ReplaceManaged run failed."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath $managedTarget -Raw) -eq "source-c") -Message "-ReplaceManaged did not overwrite the managed conflict."
    Assert-InstallerCondition -Condition (Test-Path -LiteralPath $unknownFile) -Message "-ReplaceManaged removed an unknown file."
    Assert-InstallerCondition -Condition ([int]$report.counts.conflicts -eq 0) -Message "-ReplaceManaged left a conflict in the report."
    $scenarioEvidence.Add([ordered]@{ scenario = "replace-managed"; exit_code = $replaceRun.exit_code; status = [string]$report.status; preserved_unknown = [int]$report.counts.preserved_unknown })

    Write-FixtureText -Path $managedTarget -Text "local-c"
    Write-FixtureText -Path $hubManagedSource -Text "source-d"
    $forceRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot -AdditionalArguments @("-Force")
    $report = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-report.json"
    $forceWarning = "WARNING: -Force is deprecated for full reinstall semantics; treating it as -ReplaceManaged. Use -ReplaceManaged explicitly in new scripts."
    Assert-InstallerCondition -Condition ($forceRun.exit_code -eq 0) -Message "Compatibility -Force run failed."
    Assert-InstallerCondition -Condition (@($forceRun.output | Where-Object { [string]$_ -like "*$forceWarning*" }).Count -eq 1) -Message "Compatibility -Force warning was missing or repeated."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath $managedTarget -Raw) -eq "source-d") -Message "Compatibility -Force did not map to -ReplaceManaged."
    Assert-InstallerCondition -Condition (Test-Path -LiteralPath $unknownFile) -Message "Compatibility -Force removed an unknown file."
    Assert-InstallerCondition -Condition (Test-ReportPath -Values @($report.warnings) -Path $forceWarning) -Message "Compatibility warning missing from install report."
    Assert-ReportCountConsistency -Report $report
    $manifest = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-manifest.json"
    Assert-ManifestFileHashes -Manifest $manifest -RuntimeRoot $runtimeRoot
    $scenarioEvidence.Add([ordered]@{ scenario = "force-compatibility"; exit_code = $forceRun.exit_code; status = [string]$report.status; warning_count = @($report.warnings).Count })

    $collidingUnknownSource = Join-PathParts $fixtureSource "knowledge-hub" "user-note.txt"
    Write-FixtureText -Path $collidingUnknownSource -Text "source-collision"
    $unknownCollisionRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $runtimeRoot -AdditionalArguments @("-ReplaceManaged")
    $report = Read-InstallArtifact -RuntimeRoot $runtimeRoot -Name "install-report.json"
    Assert-InstallerCondition -Condition ($unknownCollisionRun.exit_code -ne 0) -Message "-ReplaceManaged overwrote a source-colliding unknown file without conflict."
    Assert-InstallerCondition -Condition ([string]$report.status -eq "conflict") -Message "Source-colliding unknown file did not retain conflict status."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath $unknownFile -Raw) -eq "preserve-me") -Message "-ReplaceManaged overwrote a source-colliding unknown file."
    Assert-InstallerCondition -Condition ((Test-ReportPath -Values @($report.preserved_unknown) -Path "knowledge-hub/user-note.txt") -and (Test-ReportPath -Values @($report.conflicts) -Path "knowledge-hub/user-note.txt")) -Message "Source-colliding unknown file was not preserved and reported as a conflict."
    Remove-Item -LiteralPath $collidingUnknownSource -Force
    $scenarioEvidence.Add([ordered]@{ scenario = "replace-managed-preserves-source-colliding-unknown"; exit_code = $unknownCollisionRun.exit_code; status = [string]$report.status })

    $recommendedInstall = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $profileShrinkRuntime -Profile "recommended"
    Assert-InstallerCondition -Condition ($recommendedInstall.exit_code -eq 0) -Message "Recommended profile setup for shrink fixture failed."
    $recommendedManifest = Read-InstallArtifact -RuntimeRoot $profileShrinkRuntime -Name "install-manifest.json"
    Assert-InstallerCondition -Condition ([string]$recommendedManifest.workspace.architecture -ceq "c3.3" -and [string]$recommendedManifest.workspace.lifecycle -ceq "active" -and [bool]$recommendedManifest.workspace.default_cutover) -Message "Recommended manifest did not record the active C3.3 default runtime contract."
    Assert-InstallerCondition -Condition (Test-ExactArray -Actual @($recommendedManifest.skills) -Expected @("project-bootstrap", "project-workspace")) -Message "Recommended manifest skills are not the post-cutover C3.3 authority."
    $statusProviderItem = @($recommendedManifest.items | Where-Object { [string]$_.name -eq "runtime-status-provider" })
    Assert-InstallerCondition -Condition ($statusProviderItem.Count -eq 1) -Message "Recommended copy install did not record one runtime status provider item."
    Assert-InstallerCondition -Condition (Test-ExactArray -Actual @($statusProviderItem[0].files | ForEach-Object { [string]$_.path }) -Expected @("lib/path-guard.ps1", "lib/runtime-status-action.ps1", "status.ps1", "migrate-project.ps1", "validation/powershell-runtime-requirement.ps1")) -Message "Runtime status provider item did not contain the exact dependency closure."
    Assert-InstallerCondition -Condition (@(Get-ChildItem -LiteralPath (Join-PathParts $profileShrinkRuntime "scripts") -Recurse -File).Count -eq 5) -Message "Recommended copy install copied unrelated scripts."
    $scenarioEvidence.Add([ordered]@{ scenario = "recommended-status-provider-ownership"; exit_code = $recommendedInstall.exit_code; managed_file_count = @($statusProviderItem[0].files).Count })
    $profileShrinkRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $profileShrinkRuntime -Profile "minimal"
    $profileShrinkManifest = Read-InstallArtifact -RuntimeRoot $profileShrinkRuntime -Name "install-manifest.json"
    $profileShrinkReport = Read-InstallArtifact -RuntimeRoot $profileShrinkRuntime -Name "install-report.json"
    Assert-InstallerCondition -Condition ($profileShrinkRun.exit_code -eq 0 -and [string]$profileShrinkReport.status -eq "success") -Message "Clean recommended-to-minimal profile shrink failed."
    Assert-InstallerCondition -Condition (Test-ExactArray -Actual @($profileShrinkManifest.items | ForEach-Object { [string]$_.name }) -Expected @("knowledge-hub", "skills/project-bootstrap")) -Message "Profile shrink manifest retained or lost the wrong managed items."
    Assert-InstallerCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $profileShrinkRuntime "scripts"))) -Message "Profile shrink retained the runtime status provider."
    foreach ($excludedRelative in @("skills/project-workspace", "templates/project", "schemas/project-workspace")) {
        Assert-InstallerCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $profileShrinkRuntime $excludedRelative))) -Message "Profile shrink left an excluded managed item on disk: $excludedRelative"
    }
    Assert-InstallerCondition -Condition (Test-ReportPath -Values @($profileShrinkReport.updated) -Path "skills/project-workspace/managed.txt") -Message "Profile shrink did not report the excluded project-workspace skill as updated."
    Assert-ManifestFileHashes -Manifest $profileShrinkManifest -RuntimeRoot $profileShrinkRuntime
    $profileShrinkUninstall = Invoke-FixtureUninstall -Uninstaller $uninstaller -RuntimeRoot $profileShrinkRuntime -AdditionalArguments @("-Json")
    $profileShrinkUninstallResult = (($profileShrinkUninstall.output -join "`n") | ConvertFrom-Json)
    Assert-InstallerCondition -Condition ($profileShrinkUninstall.exit_code -eq 0 -and [string]$profileShrinkUninstallResult.status -eq "uninstalled") -Message "Post-shrink uninstall failed."
    Assert-InstallerCondition -Condition (-not (Test-Path -LiteralPath (Join-PathParts $profileShrinkRuntime "knowledge-hub")) -and -not (Test-Path -LiteralPath (Join-PathParts $profileShrinkRuntime "skills" "project-bootstrap"))) -Message "Post-shrink uninstall ownership did not match the manifest."
    $scenarioEvidence.Add([ordered]@{ scenario = "recommended-to-minimal-ownership"; exit_code = $profileShrinkRun.exit_code; status = [string]$profileShrinkReport.status; uninstall_status = [string]$profileShrinkUninstallResult.status })

    $rootConflictSetup = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $rootConflictRuntime -Profile "recommended"
    Assert-InstallerCondition -Condition ($rootConflictSetup.exit_code -eq 0) -Message "Root-conflict fixture setup failed."
    $rootConflictManifestBefore = Read-InstallArtifact -RuntimeRoot $rootConflictRuntime -Name "install-manifest.json"
    $ownedItemBefore = @($rootConflictManifestBefore.items | Where-Object { [string]$_.name -eq "skills/project-workspace" })[0]
    $ownedRoot = Join-PathParts $rootConflictRuntime "skills" "project-workspace"
    Remove-Item -LiteralPath $ownedRoot -Recurse -Force
    Write-FixtureText -Path $ownedRoot -Text "locally-replaced-item-root"
    $rootConflictRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $rootConflictRuntime -Profile "minimal"
    $rootConflictManifest = Read-InstallArtifact -RuntimeRoot $rootConflictRuntime -Name "install-manifest.json"
    $rootConflictReport = Read-InstallArtifact -RuntimeRoot $rootConflictRuntime -Name "install-report.json"
    $ownedItemAfter = @($rootConflictManifest.items | Where-Object { [string]$_.name -eq "skills/project-workspace" })
    Assert-InstallerCondition -Condition ($rootConflictRun.exit_code -ne 0 -and [string]$rootConflictReport.status -eq "conflict") -Message "Obsolete managed item root conflict did not fail by default."
    Assert-InstallerCondition -Condition ($ownedItemAfter.Count -eq 1 -and [string]$ownedItemAfter[0].installed_hash -eq [string]$ownedItemBefore.installed_hash) -Message "Root conflict forgot previous managed ownership or baseline."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath $ownedRoot -Raw) -eq "locally-replaced-item-root") -Message "Root conflict overwrote the abnormal item root."
    Assert-InstallerCondition -Condition ((Test-ReportPath -Values @($rootConflictReport.conflicts) -Path "skills/project-workspace") -and -not (Test-ReportPath -Values @($rootConflictReport.preserved_unknown) -Path "skills/project-workspace")) -Message "Root conflict was degraded to unknown ownership."
    $rootConflictPartial = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $rootConflictRuntime -Profile "minimal" -AdditionalArguments @("-AllowPartial")
    $rootConflictManifestPartial = Read-InstallArtifact -RuntimeRoot $rootConflictRuntime -Name "install-manifest.json"
    $rootConflictReportPartial = Read-InstallArtifact -RuntimeRoot $rootConflictRuntime -Name "install-report.json"
    $ownedItemPartial = @($rootConflictManifestPartial.items | Where-Object { [string]$_.name -eq "skills/project-workspace" })
    Assert-InstallerCondition -Condition ($rootConflictPartial.exit_code -eq 0 -and [string]$rootConflictReportPartial.status -eq "conflict") -Message "Root conflict -AllowPartial rerun did not preserve conflict semantics."
    Assert-InstallerCondition -Condition ($ownedItemPartial.Count -eq 1 -and [string]$ownedItemPartial[0].installed_hash -eq [string]$ownedItemBefore.installed_hash) -Message "Root conflict -AllowPartial rerun forgot ownership."
    Assert-InstallerCondition -Condition (-not (Test-ReportPath -Values @($rootConflictReportPartial.preserved_unknown) -Path "skills/project-workspace")) -Message "Root conflict rerun degraded the managed item root to unknown."
    $scenarioEvidence.Add([ordered]@{ scenario = "managed-item-root-conflict-rerun"; default_exit = $rootConflictRun.exit_code; partial_exit = $rootConflictPartial.exit_code; status = [string]$rootConflictReportPartial.status })

    if (-not $SkipDevLink.IsPresent) {
        $devLinkRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $devLinkRuntime -AdditionalArguments @("-DevLink")
        $devManifest = Read-InstallArtifact -RuntimeRoot $devLinkRuntime -Name "install-manifest.json"
        $devReport = Read-InstallArtifact -RuntimeRoot $devLinkRuntime -Name "install-report.json"
        Assert-InstallerCondition -Condition ($devLinkRun.exit_code -eq 0) -Message "Explicit -DevLink install failed."
        Assert-InstallerCondition -Condition ([string]$devManifest.install_strategy -eq "dev-link") -Message "Explicit -DevLink strategy missing from manifest."
        Assert-InstallerCondition -Condition (Test-FixtureReparsePoint -Path (Join-PathParts $devLinkRuntime "knowledge-hub")) -Message "Explicit -DevLink knowledge-hub is not a link."
        Assert-InstallerCondition -Condition (@($devManifest.items | Where-Object { [string]$_.mode -notin @("junction", "symboliclink") }).Count -eq 0) -Message "Explicit -DevLink manifest recorded a non-link item mode."
        Assert-ReportCountConsistency -Report $devReport
        $scenarioEvidence.Add([ordered]@{ scenario = "explicit-dev-link"; exit_code = $devLinkRun.exit_code; status = [string]$devReport.status; strategy = [string]$devManifest.install_strategy })

        $devLinkRerun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $devLinkRuntime -AdditionalArguments @("-DevLink")
        $devRerunReport = Read-InstallArtifact -RuntimeRoot $devLinkRuntime -Name "install-report.json"
        Assert-InstallerCondition -Condition ($devLinkRerun.exit_code -eq 0) -Message "Explicit -DevLink unchanged rerun failed target verification."
        Assert-InstallerCondition -Condition ([int]$devRerunReport.counts.updated -eq 0 -and [int]$devRerunReport.counts.unchanged -eq 3) -Message "Explicit -DevLink unchanged rerun report was inconsistent."
        $scenarioEvidence.Add([ordered]@{ scenario = "explicit-dev-link-rerun"; exit_code = $devLinkRerun.exit_code; status = [string]$devRerunReport.status })

        New-Item -ItemType Directory -Force -Path (Join-PathParts $legacyLinkRuntime "skills") | Out-Null
        $legacyLinkItemType = "SymbolicLink"
        $legacyLinkMode = "symboliclink"
        if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            $legacyLinkItemType = "Junction"
            $legacyLinkMode = "junction"
        }
        New-Item -ItemType $legacyLinkItemType -Path (Join-PathParts $legacyLinkRuntime "knowledge-hub") -Target (Join-PathParts $fixtureSource "knowledge-hub") | Out-Null
        New-Item -ItemType $legacyLinkItemType -Path (Join-PathParts $legacyLinkRuntime "skills" "project-bootstrap") -Target (Join-PathParts $fixtureSource "skills" "project-bootstrap") | Out-Null
        $legacyLinkManifest = [ordered]@{
            schema_version = 1
            profile = "minimal"
            link_preferred = $true
            skills = @("project-bootstrap")
            items = @(
                [ordered]@{ name = "knowledge-hub"; source = (Join-PathParts $fixtureSource "knowledge-hub"); destination = (Join-PathParts $legacyLinkRuntime "knowledge-hub"); mode = $legacyLinkMode },
                [ordered]@{ name = "skills/project-bootstrap"; source = (Join-PathParts $fixtureSource "skills" "project-bootstrap"); destination = (Join-PathParts $legacyLinkRuntime "skills" "project-bootstrap"); mode = $legacyLinkMode }
            )
        }
        Write-FixtureText -Path (Join-PathParts $legacyLinkRuntime "install-manifest.json") -Text ($legacyLinkManifest | ConvertTo-Json -Depth 8)
        $legacyLinkUpgrade = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $legacyLinkRuntime
        $legacyLinkUpgradedManifest = Read-InstallArtifact -RuntimeRoot $legacyLinkRuntime -Name "install-manifest.json"
        Assert-InstallerCondition -Condition ($legacyLinkUpgrade.exit_code -eq 0) -Message ("Legacy default link-to-copy migration failed with exit code {0}." -f $legacyLinkUpgrade.exit_code)
        Assert-InstallerCondition -Condition ([string]$legacyLinkUpgradedManifest.install_strategy -eq "copy") -Message "Legacy link migration did not record copy strategy."
        Assert-InstallerCondition -Condition (-not (Test-FixtureReparsePoint -Path (Join-PathParts $legacyLinkRuntime "knowledge-hub"))) -Message "Legacy link migration left knowledge-hub linked."
        Assert-InstallerCondition -Condition ((Get-Content -LiteralPath $hubManagedSource -Raw) -eq "source-d") -Message "Legacy link migration modified the source checkout."
        $scenarioEvidence.Add([ordered]@{ scenario = "legacy-default-link-to-copy"; exit_code = $legacyLinkUpgrade.exit_code; schema_version = [int]$legacyLinkUpgradedManifest.schema_version })
    }

    New-Item -ItemType Directory -Force -Path (Join-PathParts $legacyRuntime "knowledge-hub") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-PathParts $legacyRuntime "skills" "project-bootstrap") | Out-Null
    Copy-Item -Path (Join-PathParts $fixtureSource "knowledge-hub" "*") -Destination (Join-PathParts $legacyRuntime "knowledge-hub") -Force
    Copy-Item -Path (Join-PathParts $fixtureSource "skills" "project-bootstrap" "*") -Destination (Join-PathParts $legacyRuntime "skills" "project-bootstrap") -Force
    Write-FixtureText -Path (Join-PathParts $legacyRuntime "knowledge-hub" "managed.txt") -Text "legacy-copy-local-content"
    $legacyManifest = [ordered]@{
        schema_version = 1
        profile = "minimal"
        link_preferred = $false
        skills = @("project-bootstrap")
        items = @(
            [ordered]@{ name = "knowledge-hub"; source = (Join-PathParts $fixtureSource "knowledge-hub"); destination = (Join-PathParts $legacyRuntime "knowledge-hub"); mode = "copy" },
            [ordered]@{ name = "skills/project-bootstrap"; source = (Join-PathParts $fixtureSource "skills" "project-bootstrap"); destination = (Join-PathParts $legacyRuntime "skills" "project-bootstrap"); mode = "copy" }
        )
    }
    Write-FixtureText -Path (Join-PathParts $legacyRuntime "install-manifest.json") -Text ($legacyManifest | ConvertTo-Json -Depth 8)
    $legacyManifestBeforeConflict = Get-Content -LiteralPath (Join-PathParts $legacyRuntime "install-manifest.json") -Raw
    $legacyRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $legacyRuntime
    $legacyConflictManifest = Read-InstallArtifact -RuntimeRoot $legacyRuntime -Name "install-manifest.json"
    $legacyConflictReport = Read-InstallArtifact -RuntimeRoot $legacyRuntime -Name "install-report.json"
    Assert-InstallerCondition -Condition ($legacyRun.exit_code -ne 0 -and [string]$legacyConflictReport.status -eq "conflict") -Message "Differing schema-1 copy target did not fail conservatively."
    Assert-InstallerCondition -Condition ([int]$legacyConflictManifest.schema_version -eq 1 -and -not [bool]$legacyConflictReport.manifest_updated) -Message "Conflicted schema-1 copy migration wrote a misleading schema-2 baseline."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath (Join-PathParts $legacyRuntime "install-manifest.json") -Raw) -eq $legacyManifestBeforeConflict) -Message "Provenance bypassed schema-1 conflict manifest preservation."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath (Join-PathParts $legacyRuntime "knowledge-hub" "managed.txt") -Raw) -eq "legacy-copy-local-content") -Message "Default legacy copy conflict overwrote target content."
    $scenarioEvidence.Add([ordered]@{ scenario = "legacy-copy-difference-conflict"; exit_code = $legacyRun.exit_code; status = [string]$legacyConflictReport.status; manifest_schema_version = [int]$legacyConflictManifest.schema_version })

    $legacyReplaceRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $legacyRuntime -AdditionalArguments @("-ReplaceManaged")
    $legacyUpgradedManifest = Read-InstallArtifact -RuntimeRoot $legacyRuntime -Name "install-manifest.json"
    $legacyReplaceReport = Read-InstallArtifact -RuntimeRoot $legacyRuntime -Name "install-report.json"
    Assert-InstallerCondition -Condition ($legacyReplaceRun.exit_code -eq 0 -and [int]$legacyUpgradedManifest.schema_version -eq 2) -Message "-ReplaceManaged did not complete schema-1 copy migration."
    Assert-InstallerCondition -Condition ((Get-Content -LiteralPath (Join-PathParts $legacyRuntime "knowledge-hub" "managed.txt") -Raw) -eq (Get-Content -LiteralPath $hubManagedSource -Raw)) -Message "Legacy copy replacement did not converge to source content."
    Assert-ManifestFileHashes -Manifest $legacyUpgradedManifest -RuntimeRoot $legacyRuntime
    Assert-InstallerCondition -Condition ([bool]$legacyReplaceReport.manifest_updated -and [int]$legacyReplaceReport.manifest_schema_version -eq 2) -Message "Legacy replacement report did not record completed schema-2 migration."
    Assert-InstallerCondition -Condition (-not ((Get-Content -LiteralPath (Join-PathParts $legacyRuntime "install-manifest.json") -Raw).Contains([System.IO.Path]::GetFullPath($fixtureSource)))) -Message "Upgraded legacy manifest retained an absolute source path."
    $scenarioEvidence.Add([ordered]@{ scenario = "legacy-copy-replace-managed-migration"; exit_code = $legacyReplaceRun.exit_code; schema_version = [int]$legacyUpgradedManifest.schema_version })

    return @($scenarioEvidence.ToArray())
}
