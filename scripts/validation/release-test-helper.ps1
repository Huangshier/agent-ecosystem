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

    $durationMs = 0L
    if ($null -ne $script:validationCheckStopwatch) {
        $elapsedMs = [long]$script:validationCheckStopwatch.ElapsedMilliseconds
        $durationMs = [Math]::Max(0L, ($elapsedMs - [long]$script:validationCheckCheckpointMs))
        $script:validationCheckCheckpointMs = $elapsedMs
    }

    $effectiveName = $Name
    $isMergedAssertion = $false
    if ($null -ne $script:releaseMergedCheckMap -and $script:releaseMergedCheckMap.ContainsKey($Name)) {
        $effectiveName = [string]$script:releaseMergedCheckMap[$Name]
        $isMergedAssertion = $true
    }

    $isMergeAuthority = $null -ne $script:releaseMergedCheckTargets -and $script:releaseMergedCheckTargets.ContainsKey($effectiveName)
    $existingIndex = -1
    if ($isMergedAssertion -or $isMergeAuthority) {
        for ($index = 0; $index -lt $script:checks.Count; $index++) {
            if ([string]$script:checks[$index]["name"] -ceq $effectiveName) {
                $existingIndex = $index
                break
            }
        }
    }

    $assertion = [ordered]@{
        name = $Name
        status = $Status
        detail = $Detail
        data = $Data
        duration_ms = [long]$durationMs
    }
    if ($isMergedAssertion) {
        $script:mergedCheckEvidence.Add([object]$assertion)
    }

    if ($existingIndex -lt 0) {
        $script:checks.Add([ordered]@{
            name = $effectiveName
            status = $Status
            detail = $(if ($isMergedAssertion) { "Merged assertion '$Name': $Detail" } else { $Detail })
            data = $(if ($isMergedAssertion) { @([object]$assertion) } else { $Data })
            duration_ms = [long]$durationMs
        })
        return
    }

    # NOTE: Merged assertions retain evidence while reporting one authoritative status.
    $current = $script:checks[$existingIndex]
    $statusRank = @{ PASS = 0; DEFERRED = 1; WARN = 2; FAIL = 3 }
    if ([int]$statusRank[$Status] -gt [int]$statusRank[[string]$current["status"]]) {
        $current["status"] = $Status
    }
    $current["duration_ms"] = [long]$current["duration_ms"] + [long]$durationMs
    $detailParts = @([string]$current["detail"], $(if ($isMergedAssertion) { "Merged assertion '$Name': $Detail" } else { $Detail })) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    $current["detail"] = $detailParts -join " | "
    $current["data"] = @($current["data"]) + @([object]$assertion)
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

function Get-MissingRequiredText {
    param(
        [AllowNull()][string]$Text,
        [string[]]$RequiredText = @()
    )

    if ($null -eq $Text) {
        $Text = ""
    }

    return @($RequiredText | Where-Object { $Text -notlike ("*{0}*" -f $_) })
}

function Get-ValidationFilesByExtension {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Filter
    )

    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Filter | Where-Object {
            (ConvertTo-DisplayPath -Path $_.FullName -Root $Root) -notmatch '(^|/)\.git(/|$)'
        })
}

function Test-BytesHaveUtf8Bom {
    param([byte[]]$Bytes)

    return ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
}

function Test-BytesHaveNonAscii {
    param([byte[]]$Bytes)

    foreach ($byte in $Bytes) {
        if ($byte -gt 0x7F) {
            return $true
        }
    }
    return $false
}

function Get-PowerShellParseError {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $ignoredAst = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$ignoredAst, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        return ("{0}: {1}" -f (ConvertTo-DisplayPath -Path $Path -Root $Root), ($errors | ForEach-Object { $_.Message }) -join "; ")
    }
    return ""
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
