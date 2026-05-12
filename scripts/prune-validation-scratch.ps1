[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ScratchRoot,
    [int]$RetainLatest = 10,
    [string]$EvidenceFileName = "validation-result.json",
    [switch]$Apply,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir "lib/path-guard.ps1")

function Assert-ScratchPruneRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $fullRepoRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    $driveRoot = [System.IO.Path]::GetPathRoot($fullRoot).TrimEnd('\', '/')
    $gitRoot = Join-PathParts $fullRepoRoot ".git"

    if ([string]::IsNullOrWhiteSpace($fullRoot)) {
        throw "ScratchRoot resolved to an empty path."
    }
    if ($fullRoot.Equals($driveRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to prune a filesystem root: $fullRoot"
    }
    if ($fullRoot.Equals($fullRepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to prune the repository root: $fullRoot"
    }
    if ($fullRoot.Equals($gitRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullRoot.StartsWith($gitRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to prune the repository .git directory: $fullRoot"
    }

    Assert-NotLiveRuntime -Path $fullRoot
}

function Measure-DirectoryBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    $measurement = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum
    if ($null -eq $measurement.Sum) {
        return [int64]0
    }
    return [int64]$measurement.Sum
}

if ($RetainLatest -lt 1) {
    throw "RetainLatest must be greater than zero."
}
if ([string]::IsNullOrWhiteSpace($EvidenceFileName)) {
    throw "EvidenceFileName must not be empty."
}
if ($EvidenceFileName -match '[\\/]') {
    throw "EvidenceFileName must be a file name, not a path: $EvidenceFileName"
}

$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot).TrimEnd('\', '/')
Assert-ScratchPruneRoot -Root $scratchRootFull -RepositoryRoot $repoRoot

if (-not (Test-Path -LiteralPath $scratchRootFull -PathType Container)) {
    throw "ScratchRoot does not exist or is not a directory: $scratchRootFull"
}

$candidates = @(
    Get-ChildItem -LiteralPath $scratchRootFull -Force -Directory |
        Where-Object { Test-Path -LiteralPath (Join-PathParts $_.FullName $EvidenceFileName) } |
        ForEach-Object {
            $fullName = [System.IO.Path]::GetFullPath($_.FullName).TrimEnd('\', '/')
            Assert-PathInsideRoot -Path $fullName -Root $scratchRootFull
            [pscustomobject]@{
                name = $_.Name
                path = $fullName
                last_write_utc = $_.LastWriteTimeUtc.ToString("o")
                bytes = Measure-DirectoryBytes -Path $fullName
            }
        } |
        Sort-Object -Property last_write_utc -Descending
)

$retained = @($candidates | Select-Object -First $RetainLatest)
$prunable = @($candidates | Select-Object -Skip $RetainLatest)

if ($Apply.IsPresent) {
    foreach ($item in $prunable) {
        $target = [string]$item.path
        Assert-PathInsideRoot -Path $target -Root $scratchRootFull
        $evidencePath = Join-PathParts $target $EvidenceFileName
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw "Refusing to prune run without evidence marker: $target"
        }
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

$selectedBytes = [int64]0
foreach ($item in $prunable) {
    $selectedBytes += [int64]$item.bytes
}

$result = [ordered]@{
    schema_version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    scratch_root = $scratchRootFull
    evidence_file_name = $EvidenceFileName
    apply = [bool]$Apply.IsPresent
    retain_latest = $RetainLatest
    summary = [ordered]@{
        candidate_count = $candidates.Count
        retained_count = $retained.Count
        prunable_count = $prunable.Count
        selected_bytes = $selectedBytes
    }
    retained = @($retained)
    prunable = @($prunable)
}

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-Output "Validation scratch pruning summary"
    Write-Output ("Scratch root: {0}" -f $scratchRootFull)
    Write-Output ("Evidence marker: {0}" -f $EvidenceFileName)
    Write-Output ("Apply: {0}" -f [bool]$Apply.IsPresent)
    Write-Output ("Candidates={0} Retained={1} Prunable={2} SelectedBytes={3}" -f $result.summary.candidate_count, $result.summary.retained_count, $result.summary.prunable_count, $result.summary.selected_bytes)
    if (-not $Apply.IsPresent -and $prunable.Count -gt 0) {
        Write-Output "Dry run only. Re-run with -Apply to remove the prunable directories."
    }
}
