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
                Get-ChildItem -LiteralPath $rootFull -Recurse -Force |
                    Sort-Object FullName |
                    ForEach-Object {
                        $relative = $_.FullName.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
                        if ($_.PSIsContainer) {
                            "D|{0}" -f $relative
                        }
                        else {
                            "F|{0}|{1}" -f $relative, ((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
                        }
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
                [string]$ExpectedPattern,
                [string[]]$ForbiddenText = @()
            )
            Invoke-ExpectedCandidateCommandFailure -Script $Script -Parameters @{
                Mode = "Intake"
                InboxDir = $Inbox
                ProjectRoot = $Root
                Language = $LanguageValue
                ObservedOn = "2026-07-10"
            } -ExpectedPattern $ExpectedPattern -ForbiddenText $ForbiddenText
        }

        function Invoke-ExpectedCandidateCommandFailure {
            param(
                [string]$Script,
                [hashtable]$Parameters,
                [string]$ExpectedPattern,
                [string[]]$ForbiddenText = @()
            )
            $failed = $false
            $message = ""
            $output = @()
            try {
                $output = @(& $Script @Parameters 2>&1 | ForEach-Object { [string]$_ })
            }
            catch {
                $failed = $true
                $message = $_.Exception.Message
            }
            $combined = (@($output) + @($message)) -join "`n"
            foreach ($forbidden in $ForbiddenText) {
                if (-not [string]::IsNullOrWhiteSpace($forbidden) -and $combined.Contains($forbidden)) {
                    throw "Candidate failure output leaked rejected public-safe content."
                }
            }
            if (-not $failed -or $message -notmatch $ExpectedPattern) {
                throw "Candidate command expected sanitized category '$ExpectedPattern' but observed: $message"
            }
        }

        function Update-CandidateMetadata {
            param(
                [string]$Path,
                [scriptblock]$Update
            )
            $text = [System.IO.File]::ReadAllText($Path, $utf8)
            $match = [regex]::Match($text, '(?s)\A---\r?\n(?<json>.*?)\r?\n---\r?\n(?<body>.*)\z')
            if (-not $match.Success) {
                throw "Fixture candidate is missing canonical front matter."
            }
            $metadata = $match.Groups['json'].Value | ConvertFrom-Json
            & $Update $metadata
            $json = $metadata | ConvertTo-Json -Depth 12 -Compress
            Write-FixtureText -Path $Path -Text ("---`n{0}`n---`n{1}" -f $json, $match.Groups['body'].Value)
        }

        function Get-CandidatePathById {
            param([string]$Inbox, [string]$Id)
            foreach ($file in @(Get-ChildItem -LiteralPath $Inbox -File -Filter "*.md")) {
                $metadata = Get-CandidateMetadata -Path $file.FullName
                if ([string]$metadata.candidate_id -eq $Id) {
                    return $file.FullName
                }
            }
            throw "Fixture candidate ID was not found."
        }

        function Copy-FixtureInbox {
            param([string]$Source, [string]$Destination)
            [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Destination)) | Out-Null
            Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
        }

        function Assert-NoTransactionArtifacts {
            param([string]$Parent, [string]$InboxLeaf)
            if (Test-Path -LiteralPath (Join-Path $Parent $InboxLeaf)) {
                throw "Failed preflight created the final inbox."
            }
            foreach ($entry in @(Get-ChildItem -LiteralPath $Parent -Force -ErrorAction SilentlyContinue)) {
                if ($entry.Name -like ".$InboxLeaf.stage.*" -or $entry.Name -like ".$InboxLeaf.backup.*") {
                    throw "Failed preflight left a transaction artifact."
                }
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

        $projectState = Join-Path $projectEn "state"
        [System.IO.Directory]::CreateDirectory($projectState) | Out-Null
        $projectEnHashBeforeAliasChecks = Get-TreeDigest -Root $projectEn

        $projectAlias = Join-Path $fixtureRoot "project-alias"
        if ($env:OS -eq "Windows_NT") {
            New-Item -ItemType Junction -Path $projectAlias -Target $projectEn -Force | Out-Null
        }
        else {
            New-Item -ItemType SymbolicLink -Path $projectAlias -Target ([System.IO.Path]::GetFileName($projectEn)) -Force | Out-Null
        }
        Invoke-ExpectedCandidateFailure -Script $candidateScript -Inbox (Join-PathParts $projectAlias "state" "knowledge-candidates") -Root $projectEn -LanguageValue "en" -ExpectedPattern "physically overlap"
        if ($projectEnHashBeforeAliasChecks -ne (Get-TreeDigest -Root $projectEn)) {
            throw "Physical-overlap preflight changed the project tree."
        }
        Assert-NoTransactionArtifacts -Parent $projectState -InboxLeaf "knowledge-candidates"

        $multiAliasB = Join-Path $fixtureRoot "project-alias-b"
        $multiAliasA = Join-Path $fixtureRoot "project-alias-a"
        if ($env:OS -eq "Windows_NT") {
            New-Item -ItemType Junction -Path $multiAliasB -Target $projectEn -Force | Out-Null
            New-Item -ItemType Junction -Path $multiAliasA -Target $multiAliasB -Force | Out-Null
        }
        else {
            New-Item -ItemType SymbolicLink -Path $multiAliasB -Target ([System.IO.Path]::GetFileName($projectEn)) -Force | Out-Null
            New-Item -ItemType SymbolicLink -Path $multiAliasA -Target ([System.IO.Path]::GetFileName($multiAliasB)) -Force | Out-Null
        }
        Invoke-ExpectedCandidateFailure -Script $candidateScript -Inbox (Join-PathParts $multiAliasA "state" "knowledge-candidates") -Root $projectEn -LanguageValue "en" -ExpectedPattern "physically overlap"
        if ($projectEnHashBeforeAliasChecks -ne (Get-TreeDigest -Root $projectEn)) {
            throw "Multi-alias overlap preflight changed the project tree."
        }
        Assert-NoTransactionArtifacts -Parent $projectState -InboxLeaf "knowledge-candidates"

        $safeRuntime = Join-Path $fixtureRoot "safe-runtime-target"
        $safeRuntimeState = Join-Path $safeRuntime "state"
        [System.IO.Directory]::CreateDirectory($safeRuntimeState) | Out-Null
        $safeAlias = Join-Path $fixtureRoot "safe-runtime-alias"
        if ($env:OS -eq "Windows_NT") {
            New-Item -ItemType Junction -Path $safeAlias -Target $safeRuntime -Force | Out-Null
        }
        else {
            New-Item -ItemType SymbolicLink -Path $safeAlias -Target ([System.IO.Path]::GetFileName($safeRuntime)) -Force | Out-Null
        }
        $safePhysicalInbox = Join-Path $safeRuntimeState "knowledge-candidates"
        & $candidateScript -Mode Intake -InboxDir (Join-PathParts $safeAlias "state" "knowledge-candidates") -ProjectRoot $projectEn -Language "en" -ObservedOn "2026-07-10" | Out-Null
        if (@(Get-ChildItem -LiteralPath $safePhysicalInbox -File -Filter "*.md").Count -ne 3) {
            throw "Safe runtime alias did not write only to its canonical external target."
        }
        foreach ($entry in @(Get-ChildItem -LiteralPath $safeRuntimeState -Force)) {
            if ($entry.Name -like ".knowledge-candidates.stage.*" -or $entry.Name -like ".knowledge-candidates.backup.*") {
                throw "Safe runtime alias left a transaction artifact."
            }
        }

        $brokenAlias = Join-Path $fixtureRoot "broken-runtime-alias"
        if ($env:OS -eq "Windows_NT") {
            $brokenTarget = Join-Path $fixtureRoot "missing-runtime-target"
            & cmd.exe /d /c ('mklink /D "{0}" "{1}"' -f $brokenAlias, $brokenTarget) | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Fixture could not create a broken Windows symbolic link."
            }
        }
        else {
            New-Item -ItemType SymbolicLink -Path $brokenAlias -Target "missing-runtime-target" -Force | Out-Null
        }
        Invoke-ExpectedCandidateFailure -Script $candidateScript -Inbox (Join-PathParts $brokenAlias "state" "knowledge-candidates") -Root $projectEn -LanguageValue "en" -ExpectedPattern "broken symbolic link|missing required target"

        $cycleAliasA = Join-Path $fixtureRoot "cycle-runtime-a"
        $cycleAliasB = Join-Path $fixtureRoot "cycle-runtime-b"
        if ($env:OS -eq "Windows_NT") {
            & cmd.exe /d /c ('mklink /D "{0}" "{1}"' -f $cycleAliasA, $cycleAliasB) | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Fixture could not create the first Windows cycle link."
            }
            & cmd.exe /d /c ('mklink /D "{0}" "{1}"' -f $cycleAliasB, $cycleAliasA) | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Fixture could not create the second Windows cycle link."
            }
        }
        else {
            New-Item -ItemType SymbolicLink -Path $cycleAliasA -Target ([System.IO.Path]::GetFileName($cycleAliasB)) -Force | Out-Null
            New-Item -ItemType SymbolicLink -Path $cycleAliasB -Target ([System.IO.Path]::GetFileName($cycleAliasA)) -Force | Out-Null
        }
        Invoke-ExpectedCandidateFailure -Script $candidateScript -Inbox (Join-PathParts $cycleAliasA "state" "knowledge-candidates") -Root $projectEn -LanguageValue "en" -ExpectedPattern "cycle"
        if ($projectEnHashBeforeAliasChecks -ne (Get-TreeDigest -Root $projectEn)) {
            throw "Broken/cyclic alias preflight changed the project tree."
        }
        Assert-NoTransactionArtifacts -Parent $projectState -InboxLeaf "knowledge-candidates"

        $unsafeSummaryCases = @(
            [ordered]@{ name = "windows-path"; value = ('prefix=C:' + '\Users\fixture\private.txt'); rule = "absolute path" },
            [ordered]@{ name = "unc-path"; value = ('prefix=\\' + 'fixture-server\private-share\file.txt'); rule = "absolute path" },
            [ordered]@{ name = "unix-path"; value = 'prefix=/home/fixture/private.txt'; rule = "absolute path" },
            [ordered]@{ name = "macos-path"; value = 'prefix=/Users/fixture/private.txt'; rule = "absolute path" },
            [ordered]@{ name = "github-token"; value = ('ghp' + '_FAKEFIXTURE1234567890'); rule = "GitHub token" },
            [ordered]@{ name = "github-pat"; value = ('github' + '_pat_FAKE_FIXTURE_1234567890'); rule = "GitHub token" },
            [ordered]@{ name = "openai-key"; value = ('sk' + '-FAKEFIXTURE1234567890'); rule = "OpenAI key" },
            [ordered]@{ name = "aws-key"; value = ('AK' + 'IAFAKEFIXTURE123456'); rule = "AWS access key" },
            [ordered]@{ name = "slack-token"; value = ('xoxb' + '-FAKE-FIXTURE-1234567890'); rule = "Slack token" },
            [ordered]@{ name = "private-key"; value = ('-----BEGIN ' + 'PRIVATE KEY-----'); rule = "private key" },
            [ordered]@{ name = "authorization"; value = 'Authorization: Bearer FAKE-FIXTURE-1234567890'; rule = "authorization header" },
            [ordered]@{ name = "cookie"; value = 'cookie=FAKE-FIXTURE-1234567890'; rule = "secret assignment" },
            [ordered]@{ name = "credential"; value = 'credential=FAKE-FIXTURE-1234567890'; rule = "secret assignment" },
            [ordered]@{ name = "password"; value = 'password=FAKE-FIXTURE-1234567890'; rule = "secret assignment" },
            [ordered]@{ name = "api-key"; value = 'api_key=FAKE-FIXTURE-1234567890'; rule = "secret assignment" },
            [ordered]@{ name = "secret"; value = 'secret=FAKE-FIXTURE-1234567890'; rule = "secret assignment" },
            [ordered]@{ name = "token-assignment"; value = 'token=FAKE-FIXTURE-1234567890'; rule = "secret assignment" },
            [ordered]@{ name = "raw-log"; value = 'raw log sentinel: FAKE-RAW-EVIDENCE-1234567890'; rule = "raw evidence" },
            [ordered]@{ name = "transcript"; value = 'transcript: FAKE-TRANSCRIPT-1234567890'; rule = "raw evidence" },
            [ordered]@{ name = "stack-trace"; value = 'stack trace: FAKE-STACK-EVIDENCE-1234567890'; rule = "raw evidence" },
            [ordered]@{ name = "command-output"; value = 'command output: FAKE-COMMAND-EVIDENCE-1234567890'; rule = "raw evidence" },
            [ordered]@{ name = "private-mapping"; value = 'private repository mapping: FAKE-PRIVATE-MAPPING-1234567890'; rule = "private repository mapping" },
            [ordered]@{ name = "access-material"; value = 'access material: FAKE-ACCESS-MATERIAL-1234567890'; rule = "private repository mapping" }
        )
        foreach ($unsafeCase in $unsafeSummaryCases) {
            $unsafeProject = Join-Path $fixtureRoot ("unsafe-project-" + $unsafeCase.name)
            $unsafeExperience = Join-PathParts $unsafeProject ".agents" "context" "experience"
            $unsafeCandidate = "# Unsafe summary fixture`n`n## Summary`n`n$($unsafeCase.value)`n`n## Keywords`n`n- safe fixture`n`nGlobal candidate: Yes`n"
            Write-FixtureText -Path (Join-Path $unsafeExperience "candidate.md") -Text $unsafeCandidate
            $unsafeProjectHash = Get-TreeDigest -Root $unsafeProject
            $unsafeState = Join-PathParts $fixtureRoot ("unsafe-runtime-" + $unsafeCase.name) "state"
            [System.IO.Directory]::CreateDirectory($unsafeState) | Out-Null
            $unsafeInbox = Join-Path $unsafeState "knowledge-candidates"
            Invoke-ExpectedCandidateFailure -Script $candidateScript -Inbox $unsafeInbox -Root $unsafeProject -LanguageValue "en" -ExpectedPattern ([regex]::Escape([string]$unsafeCase.rule)) -ForbiddenText @([string]$unsafeCase.value)
            if ($unsafeProjectHash -ne (Get-TreeDigest -Root $unsafeProject)) {
                throw "Rejected public-safe summary changed its project root."
            }
            Assert-NoTransactionArtifacts -Parent $unsafeState -InboxLeaf "knowledge-candidates"
        }
        $unsafePublicFieldCases = @(
            [ordered]@{ name = "title"; title = "token=FAKE-TITLE-1234567890"; keyword = "safe fixture"; field = "title" },
            [ordered]@{ name = "keywords"; title = "Safe title fixture"; keyword = "secret=FAKE-KEYWORD-1234567890"; field = "keywords" }
        )
        foreach ($unsafeFieldCase in $unsafePublicFieldCases) {
            $unsafeProject = Join-Path $fixtureRoot ("unsafe-field-project-" + $unsafeFieldCase.name)
            $unsafeExperience = Join-PathParts $unsafeProject ".agents" "context" "experience"
            $unsafeCandidate = "# $($unsafeFieldCase.title)`n`n## Summary`n`nA normal public-safe summary.`n`n## Keywords`n`n- $($unsafeFieldCase.keyword)`n`nGlobal candidate: Yes`n"
            Write-FixtureText -Path (Join-Path $unsafeExperience "candidate.md") -Text $unsafeCandidate
            $unsafeState = Join-PathParts $fixtureRoot ("unsafe-field-runtime-" + $unsafeFieldCase.name) "state"
            [System.IO.Directory]::CreateDirectory($unsafeState) | Out-Null
            $unsafeInbox = Join-Path $unsafeState "knowledge-candidates"
            $forbiddenValue = if ($unsafeFieldCase.name -eq "title") { [string]$unsafeFieldCase.title } else { [string]$unsafeFieldCase.keyword }
            Invoke-ExpectedCandidateFailure -Script $candidateScript -Inbox $unsafeInbox -Root $unsafeProject -LanguageValue "en" -ExpectedPattern ("{0}.*secret assignment" -f $unsafeFieldCase.field) -ForbiddenText @($forbiddenValue)
            Assert-NoTransactionArtifacts -Parent $unsafeState -InboxLeaf "knowledge-candidates"
        }

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

        $unsafeStoredValue = "token=FAKE-STORED-CANDIDATE-1234567890"
        $storedCandidatePath = Get-CandidatePathById -Inbox $inbox -Id ([string]$candidateAInbox.candidate_id)
        $storedOriginalBytes = [System.IO.File]::ReadAllBytes($storedCandidatePath)
        $storedText = [System.IO.File]::ReadAllText($storedCandidatePath, $utf8)
        if ($storedText -notmatch 'candidate intake') {
            throw "Fixture could not prepare an unsafe stored keyword."
        }
        Write-FixtureText -Path $storedCandidatePath -Text ($storedText.Replace("candidate intake", $unsafeStoredValue))
        $unsafeStoredHash = Get-TreeDigest -Root $inbox
        foreach ($mode in @("List", "Export")) {
            Invoke-ExpectedCandidateCommandFailure -Script $candidateScript -Parameters @{
                Mode = $mode
                InboxDir = $inbox
                Json = $true
                ObservedOn = "2026-07-10"
            } -ExpectedPattern "keywords.*secret assignment" -ForbiddenText @($unsafeStoredValue)
            if ($unsafeStoredHash -ne (Get-TreeDigest -Root $inbox)) {
                throw "Stored public-safe validation changed the inbox."
            }
        }
        [System.IO.File]::WriteAllBytes($storedCandidatePath, $storedOriginalBytes)

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

        $mergeTargetId = $byTitle["PowerShell deterministic intake"]
        $mergeSourceId = $byTitle["人工复核后再晋升"]
        $otherTargetId = $byTitle["Reject unsafe partial writes"]
        $mergeInboxHash = Get-TreeDigest -Root $inbox
        Invoke-ExpectedCandidateCommandFailure -Script $candidateScript -Parameters @{
            Mode = "Triage"
            InboxDir = $inbox
            CandidateId = $mergeSourceId
            Status = "accepted"
            ReviewedBy = "fixture-reviewer"
            ObservedOn = "2026-07-10"
        } -ExpectedPattern "existing merge relationship"
        if ($mergeInboxHash -ne (Get-TreeDigest -Root $inbox)) {
            throw "Merged-source retriage failure changed the inbox."
        }
        Invoke-ExpectedCandidateCommandFailure -Script $candidateScript -Parameters @{
            Mode = "Triage"
            InboxDir = $inbox
            CandidateId = $otherTargetId
            Status = "rejected"
            MergeCandidateId = @($mergeSourceId)
            ReviewedBy = "fixture-reviewer"
            ObservedOn = "2026-07-10"
        } -ExpectedPattern "already owned"
        if ($mergeInboxHash -ne (Get-TreeDigest -Root $inbox)) {
            throw "Cross-target merge failure changed the inbox."
        }

        $mergeMismatchInbox = Join-Path $fixtureRoot "merge-mismatch-inbox"
        Copy-FixtureInbox -Source $inbox -Destination $mergeMismatchInbox
        Update-CandidateMetadata -Path (Get-CandidatePathById -Inbox $mergeMismatchInbox -Id $mergeSourceId) -Update {
            param($item)
            $item.status = "pending_review"
            $item.superseded_by = ""
        }
        Invoke-ExpectedCandidateCommandFailure -Script $candidateScript -Parameters @{ Mode = "List"; InboxDir = $mergeMismatchInbox; Json = $true; ObservedOn = "2026-07-10" } -ExpectedPattern "merged_from source"

        $missingReverseInbox = Join-Path $fixtureRoot "merge-missing-reverse-inbox"
        Copy-FixtureInbox -Source $inbox -Destination $missingReverseInbox
        Update-CandidateMetadata -Path (Get-CandidatePathById -Inbox $missingReverseInbox -Id $mergeTargetId) -Update {
            param($item)
            $item.merged_from = @($item.merged_from | Where-Object { [string]$_ -ne $mergeSourceId })
        }
        Invoke-ExpectedCandidateCommandFailure -Script $candidateScript -Parameters @{ Mode = "List"; InboxDir = $missingReverseInbox; Json = $true; ObservedOn = "2026-07-10" } -ExpectedPattern "recorded merge source"

        $duplicateOwnerInbox = Join-Path $fixtureRoot "merge-duplicate-owner-inbox"
        Copy-FixtureInbox -Source $inbox -Destination $duplicateOwnerInbox
        Update-CandidateMetadata -Path (Get-CandidatePathById -Inbox $duplicateOwnerInbox -Id $otherTargetId) -Update {
            param($item)
            $item.merged_from = @(@($item.merged_from) + $mergeSourceId)
        }
        Invoke-ExpectedCandidateCommandFailure -Script $candidateScript -Parameters @{ Mode = "List"; InboxDir = $duplicateOwnerInbox; Json = $true; ObservedOn = "2026-07-10" } -ExpectedPattern "multiple merged_from targets"

        $cycleInbox = Join-Path $fixtureRoot "superseded-cycle-inbox"
        Copy-FixtureInbox -Source $inbox -Destination $cycleInbox
        $ordinarySupersededId = $byTitle["Keep project roots read only"]
        Update-CandidateMetadata -Path (Get-CandidatePathById -Inbox $cycleInbox -Id $mergeTargetId) -Update {
            param($item)
            $item.status = "superseded"
            $item.superseded_by = $ordinarySupersededId
        }
        Invoke-ExpectedCandidateCommandFailure -Script $candidateScript -Parameters @{ Mode = "List"; InboxDir = $cycleInbox; Json = $true; ObservedOn = "2026-07-10" } -ExpectedPattern "cycle"

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
            physical_overlap_aliases_rejected = $true
            safe_external_alias_canonical_write = $true
            broken_and_cyclic_aliases_rejected = $true
            public_safe_rule_categories = @($unsafeSummaryCases | ForEach-Object { [string]$_.rule } | Sort-Object -Unique)
            stored_public_fields_revalidated = $true
            merge_bidirectional_invariant = $true
            merged_source_retriage_rejected = $true
            cross_target_remerge_rejected = $true
            superseded_cycle_rejected = $true
            formal_experience_hub_unchanged = $true
            cross_host_bytes_compared = $crossHostCompared
            intake_output = @($intakeOutput)
        }
        Add-Check "knowledge candidate intake" "PASS" "Isolated candidate discovery, physical-path intake, public-safe validation, bidirectional merge triage, redacted export, atomic preflight, idempotence, and runtime boundary fixtures passed." $script:evidence.knowledge_candidate_intake
    }
    catch {
        Add-Check "knowledge candidate intake" "FAIL" $_.Exception.Message
    }
}
