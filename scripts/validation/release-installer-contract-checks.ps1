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
            [string[]]$AdditionalArguments = @()
        )
        $arguments = @("-Profile", "minimal", "-TargetDir", $RuntimeRoot) + @($AdditionalArguments)
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            return Invoke-IsolatedPowerShellScript -ScriptPath $Installer -Arguments $arguments
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
            [Parameter(Mandatory = $true)][object[]]$Values,
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

    $fixtureSource = Join-PathParts $ScratchRoot "installer-contract-source"
    $runtimeRoot = Join-PathParts $ScratchRoot "installer-contract-runtime"
    $devLinkRuntime = Join-PathParts $ScratchRoot "installer-contract-dev-link-runtime"
    $legacyLinkRuntime = Join-PathParts $ScratchRoot "installer-contract-legacy-link-runtime"
    $legacyRuntime = Join-PathParts $ScratchRoot "installer-contract-legacy-runtime"
    foreach ($path in @($fixtureSource, $runtimeRoot, $devLinkRuntime, $legacyLinkRuntime, $legacyRuntime)) {
        Assert-PathInsideRoot -Path $path -Root $ScratchRoot
    }

    New-Item -ItemType Directory -Force -Path (Join-PathParts $fixtureSource "scripts" "lib") | Out-Null
    Copy-Item -LiteralPath (Join-PathParts $RepositoryRoot "scripts" "install.ps1") -Destination (Join-PathParts $fixtureSource "scripts" "install.ps1") -Force
    Copy-Item -LiteralPath (Join-PathParts $RepositoryRoot "scripts" "lib" "path-guard.ps1") -Destination (Join-PathParts $fixtureSource "scripts" "lib" "path-guard.ps1") -Force

    $hubManagedSource = Join-PathParts $fixtureSource "knowledge-hub" "managed.txt"
    $hubStableSource = Join-PathParts $fixtureSource "knowledge-hub" "stable.txt"
    $skillManagedSource = Join-PathParts $fixtureSource "skills" "project-bootstrap" "managed.txt"
    Write-FixtureText -Path $hubManagedSource -Text "source-a"
    Write-FixtureText -Path $hubStableSource -Text "stable"
    Write-FixtureText -Path $skillManagedSource -Text "skill-a"

    $installer = Join-PathParts $fixtureSource "scripts" "install.ps1"
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
    Assert-ReportCountConsistency -Report $report
    $scenarioEvidence.Add([ordered]@{ scenario = "fresh-default-copy"; exit_code = $fresh.exit_code; status = [string]$report.status; updated = [int]$report.counts.updated })

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
    foreach ($item in @($manifest.items)) {
        foreach ($file in @($item.files)) {
            $installedPath = Join-PathParts $runtimeRoot ([string]$item.destination) ([string]$file.path)
            Assert-InstallerCondition -Condition (Test-Path -LiteralPath $installedPath -PathType Leaf) -Message "Manifest managed file is missing after compatibility Force run."
            $actualHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash.ToLowerInvariant()
            Assert-InstallerCondition -Condition ($actualHash -eq [string]$file.installed_sha256) -Message "Manifest installed hash does not match the runtime file."
        }
    }
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
    $legacyRun = Invoke-FixtureInstall -Installer $installer -RuntimeRoot $legacyRuntime
    $legacyUpgradedManifest = Read-InstallArtifact -RuntimeRoot $legacyRuntime -Name "install-manifest.json"
    Assert-InstallerCondition -Condition ($legacyRun.exit_code -eq 0) -Message "Legacy manifest compatibility rerun failed."
    Assert-InstallerCondition -Condition ([int]$legacyUpgradedManifest.schema_version -eq 2) -Message "Legacy manifest was not upgraded to schema 2."
    Assert-InstallerCondition -Condition (-not ((Get-Content -LiteralPath (Join-PathParts $legacyRuntime "install-manifest.json") -Raw).Contains([System.IO.Path]::GetFullPath($fixtureSource)))) -Message "Upgraded legacy manifest retained an absolute source path."
    $scenarioEvidence.Add([ordered]@{ scenario = "legacy-manifest-upgrade"; exit_code = $legacyRun.exit_code; schema_version = [int]$legacyUpgradedManifest.schema_version })

    return @($scenarioEvidence.ToArray())
}
