# release-knowledge-candidate-checks.ps1
# Isolated fixture coverage for the local runtime candidate inbox contract.
# Depends on release-test-helper.ps1 and path-guard.ps1 through validate-release.ps1.

function Invoke-ReleaseKnowledgeCandidateChecks {
    try {
        $fixtureRoot = Join-PathParts $scratchRootFull "knowledge-candidate-intake"
        if (Test-Path -LiteralPath $fixtureRoot) {
            [System.IO.Directory]::Delete($fixtureRoot, $true)
        }
        [System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
        $utf8 = New-Object System.Text.UTF8Encoding($false)

        function Write-FixtureText {
            param([string]$Path, [string]$Text)
            $parent = [System.IO.Path]::GetDirectoryName($Path)
            [System.IO.Directory]::CreateDirectory($parent) | Out-Null
            [System.IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), $utf8)
        }

        function Get-TreeDigest {
            param([string]$Root)
            if (-not (Test-Path -LiteralPath $Root)) {
                return "missing"
            }
            $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
            $lines = @(
                Get-ChildItem -LiteralPath $rootFull -File -Recurse -Force |
                    Sort-Object FullName |
                    ForEach-Object {
                        $relative = $_.FullName.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
                        "{0}|{1}" -f $relative, ((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
                    }
            )
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $bytes = $utf8.GetBytes(($lines -join "`n"))
                return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
            }
            finally {
                $sha.Dispose()
            }
        }

        function Get-CandidateMetadata {
            param([string]$Path)
            $text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false, $true)))
            $match = [regex]::Match($text, '(?s)\A---\r?\n(?<json>.*?)\r?\n---\r?\n')
            if (-not $match.Success) {
                throw "Fixture candidate is missing JSON front matter: $Path"
            }
            return ($match.Groups['json'].Value | ConvertFrom-Json)
        }

        function Invoke-ExpectedCandidateFailure {
            param(
                [string]$Script,
                [string]$Inbox,
                [string]$Root,
                [string]$LanguageValue,
                [string]$ExpectedPattern
            )
            $failed = $false
            $message = ""
            try {
                & $Script -Mode Intake -InboxDir $Inbox -ProjectRoot $Root -Language $LanguageValue -ObservedOn "2026-07-10" 2>&1 | Out-Null
            }
            catch {
                $failed = $true
                $message = $_.Exception.Message
            }
            if (-not $failed -or $message -notmatch $ExpectedPattern) {
                throw "Expected candidate failure '$ExpectedPattern', got: $message"
            }
        }

        function Invoke-CandidateHost {
            param(
                [string]$Executable,
                [string]$Script,
                [string]$Inbox,
                [string]$Root
            )
            $arguments = @(
                "-NoProfile"
                "-ExecutionPolicy"
                "Bypass"
                "-File"
                $Script
                "-Mode"
                "Intake"
                "-InboxDir"
                $Inbox
                "-ProjectRoot"
                $Root
                "-Language"
                "en"
                "-ObservedOn"
                "2026-07-10"
            )
            $output = @(& $Executable @arguments 2>&1 | ForEach-Object { [string]$_ })
            if ($LASTEXITCODE -ne 0) {
                throw "Candidate host fixture failed under ${Executable}: $($output -join '; ')"
            }
        }

        $candidateScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "manage_candidates.ps1"
        $runtimeRoot = Join-PathParts $fixtureRoot "runtime"
        $runtimeState = Join-PathParts $runtimeRoot "state"
        $inbox = Join-PathParts $runtimeState "knowledge-candidates"
        $experienceHub = Join-PathParts $runtimeRoot "knowledge-hub" "knowledge" "experience"
        [System.IO.Directory]::CreateDirectory($runtimeState) | Out-Null
        [System.IO.Directory]::CreateDirectory($experienceHub) | Out-Null
        $hubSentinel = Join-Path $experienceHub "sentinel.md"
        Write-FixtureText -Path $hubSentinel -Text "formal experience hub must remain unchanged"
        $hubHashBefore = Get-TreeDigest -Root $experienceHub

        $projectEn = Join-PathParts $fixtureRoot "project-en"
        $projectZh = Join-PathParts $fixtureRoot "project-zh"
        $enExperience = Join-PathParts $projectEn ".agents" "context" "experience"
        $zhExperience = Join-PathParts $projectZh ".agents" "context" "experience"

        $candidateA = @"
# PowerShell deterministic intake

## Summary

Use a complete preflight before committing a candidate inbox transaction.

## Keywords

- PowerShell
- candidate intake

Global candidate: Yes

## Prevention Rule

SOURCE-BODY-ONLY-SENTINEL raw transcript must never be copied.
"@
        $candidateADuplicate = $candidateA + "`nReproduced independently in a second fixture file.`n"
        $candidateB = @"
# Reject unsafe partial writes

## Summary

Reject malformed candidate metadata before any inbox file changes.

## Keywords

- atomic commit
- fail-fast

Scope: Cross-project reusable
"@
        $candidateC = @"
# Keep project roots read only

## Summary

Candidate discovery must not modify explicitly supplied project roots.

## Keywords

- read-only discovery
- project memory

Global candidate: Yes
"@
        $candidateD = @"
# 中文候选保留源语言

## Summary

候选正文可以使用中文，但机器解析仍保留 English anchors。

## Keywords

- 中文经验
- English anchors

Global candidate: Yes
"@
        $candidateE = @"
# 人工复核后再晋升

## Summary

候选进入收件箱不等于正式全局经验，晋升必须由人工明确决定。

## Keywords

- triage
- explicit promotion

Scope: Cross-project reusable
"@
        $notCandidate = @"
# Project-local only

## Summary

This entry is intentionally project-local.

## Keywords

- local only

Global candidate: No
"@

        Write-FixtureText -Path (Join-Path $enExperience "a.md") -Text $candidateA
        Write-FixtureText -Path (Join-Path $enExperience "a-reproduced.md") -Text $candidateADuplicate
        Write-FixtureText -Path (Join-Path $enExperience "b.md") -Text $candidateB
        Write-FixtureText -Path (Join-Path $enExperience "c.md") -Text $candidateC
        Write-FixtureText -Path (Join-Path $enExperience "local.md") -Text $notCandidate
        Write-FixtureText -Path (Join-Path $zhExperience "d.md") -Text $candidateD
        Write-FixtureText -Path (Join-Path $zhExperience "e.md") -Text $candidateE

        $projectEnHashBefore = Get-TreeDigest -Root $projectEn
        $projectZhHashBefore = Get-TreeDigest -Root $projectZh

        $discoverJson = & $candidateScript -Mode Discover -ProjectRoot @($projectEn, $projectZh) -Language @("en", "zh-CN") -ObservedOn "2026-07-10" -Json
        $discover = $discoverJson | ConvertFrom-Json
        if ([int]$discover.count -ne 5) {
            throw "Expected five merged discovery candidates, got $($discover.count)."
        }
        if (@($discover.candidates | Where-Object { [string]$_.language -eq "en" }).Count -ne 3 -or @($discover.candidates | Where-Object { [string]$_.language -eq "zh-CN" }).Count -ne 2) {
            throw "Localized discovery did not preserve explicitly supplied languages."
        }
        if (@($discover.candidates | Where-Object { [string]$_.title -eq "Project-local only" }).Count -ne 0) {
            throw "Unmarked project-local experience was discovered unexpectedly."
        }
        $duplicateDiscovery = @($discover.candidates | Where-Object { [string]$_.title -eq "PowerShell deterministic intake" })
        if ($duplicateDiscovery.Count -ne 1 -or [int]$duplicateDiscovery[0].occurrence_count -ne 2) {
            throw "Duplicate discovery did not merge occurrence metadata."
        }

        $intakeOutput = @(& $candidateScript -Mode Intake -InboxDir $inbox -ProjectRoot @($projectEn, $projectZh) -Language @("en", "zh-CN") -ObservedOn "2026-07-10")
        $files = @(Get-ChildItem -LiteralPath $inbox -File -Filter "*.md" | Sort-Object Name)
        if ($files.Count -ne 5) {
            throw "Expected five inbox files, got $($files.Count)."
        }
        foreach ($file in $files) {
            if ($file.Name -notmatch '^2026-07-10-.+-[0-9a-f]{12}\.md$') {
                throw "Candidate filename is not deterministic: $($file.Name)"
            }
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            if (Test-BytesHaveUtf8Bom -Bytes $bytes) {
                throw "Candidate file must use UTF-8 without BOM: $($file.Name)"
            }
        }
        $metadata = @($files | ForEach-Object { Get-CandidateMetadata -Path $_.FullName })
        $candidateAInbox = @($metadata | Where-Object { [string]$_.title -eq "PowerShell deterministic intake" })[0]
        if ([int]$candidateAInbox.occurrence_count -ne 2 -or @($candidateAInbox._local.sources).Count -ne 2) {
            throw "Intake did not preserve merged local occurrence metadata."
        }
        if ([string]::IsNullOrWhiteSpace([string]$candidateAInbox.dedupe_key) -or [string]::IsNullOrWhiteSpace([string]$candidateAInbox.normalized_summary_hash)) {
            throw "Candidate dedupe metadata is incomplete."
        }
        if ($projectEnHashBefore -ne (Get-TreeDigest -Root $projectEn) -or $projectZhHashBefore -ne (Get-TreeDigest -Root $projectZh)) {
            throw "Project roots changed during successful discovery/intake."
        }
        if ($hubHashBefore -ne (Get-TreeDigest -Root $experienceHub)) {
            throw "Candidate intake wrote to the formal experience hub."
        }

        $inboxHashBeforeRerun = Get-TreeDigest -Root $inbox
        & $candidateScript -Mode Intake -InboxDir $inbox -ProjectRoot @($projectEn, $projectZh) -Language @("en", "zh-CN") -ObservedOn "2026-07-10" | Out-Null
        $inboxHashAfterRerun = Get-TreeDigest -Root $inbox
        if ($inboxHashBeforeRerun -ne $inboxHashAfterRerun) {
            throw "Candidate intake rerun was not byte-idempotent."
        }

        $firstFile = $files[0].FullName
        $firstOriginalBytes = [System.IO.File]::ReadAllBytes($firstFile)
        $failureCases = @(
            [ordered]@{ name = "schema"; find = '"schema_version":1'; replace = '"schema_version":2'; pattern = 'schema_version' },
            [ordered]@{ name = "status"; find = '"status":"pending_review"'; replace = '"status":"invalid"'; pattern = 'status' },
            [ordered]@{ name = "dedupe"; find = '"normalized_title":'; replace = '"normalized_title": "conflict", "original_normalized_title":'; pattern = 'normalized_title|front matter' }
        )
        foreach ($case in $failureCases) {
            [System.IO.File]::WriteAllBytes($firstFile, $firstOriginalBytes)
            $text = [System.IO.File]::ReadAllText($firstFile, $utf8)
            if ($text -notlike ("*{0}*" -f $case.find)) {
                throw "Fixture could not prepare $($case.name) malformed candidate."
            }
            Write-FixtureText -Path $firstFile -Text ($text.Replace([string]$case.find, [string]$case.replace))
            $malformedInboxHash = Get-TreeDigest -Root $inbox
            Invoke-ExpectedCandidateFailure -Script $candidateScript -Inbox $inbox -Root $projectEn -LanguageValue "en" -ExpectedPattern ([string]$case.pattern)
            if ($malformedInboxHash -ne (Get-TreeDigest -Root $inbox)) {
                throw "Malformed $($case.name) preflight left a partial inbox update."
            }
            if ($projectEnHashBefore -ne (Get-TreeDigest -Root $projectEn)) {
                throw "Project root changed during failed $($case.name) preflight."
            }
        }
        [System.IO.File]::WriteAllBytes($firstFile, $firstOriginalBytes)

        $duplicateName = "2026-07-09-" + ([System.IO.Path]::GetFileName($firstFile).Substring(11))
        $duplicatePath = Join-Path $inbox $duplicateName
        $duplicateText = [System.IO.File]::ReadAllText($firstFile, $utf8).Replace('"first_seen_on":"2026-07-10"', '"first_seen_on":"2026-07-09"')
        Write-FixtureText -Path $duplicatePath -Text $duplicateText
        $duplicateInboxHash = Get-TreeDigest -Root $inbox
        Invoke-ExpectedCandidateFailure -Script $candidateScript -Inbox $inbox -Root $projectEn -LanguageValue "en" -ExpectedPattern "Duplicate candidate_id"
        if ($duplicateInboxHash -ne (Get-TreeDigest -Root $inbox)) {
            throw "Duplicate candidate ID preflight left a partial inbox update."
        }
        [System.IO.File]::Delete($duplicatePath)

        $metadata = @((Get-ChildItem -LiteralPath $inbox -File -Filter "*.md") | ForEach-Object { Get-CandidateMetadata -Path $_.FullName })
        $byTitle = @{}
        foreach ($item in $metadata) { $byTitle[[string]$item.title] = [string]$item.candidate_id }
        & $candidateScript -Mode Triage -InboxDir $inbox -CandidateId $byTitle["PowerShell deterministic intake"] -Status accepted -ReviewedBy "fixture-reviewer" -ReviewNote "local path X:\fixture\review raw logs transcript private repository mapping LOCAL-ACCESS-MATERIAL-SENTINEL" -ObservedOn "2026-07-10" | Out-Null
        & $candidateScript -Mode Triage -InboxDir $inbox -CandidateId $byTitle["Reject unsafe partial writes"] -Status rejected -ReviewedBy "fixture-reviewer" -ObservedOn "2026-07-10" | Out-Null
        & $candidateScript -Mode Triage -InboxDir $inbox -CandidateId $byTitle["Keep project roots read only"] -Status superseded -SupersededBy $byTitle["PowerShell deterministic intake"] -ReviewedBy "fixture-reviewer" -ObservedOn "2026-07-10" | Out-Null
        & $candidateScript -Mode Triage -InboxDir $inbox -CandidateId $byTitle["PowerShell deterministic intake"] -Status accepted -MergeCandidateId $byTitle["人工复核后再晋升"] -ReviewedBy "fixture-reviewer" -ObservedOn "2026-07-10" | Out-Null

        $listJson = (& $candidateScript -Mode List -InboxDir $inbox -Json) | ConvertFrom-Json
        $statuses = @($listJson.candidates | ForEach-Object { [string]$_.status } | Sort-Object -Unique)
        foreach ($expectedStatus in @("pending_review", "accepted", "rejected", "superseded")) {
            if ($statuses -notcontains $expectedStatus) {
                throw "Candidate status allowlist fixture is missing: $expectedStatus"
            }
        }
        $accepted = @($listJson.candidates | Where-Object { [string]$_.candidate_id -eq $byTitle["PowerShell deterministic intake"] })[0]
        if (@($accepted.merged_from) -notcontains $byTitle["人工复核后再晋升"]) {
            throw "Candidate merge relationship was not recorded."
        }

        $publicJsonText = @(& $candidateScript -Mode Export -InboxDir $inbox -Json) -join "`n"
        $publicHumanText = @(& $candidateScript -Mode Export -InboxDir $inbox) -join "`n"
        $publicJson = $publicJsonText | ConvertFrom-Json
        if ([int]$publicJson.count -ne 5) {
            throw "Public JSON export count is incorrect."
        }
        $forbiddenExport = @(
            [regex]::Escape($projectEn),
            [regex]::Escape($projectZh),
            '"_local"',
            'source_file',
            'SOURCE-BODY-ONLY-SENTINEL',
            'raw logs',
            'transcript',
            'private repository mapping',
            'LOCAL-ACCESS-MATERIAL-SENTINEL',
            '## Summary',
            '## Keywords'
        )
        foreach ($pattern in $forbiddenExport) {
            if ($publicJsonText -match $pattern -or $publicHumanText -match $pattern) {
                throw "Public candidate export leaked forbidden content matching: $pattern"
            }
        }
        $postTriageMetadata = @((Get-ChildItem -LiteralPath $inbox -File -Filter "*.md") | ForEach-Object { Get-CandidateMetadata -Path $_.FullName })
        $localReview = @($postTriageMetadata | Where-Object { [string]$_.candidate_id -eq $byTitle["PowerShell deterministic intake"] })[0]._local.reviews
        if (@($localReview).Count -lt 1 -or (@($localReview | ConvertTo-Json -Depth 8) -join "`n") -notmatch 'LOCAL-ACCESS-MATERIAL-SENTINEL') {
            throw "Inbox did not retain local-only review metadata."
        }

        $crossHostCompared = $false
        $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
        $windowsPowerShellCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
        if ($null -ne $pwshCommand -and $null -ne $windowsPowerShellCommand) {
            $hostProject = Join-PathParts $fixtureRoot "host-project"
            $hostExperience = Join-PathParts $hostProject ".agents" "context" "experience"
            Write-FixtureText -Path (Join-Path $hostExperience "candidate.md") -Text $candidateA
            $hostRuntimePwsh = Join-PathParts $fixtureRoot "host-runtime-pwsh" "state"
            $hostRuntimeWinPs = Join-PathParts $fixtureRoot "host-runtime-winps" "state"
            [System.IO.Directory]::CreateDirectory($hostRuntimePwsh) | Out-Null
            [System.IO.Directory]::CreateDirectory($hostRuntimeWinPs) | Out-Null
            $hostInboxPwsh = Join-Path $hostRuntimePwsh "knowledge-candidates"
            $hostInboxWinPs = Join-Path $hostRuntimeWinPs "knowledge-candidates"
            Invoke-CandidateHost -Executable $pwshCommand.Source -Script $candidateScript -Inbox $hostInboxPwsh -Root $hostProject
            Invoke-CandidateHost -Executable $windowsPowerShellCommand.Source -Script $candidateScript -Inbox $hostInboxWinPs -Root $hostProject
            if ((Get-TreeDigest -Root $hostInboxPwsh) -ne (Get-TreeDigest -Root $hostInboxWinPs)) {
                throw "PowerShell 7 and Windows PowerShell 5.1 produced different candidate inbox bytes."
            }
            $crossHostCompared = $true
        }

        if ($projectEnHashBefore -ne (Get-TreeDigest -Root $projectEn) -or $projectZhHashBefore -ne (Get-TreeDigest -Root $projectZh)) {
            throw "Project roots changed after triage/export validation."
        }
        if ($hubHashBefore -ne (Get-TreeDigest -Root $experienceHub)) {
            throw "Candidate workflow mutated the formal experience hub."
        }

        $script:evidence.knowledge_candidate_intake = [ordered]@{
            discovered_candidates = [int]$discover.count
            inbox_files = $files.Count
            duplicate_occurrences = [int]$candidateAInbox.occurrence_count
            statuses = @($statuses)
            deterministic_rerun = ($inboxHashBeforeRerun -eq $inboxHashAfterRerun)
            project_roots_read_only = $true
            malformed_preflight_zero_partial_write = $true
            duplicate_id_fail_fast = $true
            public_export_redacted = $true
            formal_experience_hub_unchanged = $true
            cross_host_bytes_compared = $crossHostCompared
            intake_output = @($intakeOutput)
        }
        Add-Check "knowledge candidate intake" "PASS" "Isolated candidate discovery, intake, triage, redacted export, atomic preflight, idempotence, and runtime boundary fixtures passed." $script:evidence.knowledge_candidate_intake
    }
    catch {
        Add-Check "knowledge candidate intake" "FAIL" $_.Exception.Message
    }
}
