function Assert-GitCommitSha {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Value -notmatch '^[0-9a-fA-F]{40}$') {
        throw "$Label must be a 40-character Git commit ID."
    }
}

function Get-GitStablePatchId {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Commit
    )

    Assert-GitCommitSha -Value $Parent -Label "Parent"
    Assert-GitCommitSha -Value $Commit -Label "Commit"
    $parentNormalized = $Parent.ToLowerInvariant()
    $commitNormalized = $Commit.ToLowerInvariant()

    # NOTE: 仅将严格验证的 SHA 放入固定 Git 命令；内层 Git 管道保留原始字节，避免 PowerShell 文本转码.
    $pipeline = "git diff --no-ext-diff --binary --full-index --no-renames $parentNormalized $commitNormalized | git patch-id --stable"
    $patchProcessInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $workingDirectory = (Get-Location).Path
    if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
        throw "git patch-id must run from a filesystem working directory."
    }
    $patchProcessInfo.WorkingDirectory = $workingDirectory
    $patchProcess = $null
    $patchOutput = ""
    $patchError = ""
    $patchExitCode = -1
    try {
        if ($env:OS -ceq "Windows_NT") {
            $patchProcessInfo.FileName = $env:ComSpec
            $patchProcessInfo.Arguments = '/d /s /c "' + $pipeline + '"'
        }
        else {
            $patchProcessInfo.FileName = "/bin/sh"
            $patchProcessInfo.Arguments = '-c "' + $pipeline + '"'
        }
        $patchProcessInfo.UseShellExecute = $false
        $patchProcessInfo.RedirectStandardOutput = $true
        $patchProcessInfo.RedirectStandardError = $true

        # NOTE: WinPS 5.1 的函数内 cmd.exe 捕获不可靠；仅读取 patch-id ASCII 输出，内层 Git 管道保持原始字节.
        $patchProcess = [System.Diagnostics.Process]::new()
        $patchProcess.StartInfo = $patchProcessInfo
        [void]$patchProcess.Start()
        $patchOutput = $patchProcess.StandardOutput.ReadToEnd()
        $patchError = $patchProcess.StandardError.ReadToEnd()
        $patchProcess.WaitForExit()
        $patchExitCode = $patchProcess.ExitCode
    }
    finally {
        if ($null -ne $patchProcess) { $patchProcess.Dispose() }
    }

    # NOTE: patch-id 输出是 ASCII 标识符；只在 Git 完成原始 diff 传递后读取为文本.
    $patchOutput = ([string]$patchOutput).Trim()
    if ($patchExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($patchOutput)) {
        throw "git patch-id --stable failed for '$commitNormalized' (exit $patchExitCode): $patchError"
    }
    $records = @($patchOutput -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($records.Count -ne 1) {
        throw "git patch-id returned an unexpected number of records."
    }
    $parts = $records[0].Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -lt 1 -or $parts[0] -notmatch '^[0-9a-fA-F]{40}$') {
        throw "git patch-id returned malformed output."
    }
    return $parts[0].ToLowerInvariant()
}
