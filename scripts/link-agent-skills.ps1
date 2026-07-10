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

function Get-FullNormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

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
    return Get-FullNormalizedPath -Path $targetPath
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

$runtimeRoot = Get-FullNormalizedPath -Path $RuntimeDir
$agentSkillsRoot = Get-FullNormalizedPath -Path $AgentSkillsDir
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
$runtimeSkillsRootItem = Get-ExistingItem -Path $runtimeSkillsRoot
if ($null -eq $runtimeSkillsRootItem -or -not $runtimeSkillsRootItem.PSIsContainer) {
    $preflightErrors.Add("Runtime skills root is missing: $runtimeSkillsRoot")
}
elseif (Test-ReparsePoint -Item $runtimeSkillsRootItem) {
    $preflightErrors.Add("Runtime skills root must be a copy directory, not a link: $runtimeSkillsRoot")
}

$requestedSkills = New-Object 'System.Collections.Generic.List[string]'
$seenSkills = @{}
foreach ($skillNameValue in @($Skill)) {
    $skillName = [string]$skillNameValue
    if ([string]::IsNullOrWhiteSpace($skillName) -or $skillName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $skillName -in @('.', '..')) {
        $preflightErrors.Add("Invalid skill name: '$skillName'. Skill names cannot contain path separators.")
        continue
    }
    $skillKey = $skillName.ToLowerInvariant()
    if ($seenSkills.ContainsKey($skillKey)) {
        $preflightErrors.Add("Duplicate skill name: $skillName")
        continue
    }
    $seenSkills[$skillKey] = $true
    $requestedSkills.Add($skillName)
}
if ($requestedSkills.Count -eq 0) {
    $preflightErrors.Add("At least one valid -Skill value is required.")
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
    $managedName = "skills/$skillName"
    $source = Get-FullNormalizedPath -Path (Join-Path (Join-Path $runtimeRoot "skills") $skillName)
    $target = Get-FullNormalizedPath -Path (Join-Path $agentSkillsRoot $skillName)
    $candidateValid = $true

    if ($skillName -notin $manifestSkillNames) {
        $preflightErrors.Add("Skill is not listed in the runtime install manifest: $skillName")
        $candidateValid = $false
    }

    $managedItems = @($installManifest.items | Where-Object { [string]$_.name -eq $managedName })
    if ($managedItems.Count -ne 1) {
        $preflightErrors.Add("Skill must have exactly one managed install manifest item: $managedName")
        $candidateValid = $false
    }
    else {
        $managedItem = $managedItems[0]
        if ([string]$managedItem.destination -ne $managedName) {
            $preflightErrors.Add("Managed skill destination must be $managedName, got '$([string]$managedItem.destination)'.")
            $candidateValid = $false
        }
        if ([string]$managedItem.mode -ne "copy" -or -not [bool]$managedItem.managed) {
            $preflightErrors.Add("Managed skill item must record mode=copy and managed=true: $managedName")
            $candidateValid = $false
        }
    }

    $sourceItem = Get-ExistingItem -Path $source
    if ($null -eq $sourceItem -or -not $sourceItem.PSIsContainer) {
        $preflightErrors.Add("Managed runtime skill directory is missing: $source")
        $candidateValid = $false
    }
    elseif (Test-ReparsePoint -Item $sourceItem) {
        $preflightErrors.Add("Managed runtime skill source must be a copy directory, not a link: $source")
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
            if ([string]::IsNullOrWhiteSpace($actualTarget) -or -not $actualTarget.Equals($source, [System.StringComparison]::OrdinalIgnoreCase)) {
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
                skill = $skillName
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
        if (-not $actualTarget.Equals([string]$candidate.source, [System.StringComparison]::OrdinalIgnoreCase)) {
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

    $currentKeys = @{}
    foreach ($record in @($currentResults.ToArray())) {
        $currentKeys[((([string]$record.target).ToLowerInvariant()) + "`0" + (([string]$record.skill).ToLowerInvariant()))] = $true
    }

    $allRecords = New-Object 'System.Collections.Generic.List[object]'
    if ($null -ne $existingBridgeManifest) {
        foreach ($record in @($existingBridgeManifest.bridges)) {
            $key = ((([string]$record.target).ToLowerInvariant()) + "`0" + (([string]$record.skill).ToLowerInvariant()))
            if (-not $currentKeys.ContainsKey($key)) {
                $allRecords.Add($record)
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
        bridges = @($allRecords.ToArray() | Sort-Object { ([string]$_.target).ToLowerInvariant() }, { ([string]$_.skill).ToLowerInvariant() })
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
