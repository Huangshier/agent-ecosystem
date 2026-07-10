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

function Get-PhysicalPathItem {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowMissing
    )

    $itemErrors = @()
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue -ErrorVariable +itemErrors
    if ($null -ne $item) {
        return $item
    }

    $unexpectedErrors = @($itemErrors | Where-Object {
            [string]$_.FullyQualifiedErrorId -notmatch 'PathNotFound|ItemNotFound'
        })
    if ($unexpectedErrors.Count -gt 0) {
        throw "Unable to inspect path while resolving physical location: $Path"
    }
    if ($AllowMissing.IsPresent) {
        return $null
    }
    throw "Existing path disappeared or could not be resolved: $Path"
}

function Get-ReparsePointTargetPath {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory = $true)][string]$LinkPath
    )

    $targetProperty = $Item.PSObject.Properties["Target"]
    if ($null -eq $targetProperty) {
        throw "Reparse point target cannot be inspected safely: $LinkPath"
    }
    $targetValues = @($targetProperty.Value | Select-Object -First 1)
    if ($targetValues.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$targetValues[0])) {
        throw "Reparse point target cannot be inspected safely: $LinkPath"
    }

    $targetPath = [string]$targetValues[0]
    if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
        $targetPath = Join-Path (Split-Path -Parent $LinkPath) $targetPath
    }
    return Get-NormalizedFullPath -Path $targetPath
}

function Resolve-ExistingPhysicalPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$VisitedLinks,
        [int]$Depth = 0
    )

    if ($Depth -gt 64) {
        throw "Reparse point resolution exceeded the safe hop limit: $Path"
    }

    $fullPath = Get-NormalizedFullPath -Path $Path
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    $relativePath = $fullPath.Substring($pathRoot.Length).TrimStart(@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ))
    $segments = @()
    if (-not [string]::IsNullOrEmpty($relativePath)) {
        $segments = @($relativePath -split '[\\/]+')
    }

    $current = Get-NormalizedFullPath -Path $pathRoot
    Get-PhysicalPathItem -Path $current | Out-Null
    foreach ($segment in $segments) {
        $candidate = Get-NormalizedFullPath -Path (Join-Path $current $segment)
        $item = Get-PhysicalPathItem -Path $candidate
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            foreach ($visitedLink in @($VisitedLinks.ToArray())) {
                if (Test-PlatformPathEqual -Left $visitedLink -Right $candidate) {
                    throw "Reparse point cycle detected while resolving physical location: $candidate"
                }
            }
            $VisitedLinks.Add($candidate)

            $targetPath = Get-ReparsePointTargetPath -Item $item -LinkPath $candidate
            $targetItem = Get-PhysicalPathItem -Path $targetPath -AllowMissing
            if ($null -eq $targetItem) {
                throw "Broken reparse point encountered while resolving physical location: $candidate -> $targetPath"
            }
            $current = Resolve-ExistingPhysicalPath -Path $targetPath -VisitedLinks $VisitedLinks -Depth ($Depth + 1)
        }
        else {
            $current = $candidate
        }
    }
    return Get-NormalizedFullPath -Path $current
}

function Resolve-PhysicalPathForWrite {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = Get-NormalizedFullPath -Path $Path
    $cursor = $fullPath
    $remainingSegments = New-Object 'System.Collections.Generic.List[string]'
    $existingItem = $null

    while ($null -eq $existingItem) {
        $existingItem = Get-PhysicalPathItem -Path $cursor -AllowMissing
        if ($null -ne $existingItem) {
            break
        }
        $cursorRoot = [System.IO.Path]::GetPathRoot($cursor)
        if (Test-PlatformPathEqual -Left $cursor -Right $cursorRoot) {
            throw "No existing ancestor could be resolved for path: $fullPath"
        }
        $remainingSegments.Insert(0, [System.IO.Path]::GetFileName($cursor))
        $cursor = Get-NormalizedFullPath -Path ([System.IO.Path]::GetDirectoryName($cursor))
    }

    $visitedLinks = New-Object 'System.Collections.Generic.List[string]'
    $physicalPath = Resolve-ExistingPhysicalPath -Path $cursor -VisitedLinks $visitedLinks
    if ($remainingSegments.Count -gt 0) {
        $physicalItem = Get-PhysicalPathItem -Path $physicalPath
        if (-not $physicalItem.PSIsContainer) {
            throw "Nearest existing physical path ancestor is not a directory: $physicalPath"
        }
    }
    foreach ($segment in @($remainingSegments.ToArray())) {
        $physicalPath = Join-Path $physicalPath $segment
    }
    return Get-NormalizedFullPath -Path $physicalPath
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
