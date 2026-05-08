function ConvertTo-DisplayPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($fullRoot.Length).TrimStart([char[]]"\/") -replace "\\", "/"
    }
    return $fullPath -replace "\\", "/"
}

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [ValidateSet("PASS", "FAIL", "WARN", "DEFERRED")]
        [string]$Status,
        [string]$Detail = "",
        [object]$Data = $null
    )

    $script:checks.Add([ordered]@{
        name = $Name
        status = $Status
        detail = $Detail
        data = $Data
    })
}

function Test-RequiredPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [switch]$Directory
    )

    $path = Join-PathParts $repoRoot $RelativePath
    if ($Directory.IsPresent) {
        return [System.IO.Directory]::Exists($path)
    }
    return [System.IO.File]::Exists($path)
}

function Get-GitFiles {
    $output = & git -C $repoRoot ls-files --cached --others --exclude-standard
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed."
    }
    return @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-FileText {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $path = Join-PathParts $repoRoot $RelativePath
    return [System.IO.File]::ReadAllText($path)
}

function Get-LineMatches {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    $path = Join-PathParts $repoRoot $RelativePath
    if (-not [System.IO.File]::Exists($path)) {
        return @()
    }

    $lines = [System.IO.File]::ReadAllLines($path)
    $lineMatches = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $Pattern) {
            $lineMatches.Add([object][ordered]@{
                path = $RelativePath
                line = $i + 1
                text = $lines[$i].Trim()
            })
        }
    }
    return @($lineMatches.ToArray())
}

function Get-CurrentPowerShellPath {
    $currentProcess = Get-Process -Id $PID
    if (-not [string]::IsNullOrWhiteSpace($currentProcess.Path)) {
        return $currentProcess.Path
    }

    $windowsPowerShell = Get-Command powershell -ErrorAction SilentlyContinue
    if ($null -ne $windowsPowerShell -and -not [string]::IsNullOrWhiteSpace($windowsPowerShell.Source)) {
        return $windowsPowerShell.Source
    }

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $pwsh -and -not [string]::IsNullOrWhiteSpace($pwsh.Source)) {
        return $pwsh.Source
    }

    throw "Unable to locate a PowerShell executable for isolated negative-path checks."
}

function Get-PowerShellFileArguments {
    param(
        [Parameter(Mandatory = $true)][string]$PowerShellPath,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $result = @("-NoProfile")
    $exeName = [System.IO.Path]::GetFileNameWithoutExtension($PowerShellPath)
    $isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    if ($isWindowsPlatform -and $exeName -in @("powershell", "pwsh")) {
        $result += "-ExecutionPolicy"
        $result += "Bypass"
    }
    $result += "-File"
    $result += $ScriptPath
    $result += $Arguments
    return @($result)
}

function Invoke-IsolatedPowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $powerShellPath = Get-CurrentPowerShellPath
    $powerShellArguments = @(Get-PowerShellFileArguments -PowerShellPath $powerShellPath -ScriptPath $ScriptPath -Arguments $Arguments)
    $output = @(& $powerShellPath @powerShellArguments 2>&1 | ForEach-Object { [string]$_ })
    return [ordered]@{
        exit_code = [int]$LASTEXITCODE
        output = @($output)
    }
}

function Test-ExactArray {
    param(
        [object[]]$Actual,
        [object[]]$Expected
    )

    $actualValues = @($Actual | ForEach-Object { [string]$_ } | Sort-Object)
    $expectedValues = @($Expected | ForEach-Object { [string]$_ } | Sort-Object)
    if ($actualValues.Count -ne $expectedValues.Count) {
        return $false
    }
    for ($i = 0; $i -lt $actualValues.Count; $i++) {
        if ($actualValues[$i] -ne $expectedValues[$i]) {
            return $false
        }
    }
    return $true
}
