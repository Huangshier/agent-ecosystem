[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SpecPath,
    [switch]$RequireExecutionContract,
    [switch]$Json,
    [switch]$FailOnError
)

$ErrorActionPreference = "Stop"

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [string]$Id,
        [string]$Message,
        [string]$Severity = "error"
    )

    $Findings.Add([ordered]@{
        id = $Id
        severity = $Severity
        message = $Message
    })
}

function Get-SectionBody {
    param(
        [string]$Text,
        [string[]]$Aliases
    )

    foreach ($alias in $Aliases) {
        $escaped = [regex]::Escape($alias)
        $localizedSuffix = "(?:\s*[\(\uFF08][^\)\uFF09]+[\)\uFF09])?"
        $pattern = "(?ms)^##\s+\d+\.\s+$escaped$localizedSuffix\s*$\r?\n(?<body>.*?)(?=^##\s+\d+\.|\z)"
        $match = [regex]::Match($Text, $pattern)
        if ($match.Success) {
            return [string]$match.Groups["body"].Value
        }
    }

    return $null
}

function Test-MeaningfulText {
    param([string]$Text)

    if ($null -eq $Text) {
        return $false
    }

    $lines = @($Text -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
    if ($lines.Count -eq 0) {
        return $false
    }

    $placeholderPatterns = @(
        '^\-\s*$',
        '^\-\s*\[.*\]\s*$',
        '^\-\s*What\b',
        '^\-\s*How\b',
        '^\-\s*Clear completion outcomes\s*$',
        '^\-\s*Explicit boundaries for this work item\s*$',
        '^\-\s*What may fail or require fallback\s*$'
    )

    $meaningful = @($lines | Where-Object {
        $line = $_
        -not (@($placeholderPatterns | Where-Object { $line -match $_ }).Count -gt 0)
    })

    return ($meaningful.Count -gt 0)
}

function Test-RequiredField {
    param(
        [string]$Text,
        [string]$FieldName
    )

    $localizedSuffix = "(?:[ \t]*[\(\uFF08][^\)\uFF09]+[\)\uFF09])?"
    $pattern = "(?m)^\-[ \t]+\*\*{0}{1}\*\*:[ \t]+\S" -f [regex]::Escape($FieldName), $localizedSuffix
    return ($Text -match $pattern)
}

$specFullPath = [System.IO.Path]::GetFullPath($SpecPath)
$findings = New-Object 'System.Collections.Generic.List[object]'

if (-not (Test-Path -LiteralPath $specFullPath)) {
    Add-Finding $findings "spec_missing" "Spec file does not exist: $specFullPath"
}
else {
    $text = Get-Content -LiteralPath $specFullPath -Raw

    foreach ($fieldName in @("Title", "Slug", "Status", "Owner", "Updated")) {
        if (-not (Test-RequiredField -Text $text -FieldName $fieldName)) {
            Add-Finding $findings ("metadata_{0}_missing" -f $fieldName.ToLowerInvariant()) "Required metadata field is missing or empty: $fieldName"
        }
    }

    $requiredSections = @(
        [ordered]@{ id = "summary"; aliases = @("Summary", "摘要") },
        [ordered]@{ id = "current_context"; aliases = @("Current Context", "当前上下文") },
        [ordered]@{ id = "goals"; aliases = @("Goals", "目标") },
        [ordered]@{ id = "non_goals"; aliases = @("Non-Goals", "非目标") },
        [ordered]@{ id = "constraints"; aliases = @("Constraints", "约束") },
        [ordered]@{ id = "risks"; aliases = @("Risks", "风险") },
        [ordered]@{ id = "approach"; aliases = @("Proposed Approach", "方案") },
        [ordered]@{ id = "acceptance"; aliases = @("Acceptance / Evidence", "验收与证据") }
    )

    foreach ($section in $requiredSections) {
        $body = Get-SectionBody -Text $text -Aliases $section.aliases
        if (-not (Test-MeaningfulText -Text $body)) {
            Add-Finding $findings ("section_{0}_missing" -f $section.id) ("Required spec section is missing or empty: {0}" -f ($section.aliases -join " / "))
        }
    }

    $executionBody = Get-SectionBody -Text $text -Aliases @("Execution Contract", "执行契约")
    $hasExecutionContract = Test-MeaningfulText -Text $executionBody
    if ($RequireExecutionContract.IsPresent -or $hasExecutionContract) {
        if (-not $hasExecutionContract) {
            Add-Finding $findings "execution_contract_missing" "Execution Contract is required but missing or empty."
        }
        else {
            foreach ($fieldName in @("Autonomy level", "Continue rule", "Stop rule", "State record")) {
                if (-not (Test-RequiredField -Text $executionBody -FieldName $fieldName)) {
                    Add-Finding $findings ("execution_{0}_missing" -f (($fieldName -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant())) "Execution Contract field is missing or empty: $fieldName"
                }
            }

            if ($executionBody -notmatch '(?m)^\s*-\s+P\d{2}:\s+\S') {
                Add-Finding $findings "execution_phase_list_missing" "Execution Contract must include at least one non-empty phase entry such as '- P01: ...'."
            }
        }
    }
}

$result = [ordered]@{
    schema_version = 1
    spec_path = $specFullPath
    require_execution_contract = [bool]$RequireExecutionContract.IsPresent
    pass = ($findings.Count -eq 0)
    findings = @($findings.ToArray())
}

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 5
}
else {
    if ($result.pass) {
        Write-Output "Spec validation passed: $specFullPath"
    }
    else {
        Write-Output "Spec validation failed: $specFullPath"
        foreach ($finding in $findings) {
            Write-Output ("[{0}] {1}: {2}" -f $finding.severity, $finding.id, $finding.message)
        }
    }
}

if ($FailOnError.IsPresent -and -not $result.pass) {
    throw "Spec validation failed: $specFullPath"
}
