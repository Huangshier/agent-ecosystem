[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TargetDir = (Join-Path $HOME ".agents"),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir "lib/path-guard.ps1")

$targetRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetDir)
$manifestPath = Join-PathParts $targetRoot "install-manifest.json"
$bridgeManifestPath = Join-PathParts $targetRoot "agent-skill-bridge-manifest.json"

function Get-UninstallManifestProperty {
    param(
        [AllowNull()][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Manifest) {
        return $null
    }
    $property = $Manifest.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Test-UninstallManifestObject {
    param([AllowNull()][object]$Value)

    return $null -ne $Value -and $Value -isnot [System.Array] -and
        $Value -isnot [string] -and -not $Value.GetType().IsPrimitive -and
        $Value -isnot [System.ValueType]
}

function ConvertTo-NormalizedManifestPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return ($Path -replace "\\", "/").TrimStart('/')
}

function Test-CanonicalUninstallPath {
    param([AllowNull()][object]$Path)

    if ($Path -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Path)) {
        return $false
    }
    $normalized = ConvertTo-NormalizedManifestPath -Path ([string]$Path)
    return -not [System.IO.Path]::IsPathRooted([string]$Path) -and
        $normalized -cnotmatch '(^|/)\.{1,2}(/|$)' -and
        $normalized -cnotmatch '//|^/|/$' -and
        $normalized -cnotmatch ':'
}

function Test-ProjectLocalUninstallPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = ConvertTo-NormalizedManifestPath -Path $Path
    return $normalized -in @("AGENTS.md", "CLAUDE.md", ".agents", "docs/specs") -or
        $normalized.StartsWith(".agents/", [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalized.StartsWith("docs/specs/", [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-BridgeLink {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
        throw "Refusing to remove a non-link bridge target: $Path"
    }
    if ($PSCmdlet.ShouldProcess($Path, "Remove manifest-owned bridge link")) {
        if ($item.PSIsContainer) {
            [System.IO.Directory]::Delete($item.FullName)
        }
        else {
            [System.IO.File]::Delete($item.FullName)
        }
    }
}

function Get-BridgeCleanupPlan {
    $empty = [ordered]@{ present = $false; records = @(); errors = @() }
    if (-not (Test-Path -LiteralPath $bridgeManifestPath -PathType Leaf)) {
        return $empty
    }

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $bridgeItem = Get-Item -LiteralPath $bridgeManifestPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $bridgeItem -or $bridgeItem.PSIsContainer -or (($bridgeItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        $errors.Add("bridge manifest is not a regular file")
        return [ordered]@{ present = $true; records = @(); errors = @($errors.ToArray()) }
    }

    $bridgeManifest = $null
    try {
        $bridgeManifest = Get-Content -LiteralPath $bridgeManifestPath -Raw | ConvertFrom-Json
    }
    catch {
        $errors.Add("bridge manifest is not valid JSON")
        return [ordered]@{ present = $true; records = @(); errors = @($errors.ToArray()) }
    }

    $runtimeValue = Get-UninstallManifestProperty -Manifest $bridgeManifest -Name "runtime"
    $recordsValue = Get-UninstallManifestProperty -Manifest $bridgeManifest -Name "bridges"
    if (-not (Test-UninstallManifestObject -Value $bridgeManifest) -or
        [int](Get-UninstallManifestProperty -Manifest $bridgeManifest -Name "schema_version") -ne 1 -or
        [string](Get-UninstallManifestProperty -Manifest $bridgeManifest -Name "metadata_kind") -cne "agent-specific-skill-link-bridge" -or
        (Get-UninstallManifestProperty -Manifest $bridgeManifest -Name "local_runtime_metadata") -isnot [bool] -or
        -not [bool](Get-UninstallManifestProperty -Manifest $bridgeManifest -Name "local_runtime_metadata") -or
        [string](Get-UninstallManifestProperty -Manifest $bridgeManifest -Name "commit_policy") -cne "do-not-commit" -or
        $runtimeValue -isnot [string] -or -not (Test-PlatformPathEqual -Left ([string]$runtimeValue) -Right $targetRoot) -or
        $null -eq $recordsValue -or @($recordsValue).Count -eq 0) {
        $errors.Add("bridge manifest ownership contract is missing or ambiguous")
        return [ordered]@{ present = $true; records = @(); errors = @($errors.ToArray()) }
    }

    $records = New-Object 'System.Collections.Generic.List[object]'
    $seenTargets = New-Object 'System.Collections.Generic.List[string]'
    foreach ($record in @($recordsValue)) {
        if (-not (Test-UninstallManifestObject -Value $record)) {
            $errors.Add("bridge record is not an object")
            continue
        }
        $skill = Get-UninstallManifestProperty -Manifest $record -Name "skill"
        $source = Get-UninstallManifestProperty -Manifest $record -Name "source"
        $target = Get-UninstallManifestProperty -Manifest $record -Name "target"
        if ($skill -isnot [string] -or [string]$skill -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            $source -isnot [string] -or $target -isnot [string] -or
            -not [System.IO.Path]::IsPathRooted([string]$source) -or -not [System.IO.Path]::IsPathRooted([string]$target)) {
            $errors.Add("bridge record has invalid skill/source/target fields")
            continue
        }

        $expectedSource = Get-NormalizedFullPath -Path (Join-PathParts $targetRoot "skills" ([string]$skill))
        $targetPath = Get-NormalizedFullPath -Path ([string]$target)
        if (-not (Test-PlatformPathEqual -Left ([string]$source) -Right $expectedSource) -or
            (Test-PathIsEqualOrChild -Path $targetPath -Root $targetRoot) -or
            (Test-PathIsEqualOrChild -Path $targetPath -Root $expectedSource) -or
            -not [string]::Equals([System.IO.Path]::GetFileName($targetPath), [string]$skill, [System.StringComparison]::Ordinal)) {
            $errors.Add("bridge record does not point from a managed runtime Skill to an external target: $skill")
            continue
        }
        if (@($seenTargets.ToArray() | Where-Object { Test-PlatformPathEqual -Left $_ -Right $targetPath }).Count -gt 0) {
            $errors.Add("bridge target is duplicated: $targetPath")
            continue
        }
        $seenTargets.Add($targetPath)

        $targetItem = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $targetItem -or (($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)) {
            $errors.Add("bridge target is missing or not a link: $targetPath")
            continue
        }
        try {
            $actualTarget = Get-ReparsePointTargetPath -Item $targetItem -LinkPath $targetPath
            if (-not (Test-PlatformPathEqual -Left $actualTarget -Right $expectedSource)) {
                $errors.Add("bridge target points somewhere unexpected: $targetPath")
                continue
            }
        }
        catch {
            $errors.Add("bridge target cannot be resolved safely: $targetPath")
            continue
        }
        $records.Add([ordered]@{ skill = [string]$skill; target = $targetPath })
    }

    return [ordered]@{ present = $true; records = @($records.ToArray()); errors = @($errors.ToArray()) }
}

function Exit-UninstallBlocked {
    param(
        [Parameter(Mandatory = $true)][string]$Reason,
        [string[]]$OwnershipErrors = @(),
        [string[]]$NestedUnknown = @(),
        [string[]]$LocallyModified = @()
    )

    $blockedResult = [ordered]@{
        schema_version = 1
        target_dir = $targetRoot
        manifest_path = $manifestPath
        status = "blocked"
        reason = $Reason
        removed = @()
        missing = @()
        preserved_unknown = $true
        protection_scope = "fail-closed-ownership"
        ownership_errors = @($OwnershipErrors)
        nested_unknown = @($NestedUnknown)
        locally_modified = @($LocallyModified)
    }
    if ($Json.IsPresent) {
        $blockedResult | ConvertTo-Json -Depth 8
    }
    else {
        Write-Output "Uninstall blocked. No files were removed."
        foreach ($errorValue in @($OwnershipErrors)) {
            Write-Output ("- {0}" -f $errorValue)
        }
    }
    exit 2
}

function ConvertTo-RelativeRuntimePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "."
    }
    return $fullPath.Substring($fullRoot.Length).TrimStart([char[]]"\/") -replace "\\", "/"
}

function ConvertTo-RelativeChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the managed item root: $Path"
    }
    return $fullPath.Substring($prefix.Length).TrimStart([char[]]"\/") -replace "\\", "/"
}

function Get-DirectoryFileMap {
    param([Parameter(Mandatory = $true)][string]$Root)

    $result = @{}
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $result
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)) {
        $relativePath = ConvertTo-RelativeChildPath -Path $file.FullName -Root $Root
        $result[$relativePath] = [ordered]@{
            path = $file.FullName
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return $result
}

function Resolve-ManifestDestination {
    param([Parameter(Mandatory = $true)][string]$Destination)

    $resolved = $Destination
    if (-not [System.IO.Path]::IsPathRooted($resolved)) {
        $resolved = Join-PathParts $targetRoot $resolved
    }
    Assert-PathInsideRoot -Path $resolved -Root $targetRoot
    return [System.IO.Path]::GetFullPath($resolved).TrimEnd('\', '/')
}

function Remove-DirectoryIfEmpty {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $current = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    while ($current.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not [System.IO.Directory]::Exists($current)) {
            break
        }
        if (@([System.IO.Directory]::EnumerateFileSystemEntries($current)).Count -gt 0) {
            break
        }
        if ($PSCmdlet.ShouldProcess($current, "Remove empty runtime directory")) {
            Remove-Item -LiteralPath $current -Force
        }
        if ($current.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $current = [System.IO.Path]::GetDirectoryName($current).TrimEnd('\', '/')
    }
}

function Remove-InstallPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return "missing"
    }

    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($PSCmdlet.ShouldProcess($Path, "Remove installed link")) {
            if ($item.PSIsContainer) {
                [System.IO.Directory]::Delete($item.FullName)
            }
            else {
                [System.IO.File]::Delete($item.FullName)
            }
        }
        return "removed"
    }

    if ($item.PSIsContainer) {
        if ($PSCmdlet.ShouldProcess($Path, "Remove installed directory")) {
            Remove-Item -LiteralPath $Path -Recurse -Force
        }
        return "removed"
    }

    if ($PSCmdlet.ShouldProcess($Path, "Remove installed file")) {
        Remove-Item -LiteralPath $Path -Force
    }
    return "removed"
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
    $manualPaths = @(
        "install-manifest.json",
        "knowledge-hub",
        "skills/project-bootstrap",
        "skills/project-workspace",
        "skills/project-context-gate",
        "skills/workflow-spec-lite",
        "skills/memory-governance",
        "templates/project",
        "scripts"
    )
    $result = [ordered]@{
        schema_version = 1
        target_dir = $targetRoot
        manifest_path = $manifestPath
        status = "missing_manifest"
        removed = @()
        missing = @()
        preserved_unknown = $true
        protection_scope = "no_manifest_no_removal"
        nested_unknown = @()
        locally_modified = @()
        manual_cleanup_candidates = @($manualPaths)
    }
    if ($Json.IsPresent) {
        $result | ConvertTo-Json -Depth 8
    }
    else {
        Write-Warning "No install manifest found at: $manifestPath"
        Write-Output "No files were removed. Inspect the runtime manually before deleting anything."
        Write-Output "Typical public install paths are: $($manualPaths -join ', ')"
    }
    exit 0
}

$manifest = $null
try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}
catch {
    Exit-UninstallBlocked -Reason "manifest-invalid-json" -OwnershipErrors @("install manifest is not valid JSON")
}
$manifestItems = @($manifest.items)
$manifestSchemaVersion = [int]$manifest.schema_version
$nestedUnknown = New-Object 'System.Collections.Generic.List[string]'
$locallyModified = New-Object 'System.Collections.Generic.List[string]'
$bridgeCleanupPlan = [ordered]@{ present = $false; records = @(); errors = @() }

if ($manifestSchemaVersion -notin @(1, 2)) {
    Exit-UninstallBlocked -Reason "manifest-unsupported-schema" -OwnershipErrors @("unsupported install manifest schema_version: $manifestSchemaVersion")
}

if ($manifestSchemaVersion -eq 2) {
    $ownershipErrors = New-Object 'System.Collections.Generic.List[string]'
    if (-not (Test-UninstallManifestObject -Value $manifest) -or
        [string](Get-UninstallManifestProperty -Manifest $manifest -Name "source_identity") -cne "agent-ecosystem" -or
        [string](Get-UninstallManifestProperty -Manifest $manifest -Name "target_dir") -cne "." -or
        (Get-UninstallManifestProperty -Manifest $manifest -Name "items") -isnot [System.Array]) {
        $ownershipErrors.Add("schema-2 install manifest ownership header is invalid")
    }
    foreach ($item in @($manifestItems)) {
        if (-not (Test-UninstallManifestObject -Value $item)) {
            $ownershipErrors.Add("schema-2 install manifest contains a non-object item")
            continue
        }
        $destinationValue = Get-UninstallManifestProperty -Manifest $item -Name "destination"
        $modeValue = Get-UninstallManifestProperty -Manifest $item -Name "mode"
        $managedValue = Get-UninstallManifestProperty -Manifest $item -Name "managed"
        $nameValue = Get-UninstallManifestProperty -Manifest $item -Name "name"
        if ($nameValue -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$nameValue) -or
            -not (Test-CanonicalUninstallPath -Path $destinationValue) -or
            $modeValue -isnot [string] -or [string]$modeValue -notin @("copy", "junction", "symboliclink") -or
            $managedValue -isnot [bool] -or -not [bool]$managedValue) {
            $ownershipErrors.Add("schema-2 install manifest contains an ambiguous managed item")
            continue
        }
        $destinationRelative = ConvertTo-NormalizedManifestPath -Path ([string]$destinationValue)
        if (Test-ProjectLocalUninstallPath -Path $destinationRelative) {
            $ownershipErrors.Add("manifest item is project-local and cannot be runtime-owned: $destinationRelative")
        }
    }
    if ($ownershipErrors.Count -gt 0) {
        Exit-UninstallBlocked -Reason "manifest-ownership-ambiguous" -OwnershipErrors @($ownershipErrors.ToArray())
    }

    $bridgeCleanupPlan = Get-BridgeCleanupPlan
    if (@($bridgeCleanupPlan.errors).Count -gt 0) {
        Exit-UninstallBlocked -Reason "bridge-ownership-ambiguous" -OwnershipErrors @($bridgeCleanupPlan.errors)
    }
}

if ($manifestSchemaVersion -eq 2) {
    foreach ($item in $manifestItems) {
        if ([string]$item.mode -ne "copy") {
            continue
        }
        $destinationRelative = ([string]$item.destination -replace "\\", "/").TrimStart('/')
        $destination = Resolve-ManifestDestination -Destination ([string]$item.destination)
        if (-not (Test-Path -LiteralPath $destination)) {
            continue
        }
        $destinationItem = Get-Item -LiteralPath $destination -Force
        if (($destinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or -not $destinationItem.PSIsContainer) {
            $locallyModified.Add($destinationRelative)
            continue
        }

        $managedFiles = @{}
        foreach ($file in @($item.files)) {
            $relativePath = ([string]$file.path -replace "\\", "/").TrimStart('/')
            if (-not [string]::IsNullOrWhiteSpace($relativePath)) {
                $managedFiles[$relativePath] = $file
            }
        }
        $targetFiles = Get-DirectoryFileMap -Root $destination
        foreach ($relativePath in @($targetFiles.Keys | Sort-Object)) {
            $runtimePath = ($destinationRelative.TrimEnd('/') + "/" + $relativePath).TrimStart('/')
            if (-not $managedFiles.ContainsKey($relativePath)) {
                $nestedUnknown.Add($runtimePath)
                continue
            }
            $installedHash = [string]$managedFiles[$relativePath].installed_sha256
            if ([string]::IsNullOrWhiteSpace($installedHash) -or [string]$targetFiles[$relativePath].sha256 -ne $installedHash) {
                $locallyModified.Add($runtimePath)
            }
        }
    }
}

$nestedUnknownValues = @($nestedUnknown.ToArray() | Sort-Object -Unique)
$locallyModifiedValues = @($locallyModified.ToArray() | Sort-Object -Unique)
if ($nestedUnknownValues.Count -gt 0 -or $locallyModifiedValues.Count -gt 0) {
    Exit-UninstallBlocked -Reason "schema2_copy_item_safety_check" -NestedUnknown $nestedUnknownValues -LocallyModified $locallyModifiedValues
}

$destinations = New-Object 'System.Collections.Generic.List[string]'
foreach ($item in $manifestItems) {
    $destination = [string]$item.destination
    if ([string]::IsNullOrWhiteSpace($destination)) {
        continue
    }

    $fullDestination = Resolve-ManifestDestination -Destination $destination
    if ($fullDestination.Equals([System.IO.Path]::GetFullPath($targetRoot).TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove manifest item that points at the runtime root: $fullDestination"
    }
    $destinations.Add($fullDestination)
}

$removed = New-Object 'System.Collections.Generic.List[string]'
$missing = New-Object 'System.Collections.Generic.List[string]'
$orderedDestinations = @($destinations.ToArray() | Sort-Object -Unique | Sort-Object { $_.Length } -Descending)
foreach ($destination in $orderedDestinations) {
    $status = Remove-InstallPath -Path $destination
    $relative = ConvertTo-RelativeRuntimePath -Path $destination -Root $targetRoot
    if ($status -eq "removed") {
        $removed.Add($relative)
    }
    else {
        $missing.Add($relative)
    }

    $parent = Split-Path -Parent $destination
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Remove-DirectoryIfEmpty -Path $parent -Root $targetRoot
    }
}

if (Test-Path -LiteralPath $manifestPath) {
    if ($PSCmdlet.ShouldProcess($manifestPath, "Remove install manifest")) {
        Remove-Item -LiteralPath $manifestPath -Force
    }
    $removed.Add("install-manifest.json")
}

$installReportPath = Join-PathParts $targetRoot "install-report.json"
if (Test-Path -LiteralPath $installReportPath) {
    if ($PSCmdlet.ShouldProcess($installReportPath, "Remove install report")) {
        Remove-Item -LiteralPath $installReportPath -Force
    }
    $removed.Add("install-report.json")
}

$bridgeRemoved = New-Object 'System.Collections.Generic.List[string]'
if ([bool]$bridgeCleanupPlan.present) {
    foreach ($bridgeRecord in @($bridgeCleanupPlan.records)) {
        Remove-BridgeLink -Path ([string]$bridgeRecord.target)
        $bridgeRemoved.Add("bridge/$([string]$bridgeRecord.skill)")
    }
    if (Test-Path -LiteralPath $bridgeManifestPath) {
        if ($PSCmdlet.ShouldProcess($bridgeManifestPath, "Remove manifest-owned bridge metadata")) {
            Remove-Item -LiteralPath $bridgeManifestPath -Force
        }
        $bridgeRemoved.Add("agent-skill-bridge-manifest.json")
    }
}

if (Test-Path -LiteralPath $targetRoot) {
    Remove-DirectoryIfEmpty -Path $targetRoot -Root $targetRoot
}

$result = [ordered]@{
    schema_version = 1
    target_dir = $targetRoot
    manifest_path = $manifestPath
    status = "uninstalled"
    removed = @($removed.ToArray())
    missing = @($missing.ToArray())
    preserved_unknown = if ($manifestSchemaVersion -eq 2) { $true } else { $null }
    protection_scope = if ($manifestSchemaVersion -eq 2) { "schema2_copy_preflight" } else { "legacy_manifest_item_boundaries" }
    bridge_removed = @($bridgeRemoved.ToArray())
    nested_unknown = @()
    locally_modified = @()
}

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-Output "Uninstalled Agent Ecosystem public runtime content from: $targetRoot"
    Write-Output "Removed: $($removed.Count)"
    if ($missing.Count -gt 0) {
        Write-Output "Already missing: $($missing.Count)"
    }
    if ($manifestSchemaVersion -eq 2) {
        Write-Output "Schema-2 copy items passed nested unknown and local-modification preflight."
        Write-Output "Paths outside manifest destinations were preserved."
    }
    else {
        Write-Output "Legacy manifest destinations were removed without file-level unknown-content verification."
    }
    if ($bridgeRemoved.Count -gt 0) {
        Write-Output "Manifest-owned bridge integration removed: $($bridgeRemoved.Count)"
    }
}
