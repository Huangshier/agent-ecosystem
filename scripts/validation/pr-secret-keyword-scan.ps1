# pr-secret-keyword-scan.ps1
# Lightweight PR added-line sensitive scan.
# Dot-sources the shared sensitive scan contract; rules are not duplicated here.
# Only scans added lines in the PR diff; deleted lines, context lines, and
# unmodified history never trigger.
# Fail-closed: missing diff or unavailable refs produce FAIL, not SKIP.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseRef,
    [Parameter(Mandatory = $true)][string]$HeadRef,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

# Load shared sensitive scan contract
$contractPath = Join-Path (Split-Path -Parent $PSCommandPath) "sensitive-scan-contract.ps1"
if (-not (Test-Path -LiteralPath $contractPath)) {
    if ($Json.IsPresent) {
        [ordered]@{ status = "FAIL"; reason = "contract-missing"; violation_count = 0; violations = @() } | ConvertTo-Json -Depth 4
    } else {
        Write-Output "PR sensitive scan: FAIL (sensitive scan contract not found)"
    }
    exit 1
}
. $contractPath

# Compute PR diff (added lines only)
$global:LASTEXITCODE = 0
$diffLines = @(& git diff "$BaseRef" "$HeadRef" --unified=1 --diff-filter=ACMR 2>$null)
if ($LASTEXITCODE -ne 0) {
    # Fail-closed: diff unavailable is a scan failure
    if ($Json.IsPresent) {
        [ordered]@{ status = "FAIL"; reason = "diff-unavailable"; base_ref = $BaseRef; head_ref = $HeadRef; violation_count = 0; violations = @() } | ConvertTo-Json -Depth 4
    } else {
        Write-Output "PR sensitive scan: FAIL (diff unavailable between $BaseRef and $HeadRef)"
    }
    exit 1
}
$global:LASTEXITCODE = 0

# Parse diff: extract added lines per file with line numbers
$violations = New-Object 'System.Collections.Generic.List[object]'
$currentFile = ""
$currentLine = 0
$inHunk = $false

foreach ($line in $diffLines) {
    if ($line.StartsWith("diff --git ")) {
        $inHunk = $false
        continue
    }
    if ($line -match '^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@') {
        $currentLine = [int]$Matches[1]
        $inHunk = $true
        continue
    }
    if (-not $inHunk) {
        if ($line -match '^\+\+\+ b/(.*)$') {
            $currentFile = $Matches[1] -replace '\\', '/'
        }
        continue
    }
    if ($line.StartsWith("+")) {
        $text = $line.Substring(1)

        # High-risk format rules: never allowed in any path
        foreach ($rule in $SensitiveScanHighRiskPatterns) {
            if ($text -match $rule.pattern) {
                $violations.Add([ordered]@{
                    rule = $rule.name
                    path = $currentFile
                    line = $currentLine
                    text = $text.Trim()
                })
            }
        }

        # Keyword rule: exempt allowed paths and exact allowed references
        if ($text -match $SensitiveScanKeywordPattern) {
            $isAllowedPath = $currentFile -in $SensitiveScanAllowedPaths
            $isExactAllowed = $SensitiveScanAllowedReferences.ContainsKey($currentFile) -and
                $text -match $SensitiveScanAllowedReferences[$currentFile]
            if (-not $isAllowedPath -and -not $isExactAllowed) {
                $violations.Add([ordered]@{
                    rule = "secret_keyword"
                    path = $currentFile
                    line = $currentLine
                    text = $text.Trim()
                })
            }
        }

        $currentLine++
    }
    elseif ($line.StartsWith("-")) {
        # Deleted lines do not increment line number
    }
    else {
        # Context lines are ignored for matching but advance the new-file line number.
        $currentLine++
    }
}

if ($Json.IsPresent) {
    [ordered]@{
        status = if ($violations.Count -eq 0) { "PASS" } else { "FAIL" }
        base_ref = $BaseRef
        head_ref = $HeadRef
        violation_count = $violations.Count
        violations = @($violations.ToArray())
    } | ConvertTo-Json -Depth 4
} else {
    if ($violations.Count -eq 0) {
        Write-Output "PR sensitive scan: PASS (0 violations in added lines)"
    } else {
        Write-Output "PR sensitive scan: FAIL ($($violations.Count) violations in added lines)"
        foreach ($v in $violations) {
            Write-Output ("  {0}:{1} [{2}] {3}" -f $v.path, $v.line, $v.rule, $v.text)
        }
    }
}

if ($violations.Count -gt 0) { exit 1 }
exit 0
