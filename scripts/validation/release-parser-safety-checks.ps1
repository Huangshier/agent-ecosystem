# release-parser-safety-checks.ps1
# Extracted from scripts/validate-release.ps1 Invoke-ReleaseValidationParserSafetyChecks (Phase 2).
# Routes repository safety checks to PlatformNeutral and parser compatibility checks to RuntimePlatform.
# Depends on: release-test-helper.ps1 (Add-Check, ConvertTo-DisplayPath, Get-GitFiles, Get-LineMatches,
#             Get-ValidationFilesByExtension, Test-BytesHaveUtf8Bom, Test-BytesHaveNonAscii,
#             Get-PowerShellParseError), path-guard.ps1 (Join-PathParts).
# Scope: script-level $repoRoot, $script:evidence, $checks.

# Invoke-ReleaseParserSafetyChecks: Runs the selected parser/safety responsibility shard.
function Invoke-ReleaseParserSafetyChecks {
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("PlatformNeutral", "RuntimePlatform")]
    [string]$ValidationShard
)

if ($ValidationShard -ceq "PlatformNeutral") {
try {
    $gitDiffCheck = & git -c core.autocrlf=false -c core.safecrlf=false -C $repoRoot diff --check 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($gitDiffCheck -join "`n")
    }
    Add-Check "git diff check" "PASS" "git diff --check found no whitespace errors."
}
catch {
    Add-Check "git diff check" "FAIL" $_.Exception.Message
}
}

if ($ValidationShard -ceq "RuntimePlatform") {
try {
    $encodingErrors = New-Object 'System.Collections.Generic.List[string]'
    $psFiles = @(Get-ValidationFilesByExtension -Root $repoRoot -Filter "*.ps1")
    foreach ($file in $psFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -eq 0) {
            continue
        }

        $hasUtf8Bom = Test-BytesHaveUtf8Bom -Bytes $bytes
        $hasNonAscii = Test-BytesHaveNonAscii -Bytes $bytes

        if ($hasNonAscii -and -not $hasUtf8Bom) {
            $encodingErrors.Add(("{0}: contains non-ASCII bytes but is not UTF-8 with BOM" -f (ConvertTo-DisplayPath -Path $file.FullName -Root $repoRoot)))
        }
    }

    if ($encodingErrors.Count -gt 0) {
        Add-Check "Windows PowerShell script encoding" "FAIL" "Non-ASCII PowerShell scripts must be UTF-8 with BOM so Windows PowerShell 5.1 parses them correctly." @($encodingErrors.ToArray())
    }
    else {
        Add-Check "Windows PowerShell script encoding" "PASS" "Non-ASCII PowerShell scripts are UTF-8 with BOM for Windows PowerShell 5.1 compatibility."
    }
}
catch {
    Add-Check "Windows PowerShell script encoding" "FAIL" $_.Exception.Message
}

try {
    $parseErrors = New-Object 'System.Collections.Generic.List[string]'
    $psFiles = @(Get-ValidationFilesByExtension -Root $repoRoot -Filter "*.ps1")
    foreach ($file in $psFiles) {
        $parseError = Get-PowerShellParseError -Path $file.FullName -Root $repoRoot
        if (-not [string]::IsNullOrWhiteSpace($parseError)) {
            $parseErrors.Add($parseError)
        }
    }
    if ($parseErrors.Count -gt 0) {
        Add-Check "PowerShell parse" "FAIL" "One or more PowerShell scripts failed parser checks." @($parseErrors.ToArray())
    }
    else {
        Add-Check "PowerShell parse" "PASS" ("Parsed {0} PowerShell scripts." -f $psFiles.Count)
    }
}
catch {
    Add-Check "PowerShell parse" "FAIL" $_.Exception.Message
}

try {
    $jsonErrors = New-Object 'System.Collections.Generic.List[string]'
    $jsonFiles = @(Get-ValidationFilesByExtension -Root $repoRoot -Filter "*.json")
    foreach ($file in $jsonFiles) {
        try {
            Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null
        }
        catch {
            $jsonErrors.Add(("{0}: {1}" -f (ConvertTo-DisplayPath -Path $file.FullName -Root $repoRoot), $_.Exception.Message))
        }
    }
    if ($jsonErrors.Count -gt 0) {
        Add-Check "JSON parse" "FAIL" "One or more JSON files failed parse checks." @($jsonErrors.ToArray())
    }
    else {
        Add-Check "JSON parse" "PASS" ("Parsed {0} JSON files." -f $jsonFiles.Count)
    }
}
catch {
    Add-Check "JSON parse" "FAIL" $_.Exception.Message
}
}

if ($ValidationShard -ceq "PlatformNeutral") {
try {
    $gitFiles = @(Get-GitFiles)

    # Load shared sensitive scan contract (single source of truth)
    . (Join-Path $PSScriptRoot "sensitive-scan-contract.ps1")
    $highRiskPatterns = $SensitiveScanHighRiskPatterns
    $secretPattern = $SensitiveScanKeywordPattern
    $allowedSecretReferences = $SensitiveScanAllowedReferences
    $allowedSecretPaths = $SensitiveScanAllowedPaths

    $highRiskMatches = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $gitFiles) {
        foreach ($rule in $highRiskPatterns) {
            foreach ($match in @(Get-LineMatches -RelativePath $file -Pattern $rule.pattern)) {
                $highRiskMatches.Add([object][ordered]@{
                    rule = $rule.name
                    path = $match.path
                    line = $match.line
                    text = $match.text
                })
            }
        }
    }

    $keywordMatches = New-Object 'System.Collections.Generic.List[object]'
    $unexpectedKeywordMatches = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $gitFiles) {
        foreach ($match in @(Get-LineMatches -RelativePath $file -Pattern $secretPattern)) {
            $keywordMatches.Add([object]$match)
            $isExactAllowedReference = $allowedSecretReferences.ContainsKey($file) -and
                [string]$match.text -match $allowedSecretReferences[$file]
            if ($file -notin $allowedSecretPaths -and -not $isExactAllowedReference) {
                $unexpectedKeywordMatches.Add([object]$match)
            }
        }
    }

    $script:evidence.audit = [ordered]@{
        public_files_scanned = $gitFiles.Count
        high_risk_matches = @($highRiskMatches.ToArray())
        secret_keyword_matches = @($keywordMatches.ToArray())
        unexpected_secret_keyword_matches = @($unexpectedKeywordMatches.ToArray())
    }

    if ($highRiskMatches.Count -gt 0) {
        Add-Check "high-risk sensitive scan" "FAIL" "High-risk sensitive patterns were found." @($highRiskMatches.ToArray())
    }
    else {
        Add-Check "high-risk sensitive scan" "PASS" ("Scanned {0} tracked and untracked public files; no high-risk matches." -f $gitFiles.Count)
    }

    if ($unexpectedKeywordMatches.Count -gt 0) {
        Add-Check "secret keyword scan" "FAIL" "Secret-related keywords appeared outside expected public safety/documentation/audit-tooling files." @($unexpectedKeywordMatches.ToArray())
    }
    else {
        Add-Check "secret keyword scan" "PASS" ("Secret-related keyword matches were limited to expected public safety/documentation/audit-tooling files ({0} matches)." -f $keywordMatches.Count)
    }
}
catch {
    Add-Check "sensitive audit" "FAIL" $_.Exception.Message
}
}

}
