# release-parser-safety-checks.ps1
# Extracted from scripts/validate-release.ps1 Invoke-ReleaseValidationParserSafetyChecks (Phase 2).
# Runs git diff, encoding, PowerShell/JSON parser, and public safety scan checks.
# Depends on: release-test-helper.ps1 (Add-Check, ConvertTo-DisplayPath, Get-GitFiles, Get-LineMatches,
#             Get-ValidationFilesByExtension, Test-BytesHaveUtf8Bom, Test-BytesHaveNonAscii,
#             Get-PowerShellParseError), path-guard.ps1 (Join-PathParts).
# Scope: script-level $repoRoot, $script:evidence, $checks.

# Invoke-ReleaseParserSafetyChecks: No parameters; runs git diff, encoding, PowerShell/JSON parser,
# and public safety scan checks in the original order.
function Invoke-ReleaseParserSafetyChecks {

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

try {
    $gitFiles = @(Get-GitFiles)
    $highRiskPatterns = @(
        [ordered]@{ name = "windows_user_path"; pattern = '(?i)\b[A-Z]:[\\/]+Users[\\/]+[^\\/ ]+' },
        [ordered]@{ name = "windows_projects_path"; pattern = '(?i)\b[A-Z]:[\\/]+Projects[\\/]+[^\\/ ]+' },
        [ordered]@{ name = "private_key_marker"; pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----' },
        [ordered]@{ name = "github_token"; pattern = '(?i)\b(ghp|github_pat)_[A-Za-z0-9_]{20,}\b' },
        [ordered]@{ name = "openai_key"; pattern = '(?i)\bsk-[A-Za-z0-9]{20,}\b' },
        [ordered]@{ name = "aws_access_key"; pattern = '\bAKIA[0-9A-Z]{16}\b' },
        [ordered]@{ name = "slack_token"; pattern = '(?i)\bxox[abprs]-[A-Za-z0-9-]{20,}\b' }
    )

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

    $secretPattern = '(?i)\b(secret|password|api[_ -]?key|credential|credentials|cookie|cookies|token|tokens|private key|private keys)\b'
    $allowedSecretPaths = @(
        "AGENTS.md",
        ".agents/AGENTS.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "docs/agent-governance.md",
        "docs/release-readiness.md",
        "docs/release-process.md",
        "docs/roadmap/evolution-plan.md",
        "docs/roadmap/release-validator-thin-entrypoint-plan.md",
        "knowledge-hub/templates/languages/en/project-root/AGENTS.md",
        "knowledge-hub/templates/languages/en/project-agent/AGENTS.md",
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root/AGENTS.md",
        "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent/AGENTS.md",
        "skills/project-bootstrap/scripts/set_project_language.ps1",
        "skills/project-context-gate/SKILL.md",
        "scripts/validation/release-repository-checks.ps1",
        "scripts/validation/release-parser-safety-checks.ps1",
        "scripts/validation/release-documentation-checks.ps1",
        "scripts/validation/release-knowledge-hub-checks.ps1",
        "scripts/validation/release-runtime-smoke-checks.ps1",
        "scripts/validation/release-bootstrap-checks.ps1",
        "scripts/validation/release-project-template-checks.ps1",
        "scripts/validation/release-template-language-checks.ps1",
        "knowledge-hub/knowledge/patterns/examples/issue-decomposition-positive-fixture.md",
        "scripts/validate-release.ps1"
    )
    $keywordMatches = New-Object 'System.Collections.Generic.List[object]'
    $unexpectedKeywordMatches = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $gitFiles) {
        foreach ($match in @(Get-LineMatches -RelativePath $file -Pattern $secretPattern)) {
            $keywordMatches.Add([object]$match)
            if ($file -notin $allowedSecretPaths) {
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
