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
            Remove-Item -LiteralPath $Path -Force
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
$destinations = New-Object 'System.Collections.Generic.List[string]'
foreach ($item in $manifestItems) {
    $destination = [string]$item.destination
    if ([string]::IsNullOrWhiteSpace($destination)) {
        continue
    }

    Assert-PathInsideRoot -Path $destination -Root $targetRoot
    $fullDestination = [System.IO.Path]::GetFullPath($destination).TrimEnd('\', '/')
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
    preserved_unknown = $true
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
    Write-Output "Unknown files were preserved."
}
