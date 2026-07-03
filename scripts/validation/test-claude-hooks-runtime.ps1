[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-claude-hooks-runtime-{0}" -f ([Guid]::NewGuid().ToString("N")))
}
$ScratchRoot = [System.IO.Path]::GetFullPath($ScratchRoot)
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
if (-not $ScratchRoot.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "ScratchRoot must be inside the system temporary directory."
}

function Copy-TreeContents {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
    }
}

function Invoke-HookFixture {
    param(
        [Parameter(Mandatory = $true)][string]$RunnerPath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][object]$Event
    )

    $powerShellPath = (Get-Process -Id $PID).Path
    $eventJson = $Event | ConvertTo-Json -Depth 10 -Compress
    $oldProjectDir = [string]$env:CLAUDE_PROJECT_DIR
    try {
        $env:CLAUDE_PROJECT_DIR = $ProjectRoot
        $output = @($eventJson | & $powerShellPath -NoProfile -File $RunnerPath 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        if ([string]::IsNullOrEmpty($oldProjectDir)) {
            Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
        }
        else {
            $env:CLAUDE_PROJECT_DIR = $oldProjectDir
        }
    }
    return [ordered]@{
        exit_code = $exitCode
        output = ($output -join "`n").Trim()
    }
}

$fixturePath = Join-Path $RepositoryRoot "scripts/validation/claude-hooks-runtime-fixtures/cases.json"
$fixture = [System.IO.File]::ReadAllText($fixturePath) | ConvertFrom-Json
if ([int]$fixture.schema_version -ne 1 -or [string]$fixture.source -ne "public-deterministic-hook-io-fixtures") {
    throw "Claude hooks runtime fixture metadata is invalid."
}
$requiredCases = @(
    "powershell-external-write-asks",
    "powershell-dangerous-memory-reset-asks",
    "monitor-external-write-asks"
)
$fixtureCaseNames = @($fixture.cases | ForEach-Object { [string]$_.name })
foreach ($requiredCase in $requiredCases) {
    if ($requiredCase -notin $fixtureCaseNames) {
        throw "Claude hooks runtime fixtures are missing required case: $requiredCase"
    }
}

$authorityRoot = Join-Path $RepositoryRoot "knowledge-hub/templates/languages/en"
$projectRootTemplate = Join-Path $authorityRoot "project-root"
$projectAgentTemplate = Join-Path $authorityRoot "project-agent"
$results = New-Object 'System.Collections.Generic.List[object]'
$failures = New-Object 'System.Collections.Generic.List[string]'

try {
    New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null
    foreach ($case in @($fixture.cases)) {
        if (-not [bool]$case.public_safe) {
            $failures.Add("fixture is not public_safe: $($case.name)")
            continue
        }
        $caseRoot = Join-Path $ScratchRoot ([string]$case.name)
        Copy-TreeContents -Source $projectRootTemplate -Destination $caseRoot
        Copy-TreeContents -Source $projectAgentTemplate -Destination (Join-Path $caseRoot ".agents")
        [System.IO.File]::WriteAllText((Join-Path $caseRoot ".agents/hub.lock.json"), "{`"schema_version`":1}")

        foreach ($relativePath in @($case.remove_paths)) {
            if ([string]::IsNullOrWhiteSpace([string]$relativePath)) {
                continue
            }
            $removePath = [System.IO.Path]::GetFullPath((Join-Path $caseRoot ([string]$relativePath)))
            $casePrefix = [System.IO.Path]::GetFullPath($caseRoot).TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
            if (-not $removePath.StartsWith($casePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Fixture remove path escaped the case root."
            }
            Remove-Item -LiteralPath $removePath -Force
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$case.profile_override)) {
            $profilePath = Join-Path $caseRoot ".claude/guardrails/profile.json"
            $profile = [System.IO.File]::ReadAllText($profilePath) | ConvertFrom-Json
            $profile.default_profile = [string]$case.profile_override
            [System.IO.File]::WriteAllText($profilePath, ($profile | ConvertTo-Json -Depth 10))
        }

        $runnerPath = Join-Path $caseRoot ".claude/hooks/guardrail.ps1"
        $actual = Invoke-HookFixture -RunnerPath $runnerPath -ProjectRoot $caseRoot -Event $case.event
        $caseFailures = New-Object 'System.Collections.Generic.List[string]'
        if ($actual.exit_code -ne 0) {
            $caseFailures.Add("exit code $($actual.exit_code)")
        }

        $expectNoOutput = [bool]$case.expected.no_output
        $outputObject = $null
        if ($expectNoOutput) {
            if (-not [string]::IsNullOrWhiteSpace($actual.output)) {
                $caseFailures.Add("expected no stdout")
            }
        }
        elseif ([string]::IsNullOrWhiteSpace($actual.output)) {
            $caseFailures.Add("expected structured stdout")
        }
        else {
            try {
                $outputObject = $actual.output | ConvertFrom-Json
            }
            catch {
                $caseFailures.Add("stdout was not valid JSON")
            }
        }

        if ($null -ne $outputObject) {
            if (-not [string]::IsNullOrWhiteSpace([string]$case.expected.permission_decision) -and
                [string]$outputObject.hookSpecificOutput.permissionDecision -ne [string]$case.expected.permission_decision) {
                $caseFailures.Add("permission decision mismatch")
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$case.expected.decision) -and
                [string]$outputObject.decision -ne [string]$case.expected.decision) {
                $caseFailures.Add("stop decision mismatch")
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$case.expected.reason_contains)) {
                $reason = [string]$outputObject.reason
                if ([string]::IsNullOrWhiteSpace($reason)) {
                    $reason = [string]$outputObject.hookSpecificOutput.permissionDecisionReason
                }
                if (-not $reason.Contains([string]$case.expected.reason_contains)) {
                    $caseFailures.Add("reason mismatch")
                }
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$case.expected.additional_context_contains) -and
                -not ([string]$outputObject.hookSpecificOutput.additionalContext).Contains([string]$case.expected.additional_context_contains)) {
                $caseFailures.Add("additional context mismatch")
            }
        }

        $passed = $caseFailures.Count -eq 0
        if (-not $passed) {
            $failures.Add("$($case.name): $($caseFailures -join ', ')")
        }
        $results.Add([ordered]@{
            name = [string]$case.name
            status = $(if ($passed) { "PASS" } else { "FAIL" })
            findings = @($caseFailures.ToArray())
        })
    }
}
finally {
    if (Test-Path -LiteralPath $ScratchRoot) {
        Remove-Item -LiteralPath $ScratchRoot -Recurse -Force
    }
}

$summary = [ordered]@{
    status = $(if ($failures.Count -eq 0) { "PASS" } else { "FAIL" })
    case_count = $results.Count
    passed = @($results | Where-Object { $_.status -eq "PASS" }).Count
    failed = @($results | Where-Object { $_.status -eq "FAIL" }).Count
    results = @($results.ToArray())
    failures = @($failures.ToArray())
}

if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 8
}
else {
    foreach ($result in $results) {
        Write-Output ("[{0}] {1}" -f $result.status, $result.name)
    }
    Write-Output ("Claude hooks runtime fixtures: {0}/{1} PASS" -f $summary.passed, $summary.case_count)
}

if ($failures.Count -gt 0) {
    exit 1
}
