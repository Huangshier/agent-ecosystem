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
        "skills/project-context-gate",
        "skills/workflow-spec-lite",
        "skills/memory-governance"
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

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifestItems = @($manifest.items)
$manifestSchemaVersion = [int]$manifest.schema_version
$nestedUnknown = New-Object 'System.Collections.Generic.List[string]'
$locallyModified = New-Object 'System.Collections.Generic.List[string]'

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
    $blockedResult = [ordered]@{
        schema_version = 1
        target_dir = $targetRoot
        manifest_path = $manifestPath
        status = "blocked"
        reason = "schema2_copy_item_safety_check"
        removed = @()
        missing = @()
        preserved_unknown = $true
        protection_scope = "schema2_copy_preflight"
        nested_unknown = $nestedUnknownValues
        locally_modified = $locallyModifiedValues
    }
    if ($Json.IsPresent) {
        $blockedResult | ConvertTo-Json -Depth 8
    }
    else {
        Write-Output "Uninstall blocked. No files were removed."
        Write-Output "Nested unknown files: $($nestedUnknownValues.Count)"
        Write-Output "Locally modified managed files: $($locallyModifiedValues.Count)"
        Write-Output "The install manifest and install report were preserved."
    }
    exit 2
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
}
