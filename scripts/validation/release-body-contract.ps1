# release-body-contract.ps1
# Validates the user-facing content between RELEASE_BODY markers.

$script:LegacyPublishedReleaseNotePaths = @(
    'docs/releases/v0.1.0.md',
    'docs/releases/v0.2.0.md',
    'docs/releases/v0.3.0.md',
    'docs/releases/v0.3.1.md',
    'docs/releases/v0.4.0.md',
    'docs/releases/v0.4.1.md',
    'docs/releases/v0.4.2.md',
    'docs/releases/v0.4.3.md',
    'docs/releases/v0.4.4.md',
    'docs/releases/v0.4.5.md',
    'docs/releases/v0.4.6.md',
    'docs/releases/v0.5.0.md',
    'docs/releases/v0.5.1.md',
    'docs/releases/v0.5.2.md',
    'docs/releases/v0.6.0.md'
)

function Get-ReleaseBodyContractResult {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text = "",
        [string]$SourceName = "<memory>"
    )

    $startMarker = '<!-- RELEASE_BODY_START -->'
    $endMarker = '<!-- RELEASE_BODY_END -->'
    $errors = New-Object 'System.Collections.Generic.List[object]'
    $startMatches = @([regex]::Matches($Text, [regex]::Escape($startMarker)))
    $endMatches = @([regex]::Matches($Text, [regex]::Escape($endMarker)))

    if ($startMatches.Count -ne 1) {
        $errors.Add([ordered]@{ code = "marker_start_count"; detail = "Expected exactly one RELEASE_BODY_START marker; found $($startMatches.Count)." })
    }
    if ($endMatches.Count -ne 1) {
        $errors.Add([ordered]@{ code = "marker_end_count"; detail = "Expected exactly one RELEASE_BODY_END marker; found $($endMatches.Count)." })
    }

    $body = ""
    if ($startMatches.Count -eq 1 -and $endMatches.Count -eq 1) {
        $bodyStart = $startMatches[0].Index + $startMatches[0].Length
        if ($bodyStart -ge $endMatches[0].Index) {
            $errors.Add([ordered]@{ code = "marker_order"; detail = "RELEASE_BODY_START must precede RELEASE_BODY_END." })
        }
        else {
            $body = $Text.Substring($bodyStart, $endMatches[0].Index - $bodyStart).Trim()
            if ([string]::IsNullOrWhiteSpace($body)) {
                $errors.Add([ordered]@{ code = "body_empty"; detail = "The user-facing release body is empty." })
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($body)) {
        $requiredSections = @(
            [ordered]@{ code = "audience_missing"; pattern = '(?im)^#{2,4}\s+(Who this release is for|Who should update)\s*$' },
            [ordered]@{ code = "upgrade_missing"; pattern = '(?im)^#{2,4}\s+(Required upgrade actions|Upgrade actions)\s*$' },
            [ordered]@{ code = "changes_missing"; pattern = '(?im)^#{2,4}\s+(What changed|Highlights|Main changes)\s*$' },
            [ordered]@{ code = "compatibility_missing"; pattern = '(?im)^#{2,4}\s+(Compatibility|Breaking and compatibility notes)\s*$' },
            [ordered]@{ code = "limitations_missing"; pattern = '(?im)^#{2,4}\s+Known limitations\s*$' },
            [ordered]@{ code = "rollback_missing"; pattern = '(?im)^#{2,4}\s+Rollback\s*$' },
            [ordered]@{ code = "boundary_missing"; pattern = '(?im)^#{2,4}\s+(Public boundary|Release boundary)\s*$' }
        )
        foreach ($section in $requiredSections) {
            if ($body -notmatch $section.pattern) {
                $errors.Add([ordered]@{ code = $section.code; detail = "Required user-facing section is missing." })
            }
        }

        $forbiddenRules = @(
            [ordered]@{ code = "issue_pr_mapping"; pattern = '(?im)(?:\b(?:Issue|PR)\s*#\d+\b|\b(?:Fixes|Closes|Refs)\s+#\d+\b|#\d+\s*(?:/|->)\s*#\d+|github\.com/[^\s)]+/(?:issues|pull)/\d+|^#{2,4}\s+Issue\s*/\s*PR mapping\s*$)' },
            [ordered]@{ code = "exact_validation_counts"; pattern = '(?i)(?:\b(?:PASS|FAIL|WARN|DEFERRED)\s*(?:=|:)\s*\d+\b|\b\d+(?:\s*/\s*\d+)?\s+(?:PASS|FAIL|WARN|DEFERRED)\b)' },
            [ordered]@{ code = "hosted_run_identity"; pattern = '(?i)(?:\b(?:hosted\s+)?(?:run(?:\s+ID)?|Actions run)\s*[:#]?\s*\d{6,}\b|/actions/runs/\d+)' },
            [ordered]@{ code = "hosted_platform_matrix"; pattern = '(?i)(?:\b(?:hosted|validation|platform)\s+matrix\b|\b(?:windows-latest|ubuntu-latest|macos-latest)\b|\bWindows\b[^\r\n]*\bUbuntu\b[^\r\n]*\bmacOS\b[^\r\n]*\bvalidation\b)' },
            [ordered]@{ code = "merge_instruction"; pattern = '(?i)(?:\bwaiting for (?:the )?merge\b|\bwait for (?:the )?merge\b|\bafter merg(?:e|ing)\b|\bMerge-to-publish\b|\u5408\u5e76\u540e|\u7b49\u5f85\u5408\u5e76)' },
            [ordered]@{ code = "tag_instruction"; pattern = '(?i)(?:\bcreate (?:the )?tag\b|\bpush (?:the )?tag\b|\btag target\s*:|\u521b\u5efa\s*(?:Git\s*)?(?:tag|\u6807\u7b7e))' },
            [ordered]@{ code = "publish_instruction"; pattern = '(?i)(?:\bpublish (?:the )?GitHub Release\b|\bready to publish\b|\bpublish-finalization\b|\u53d1\u5e03\s*(?:GitHub\s*)?Release)' },
            [ordered]@{ code = "maintainer_governance"; pattern = '(?i)(?:\bmaintainer authorization\b|\bmaintainer record\b|\bhosted checks?\b|\brelease status\s*:|\u7ef4\u62a4\u8005(?:\u8bb0\u5f55|\u5efa\u8bae|\u786e\u8ba4\u524d|\u5ba1\u6838\u524d))' },
            [ordered]@{ code = "candidate_governance"; pattern = '(?i)(?:\brelease candidate\b|\brelease-prep(?:\s+draft)?\b|\bdraft PR\b|\bno additional commits required\b|\u5019\u9009\u7248\u672c|\u53d1\u5e03\u5019\u9009|\u53d1\u5e03\u8349\u6848|\u65e0\u9700\u989d\u5916\u63d0\u4ea4)' }
        )
        foreach ($rule in $forbiddenRules) {
            $match = [regex]::Match($body, $rule.pattern)
            if ($match.Success) {
                $errors.Add([ordered]@{ code = $rule.code; detail = "Internal governance evidence is not allowed inside the release body markers."; match = $match.Value })
            }
        }
    }

    return [ordered]@{
        source = $SourceName
        mode = "strict-v1"
        passed = ($errors.Count -eq 0)
        body_length = $body.Length
        errors = @($errors.ToArray())
    }
}

function Get-ReleaseNoteContractMode {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = $RelativePath -replace '\\', '/'
    if ($normalized -eq 'docs/releases/template.md') {
        return "strict-v1"
    }
    if ($normalized -in $script:LegacyPublishedReleaseNotePaths) {
        return "legacy-published-through-v0.6.0"
    }
    return "strict-v1"
}

function Test-ReleaseNoteDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $mode = Get-ReleaseNoteContractMode -RelativePath $RelativePath
    if ($mode -eq "legacy-published-through-v0.6.0") {
        return [ordered]@{
            source = ($RelativePath -replace '\\', '/')
            mode = $mode
            passed = $true
            body_length = 0
            errors = @()
        }
    }
    return Get-ReleaseBodyContractResult -Text $Text -SourceName ($RelativePath -replace '\\', '/')
}
