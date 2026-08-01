[CmdletBinding()]
param(
    [switch]$Json,
    [string]$OutputPath,
    [string[]]$ChangedPath
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$changeValidator = Join-Path $PSScriptRoot "validate-change.ps1"
$routingTester = Join-Path $PSScriptRoot "test-validate-change.ps1"
$sensitiveScanTester = Join-Path $PSScriptRoot "validation/test-sensitive-scan.ps1"

function Normalize-ChangedPaths {
    param([string[]]$Paths)

    return @(
        $Paths |
            ForEach-Object { @(([string]$_) -split ',') } |
            ForEach-Object { (([string]$_).Trim().Replace('\', '/')) -replace '^\./', '' } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function Get-GitDiffPaths {
    param([string]$Base, [string]$Head)

    $paths = @(& git -C $repoRoot diff --name-only -M $Base $Head 2>$null)
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($exitCode -ne 0) {
        throw "Could not resolve validation diff boundary: $Base..$Head"
    }
    return @(Normalize-ChangedPaths -Paths $paths)
}

function Get-ValidationChangedPaths {
    param([string[]]$ExplicitPaths)

    $directPaths = @(Normalize-ChangedPaths -Paths $ExplicitPaths)
    if ($directPaths.Count -gt 0) {
        return [ordered]@{
            source = "explicit"
            base_ref = ""
            head_ref = ""
            paths = $directPaths
        }
    }

    $base = [string]$env:PR_BASE_SHA
    $head = [string]$env:PR_HEAD_SHA
    $source = "pull-request-environment"
    if ([string]::IsNullOrWhiteSpace($base) -or [string]::IsNullOrWhiteSpace($head)) {
        $base = [string]$env:GITHUB_EVENT_BEFORE
        $head = [string]$env:GITHUB_SHA
        $source = "push-environment"
        if ([string]::IsNullOrWhiteSpace($base) -and -not [string]::IsNullOrWhiteSpace([string]$env:GITHUB_EVENT_PATH) -and (Test-Path -LiteralPath $env:GITHUB_EVENT_PATH -PathType Leaf)) {
            try {
                $event = Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
                $base = [string]$event.before
            }
            catch {
                $base = ""
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($base) -or [string]::IsNullOrWhiteSpace($head) -or $base -match '^0+$') {
        return [ordered]@{
            source = "unavailable"
            base_ref = $base
            head_ref = $head
            paths = @()
        }
    }

    try {
        $paths = @(Get-GitDiffPaths -Base $base -Head $head)
        return [ordered]@{
            source = $source
            base_ref = $base
            head_ref = $head
            paths = $paths
        }
    }
    catch {
        return [ordered]@{
            source = "unavailable"
            base_ref = $base
            head_ref = $head
            paths = @()
            error = $_.Exception.Message
        }
    }
}

function Invoke-JsonChild {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments
    )

    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-heavy-stderr-{0}.log" -f ([Guid]::NewGuid().ToString("N")))
    try {
        $global:LASTEXITCODE = 0
        $raw = @(& pwsh -NoProfile -File $ScriptPath @Arguments 2> $stderrPath)
        $exitCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        $stderr = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
    }
    finally {
        if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }
    $text = ($raw | ForEach-Object { [string]$_ }) -join "`n"
    if ($exitCode -ne 0) {
        throw "Child validation script failed with exit ${exitCode}: $ScriptPath`n$text`n$stderr"
    }

    # Targeted child checks may emit informational lines before their JSON summary.
    # Keep the exit-code failure boundary, but parse the first complete JSON object
    # so those diagnostics do not invalidate otherwise complete evidence.
    for ($start = 0; $start -lt $text.Length; $start++) {
        if ($text[$start] -ne '{') {
            continue
        }

        $depth = 0
        $inString = $false
        $escaped = $false
        for ($index = $start; $index -lt $text.Length; $index++) {
            $character = $text[$index]
            if ($inString) {
                if ($escaped) {
                    $escaped = $false
                }
                elseif ($character -eq '\') {
                    $escaped = $true
                }
                elseif ($character -eq '"') {
                    $inString = $false
                }
                continue
            }

            if ($character -eq '"') {
                $inString = $true
            }
            elseif ($character -eq '{') {
                $depth++
            }
            elseif ($character -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $candidate = $text.Substring($start, $index - $start + 1)
                    try {
                        return ($candidate | ConvertFrom-Json)
                    }
                    catch {
                        break
                    }
                }
            }
        }
    }

    throw "Child validation script did not produce JSON evidence: $ScriptPath`n$text"
}

function Get-SensitiveScanDecision {
    param([object]$Boundary)

    $paths = @($Boundary.paths)
    if ($paths.Count -eq 0) {
        return [ordered]@{
            execute = $true
            reason = "changed-paths-unavailable-fail-closed"
            source = [string]$Boundary.source
            base_ref = [string]$Boundary.base_ref
            head_ref = [string]$Boundary.head_ref
            changed_paths = @()
            control_plane = $null
        }
    }

    $classificationRaw = @(& $changeValidator -ChangedPath $paths -Json 2>&1)
    $classificationExit = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($classificationExit -ne 0) {
        throw "Could not classify validation control-plane paths with exit $classificationExit."
    }
    $classificationText = ($classificationRaw | ForEach-Object { [string]$_ }) -join "`n"
    try {
        $classification = $classificationText | ConvertFrom-Json
    }
    catch {
        throw "Validation control-plane classification did not produce JSON evidence: $classificationText"
    }
    $controlPlane = [bool]$classification.control_plane
    return [ordered]@{
        execute = $controlPlane
        reason = $(if ($controlPlane) { "self-protection-control-surface" } else { "no-sensitive-scan-control-surface-change" })
        source = [string]$Boundary.source
        base_ref = [string]$Boundary.base_ref
        head_ref = [string]$Boundary.head_ref
        changed_paths = $paths
        control_plane = $controlPlane
    }
}

$boundary = Get-ValidationChangedPaths -ExplicitPaths $ChangedPath
$sensitiveDecision = Get-SensitiveScanDecision -Boundary $boundary
$routingResult = Invoke-JsonChild -ScriptPath $routingTester -Arguments @("-RunTargetedRegression", "-Json")

$sensitiveResult = [ordered]@{
    status = "NOT_RUN"
    case_count = 0
    pass = 0
    fail = 0
    executed = $false
    reason = [string]$sensitiveDecision.reason
    cases = @()
}
if ([bool]$sensitiveDecision.execute) {
    $fixtureResult = Invoke-JsonChild -ScriptPath $sensitiveScanTester -Arguments @("-Json")
    $fixtureCaseCount = @($fixtureResult.cases).Count
    if ([string]$fixtureResult.status -cne "PASS" -or [int]$fixtureResult.pass -ne 17 -or [int]$fixtureResult.fail -ne 0 -or $fixtureCaseCount -ne 17) {
        throw "Sensitive scan self-protection requires 17/17 PASS; got status=$($fixtureResult.status) cases=$fixtureCaseCount pass=$($fixtureResult.pass) fail=$($fixtureResult.fail)."
    }
    $sensitiveResult = [ordered]@{
        status = [string]$fixtureResult.status
        case_count = $fixtureCaseCount
        pass = [int]$fixtureResult.pass
        fail = [int]$fixtureResult.fail
        executed = $true
        reason = [string]$sensitiveDecision.reason
        cases = @($fixtureResult.cases)
    }
}

$summary = [ordered]@{
    schema_version = 2
    status = "PASS"
    routing = $routingResult
    sensitive_scan = $sensitiveResult
    sensitive_scan_regression = $sensitiveDecision
}
$summaryJson = $summary | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Set-Content -LiteralPath $OutputPath -Value $summaryJson -Encoding UTF8
}
if ($Json.IsPresent) {
    $summaryJson
}
else {
    Write-Output ("validation self-protection: PASS; sensitive scan={0} cases={1}/{2}" -f $sensitiveResult.status, $sensitiveResult.pass, $sensitiveResult.case_count)
}
