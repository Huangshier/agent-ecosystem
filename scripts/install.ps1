[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet("minimal", "recommended", "full", "dev")]
    [string]$Profile = "recommended",

    [string]$TargetDir = (Join-Path $HOME ".agents"),

    [switch]$Copy,

    [switch]$DevLink,

    [switch]$ReplaceManaged,

    [switch]$AllowPartial,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir "lib/path-guard.ps1")
$targetRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetDir)
$manifestPath = Join-PathParts $targetRoot "install-manifest.json"
$reportPath = Join-PathParts $targetRoot "install-report.json"

if ($Copy.IsPresent -and $DevLink.IsPresent) {
    throw "-Copy and -DevLink cannot be used together. Copy is the default; use -DevLink only for an explicit source-linked development runtime."
}

$installStrategy = "copy"
if ($DevLink.IsPresent) {
    $installStrategy = "dev-link"
}

$replaceManagedRequested = $ReplaceManaged.IsPresent -or $Force.IsPresent
$warnings = New-Object 'System.Collections.Generic.List[string]'
if ($Force.IsPresent) {
    $forceWarning = "WARNING: -Force is deprecated for full reinstall semantics; treating it as -ReplaceManaged. Use -ReplaceManaged explicitly in new scripts."
    $warnings.Add($forceWarning)
    Write-Output $forceWarning
}

$kernelSkills = @(
    "project-bootstrap",
    "project-context-gate",
    "workflow-spec-lite",
    "memory-governance"
)

function Get-PublicSkillNames {
    param([string]$SelectedProfile)

    if ($SelectedProfile -eq "minimal") {
        return @("project-bootstrap")
    }

    if ($SelectedProfile -in @("recommended", "full", "dev")) {
        return @($kernelSkills)
    }

    throw "Unsupported profile: $SelectedProfile"
}

function Get-InstallerSourceProvenance {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string[]]$ManagedSourcePaths
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $unknown = [ordered]@{
            release_version = $null
            source_commit = $null
        }

        $worktreeRoot = @(& git -C $SourceRoot rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or $worktreeRoot.Count -ne 1) {
            return $unknown
        }

        $resolvedSourceRoot = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
        $resolvedWorktreeRoot = [System.IO.Path]::GetFullPath([string]$worktreeRoot[0]).TrimEnd('\', '/')
        if (-not $resolvedSourceRoot.Equals($resolvedWorktreeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $unknown
        }

        $head = @(& git -C $SourceRoot rev-parse --verify HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or [string]$head[0] -notmatch '^[0-9a-fA-F]{40}$') {
            return $unknown
        }

        & git -C $SourceRoot diff --quiet HEAD -- @ManagedSourcePaths 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $unknown
        }

        $untracked = @(& git -C $SourceRoot ls-files --others --exclude-standard -- @ManagedSourcePaths 2>$null)
        if ($LASTEXITCODE -ne 0 -or $untracked.Count -gt 0) {
            return $unknown
        }

        $versionTags = @(& git -C $SourceRoot tag --points-at HEAD 2>$null | Where-Object { [string]$_ -match '^v\d+\.\d+\.\d+$' })
        if ($LASTEXITCODE -ne 0 -or $versionTags.Count -gt 1) {
            return $unknown
        }

        return [ordered]@{
            release_version = $(if ($versionTags.Count -eq 1) { [string]$versionTags[0] } else { $null })
            source_commit = ([string]$head[0]).ToLowerInvariant()
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function ConvertTo-NormalizedRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return ($Path -replace "\\", "/").TrimStart('/')
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
        throw "Path is outside the managed root: $Path"
    }
    return ConvertTo-NormalizedRelativePath -Path $fullPath.Substring($prefix.Length)
}

function Join-RuntimeRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Child
    )

    return ((ConvertTo-NormalizedRelativePath -Path $Base).TrimEnd('/') + "/" + (ConvertTo-NormalizedRelativePath -Path $Child))
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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
            sha256 = Get-FileSha256 -Path $file.FullName
        }
    }
    return $result
}

function Get-TextSha256 {
    param([AllowEmptyString()][string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes)) -replace "-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-StateHash {
    param(
        [object[]]$Entries = @(),
        [Parameter(Mandatory = $true)][string]$HashProperty
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in @($Entries | Sort-Object { [string]$_.path })) {
        $hashValue = [string]$entry.$HashProperty
        if (-not [string]::IsNullOrWhiteSpace($hashValue)) {
            $lines.Add(("{0}`0{1}" -f ([string]$entry.path), $hashValue))
        }
    }
    return Get-TextSha256 -Text ($lines -join "`n")
}

function Test-ReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-LinkMode {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    $linkTypeProperty = $item.PSObject.Properties["LinkType"]
    if ($null -ne $linkTypeProperty -and -not [string]::IsNullOrWhiteSpace([string]$linkTypeProperty.Value)) {
        return ([string]$linkTypeProperty.Value).ToLowerInvariant()
    }
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return "junction"
    }
    return "symboliclink"
}

function Get-LinkTargetPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    $targetProperty = $item.PSObject.Properties["Target"]
    if ($null -eq $targetProperty) {
        return ""
    }
    $targetValue = @($targetProperty.Value | Select-Object -First 1)
    if ($targetValue.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$targetValue[0])) {
        return ""
    }
    $targetPath = [string]$targetValue[0]
    if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
        $targetPath = Join-Path (Split-Path -Parent $Path) $targetPath
    }
    return [System.IO.Path]::GetFullPath($targetPath).TrimEnd('\', '/')
}

function Remove-ManagedLink {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        [System.IO.Directory]::Delete($item.FullName)
    }
    else {
        [System.IO.File]::Delete($item.FullName)
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 12
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json + [System.Environment]::NewLine, $utf8NoBom)
}

function Copy-ManagedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($Destination, "Update managed runtime file")) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

function Remove-ManagedFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ((Test-Path -LiteralPath $Path) -and $PSCmdlet.ShouldProcess($Path, "Remove managed runtime file no longer present in source")) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Get-PreviousFileMap {
    param([AllowNull()][object]$Item)

    $result = @{}
    if ($null -eq $Item -or $null -eq $Item.PSObject.Properties["files"]) {
        return $result
    }
    foreach ($file in @($Item.files)) {
        $path = ConvertTo-NormalizedRelativePath -Path ([string]$file.path)
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $result[$path] = $file
        }
    }
    return $result
}

function New-ManagedFileRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$SourceHash,
        [AllowEmptyString()][string]$InstalledHash
    )

    return [ordered]@{
        path = ConvertTo-NormalizedRelativePath -Path $Path
        source_sha256 = $SourceHash
        installed_sha256 = $InstalledHash
    }
}

$previousManifest = $null
$previousSchemaVersion = 0
if (Test-Path -LiteralPath $manifestPath) {
    try {
        $previousManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $previousSchemaVersion = [int]$previousManifest.schema_version
    }
    catch {
        throw "Unable to read the existing install manifest: $($_.Exception.Message)"
    }
    if ($previousSchemaVersion -notin @(1, 2)) {
        throw "Unsupported install manifest schema_version: $previousSchemaVersion"
    }
}

$previousItems = @{}
if ($null -ne $previousManifest) {
    foreach ($item in @($previousManifest.items)) {
        $itemName = [string]$item.name
        if (-not [string]::IsNullOrWhiteSpace($itemName)) {
            $previousItems[$itemName] = $item
        }
    }
}

$updated = New-Object 'System.Collections.Generic.List[string]'
$unchanged = New-Object 'System.Collections.Generic.List[string]'
$skippedLocallyModified = New-Object 'System.Collections.Generic.List[string]'
$conflicts = New-Object 'System.Collections.Generic.List[string]'
$manifestItems = New-Object 'System.Collections.Generic.List[object]'

function Install-CopyItem {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SourceRelative,
        [Parameter(Mandatory = $true)][string]$DestinationRelative
    )

    $source = Join-PathParts $repoRoot $SourceRelative
    $destination = Join-PathParts $targetRoot $DestinationRelative
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Source not found for ${Name}: $SourceRelative"
    }
    Assert-PathInsideRoot -Path $destination -Root $targetRoot -Message "Refusing to modify path outside target root"

    $previousItem = $null
    if ($previousItems.ContainsKey($Name)) {
        $previousItem = $previousItems[$Name]
    }
    $previousFiles = Get-PreviousFileMap -Item $previousItem
    $legacyManifest = $previousSchemaVersion -eq 1

    if (Test-ReparsePoint -Path $destination) {
        $previousMode = ""
        if ($null -ne $previousItem) {
            $previousMode = [string]$previousItem.mode
        }
        $previousWasLink = $previousMode -in @("junction", "symboliclink")
        if ($legacyManifest -and $null -ne $previousManifest.PSObject.Properties["link_preferred"] -and [bool]$previousManifest.link_preferred) {
            $previousWasLink = $true
        }
        if ($null -eq $previousItem -or (-not $previousWasLink -and -not $replaceManagedRequested)) {
            $rootConflictPath = ConvertTo-NormalizedRelativePath -Path $DestinationRelative
            $skippedLocallyModified.Add($rootConflictPath)
            $conflicts.Add($rootConflictPath)
            return $previousItem
        }
        if ($PSCmdlet.ShouldProcess($destination, "Replace managed development link with copy install")) {
            Remove-ManagedLink -Path $destination
        }
    }
    elseif ((Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath $destination -PathType Container)) {
        if ($null -eq $previousItem -or -not $replaceManagedRequested) {
            $rootConflictPath = ConvertTo-NormalizedRelativePath -Path $DestinationRelative
            $skippedLocallyModified.Add($rootConflictPath)
            $conflicts.Add($rootConflictPath)
            return $previousItem
        }
        if ($PSCmdlet.ShouldProcess($destination, "Replace managed item with directory")) {
            Remove-Item -LiteralPath $destination -Force
        }
    }

    if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
    }

    $sourceFiles = Get-DirectoryFileMap -Root $source
    $targetFiles = Get-DirectoryFileMap -Root $destination
    $paths = @($sourceFiles.Keys) + @($previousFiles.Keys)
    $paths = @($paths | Sort-Object -Unique)
    $newFiles = New-Object 'System.Collections.Generic.List[object]'

    foreach ($relativePath in $paths) {
        $runtimePath = Join-RuntimeRelativePath -Base $DestinationRelative -Child $relativePath
        $sourceExists = $sourceFiles.ContainsKey($relativePath)
        $targetExists = $targetFiles.ContainsKey($relativePath)
        $previousExists = $previousFiles.ContainsKey($relativePath)
        $sourceHash = ""
        $targetHash = ""
        $installedHash = ""
        if ($sourceExists) { $sourceHash = [string]$sourceFiles[$relativePath].sha256 }
        if ($targetExists) { $targetHash = [string]$targetFiles[$relativePath].sha256 }
        if ($previousExists) { $installedHash = [string]$previousFiles[$relativePath].installed_sha256 }

        if ($legacyManifest -and -not $previousExists -and $sourceExists -and $targetExists) {
            if ($sourceHash -eq $targetHash) {
                $unchanged.Add($runtimePath)
            }
            elseif ($replaceManagedRequested) {
                Copy-ManagedFile -Source ([string]$sourceFiles[$relativePath].path) -Destination (Join-PathParts $destination $relativePath)
                $updated.Add($runtimePath)
            }
            else {
                $skippedLocallyModified.Add($runtimePath)
                $conflicts.Add($runtimePath)
            }
            $recordedInstalledHash = $sourceHash
            if ($sourceHash -ne $targetHash -and -not $replaceManagedRequested) {
                $recordedInstalledHash = $targetHash
            }
            $newFiles.Add((New-ManagedFileRecord -Path $relativePath -SourceHash $sourceHash -InstalledHash $recordedInstalledHash))
            continue
        }

        if (-not $previousExists) {
            if (-not $sourceExists) {
                continue
            }
            if ($targetExists) {
                $skippedLocallyModified.Add($runtimePath)
                $conflicts.Add($runtimePath)
                continue
            }
            if (-not $targetExists -or $targetHash -ne $sourceHash) {
                Copy-ManagedFile -Source ([string]$sourceFiles[$relativePath].path) -Destination (Join-PathParts $destination $relativePath)
                $updated.Add($runtimePath)
            }
            else {
                $unchanged.Add($runtimePath)
            }
            $newFiles.Add((New-ManagedFileRecord -Path $relativePath -SourceHash $sourceHash -InstalledHash $sourceHash))
            continue
        }

        if ([string]::IsNullOrWhiteSpace($installedHash)) {
            $installedHash = [string]$previousFiles[$relativePath].source_sha256
        }

        if ($sourceExists) {
            if (-not $targetExists) {
                Copy-ManagedFile -Source ([string]$sourceFiles[$relativePath].path) -Destination (Join-PathParts $destination $relativePath)
                $updated.Add($runtimePath)
                $newFiles.Add((New-ManagedFileRecord -Path $relativePath -SourceHash $sourceHash -InstalledHash $sourceHash))
                continue
            }

            $targetMatchesInstalled = $targetHash -eq $installedHash
            $sourceMatchesInstalled = $sourceHash -eq $installedHash
            if ($targetMatchesInstalled) {
                if ($sourceMatchesInstalled) {
                    $unchanged.Add($runtimePath)
                }
                else {
                    Copy-ManagedFile -Source ([string]$sourceFiles[$relativePath].path) -Destination (Join-PathParts $destination $relativePath)
                    $updated.Add($runtimePath)
                }
                $newFiles.Add((New-ManagedFileRecord -Path $relativePath -SourceHash $sourceHash -InstalledHash $sourceHash))
                continue
            }

            if ($replaceManagedRequested) {
                Copy-ManagedFile -Source ([string]$sourceFiles[$relativePath].path) -Destination (Join-PathParts $destination $relativePath)
                $updated.Add($runtimePath)
                $newFiles.Add((New-ManagedFileRecord -Path $relativePath -SourceHash $sourceHash -InstalledHash $sourceHash))
                continue
            }

            $skippedLocallyModified.Add($runtimePath)
            if (-not $sourceMatchesInstalled) {
                $conflicts.Add($runtimePath)
            }
            $newFiles.Add((New-ManagedFileRecord -Path $relativePath -SourceHash $sourceHash -InstalledHash $installedHash))
            continue
        }

        if (-not $targetExists) {
            continue
        }
        if ($targetHash -eq $installedHash -or $replaceManagedRequested) {
            Remove-ManagedFile -Path ([string]$targetFiles[$relativePath].path)
            $updated.Add($runtimePath)
            continue
        }

        $skippedLocallyModified.Add($runtimePath)
        $conflicts.Add($runtimePath)
        $newFiles.Add((New-ManagedFileRecord -Path $relativePath -SourceHash "" -InstalledHash $installedHash))
    }

    $sourceStateEntries = @($sourceFiles.Keys | Sort-Object | ForEach-Object {
            [ordered]@{ path = $_; sha256 = [string]$sourceFiles[$_].sha256 }
        })
    $newFileArray = @($newFiles.ToArray() | Sort-Object { [string]$_.path })
    return [ordered]@{
        name = $Name
        source = ConvertTo-NormalizedRelativePath -Path $SourceRelative
        destination = ConvertTo-NormalizedRelativePath -Path $DestinationRelative
        mode = "copy"
        managed = $true
        source_hash = Get-StateHash -Entries $sourceStateEntries -HashProperty "sha256"
        installed_hash = Get-StateHash -Entries $newFileArray -HashProperty "installed_sha256"
        files = $newFileArray
    }
}

function Remove-ObsoleteManagedItem {
    param([Parameter(Mandatory = $true)][object]$PreviousItem)

    $name = [string]$PreviousItem.name
    $destinationRelative = ConvertTo-NormalizedRelativePath -Path ([string]$PreviousItem.destination)
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($destinationRelative)) {
        throw "Previous manifest contains an invalid managed item."
    }

    $conflictRoot = $destinationRelative
    if ($previousSchemaVersion -ne 2 -or [System.IO.Path]::IsPathRooted([string]$PreviousItem.destination)) {
        $skippedLocallyModified.Add($conflictRoot)
        $conflicts.Add($conflictRoot)
        return $PreviousItem
    }

    $destination = Join-PathParts $targetRoot $destinationRelative
    Assert-PathInsideRoot -Path $destination -Root $targetRoot -Message "Refusing to remove obsolete managed item outside target root"
    if (-not (Test-Path -LiteralPath $destination)) {
        return $null
    }

    $mode = [string]$PreviousItem.mode
    if ($mode -in @("junction", "symboliclink")) {
        if (-not (Test-ReparsePoint -Path $destination)) {
            $skippedLocallyModified.Add($conflictRoot)
            $conflicts.Add($conflictRoot)
            return $PreviousItem
        }
        $sourceRelative = ConvertTo-NormalizedRelativePath -Path ([string]$PreviousItem.source)
        $expectedTarget = [System.IO.Path]::GetFullPath((Join-PathParts $repoRoot $sourceRelative)).TrimEnd('\', '/')
        $actualTarget = Get-LinkTargetPath -Path $destination
        if ([string]::IsNullOrWhiteSpace($actualTarget) -or -not $actualTarget.Equals($expectedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
            $skippedLocallyModified.Add($conflictRoot)
            $conflicts.Add($conflictRoot)
            return $PreviousItem
        }
        if ($PSCmdlet.ShouldProcess($destination, "Remove managed development link excluded by selected profile")) {
            Remove-ManagedLink -Path $destination
        }
        $updated.Add($conflictRoot)
        return $null
    }

    if ($mode -ne "copy" -or (Test-ReparsePoint -Path $destination) -or -not (Test-Path -LiteralPath $destination -PathType Container)) {
        $skippedLocallyModified.Add($conflictRoot)
        $conflicts.Add($conflictRoot)
        return $PreviousItem
    }

    $previousFiles = Get-PreviousFileMap -Item $PreviousItem
    $targetFiles = Get-DirectoryFileMap -Root $destination
    $unsafePaths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in @($targetFiles.Keys | Sort-Object)) {
        $runtimePath = Join-RuntimeRelativePath -Base $destinationRelative -Child $relativePath
        if (-not $previousFiles.ContainsKey($relativePath)) {
            $unsafePaths.Add($runtimePath)
            continue
        }
        $installedHash = [string]$previousFiles[$relativePath].installed_sha256
        if ([string]::IsNullOrWhiteSpace($installedHash) -or [string]$targetFiles[$relativePath].sha256 -ne $installedHash) {
            $unsafePaths.Add($runtimePath)
        }
    }

    if ($unsafePaths.Count -gt 0) {
        foreach ($runtimePath in @($unsafePaths.ToArray())) {
            $skippedLocallyModified.Add($runtimePath)
            $conflicts.Add($runtimePath)
        }
        return $PreviousItem
    }

    foreach ($relativePath in @($targetFiles.Keys | Sort-Object)) {
        $updated.Add((Join-RuntimeRelativePath -Base $destinationRelative -Child $relativePath))
    }
    if ($PSCmdlet.ShouldProcess($destination, "Remove unchanged managed item excluded by selected profile")) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    return $null
}

function Install-DevLinkItem {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SourceRelative,
        [Parameter(Mandatory = $true)][string]$DestinationRelative
    )

    $source = Join-PathParts $repoRoot $SourceRelative
    $destination = Join-PathParts $targetRoot $DestinationRelative
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Source not found for ${Name}: $SourceRelative"
    }
    Assert-PathInsideRoot -Path $destination -Root $targetRoot -Message "Refusing to modify path outside target root"

    $previousItem = $null
    if ($previousItems.ContainsKey($Name)) {
        $previousItem = $previousItems[$Name]
    }
    $previousFiles = Get-PreviousFileMap -Item $previousItem

    if (Test-Path -LiteralPath $destination) {
        if (-not (Test-ReparsePoint -Path $destination)) {
            throw "Explicit -DevLink install cannot replace an existing copy directory while preserving unknown files: $DestinationRelative"
        }
        if ($null -eq $previousItem) {
            throw "Explicit -DevLink install found an unmanaged existing link: $DestinationRelative"
        }
        $actualLinkTarget = Get-LinkTargetPath -Path $destination
        $expectedLinkTarget = [System.IO.Path]::GetFullPath($source).TrimEnd('\', '/')
        if ([string]::IsNullOrWhiteSpace($actualLinkTarget) -or -not $actualLinkTarget.Equals($expectedLinkTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Explicit -DevLink install found a link that does not target the current source item: $DestinationRelative"
        }
    }
    else {
        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        $itemType = "SymbolicLink"
        if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            $itemType = "Junction"
        }
        if ($PSCmdlet.ShouldProcess($destination, "Create explicit development link")) {
            New-Item -ItemType $itemType -Path $destination -Target $source -ErrorAction Stop | Out-Null
        }
    }

    $sourceFiles = Get-DirectoryFileMap -Root $source
    $newFiles = New-Object 'System.Collections.Generic.List[object]'
    foreach ($relativePath in @($sourceFiles.Keys | Sort-Object)) {
        $runtimePath = Join-RuntimeRelativePath -Base $DestinationRelative -Child $relativePath
        $sourceHash = [string]$sourceFiles[$relativePath].sha256
        if ($previousFiles.ContainsKey($relativePath) -and [string]$previousFiles[$relativePath].installed_sha256 -eq $sourceHash) {
            $unchanged.Add($runtimePath)
        }
        else {
            $updated.Add($runtimePath)
        }
        $newFiles.Add((New-ManagedFileRecord -Path $relativePath -SourceHash $sourceHash -InstalledHash $sourceHash))
    }
    foreach ($relativePath in @($previousFiles.Keys | Where-Object { -not $sourceFiles.ContainsKey($_) } | Sort-Object)) {
        $updated.Add((Join-RuntimeRelativePath -Base $DestinationRelative -Child $relativePath))
    }

    $sourceStateEntries = @($sourceFiles.Keys | Sort-Object | ForEach-Object {
            [ordered]@{ path = $_; sha256 = [string]$sourceFiles[$_].sha256 }
        })
    $newFileArray = @($newFiles.ToArray() | Sort-Object { [string]$_.path })
    return [ordered]@{
        name = $Name
        source = ConvertTo-NormalizedRelativePath -Path $SourceRelative
        destination = ConvertTo-NormalizedRelativePath -Path $DestinationRelative
        mode = Get-LinkMode -Path $destination
        managed = $true
        source_hash = Get-StateHash -Entries $sourceStateEntries -HashProperty "sha256"
        installed_hash = Get-StateHash -Entries $newFileArray -HashProperty "installed_sha256"
        files = $newFileArray
    }
}

$skillNames = @(Get-PublicSkillNames -SelectedProfile $Profile)
$managedSourcePaths = @("knowledge-hub") + @($skillNames | ForEach-Object { "skills/$_" })
$sourceProvenance = Get-InstallerSourceProvenance -SourceRoot $repoRoot -ManagedSourcePaths $managedSourcePaths
$itemSpecs = New-Object 'System.Collections.Generic.List[object]'
$desiredItemNames = @{}
$itemSpecs.Add([ordered]@{ name = "knowledge-hub"; source = "knowledge-hub"; destination = "knowledge-hub" })
$desiredItemNames["knowledge-hub"] = $true
foreach ($skillName in $skillNames) {
    $itemSpecs.Add([ordered]@{
            name = "skills/$skillName"
            source = "skills/$skillName"
            destination = "skills/$skillName"
        })
    $desiredItemNames["skills/$skillName"] = $true
}

New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
foreach ($spec in $itemSpecs) {
    $item = $null
    if ($installStrategy -eq "dev-link") {
        $item = Install-DevLinkItem -Name $spec.name -SourceRelative $spec.source -DestinationRelative $spec.destination
    }
    else {
        $item = Install-CopyItem -Name $spec.name -SourceRelative $spec.source -DestinationRelative $spec.destination
    }
    if ($null -ne $item) {
        $manifestItems.Add($item)
    }
}

foreach ($previousName in @($previousItems.Keys | Sort-Object)) {
    if ($desiredItemNames.ContainsKey($previousName)) {
        continue
    }
    $retainedItem = Remove-ObsoleteManagedItem -PreviousItem $previousItems[$previousName]
    if ($null -ne $retainedItem) {
        $manifestItems.Add($retainedItem)
    }
}

$managedRuntimeFiles = @{}
$managedRuntimeRoots = @{}
foreach ($item in @($manifestItems.ToArray())) {
    $managedRuntimeRoots[(ConvertTo-NormalizedRelativePath -Path ([string]$item.destination))] = $true
    foreach ($file in @($item.files)) {
        $managedRuntimeFiles[(Join-RuntimeRelativePath -Base ([string]$item.destination) -Child ([string]$file.path))] = $true
    }
}

$preservedUnknown = New-Object 'System.Collections.Generic.List[string]'
foreach ($file in @(Get-ChildItem -LiteralPath $targetRoot -Recurse -File -Force)) {
    $relativePath = ConvertTo-RelativeChildPath -Path $file.FullName -Root $targetRoot
    if ($relativePath -in @("install-manifest.json", "install-report.json")) {
        continue
    }
    if (-not $managedRuntimeFiles.ContainsKey($relativePath) -and -not $managedRuntimeRoots.ContainsKey($relativePath)) {
        $preservedUnknown.Add($relativePath)
    }
}

$updatedValues = @($updated.ToArray() | Sort-Object -Unique)
$unchangedValues = @($unchanged.ToArray() | Sort-Object -Unique)
$unknownValues = @($preservedUnknown.ToArray() | Sort-Object -Unique)
$skippedValues = @($skippedLocallyModified.ToArray() | Sort-Object -Unique)
$conflictValues = @($conflicts.ToArray() | Sort-Object -Unique)
$warningValues = @($warnings.ToArray())
$manifestUpdated = -not ($previousSchemaVersion -eq 1 -and $conflictValues.Count -gt 0)
$resultingManifestSchemaVersion = 2
if (-not $manifestUpdated) {
    $resultingManifestSchemaVersion = $previousSchemaVersion
}

$status = "success"
if ($conflictValues.Count -gt 0) {
    $status = "conflict"
}
elseif ($unknownValues.Count -gt 0 -or $skippedValues.Count -gt 0 -or $warningValues.Count -gt 0) {
    $status = "warning"
}

$manifest = [ordered]@{
    schema_version = 2
    source_identity = "agent-ecosystem"
    release_version = $sourceProvenance.release_version
    source_commit = $sourceProvenance.source_commit
    install_strategy = $installStrategy
    profile = $Profile
    installed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    target_dir = "."
    skills = @($skillNames)
    items = @($manifestItems.ToArray())
}

$report = [ordered]@{
    schema_version = 1
    status = $status
    profile = $Profile
    install_strategy = $installStrategy
    allow_partial = [bool]$AllowPartial.IsPresent
    replace_managed = [bool]$replaceManagedRequested
    manifest_updated = [bool]$manifestUpdated
    manifest_schema_version = [int]$resultingManifestSchemaVersion
    counts = [ordered]@{
        updated = $updatedValues.Count
        unchanged = $unchangedValues.Count
        preserved_unknown = $unknownValues.Count
        skipped_locally_modified = $skippedValues.Count
        conflicts = $conflictValues.Count
    }
    updated = $updatedValues
    unchanged = $unchangedValues
    preserved_unknown = $unknownValues
    skipped_locally_modified = $skippedValues
    conflicts = $conflictValues
    warnings = $warningValues
}

if ($manifestUpdated -and $PSCmdlet.ShouldProcess($manifestPath, "Write install manifest")) {
    Write-JsonFile -Path $manifestPath -Value $manifest
}
if ($PSCmdlet.ShouldProcess($reportPath, "Write install report")) {
    Write-JsonFile -Path $reportPath -Value $report
}

if ($status -eq "success") {
    Write-Output "Install completed successfully."
}
elseif ($status -eq "warning") {
    Write-Output "Install completed with warnings."
}
else {
    Write-Output "Install completed with conflicts."
}
Write-Output ""
Write-Output "Updated: $($updatedValues.Count) files"
Write-Output "Unchanged: $($unchangedValues.Count) files"
Write-Output "Preserved unknown files: $($unknownValues.Count)"
Write-Output "Skipped locally modified managed files: $($skippedValues.Count)"
Write-Output "Conflicts: $($conflictValues.Count)"
Write-Output ""
Write-Output "Manifest: $manifestPath"
Write-Output "Report: $reportPath"

if ($conflictValues.Count -gt 0 -and -not $AllowPartial.IsPresent) {
    throw "Install completed with conflicts. Re-run with -AllowPartial to accept partial success or -ReplaceManaged to replace managed files."
}
