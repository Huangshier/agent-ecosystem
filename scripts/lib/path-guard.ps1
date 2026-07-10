function Join-PathParts {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Children
    )

    $path = $Root
    foreach ($child in $Children) {
        if ([string]::IsNullOrWhiteSpace($child)) {
            continue
        }
        foreach ($segment in @($child -split '[\\/]+')) {
            if (-not [string]::IsNullOrWhiteSpace($segment)) {
                $path = Join-Path $path $segment
            }
        }
    }
    return $path
}

function Get-PlatformPathComparison {
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return [System.StringComparison]::OrdinalIgnoreCase
    }
    return [System.StringComparison]::Ordinal
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if (-not [string]::IsNullOrEmpty($pathRoot) -and $fullPath.Length -eq $pathRoot.Length) {
        return $pathRoot
    }
    return $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Test-PlatformPathEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $leftPath = Get-NormalizedFullPath -Path $Left
    $rightPath = Get-NormalizedFullPath -Path $Right
    return $leftPath.Equals($rightPath, (Get-PlatformPathComparison))
}

function Test-PathIsEqualOrChild {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = Get-NormalizedFullPath -Path $Path
    $fullRoot = Get-NormalizedFullPath -Path $Root
    $comparison = Get-PlatformPathComparison
    if ($fullPath.Equals($fullRoot, $comparison)) {
        return $true
    }

    $rootWithBoundary = $fullRoot
    if (-not $rootWithBoundary.EndsWith([string][System.IO.Path]::DirectorySeparatorChar) -and
        -not $rootWithBoundary.EndsWith([string][System.IO.Path]::AltDirectorySeparatorChar)) {
        $rootWithBoundary += [System.IO.Path]::DirectorySeparatorChar
    }
    return $fullPath.StartsWith($rootWithBoundary, $comparison)
}

function Test-IsFileSystemRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = Get-NormalizedFullPath -Path $Path
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    return (-not [string]::IsNullOrEmpty($pathRoot) -and (Test-PlatformPathEqual -Left $fullPath -Right $pathRoot))
}

function Get-AgentLiveRuntimeCandidates {
    $liveCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($HOME)) {
        $liveCandidates += Get-NormalizedFullPath -Path (Join-Path $HOME ".agents")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $liveCandidates += Get-NormalizedFullPath -Path (Join-Path $env:USERPROFILE ".agents")
    }
    return @($liveCandidates | Sort-Object -Unique)
}

function Assert-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$Message = "Path is outside expected root"
    )

    $fullPath = Get-NormalizedFullPath -Path $Path
    if (-not (Test-PathIsEqualOrChild -Path $fullPath -Root $Root)) {
        throw "${Message}: $fullPath"
    }
}

function Assert-NotLiveRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$LiveRuntimeCandidates = @(),
        [string]$Message = "Refusing to use live runtime path"
    )

    $fullPath = Get-NormalizedFullPath -Path $Path
    $candidates = @($LiveRuntimeCandidates)
    if ($candidates.Count -eq 0) {
        $candidates = @(Get-AgentLiveRuntimeCandidates)
    }
    foreach ($candidate in @($candidates | Sort-Object -Unique)) {
        if (Test-PathIsEqualOrChild -Path $fullPath -Root $candidate) {
            throw "${Message}: $fullPath"
        }
    }
}
