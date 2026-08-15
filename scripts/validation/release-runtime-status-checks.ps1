function Invoke-RuntimeStatusFixtureChecks {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ScratchRoot
    )

    $isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

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
            Get-ChildItem -LiteralPath $RuntimeRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
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

    function Get-ManagedAliasState {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeRoot,
            [Parameter(Mandatory = $true)][string]$AliasPath,
            [Parameter(Mandatory = $true)][string]$TargetPath,
            [switch]$Broken
        )
        if (-not $isWindowsPlatform) {
            $aliasTarget = @(& readlink $AliasPath) -join "`n"
            if ($LASTEXITCODE -ne 0) { throw "Could not inspect the managed alias fixture." }
            $aliasType = "SymbolicLink"
        }
        elseif ($PSVersionTable.PSVersion.Major -ge 7) {
            $alias = [System.IO.DirectoryInfo]::new($AliasPath)
            $aliasTarget = [string]$alias.LinkTarget
            $aliasType = if ([string]::IsNullOrWhiteSpace($aliasTarget)) { $null } elseif ($isWindowsPlatform) { "Junction" } else { "SymbolicLink" }
        }
        else {
            $aliasName = [System.IO.Path]::GetFileName($AliasPath)
            $alias = Get-ChildItem -LiteralPath (Split-Path -Parent $AliasPath) -Force |
                Where-Object { [string]::Equals([string]$_.Name, $aliasName, [System.StringComparison]::Ordinal) } |
                Select-Object -First 1
            $aliasTarget = if ($null -eq $alias) { $null } else { @($alias.Target) -join "|" }
            $aliasType = if ($null -eq $alias) { $null } else { [string]$alias.LinkType }
        }
        return [ordered]@{
            manifest_hash = (Get-FileHash -LiteralPath (Join-PathParts $RuntimeRoot "install-manifest.json") -Algorithm SHA256).Hash
            alias_type = $aliasType
            alias_target = $aliasTarget
            target_hash = if (Test-Path -LiteralPath $TargetPath -PathType Leaf) { (Get-FileHash -LiteralPath $TargetPath -Algorithm SHA256).Hash } else { $null }
            runtime_tree = if ($Broken.IsPresent) { @() } else { @(Get-StatusTreeState -RuntimeRoot $RuntimeRoot) }
        }
    }

    function Invoke-Status {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeRoot,
            [string]$ProjectRoot = "",
            [switch]$Text,
            [string]$LockHelper = "",
            [string]$UpgradeHelper = "",
            [string]$DiagnoseHelper = ""
        )
        $arguments = @("-RuntimeDir", $RuntimeRoot)
        if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) { $arguments += @("-ProjectDir", $ProjectRoot) }
        if ($LockHelper) { $arguments += @("-LockHelperPath", $LockHelper) }
        if ($UpgradeHelper) { $arguments += @("-UpgradeHelperPath", $UpgradeHelper) }
        if ($DiagnoseHelper) { $arguments += @("-DiagnoseHelperPath", $DiagnoseHelper) }
        if (-not $Text.IsPresent) { $arguments += "-Json" }
        return Invoke-IsolatedPowerShellScript -ScriptPath $statusScript -Arguments $arguments
    }

    function New-StatusHelperFixture {
        param([string]$Name, [string]$Kind, [string]$Json)
        $path = Join-PathParts $fixtureRoot "helpers" ("{0}.ps1" -f $Name)
        $parameters = switch ($Kind) {
            "lock" { 'param([string[]]$ProjectDir, [string]$RuntimeDir, [switch]$Json)' }
            "upgrade" { 'param([string]$ProjectDir, [string]$Mode, [switch]$Json)' }
            default { 'param([string]$ProjectRoot, [switch]$Json)' }
        }
        Write-StatusText -Path $path -Text ($parameters + "`nWrite-Output @'`n" + $Json + "`n'@")
        return $path
    }

    function Get-ProjectFixtureTreeState {
        param([string]$Root)
        return @(
            Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
                Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
                Sort-Object FullName | ForEach-Object {
                    "{0}|{1}" -f (ConvertTo-DisplayPath -Path $_.FullName -Root $Root), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                }
        )
    }

    function Get-ProjectTemplateHash {
        param([string]$HubRoot, [string]$Language)
        $records = @()
        foreach ($entry in @("project-root", "project-agent")) {
            $root = Join-PathParts $HubRoot "templates" "languages" $Language $entry
            if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
            Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName | ForEach-Object {
                $relative = $_.FullName.Substring($root.Length).TrimStart([char[]]"\/") -replace "\\", "/"
                $records += ("{0}/{1}:{2}" -f $entry, $relative, (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
            }
        }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($records -join "`n")))).Replace("-", "").ToLowerInvariant() }
        finally { $sha.Dispose() }
    }

    function New-ProjectStatusFixture {
        param([string]$Name, [string]$Language = "en")
        $root = Join-PathParts $fixtureRoot "project-$Name"
        $hub = Join-PathParts $fixtureRoot "hub-$Name"
        Write-StatusText -Path (Join-PathParts $hub "templates" "languages" $Language "project-root" "AGENTS.md") -Text "template"
        & git init -q -b main $hub
        & git -C $hub config user.name fixture
        & git -C $hub config user.email fixture@example.invalid
        & git -C $hub remote add origin https://example.invalid/hub.git
        & git -C $hub add .
        & git -C $hub commit -q -m fixture
        $commit = @(& git -C $hub rev-parse HEAD) -join ""

        foreach ($file in @("AGENTS.md", ".agents/AGENTS.md", ".agents/process.txt", ".agents/plan.md", ".agents/notes.md", ".agents/context/README.md", ".agents/commands/README.md")) {
            $content = if ($file -eq ".agents/AGENTS.md") {
                if ($Language -eq "zh-CN") { -join (@(0x9879,0x76EE,0x8BB0,0x5FC6,0x8BED,0x8A00,0xFF1A,0x7B80,0x4F53,0x4E2D,0x6587,0x3002) | ForEach-Object { [char]$_ }) } else { "Project memory language: English." }
            } else { "fixture" }
            Write-StatusText -Path (Join-PathParts $root $file) -Text $content
        }
        Write-StatusText -Path (Join-Path $root "CLAUDE.md") -Text "@AGENTS.md`n@.agents/AGENTS.md`n@.agents/process.txt`n@.agents/plan.md`n@.agents/context/README.md`n@.agents/commands/README.md"
        New-Item -ItemType Directory -Force -Path (Join-PathParts $root "docs" "specs" "_templates") | Out-Null
        $lock = [ordered]@{
            schema_version = 1; hub_dir = $hub; hub_remote = "https://example.invalid/hub.git"; hub_branch = "main"; hub_commit = $commit
            hub_dirty = $false; project_language = $Language; template_tree_hash_sha256 = Get-ProjectTemplateHash $hub $Language
        }
        Write-StatusText -Path (Join-PathParts $root ".agents" "hub.lock.json") -Text ($lock | ConvertTo-Json)
        return [ordered]@{ root = $root; hub = $hub; lock = $lock }
    }

    function New-C33ProjectStatusFixture {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [ValidateSet("c3.3", "legacy")][string]$WorkspaceModel = "c3.3",
            [string]$WorkspaceState = "active"
        )

        $root = Join-PathParts $fixtureRoot "c33-project-$Name"
        Write-StatusText -Path (Join-PathParts $root "AGENTS.md") -Text "# Fixture"
        Write-StatusText -Path (Join-PathParts $root ".agents" "README.md") -Text "# Workspace"
        foreach ($relative in @(".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")) {
            New-Item -ItemType Directory -Force -Path (Join-PathParts $root $relative) | Out-Null
        }
        $lock = [ordered]@{
            schema_version = 1
            project_language = "en"
            workspace_model = $WorkspaceModel
            workspace_state = $WorkspaceState
            workspace_roots = @(".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")
        }
        $lockPath = Join-PathParts $root ".agents" "hub.lock.json"
        Write-StatusText -Path $lockPath -Text ($lock | ConvertTo-Json -Depth 8)
        return [ordered]@{ root = $root; lock = $lock; lock_path = $lockPath }
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
            target_dir = "."
            workspace = [ordered]@{
                architecture = "legacy-runtime"
                lifecycle = "not-enabled"
                default_cutover = $false
                packaged_content = @()
                c3_3_authority = @()
                legacy_only_compatibility_payload = @("project-context-gate", "memory-governance", "workflow-spec-lite")
                retired_from_c3_3_authority = @("project-context-gate", "memory-governance", "workflow-spec-lite")
                compatibility_aliases = $false
                automatic_forwarding = $false
                dual_write = $false
                project_local_authority = "project-local"
                derived_cache = ".agents/.cache/catalog.json"
            }
            items = @()
        }
    }

    function New-ManagedCopyProjectFixture {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [ValidateSet("legacy-git", "copy")][string]$LockKind = "legacy-git"
        )

        $project = New-ProjectStatusFixture -Name ("managed-copy-{0}" -f $Name)
        $runtime = Join-PathParts $fixtureRoot ("managed-copy-runtime-{0}" -f $Name)
        $hub = Join-PathParts $runtime "knowledge-hub"
        $templateFiles = @(
            "templates/languages/en/project-root/AGENTS.md",
            "templates/languages/en/project-agent/AGENTS.md"
        )
        $records = New-Object 'System.Collections.Generic.List[object]'
        foreach ($relativePath in $templateFiles) {
            $livePath = Join-PathParts $hub $relativePath
            Write-StatusText -Path $livePath -Text ("managed template {0}" -f $relativePath)
            $hash = (Get-FileHash -LiteralPath $livePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $records.Add([ordered]@{ path = $relativePath; source_sha256 = $hash; installed_sha256 = $hash })
        }
        $manifest = New-CurrentManifest
        $manifest.items = @([ordered]@{
                name = "knowledge-hub"
                source = "knowledge-hub"
                destination = "knowledge-hub"
                mode = "copy"
                managed = $true
                files = @($records.ToArray())
            })
        Write-StatusManifest -RuntimeRoot $runtime -Value $manifest

        $project.lock.hub_dir = $hub
        $project.lock.template_tree_hash_sha256 = Get-ProjectTemplateHash $hub "en"
        if ($LockKind -eq "copy") {
            $project.lock.hub_remote = ""
            $project.lock.hub_branch = "UNKNOWN"
            $project.lock.hub_commit = "UNKNOWN"
        }
        Write-StatusText -Path (Join-PathParts $project.root ".agents" "hub.lock.json") -Text ($project.lock | ConvertTo-Json)
        return [ordered]@{
            project = $project
            runtime = $runtime
            hub = $hub
            manifest = $manifest
            first_managed_file = Join-PathParts $hub $templateFiles[0]
        }
    }

    function New-ManagedStatusFixture {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [string]$Content = "managed content",
            [switch]$Missing,
            [AllowEmptyString()][string]$SourceHash,
            [AllowEmptyString()][string]$InstalledHash
        )
        $runtime = Join-PathParts $fixtureRoot $Name
        $relativePath = "SKILL.md"
        $livePath = Join-PathParts $runtime "skills" "project-bootstrap" $relativePath
        if (-not $Missing.IsPresent) { Write-StatusText -Path $livePath -Text $Content }
        $contentHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Content))).Replace("-", "").ToLowerInvariant()
        if (-not $PSBoundParameters.ContainsKey("InstalledHash")) { $InstalledHash = $contentHash }
        if (-not $PSBoundParameters.ContainsKey("SourceHash")) { $SourceHash = $InstalledHash }
        $manifest = New-CurrentManifest
        $manifest.items = @([ordered]@{
                name = "skills/project-bootstrap"
                destination = "skills/project-bootstrap"
                mode = "copy"
                managed = $true
                files = @([ordered]@{ path = $relativePath; source_sha256 = $SourceHash; installed_sha256 = $InstalledHash })
            })
        Write-StatusManifest -RuntimeRoot $runtime -Value $manifest
        return [ordered]@{ runtime = $runtime; manifest = $manifest; live_path = $livePath; content_hash = $contentHash }
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
                [ordered]@{ name = "skills/$_"; destination = "skills/$_"; mode = "copy"; managed = $true; files = @() }
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
    $actionHelper = Join-PathParts $RepositoryRoot "scripts" "lib" "runtime-status-action.ps1"
    $fixtureRoot = Join-PathParts $ScratchRoot "runtime-status-fixtures"
    Assert-PathInsideRoot -Path $fixtureRoot -Root $ScratchRoot
    New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
    $evidence = New-Object 'System.Collections.Generic.List[object]'

    . $actionHelper
    function New-ActionPayload {
        param(
            [object]$Manifest = "current",
            [object]$Managed = "current",
            [object]$Bridge = "current",
            [object]$Project = "current",
            [object]$ProjectReason = "in-sync"
        )
        return [pscustomobject]@{
            schema_version = 1
            runtime = [pscustomobject]@{
                manifest_status = $Manifest
                release_version = [pscustomobject]@{ value = $null; reason = "not-recorded" }
                source_commit = [pscustomobject]@{ value = $null; reason = "not-recorded" }
                managed_files = [pscustomobject]@{ status = $Managed }
            }
            bridge = [pscustomobject]@{ status = $Bridge }
            project = [pscustomobject]@{ status = $Project; reason = $ProjectReason }
        }
    }
    $allowedActions = @("none", "inspect-manually", "reinstall-runtime", "review-managed-conflicts", "repair-bridge", "refresh-project-templates", "run-project-migration-analysis")
    $actionCases = @(
        @{ name = "healthy"; expected = "none" },
        @{ name = "not-configured-not-requested"; bridge = "not-configured"; project = "unknown"; reason = "not-requested"; expected = "none" },
        @{ name = "manifest-missing"; manifest = "missing"; expected = "reinstall-runtime" },
        @{ name = "manifest-legacy"; manifest = "legacy"; expected = "reinstall-runtime" },
        @{ name = "manifest-unsupported"; manifest = "unsupported"; expected = "reinstall-runtime" },
        @{ name = "manifest-invalid-managed-conflict"; manifest = "invalid"; managed = "conflict"; expected = "reinstall-runtime" },
        @{ name = "managed-conflict-bridge-broken"; managed = "conflict"; bridge = "broken"; expected = "review-managed-conflicts" },
        @{ name = "managed-missing-bridge-broken"; managed = "missing"; bridge = "broken"; expected = "reinstall-runtime" },
        @{ name = "managed-modified-bridge-broken"; managed = "modified"; bridge = "broken"; expected = "inspect-manually" },
        @{ name = "managed-unknown-bridge-broken"; managed = "unknown"; bridge = "broken"; expected = "inspect-manually" },
        @{ name = "bridge-stale"; bridge = "stale"; expected = "repair-bridge" },
        @{ name = "bridge-broken-migration"; bridge = "broken"; project = "migration-required"; expected = "repair-bridge" },
        @{ name = "bridge-conflict"; bridge = "conflict"; expected = "repair-bridge" },
        @{ name = "bridge-unknown-refresh"; bridge = "unknown"; project = "optional-refresh"; expected = "inspect-manually" },
        @{ name = "project-migration"; project = "migration-required"; expected = "run-project-migration-analysis" },
        @{ name = "project-refresh"; project = "optional-refresh"; expected = "refresh-project-templates" },
        @{ name = "project-unknown"; project = "unknown"; reason = "missing-lock"; expected = "inspect-manually" },
        @{ name = "manifest-unrecognized"; manifest = "future"; expected = "inspect-manually" },
        @{ name = "managed-unrecognized"; managed = "future"; expected = "inspect-manually" },
        @{ name = "bridge-unrecognized"; bridge = "future"; expected = "inspect-manually" },
        @{ name = "project-unrecognized"; project = "future"; expected = "inspect-manually" },
        @{ name = "manifest-case-variant"; manifest = "CURRENT"; expected = "inspect-manually" },
        @{ name = "managed-case-variant"; managed = "Conflict"; expected = "inspect-manually" },
        @{ name = "bridge-case-variant"; bridge = "Broken"; expected = "inspect-manually" },
        @{ name = "project-case-variant"; project = "OPTIONAL-REFRESH"; expected = "inspect-manually" },
        @{ name = "project-reason-case-variant"; project = "unknown"; reason = "NOT-REQUESTED"; expected = "inspect-manually" },
        @{ name = "manifest-wrong-type"; manifest = 7; expected = "inspect-manually" },
        @{ name = "managed-wrong-type"; managed = @("current", "extra"); expected = "inspect-manually" },
        @{ name = "bridge-wrong-type"; bridge = $true; expected = "inspect-manually" },
        @{ name = "project-wrong-type"; project = 7; expected = "inspect-manually" },
        @{ name = "reason-wrong-type"; project = "unknown"; reason = 7; expected = "inspect-manually" }
    )
    foreach ($case in $actionCases) {
        $parameters = @{}
        foreach ($mapping in @(@("manifest", "Manifest"), @("managed", "Managed"), @("bridge", "Bridge"), @("project", "Project"), @("reason", "ProjectReason"))) {
            if ($case.ContainsKey($mapping[0])) { $parameters[$mapping[1]] = $case[$mapping[0]] }
        }
        $actual = Get-RecommendedNextAction -Payload (New-ActionPayload @parameters)
        Assert-StatusCondition -Condition ($actual -ceq $case.expected) -Message "Recommended action case $($case.name) returned $actual."
        Assert-StatusCondition -Condition ($actual -cin $allowedActions) -Message "Recommended action case $($case.name) returned an action outside the public contract."
        $evidence.Add([ordered]@{ scenario = "recommended-action-$($case.name)"; status = $actual })
    }
    $orderedPayload = [ordered]@{
        runtime = [ordered]@{ manifest_status = "current"; managed_files = [ordered]@{ status = "current" } }
        bridge = [ordered]@{ status = "not-configured" }
        project = [ordered]@{ status = "current"; reason = "in-sync" }
    }
    Assert-StatusCondition -Condition ((Get-RecommendedNextAction -Payload $orderedPayload) -ceq "none") -Message "Ordered runtime payload did not use the recommended action contract."
    $evidence.Add([ordered]@{ scenario = "recommended-action-ordered-payload"; status = "none" })
    foreach ($missingPayload in @(
        [pscustomobject]@{},
        [pscustomobject]@{ runtime = [pscustomobject]@{} },
        [pscustomobject]@{ runtime = [pscustomobject]@{ manifest_status = "current" } }
    )) {
        Assert-StatusCondition -Condition ((Get-RecommendedNextAction -Payload $missingPayload) -ceq "inspect-manually") -Message "Missing recommended action property did not fail soft."
    }
    $throwingPayload = New-ActionPayload
    $throwingPayload.runtime.PSObject.Properties.Remove("manifest_status")
    $throwingPayload.runtime | Add-Member -MemberType ScriptProperty -Name manifest_status -Value { throw "private synthetic action failure" }
    Assert-StatusCondition -Condition ((Get-RecommendedNextAction -Payload $throwingPayload) -ceq "inspect-manually") -Message "Throwing recommended action property did not fail soft."
    Assert-StatusCondition -Condition (@($actionCases | ForEach-Object { $_.expected } | Sort-Object -Unique).Count -eq $allowedActions.Count) -Message "Recommended action fixtures do not cover every allowed action."

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

    $managedCurrent = New-ManagedStatusFixture -Name "managed-current"
    Write-StatusText -Path (Join-PathParts $managedCurrent.runtime "skills" "project-bootstrap" "unrecorded.txt") -Text "ignored"
    $managedBefore = @(Get-StatusTreeState -RuntimeRoot $managedCurrent.runtime)
    $managedCurrentPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedCurrent.runtime)
    $managedAfter = @(Get-StatusTreeState -RuntimeRoot $managedCurrent.runtime)
    Assert-StatusCondition -Condition ([string]$managedCurrentPayload.runtime.managed_files.status -eq "current" -and [string]$managedCurrentPayload.runtime.managed_files.reason -eq "scanned") -Message "Matching managed file did not report current."
    Assert-StatusCondition -Condition ([int]$managedCurrentPayload.runtime.managed_files.tracked_item_count -eq 1 -and [int]$managedCurrentPayload.runtime.managed_files.tracked_file_count -eq 1 -and [int]$managedCurrentPayload.runtime.managed_files.counts.current -eq 1) -Message "Managed file counts are incorrect."
    Assert-StatusCondition -Condition (@($managedCurrentPayload.runtime.managed_files.problems).Count -eq 0 -and (@($managedBefore) -join "`n") -ceq (@($managedAfter) -join "`n")) -Message "Managed status scanned unknown files or modified the runtime."
    $evidence.Add([ordered]@{ scenario = "managed-current-unrecorded-ignored"; status = [string]$managedCurrentPayload.runtime.managed_files.status })

    $managedModified = New-ManagedStatusFixture -Name "managed-modified" -Content "original"
    Write-StatusText -Path $managedModified.live_path -Text "changed"
    $modifiedPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedModified.runtime)
    Assert-StatusCondition -Condition ([string]$modifiedPayload.runtime.managed_files.status -eq "modified" -and [string]$modifiedPayload.runtime.managed_files.problems[0].path -eq "skills/project-bootstrap/SKILL.md" -and @($modifiedPayload.findings | Where-Object code -eq "runtime.managed.modified").Count -eq 1) -Message "Locally modified managed file was not reported."
    $evidence.Add([ordered]@{ scenario = "managed-modified"; status = [string]$modifiedPayload.runtime.managed_files.status })

    $managedMissing = New-ManagedStatusFixture -Name "managed-missing" -Missing
    $missingManagedPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedMissing.runtime)
    Assert-StatusCondition -Condition ([string]$missingManagedPayload.runtime.managed_files.status -eq "missing" -and @($missingManagedPayload.findings | Where-Object code -eq "runtime.managed.missing").Count -eq 1) -Message "Missing managed file was not reported."
    $evidence.Add([ordered]@{ scenario = "managed-missing"; status = [string]$missingManagedPayload.runtime.managed_files.status })

    $installedBytes = [System.Text.Encoding]::UTF8.GetBytes("installed")
    $sourceBytes = [System.Text.Encoding]::UTF8.GetBytes("source")
    $installedBaseline = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($installedBytes)).Replace("-", "").ToLowerInvariant()
    $sourceBaseline = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($sourceBytes)).Replace("-", "").ToLowerInvariant()
    foreach ($conflictCase in @(
            [ordered]@{ name = "live-installed"; content = "installed"; source = $sourceBaseline; installed = $installedBaseline; missing = $false },
            [ordered]@{ name = "live-source"; content = "source"; source = $sourceBaseline; installed = $installedBaseline; missing = $false },
            [ordered]@{ name = "live-third"; content = "third"; source = $sourceBaseline; installed = $installedBaseline; missing = $false },
            [ordered]@{ name = "missing"; content = "installed"; source = $sourceBaseline; installed = $installedBaseline; missing = $true },
            [ordered]@{ name = "source-removed"; content = "installed"; source = ""; installed = $installedBaseline; missing = $false }
        )) {
        $fixture = New-ManagedStatusFixture -Name ("managed-conflict-{0}" -f $conflictCase.name) -Content ([string]$conflictCase.content) -SourceHash ([string]$conflictCase.source) -InstalledHash ([string]$conflictCase.installed) -Missing:([bool]$conflictCase.missing)
        $payload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $fixture.runtime)
        Assert-StatusCondition -Condition ([string]$payload.runtime.managed_files.status -eq "conflict" -and [int]$payload.runtime.managed_files.counts.conflict -eq 1) -Message "Recorded source divergence did not remain conflict."
        $evidence.Add([ordered]@{ scenario = "managed-conflict-$($conflictCase.name)"; status = [string]$payload.runtime.managed_files.status })
    }

    $devLink = New-CurrentManifest
    $devLink.install_strategy = "dev-link"
    $devLinkRuntime = Join-PathParts $fixtureRoot "managed-dev-link"
    Write-StatusManifest -RuntimeRoot $devLinkRuntime -Value $devLink
    $devLinkPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $devLinkRuntime)
    Assert-StatusCondition -Condition ([string]$devLinkPayload.runtime.managed_files.status -eq "unknown" -and [string]$devLinkPayload.runtime.managed_files.reason -eq "dev-link-source-not-recorded" -and @($devLinkPayload.findings | Where-Object code -eq "runtime.managed.dev_link_unverifiable").Count -eq 1) -Message "Development-link runtime did not fail soft."
    $evidence.Add([ordered]@{ scenario = "managed-dev-link"; status = [string]$devLinkPayload.runtime.managed_files.status })

    $rootConflict = New-ManagedStatusFixture -Name "managed-item-root-file"
    [System.IO.Directory]::Delete((Join-PathParts $rootConflict.runtime "skills" "project-bootstrap"), $true)
    Write-StatusText -Path (Join-PathParts $rootConflict.runtime "skills" "project-bootstrap") -Text "occupied"
    $rootConflictPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $rootConflict.runtime)
    Assert-StatusCondition -Condition ([string]$rootConflictPayload.runtime.managed_files.status -eq "conflict") -Message "Managed item root occupied by a file did not report conflict."
    $evidence.Add([ordered]@{ scenario = "managed-item-root-file"; status = [string]$rootConflictPayload.runtime.managed_files.status })

    $leafDirectory = New-ManagedStatusFixture -Name "managed-leaf-directory"
    [System.IO.File]::Delete($leafDirectory.live_path)
    New-Item -ItemType Directory -Path $leafDirectory.live_path | Out-Null
    $leafDirectoryPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $leafDirectory.runtime)
    Assert-StatusCondition -Condition ([string]$leafDirectoryPayload.runtime.managed_files.status -eq "conflict") -Message "Managed leaf occupied by a directory did not report conflict."
    $evidence.Add([ordered]@{ scenario = "managed-leaf-directory"; status = [string]$leafDirectoryPayload.runtime.managed_files.status })

    $aliasedRoot = New-ManagedStatusFixture -Name "managed-item-root-alias"
    $aliasedRootPath = Join-PathParts $aliasedRoot.runtime "skills" "project-bootstrap"
    $externalRoot = Join-PathParts $fixtureRoot "managed-item-root-alias-external"
    [System.IO.Directory]::Delete($aliasedRootPath, $true)
    New-Item -ItemType Directory -Force -Path $externalRoot | Out-Null
    if ($isWindowsPlatform) { New-Item -ItemType Junction -Path $aliasedRootPath -Target $externalRoot | Out-Null }
    else { New-Item -ItemType SymbolicLink -Path $aliasedRootPath -Target $externalRoot | Out-Null }
    $aliasedRootPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $aliasedRoot.runtime)
    Assert-StatusCondition -Condition ([string]$aliasedRootPayload.runtime.managed_files.status -eq "conflict") -Message "Managed item root alias did not report conflict."
    $evidence.Add([ordered]@{ scenario = "managed-item-root-alias"; status = [string]$aliasedRootPayload.runtime.managed_files.status })

    foreach ($aliasCase in @(
            [ordered]@{ name = "inside"; outside = $false; broken = $false },
            [ordered]@{ name = "outside"; outside = $true; broken = $false },
            [ordered]@{ name = "broken"; outside = $true; broken = $true }
        )) {
        $aliasFixture = New-ManagedStatusFixture -Name ("managed-nested-alias-{0}" -f $aliasCase.name)
        $aliasFixture.manifest.items[0].files = @([ordered]@{ path = "nested/SKILL.md"; source_sha256 = $aliasFixture.content_hash; installed_sha256 = $aliasFixture.content_hash })
        [System.IO.File]::Delete($aliasFixture.live_path)
        $aliasPath = Join-PathParts $aliasFixture.runtime "skills" "project-bootstrap" "nested"
        $targetRoot = if ($aliasCase.outside) { Join-PathParts $fixtureRoot ("managed-alias-target-{0}" -f $aliasCase.name) } else { Join-PathParts $aliasFixture.runtime "other" ("target-{0}" -f $aliasCase.name) }
        $targetFile = Join-PathParts $targetRoot "SKILL.md"
        Write-StatusText -Path $targetFile -Text "managed content"
        if ($isWindowsPlatform) { New-Item -ItemType Junction -Path $aliasPath -Target $targetRoot | Out-Null }
        else { New-Item -ItemType SymbolicLink -Path $aliasPath -Target $targetRoot | Out-Null }
        if ($aliasCase.broken) { [System.IO.Directory]::Delete($targetRoot, $true) }
        Write-StatusManifest -RuntimeRoot $aliasFixture.runtime -Value $aliasFixture.manifest
        $aliasBefore = Get-ManagedAliasState -RuntimeRoot $aliasFixture.runtime -AliasPath $aliasPath -TargetPath $targetFile -Broken:([bool]$aliasCase.broken)
        $aliasRun = Invoke-Status -RuntimeRoot $aliasFixture.runtime
        $aliasPayload = Read-StatusPayload -Run $aliasRun
        $aliasAfter = Get-ManagedAliasState -RuntimeRoot $aliasFixture.runtime -AliasPath $aliasPath -TargetPath $targetFile -Broken:([bool]$aliasCase.broken)
        if ($aliasCase.broken) {
            Assert-StatusCondition -Condition ([string]$aliasPayload.runtime.managed_files.status -eq "unknown" -and [string]$aliasPayload.runtime.managed_files.reason -eq "path-unresolvable") -Message "Broken nested managed alias did not fail soft."
        }
        else {
            Assert-StatusCondition -Condition ([string]$aliasPayload.runtime.managed_files.status -eq "conflict" -and [int]$aliasPayload.runtime.managed_files.counts.conflict -eq 1) -Message "Nested managed alias was followed instead of reporting conflict."
        }
        Assert-StatusCondition -Condition (($aliasBefore | ConvertTo-Json -Depth 6 -Compress) -ceq ($aliasAfter | ConvertTo-Json -Depth 6 -Compress)) -Message "Managed alias inspection changed the alias, target, manifest, or runtime tree."
        $aliasJson = @($aliasRun.output) -join "`n"
        foreach ($privateValue in @([System.IO.Path]::GetFullPath($targetRoot), $aliasFixture.content_hash, $env:USERNAME)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$privateValue)) {
                Assert-StatusCondition -Condition (-not $aliasJson.Contains([string]$privateValue)) -Message "Managed alias status exposed a private path, hash, user name, or raw resolution detail."
            }
        }
        $evidence.Add([ordered]@{ scenario = "managed-nested-alias-$($aliasCase.name)"; status = [string]$aliasPayload.runtime.managed_files.status })
    }

    $partial = New-ManagedStatusFixture -Name "managed-partial-then-unresolvable"
    $partial.manifest.items[0].files = @(
        [ordered]@{ path = "a-current.txt"; source_sha256 = $partial.content_hash; installed_sha256 = $partial.content_hash },
        [ordered]@{ path = "broken/SKILL.md"; source_sha256 = $partial.content_hash; installed_sha256 = $partial.content_hash }
    )
    Write-StatusText -Path (Join-PathParts $partial.runtime "skills" "project-bootstrap" "a-current.txt") -Text "managed content"
    [System.IO.File]::Delete($partial.live_path)
    $partialBrokenTarget = Join-PathParts $fixtureRoot "managed-partial-broken-target"
    New-Item -ItemType Directory -Force -Path $partialBrokenTarget | Out-Null
    $partialBrokenAlias = Join-PathParts $partial.runtime "skills" "project-bootstrap" "broken"
    if ($isWindowsPlatform) { New-Item -ItemType Junction -Path $partialBrokenAlias -Target $partialBrokenTarget | Out-Null }
    else { New-Item -ItemType SymbolicLink -Path $partialBrokenAlias -Target $partialBrokenTarget | Out-Null }
    [System.IO.Directory]::Delete($partialBrokenTarget, $true)
    Write-StatusManifest -RuntimeRoot $partial.runtime -Value $partial.manifest
    $partialPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $partial.runtime)
    Assert-StatusCondition -Condition ([string]$partialPayload.runtime.managed_files.status -eq "unknown" -and [string]$partialPayload.runtime.managed_files.reason -eq "path-unresolvable" -and [int]$partialPayload.runtime.managed_files.counts.current -eq 0 -and [int]$partialPayload.runtime.managed_files.counts.unknown -eq 2 -and @($partialPayload.runtime.managed_files.problems).Count -eq 0) -Message "Section-wide unknown retained partial managed file results."
    $evidence.Add([ordered]@{ scenario = "managed-partial-then-unresolvable"; status = [string]$partialPayload.runtime.managed_files.status })

    foreach ($emptyCase in @("directory", "missing", "file", "alias", "unresolvable")) {
        $empty = New-ManagedStatusFixture -Name ("managed-empty-item-{0}" -f $emptyCase)
        [System.IO.File]::Delete($empty.live_path)
        $empty.manifest.items[0].files = @()
        $emptyRoot = Join-PathParts $empty.runtime "skills" "project-bootstrap"
        if ($emptyCase -eq "missing") { [System.IO.Directory]::Delete($emptyRoot, $true) }
        elseif ($emptyCase -eq "file") { [System.IO.Directory]::Delete($emptyRoot, $true); Write-StatusText -Path $emptyRoot -Text "occupied" }
        elseif ($emptyCase -eq "alias") {
            [System.IO.Directory]::Delete($emptyRoot, $true)
            $emptyTarget = Join-PathParts $fixtureRoot "managed-empty-item-alias-target"
            New-Item -ItemType Directory -Force -Path $emptyTarget | Out-Null
            if ($isWindowsPlatform) { New-Item -ItemType Junction -Path $emptyRoot -Target $emptyTarget | Out-Null }
            else { New-Item -ItemType SymbolicLink -Path $emptyRoot -Target $emptyTarget | Out-Null }
        }
        elseif ($emptyCase -eq "unresolvable") {
            [System.IO.Directory]::Delete((Join-PathParts $empty.runtime "skills"), $true)
            $emptyBrokenTarget = Join-PathParts $fixtureRoot "managed-empty-item-broken-target"
            New-Item -ItemType Directory -Force -Path $emptyBrokenTarget | Out-Null
            if ($isWindowsPlatform) { New-Item -ItemType Junction -Path (Join-PathParts $empty.runtime "skills") -Target $emptyBrokenTarget | Out-Null }
            else { New-Item -ItemType SymbolicLink -Path (Join-PathParts $empty.runtime "skills") -Target $emptyBrokenTarget | Out-Null }
            [System.IO.Directory]::Delete($emptyBrokenTarget, $true)
        }
        Write-StatusManifest -RuntimeRoot $empty.runtime -Value $empty.manifest
        $emptyPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $empty.runtime)
        $expectedEmptyStatus = if ($emptyCase -eq "directory") { "current" } elseif ($emptyCase -eq "missing") { "missing" } elseif ($emptyCase -eq "unresolvable") { "unknown" } else { "conflict" }
        Assert-StatusCondition -Condition ([string]$emptyPayload.runtime.managed_files.status -eq $expectedEmptyStatus -and [int]$emptyPayload.runtime.managed_files.tracked_file_count -eq 0) -Message "Empty managed item root status is incorrect."
        if ($emptyCase -notin @("directory", "unresolvable")) {
            Assert-StatusCondition -Condition (@($emptyPayload.runtime.managed_files.problems).Count -eq 1 -and [string]$emptyPayload.runtime.managed_files.problems[0].scope -eq "item" -and [string]$emptyPayload.runtime.managed_files.problems[0].path -eq "skills/project-bootstrap") -Message "Empty managed item root problem is missing."
        }
        if ($emptyCase -eq "file") {
            $emptyText = @((Invoke-Status -RuntimeRoot $empty.runtime -Text).output) -join "`n"
            Assert-StatusCondition -Condition ($emptyText.Contains("Managed files: conflict") -and $emptyText.Contains("- skills/project-bootstrap: conflict")) -Message "Managed text output omitted an empty item root problem."
        }
        $evidence.Add([ordered]@{ scenario = "managed-empty-item-$emptyCase"; status = [string]$emptyPayload.runtime.managed_files.status })
    }

    $mixed = New-ManagedStatusFixture -Name "managed-mixed-priority" -Content "current"
    $currentHash = [string]$mixed.content_hash
    $mixed.manifest.items[0].files = @(
        [ordered]@{ path = "a-current.txt"; source_sha256 = $currentHash; installed_sha256 = $currentHash },
        [ordered]@{ path = "b-modified.txt"; source_sha256 = $currentHash; installed_sha256 = $currentHash },
        [ordered]@{ path = "c-missing.txt"; source_sha256 = $currentHash; installed_sha256 = $currentHash },
        [ordered]@{ path = "d-conflict.txt"; source_sha256 = ("a" * 64); installed_sha256 = $currentHash }
    )
    Write-StatusText -Path (Join-PathParts $mixed.runtime "skills" "project-bootstrap" "a-current.txt") -Text "current"
    Write-StatusText -Path (Join-PathParts $mixed.runtime "skills" "project-bootstrap" "b-modified.txt") -Text "changed"
    Write-StatusText -Path (Join-PathParts $mixed.runtime "skills" "project-bootstrap" "d-conflict.txt") -Text "current"
    [System.IO.File]::Delete($mixed.live_path)
    Write-StatusManifest -RuntimeRoot $mixed.runtime -Value $mixed.manifest
    $mixedPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $mixed.runtime)
    Assert-StatusCondition -Condition ([string]$mixedPayload.runtime.managed_files.status -eq "conflict" -and [int]$mixedPayload.runtime.managed_files.counts.current -eq 1 -and [int]$mixedPayload.runtime.managed_files.counts.modified -eq 1 -and [int]$mixedPayload.runtime.managed_files.counts.missing -eq 1 -and [int]$mixedPayload.runtime.managed_files.counts.conflict -eq 1) -Message "Managed mixed-state priority is unstable."
    Assert-StatusCondition -Condition ((@($mixedPayload.runtime.managed_files.problems | ForEach-Object path) -join ",") -eq "skills/project-bootstrap/b-modified.txt,skills/project-bootstrap/c-missing.txt,skills/project-bootstrap/d-conflict.txt") -Message "Managed problems are not canonically sorted."
    $evidence.Add([ordered]@{ scenario = "managed-mixed-priority"; status = [string]$mixedPayload.runtime.managed_files.status })

    foreach ($invalidContract in @(
            [ordered]@{ name = "absolute-path"; mutate = { param($m) $m.items[0].files[0].path = if ($isWindowsPlatform) { "C:/outside.txt" } else { "/outside.txt" } } },
            [ordered]@{ name = "traversal"; mutate = { param($m) $m.items[0].files[0].path = "../outside.txt" } },
            [ordered]@{ name = "duplicate-item"; mutate = { param($m) $m.items = @($m.items[0], $m.items[0]) } },
            [ordered]@{ name = "duplicate-file"; mutate = { param($m) $m.items[0].files = @($m.items[0].files[0], $m.items[0].files[0]) } },
            [ordered]@{ name = "case-conflict"; mutate = { param($m) $other = [ordered]@{ path = "skill.md"; source_sha256 = $m.items[0].files[0].source_sha256; installed_sha256 = $m.items[0].files[0].installed_sha256 }; $m.items[0].files = @($m.items[0].files[0], $other) } },
            [ordered]@{ name = "uppercase-hash"; mutate = { param($m) $m.items[0].files[0].installed_sha256 = ([string]$m.items[0].files[0].installed_sha256).ToUpperInvariant() } },
            [ordered]@{ name = "scalar-file"; mutate = { param($m) $m.items[0].files = @("invalid") } },
            [ordered]@{ name = "null-file"; mutate = { param($m) $m.items[0].files = @($null) } }
        )) {
        $invalidFixture = New-ManagedStatusFixture -Name ("managed-invalid-{0}" -f $invalidContract.name)
        & $invalidContract.mutate $invalidFixture.manifest
        Write-StatusManifest -RuntimeRoot $invalidFixture.runtime -Value $invalidFixture.manifest
        $invalidPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $invalidFixture.runtime)
        Assert-StatusCondition -Condition ([string]$invalidPayload.runtime.managed_files.status -eq "unknown" -and [string]$invalidPayload.runtime.managed_files.reason -eq "contract-invalid" -and @($invalidPayload.findings | Where-Object code -eq "runtime.managed.contract_invalid").Count -eq 1) -Message "Invalid managed contract did not fail soft."
        $evidence.Add([ordered]@{ scenario = "managed-invalid-$($invalidContract.name)"; status = [string]$invalidPayload.runtime.managed_files.status })
    }

    $safeJson = @((Invoke-Status -RuntimeRoot $managedModified.runtime).output) -join "`n"
    $safeText = @((Invoke-Status -RuntimeRoot $managedModified.runtime -Text).output) -join "`n"
    foreach ($privateValue in @([System.IO.Path]::GetFullPath($managedModified.runtime), $managedModified.content_hash, $env:USERNAME)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$privateValue)) {
            Assert-StatusCondition -Condition (-not $safeJson.Contains([string]$privateValue) -and -not $safeText.Contains([string]$privateValue)) -Message "Managed status exposed private path or hash data."
        }
    }
    Assert-StatusCondition -Condition ($safeText.Contains("Managed files: modified") -and $safeText.Contains("- skills/project-bootstrap/SKILL.md: modified")) -Message "Managed text output was not rendered from the payload."
    $evidence.Add([ordered]@{ scenario = "managed-public-safe-text-json"; status = "current" })

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

    # --- C3.3 active profile matrix + historical dormant candidate ---
    $expectedRetiredForStatus = @("project-context-gate", "memory-governance", "workflow-spec-lite")
    $fullAuthorityForStatus = @("project-bootstrap", "project-workspace")
    $minimalAuthorityForStatus = @("project-bootstrap")
    $fullPackagedForStatus = @("skills/project-workspace", "schemas/project-workspace", "templates/project", "scripts/migrate-project.ps1")

    function New-C33Workspace {
        param(
            [string]$Lifecycle = "active",
            [bool]$DefaultCutover = $true,
            [object[]]$Authority = @(),
            [object[]]$Packaged = @()
        )
        return [ordered]@{
            architecture = "c3.3"
            lifecycle = $Lifecycle
            default_cutover = $DefaultCutover
            packaged_content = @($Packaged)
            c3_3_authority = @($Authority)
            legacy_only_compatibility_payload = @()
            retired_from_c3_3_authority = @($expectedRetiredForStatus)
            compatibility_aliases = $false
            automatic_forwarding = $false
            dual_write = $false
            project_local_authority = "project-local"
            derived_cache = ".agents/.cache/catalog.json"
        }
    }

    function New-C33StatusManifest {
        param(
            [Parameter(Mandatory = $true)][string]$Profile,
            [Parameter(Mandatory = $true)][object]$Workspace
        )
        $manifest = New-CurrentManifest
        $manifest.profile = $Profile
        $manifest.workspace = $Workspace
        return $manifest
    }

    function Assert-C33ContractInvalid {
        param(
            [Parameter(Mandatory = $true)][string]$RuntimeRoot,
            [Parameter(Mandatory = $true)][string]$Scenario
        )
        $payload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $RuntimeRoot)
        Assert-StatusCondition -Condition (@($payload.findings | Where-Object code -eq "runtime.workspace.contract_invalid").Count -eq 1 -and
            [string]$payload.runtime.workspace.lifecycle -eq "unknown") -Message "C3.3 $Scenario did not fail closed as contract_invalid."
        $evidence.Add([ordered]@{ scenario = "c33-$Scenario-contract-invalid"; lifecycle = [string]$payload.runtime.workspace.lifecycle })
    }

    $recActive = New-C33StatusManifest -Profile "recommended" -Workspace (New-C33Workspace -Authority $fullAuthorityForStatus -Packaged $fullPackagedForStatus)
    $recActiveRuntime = Join-PathParts $fixtureRoot "c33-active-recommended"
    Write-StatusManifest -RuntimeRoot $recActiveRuntime -Value $recActive
    $recActivePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $recActiveRuntime)
    Assert-StatusCondition -Condition ([string]$recActivePayload.runtime.workspace.architecture -eq "c3.3" -and
        [string]$recActivePayload.runtime.workspace.lifecycle -eq "active" -and
        [bool]$recActivePayload.runtime.workspace.default_cutover -and
        @($recActivePayload.findings | Where-Object code -eq "runtime.workspace.contract_invalid").Count -eq 0) -Message "Valid recommended active C3.3 contract was not accepted."
    $evidence.Add([ordered]@{ scenario = "c33-active-recommended"; lifecycle = [string]$recActivePayload.runtime.workspace.lifecycle })

    $absentRetiredHelper = Join-PathParts $fixtureRoot "helpers" "retired-helper-absent.ps1"
    $c33CurrentProject = New-C33ProjectStatusFixture -Name "current"
    $c33CurrentBefore = @(Get-ProjectFixtureTreeState -Root $c33CurrentProject.root)
    $c33CurrentRun = Invoke-Status `
        -RuntimeRoot $recActiveRuntime `
        -ProjectRoot $c33CurrentProject.root `
        -LockHelper $absentRetiredHelper `
        -UpgradeHelper $absentRetiredHelper `
        -DiagnoseHelper $absentRetiredHelper
    $c33CurrentText = @($c33CurrentRun.output) -join "`n"
    $c33CurrentPayload = Read-StatusPayload -Run $c33CurrentRun
    Assert-StatusCondition -Condition (
        [string]$c33CurrentPayload.project.status -ceq "current" -and
        [string]$c33CurrentPayload.project.reason -ceq "canonical-layout-present" -and
        [string]$c33CurrentPayload.project.workspace.status -ceq "current" -and
        [string]$c33CurrentPayload.project.workspace.layout -ceq "complete" -and
        [string]$c33CurrentPayload.project.workspace.runtime_boundary -ceq "separate" -and
        [string]$c33CurrentPayload.project.workspace.readiness -ceq "active-ready" -and
        [string]$c33CurrentPayload.recommended_next_action -ceq "none"
    ) -Message "Active C3.3 workspace did not own the top-level Project status."
    Assert-StatusCondition -Condition (-not $c33CurrentText.Contains("memory-helper-unavailable")) -Message "Active C3.3 status still depended on a retired memory helper."
    Assert-StatusCondition -Condition ((@($c33CurrentBefore) -join "`n") -ceq (@(Get-ProjectFixtureTreeState -Root $c33CurrentProject.root) -join "`n")) -Message "Active C3.3 status modified the project fixture."
    $evidence.Add([ordered]@{ scenario = "c33-project-current-retired-helpers-absent"; status = [string]$c33CurrentPayload.project.status; readiness = [string]$c33CurrentPayload.project.workspace.readiness })

    $c33LegacyProject = New-C33ProjectStatusFixture -Name "legacy" -WorkspaceModel "legacy" -WorkspaceState "not-enabled"
    $c33LegacyPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $recActiveRuntime -ProjectRoot $c33LegacyProject.root -LockHelper $absentRetiredHelper -UpgradeHelper $absentRetiredHelper -DiagnoseHelper $absentRetiredHelper)
    Assert-StatusCondition -Condition (
        [string]$c33LegacyPayload.project.status -ceq "migration-required" -and
        [string]$c33LegacyPayload.project.reason -ceq "legacy-workspace" -and
        [string]$c33LegacyPayload.project.workspace.readiness -ceq "not-c3-3" -and
        [string]$c33LegacyPayload.recommended_next_action -ceq "run-project-migration-analysis"
    ) -Message "Legacy project did not route exclusively to the C3.3 project migration authority."
    $evidence.Add([ordered]@{ scenario = "c33-project-legacy-migration"; status = [string]$c33LegacyPayload.project.status; next_action = [string]$c33LegacyPayload.recommended_next_action })

    $c33MalformedProject = New-C33ProjectStatusFixture -Name "malformed"
    Write-StatusText -Path $c33MalformedProject.lock_path -Text '{"schema_version":'
    $c33MalformedPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $recActiveRuntime -ProjectRoot $c33MalformedProject.root -LockHelper $absentRetiredHelper -UpgradeHelper $absentRetiredHelper -DiagnoseHelper $absentRetiredHelper)
    Assert-StatusCondition -Condition (
        [string]$c33MalformedPayload.project.status -ceq "unknown" -and
        [string]$c33MalformedPayload.project.reason -ceq "invalid-workspace-metadata" -and
        [string]$c33MalformedPayload.project.workspace.status -ceq "unknown" -and
        [string]$c33MalformedPayload.project.workspace.readiness -ceq "unknown"
    ) -Message "Malformed C3.3 workspace metadata did not fail closed."
    $evidence.Add([ordered]@{ scenario = "c33-project-malformed"; status = [string]$c33MalformedPayload.project.status })

    $c33SchemaProject = New-C33ProjectStatusFixture -Name "schema-missing"
    $c33SchemaProject.lock.Remove("schema_version")
    Write-StatusText -Path $c33SchemaProject.lock_path -Text ($c33SchemaProject.lock | ConvertTo-Json -Depth 8)
    $c33SchemaPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $recActiveRuntime -ProjectRoot $c33SchemaProject.root -LockHelper $absentRetiredHelper -UpgradeHelper $absentRetiredHelper -DiagnoseHelper $absentRetiredHelper)
    Assert-StatusCondition -Condition ([string]$c33SchemaPayload.project.status -ceq "unknown" -and [string]$c33SchemaPayload.project.reason -ceq "invalid-workspace-metadata") -Message "Schema-less C3.3 workspace metadata was reported as current."
    $evidence.Add([ordered]@{ scenario = "c33-project-schema-missing"; status = [string]$c33SchemaPayload.project.status })

    $c33MissingRoot = Join-PathParts $fixtureRoot "c33-project-missing"
    $c33MissingPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $recActiveRuntime -ProjectRoot $c33MissingRoot -LockHelper $absentRetiredHelper -UpgradeHelper $absentRetiredHelper -DiagnoseHelper $absentRetiredHelper)
    Assert-StatusCondition -Condition ([string]$c33MissingPayload.project.status -ceq "unknown" -and [string]$c33MissingPayload.project.reason -ceq "project-not-found" -and [string]$c33MissingPayload.project.workspace.status -ceq "missing") -Message "Missing C3.3 project did not fail closed."
    $evidence.Add([ordered]@{ scenario = "c33-project-missing"; status = [string]$c33MissingPayload.project.status })

    $minActive = New-C33StatusManifest -Profile "minimal" -Workspace (New-C33Workspace -Authority $minimalAuthorityForStatus)
    $minActiveRuntime = Join-PathParts $fixtureRoot "c33-active-minimal"
    Write-StatusManifest -RuntimeRoot $minActiveRuntime -Value $minActive
    $minActivePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $minActiveRuntime)
    Assert-StatusCondition -Condition ([string]$minActivePayload.runtime.workspace.architecture -eq "c3.3" -and
        [string]$minActivePayload.runtime.workspace.lifecycle -eq "active" -and
        [bool]$minActivePayload.runtime.workspace.default_cutover -and
        @($minActivePayload.runtime.workspace.c3_3_authority).Count -eq 1 -and
        @($minActivePayload.runtime.workspace.packaged_content).Count -eq 0 -and
        @($minActivePayload.findings | Where-Object code -eq "runtime.workspace.contract_invalid").Count -eq 0) -Message "Valid minimal active C3.3 contract was not accepted."
    $evidence.Add([ordered]@{ scenario = "c33-active-minimal"; lifecycle = [string]$minActivePayload.runtime.workspace.lifecycle })

    $recAsMinimal = New-C33StatusManifest -Profile "recommended" -Workspace (New-C33Workspace -Authority $minimalAuthorityForStatus)
    $recAsMinimalRuntime = Join-PathParts $fixtureRoot "c33-recommended-minimal-contract"
    Write-StatusManifest -RuntimeRoot $recAsMinimalRuntime -Value $recAsMinimal
    Assert-C33ContractInvalid -RuntimeRoot $recAsMinimalRuntime -Scenario "recommended-minimal-contract"

    $minAsFull = New-C33StatusManifest -Profile "minimal" -Workspace (New-C33Workspace -Authority $fullAuthorityForStatus -Packaged $fullPackagedForStatus)
    $minAsFullRuntime = Join-PathParts $fixtureRoot "c33-minimal-full-contract"
    Write-StatusManifest -RuntimeRoot $minAsFullRuntime -Value $minAsFull
    Assert-C33ContractInvalid -RuntimeRoot $minAsFullRuntime -Scenario "minimal-full-contract"

    $dormantCandidate = New-C33StatusManifest -Profile "c3-3-candidate" -Workspace (New-C33Workspace -Lifecycle "dormant" -DefaultCutover $false -Authority $fullAuthorityForStatus -Packaged $fullPackagedForStatus)
    $dormantCandidateRuntime = Join-PathParts $fixtureRoot "c33-dormant-candidate"
    Write-StatusManifest -RuntimeRoot $dormantCandidateRuntime -Value $dormantCandidate
    $dormantPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $dormantCandidateRuntime)
    Assert-StatusCondition -Condition ([string]$dormantPayload.runtime.workspace.architecture -eq "c3.3" -and
        [string]$dormantPayload.runtime.workspace.lifecycle -eq "dormant" -and
        [bool]$dormantPayload.runtime.workspace.default_cutover -eq $false -and
        @($dormantPayload.findings | Where-Object code -eq "runtime.workspace.contract_invalid").Count -eq 0) -Message "Historical dormant candidate contract was not reported read-only."
    $evidence.Add([ordered]@{ scenario = "c33-dormant-candidate-readonly"; lifecycle = [string]$dormantPayload.runtime.workspace.lifecycle })

    $dormantWrongPackage = New-C33StatusManifest -Profile "c3-3-candidate" -Workspace (New-C33Workspace -Lifecycle "dormant" -DefaultCutover $false -Authority $fullAuthorityForStatus)
    $dormantWrongPackageRuntime = Join-PathParts $fixtureRoot "c33-dormant-candidate-wrong-package"
    Write-StatusManifest -RuntimeRoot $dormantWrongPackageRuntime -Value $dormantWrongPackage
    Assert-C33ContractInvalid -RuntimeRoot $dormantWrongPackageRuntime -Scenario "dormant-candidate-wrong-package"

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
            "Recommended next action: $([string]$nullPayload.recommended_next_action)",
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

    $notRequested = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime)
    Assert-StatusCondition -Condition ([string]$notRequested.project.status -eq "unknown" -and [string]$notRequested.project.reason -eq "not-requested") -Message "Omitted ProjectDir did not remain not-requested."
    $evidence.Add([ordered]@{ scenario = "project-not-requested"; status = [string]$notRequested.project.status })

    $managedCopyCurrent = New-ManagedCopyProjectFixture -Name "current"
    $managedCopyProjectBefore = @(Get-ProjectFixtureTreeState $managedCopyCurrent.project.root)
    $managedCopyRuntimeBefore = @(Get-StatusTreeState -RuntimeRoot $managedCopyCurrent.runtime)
    $managedCopyCurrentPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedCopyCurrent.runtime -ProjectRoot $managedCopyCurrent.project.root)
    Assert-StatusCondition -Condition (
        [string]$managedCopyCurrentPayload.project.status -eq "current" -and
        [string]$managedCopyCurrentPayload.project.reason -eq "in-sync" -and
        [string]$managedCopyCurrentPayload.recommended_next_action -eq "none"
    ) -Message "Trusted managed copy with a matching legacy Git lock did not report current."
    # NOTE: #278 三事实 assertion — trusted managed copy: snapshot current, provenance verified, remote not-checked。
    Assert-StatusCondition -Condition (
        [string]$managedCopyCurrentPayload.project.snapshot_consistency -eq "current" -and
        [string]$managedCopyCurrentPayload.project.source_provenance -eq "verified" -and
        [string]$managedCopyCurrentPayload.project.remote_latest -eq "not-checked"
    ) -Message "Trusted managed copy did not report snapshot current / provenance verified / remote not-checked."
    Assert-StatusCondition -Condition (
        (@($managedCopyProjectBefore) -join "`n") -ceq (@(Get-ProjectFixtureTreeState $managedCopyCurrent.project.root) -join "`n") -and
        (@($managedCopyRuntimeBefore) -join "`n") -ceq (@(Get-StatusTreeState -RuntimeRoot $managedCopyCurrent.runtime) -join "`n")
    ) -Message "Managed-copy project status modified project or runtime files."
    $evidence.Add([ordered]@{ scenario = "project-managed-copy-legacy-current"; status = [string]$managedCopyCurrentPayload.project.status })

    $managedCopyDrift = New-ManagedCopyProjectFixture -Name "template-drift"
    $managedCopyDrift.project.lock.template_tree_hash_sha256 = "0" * 64
    Write-StatusText -Path (Join-PathParts $managedCopyDrift.project.root ".agents" "hub.lock.json") -Text ($managedCopyDrift.project.lock | ConvertTo-Json)
    $managedCopyDriftPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedCopyDrift.runtime -ProjectRoot $managedCopyDrift.project.root)
    Assert-StatusCondition -Condition (
        [string]$managedCopyDriftPayload.project.status -eq "optional-refresh" -and
        [string]$managedCopyDriftPayload.project.reason -eq "template-baseline-drift" -and
        [string]$managedCopyDriftPayload.recommended_next_action -eq "refresh-project-templates"
    ) -Message "Trusted managed copy with template drift did not report optional-refresh."
    # NOTE: #278 三事实 assertion — trusted managed copy template drift: snapshot drift, provenance verified, remote not-checked。
    Assert-StatusCondition -Condition (
        [string]$managedCopyDriftPayload.project.snapshot_consistency -eq "drift" -and
        [string]$managedCopyDriftPayload.project.source_provenance -eq "verified" -and
        [string]$managedCopyDriftPayload.project.remote_latest -eq "not-checked"
    ) -Message "Trusted managed copy template drift did not report snapshot drift / provenance verified / remote not-checked."
    $evidence.Add([ordered]@{ scenario = "project-managed-copy-legacy-template-drift"; status = [string]$managedCopyDriftPayload.project.status })

    $managedCopyFresh = New-ManagedCopyProjectFixture -Name "fresh-copy-lock" -LockKind "copy"
    $managedCopyFreshPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedCopyFresh.runtime -ProjectRoot $managedCopyFresh.project.root)
    Assert-StatusCondition -Condition (
        [string]$managedCopyFreshPayload.project.status -eq "current" -and
        [string]$managedCopyFreshPayload.project.reason -eq "in-sync" -and
        [string]$managedCopyFreshPayload.recommended_next_action -eq "none"
    ) -Message "Fresh copy lock behavior regressed."
    # NOTE: #278 三事实 assertion — trusted managed copy (fresh copy lock): snapshot current, provenance verified (manifest schema 2 + SHA-256 match), remote not-checked。
    Assert-StatusCondition -Condition (
        [string]$managedCopyFreshPayload.project.snapshot_consistency -eq "current" -and
        [string]$managedCopyFreshPayload.project.source_provenance -eq "verified" -and
        [string]$managedCopyFreshPayload.project.remote_latest -eq "not-checked"
    ) -Message "Fresh copy lock did not report snapshot current / provenance verified / remote not-checked."
    $evidence.Add([ordered]@{ scenario = "project-managed-copy-fresh-lock-current"; status = [string]$managedCopyFreshPayload.project.status })

    $managedCopySimilar = New-ManagedCopyProjectFixture -Name "similar-path"
    $similarHub = Join-PathParts $managedCopySimilar.runtime "knowledge-hub-copy"
    Copy-Item -LiteralPath $managedCopySimilar.hub -Destination $similarHub -Recurse
    $managedCopySimilar.project.lock.hub_dir = $similarHub
    Write-StatusText -Path (Join-PathParts $managedCopySimilar.project.root ".agents" "hub.lock.json") -Text ($managedCopySimilar.project.lock | ConvertTo-Json)
    $managedCopySimilarPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedCopySimilar.runtime -ProjectRoot $managedCopySimilar.project.root)
    Assert-StatusCondition -Condition ([string]$managedCopySimilarPayload.project.status -eq "unknown" -and [string]$managedCopySimilarPayload.project.reason -eq "hub-not-git") -Message "Similar managed Hub path was trusted without an exact match."
    $evidence.Add([ordered]@{ scenario = "project-managed-copy-similar-path-rejected"; status = [string]$managedCopySimilarPayload.project.status })

    foreach ($manifestCase in @(
            @{ name = "schema"; mutate = { param($manifest) $manifest.schema_version = 1 } },
            @{ name = "strategy"; mutate = { param($manifest) $manifest.install_strategy = "dev-link" } },
            @{ name = "missing-item"; mutate = { param($manifest) $manifest.items = @() } }
        )) {
        $fixture = New-ManagedCopyProjectFixture -Name ("manifest-{0}" -f $manifestCase.name)
        & $manifestCase.mutate $fixture.manifest
        Write-StatusManifest -RuntimeRoot $fixture.runtime -Value $fixture.manifest
        $payload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $fixture.runtime -ProjectRoot $fixture.project.root)
        Assert-StatusCondition -Condition ([string]$payload.project.status -eq "unknown" -and [string]$payload.project.reason -eq "hub-not-git") -Message "Untrusted managed-copy manifest case $($manifestCase.name) bypassed hub-not-git."
        $evidence.Add([ordered]@{ scenario = "project-managed-copy-manifest-$($manifestCase.name)-rejected"; status = [string]$payload.project.status })
    }

    $managedCopyModified = New-ManagedCopyProjectFixture -Name "managed-modified"
    Write-StatusText -Path $managedCopyModified.first_managed_file -Text "modified managed template"
    $managedCopyModifiedPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedCopyModified.runtime -ProjectRoot $managedCopyModified.project.root)
    Assert-StatusCondition -Condition ([string]$managedCopyModifiedPayload.project.status -eq "unknown" -and [string]$managedCopyModifiedPayload.project.reason -eq "hub-not-git") -Message "Modified managed Hub file bypassed hub-not-git."
    $evidence.Add([ordered]@{ scenario = "project-managed-copy-modified-rejected"; status = [string]$managedCopyModifiedPayload.project.status })

    $managedCopyMissing = New-ManagedCopyProjectFixture -Name "managed-missing"
    Remove-Item -LiteralPath $managedCopyMissing.first_managed_file
    $managedCopyMissingPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedCopyMissing.runtime -ProjectRoot $managedCopyMissing.project.root)
    Assert-StatusCondition -Condition ([string]$managedCopyMissingPayload.project.status -eq "unknown" -and [string]$managedCopyMissingPayload.project.reason -eq "hub-not-git") -Message "Missing managed Hub file bypassed hub-not-git."
    $evidence.Add([ordered]@{ scenario = "project-managed-copy-missing-rejected"; status = [string]$managedCopyMissingPayload.project.status })

    $managedCopyHashInvalid = New-ManagedCopyProjectFixture -Name "managed-hash-invalid"
    $managedCopyHashInvalid.manifest.items[0].files[0].installed_sha256 = "not-a-trusted-hash"
    Write-StatusManifest -RuntimeRoot $managedCopyHashInvalid.runtime -Value $managedCopyHashInvalid.manifest
    $managedCopyHashInvalidPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedCopyHashInvalid.runtime -ProjectRoot $managedCopyHashInvalid.project.root)
    Assert-StatusCondition -Condition ([string]$managedCopyHashInvalidPayload.project.status -eq "unknown" -and [string]$managedCopyHashInvalidPayload.project.reason -eq "hub-not-git") -Message "Invalid managed Hub hash bypassed hub-not-git."
    $evidence.Add([ordered]@{ scenario = "project-managed-copy-invalid-hash-rejected"; status = [string]$managedCopyHashInvalidPayload.project.status })

    $managedCopyPlain = New-ManagedCopyProjectFixture -Name "plain-non-git"
    $plainHub = Join-PathParts $fixtureRoot "plain-non-git-hub"
    Copy-Item -LiteralPath $managedCopyPlain.hub -Destination $plainHub -Recurse
    $managedCopyPlain.project.lock.hub_dir = $plainHub
    Write-StatusText -Path (Join-PathParts $managedCopyPlain.project.root ".agents" "hub.lock.json") -Text ($managedCopyPlain.project.lock | ConvertTo-Json)
    $managedCopyPlainPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $managedCopyPlain.runtime -ProjectRoot $managedCopyPlain.project.root)
    Assert-StatusCondition -Condition ([string]$managedCopyPlainPayload.project.status -eq "unknown" -and [string]$managedCopyPlainPayload.project.reason -eq "hub-not-git") -Message "Plain non-Git Hub with legacy Git provenance stopped failing closed."
    $evidence.Add([ordered]@{ scenario = "project-plain-non-git-legacy-rejected"; status = [string]$managedCopyPlainPayload.project.status })

    $currentProject = New-ProjectStatusFixture -Name "current"
    $projectBefore = @(Get-ProjectFixtureTreeState $currentProject.root)
    $hubBefore = @(Get-ProjectFixtureTreeState $currentProject.hub)
    $currentProjectText = @((Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $currentProject.root).output) -join "`n"
    $currentProjectPayload = $currentProjectText | ConvertFrom-Json
    Assert-StatusCondition -Condition ([string]$currentProjectPayload.project.status -eq "current" -and [string]$currentProjectPayload.project.project_language -eq "en") -Message "Clean project baseline and memory did not report current."
    # NOTE: #278 三事实 assertion — clean Git Hub: snapshot current, provenance verified, remote not-checked。
    Assert-StatusCondition -Condition ([string]$currentProjectPayload.project.snapshot_consistency -eq "current" -and [string]$currentProjectPayload.project.source_provenance -eq "verified" -and [string]$currentProjectPayload.project.remote_latest -eq "not-checked") -Message "Clean Git Hub did not report snapshot current / provenance verified / remote not-checked."
    Assert-StatusCondition -Condition ((@($projectBefore) -join "`n") -ceq (@(Get-ProjectFixtureTreeState $currentProject.root) -join "`n") -and (@($hubBefore) -join "`n") -ceq (@(Get-ProjectFixtureTreeState $currentProject.hub) -join "`n")) -Message "Project status modified project or hub files."
    foreach ($privateValue in @($currentProject.root, $currentProject.hub, "https://example.invalid/hub.git", [Environment]::UserName, [string]$currentProject.lock.hub_commit, [string]$currentProject.lock.template_tree_hash_sha256)) {
        Assert-StatusCondition -Condition (-not $currentProjectText.Contains($privateValue)) -Message "Project JSON leaked private helper data."
    }
    $evidence.Add([ordered]@{ scenario = "project-current-read-only-public-safe"; status = [string]$currentProjectPayload.project.status })

    # NOTE: #280 证据转入 #278 — repository dirty 但 template subtree hash 一致时：
    # snapshot_consistency 独立报告 current；source_provenance 因 dirty 报告 limited；
    # status/reason 保持 unknown/current-hub-dirty 以兼容 schema-1 消费方；remote_latest 固定 not-checked。
    $dirtyHubProject = New-ProjectStatusFixture -Name "git-hub-dirty"
    Write-StatusText -Path (Join-PathParts $dirtyHubProject.hub "sibling-dirty-marker.txt") -Text "non-template sibling file"
    $dirtyHubPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $dirtyHubProject.root)
    Assert-StatusCondition -Condition ([string]$dirtyHubPayload.project.status -eq "unknown" -and [string]$dirtyHubPayload.project.reason -eq "current-hub-dirty") -Message "Dirty Git Hub did not keep schema-1 unknown/current-hub-dirty for compatibility."
    Assert-StatusCondition -Condition ([string]$dirtyHubPayload.project.snapshot_consistency -eq "current" -and [string]$dirtyHubPayload.project.source_provenance -eq "limited" -and [string]$dirtyHubPayload.project.remote_latest -eq "not-checked") -Message "Dirty Git Hub with matching template hash did not report snapshot current / provenance limited / remote not-checked."
    $evidence.Add([ordered]@{ scenario = "project-git-hub-dirty-snapshot-current"; status = [string]$dirtyHubPayload.project.status })

    # NOTE: #278 text / JSON 一致性检查 — checker text、checker JSON、status JSON、status text 对三事实使用一致语义。
    $checkerScript = Join-Path $repoRoot "skills/project-bootstrap/scripts/check_hub_lock.ps1"
    $checkerJsonRun = Invoke-IsolatedPowerShellScript -ScriptPath $checkerScript -Arguments @("-ProjectDir", $dirtyHubProject.root, "-Json")
    $checkerTextRun = Invoke-IsolatedPowerShellScript -ScriptPath $checkerScript -Arguments @("-ProjectDir", $dirtyHubProject.root)
    $checkerJson = (@($checkerJsonRun.output) -join "`n") | ConvertFrom-Json
    $checkerResult = $checkerJson.results[0]
    $checkerTextOutput = @($checkerTextRun.output) -join "`n"
    Assert-StatusCondition -Condition ([string]$checkerResult.snapshot_consistency -eq "current" -and [string]$checkerResult.source_provenance -eq "limited" -and [string]$checkerResult.remote_latest -eq "not-checked") -Message "Checker JSON did not report three facts consistently for dirty Git Hub."
    Assert-StatusCondition -Condition ($checkerTextOutput -match "Snapshot consistency: current" -and $checkerTextOutput -match "Source provenance: limited" -and $checkerTextOutput -match "Remote latest: not-checked") -Message "Checker text did not display three facts consistently for dirty Git Hub."
    Assert-StatusCondition -Condition ($checkerTextOutput -match "Status: unknown") -Message "Checker text still projected unknown/current-hub-dirty as drift (#280 regression)."
    # NOTE: status text 也必须显示三事实，与 status JSON 一致。
    $statusTextOutput = @((Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $dirtyHubProject.root -Text).output) -join "`n"
    Assert-StatusCondition -Condition ($statusTextOutput -match "Snapshot consistency: current" -and $statusTextOutput -match "Source provenance: limited" -and $statusTextOutput -match "Remote latest: not-checked") -Message "Status text did not display three facts consistently for dirty Git Hub."
    $evidence.Add([ordered]@{ scenario = "project-git-hub-dirty-text-json-consistency"; status = [string]$checkerResult.snapshot_consistency })
    # NOTE: #289 组合 provenance 异常回归 — locked-hub-dirty 与 remote/branch drift 同时存在时，
    # lock 记录的 template hash 是从 dirty Hub 生成的，不是可信 snapshot baseline；
    # 即使当前 template hash 恰好与 dirty lock hash 相同，snapshot 也必须 fail-closed 为 unknown。
    # 三事实映射依据完整 reason_codes（locked-hub-dirty 优先），不受主 reason 插入顺序影响。
    # source_provenance = limited，remote_latest = not-checked，schema-1 status/reason 保持兼容。
    # 控制场景 remote-drift-only（无 locked-hub-dirty、hash 可验证）证明 snapshot 仍按设计报告 current。
    $combinedProvenanceCases = @(
        @{ name = "project-locked-dirty-remote-drift-fail-closed"; expectedReason = "hub-remote-drift"; snapshot = "unknown"; mutate = { param($lock) $lock.hub_dirty = $true; $lock.hub_remote = "https://example.invalid/other-hub.git" } },
        @{ name = "project-locked-dirty-branch-drift-fail-closed"; expectedReason = "hub-branch-drift"; snapshot = "unknown"; mutate = { param($lock) $lock.hub_dirty = $true; $lock.hub_branch = "release" } },
        @{ name = "project-remote-drift-verifiable-snapshot-current"; expectedReason = "hub-remote-drift"; snapshot = "current"; mutate = { param($lock) $lock.hub_remote = "https://example.invalid/other-hub.git" } }
    )
    foreach ($combinedCase in $combinedProvenanceCases) {
        $combinedFixture = New-ProjectStatusFixture -Name $combinedCase.name
        & $combinedCase.mutate $combinedFixture.lock
        Write-StatusText -Path (Join-PathParts $combinedFixture.root ".agents" "hub.lock.json") -Text ($combinedFixture.lock | ConvertTo-Json)

        # status JSON：schema-1 status/reason 兼容 + 三事实
        $combinedStatusPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $combinedFixture.root)
        Assert-StatusCondition -Condition ([string]$combinedStatusPayload.project.status -eq "unknown" -and [string]$combinedStatusPayload.project.reason -eq $combinedCase.expectedReason) -Message "Combined case $($combinedCase.name) did not keep schema-1 unknown/$($combinedCase.expectedReason)."
        Assert-StatusCondition -Condition ([string]$combinedStatusPayload.project.snapshot_consistency -eq $combinedCase.snapshot -and [string]$combinedStatusPayload.project.source_provenance -eq "limited" -and [string]$combinedStatusPayload.project.remote_latest -eq "not-checked") -Message "Combined case $($combinedCase.name) status JSON did not report snapshot $($combinedCase.snapshot) / provenance limited / remote not-checked."

        # checker JSON：三事实 + status/reason 与 status provider 一致
        $combinedCheckerJsonRun = Invoke-IsolatedPowerShellScript -ScriptPath $checkerScript -Arguments @("-ProjectDir", $combinedFixture.root, "-Json")
        $combinedCheckerResult = ((@($combinedCheckerJsonRun.output) -join "`n") | ConvertFrom-Json).results[0]
        Assert-StatusCondition -Condition ([string]$combinedCheckerResult.snapshot_consistency -eq $combinedCase.snapshot -and [string]$combinedCheckerResult.source_provenance -eq "limited" -and [string]$combinedCheckerResult.remote_latest -eq "not-checked") -Message "Combined case $($combinedCase.name) checker JSON did not report three facts consistently."
        Assert-StatusCondition -Condition ([string]$combinedCheckerResult.status -eq "unknown" -and [string]$combinedCheckerResult.reason -eq $combinedCase.expectedReason -and (@($combinedCheckerResult.reason_codes) -contains "locked-hub-dirty") -eq ($combinedCase.snapshot -eq "unknown")) -Message "Combined case $($combinedCase.name) checker JSON status/reason/reason_codes drifted."

        # checker text 与 checker JSON 三事实一致
        $combinedCheckerTextRun = Invoke-IsolatedPowerShellScript -ScriptPath $checkerScript -Arguments @("-ProjectDir", $combinedFixture.root)
        $combinedCheckerText = @($combinedCheckerTextRun.output) -join "`n"
        Assert-StatusCondition -Condition ($combinedCheckerText -match ("Snapshot consistency: {0}" -f $combinedCase.snapshot) -and $combinedCheckerText -match "Source provenance: limited" -and $combinedCheckerText -match "Remote latest: not-checked") -Message "Combined case $($combinedCase.name) checker text did not display three facts consistently."

        # status text 与 status JSON 三事实一致
        $combinedStatusText = @((Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $combinedFixture.root -Text).output) -join "`n"
        Assert-StatusCondition -Condition ($combinedStatusText -match ("Snapshot consistency: {0}" -f $combinedCase.snapshot) -and $combinedStatusText -match "Source provenance: limited" -and $combinedStatusText -match "Remote latest: not-checked") -Message "Combined case $($combinedCase.name) status text did not display three facts consistently."

        $evidence.Add([ordered]@{ scenario = $combinedCase.name; status = [string]$combinedCheckerResult.snapshot_consistency })
    }

    $legacyProject = New-ProjectStatusFixture -Name "legacy"
    $legacyProject.lock.Remove("template_tree_hash_sha256")
    Write-StatusText -Path (Join-PathParts $legacyProject.root ".agents" "hub.lock.json") -Text ($legacyProject.lock | ConvertTo-Json)
    $legacyPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $legacyProject.root)
    Assert-StatusCondition -Condition ([string]$legacyPayload.project.status -eq "optional-refresh" -and [string]$legacyPayload.project.baseline.status -eq "optional-refresh") -Message "Legacy lock without template hash did not report optional-refresh."
    $evidence.Add([ordered]@{ scenario = "project-legacy-lock-refresh"; status = [string]$legacyPayload.project.status })

    $migrationProject = New-ProjectStatusFixture -Name "migration"
    Write-StatusText -Path (Join-PathParts $migrationProject.root ".agents" "notes.md") -Text "todo next step"
    $migrationPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $migrationProject.root)
    Assert-StatusCondition -Condition ([string]$migrationPayload.project.status -eq "migration-required" -and [int]$migrationPayload.project.memory.migration_finding_count -gt 0 -and @($migrationPayload.project.memory.finding_codes) -contains "notes_contains_session_state") -Message "Structural memory finding did not report migration-required."
    $evidence.Add([ordered]@{ scenario = "project-memory-migration"; status = [string]$migrationPayload.project.status })

    $missingScaffoldProject = New-ProjectStatusFixture -Name "missing-scaffold"
    Remove-Item -LiteralPath (Join-PathParts $missingScaffoldProject.root ".agents" "notes.md")
    $refreshPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $missingScaffoldProject.root)
    Assert-StatusCondition -Condition ([string]$refreshPayload.project.status -eq "optional-refresh" -and [int]$refreshPayload.project.memory.refresh_finding_count -gt 0) -Message "Missing scaffold did not report optional-refresh."
    $evidence.Add([ordered]@{ scenario = "project-missing-scaffold-refresh"; status = [string]$refreshPayload.project.status })

    $missingLockProject = New-ProjectStatusFixture -Name "missing-lock"
    Remove-Item -LiteralPath (Join-PathParts $missingLockProject.root ".agents" "hub.lock.json")
    Write-StatusText -Path (Join-PathParts $missingLockProject.root ".agents" "notes.md") -Text "todo next step"
    $missingLockPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $missingLockProject.root)
    Assert-StatusCondition -Condition ([string]$missingLockPayload.project.status -eq "unknown" -and [string]$missingLockPayload.project.reason -eq "missing-lock") -Message "Missing lock was not dominant unknown."
    $evidence.Add([ordered]@{ scenario = "project-missing-lock-unknown"; status = [string]$missingLockPayload.project.status })

    $languageProject = New-ProjectStatusFixture -Name "zh" -Language "zh-CN"
    $languagePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $languageProject.root)
    Assert-StatusCondition -Condition ([string]$languagePayload.project.project_language -eq "zh-CN") -Message "zh-CN template baseline was not selected."
    $languageProject.lock.Remove("project_language")
    Write-StatusText -Path (Join-PathParts $languageProject.root ".agents" "hub.lock.json") -Text ($languageProject.lock | ConvertTo-Json)
    $guideLanguagePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $languageProject.root)
    Assert-StatusCondition -Condition ([string]$guideLanguagePayload.project.project_language -eq "zh-CN") -Message "Project guide language fallback was not used."
    $languageProject.lock.project_language = "en"
    Write-StatusText -Path (Join-PathParts $languageProject.root ".agents" "hub.lock.json") -Text ($languageProject.lock | ConvertTo-Json)
    $conflictLanguagePayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $languageProject.root)
    Assert-StatusCondition -Condition ([string]$conflictLanguagePayload.project.status -eq "unknown" -and $null -eq $conflictLanguagePayload.project.project_language) -Message "Conflicting project language did not report unknown/null."
    $evidence.Add([ordered]@{ scenario = "project-language-resolution"; status = [string]$conflictLanguagePayload.project.status })

    $templateDriftProject = New-ProjectStatusFixture -Name "template-drift"
    $templateDriftProject.lock.template_tree_hash_sha256 = "0" * 64
    Write-StatusText -Path (Join-PathParts $templateDriftProject.root ".agents" "hub.lock.json") -Text ($templateDriftProject.lock | ConvertTo-Json)
    $templateDriftPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $templateDriftProject.root)
    Assert-StatusCondition -Condition ([string]$templateDriftPayload.project.status -eq "optional-refresh") -Message "Template hash drift did not report optional-refresh."
    Write-StatusText -Path (Join-PathParts $templateDriftProject.root ".agents" "notes.md") -Text "todo next step"
    $driftMigrationPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $templateDriftProject.root)
    Assert-StatusCondition -Condition ([string]$driftMigrationPayload.project.status -eq "migration-required") -Message "Migration finding did not dominate baseline drift."
    $evidence.Add([ordered]@{ scenario = "project-baseline-drift-migration-priority"; status = [string]$driftMigrationPayload.project.status })

    $diagnosticProject = New-ProjectStatusFixture -Name "diagnostic"
    Write-StatusText -Path (Join-PathParts $diagnosticProject.root ".agents" "context" "detail.md") -Text "fixture"
    $diagnosticPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $diagnosticProject.root)
    Assert-StatusCondition -Condition ([string]$diagnosticPayload.project.status -eq "current" -and [int]$diagnosticPayload.project.memory.migration_finding_count -eq 0 -and [int]$diagnosticPayload.project.memory.diagnostic_warning_count -gt 0) -Message "Diagnostic-only finding changed project drift status."
    $evidence.Add([ordered]@{ scenario = "project-diagnostic-only"; status = [string]$diagnosticPayload.project.status })

    $validLockHelper = New-StatusHelperFixture -Name "lock-valid" -Kind "lock" -Json '{"schema_version":1,"results":[{"status":"in-sync","reason":"hub-lock-in-sync","project_language":"en"}]}'
    $validUpgradeHelper = New-StatusHelperFixture -Name "upgrade-valid" -Kind "upgrade" -Json '{"findings":[]}'
    $validDiagnoseHelper = New-StatusHelperFixture -Name "diagnose-valid" -Kind "diagnose" -Json '{"findings":[]}'
    $separator = [string][char]92
    $maliciousValue = "C:{0}Users{0}private-{1}{0}data" -f $separator, "user"
    $lockContractCases = @(
        @{ name = "schema-string"; json = '{"schema_version":"bad","results":[{"status":"in-sync","reason":"hub-lock-in-sync","project_language":"en"}]}' },
        @{ name = "results-null"; json = '{"schema_version":1,"results":null}' },
        @{ name = "results-empty"; json = '{"schema_version":1,"results":[]}' },
        @{ name = "results-multiple"; json = '{"schema_version":1,"results":[{},{}]}' },
        @{ name = "result-scalar"; json = '{"schema_version":1,"results":[7]}' },
        @{ name = "result-array"; json = '{"schema_version":1,"results":[[]]}' },
        @{ name = "unknown-status"; json = '{"schema_version":1,"results":[{"status":"unsafe","reason":"hub-lock-in-sync","project_language":"en"}]}' },
        @{ name = "unknown-reason"; json = '{"schema_version":1,"results":[{"status":"unknown","reason":"__VALUE__","project_language":null}]}'.Replace('__VALUE__', ($maliciousValue -replace '\\','\\')) },
        @{ name = "invalid-language"; json = '{"schema_version":1,"results":[{"status":"in-sync","reason":"hub-lock-in-sync","project_language":"private"}]}' },
        @{ name = "in-sync-missing-lock-null"; json = '{"schema_version":1,"results":[{"status":"in-sync","reason":"missing-lock","project_language":null}]}' },
        @{ name = "in-sync-language-null"; json = '{"schema_version":1,"results":[{"status":"in-sync","reason":"hub-lock-in-sync","project_language":null}]}' },
        @{ name = "drift-invalid-lock-en"; json = '{"schema_version":1,"results":[{"status":"drift","reason":"invalid-lock","project_language":"en"}]}' },
        @{ name = "unknown-in-sync-null"; json = '{"schema_version":1,"results":[{"status":"unknown","reason":"hub-lock-in-sync","project_language":null}]}' },
        @{ name = "unknown-template-drift-en"; json = '{"schema_version":1,"results":[{"status":"unknown","reason":"template-tree-drift","project_language":"en"}]}' }
    )
    foreach ($case in $lockContractCases) {
        $helper = New-StatusHelperFixture -Name ("lock-{0}" -f $case.name) -Kind "lock" -Json $case.json
        foreach ($textMode in @($false, $true)) {
            $run = Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $currentProject.root -Text:$textMode -LockHelper $helper -UpgradeHelper $validUpgradeHelper -DiagnoseHelper $validDiagnoseHelper
            Assert-StatusCondition -Condition ([int]$run.exit_code -eq 0) -Message "Malformed lock helper $($case.name) did not fail soft."
            $output = @($run.output) -join "`n"
            Assert-StatusCondition -Condition (-not $output.Contains($maliciousValue) -and -not $output.Contains("ParameterBinding") -and -not $output.Contains("Cannot bind argument")) -Message "Malformed lock helper $($case.name) leaked untrusted content."
            if (-not $textMode) {
                $payload = $output | ConvertFrom-Json
                Assert-StatusCondition -Condition ([string]$payload.project.status -eq "unknown" -and [string]$payload.project.reason -eq "baseline-helper-unavailable" -and $null -eq $payload.project.project_language -and [string]$payload.project.baseline.status -eq "unknown" -and [string]$payload.project.baseline.reason -eq "helper-unavailable" -and [string]$payload.project.memory.status -eq "unknown" -and [int]$payload.project.memory.migration_finding_count -eq 0 -and [int]$payload.project.memory.refresh_finding_count -eq 0 -and [int]$payload.project.memory.diagnostic_warning_count -eq 0 -and @($payload.project.memory.finding_codes).Count -eq 0) -Message "Malformed lock helper $($case.name) returned the wrong fallback."
                # NOTE: #278 fail-closed 时三事实必须重置为 unknown/unknown/not-checked。
                Assert-StatusCondition -Condition ([string]$payload.project.snapshot_consistency -eq "unknown" -and [string]$payload.project.source_provenance -eq "unknown" -and [string]$payload.project.remote_latest -eq "not-checked") -Message "Malformed lock helper $($case.name) did not reset three facts to unknown/unknown/not-checked."
            }
        }
        $evidence.Add([ordered]@{ scenario = "project-lock-contract-$($case.name)"; status = "unknown" })
    }

    $validLockCombinations = @(
        @{ name = "in-sync-en"; json = '{"schema_version":1,"results":[{"status":"in-sync","reason":"hub-lock-in-sync","project_language":"en"}]}'; expected = "current"; language = "en" },
        @{ name = "in-sync-zh"; json = '{"schema_version":1,"results":[{"status":"in-sync","reason":"hub-lock-in-sync","project_language":"zh-CN"}]}'; expected = "current"; language = "zh-CN" },
        @{ name = "commit-drift-en"; json = '{"schema_version":1,"results":[{"status":"drift","reason":"hub-commit-drift","project_language":"en"}]}'; expected = "optional-refresh"; language = "en" },
        @{ name = "tree-drift-zh"; json = '{"schema_version":1,"results":[{"status":"drift","reason":"template-tree-drift","project_language":"zh-CN"}]}'; expected = "optional-refresh"; language = "zh-CN" },
        @{ name = "missing-lock-null"; json = '{"schema_version":1,"results":[{"status":"unknown","reason":"missing-lock","project_language":null}]}'; expected = "unknown"; language = $null },
        @{ name = "language-conflict-null"; json = '{"schema_version":1,"results":[{"status":"unknown","reason":"project-language-conflict","project_language":null}]}'; expected = "unknown"; language = $null }
    )
    foreach ($case in $validLockCombinations) {
        $helper = New-StatusHelperFixture -Name ("lock-valid-{0}" -f $case.name) -Kind "lock" -Json $case.json
        $payload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $currentProject.root -LockHelper $helper -UpgradeHelper $validUpgradeHelper -DiagnoseHelper $validDiagnoseHelper)
        Assert-StatusCondition -Condition ([string]$payload.project.status -eq $case.expected -and $payload.project.project_language -eq $case.language) -Message "Valid lock helper combination $($case.name) changed mapping."
        $evidence.Add([ordered]@{ scenario = "project-lock-combination-$($case.name)"; status = [string]$payload.project.status })
    }

    $catchUpgradeHelper = Join-PathParts $fixtureRoot "helpers" "memory-final-catch.ps1"
    Write-StatusText -Path $catchUpgradeHelper -Text @'
param([string]$ProjectDir, [string]$Mode, [switch]$Json)
function global:Sort-Object { throw "private final aggregation failure" }
Write-Output '{"findings":[{"code":"notes_contains_session_state"},{"code":"missing_scaffold"},{"code":"hot_memory_plan_long"}]}'
'@
    foreach ($textMode in @($false, $true)) {
        $run = Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $currentProject.root -Text:$textMode -LockHelper $validLockHelper -UpgradeHelper $catchUpgradeHelper -DiagnoseHelper $validDiagnoseHelper
        Assert-StatusCondition -Condition ([int]$run.exit_code -eq 0) -Message "Final project aggregation catch did not fail soft."
        $output = @($run.output) -join "`n"
        Assert-StatusCondition -Condition (-not $output.Contains("private final aggregation failure") -and -not $output.Contains("ParameterBinding") -and -not $output.Contains("Cannot bind argument")) -Message "Final project aggregation catch leaked exception content."
        if (-not $textMode) {
            $payload = $output | ConvertFrom-Json
            Assert-StatusCondition -Condition ([string]$payload.project.status -eq "unknown" -and [string]$payload.project.reason -eq "baseline-helper-unavailable" -and $null -eq $payload.project.project_language -and [string]$payload.project.baseline.status -eq "unknown" -and [string]$payload.project.baseline.reason -eq "helper-unavailable" -and [string]$payload.project.memory.status -eq "unknown" -and [int]$payload.project.memory.migration_finding_count -eq 0 -and [int]$payload.project.memory.refresh_finding_count -eq 0 -and [int]$payload.project.memory.diagnostic_warning_count -eq 0 -and @($payload.project.memory.finding_codes).Count -eq 0) -Message "Final project aggregation catch retained partial project state."
        }
    }
    $evidence.Add([ordered]@{ scenario = "project-final-catch-full-reset"; status = "unknown" })

    $memoryContractCases = @(
        @{ name = "top-null"; json = 'null' }, @{ name = "top-scalar"; json = '7' }, @{ name = "top-array"; json = '[]' },
        @{ name = "findings-missing"; json = '{}' }, @{ name = "findings-null"; json = '{"findings":null}' },
        @{ name = "finding-scalar"; json = '{"findings":[7]}' },
        @{ name = "unknown-code"; json = '{"findings":[{"code":"__VALUE__"}]}'.Replace('__VALUE__', ($maliciousValue -replace '\\','\\')) },
        @{ name = "mixed-codes"; json = '{"findings":[{"code":"notes_contains_session_state"},{"code":"__VALUE__"}]}'.Replace('__VALUE__', ($maliciousValue -replace '\\','\\')) }
    )
    foreach ($case in $memoryContractCases) {
        $helper = New-StatusHelperFixture -Name ("memory-{0}" -f $case.name) -Kind "upgrade" -Json $case.json
        $run = Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $currentProject.root -LockHelper $validLockHelper -UpgradeHelper $helper -DiagnoseHelper $validDiagnoseHelper
        $payloadText = @($run.output) -join "`n"
        Assert-StatusCondition -Condition ([int]$run.exit_code -eq 0 -and -not $payloadText.Contains($maliciousValue)) -Message "Memory helper $($case.name) did not remain public-safe and fail-soft."
        $payload = $payloadText | ConvertFrom-Json
        if ($case.name -eq "unknown-code") {
            Assert-StatusCondition -Condition ([string]$payload.project.status -eq "current" -and @($payload.project.memory.finding_codes).Count -eq 0) -Message "Unknown memory finding code changed status or entered output."
        } elseif ($case.name -eq "mixed-codes") {
            Assert-StatusCondition -Condition ([string]$payload.project.status -eq "migration-required" -and (@($payload.project.memory.finding_codes) -join ',') -eq "notes_contains_session_state") -Message "Mixed memory findings did not retain only the known code."
        } else {
            Assert-StatusCondition -Condition ([string]$payload.project.reason -eq "memory-helper-unavailable" -and [int]$payload.project.memory.migration_finding_count -eq 0 -and @($payload.project.memory.finding_codes).Count -eq 0) -Message "Malformed memory helper $($case.name) returned the wrong fallback."
        }
        $evidence.Add([ordered]@{ scenario = "project-memory-contract-$($case.name)"; status = [string]$payload.project.status })
    }

    foreach ($unknownCase in @("malformed-lock", "invalid-hub", "hub-not-git", "locked-dirty", "current-dirty", "remote-mismatch", "branch-mismatch")) {
        $unknownFixture = New-ProjectStatusFixture -Name $unknownCase
        switch ($unknownCase) {
            "malformed-lock" { Write-StatusText -Path (Join-PathParts $unknownFixture.root ".agents" "hub.lock.json") -Text '{"schema_version":' }
            "invalid-hub" { $unknownFixture.lock.hub_dir = (Join-Path $unknownFixture.root "absent-hub") }
            "hub-not-git" {
                $plainHub = Join-Path $unknownFixture.root "plain-hub"
                New-Item -ItemType Directory -Path $plainHub | Out-Null
                $unknownFixture.lock.hub_dir = $plainHub
            }
            "locked-dirty" { $unknownFixture.lock.hub_dirty = $true }
            "current-dirty" { Write-StatusText -Path (Join-Path $unknownFixture.hub "dirty.txt") -Text "dirty" }
            "remote-mismatch" { $unknownFixture.lock.hub_remote = "https://example.invalid/other.git" }
            "branch-mismatch" { $unknownFixture.lock.hub_branch = "other" }
        }
        if ($unknownCase -ne "malformed-lock") {
            Write-StatusText -Path (Join-PathParts $unknownFixture.root ".agents" "hub.lock.json") -Text ($unknownFixture.lock | ConvertTo-Json)
        }
        $unknownPayload = Read-StatusPayload -Run (Invoke-Status -RuntimeRoot $validRuntime -ProjectRoot $unknownFixture.root)
        Assert-StatusCondition -Condition ([string]$unknownPayload.project.status -eq "unknown") -Message "Project baseline case $unknownCase did not report unknown."
        $evidence.Add([ordered]@{ scenario = "project-$unknownCase-unknown"; status = [string]$unknownPayload.project.status })
    }

    $allowedStatuses = @("current", "legacy", "missing", "invalid", "unsupported")
    $allowedReasons = @("recorded", "not-recorded", "legacy-manifest", "manifest-missing", "manifest-invalid", "unsupported-schema", "invalid-value")
    $allowedSeverities = @("info", "warning", "error")
    foreach ($runtimeDir in @(Get-ChildItem -LiteralPath $fixtureRoot -Directory)) {
        $run = Invoke-Status -RuntimeRoot $runtimeDir.FullName
        $payload = Read-StatusPayload -Run $run
        Assert-StatusCondition -Condition ([string]$payload.runtime.manifest_status -in $allowedStatuses) -Message "Unexpected manifest status enum."
        Assert-StatusCondition -Condition ([string]$payload.recommended_next_action -in $allowedActions) -Message "Unexpected recommended action enum."
        Assert-StatusCondition -Condition ([string]$payload.runtime.release_version.reason -in $allowedReasons -and [string]$payload.runtime.source_commit.reason -in $allowedReasons) -Message "Unexpected provenance reason enum."
        Assert-StatusCondition -Condition (@($payload.findings | Where-Object { [string]$_.severity -notin $allowedSeverities }).Count -eq 0) -Message "Unexpected finding severity enum."
    }

    return @($evidence.ToArray())
}
