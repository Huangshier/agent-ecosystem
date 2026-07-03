$ErrorActionPreference = "Stop"

function Write-HookJson {
    param([Parameter(Mandatory = $true)][object]$Value)

    [Console]::Out.WriteLine(($Value | ConvertTo-Json -Depth 8 -Compress))
}

function New-PreToolDecision {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("ask", "deny")][string]$Decision,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    return [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName = "PreToolUse"
            permissionDecision = $Decision
            permissionDecisionReason = $Reason
        }
    }
}

function Get-ProjectState {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $requiredPaths = @(
        "CLAUDE.md",
        "AGENTS.md",
        ".agents/AGENTS.md",
        ".agents/process.txt",
        ".agents/plan.md",
        ".agents/hub.lock.json",
        ".claude/guardrails/README.md",
        ".claude/guardrails/profile.json",
        ".claude/hooks/README.md"
    )
    $missing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $requiredPaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $relativePath) -PathType Leaf)) {
            $missing.Add($relativePath)
        }
    }

    $claudePath = Join-Path $ProjectRoot "CLAUDE.md"
    if (Test-Path -LiteralPath $claudePath -PathType Leaf) {
        $claudeText = [System.IO.File]::ReadAllText($claudePath)
        foreach ($requiredImport in @(
            "@AGENTS.md",
            "@.claude/guardrails/README.md"
        )) {
            if (-not $claudeText.Contains($requiredImport)) {
                $missing.Add("CLAUDE.md import: $requiredImport")
            }
        }
    }

    $profile = $null
    $profileName = ""
    $profilePath = Join-Path $ProjectRoot ".claude/guardrails/profile.json"
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        try {
            $profile = [System.IO.File]::ReadAllText($profilePath) | ConvertFrom-Json
            $profileName = [string]$profile.default_profile
            if ([string]::IsNullOrWhiteSpace($profileName) -or
                $null -eq $profile.write_authorization_profiles.$profileName) {
                $missing.Add("valid default_profile in .claude/guardrails/profile.json")
            }
        }
        catch {
            $missing.Add("valid .claude/guardrails/profile.json")
        }
    }

    return [ordered]@{
        missing = @($missing.ToArray())
        profile = $profile
        profile_name = $profileName
    }
}

function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    $rootFull = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]"\/")
    $candidateFull = if ([System.IO.Path]::IsPathRooted($Candidate)) {
        [System.IO.Path]::GetFullPath($Candidate)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $rootFull $Candidate))
    }
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    return ($candidateFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $candidateFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))
}

function Get-ToolTargetPath {
    param([object]$ToolInput)

    if ($null -eq $ToolInput) {
        return ""
    }
    foreach ($name in @("file_path", "path", "notebook_path")) {
        $property = $ToolInput.PSObject.Properties[$name]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return [string]$property.Value
        }
    }
    return ""
}

function Test-RawArtifactPublicationPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path -replace "\\", "/"
    $isQuarantined = $normalized -match '(?i)(^|/)(\.private|private|\.agents/private|\.claude/private)(/|$)'
    $looksRaw = $normalized -match '(?i)(transcript.*\.jsonl$|hook[-_]?payload|event[-_]?ledger|raw[-_]?evidence)'
    return ($looksRaw -and -not $isQuarantined)
}

function Test-ExternalWrite {
    param(
        [string]$ToolName,
        [object]$ToolInput
    )

    if ($ToolName -in @("Bash", "PowerShell", "Monitor")) {
        $command = [string]$ToolInput.command
        return ($command -match '(?i)(\bgit\s+push\b|\bgh\s+(issue|pr|release|repo|workflow)\s+(create|edit|close|reopen|merge|ready|delete|run)\b|\bapi\.github\.com\b)')
    }
    return ($ToolName -match '(?i)^mcp__.*github.*__(create|update|delete|merge|close|reopen|publish|dispatch|push|add|remove|mark|convert|request|rerun)')
}

function Test-DangerousMemoryOperation {
    param(
        [string]$ToolName,
        [object]$ToolInput
    )

    if ($ToolName -notin @("Bash", "PowerShell", "Monitor")) {
        return $false
    }
    $command = [string]$ToolInput.command
    $memorySurface = $command -match '(?i)(project-bootstrap|bootstrap_project|memory[_-](upgrade|governance)|project memory)'
    $dangerousMode = $command -match '(?i)(-ForceReset\b|--force-reset\b|-AutoUpgrade\b|\breset\b|\breinitialize\b)'
    return ($memorySurface -and $dangerousMode)
}

try {
    $rawInput = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($rawInput)) {
        throw "Hook input is empty."
    }
    $inputData = $rawInput | ConvertFrom-Json
    $eventName = [string]$inputData.hook_event_name
    $projectRoot = [string]$env:CLAUDE_PROJECT_DIR
    if ([string]::IsNullOrWhiteSpace($projectRoot)) {
        $projectRoot = [string]$inputData.cwd
    }
    if ([string]::IsNullOrWhiteSpace($projectRoot) -or -not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Project root is unavailable."
    }
    $projectRoot = [System.IO.Path]::GetFullPath($projectRoot)
    $state = Get-ProjectState -ProjectRoot $projectRoot

    if ($eventName -eq "SessionStart") {
        $context = if ($state.missing.Count -gt 0) {
            "needs-human: generated Claude project context is incomplete: $($state.missing -join ', '). Stop before external writes or memory governance work."
        }
        else {
            "Template reliability hooks runtime is active. CLAUDE.md imports and project context are present. Active write authorization profile: $($state.profile_name). Hooks do not authorize external writes and are not a security sandbox."
        }
        Write-HookJson ([ordered]@{
            hookSpecificOutput = [ordered]@{
                hookEventName = "SessionStart"
                additionalContext = $context
            }
        })
        exit 0
    }

    if ($eventName -eq "PreToolUse") {
        if ($state.missing.Count -gt 0) {
            Write-HookJson (New-PreToolDecision -Decision "deny" -Reason "needs-human: required project entrypoint, context, or authorization profile is missing.")
            exit 0
        }

        $toolName = [string]$inputData.tool_name
        $toolInput = $inputData.tool_input
        $eventCwd = [string]$inputData.cwd
        if (-not [string]::IsNullOrWhiteSpace($eventCwd) -and
            -not (Test-PathInsideRoot -Candidate $eventCwd -ProjectRoot $projectRoot)) {
            Write-HookJson (New-PreToolDecision -Decision "deny" -Reason "needs-human: the current tool working directory is outside the project boundary.")
            exit 0
        }
        $targetPath = Get-ToolTargetPath -ToolInput $toolInput
        if (-not [string]::IsNullOrWhiteSpace($targetPath)) {
            if (-not (Test-PathInsideRoot -Candidate $targetPath -ProjectRoot $projectRoot)) {
                Write-HookJson (New-PreToolDecision -Decision "deny" -Reason "needs-human: the requested write path is outside the project boundary.")
                exit 0
            }
            if (Test-RawArtifactPublicationPath -Path $targetPath) {
                Write-HookJson (New-PreToolDecision -Decision "deny" -Reason "needs-human: quarantine raw transcripts, hook payloads, event ledgers, and raw evidence in a declared local/private path.")
                exit 0
            }
        }

        if (Test-DangerousMemoryOperation -ToolName $toolName -ToolInput $toolInput) {
            Write-HookJson (New-PreToolDecision -Decision "ask" -Reason "Dangerous memory refresh or reset mode requires explicit user confirmation.")
            exit 0
        }

        if (Test-ExternalWrite -ToolName $toolName -ToolInput $toolInput) {
            if ($state.profile_name -ne "public-contributor") {
                Write-HookJson (New-PreToolDecision -Decision "ask" -Reason "External write requires explicit confirmation under the active write authorization profile.")
            }
            exit 0
        }

        exit 0
    }

    if ($eventName -eq "Stop") {
        if ([bool]$inputData.stop_hook_active) {
            exit 0
        }
        if ($state.missing.Count -gt 0) {
            Write-HookJson ([ordered]@{
                decision = "block"
                reason = "needs-human: required project context is incomplete; report the missing context before stopping."
            })
        }
        exit 0
    }

    exit 0
}
catch {
    $message = "needs-human: Claude guardrail hook could not evaluate the event safely."
    if ($eventName -eq "SessionStart") {
        Write-HookJson ([ordered]@{
            hookSpecificOutput = [ordered]@{
                hookEventName = "SessionStart"
                additionalContext = $message
            }
        })
    }
    elseif ($eventName -eq "Stop") {
        Write-HookJson ([ordered]@{ decision = "block"; reason = $message })
    }
    else {
        Write-HookJson (New-PreToolDecision -Decision "deny" -Reason $message)
    }
    exit 0
}
