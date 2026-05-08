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

function Get-AgentLiveRuntimeCandidates {
    $liveCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($HOME)) {
        $liveCandidates += [System.IO.Path]::GetFullPath((Join-Path $HOME ".agents")).TrimEnd('\', '/')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $liveCandidates += [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ".agents")).TrimEnd('\', '/')
    }
    return @($liveCandidates | Sort-Object -Unique)
}

function Assert-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$Message = "Path is outside expected root"
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "${Message}: $fullPath"
    }
}

function Assert-NotLiveRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$LiveRuntimeCandidates = @(),
        [string]$Message = "Refusing to use live runtime path"
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $candidates = @($LiveRuntimeCandidates)
    if ($candidates.Count -eq 0) {
        $candidates = @(Get-AgentLiveRuntimeCandidates)
    }
    foreach ($candidate in @($candidates | Sort-Object -Unique)) {
        if ($fullPath.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($candidate + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "${Message}: $fullPath"
        }
    }
}
