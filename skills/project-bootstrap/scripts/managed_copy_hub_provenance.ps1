function Test-ManagedCopyHubObject {
    param([AllowNull()][object]$Value)
    return $null -ne $Value -and $Value -isnot [System.Array] -and $Value -isnot [string] -and $Value -isnot [ValueType]
}

function Get-ManagedCopyHubProperty {
    param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-ManagedCopyHubInteger {
    param([AllowNull()][object]$Value)
    return $Value -is [sbyte] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

function Test-ManagedCopyHubRelativePath {
    param([AllowNull()][object]$Value)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $false }
    $path = [string]$Value
    return -not [System.IO.Path]::IsPathRooted($path) -and
        $path -cnotmatch '\\' -and $path -cnotmatch '(^|/)\.{1,2}(/|$)' -and
        $path -cnotmatch '//|^/|/$' -and $path -cmatch '^[^:]+$'
}

function Get-ManagedCopyHubFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if (-not [string]::IsNullOrEmpty($root) -and $fullPath.Length -eq $root.Length) { return $root }
    return $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Get-ManagedCopyHubPathComparison {
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return [System.StringComparison]::OrdinalIgnoreCase
    }
    return [System.StringComparison]::Ordinal
}

function Test-ManagedCopyHubPathEqual {
    param([Parameter(Mandatory = $true)][string]$Left, [Parameter(Mandatory = $true)][string]$Right)
    return (Get-ManagedCopyHubFullPath -Path $Left).Equals(
        (Get-ManagedCopyHubFullPath -Path $Right),
        (Get-ManagedCopyHubPathComparison)
    )
}

function Test-ManagedCopyHubPathContained {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root)
    $fullPath = Get-ManagedCopyHubFullPath -Path $Path
    $fullRoot = Get-ManagedCopyHubFullPath -Path $Root
    $comparison = Get-ManagedCopyHubPathComparison
    if ($fullPath.Equals($fullRoot, $comparison)) { return $true }
    $boundary = $fullRoot
    if (-not $boundary.EndsWith([string][System.IO.Path]::DirectorySeparatorChar) -and
        -not $boundary.EndsWith([string][System.IO.Path]::AltDirectorySeparatorChar)) {
        $boundary += [System.IO.Path]::DirectorySeparatorChar
    }
    return $fullPath.StartsWith($boundary, $comparison)
}

function Test-ManagedCopyHubPathIsPlain {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root)
    $fullPath = Get-ManagedCopyHubFullPath -Path $Path
    $fullRoot = Get-ManagedCopyHubFullPath -Path $Root
    if (-not (Test-ManagedCopyHubPathContained -Path $fullPath -Root $fullRoot)) { return $false }

    $rootItem = Get-Item -LiteralPath $fullRoot -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    if (Test-ManagedCopyHubPathEqual -Left $fullPath -Right $fullRoot) { return $true }

    $relative = $fullPath.Substring($fullRoot.Length).TrimStart(@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ))
    $cursor = $fullRoot
    foreach ($segment in @($relative -split '[\\/]+')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        $cursor = Join-Path $cursor $segment
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    }
    return $true
}

function Test-TrustedManagedCopyHub {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeDir,
        [Parameter(Mandatory = $true)][string]$HubDir
    )

    try {
        $runtimeRoot = Get-ManagedCopyHubFullPath -Path $RuntimeDir
        $resolvedHub = Get-ManagedCopyHubFullPath -Path $HubDir
        $expectedHub = Get-ManagedCopyHubFullPath -Path (Join-Path $runtimeRoot "knowledge-hub")
        if (-not (Test-ManagedCopyHubPathEqual -Left $resolvedHub -Right $expectedHub)) { return $false }
        if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container) -or
            -not (Test-Path -LiteralPath $resolvedHub -PathType Container)) { return $false }
        if (-not (Test-ManagedCopyHubPathIsPlain -Path $resolvedHub -Root $runtimeRoot)) { return $false }

        $manifestPath = Get-ManagedCopyHubFullPath -Path (Join-Path $runtimeRoot "install-manifest.json")
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
            -not (Test-ManagedCopyHubPathIsPlain -Path $manifestPath -Root $runtimeRoot)) { return $false }
        $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
        if (-not (Test-ManagedCopyHubObject -Value $manifest)) { return $false }

        $schema = Get-ManagedCopyHubProperty -Object $manifest -Name "schema_version"
        if (-not (Test-ManagedCopyHubInteger -Value $schema) -or [int64]$schema -ne 2) { return $false }
        if ((Get-ManagedCopyHubProperty -Object $manifest -Name "source_identity") -isnot [string] -or
            [string](Get-ManagedCopyHubProperty -Object $manifest -Name "source_identity") -cne "agent-ecosystem") { return $false }
        if ((Get-ManagedCopyHubProperty -Object $manifest -Name "install_strategy") -isnot [string] -or
            [string](Get-ManagedCopyHubProperty -Object $manifest -Name "install_strategy") -cne "copy") { return $false }
        if ((Get-ManagedCopyHubProperty -Object $manifest -Name "target_dir") -isnot [string] -or
            [string](Get-ManagedCopyHubProperty -Object $manifest -Name "target_dir") -cne ".") { return $false }

        $itemsProperty = $manifest.PSObject.Properties["items"]
        if ($null -eq $itemsProperty -or $itemsProperty.Value -isnot [System.Array]) { return $false }
        $items = $itemsProperty.Value
        $hubItems = @($items | Where-Object {
                (Test-ManagedCopyHubObject -Value $_) -and (
                    [string](Get-ManagedCopyHubProperty -Object $_ -Name "name") -ceq "knowledge-hub" -or
                    [string](Get-ManagedCopyHubProperty -Object $_ -Name "source") -ceq "knowledge-hub" -or
                    [string](Get-ManagedCopyHubProperty -Object $_ -Name "destination") -ceq "knowledge-hub"
                )
            })
        if ($hubItems.Count -ne 1) { return $false }
        $hubItem = $hubItems[0]
        if ([string](Get-ManagedCopyHubProperty -Object $hubItem -Name "name") -cne "knowledge-hub" -or
            [string](Get-ManagedCopyHubProperty -Object $hubItem -Name "source") -cne "knowledge-hub" -or
            [string](Get-ManagedCopyHubProperty -Object $hubItem -Name "destination") -cne "knowledge-hub" -or
            [string](Get-ManagedCopyHubProperty -Object $hubItem -Name "mode") -cne "copy" -or
            (Get-ManagedCopyHubProperty -Object $hubItem -Name "managed") -isnot [bool] -or
            -not [bool](Get-ManagedCopyHubProperty -Object $hubItem -Name "managed")) { return $false }

        $filesProperty = $hubItem.PSObject.Properties["files"]
        if ($null -eq $filesProperty -or $filesProperty.Value -isnot [System.Array]) { return $false }
        $files = $filesProperty.Value
        if ($files.Count -eq 0) { return $false }
        $seenPaths = New-Object 'System.Collections.Generic.List[string]'
        foreach ($file in @($files)) {
            if (-not (Test-ManagedCopyHubObject -Value $file)) { return $false }
            $relativePath = Get-ManagedCopyHubProperty -Object $file -Name "path"
            $sourceHash = Get-ManagedCopyHubProperty -Object $file -Name "source_sha256"
            $installedHash = Get-ManagedCopyHubProperty -Object $file -Name "installed_sha256"
            if (-not (Test-ManagedCopyHubRelativePath -Value $relativePath) -or
                $sourceHash -isnot [string] -or [string]$sourceHash -cnotmatch '^[0-9a-f]{64}$' -or
                $installedHash -isnot [string] -or [string]$installedHash -cnotmatch '^[0-9a-f]{64}$' -or
                [string]$sourceHash -cne [string]$installedHash) { return $false }
            if (@($seenPaths.ToArray() | Where-Object {
                        [string]::Equals($_, [string]$relativePath, [System.StringComparison]::OrdinalIgnoreCase)
                    }).Count -gt 0) { return $false }
            $seenPaths.Add([string]$relativePath)

            $nativeRelativePath = ([string]$relativePath).Replace([char]'/', [System.IO.Path]::DirectorySeparatorChar)
            $livePath = Get-ManagedCopyHubFullPath -Path (Join-Path $resolvedHub $nativeRelativePath)
            if (-not (Test-ManagedCopyHubPathContained -Path $livePath -Root $resolvedHub) -or
                -not (Test-Path -LiteralPath $livePath -PathType Leaf) -or
                -not (Test-ManagedCopyHubPathIsPlain -Path $livePath -Root $runtimeRoot)) { return $false }
            $liveHash = (Get-FileHash -LiteralPath $livePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($liveHash -cne [string]$installedHash) { return $false }
        }
        return $true
    }
    catch {
        return $false
    }
}
