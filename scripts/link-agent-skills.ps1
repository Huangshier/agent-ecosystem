[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeDir,

    [Parameter(Mandatory = $true)]
    [string]$AgentSkillsDir,

    [Parameter(Mandatory = $true)]
    [string[]]$Skill,

    [switch]$Json
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir "lib/path-guard.ps1")

function Test-ReparsePoint {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item)

    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-ExistingItem {
    param([Parameter(Mandatory = $true)][string]$Path)

    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Get-LinkTargetPath {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory = $true)][string]$LinkPath
    )

    $targetProperty = $Item.PSObject.Properties["Target"]
    if ($null -eq $targetProperty) {
        return ""
    }
    $targetValue = @($targetProperty.Value | Select-Object -First 1)
    if ($targetValue.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$targetValue[0])) {
        return ""
    }
    $targetPath = [string]$targetValue[0]
    if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
        $targetPath = Join-Path (Split-Path -Parent $LinkPath) $targetPath
    }
    return Get-NormalizedFullPath -Path $targetPath
}

function Get-LinkMode {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item)

    $linkTypeProperty = $Item.PSObject.Properties["LinkType"]
    if ($null -ne $linkTypeProperty -and -not [string]::IsNullOrWhiteSpace([string]$linkTypeProperty.Value)) {
        return ([string]$linkTypeProperty.Value).ToLowerInvariant()
    }
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return "junction"
    }
    return "symboliclink"
}

function Remove-BridgeLink {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-ExistingItem -Path $Path
    if ($null -eq $item) {
        return
    }
    if ($item.PSIsContainer) {
        [System.IO.Directory]::Delete($item.FullName)
    }
    else {
        [System.IO.File]::Delete($item.FullName)
    }
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

$runtimeRoot = Get-NormalizedFullPath -Path $RuntimeDir
$runtimePhysicalRoot = Resolve-PhysicalPathForWrite -Path $runtimeRoot
$agentSkillsRequestedRoot = Get-NormalizedFullPath -Path $AgentSkillsDir
$agentSkillsRoot = Resolve-PhysicalPathForWrite -Path $agentSkillsRequestedRoot
$installManifestPath = Join-Path $runtimeRoot "install-manifest.json"
$bridgeManifestPath = Join-Path $runtimeRoot "agent-skill-bridge-manifest.json"
$runtimeSkillsRoot = Join-Path $runtimeRoot "skills"
$preflightErrors = New-Object 'System.Collections.Generic.List[string]'
$candidates = New-Object 'System.Collections.Generic.List[object]'

$runtimeItem = Get-ExistingItem -Path $runtimeRoot
if ($null -eq $runtimeItem -or -not $runtimeItem.PSIsContainer) {
    throw "RuntimeDir must be an existing directory: $runtimeRoot"
}
if (Test-ReparsePoint -Item $runtimeItem) {
    throw "RuntimeDir must be an installed copy directory, not a link: $runtimeRoot"
}
$installManifestItem = Get-ExistingItem -Path $installManifestPath
if ($null -eq $installManifestItem -or $installManifestItem.PSIsContainer) {
    throw "RuntimeDir does not contain install-manifest.json: $runtimeRoot"
}
if (Test-ReparsePoint -Item $installManifestItem) {
    throw "Runtime install-manifest.json must be a real file, not a link: $installManifestPath"
}

try {
    $installManifestText = [System.IO.File]::ReadAllText($installManifestPath)
    $installManifest = $installManifestText | ConvertFrom-Json
}
catch {
    throw "Runtime install-manifest.json is not valid JSON: $($_.Exception.Message)"
}

if ([int]$installManifest.schema_version -ne 2) {
    $preflightErrors.Add("Runtime install-manifest.json must use schema_version 2.")
}
if ([string]$installManifest.source_identity -ne "agent-ecosystem") {
    $preflightErrors.Add("Runtime install-manifest.json must identify the public agent-ecosystem runtime.")
}
if ([string]$installManifest.install_strategy -ne "copy") {
    $preflightErrors.Add("Runtime install_strategy must be copy; source-linked and dev-link runtimes cannot be bridged.")
}
if ([string]$installManifest.target_dir -ne ".") {
    $preflightErrors.Add("Runtime install-manifest.json target_dir must be runtime-relative '.'.")
}
$retiredC33AuthoritySkills = @()
if ([string]$installManifest.profile -ceq "c3-3-candidate") {
    $workspace = $installManifest.workspace
    $declaredAuthority = @($workspace.c3_3_authority | ForEach-Object { [string]$_ })
    $retiredC33AuthoritySkills = @($workspace.retired_from_c3_3_authority | ForEach-Object { [string]$_ })
    $expectedAuthority = @("project-bootstrap", "project-workspace")
    $expectedRetired = @("project-context-gate", "memory-governance", "workflow-spec-lite")
    $authorityContractValid =
        (@($declaredAuthority) -join "`n") -ceq (@($expectedAuthority) -join "`n") -and
        (@($retiredC33AuthoritySkills) -join "`n") -ceq (@($expectedRetired) -join "`n") -and
        @($workspace.legacy_only_compatibility_payload).Count -eq 0 -and
        $workspace.compatibility_aliases -is [bool] -and -not [bool]$workspace.compatibility_aliases -and
        $workspace.automatic_forwarding -is [bool] -and -not [bool]$workspace.automatic_forwarding -and
        $workspace.dual_write -is [bool] -and -not [bool]$workspace.dual_write
    if (-not $authorityContractValid) {
        $preflightErrors.Add("The C3.3 candidate Skill authority contract is invalid.")
    }
}
$runtimeSkillsRootItem = Get-ExistingItem -Path $runtimeSkillsRoot
if ($null -eq $runtimeSkillsRootItem -or -not $runtimeSkillsRootItem.PSIsContainer) {
    $preflightErrors.Add("Runtime skills root is missing: $runtimeSkillsRoot")
}
elseif (Test-ReparsePoint -Item $runtimeSkillsRootItem) {
    $preflightErrors.Add("Runtime skills root must be a copy directory, not a link: $runtimeSkillsRoot")
}

$requestedSkills = New-Object 'System.Collections.Generic.List[string]'
foreach ($skillNameValue in @($Skill)) {
    $skillName = [string]$skillNameValue
    if ([string]::IsNullOrWhiteSpace($skillName) -or $skillName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $skillName -in @('.', '..')) {
        $preflightErrors.Add("Invalid skill name: '$skillName'. Skill names cannot contain path separators.")
        continue
    }
    $duplicateRequest = @($requestedSkills.ToArray() | Where-Object {
            [string]::Equals([string]$_, $skillName, [System.StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
    if ($duplicateRequest) {
        $preflightErrors.Add("Duplicate skill name: $skillName")
        continue
    }
    $requestedSkills.Add($skillName)
}
if ($requestedSkills.Count -eq 0) {
    $preflightErrors.Add("At least one valid -Skill value is required.")
}

if (Test-IsFileSystemRoot -Path $agentSkillsRoot) {
    $preflightErrors.Add("AgentSkillsDir cannot be a filesystem root: $agentSkillsRoot")
}
if (Test-PathIsEqualOrChild -Path $agentSkillsRoot -Root $runtimePhysicalRoot) {
    $preflightErrors.Add("AgentSkillsDir must be outside RuntimeDir: $agentSkillsRoot")
}

$agentSkillsRootItem = Get-ExistingItem -Path $agentSkillsRoot
if ($null -ne $agentSkillsRootItem) {
    if (-not $agentSkillsRootItem.PSIsContainer) {
        $preflightErrors.Add("AgentSkillsDir exists but is not a directory: $agentSkillsRoot")
    }
    elseif (Test-ReparsePoint -Item $agentSkillsRootItem) {
        $preflightErrors.Add("AgentSkillsDir must be a real directory, not a link: $agentSkillsRoot")
    }
}

$manifestSkillNames = @($installManifest.skills | ForEach-Object { [string]$_ })
foreach ($skillName in @($requestedSkills.ToArray())) {
    if ([string]$installManifest.profile -ceq "c3-3-candidate" -and $skillName -in $retiredC33AuthoritySkills) {
        $preflightErrors.Add("Skill is retired from C3.3 Runtime authority and cannot be bridged by c3-3-candidate: $skillName")
        continue
    }
    $canonicalMatches = @($manifestSkillNames | Where-Object {
            [string]::Equals([string]$_, $skillName, [System.StringComparison]::Ordinal)
        })
    if ($canonicalMatches.Count -ne 1) {
        $preflightErrors.Add("Skill must exactly match one canonical runtime manifest skill: $skillName")
        continue
    }

    $canonicalSkill = [string]$canonicalMatches[0]
    $managedName = "skills/$canonicalSkill"
    $managedItems = @($installManifest.items | Where-Object {
            [string]::Equals([string]$_.name, $managedName, [System.StringComparison]::Ordinal)
        })
    if ($managedItems.Count -ne 1) {
        $preflightErrors.Add("Skill must have exactly one managed install manifest item: $managedName")
        continue
    }

    $managedItem = $managedItems[0]
    $canonicalDestination = [string]$managedItem.destination
    if (-not [string]::Equals($canonicalDestination, $managedName, [System.StringComparison]::Ordinal)) {
        $preflightErrors.Add("Managed skill destination must exactly match $managedName, got '$canonicalDestination'.")
        continue
    }
    if (-not [string]::Equals([string]$managedItem.mode, "copy", [System.StringComparison]::Ordinal) -or -not [bool]$managedItem.managed) {
        $preflightErrors.Add("Managed skill item must record mode=copy and managed=true: $managedName")
        continue
    }

    $source = Resolve-PhysicalPathForWrite -Path (Join-PathParts $runtimeRoot $canonicalDestination)
    $target = Get-NormalizedFullPath -Path (Join-Path $agentSkillsRoot $canonicalSkill)
    $candidateValid = $true

    $sourceItem = Get-ExistingItem -Path $source
    if ($null -eq $sourceItem -or -not $sourceItem.PSIsContainer) {
        $preflightErrors.Add("Managed runtime skill directory is missing: $source")
        $candidateValid = $false
    }
    elseif (Test-ReparsePoint -Item $sourceItem) {
        $preflightErrors.Add("Managed runtime skill source must be a copy directory, not a link: $source")
        $candidateValid = $false
    }

    if (Test-PathIsEqualOrChild -Path $agentSkillsRoot -Root $source) {
        $preflightErrors.Add("AgentSkillsDir must be outside selected skill source: $agentSkillsRoot")
        $candidateValid = $false
    }
    if (Test-PathIsEqualOrChild -Path $target -Root $source) {
        $preflightErrors.Add("Final skill target must not equal or be inside selected skill source: $target")
        $candidateValid = $false
    }

    $targetState = "create"
    $targetItem = Get-ExistingItem -Path $target
    if ($null -ne $targetItem) {
        if (-not (Test-ReparsePoint -Item $targetItem)) {
            $preflightErrors.Add("Target exists and is not a link: $target")
            $targetState = "conflict"
        }
        else {
            $actualTarget = Get-LinkTargetPath -Item $targetItem -LinkPath $target
            if ([string]::IsNullOrWhiteSpace($actualTarget) -or -not (Test-PlatformPathEqual -Left $actualTarget -Right $source)) {
                $preflightErrors.Add("Target link points somewhere unexpected: $target -> $actualTarget")
                $targetState = "conflict"
            }
            else {
                $targetState = "unchanged"
            }
        }
    }

    if ($candidateValid) {
        $candidates.Add([ordered]@{
                skill = $canonicalSkill
                source = $source
                target = $target
                preflight = $targetState
            })
    }
}

$existingBridgeManifest = $null
$existingBridgeManifestText = $null
if ([System.IO.File]::Exists($bridgeManifestPath)) {
    try {
        $bridgeManifestItem = Get-ExistingItem -Path $bridgeManifestPath
        if ($null -eq $bridgeManifestItem -or $bridgeManifestItem.PSIsContainer -or (Test-ReparsePoint -Item $bridgeManifestItem)) {
            throw "Existing bridge manifest must be a real file."
        }
        $existingBridgeManifestText = [System.IO.File]::ReadAllText($bridgeManifestPath)
        $existingBridgeManifest = $existingBridgeManifestText | ConvertFrom-Json
        if ([int]$existingBridgeManifest.schema_version -ne 1 -or [string]$existingBridgeManifest.metadata_kind -ne "agent-specific-skill-link-bridge") {
            $preflightErrors.Add("Existing bridge manifest has an unsupported contract: $bridgeManifestPath")
        }
    }
    catch {
        $preflightErrors.Add("Existing bridge manifest is not valid JSON: $bridgeManifestPath")
    }
}

if ($preflightErrors.Count -gt 0) {
    throw ("Bridge preflight failed; no links were created:`n- " + ($preflightErrors.ToArray() -join "`n- "))
}

$createdLinks = New-Object 'System.Collections.Generic.List[string]'
$currentResults = New-Object 'System.Collections.Generic.List[object]'
$targetRootCreated = $false
$manifestTempPath = Join-Path $runtimeRoot (".agent-skill-bridge-manifest.{0}.tmp" -f ([Guid]::NewGuid().ToString("N")))

try {
    if ($null -eq $agentSkillsRootItem) {
        New-Item -ItemType Directory -Force -Path $agentSkillsRoot | Out-Null
        $targetRootCreated = $true
    }

    foreach ($candidate in @($candidates.ToArray())) {
        $result = "unchanged"
        if ([string]$candidate.preflight -eq "create") {
            $itemType = "SymbolicLink"
            if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
                $itemType = "Junction"
            }
            New-Item -ItemType $itemType -Path ([string]$candidate.target) -Target ([string]$candidate.source) -ErrorAction Stop | Out-Null
            $createdLinks.Add([string]$candidate.target)
            $result = "created"
        }

        $linkedItem = Get-ExistingItem -Path ([string]$candidate.target)
        if ($null -eq $linkedItem -or -not (Test-ReparsePoint -Item $linkedItem)) {
            throw "Bridge link was not created as a link: $([string]$candidate.target)"
        }
        $actualTarget = Get-LinkTargetPath -Item $linkedItem -LinkPath ([string]$candidate.target)
        if (-not (Test-PlatformPathEqual -Left $actualTarget -Right ([string]$candidate.source))) {
            throw "Bridge link verification failed: $([string]$candidate.target) -> $actualTarget"
        }

        $currentResults.Add([ordered]@{
                skill = [string]$candidate.skill
                source = [string]$candidate.source
                target = [string]$candidate.target
                result = $result
                link_mode = Get-LinkMode -Item $linkedItem
            })
    }

    $allRecords = New-Object 'System.Collections.Generic.List[object]'
    if ($null -ne $existingBridgeManifest) {
        foreach ($existingRecord in @($existingBridgeManifest.bridges)) {
            $replacedByCurrentResult = $false
            foreach ($currentRecord in @($currentResults.ToArray())) {
                if ([string]::Equals([string]$existingRecord.skill, [string]$currentRecord.skill, [System.StringComparison]::OrdinalIgnoreCase) -and
                    (Test-PlatformPathEqual -Left ([string]$existingRecord.target) -Right ([string]$currentRecord.target))) {
                    $replacedByCurrentResult = $true
                    break
                }
            }
            if (-not $replacedByCurrentResult) {
                $allRecords.Add($existingRecord)
            }
        }
    }
    foreach ($record in @($currentResults.ToArray())) {
        $allRecords.Add($record)
    }

    $bridgeManifest = [ordered]@{
        schema_version = 1
        metadata_kind = "agent-specific-skill-link-bridge"
        local_runtime_metadata = $true
        commit_policy = "do-not-commit"
        runtime = $runtimeRoot
        updated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        bridges = @($allRecords.ToArray() | Sort-Object { [string]$_.target }, { [string]$_.skill })
    }
    $bridgeManifestJson = $bridgeManifest | ConvertTo-Json -Depth 8
    Write-Utf8NoBomFile -Path $manifestTempPath -Text ($bridgeManifestJson + [System.Environment]::NewLine)
    Move-Item -LiteralPath $manifestTempPath -Destination $bridgeManifestPath -Force
}
catch {
    $originalError = $_
    foreach ($createdPath in @($createdLinks.ToArray())) {
        try {
            Remove-BridgeLink -Path $createdPath
        }
        catch {
        }
    }
    if ($targetRootCreated) {
        try {
            if ([System.IO.Directory]::Exists($agentSkillsRoot) -and @(Get-ChildItem -LiteralPath $agentSkillsRoot -Force).Count -eq 0) {
                [System.IO.Directory]::Delete($agentSkillsRoot)
            }
        }
        catch {
        }
    }
    try {
        if ($null -ne $existingBridgeManifestText) {
            Write-Utf8NoBomFile -Path $bridgeManifestPath -Text $existingBridgeManifestText
        }
        elseif ([System.IO.File]::Exists($bridgeManifestPath)) {
            [System.IO.File]::Delete($bridgeManifestPath)
        }
    }
    catch {
    }
    throw $originalError
}
finally {
    if ([System.IO.File]::Exists($manifestTempPath)) {
        [System.IO.File]::Delete($manifestTempPath)
    }
}

$output = [ordered]@{
    schema_version = 1
    status = "success"
    runtime = $runtimeRoot
    agent_skills_dir = $agentSkillsRoot
    bridge_manifest = $bridgeManifestPath
    results = @($currentResults.ToArray())
}

if ($Json.IsPresent) {
    $output | ConvertTo-Json -Depth 8
}
else {
    foreach ($record in @($currentResults.ToArray())) {
        Write-Output ("[{0}] {1}: {2} -> {3}" -f $record.result, $record.skill, $record.source, $record.target)
    }
    Write-Output ("Bridge manifest: {0}" -f $bridgeManifestPath)
    Write-Output "Bridge manifest is local runtime metadata; do not commit it."
}
