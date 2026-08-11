#requires -Version 7.6

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet("Analyze", "Apply", "Rollback")][string]$Mode,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$AnalyzeEvidence,
    [string]$DispositionEvidence,
    [string]$BackupId,
    [switch]$ConfirmMigration,
    [switch]$ConfirmRollback,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$script:MigrationSchemaVersion = 1
$script:MigrationRevisionVersion = "c3.3-slice-f-v7"
$script:MigrationSentinel = "2026-01-01T00:00:00Z"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false, $true)

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $bytes = $script:Utf8NoBom.GetBytes($Text)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-Sha256Bytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertTo-StableJson {
    param([Parameter(Mandatory = $true)][object]$Value, [int]$Depth = 40)
    return ($Value | ConvertTo-Json -Depth $Depth -Compress)
}

function ConvertTo-YamlString {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    return ($Value | ConvertTo-Json -Compress)
}

function Get-HashtableValue {
    param([object]$Value, [Parameter(Mandatory = $true)][string]$Name)
    if ($Value -is [Collections.IDictionary]) {
        if ($Value.Contains($Name)) { return $Value[$Name] }
        return $null
    }
    if ($null -eq $Value) { return $null }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-HashtableProperty {
    param([object]$Value, [Parameter(Mandatory = $true)][string]$Name)
    if ($Value -is [Collections.IDictionary]) { return $Value.Contains($Name) }
    return ($null -ne $Value -and $null -ne $Value.PSObject.Properties[$Name])
}

function Get-NormalizedProjectRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "PROJECT_ROOT_INVALID" }
    return $full
}

function Test-SafeRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:' -or $Path -match '(^|[\\/])\.\.?(?:[\\/]|$)') { return $false }
    return ($Path -notmatch '[\x00-\x1f:*?"<>|]')
}

function Get-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$RelativePath)
    if (-not (Test-SafeRelativePath $RelativePath)) { throw "UNSAFE_PROJECT_PATH" }
    $candidate = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $prefix = $Root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "UNSAFE_PROJECT_PATH" }
    return $candidate
}

function Resolve-ProjectEvidencePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RecordedPath
    )
    if ([string]::IsNullOrWhiteSpace($RecordedPath) -or $RecordedPath -match '[\x00-\x1f]' -or $RecordedPath -match '(^|[\\/])\.\.?(?:[\\/]|$)') { throw "LANGUAGE_MIGRATION_PROVENANCE_INVALID" }
    try {
        $candidate = if ([IO.Path]::IsPathRooted($RecordedPath)) {
            [IO.Path]::GetFullPath($RecordedPath)
        }
        else {
            [IO.Path]::GetFullPath((Join-Path $Root $RecordedPath))
        }
    }
    catch { throw "LANGUAGE_MIGRATION_PROVENANCE_INVALID" }

    $prefix = $Root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "LANGUAGE_MIGRATION_PROVENANCE_INVALID" }
    $relative = ConvertTo-RelativePath $Root $candidate
    if (-not (Test-SafeRelativePath $relative)) { throw "LANGUAGE_MIGRATION_PROVENANCE_INVALID" }

    $current = $Root
    foreach ($part in @($relative -split '[\\/]')) {
        $current = Join-Path $current $part
        if (-not (Test-Path -LiteralPath $current)) { throw "LANGUAGE_MIGRATION_PROVENANCE_INVALID" }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "LANGUAGE_MIGRATION_PROVENANCE_INVALID" }
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "LANGUAGE_MIGRATION_PROVENANCE_INVALID" }
    return $candidate
}

function ConvertTo-RelativePath {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Path)
    return [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
}

function Test-ReparsePointInScope {
    param([Parameter(Mandatory = $true)][string]$Root)
    foreach ($relative in @(".agents", "docs/specs", ".claude/skills", ".codex/skills", ".github/skills")) {
        $path = Get-ProjectPath $Root $relative
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $rootItem = Get-Item -LiteralPath $path -Force
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
        foreach ($item in @(Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction Stop)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
        }
    }
    return $false
}

function Get-MigrationRelevantPaths {
    param([Parameter(Mandatory = $true)][string]$Root)
    $paths = [Collections.Generic.List[string]]::new()
    $agentsEntry = Get-ProjectPath $Root "AGENTS.md"
    if (Test-Path -LiteralPath $agentsEntry -PathType Leaf) { $paths.Add("AGENTS.md") }
    foreach ($relativeRoot in @(".agents", "docs/specs", ".claude/skills", ".codex/skills", ".github/skills")) {
        $fullRoot = Get-ProjectPath $Root $relativeRoot
        if (-not (Test-Path -LiteralPath $fullRoot -PathType Container)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $fullRoot -Force -Recurse)) {
            $relative = ConvertTo-RelativePath $Root $item.FullName
            if ($relative -match '^\.agents/\.migration-backups(?:/|$)') { continue }
            $paths.Add($relative)
        }
    }
    return @($paths.ToArray() | Sort-Object -Unique)
}

function Get-PathState {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$RelativePath, [switch]$IncludeContent)
    $full = Get-ProjectPath $Root $RelativePath
    if (-not (Test-Path -LiteralPath $full)) {
        return [ordered]@{ path = $RelativePath.Replace('\', '/'); presence = "absent"; sha256 = $null; length = 0 }
    }
    $item = Get-Item -LiteralPath $full -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "REPARSE_POINT_UNSUPPORTED" }
    if ($item.PSIsContainer) {
        return [ordered]@{ path = $RelativePath.Replace('\', '/'); presence = "directory"; sha256 = $null; length = 0 }
    }
    $bytes = [IO.File]::ReadAllBytes($full)
    $state = [ordered]@{ path = $RelativePath.Replace('\', '/'); presence = "file"; sha256 = Get-Sha256Bytes $bytes; length = $bytes.Length }
    if ($IncludeContent) { $state.content_base64 = [Convert]::ToBase64String($bytes) }
    return $state
}

function Get-StateSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root, [string[]]$AdditionalPaths = @(), [switch]$IncludeContent)
    $all = [Collections.Generic.List[string]]::new()
    foreach ($path in @(Get-MigrationRelevantPaths $Root)) { $all.Add($path) }
    foreach ($path in @($AdditionalPaths)) { if (-not [string]::IsNullOrWhiteSpace($path)) { $all.Add($path.Replace('\', '/')) } }
    $result = [Collections.Generic.List[object]]::new()
    foreach ($path in @($all.ToArray() | Sort-Object -Unique)) { $result.Add((Get-PathState $Root $path -IncludeContent:$IncludeContent)) }
    return @($result.ToArray())
}

function Get-StateDigest {
    param([Parameter(Mandatory = $true)][object[]]$Files)
    $minimal = @($Files | ForEach-Object { [ordered]@{ path = [string]$_.path; presence = [string]$_.presence; sha256 = $_.sha256; length = [long]$_.length } })
    return Get-Sha256Text (ConvertTo-StableJson $minimal)
}

function Test-StateItemEqual {
    param([Parameter(Mandatory = $true)][object]$Left, [Parameter(Mandatory = $true)][object]$Right)
    return (
        [string](Get-HashtableValue $Left "path") -ceq [string](Get-HashtableValue $Right "path") -and
        [string](Get-HashtableValue $Left "presence") -ceq [string](Get-HashtableValue $Right "presence") -and
        [string](Get-HashtableValue $Left "sha256") -ceq [string](Get-HashtableValue $Right "sha256") -and
        [long](Get-HashtableValue $Left "length") -eq [long](Get-HashtableValue $Right "length")
    )
}

function Get-PlannedPostState {
    param(
        [Parameter(Mandatory = $true)][object[]]$PreState,
        [Parameter(Mandatory = $true)][object[]]$Actions
    )
    $byPath = @{}
    foreach ($item in $PreState) {
        $path = [string](Get-HashtableValue $item "path")
        $byPath[$path] = [ordered]@{
            path = $path
            presence = [string](Get-HashtableValue $item "presence")
            sha256 = Get-HashtableValue $item "sha256"
            length = [long](Get-HashtableValue $item "length")
        }
    }
    foreach ($action in $Actions) {
        $kind = [string](Get-HashtableValue $action "action")
        if ($kind -in @("preserve", "preserve-directory")) { continue }
        $path = [string](Get-HashtableValue $action "path")
        if (-not $byPath.ContainsKey($path)) { throw "ROLLBACK_SCOPE_INCOMPLETE" }
        if ($kind -in @("create", "change")) {
            $content = [string](Get-HashtableValue $action "content")
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($content)
            $byPath[$path] = [ordered]@{ path = $path; presence = "file"; sha256 = Get-Sha256Bytes $bytes; length = $bytes.Length }
        }
        elseif ($kind -ceq "remove") {
            $byPath[$path] = [ordered]@{ path = $path; presence = "absent"; sha256 = $null; length = 0 }
        }
        elseif ($kind -ceq "create-directory") {
            $byPath[$path] = [ordered]@{ path = $path; presence = "directory"; sha256 = $null; length = 0 }
        }
        else { throw "MIGRATION_ACTION_UNSUPPORTED" }
    }
    return @($byPath.Keys | Sort-Object -Unique | ForEach-Object { $byPath[$_] })
}

function Read-Utf8Text {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return [IO.File]::ReadAllText($Path, $script:Utf8NoBom) }
    catch [Text.DecoderFallbackException] { throw "INVALID_UTF8" }
}

function Get-MarkdownTitle {
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Fallback)
    $match = [regex]::Match($Text, '(?m)^#\s+(?<value>[^#\r\n].+?)\s*$')
    if ($match.Success) { return $match.Groups['value'].Value.Trim() }
    return $Fallback
}

function Get-MarkdownSection {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Names,
        [switch]$AllowNumericPrefix
    )
    $numericPrefix = if ($AllowNumericPrefix.IsPresent) { '(?:\d+\.[ \t]+)?' } else { '' }
    foreach ($name in $Names) {
        $escaped = [regex]::Escape($name)
        $match = [regex]::Match($Text, "(?ms)^#{1,6}\s+$numericPrefix$escaped\s*\r?\n(?<value>.*?)(?=^#{1,6}\s+|\z)", 'IgnoreCase,CultureInvariant')
        if ($match.Success -and -not [string]::IsNullOrWhiteSpace($match.Groups['value'].Value)) { return $match.Groups['value'].Value.Trim() }
    }
    return ""
}

function Get-LegacyMetadataMatches {
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Name)
    $escaped = [regex]::Escape($Name)
    return @([regex]::Matches($Text, "(?im)^[ \t]*-[ \t]+\*\*$escaped\*\*[ \t]*:[ \t]*(?<value>.*?)[ \t]*$", 'CultureInvariant'))
}

function Convert-LegacySpecStatus {
    param([Parameter(Mandatory = $true)][string]$Status)
    switch ($Status.Trim().ToLowerInvariant()) {
        "draft" { return "draft" }
        "active" { return "accepted" }
        "done" { return "implemented" }
        "archived" { return "archived" }
        "superseded" { return "superseded" }
        default { return $null }
    }
}

function Test-TemplateText {
    param([Parameter(Mandatory = $true)][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }
    return ($Text -match '(?im)^\s*(?:#\s+)?(?:template|example|placeholder)(?:\s|$)' -or $Text -match 'sha256:0{64}' -or $Text -match '(?im)^\s*(?:TODO|TBD):?\s*$')
}

function Test-ContextTemplateText {
    param([Parameter(Mandatory = $true)][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }

    $deterministicPlaceholder = (
        $Text -match 'sha256:0{64}' -or
        $Text -match '(?im)^\s*#{1,6}\s+(?:template|example|placeholder)\s*$' -or
        $Text -match '(?im)^\s*(?:TODO|TBD):?\s*$'
    )

    $explicitFillInstruction = (
        $Text -match '(?im)^\s*(?:[-*]\s*)?(?:TODO|TBD)\s*:\s*(?:fill|add|replace|describe|document|enter|complete)\b' -or
        $Text -match '(?im)^\s*(?:[-*]\s*)?(?:待填写|请填写|在此填写|待补充)(?:\s|[:：]|$)'
    )
    $explicitTemplateRole = (
        $Text -match '(?im)^\s*#{1,6}\s+.*\b(?:template|placeholder)\s*$' -and
        $Text -match '(?im)^\s*(?:template|placeholder)\s+(?:for|to)\b'
    )
    return ($deterministicPlaceholder -or $explicitFillInstruction -or $explicitTemplateRole)
}

function Test-ContextIndexText {
    param([Parameter(Mandatory = $true)][string]$Text)
    return (
        $Text -match '(?im)^\s*#\s+.*\b(?:index|catalog)\s*$' -and
        $Text -match '(?im)^\s*(?:this (?:file|document|page) (?:is|serves as) (?:an? )?(?:index|catalog)|use this (?:index|catalog) to|(?:index|catalog) of (?:context|entries|documents))\b'
    )
}

function Test-ContextFilenameAmbiguous {
    param([Parameter(Mandatory = $true)][string]$Path)
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    return ($name -match '(?i)(?:^|[-_.])(?:template|index|placeholder)(?:$|[-_.])')
}

function Test-ContextNonAuthorityDocument {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    return (
        [IO.Path]::GetFileName($Path) -ieq "README.md" -or
        (Test-ContextTemplateText $Text) -or
        (Test-ContextIndexText $Text)
    )
}

function Test-ContextAuthorityAmbiguous {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    return (
        $name -match '(?i)(?:^|[-_.])(?:example|sample)(?:$|[-_.])' -or
        ($Text -match '(?im)^\s*#{1,6}\s+.*\b(?:guide|guidance|instructions?|catalog|reference)\b' -and
            $Text -match '(?im)\b(?:use this|add entries|fill in|document .+ here|how to)\b')
    )
}

function Get-SafeId {
    param([Parameter(Mandatory = $true)][string]$Value, [string]$Fallback = "legacy")
    $id = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $id = $id.Trim('-')
    if ([string]::IsNullOrWhiteSpace($id)) { return $Fallback }
    return $id
}

function Get-WorkRevisionFromText {
    param([Parameter(Mandatory = $true)][string]$Text)
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = @($normalized -split "`n")
    $withoutRevision = [Collections.Generic.List[string]]::new()
    $inFrontMatter = ($lines.Count -gt 0 -and [string]$lines[0] -ceq "---")
    $frontMatterClosed = $false
    $removed = $false
    foreach ($line in $lines) {
        if ($inFrontMatter -and -not $frontMatterClosed -and [string]$line -ceq "---" -and $withoutRevision.Count -gt 0) {
            $frontMatterClosed = $true
        }
        if ($inFrontMatter -and -not $frontMatterClosed -and -not $removed -and [string]$line -match '^revision:') {
            $removed = $true
            continue
        }
        [void]$withoutRevision.Add([string]$line)
    }
    return Get-Sha256Text ($withoutRevision.ToArray() -join "`n")
}

function New-WorkContent {
    param([Parameter(Mandatory = $true)][object[]]$Sources)
    $joined = @($Sources | ForEach-Object { "## Legacy source: $($_.path)`n`n$($_.text.Trim())" }) -join "`n`n"
    $summary = "Preserve explicit unfinished legacy work for reviewed C3.3 continuation."
    $next = "Review the migrated legacy state and select the next verified step."
    $placeholder = @"
---
schema: agent-ecosystem/work-item/v1
id: legacy-work
title: Legacy unfinished work
status: active
updated: $($script:MigrationSentinel)
revision: sha256:$('0' * 64)
summary: $(ConvertTo-YamlString $summary)
next: $(ConvertTo-YamlString $next)
---

$joined
"@.TrimStart()
    $revision = Get-WorkRevisionFromText $placeholder
    return $placeholder -replace 'revision: sha256:0{64}', "revision: sha256:$revision"
}

function New-ContextContent {
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$Title, [Parameter(Mandatory = $true)][string]$Summary, [Parameter(Mandatory = $true)][string[]]$Keywords, [Parameter(Mandatory = $true)][string]$SourcePath, [Parameter(Mandatory = $true)][string]$Body)
    $keywordLines = @($Keywords | Sort-Object -Unique | ForEach-Object { "  - $(ConvertTo-YamlString $_)" }) -join "`n"
    return @"
---
schema: agent-ecosystem/context/v1
id: $Id
title: $(ConvertTo-YamlString $Title)
status: active
updated: $($script:MigrationSentinel)
summary: $(ConvertTo-YamlString $Summary)
keywords:
$keywordLines
evidence:
  - $(ConvertTo-YamlString "Migrated verbatim from $SourcePath")
---

$Body
"@.TrimStart()
}

function New-ProcedureContent {
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$Title, [Parameter(Mandatory = $true)][string]$Summary, [Parameter(Mandatory = $true)][string]$SourcePath, [Parameter(Mandatory = $true)][string]$Body)
    return @"
---
schema: agent-ecosystem/procedure/v1
id: $Id
title: $(ConvertTo-YamlString $Title)
kind: workflow
exposure: internal
summary: $(ConvertTo-YamlString $Summary)
triggers:
  - $(ConvertTo-YamlString "Use the migrated procedure from $SourcePath")
side_effects:
  - $(ConvertTo-YamlString "Review the migrated safety boundary before execution")
---

$Body
"@.TrimStart()
}

function New-SpecContent {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Summary,
        [Parameter(Mandatory = $true)][string]$Body
    )
    return @"
---
schema: agent-ecosystem/spec/v1
id: $Id
title: $(ConvertTo-YamlString $Title)
status: $Status
updated: $($script:MigrationSentinel)
summary: $(ConvertTo-YamlString $Summary)
related_work: []
supersedes: []
---

$Body
"@.TrimStart()
}

function Add-PlanAction {
    param([Collections.Generic.List[object]]$Actions, [string]$Action, [string]$Path, [string[]]$SourcePaths = @(), [AllowNull()][string]$Content = $null, [string]$ReasonCode)
    $entry = [ordered]@{ action = $Action; path = $Path.Replace('\', '/'); source_paths = @($SourcePaths | Sort-Object -Unique); reason_code = $ReasonCode }
    if ($Action -in @("create", "change")) { $entry.content = $Content; $entry.expected_sha256 = Get-Sha256Text $Content }
    $Actions.Add($entry)
}

function Set-ResolvedNonAuthorityLockEntries {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][Collections.Generic.List[object]]$Actions,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries
    )
    if ($Entries.Count -eq 0) { return }
    $indexes = @(0..($Actions.Count - 1) | Where-Object {
            [string](Get-HashtableValue $Actions[$_] "path") -ceq ".agents/hub.lock.json" -and
            [string](Get-HashtableValue $Actions[$_] "action") -ceq "change"
        })
    if ($indexes.Count -ne 1) { throw "DISPOSITION_LOCK_ACTION_MISSING" }
    $index = [int]$indexes[0]
    $action = $Actions[$index]
    try { $lock = [string](Get-HashtableValue $action "content") | ConvertFrom-Json -AsHashtable -Depth 100 -ErrorAction Stop }
    catch { throw "DISPOSITION_LOCK_CONTENT_INVALID" }
    $existing = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $section = Get-HashtableValue $lock "migration_non_authority"
    if ($null -ne $section) {
        $existingValue = $null
        if ($section -is [Collections.IDictionary] -and $section.Contains("entries")) { $existingValue = $section["entries"] }
        if ([int](Get-HashtableValue $section "schema_version") -ne 1 -or $existingValue -isnot [Collections.IList] -or $existingValue -is [string]) { throw "DISPOSITION_LOCK_SECTION_INVALID" }
        foreach ($entry in @($existingValue)) {
            $entryPath = [string](Get-HashtableValue $entry "path")
            if ([string]::IsNullOrWhiteSpace($entryPath) -or $existing.ContainsKey($entryPath)) { throw "DISPOSITION_LOCK_ENTRY_INVALID" }
            $existing[$entryPath] = $entry
        }
    }
    foreach ($entry in $Entries) {
        $entryPath = [string](Get-HashtableValue $entry "path")
        if ($existing.ContainsKey($entryPath)) { throw "DISPOSITION_TARGET_COLLISION" }
        $existing[$entryPath] = $entry
    }
    $lock["migration_non_authority"] = [ordered]@{
        schema_version = 1
        entries = [object[]]@($existing.Keys | Sort-Object | ForEach-Object { $existing[$_] })
    }
    $Actions.RemoveAt($index)
    Add-PlanAction $Actions "change" ".agents/hub.lock.json" @($action.source_paths) (($lock | ConvertTo-Json -Depth 100) + "`n") ([string]$action.reason_code)
}

function Assert-ExactObjectProperties {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string[]]$Required,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$ErrorCode
    )
    if ($Value -isnot [Collections.IDictionary]) { throw $ErrorCode }
    $names = @($Value.Keys | ForEach-Object { [string]$_ })
    if (@($Required | Where-Object { $names -cnotcontains $_ }).Count -gt 0 -or
        @($names | Where-Object { $Allowed -cnotcontains $_ }).Count -gt 0) { throw $ErrorCode }
}

function Test-CanonicalProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-SafeRelativePath $Path)) { return $false }
    try { return ((ConvertTo-RelativePath $Root (Get-ProjectPath $Root $Path)) -ceq $Path) }
    catch { return $false }
}

function Get-DispositionKey {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ReasonCode)
    return "$Path`n$ReasonCode"
}

function Assert-ReviewedSourceBinding {
    param(
        [Parameter(Mandatory = $true)][object]$Candidate,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SourceSha256
    )
    if ($SourceSha256 -cnotmatch '^[a-f0-9]{64}$') { throw "DISPOSITION_EVIDENCE_INVALID" }
    $matches = @((Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "files") | Where-Object {
            [string](Get-HashtableValue $_ "path") -ceq $Path
        })
    if ($matches.Count -ne 1 -or [string](Get-HashtableValue $matches[0] "presence") -cne "file" -or
        [string](Get-HashtableValue $matches[0] "sha256") -cne $SourceSha256) { throw "DISPOSITION_SOURCE_MISMATCH" }
}

function Test-PreserveDispositionAllowed {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ReasonCode)
    if ($ReasonCode -ceq "LEGACY_WORK_NOT_DETERMINISTIC") { return ($Path -cin @(".agents/process.txt", ".agents/plan.md")) }
    if ($ReasonCode -ceq "CONTEXT_MARKERS_MISSING") {
        return ($Path -ceq ".agents/notes.md" -or $Path -cmatch '^\.agents/context/.+\.md$')
    }
    return $false
}

function Test-RetireDispositionAllowed {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ReasonCode)
    if ($ReasonCode -ceq "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED") { return ($Path -ceq ".agents/AGENTS.md") }
    if ($ReasonCode -ceq "LEGACY_WORK_NOT_DETERMINISTIC") { return ($Path -cin @(".agents/process.txt", ".agents/plan.md")) }
    if ($ReasonCode -ceq "CONTEXT_MARKERS_MISSING") {
        return ($Path -ceq ".agents/notes.md" -or $Path -cmatch '^\.agents/context/.+\.md$')
    }
    return $false
}

function Resolve-ReviewedDisposition {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object]$Candidate,
        [Parameter(Mandatory = $true)][string]$EvidenceJson
    )
    try { $reviewed = $EvidenceJson | ConvertFrom-Json -AsHashtable -Depth 100 -ErrorAction Stop }
    catch { throw "DISPOSITION_EVIDENCE_INVALID" }
    Assert-ExactObjectProperties $reviewed @("schema_version", "project_root", "migration_revision", "state_digest", "plan_digest", "human_disposition", "decisions") @("schema_version", "project_root", "migration_revision", "state_digest", "plan_digest", "human_disposition", "decisions") "DISPOSITION_EVIDENCE_INVALID"
    if ([int](Get-HashtableValue $reviewed "schema_version") -ne 1) { throw "DISPOSITION_EVIDENCE_INVALID" }
    if ([string](Get-HashtableValue $reviewed "project_root") -cne [string](Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "project_root") -or
        [string](Get-HashtableValue $reviewed "migration_revision") -cne [string](Get-HashtableValue $Candidate "migration_revision") -or
        [string](Get-HashtableValue $reviewed "state_digest") -cne [string](Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "state_digest") -or
        [string](Get-HashtableValue $reviewed "plan_digest") -cne [string](Get-HashtableValue (Get-HashtableValue $Candidate "plan") "plan_digest")) { throw "DISPOSITION_EVIDENCE_STALE" }

    $candidateHuman = @((Get-HashtableValue $Candidate "human_disposition"))
    # Read array-valued fields directly so a single JSON element stays an
    # IList without accepting an object where the schema requires an array.
    $suppliedHumanValue = $reviewed["human_disposition"]
    $decisionsValue = $reviewed["decisions"]
    if ($suppliedHumanValue -isnot [Collections.IList] -or $suppliedHumanValue -is [string] -or
        $decisionsValue -isnot [Collections.IList] -or $decisionsValue -is [string]) { throw "DISPOSITION_EVIDENCE_INVALID" }
    if ($candidateHuman.Count -eq 0) { throw "DISPOSITION_DECISION_EXTRA" }

    $candidateByKey = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $candidatePaths = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
    $normalizedHuman = [Collections.Generic.List[object]]::new()
    foreach ($item in @($candidateHuman | Sort-Object path, reason_code)) {
        $path = [string](Get-HashtableValue $item "path")
        $reason = [string](Get-HashtableValue $item "reason_code")
        $key = Get-DispositionKey $path $reason
        if ($candidateByKey.ContainsKey($key)) { throw "DISPOSITION_EVIDENCE_INVALID" }
        $candidateByKey[$key] = $item
        $candidatePaths[$path] = $true
        $normalizedHuman.Add([ordered]@{ path = $path; reason_code = $reason })
    }

    $suppliedHuman = [Collections.Generic.List[object]]::new()
    $suppliedHumanKeys = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
    foreach ($item in @($suppliedHumanValue)) {
        Assert-ExactObjectProperties $item @("path", "reason_code") @("path", "reason_code") "DISPOSITION_EVIDENCE_INVALID"
        $path = [string](Get-HashtableValue $item "path")
        $reason = [string](Get-HashtableValue $item "reason_code")
        $key = Get-DispositionKey $path $reason
        if ($suppliedHumanKeys.ContainsKey($key)) { throw "DISPOSITION_EVIDENCE_INVALID" }
        $suppliedHumanKeys[$key] = $true
        $suppliedHuman.Add([ordered]@{ path = $path; reason_code = $reason })
    }
    if ($suppliedHumanKeys.Count -ne $candidateByKey.Count -or
        @($candidateByKey.Keys | Where-Object { -not $suppliedHumanKeys.ContainsKey([string]$_) }).Count -gt 0) { throw "DISPOSITION_EVIDENCE_STALE" }

    $decisionByKey = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $decisionByPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($decision in @($decisionsValue)) {
        if ($decision -isnot [Collections.IDictionary]) { throw "DISPOSITION_EVIDENCE_INVALID" }
        foreach ($required in @("path", "reason_code", "disposition")) {
            if (-not (Test-HashtableProperty $decision $required)) { throw "DISPOSITION_EVIDENCE_INVALID" }
        }
        $path = [string](Get-HashtableValue $decision "path")
        $reason = [string](Get-HashtableValue $decision "reason_code")
        $key = Get-DispositionKey $path $reason
        if ($decisionByKey.ContainsKey($key)) { throw "DISPOSITION_DECISION_DUPLICATE" }
        if (-not $candidateByKey.ContainsKey($key)) {
            if ($candidatePaths.ContainsKey($path)) { throw "DISPOSITION_PATH_REASON_MISMATCH" }
            throw "DISPOSITION_DECISION_EXTRA"
        }
        if ($decisionByPath.ContainsKey($path)) { throw "DISPOSITION_DECISION_DUPLICATE" }
        $decisionByKey[$key] = $decision
        $decisionByPath[$path] = $decision
    }
    if ($decisionByKey.Count -ne $candidateByKey.Count) { throw "DISPOSITION_DECISION_MISSING" }

    $groupOwnerBySource = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($decision in @($decisionsValue)) {
        if ([string](Get-HashtableValue $decision "disposition") -cne "create-context-and-retire-sources") { continue }
        Assert-ExactObjectProperties $decision @("path", "reason_code", "disposition", "source_paths", "target", "content") @("path", "reason_code", "disposition", "source_paths", "target", "content") "DISPOSITION_EVIDENCE_INVALID"
        $leader = [string](Get-HashtableValue $decision "path")
        $sourcesValue = Get-HashtableValue $decision "source_paths"
        if ($sourcesValue -isnot [Collections.IList] -or $sourcesValue -is [string]) { throw "DISPOSITION_EVIDENCE_INVALID" }
        $sources = @($sourcesValue | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        if ($sources.Count -lt 2 -or $sources -cnotcontains $leader -or $sources.Count -ne @($sourcesValue).Count) { throw "DISPOSITION_EVIDENCE_INVALID" }
        foreach ($source in $sources) {
            if ($groupOwnerBySource.ContainsKey($source)) { throw "DISPOSITION_TARGET_COLLISION" }
            if (-not $decisionByPath.ContainsKey($source)) { throw "DISPOSITION_DECISION_MISSING" }
            $sourceDecision = $decisionByPath[$source]
            if ([string](Get-HashtableValue $sourceDecision "reason_code") -cne "CONTEXT_MARKERS_MISSING") { throw "DISPOSITION_PATH_REASON_MISMATCH" }
            $expectedOperation = if ($source -ceq $leader) { "create-context-and-retire-sources" } else { "retire-legacy-source" }
            if ([string](Get-HashtableValue $sourceDecision "disposition") -cne $expectedOperation) { throw "DISPOSITION_EVIDENCE_INVALID" }
            $groupOwnerBySource[$source] = $leader
        }
    }

    $resolvedActions = [Collections.Generic.List[object]]::new()
    $actionPaths = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
    foreach ($action in @((Get-HashtableValue (Get-HashtableValue $Candidate "plan") "actions"))) {
        $path = [string](Get-HashtableValue $action "path")
        if ($actionPaths.ContainsKey($path)) { throw "DISPOSITION_TARGET_COLLISION" }
        $actionPaths[$path] = $true
        $resolvedActions.Add($action)
    }
    $normalizedDecisions = [Collections.Generic.List[object]]::new()
    foreach ($decision in @($decisionsValue | Sort-Object path, reason_code)) {
        $path = [string](Get-HashtableValue $decision "path")
        $reason = [string](Get-HashtableValue $decision "reason_code")
        $operation = [string](Get-HashtableValue $decision "disposition")
        if (-not (Test-CanonicalProjectRelativePath $Root $path)) { throw "DISPOSITION_TARGET_INVALID" }
        if ($actionPaths.ContainsKey($path)) { throw "DISPOSITION_TARGET_COLLISION" }
        switch ($operation) {
            "preserve-non-authority" {
                Assert-ExactObjectProperties $decision @("path", "reason_code", "disposition") @("path", "reason_code", "disposition") "DISPOSITION_EVIDENCE_INVALID"
                if (-not (Test-PreserveDispositionAllowed $path $reason)) { throw "DISPOSITION_UNSUPPORTED" }
                if (-not (Test-Path -LiteralPath (Get-ProjectPath $Root $path) -PathType Leaf)) { throw "DISPOSITION_EVIDENCE_STALE" }
                Add-PlanAction $resolvedActions "preserve" $path @($path) $null "REVIEWED_NON_AUTHORITY_PRESERVED"
                $actionPaths[$path] = $true
                $normalizedDecisions.Add([ordered]@{ path = $path; reason_code = $reason; disposition = $operation })
            }
            "retire-legacy-source" {
                Assert-ExactObjectProperties $decision @("path", "reason_code", "disposition") @("path", "reason_code", "disposition") "DISPOSITION_EVIDENCE_INVALID"
                if (-not (Test-RetireDispositionAllowed $path $reason)) { throw "DISPOSITION_UNSUPPORTED" }
                if (-not (Test-Path -LiteralPath (Get-ProjectPath $Root $path) -PathType Leaf)) { throw "DISPOSITION_EVIDENCE_STALE" }
                Add-PlanAction $resolvedActions "remove" $path @($path) $null "REVIEWED_LEGACY_SOURCE_RETIRED"
                $actionPaths[$path] = $true
                $normalizedDecisions.Add([ordered]@{ path = $path; reason_code = $reason; disposition = $operation })
            }
            "replace-root-contract" {
                Assert-ExactObjectProperties $decision @("path", "reason_code", "disposition", "target", "content") @("path", "reason_code", "disposition", "target", "content") "DISPOSITION_EVIDENCE_INVALID"
                $target = [string](Get-HashtableValue $decision "target")
                $contentValue = Get-HashtableValue $decision "content"
                if ($path -cnotin @("AGENTS.md", ".agents/AGENTS.md") -or $reason -cne "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED") { throw "DISPOSITION_UNSUPPORTED" }
                if ($target -cne "AGENTS.md") { throw "DISPOSITION_TARGET_INVALID" }
                if ($contentValue -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$contentValue) -or [string]$contentValue -match "`0") { throw "DISPOSITION_CONTENT_INVALID" }
                if (-not (Test-Path -LiteralPath (Get-ProjectPath $Root $path) -PathType Leaf)) { throw "DISPOSITION_EVIDENCE_STALE" }
                if ($path -ceq ".agents/AGENTS.md") {
                    $candidateRootActions = @((Get-HashtableValue (Get-HashtableValue $Candidate "plan") "actions") | Where-Object { [string](Get-HashtableValue $_ "path") -ceq "AGENTS.md" })
                    if ($candidateRootActions.Count -ne 1 -or
                        [string](Get-HashtableValue $candidateRootActions[0] "action") -cne "change" -or
                        [string](Get-HashtableValue $candidateRootActions[0] "reason_code") -cne "LEGACY_ENTRYPOINT_REPLACED") { throw "DISPOSITION_TARGET_COLLISION" }
                    $resolvedRootIndexes = @(0..($resolvedActions.Count - 1) | Where-Object { [string](Get-HashtableValue $resolvedActions[$_] "path") -ceq "AGENTS.md" })
                    if ($resolvedRootIndexes.Count -ne 1) { throw "DISPOSITION_TARGET_COLLISION" }
                    $resolvedActions.RemoveAt([int]$resolvedRootIndexes[0])
                    [void]$actionPaths.Remove("AGENTS.md")
                    Add-PlanAction $resolvedActions "change" $target @("AGENTS.md", $path) ([string]$contentValue) "REVIEWED_ROOT_CONTRACT_REPLACED"
                    $actionPaths[$target] = $true
                    Add-PlanAction $resolvedActions "remove" $path @($path) $null "REVIEWED_LEGACY_SOURCE_RETIRED"
                    $actionPaths[$path] = $true
                }
                else {
                    Add-PlanAction $resolvedActions "change" $target @($path) ([string]$contentValue) "REVIEWED_ROOT_CONTRACT_REPLACED"
                    $actionPaths[$target] = $true
                }
                $normalizedDecisions.Add([ordered]@{ path = $path; reason_code = $reason; disposition = $operation; target = $target; content = [string]$contentValue })
            }
            "create-context-and-retire-sources" {
                $target = [string](Get-HashtableValue $decision "target")
                $contentValue = Get-HashtableValue $decision "content"
                $sources = @((Get-HashtableValue $decision "source_paths") | ForEach-Object { [string]$_ } | Sort-Object -Unique)
                if ((Test-CanonicalProjectRelativePath $Root $target) -and
                    ($actionPaths.ContainsKey($target) -or (Test-Path -LiteralPath (Get-ProjectPath $Root $target)))) { throw "DISPOSITION_TARGET_COLLISION" }
                if ($reason -cne "CONTEXT_MARKERS_MISSING") { throw "DISPOSITION_UNSUPPORTED" }
                if ($target -cnotmatch '^\.agents/context/[a-z0-9]+(?:-[a-z0-9]+)*\.md$' -or
                    -not (Test-CanonicalProjectRelativePath $Root $target) -or $sources -ccontains $target) { throw "DISPOSITION_TARGET_INVALID" }
                if ($contentValue -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$contentValue) -or [string]$contentValue -match "`0") { throw "DISPOSITION_CONTENT_INVALID" }
                Add-PlanAction $resolvedActions "create" $target $sources ([string]$contentValue) "REVIEWED_CONTEXT_CREATED"
                $actionPaths[$target] = $true
                Add-PlanAction $resolvedActions "remove" $path @($path) $null "REVIEWED_LEGACY_SOURCE_RETIRED"
                $actionPaths[$path] = $true
                $normalizedDecisions.Add([ordered]@{ path = $path; reason_code = $reason; disposition = $operation; source_paths = $sources; target = $target; content = [string]$contentValue })
            }
            "create-procedure-and-retire-source" {
                Assert-ExactObjectProperties $decision @("path", "reason_code", "disposition", "source_sha256", "target", "content") @("path", "reason_code", "disposition", "source_sha256", "target", "content") "DISPOSITION_EVIDENCE_INVALID"
                $target = [string](Get-HashtableValue $decision "target")
                $contentValue = Get-HashtableValue $decision "content"
                if ($reason -cne "PROCEDURE_MARKERS_MISSING") { throw "DISPOSITION_UNSUPPORTED" }
                Assert-ReviewedSourceBinding $Candidate $path ([string](Get-HashtableValue $decision "source_sha256"))
                if ($target -cnotmatch '^\.agents/procedures/[a-z0-9]+(?:-[a-z0-9]+)*\.md$' -or
                    -not (Test-CanonicalProjectRelativePath $Root $target) -or $target -ceq $path) { throw "DISPOSITION_TARGET_INVALID" }
                if ($actionPaths.ContainsKey($target) -or (Test-Path -LiteralPath (Get-ProjectPath $Root $target))) { throw "DISPOSITION_TARGET_COLLISION" }
                if ($contentValue -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$contentValue) -or [string]$contentValue -match "`0") { throw "DISPOSITION_CONTENT_INVALID" }
                if (-not (Test-Path -LiteralPath (Get-ProjectPath $Root $path) -PathType Leaf)) { throw "DISPOSITION_EVIDENCE_STALE" }
                Add-PlanAction $resolvedActions "create" $target @($path) ([string]$contentValue) "REVIEWED_PROCEDURE_CREATED"
                $actionPaths[$target] = $true
                Add-PlanAction $resolvedActions "remove" $path @($path) $null "REVIEWED_LEGACY_SOURCE_RETIRED"
                $actionPaths[$path] = $true
                $normalizedDecisions.Add([ordered]@{ path = $path; reason_code = $reason; disposition = $operation; source_sha256 = [string](Get-HashtableValue $decision "source_sha256"); target = $target; content = [string]$contentValue })
            }
            "create-spec-and-retire-source" {
                Assert-ExactObjectProperties $decision @("path", "reason_code", "disposition", "source_sha256", "target", "content") @("path", "reason_code", "disposition", "source_sha256", "target", "content") "DISPOSITION_EVIDENCE_INVALID"
                $target = [string](Get-HashtableValue $decision "target")
                $contentValue = Get-HashtableValue $decision "content"
                if ($reason -cne "SPEC_MARKERS_MISSING") { throw "DISPOSITION_UNSUPPORTED" }
                Assert-ReviewedSourceBinding $Candidate $path ([string](Get-HashtableValue $decision "source_sha256"))
                if ($target -cnotmatch '^docs/specs/[a-z0-9]+(?:-[a-z0-9]+)*/spec\.md$' -or
                    -not (Test-CanonicalProjectRelativePath $Root $target)) { throw "DISPOSITION_TARGET_INVALID" }
                if ($contentValue -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$contentValue) -or [string]$contentValue -match "`0") { throw "DISPOSITION_CONTENT_INVALID" }
                if (-not (Test-Path -LiteralPath (Get-ProjectPath $Root $path) -PathType Leaf)) { throw "DISPOSITION_EVIDENCE_STALE" }
                if ($target -ceq $path) {
                    if ($actionPaths.ContainsKey($target)) { throw "DISPOSITION_TARGET_COLLISION" }
                    Add-PlanAction $resolvedActions "change" $target @($path) ([string]$contentValue) "REVIEWED_SPEC_REPLACED"
                    $actionPaths[$target] = $true
                }
                else {
                    $targetDirectory = $target.Substring(0, $target.LastIndexOf('/'))
                    if ($actionPaths.ContainsKey($target) -or $actionPaths.ContainsKey($targetDirectory) -or
                        (Test-Path -LiteralPath (Get-ProjectPath $Root $target)) -or
                        (Test-Path -LiteralPath (Get-ProjectPath $Root $targetDirectory))) { throw "DISPOSITION_TARGET_COLLISION" }
                    Add-PlanAction $resolvedActions "create-directory" $targetDirectory @($path) $null "REVIEWED_SPEC_DIRECTORY_CREATED"
                    $actionPaths[$targetDirectory] = $true
                    Add-PlanAction $resolvedActions "create" $target @($path) ([string]$contentValue) "REVIEWED_SPEC_CREATED"
                    $actionPaths[$target] = $true
                    Add-PlanAction $resolvedActions "remove" $path @($path) $null "REVIEWED_LEGACY_SOURCE_RETIRED"
                    $actionPaths[$path] = $true
                }
                $normalizedDecisions.Add([ordered]@{ path = $path; reason_code = $reason; disposition = $operation; source_sha256 = [string](Get-HashtableValue $decision "source_sha256"); target = $target; content = [string]$contentValue })
            }
            default { throw "DISPOSITION_UNSUPPORTED" }
        }
    }

    $normalizedEvidence = [ordered]@{
        schema_version = 1
        project_root = [string](Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "project_root")
        migration_revision = [string](Get-HashtableValue $Candidate "migration_revision")
        state_digest = [string](Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "state_digest")
        plan_digest = [string](Get-HashtableValue (Get-HashtableValue $Candidate "plan") "plan_digest")
        human_disposition = @($normalizedHuman.ToArray())
        decisions = @($normalizedDecisions.ToArray())
    }
    $dispositionDigest = Get-Sha256Text (ConvertTo-StableJson $normalizedEvidence)
    $reviewedNonAuthorityEntries = @($normalizedDecisions.ToArray() | Where-Object {
            [string](Get-HashtableValue $_ "disposition") -ceq "preserve-non-authority" -and
            [string](Get-HashtableValue $_ "path") -cmatch '^\.agents/context/.+\.md$'
        } | ForEach-Object {
            $entryPath = [string](Get-HashtableValue $_ "path")
            $candidateFile = @((Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "files") | Where-Object {
                    [string](Get-HashtableValue $_ "path") -ceq $entryPath
                })
            if ($candidateFile.Count -ne 1 -or [string](Get-HashtableValue $candidateFile[0] "presence") -cne "file") { throw "DISPOSITION_SOURCE_MISMATCH" }
            [ordered]@{ path = $entryPath; sha256 = [string](Get-HashtableValue $candidateFile[0] "sha256"); evidence_kind = "reviewed-disposition"; evidence_sha256 = $dispositionDigest }
        })
    Set-ResolvedNonAuthorityLockEntries $Root $resolvedActions $reviewedNonAuthorityEntries
    $sortedActions = @($resolvedActions.ToArray() | Sort-Object path, action, reason_code)
    $allPlanPaths = @($sortedActions | ForEach-Object { [string](Get-HashtableValue $_ "path") } | Sort-Object -Unique)
    $files = @(Get-StateSnapshot $Root $allPlanPaths)
    $stateDigest = Get-StateDigest $files
    $planCore = [ordered]@{ sentinel_updated = $script:MigrationSentinel; sentinel_source = "deterministic-migration-sentinel-v1"; reviewed_disposition_digest = $dispositionDigest; actions = $sortedActions }
    $planDigest = Get-Sha256Text (ConvertTo-StableJson $planCore)
    $migrationRevision = Get-Sha256Text ("$($script:MigrationRevisionVersion)`n$stateDigest`n$planDigest")
    $remainingReasons = [Collections.Generic.List[string]]::new()
    foreach ($reasonCode in @((Get-HashtableValue $Candidate "reason_codes"))) {
        if ([string]$reasonCode -cnotin @("HUMAN_DISPOSITION_REQUIRED", "NO_MIGRATABLE_AUTHORITY")) { $remainingReasons.Add([string]$reasonCode) }
    }
    if (@($sortedActions | Where-Object { [string]$_.action -in @("create", "change") -and [string]$_.path -cne ".agents/hub.lock.json" }).Count -eq 0) { $remainingReasons.Add("NO_MIGRATABLE_AUTHORITY") }
    $reasonArray = @($remainingReasons.ToArray() | Sort-Object -Unique)
    if ($reasonArray.Count -eq 0) {
        try { [void](Assert-ResolvedPlanWorkspaceValid $Root $sortedActions) }
        catch { throw "DISPOSITION_CONTENT_INVALID" }
    }
    $eligible = ($reasonArray.Count -eq 0)
    $normalizedEvidence.reviewed_disposition_digest = $dispositionDigest
    return [ordered]@{
        schema_version = $script:MigrationSchemaVersion; operation = "analyze"; status = $(if ($eligible) { "eligible" } else { "blocked" }); eligible = $eligible
        reason_codes = $reasonArray; migration_revision = $migrationRevision
        evidence = [ordered]@{ evidence_version = 1; project_root = $Root; project_language = (Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "project_language"); workspace_model = (Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "workspace_model"); workspace_state = (Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "workspace_state"); scaffold_contract = (Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "scaffold_contract"); files = $files; state_digest = $stateDigest; candidate_state_digest = [string](Get-HashtableValue (Get-HashtableValue $Candidate "evidence") "state_digest") }
        plan = [ordered]@{ plan_version = 2; plan_digest = $planDigest; candidate_plan_digest = [string](Get-HashtableValue (Get-HashtableValue $Candidate "plan") "plan_digest"); reviewed_disposition_digest = $dispositionDigest; sentinel_updated = $script:MigrationSentinel; sentinel_source = "deterministic-migration-sentinel-v1"; actions = $sortedActions; create = @($sortedActions | Where-Object action -eq "create" | ForEach-Object path); create_directories = @($sortedActions | Where-Object action -eq "create-directory" | ForEach-Object path); change = @($sortedActions | Where-Object action -eq "change" | ForEach-Object path); remove = @($sortedActions | Where-Object action -eq "remove" | ForEach-Object path); preserve = @($sortedActions | Where-Object action -in @("preserve", "preserve-directory") | ForEach-Object path) }
        human_disposition = @($normalizedHuman.ToArray())
        reviewed_disposition = $normalizedEvidence
        backup_requirements = [ordered]@{ backup_id = $migrationRevision.Substring(0, 24); path = ".agents/.migration-backups/$($migrationRevision.Substring(0, 24))/"; project_owned = $true; offline = $true; retained_after_rollback = $true; complete_pre_state_required = $true }
    }
}

function Get-C33ScaffoldContract {
    param([Parameter(Mandatory = $true)][string]$Language)
    $runtimeRoot = Split-Path -Parent $PSScriptRoot
    $relativeRoot = "skills/project-bootstrap/assets/c3-3-project-template/$Language"
    $templateRoot = Join-Path $runtimeRoot $relativeRoot
    $files = [ordered]@{}
    foreach ($relative in @("AGENTS.md", ".agents/README.md", ".agents/.gitignore")) {
        $source = Join-Path $templateRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "C33_SCAFFOLD_CONTRACT_UNAVAILABLE" }
        $content = Read-Utf8Text $source
        $files[$relative] = [ordered]@{
            source = "$relativeRoot/$relative"
            content = $content
            sha256 = Get-Sha256Text $content
        }
    }
    return [ordered]@{
        source = $relativeRoot
        files = $files
        directories = @(".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")
    }
}

function Get-LegacyScaffoldText {
    param([Parameter(Mandatory = $true)][string]$Language, [Parameter(Mandatory = $true)][string]$RelativePath)
    $runtimeRoot = Split-Path -Parent $PSScriptRoot
    $source = switch ($RelativePath) {
        "AGENTS.md" { Join-Path $runtimeRoot "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/$Language/project-root/AGENTS.md" }
        ".agents/AGENTS.md" { Join-Path $runtimeRoot "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/$Language/project-agent/AGENTS.md" }
        default { return $null }
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "LEGACY_SCAFFOLD_CONTRACT_UNAVAILABLE" }
    return Read-Utf8Text $source
}

function Test-RecordedLegacyScaffold {
    param(
        [AllowNull()][object]$Lock,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Content
    )
    if ($null -eq $Lock -or [string](Get-HashtableValue $Lock "workspace_model") -notin @("", "legacy")) { return $false }
    $hashes = Get-HashtableValue $Lock "template_installed_hashes_sha256"
    $recorded = [string](Get-HashtableValue $hashes $RelativePath)
    return (-not [string]::IsNullOrWhiteSpace($recorded) -and $recorded -ceq (Get-Sha256Text $Content))
}

function Get-VerifiedLanguageMigrationTemplatePaths {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [AllowNull()][object]$Lock,
        [Parameter(Mandatory = $true)][string]$ProjectLanguage,
        [Parameter(Mandatory = $true)][ref]$ManualReviewPaths
    )
    $verified = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
    $manualReview = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
    $ManualReviewPaths.Value = $manualReview
    try {
        $migration = Get-HashtableValue $Lock "language_migration"
        if ($null -eq $migration -or [int](Get-HashtableValue $migration "schema_version") -ne 1) { return ,$verified }
        $sourceLanguage = [string](Get-HashtableValue $migration "source_language")
        $targetLanguage = [string](Get-HashtableValue $migration "target_language")
        if ($sourceLanguage -cnotin @("en", "zh-CN") -or $targetLanguage -cnotin @("en", "zh-CN") -or
            $sourceLanguage -ceq $targetLanguage -or $targetLanguage -cne $ProjectLanguage) { return ,$verified }

        $proposalPath = Resolve-ProjectEvidencePath $Root ([string](Get-HashtableValue $migration "proposal"))
        $resultPath = Resolve-ProjectEvidencePath $Root ([string](Get-HashtableValue $migration "result"))
        if ([IO.Path]::GetFileName($proposalPath) -cne "proposal.json" -or [IO.Path]::GetFileName($resultPath) -cne "result.json" -or
            -not [string]::Equals((Split-Path -Parent $proposalPath), (Split-Path -Parent $resultPath), [StringComparison]::OrdinalIgnoreCase)) { return ,$verified }
        $proposal = Read-Utf8Text $proposalPath | ConvertFrom-Json -AsHashtable -Depth 50 -ErrorAction Stop
        $result = Read-Utf8Text $resultPath | ConvertFrom-Json -AsHashtable -Depth 50 -ErrorAction Stop
        if ([int](Get-HashtableValue $proposal "schema_version") -ne 1 -or [int](Get-HashtableValue $result "schema_version") -ne 1) { return ,$verified }
        if ([string](Get-HashtableValue $proposal "source_language") -cne $sourceLanguage -or
            [string](Get-HashtableValue $proposal "target_language") -cne $targetLanguage -or
            [string](Get-HashtableValue $result "source_language") -cne $sourceLanguage -or
            [string](Get-HashtableValue $result "target_language") -cne $targetLanguage) { return ,$verified }

        $proposalProject = Get-NormalizedProjectRoot ([string](Get-HashtableValue $proposal "project"))
        $resultProject = Get-NormalizedProjectRoot ([string](Get-HashtableValue $result "project"))
        if (-not [string]::Equals($proposalProject, $Root, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals($resultProject, $Root, [StringComparison]::OrdinalIgnoreCase)) { return ,$verified }
        $resultProposalPath = Resolve-ProjectEvidencePath $Root ([string](Get-HashtableValue $result "proposal"))
        if (-not [string]::Equals($resultProposalPath, $proposalPath, [StringComparison]::OrdinalIgnoreCase)) { return ,$verified }

        $proposalActions = @((Get-HashtableValue $proposal "actions"))
        $resultActions = @((Get-HashtableValue $result "actions"))
        if ($proposalActions.Count -eq 0 -or $proposalActions.Count -ne $resultActions.Count) { return ,$verified }
        for ($index = 0; $index -lt $proposalActions.Count; $index++) {
            if ([string](Get-HashtableValue $proposalActions[$index] "relative_path") -cne [string](Get-HashtableValue $resultActions[$index] "relative_path") -or
                [string](Get-HashtableValue $proposalActions[$index] "action") -cne [string](Get-HashtableValue $resultActions[$index] "action")) { return ,$verified }
        }
        $proposalByPath = @{}
        foreach ($action in $proposalActions) {
            $relative = [string](Get-HashtableValue $action "relative_path")
            $canonicalRelative = if (Test-SafeRelativePath $relative) { ConvertTo-RelativePath $Root (Get-ProjectPath $Root $relative) } else { "" }
            if ($relative -cne $canonicalRelative -or $proposalByPath.ContainsKey($relative)) { return ,$verified }
            $proposalByPath[$relative] = $action
        }

        $resultByPath = @{}
        foreach ($action in $resultActions) {
            $relative = [string](Get-HashtableValue $action "relative_path")
            $canonicalRelative = if (Test-SafeRelativePath $relative) { ConvertTo-RelativePath $Root (Get-ProjectPath $Root $relative) } else { "" }
            if ($relative -cne $canonicalRelative -or $resultByPath.ContainsKey($relative) -or -not $proposalByPath.ContainsKey($relative)) { return ,$verified }
            if ([string](Get-HashtableValue $action "action") -cne [string](Get-HashtableValue $proposalByPath[$relative] "action")) { return ,$verified }
            $resultByPath[$relative] = $action
        }

        $pureActions = @("already-target-template", "replace-template", "add-target-template")
        foreach ($relative in @($proposalByPath.Keys | Sort-Object)) {
            $proposalAction = $proposalByPath[$relative]
            $resultAction = $resultByPath[$relative]
            $actionName = [string](Get-HashtableValue $proposalAction "action")
            if ([bool](Get-HashtableValue $proposalAction "manual_review")) {
                $manualReview[$relative] = $true
                continue
            }
            if ($actionName -cnotin $pureActions) { continue }
            $targetHash = [string](Get-HashtableValue $proposalAction "target_template_hash_sha256")
            $finalHash = [string](Get-HashtableValue $resultAction "final_hash_sha256")
            if ($targetHash -notmatch '^[a-f0-9]{64}$' -or $finalHash -cne $targetHash) { continue }
            $expectedResult = if ($actionName -ceq "already-target-template") { "preserved" } else { "written-target-template" }
            if ([string](Get-HashtableValue $resultAction "result") -cne $expectedResult) { continue }
            $currentPath = Get-ProjectPath $Root $relative
            if (-not (Test-Path -LiteralPath $currentPath -PathType Leaf)) { continue }
            # NOTE: language_migration.ps1 defines final_hash_sha256 over strict
            # UTF-8 text bytes without a BOM, so verification uses that existing
            # producer contract while the migration state digest still binds raw bytes.
            $currentHash = Get-Sha256Text (Read-Utf8Text $currentPath)
            if ($currentHash -ceq $finalHash) { $verified[$relative] = $true }
        }
    }
    catch {
        # NOTE: Missing, malformed, stale, or unsafe provenance grants no trust.
        $ManualReviewPaths.Value = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
        return ,[Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
    }
    return ,$verified
}

function Add-ScaffoldTransitionPlan {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Language,
        [AllowNull()][object]$Lock,
        [Parameter(Mandatory = $true)][object]$VerifiedLanguageTemplates,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.List[object]]$Actions,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.List[object]]$Human,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.List[string]]$TargetPaths
    )
    $legacyRoot = Get-LegacyScaffoldText $Language "AGENTS.md"
    $legacyAgent = Get-LegacyScaffoldText $Language ".agents/AGENTS.md"
    foreach ($relative in @("AGENTS.md", ".agents/README.md", ".agents/.gitignore")) {
        $TargetPaths.Add($relative)
        $full = Get-ProjectPath $Root $relative
        $target = Get-HashtableValue (Get-HashtableValue $Contract "files") $relative
        $targetContent = [string](Get-HashtableValue $target "content")
        if (-not (Test-Path -LiteralPath $full)) {
            Add-PlanAction $Actions "create" $relative @([string](Get-HashtableValue $target "source")) $targetContent "C33_SCAFFOLD_CREATED"
            continue
        }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            $Human.Add([ordered]@{ path = $relative; reason_code = "SCAFFOLD_PATH_CONFLICT" })
            continue
        }
        $current = Read-Utf8Text $full
        if ($current -ceq $targetContent) {
            Add-PlanAction $Actions "preserve" $relative @($relative) $null "C33_SCAFFOLD_PRESERVED"
        }
        elseif (($relative -ceq "AGENTS.md" -and $current -ceq $legacyRoot) -or (Test-RecordedLegacyScaffold $Lock $relative $current) -or $VerifiedLanguageTemplates.ContainsKey($relative)) {
            Add-PlanAction $Actions "change" $relative @($relative, [string](Get-HashtableValue $target "source")) $targetContent "LEGACY_ENTRYPOINT_REPLACED"
        }
        else {
            $Human.Add([ordered]@{ path = $relative; reason_code = "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED" })
        }
    }

    $legacyAgentPath = ".agents/AGENTS.md"
    $TargetPaths.Add($legacyAgentPath)
    $legacyAgentFull = Get-ProjectPath $Root $legacyAgentPath
    if (-not (Test-Path -LiteralPath $legacyAgentFull)) {
        Add-PlanAction $Actions "preserve" $legacyAgentPath @($legacyAgentPath) $null "LEGACY_AUTHORITY_ALREADY_ABSENT"
    }
    elseif (-not (Test-Path -LiteralPath $legacyAgentFull -PathType Leaf)) {
        $Human.Add([ordered]@{ path = $legacyAgentPath; reason_code = "SCAFFOLD_PATH_CONFLICT" })
    }
    else {
        $current = Read-Utf8Text $legacyAgentFull
        if ($current -ceq $legacyAgent -or (Test-RecordedLegacyScaffold $Lock $legacyAgentPath $current) -or $VerifiedLanguageTemplates.ContainsKey($legacyAgentPath)) {
            Add-PlanAction $Actions "remove" $legacyAgentPath @($legacyAgentPath) $null "LEGACY_PROJECT_AUTHORITY_RETIRED"
        }
        else {
            $Human.Add([ordered]@{ path = $legacyAgentPath; reason_code = "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED" })
        }
    }

    foreach ($relative in @(".agents", "docs")) {
        $TargetPaths.Add($relative)
        $full = Get-ProjectPath $Root $relative
        if (-not (Test-Path -LiteralPath $full)) {
            Add-PlanAction $Actions "create-directory" $relative @() $null "C33_CANONICAL_DIRECTORY_PARENT_CREATED"
        }
        elseif (Test-Path -LiteralPath $full -PathType Container) {
            Add-PlanAction $Actions "preserve-directory" $relative @($relative) $null "C33_CANONICAL_DIRECTORY_PARENT_PRESERVED"
        }
        else {
            $Human.Add([ordered]@{ path = $relative; reason_code = "SCAFFOLD_PATH_CONFLICT" })
        }
    }
    foreach ($relative in @(Get-HashtableValue $Contract "directories")) {
        $TargetPaths.Add([string]$relative)
        $full = Get-ProjectPath $Root ([string]$relative)
        if (-not (Test-Path -LiteralPath $full)) {
            Add-PlanAction $Actions "create-directory" ([string]$relative) @() $null "C33_CANONICAL_DIRECTORY_CREATED"
        }
        elseif (Test-Path -LiteralPath $full -PathType Container) {
            Add-PlanAction $Actions "preserve-directory" ([string]$relative) @([string]$relative) $null "C33_CANONICAL_DIRECTORY_PRESERVED"
        }
        else {
            $Human.Add([ordered]@{ path = [string]$relative; reason_code = "SCAFFOLD_PATH_CONFLICT" })
        }
    }
}

function Invoke-Analyze {
    param([Parameter(Mandatory = $true)][string]$Root)
    $reasons = [Collections.Generic.List[string]]::new()
    $human = [Collections.Generic.List[object]]::new()
    $actions = [Collections.Generic.List[object]]::new()
    $targetPaths = [Collections.Generic.List[string]]::new()
    if (Test-ReparsePointInScope $Root) { $reasons.Add("REPARSE_POINT_UNSUPPORTED") }

    $lockPath = Get-ProjectPath $Root ".agents/hub.lock.json"
    $lock = $null
    $language = $null
    $workspaceModel = $null
    $workspaceState = $null
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { $reasons.Add("HUB_LOCK_MISSING") }
    else {
        try { $lock = Read-Utf8Text $lockPath | ConvertFrom-Json -AsHashtable -Depth 50 -ErrorAction Stop }
        catch { $reasons.Add("HUB_LOCK_INVALID") }
        if ($null -ne $lock) {
            $language = [string](Get-HashtableValue $lock "project_language")
            $workspaceModel = [string](Get-HashtableValue $lock "workspace_model")
            $workspaceState = [string](Get-HashtableValue $lock "workspace_state")
            if ($language -notin @("en", "zh-CN")) { $reasons.Add("PROJECT_LANGUAGE_UNSUPPORTED") }
            if ($workspaceModel -ceq "c3.3") { $reasons.Add("WORKSPACE_ALREADY_C33") }
            elseif ($workspaceModel -notin @("legacy", "")) { $reasons.Add("WORKSPACE_MODEL_UNSUPPORTED") }
        }
    }

    $scaffoldContract = $null
    $verifiedLanguageTemplates = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
    $languageManualReviewPaths = [Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
    if ($language -in @("en", "zh-CN")) {
        try {
            $verifiedLanguageTemplates = Get-VerifiedLanguageMigrationTemplatePaths $Root $lock $language ([ref]$languageManualReviewPaths)
            $scaffoldContract = Get-C33ScaffoldContract $language
            Add-ScaffoldTransitionPlan $Root $language $lock $verifiedLanguageTemplates $scaffoldContract $actions $human $targetPaths
        }
        catch { $reasons.Add([string]$_.Exception.Message) }
    }

    $workSources = [Collections.Generic.List[object]]::new()
    foreach ($relative in @(".agents/process.txt", ".agents/plan.md")) {
        $full = Get-ProjectPath $Root $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        try { $text = Read-Utf8Text $full }
        catch { $reasons.Add("LEGACY_SOURCE_INVALID_UTF8"); $human.Add([ordered]@{ path = $relative; reason_code = "INVALID_UTF8" }); continue }
        $unfinished = $text -match '(?im)^\s*(?:[-*]\s*)?(?:status\s*[:：]\s*)?(?:active|in[- ]progress|pending|paused|blocked)\b|\b(?:TODO|FIXME|next step|current work|current task|this session|unfinished)\b|^\s*[-*]\s*\[ \]'
        if (Test-TemplateText $text) { Add-PlanAction $actions "preserve" $relative @($relative) $null "TEMPLATE_PRESERVED_NON_AUTHORITY" }
        elseif ($unfinished) { $workSources.Add([ordered]@{ path = $relative; text = $text }) }
        elseif (-not [string]::IsNullOrWhiteSpace($text)) { $human.Add([ordered]@{ path = $relative; reason_code = "LEGACY_WORK_NOT_DETERMINISTIC" }) }
    }
    if ($workSources.Count -gt 0) {
        $target = ".agents/work/legacy-work.md"; $targetPaths.Add($target)
        if (Test-Path -LiteralPath (Get-ProjectPath $Root $target)) { $human.Add([ordered]@{ path = $target; reason_code = "TARGET_CONFLICT" }) }
        else {
            Add-PlanAction $actions "create" $target @($workSources.path) (New-WorkContent @($workSources.ToArray())) "LEGACY_WORK_PROMOTED"
            foreach ($source in @($workSources.ToArray())) { Add-PlanAction $actions "remove" $source.path @($source.path) $null "LEGACY_SOURCE_RETIRED" }
        }
    }

    $unsupportedLegacyRoot = Get-ProjectPath $Root ".agents/legacy"
    if (Test-Path -LiteralPath $unsupportedLegacyRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $unsupportedLegacyRoot -File -Force -Recurse | Sort-Object FullName)) {
            $human.Add([ordered]@{ path = ConvertTo-RelativePath $Root $file.FullName; reason_code = "LEGACY_SURFACE_UNSUPPORTED" })
        }
    }

    $contextCandidates = [Collections.Generic.List[string]]::new()
    $notes = Get-ProjectPath $Root ".agents/notes.md"
    if (Test-Path -LiteralPath $notes -PathType Leaf) { $contextCandidates.Add(".agents/notes.md") }
    $contextRoot = Get-ProjectPath $Root ".agents/context"
    if (Test-Path -LiteralPath $contextRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $contextRoot -File -Filter "*.md" -Recurse -Force)) {
            $relative = ConvertTo-RelativePath $Root $file.FullName
            $contextCandidates.Add($relative)
        }
    }
    foreach ($relative in @($contextCandidates.ToArray() | Sort-Object -Unique)) {
        $text = Read-Utf8Text (Get-ProjectPath $Root $relative)
        if ($languageManualReviewPaths.ContainsKey($relative)) { $human.Add([ordered]@{ path = $relative; reason_code = "CONTEXT_MARKERS_MISSING" }); continue }
        if ($verifiedLanguageTemplates.ContainsKey($relative)) { Add-PlanAction $actions "preserve" $relative @($relative) $null "LANGUAGE_MIGRATION_TEMPLATE_PRESERVED_NON_AUTHORITY"; continue }
        if (Test-ContextNonAuthorityDocument $relative $text) { Add-PlanAction $actions "preserve" $relative @($relative) $null "TEMPLATE_PRESERVED_NON_AUTHORITY"; continue }
        if (Test-ContextAuthorityAmbiguous $relative $text) { $human.Add([ordered]@{ path = $relative; reason_code = "CONTEXT_MARKERS_MISSING" }); continue }
        $filenameOnlyAmbiguous = Test-ContextFilenameAmbiguous $relative
        $summary = Get-MarkdownSection $text @("Summary")
        $keywordsText = Get-MarkdownSection $text @("Keywords")
        $verified = Get-MarkdownSection $text @("Verified Facts", "Verified")
        if ($relative -ceq ".agents/notes.md" -and -not [string]::IsNullOrWhiteSpace($verified)) {
            $summary = "Verified legacy project facts migrated from notes."
            $keywords = @("legacy", "verified-facts")
        }
        elseif (-not [string]::IsNullOrWhiteSpace($summary) -and -not [string]::IsNullOrWhiteSpace($keywordsText)) {
            $keywords = @($keywordsText -split '[,\r\n]+' | ForEach-Object { ($_ -replace '^\s*[-*]\s*', '').Trim() } | Where-Object { $_ })
        }
        # NOTE: Filename tokens are ambiguity signals only. Stable Context
        # markers above remain authoritative; token-only candidates stay human.
        elseif ($filenameOnlyAmbiguous) { $human.Add([ordered]@{ path = $relative; reason_code = "CONTEXT_MARKERS_MISSING" }); continue }
        else { $human.Add([ordered]@{ path = $relative; reason_code = "CONTEXT_MARKERS_MISSING" }); continue }
        $stem = Get-SafeId ([IO.Path]::GetFileNameWithoutExtension($relative)) "context"
        $id = "legacy-$stem-$((Get-Sha256Text $relative).Substring(0, 8))"
        $target = ".agents/context/$id.md"; $targetPaths.Add($target)
        if ($target -cne $relative -and (Test-Path -LiteralPath (Get-ProjectPath $Root $target))) { $human.Add([ordered]@{ path = $target; reason_code = "TARGET_CONFLICT" }); continue }
        $content = New-ContextContent $id (Get-MarkdownTitle $text "Legacy context") $summary $keywords $relative $text.Trim()
        Add-PlanAction $actions $(if ($target -ceq $relative) { "change" } else { "create" }) $target @($relative) $content "LEGACY_CONTEXT_PROMOTED"
        if ($target -cne $relative) { Add-PlanAction $actions "remove" $relative @($relative) $null "LEGACY_SOURCE_RETIRED" }
    }

    $commandsRoot = Get-ProjectPath $Root ".agents/commands"
    if (Test-Path -LiteralPath $commandsRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $commandsRoot -File -Filter "*.md" -Recurse -Force | Sort-Object FullName)) {
            $relative = ConvertTo-RelativePath $Root $file.FullName
            if ($file.Name -ieq "README.md") { continue }
            $text = Read-Utf8Text $file.FullName
            $purpose = Get-MarkdownSection $text @("Purpose", "用途")
            $steps = Get-MarkdownSection $text @("Steps", "Commands", "Command", "步骤", "命令")
            $boundary = Get-MarkdownSection $text @("Validation", "Safety", "Side Effects", "验证", "安全边界", "副作用")
            if ((Test-TemplateText $text) -or [string]::IsNullOrWhiteSpace($purpose) -or [string]::IsNullOrWhiteSpace($steps) -or [string]::IsNullOrWhiteSpace($boundary)) { $human.Add([ordered]@{ path = $relative; reason_code = "PROCEDURE_MARKERS_MISSING" }); continue }
            $stem = Get-SafeId $file.BaseName "procedure"; $id = "legacy-$stem-$((Get-Sha256Text $relative).Substring(0, 8))"
            $target = ".agents/procedures/$id.md"; $targetPaths.Add($target)
            if (Test-Path -LiteralPath (Get-ProjectPath $Root $target)) { $human.Add([ordered]@{ path = $target; reason_code = "TARGET_CONFLICT" }); continue }
            Add-PlanAction $actions "create" $target @($relative) (New-ProcedureContent $id (Get-MarkdownTitle $text "Legacy procedure") $purpose $relative $text.Trim()) "LEGACY_PROCEDURE_PROMOTED"
            Add-PlanAction $actions "remove" $relative @($relative) $null "LEGACY_SOURCE_RETIRED"
        }
    }

    $specRoot = Get-ProjectPath $Root "docs/specs"
    if (Test-Path -LiteralPath $specRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $specRoot -File -Filter "spec.md" -Recurse -Force | Sort-Object FullName)) {
            $relative = ConvertTo-RelativePath $Root $file.FullName
            if ($relative -cmatch '^docs/specs/(?<id>[a-z0-9]+(?:-[a-z0-9]+)*)/spec\.md$') {
                $id = $Matches.id
            }
            elseif ($relative -cmatch '^docs/specs/archive/.+/spec\.md$') {
                # NOTE: Nested archive Specs remain evidence-bound historical bytes, never canonical authority.
                continue
            }
            else {
                $human.Add([ordered]@{ path = $relative; reason_code = "SPEC_PATH_UNSUPPORTED" })
                continue
            }
            $text = Read-Utf8Text $file.FullName
            if ($text -match '(?ms)^---\s*\r?\n.*?^schema:\s*agent-ecosystem/spec/v1\s*$') { Add-PlanAction $actions "preserve" $relative @($relative) $null "CANONICAL_SPEC_PRESERVED"; continue }
            $scope = Get-MarkdownSection $text @("Scope", "Goals", "目标", "范围") -AllowNumericPrefix
            $nonGoals = Get-MarkdownSection $text @("Non-Goals", "Non Goals", "非目标") -AllowNumericPrefix
            $acceptance = Get-MarkdownSection $text @("Acceptance", "Acceptance Criteria", "Acceptance / Evidence", "验收", "验收标准") -AllowNumericPrefix
            $design = Get-MarkdownSection $text @("Design", "Decisions", "Constraints", "Proposed Approach", "设计", "决策", "约束", "方案") -AllowNumericPrefix
            $missingSpecSections = @(@($scope, $nonGoals, $acceptance, $design) | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count
            if ((Test-TemplateText $text) -or $missingSpecSections -gt 0) { $human.Add([ordered]@{ path = $relative; reason_code = "SPEC_MARKERS_MISSING" }); continue }

            $titleMatches = @(Get-LegacyMetadataMatches $text "Title")
            $slugMatches = @(Get-LegacyMetadataMatches $text "Slug")
            $statusMatches = @(Get-LegacyMetadataMatches $text "Status")
            if ($titleMatches.Count -gt 1 -or $slugMatches.Count -gt 1 -or $statusMatches.Count -gt 1) {
                $human.Add([ordered]@{ path = $relative; reason_code = "SPEC_METADATA_AMBIGUOUS" })
                continue
            }
            $legacySlug = if ($slugMatches.Count -eq 1) { [string]$slugMatches[0].Groups['value'].Value.Trim() } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($legacySlug) -and $legacySlug -cne $id) {
                $human.Add([ordered]@{ path = $relative; reason_code = "SPEC_SLUG_MISMATCH" })
                continue
            }
            $legacyStatus = if ($statusMatches.Count -eq 1) { [string]$statusMatches[0].Groups['value'].Value.Trim() } else { "" }
            $canonicalStatus = if ([string]::IsNullOrWhiteSpace($legacyStatus)) { "draft" } else { Convert-LegacySpecStatus $legacyStatus }
            if ([string]::IsNullOrWhiteSpace($canonicalStatus)) {
                $human.Add([ordered]@{ path = $relative; reason_code = "SPEC_STATUS_REQUIRES_DISPOSITION" })
                continue
            }
            $title = Get-MarkdownTitle $text "Legacy specification"
            if ($title -ceq "Work Spec" -and $titleMatches.Count -eq 1) {
                $metadataTitle = [string]$titleMatches[0].Groups['value'].Value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($metadataTitle)) { $title = $metadataTitle }
            }
            $summary = ($scope -split '\r?\n')[0].Trim().TrimStart('-', '*').Trim()
            Add-PlanAction $actions "change" $relative @($relative) (New-SpecContent $id $title $canonicalStatus $summary $text) "LEGACY_SPEC_PROMOTED"
            $targetPaths.Add($relative)
        }
    }

    if ($null -ne $lock -and $workspaceModel -ne "c3.3" -and $language -in @("en", "zh-CN")) {
        $lock["workspace_model"] = "c3.3"; $lock["workspace_state"] = "dormant"
        $lock["workspace_roots"] = @(".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")
        $automaticNonAuthorityEntries = @($actions.ToArray() | Where-Object {
                [string](Get-HashtableValue $_ "action") -ceq "preserve" -and
                [string](Get-HashtableValue $_ "path") -cmatch '^\.agents/context/.+\.md$' -and
                [string](Get-HashtableValue $_ "reason_code") -in @("TEMPLATE_PRESERVED_NON_AUTHORITY", "LANGUAGE_MIGRATION_TEMPLATE_PRESERVED_NON_AUTHORITY")
            } | ForEach-Object {
                $entryPath = [string](Get-HashtableValue $_ "path")
                $entryState = Get-PathState $Root $entryPath
                [ordered]@{ path = $entryPath; sha256 = [string]$entryState.sha256; evidence_kind = "deterministic-template"; evidence_sha256 = [string]$entryState.sha256 }
            })
        if ($automaticNonAuthorityEntries.Count -gt 0) {
            $lock["migration_non_authority"] = [ordered]@{ schema_version = 1; entries = [object[]]@($automaticNonAuthorityEntries | Sort-Object path) }
        }
        $lockContent = ($lock | ConvertTo-Json -Depth 50) + "`n"
        Add-PlanAction $actions "change" ".agents/hub.lock.json" @(".agents/hub.lock.json") $lockContent "WORKSPACE_METADATA_MIGRATED"
        $targetPaths.Add(".agents/hub.lock.json")
    }
    if ($human.Count -gt 0) { $reasons.Add("HUMAN_DISPOSITION_REQUIRED") }
    if (@($actions | Where-Object action -in @("create", "change") | Where-Object path -ne ".agents/hub.lock.json").Count -eq 0) { $reasons.Add("NO_MIGRATABLE_AUTHORITY") }

    $sortedActions = @($actions.ToArray() | Sort-Object path, action, reason_code)
    $additional = @($targetPaths.ToArray() + @(".agents/process.txt", ".agents/plan.md", ".agents/notes.md", ".agents/hub.lock.json") | Sort-Object -Unique)
    $files = @(Get-StateSnapshot $Root $additional)
    $stateDigest = Get-StateDigest $files
    $planCore = [ordered]@{ sentinel_updated = $script:MigrationSentinel; sentinel_source = "deterministic-migration-sentinel-v1"; actions = $sortedActions }
    $planDigest = Get-Sha256Text (ConvertTo-StableJson $planCore)
    $migrationRevision = Get-Sha256Text ("$($script:MigrationRevisionVersion)`n$stateDigest`n$planDigest")
    $backupId = $migrationRevision.Substring(0, 24)
    $reasonArray = @($reasons.ToArray() | Sort-Object -Unique)
    $eligible = ($reasonArray.Count -eq 0)
    return [ordered]@{
        schema_version = $script:MigrationSchemaVersion; operation = "analyze"; status = $(if ($eligible) { "eligible" } else { "blocked" }); eligible = $eligible
        reason_codes = $reasonArray; migration_revision = $migrationRevision
        evidence = [ordered]@{ evidence_version = 1; project_root = $Root; project_language = $language; workspace_model = $workspaceModel; workspace_state = $workspaceState; scaffold_contract = $(if ($null -eq $scaffoldContract) { $null } else { [ordered]@{ source = $scaffoldContract.source; files = @($scaffoldContract.files.Keys | Sort-Object | ForEach-Object { [ordered]@{ path = $_; sha256 = $scaffoldContract.files[$_].sha256 } }); directories = @($scaffoldContract.directories) } }); files = $files; state_digest = $stateDigest }
        plan = [ordered]@{ plan_version = 1; plan_digest = $planDigest; sentinel_updated = $script:MigrationSentinel; sentinel_source = "deterministic-migration-sentinel-v1"; actions = $sortedActions; create = @($sortedActions | Where-Object action -eq "create" | ForEach-Object path); create_directories = @($sortedActions | Where-Object action -eq "create-directory" | ForEach-Object path); change = @($sortedActions | Where-Object action -eq "change" | ForEach-Object path); remove = @($sortedActions | Where-Object action -eq "remove" | ForEach-Object path); preserve = @($sortedActions | Where-Object action -in @("preserve", "preserve-directory") | ForEach-Object path) }
        human_disposition = @($human.ToArray() | Sort-Object path, reason_code)
        backup_requirements = [ordered]@{ backup_id = $backupId; path = ".agents/.migration-backups/$backupId/"; project_owned = $true; offline = $true; retained_after_rollback = $true; complete_pre_state_required = $true }
    }
}

function Assert-StateMatches {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][object[]]$Expected, [switch]$ExactScope)
    $additional = @($Expected | ForEach-Object { [string]$_.path })
    $actual = @(Get-StateSnapshot $Root $additional)
    if ($ExactScope -and (Get-StateDigest $actual) -cne (Get-StateDigest $Expected)) { throw "STATE_CONFLICT" }
    $actualByPath = @{}; foreach ($item in $actual) { $actualByPath[[string]$item.path] = $item }
    foreach ($expectedItem in $Expected) {
        $path = [string]$expectedItem.path
        if (-not $actualByPath.ContainsKey($path)) { throw "STATE_CONFLICT" }
        $actualItem = $actualByPath[$path]
        if ([string]$actualItem.presence -cne [string]$expectedItem.presence -or [string]$actualItem.sha256 -cne [string]$expectedItem.sha256 -or [long]$actualItem.length -ne [long]$expectedItem.length) { throw "STATE_CONFLICT" }
    }
}

function Assert-InterruptedApplyStateSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$PreState,
        [Parameter(Mandatory = $true)][object[]]$PlannedPostState,
        [Parameter(Mandatory = $true)][string[]]$ManagedPaths
    )
    $expectedPaths = @($PreState | ForEach-Object { [string](Get-HashtableValue $_ "path") })
    $actual = @(Get-StateSnapshot $Root $expectedPaths)
    $expectedPathSet = @($expectedPaths | Sort-Object -Unique)
    $actualPathSet = @($actual | ForEach-Object { [string](Get-HashtableValue $_ "path") } | Sort-Object -Unique)
    if (($expectedPathSet -join "`n") -cne ($actualPathSet -join "`n")) { throw "STATE_CONFLICT" }

    $preByPath = @{}; foreach ($item in $PreState) { $preByPath[[string](Get-HashtableValue $item "path")] = $item }
    $postByPath = @{}; foreach ($item in $PlannedPostState) { $postByPath[[string](Get-HashtableValue $item "path")] = $item }
    $managed = @{}; foreach ($path in $ManagedPaths) { $managed[[string]$path] = $true }
    foreach ($item in $actual) {
        $path = [string](Get-HashtableValue $item "path")
        if (-not $preByPath.ContainsKey($path) -or -not $postByPath.ContainsKey($path)) { throw "STATE_CONFLICT" }
        if ($managed.ContainsKey($path)) {
            if (-not (Test-StateItemEqual $item $preByPath[$path]) -and -not (Test-StateItemEqual $item $postByPath[$path])) { throw "STATE_CONFLICT" }
        }
        elseif (-not (Test-StateItemEqual $item $preByPath[$path])) { throw "STATE_CONFLICT" }
    }
}

function Write-ExactText {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)
    $path = Get-ProjectPath $Root $RelativePath
    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    [IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
}

function Invoke-PlanMutations {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][object[]]$Actions)
    foreach ($action in $Actions) {
        $kind = [string](Get-HashtableValue $action "action")
        $relative = [string](Get-HashtableValue $action "path")
        if ($kind -in @("create", "change")) { Write-ExactText $Root $relative ([string](Get-HashtableValue $action "content")) }
        elseif ($kind -ceq "create-directory") {
            $path = Get-ProjectPath $Root $relative
            if (-not (Test-Path -LiteralPath $path)) { [IO.Directory]::CreateDirectory($path) | Out-Null }
        }
        elseif ($kind -ceq "remove") {
            $path = Get-ProjectPath $Root $relative
            if (Test-Path -LiteralPath $path -PathType Leaf) { [IO.File]::Delete($path) }
        }
    }
}

function Assert-ResolvedPlanWorkspaceValid {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][object[]]$Actions)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $stagingRoot = [IO.Path]::GetFullPath((Join-Path $tempBase ("agent-ecosystem-disposition-validation-{0}" -f [Guid]::NewGuid().ToString("N"))))
    $tempPrefix = $tempBase + [IO.Path]::DirectorySeparatorChar
    if (-not $stagingRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "DISPOSITION_CONTENT_VALIDATION_UNAVAILABLE" }
    [IO.Directory]::CreateDirectory($stagingRoot) | Out-Null
    try {
        foreach ($relative in @(Get-MigrationRelevantPaths $Root)) {
            $source = Get-ProjectPath $Root $relative
            $destination = Get-ProjectPath $stagingRoot $relative
            $item = Get-Item -LiteralPath $source -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "REPARSE_POINT_UNSUPPORTED" }
            if ($item.PSIsContainer) { [IO.Directory]::CreateDirectory($destination) | Out-Null }
            else {
                $parent = Split-Path -Parent $destination
                if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
                [IO.File]::Copy($source, $destination, $false)
            }
        }
        Invoke-PlanMutations $stagingRoot $Actions
        if ((Invoke-MigratedWorkspaceCheck $stagingRoot) -cne "PASS") { throw "MIGRATED_WORKSPACE_INVALID" }
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
            $resolvedStaging = [IO.Path]::GetFullPath($stagingRoot)
            if (-not $resolvedStaging.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "DISPOSITION_CONTENT_VALIDATION_UNAVAILABLE" }
            [IO.Directory]::Delete($resolvedStaging, $true)
        }
    }
}

function Invoke-MigratedWorkspaceCheck {
    param([Parameter(Mandatory = $true)][string]$Root)
    $runtimeRoot = Split-Path -Parent $PSScriptRoot
    $workspaceScript = Join-Path $runtimeRoot "skills/project-workspace/scripts/project-workspace.ps1"
    if (-not (Test-Path -LiteralPath $workspaceScript -PathType Leaf)) { throw "WORKSPACE_CHECK_UNAVAILABLE" }
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $global:LASTEXITCODE = 0
    $output = @(& $pwsh -NoProfile -NonInteractive -File $workspaceScript -Operation check -ProjectRoot $Root -Json 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw "MIGRATED_WORKSPACE_INVALID" }
    try { $payload = (@($output) -join "`n") | ConvertFrom-Json -Depth 100 -ErrorAction Stop }
    catch { throw "MIGRATED_WORKSPACE_INVALID" }
    if ([string](Get-HashtableValue $payload "status") -cne "PASS") { throw "MIGRATED_WORKSPACE_INVALID" }
    return "PASS"
}

function Invoke-Apply {
    param([Parameter(Mandatory = $true)][string]$Root)
    if (-not $ConfirmMigration.IsPresent) { throw "CONFIRMATION_REQUIRED" }
    if ([string]::IsNullOrWhiteSpace($AnalyzeEvidence)) { throw "ANALYZE_EVIDENCE_REQUIRED" }
    try { $held = $AnalyzeEvidence | ConvertFrom-Json -AsHashtable -Depth 100 -ErrorAction Stop }
    catch { throw "ANALYZE_EVIDENCE_INVALID" }
    if ([int](Get-HashtableValue $held "schema_version") -ne 1 -or [string](Get-HashtableValue $held "operation") -cne "analyze") { throw "ANALYZE_EVIDENCE_INVALID" }
    if (-not [bool](Get-HashtableValue $held "eligible")) { throw "ANALYZE_EVIDENCE_INELIGIBLE" }
    $heldReviewed = Get-HashtableValue $held "reviewed_disposition"
    if ($null -ne $heldReviewed -and [string]::IsNullOrWhiteSpace($DispositionEvidence)) { throw "DISPOSITION_EVIDENCE_REQUIRED" }
    $freshCandidate = Invoke-Analyze $Root
    $fresh = if ([string]::IsNullOrWhiteSpace($DispositionEvidence)) { $freshCandidate } else { Resolve-ReviewedDisposition $Root $freshCandidate $DispositionEvidence }
    if (-not $fresh.eligible -or [string]$fresh.migration_revision -cne [string](Get-HashtableValue $held "migration_revision") -or [string]$fresh.evidence.state_digest -cne [string](Get-HashtableValue (Get-HashtableValue $held "evidence") "state_digest") -or [string]$fresh.plan.plan_digest -cne [string](Get-HashtableValue (Get-HashtableValue $held "plan") "plan_digest")) { throw "ANALYZE_EVIDENCE_STALE" }
    $heldPlan = Get-HashtableValue $held "plan"
    if ((ConvertTo-StableJson $heldPlan) -cne (ConvertTo-StableJson $fresh.plan)) { throw "ANALYZE_PLAN_MISMATCH" }
    Assert-StateMatches $Root @($fresh.evidence.files)
    $backupIdValue = [string]$fresh.backup_requirements.backup_id
    $backupRelative = ".agents/.migration-backups/$backupIdValue"
    $backupRoot = Get-ProjectPath $Root $backupRelative
    if (Test-Path -LiteralPath $backupRoot) { throw "BACKUP_ALREADY_EXISTS" }
    [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
    $preState = @(Get-StateSnapshot $Root @($fresh.evidence.files.path) -IncludeContent)
    $plannedPostState = @(Get-PlannedPostState $preState @($fresh.plan.actions))
    $managedPaths = @($fresh.plan.actions | Where-Object { [string]$_.action -in @("create", "create-directory", "change", "remove") } | ForEach-Object { [string]$_.path } | Sort-Object -Unique)
    $reviewedDispositionDigest = [string](Get-HashtableValue (Get-HashtableValue $fresh "reviewed_disposition") "reviewed_disposition_digest")
    $manifest = [ordered]@{ schema_version = 1; backup_kind = "c3.3-project-migration"; backup_id = $backupIdValue; migration_revision = $fresh.migration_revision; project_language = $fresh.evidence.project_language; pre_state = $preState; plan_digest = $fresh.plan.plan_digest; reviewed_disposition_digest = $reviewedDispositionDigest }
    $manifestText = (ConvertTo-StableJson $manifest) + "`n"
    [IO.File]::WriteAllText((Join-Path $backupRoot "manifest.json"), $manifestText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $backupRoot "manifest.sha256"), (Get-Sha256Text $manifestText) + "`n", [Text.UTF8Encoding]::new($false))
    $completion = [ordered]@{ schema_version = 1; record_kind = "c3.3-project-migration-complete"; backup_id = $backupIdValue; migration_revision = $fresh.migration_revision; plan_digest = $fresh.plan.plan_digest; reviewed_disposition_digest = $reviewedDispositionDigest; expected_post_state_digest = Get-StateDigest $plannedPostState }
    $completionText = (ConvertTo-StableJson $completion) + "`n"
    $record = [ordered]@{ schema_version = 1; record_kind = "c3.3-project-migration-apply"; apply_state = "prepared"; backup_id = $backupIdValue; migration_revision = $fresh.migration_revision; plan_digest = $fresh.plan.plan_digest; reviewed_disposition_digest = $reviewedDispositionDigest; managed_paths = $managedPaths; expected_post_state = $plannedPostState; expected_post_state_digest = $completion.expected_post_state_digest; completion_marker_sha256 = Get-Sha256Text $completionText }
    $recordText = (ConvertTo-StableJson $record) + "`n"
    [IO.File]::WriteAllText((Join-Path $backupRoot "apply-record.json"), $recordText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $backupRoot "apply-record.sha256"), (Get-Sha256Text $recordText) + "`n", [Text.UTF8Encoding]::new($false))
    $persistedManifest = Read-Utf8Text (Join-Path $backupRoot "manifest.json")
    $persistedRecord = Read-Utf8Text (Join-Path $backupRoot "apply-record.json")
    if ((Get-Sha256Text $persistedManifest) -cne (Read-Utf8Text (Join-Path $backupRoot "manifest.sha256")).Trim() -or (Get-Sha256Text $persistedRecord) -cne (Read-Utf8Text (Join-Path $backupRoot "apply-record.sha256")).Trim()) { throw "ROLLBACK_EVIDENCE_INTEGRITY_FAILED" }
    try { $persistedManifestObject = $persistedManifest | ConvertFrom-Json -AsHashtable -Depth 100 -ErrorAction Stop; $persistedRecordObject = $persistedRecord | ConvertFrom-Json -AsHashtable -Depth 100 -ErrorAction Stop }
    catch { throw "ROLLBACK_EVIDENCE_INTEGRITY_FAILED" }
    if ([string](Get-HashtableValue $persistedManifestObject "backup_id") -cne $backupIdValue -or [string](Get-HashtableValue $persistedRecordObject "backup_id") -cne $backupIdValue -or [string](Get-HashtableValue $persistedRecordObject "expected_post_state_digest") -cne [string]$completion.expected_post_state_digest) { throw "ROLLBACK_EVIDENCE_INTEGRITY_FAILED" }
    Invoke-PlanMutations $Root @($fresh.plan.actions)
    # Re-read the complete Analyze evidence scope so absent legacy/scaffold
    # paths remain part of the exact planned post-state comparison.
    $postState = @(Get-StateSnapshot $Root @($fresh.evidence.files.path))
    foreach ($action in @($fresh.plan.actions | Where-Object action -in @("create", "change"))) {
        $actual = $postState | Where-Object { [string]$_.path -ceq [string]$action.path } | Select-Object -First 1
        if ($null -eq $actual -or [string]$actual.sha256 -cne [string]$action.expected_sha256) {
            throw "APPLY_VERIFICATION_FAILED"
        }
    }
    foreach ($action in @($fresh.plan.actions | Where-Object action -eq "remove")) {
        $actual = $postState | Where-Object { [string]$_.path -ceq [string]$action.path } | Select-Object -First 1
        if ($null -eq $actual -or [string]$actual.presence -cne "absent") { throw "APPLY_VERIFICATION_FAILED" }
    }
    foreach ($action in @($fresh.plan.actions | Where-Object action -eq "create-directory")) {
        $actual = $postState | Where-Object { [string]$_.path -ceq [string]$action.path } | Select-Object -First 1
        if ($null -eq $actual -or [string]$actual.presence -cne "directory") { throw "APPLY_VERIFICATION_FAILED" }
    }
    if ((Get-StateDigest $postState) -cne [string]$record.expected_post_state_digest) { throw "APPLY_VERIFICATION_FAILED" }
    $workspaceCheck = Invoke-MigratedWorkspaceCheck $Root
    $completionTemp = Join-Path $backupRoot "apply-complete.tmp"
    $completionPath = Join-Path $backupRoot "apply-complete.json"
    [IO.File]::WriteAllText($completionTemp, $completionText, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($completionTemp, $completionPath)
    return [ordered]@{ schema_version = 1; operation = "apply"; status = "applied"; reason_codes = @(); migration_revision = $fresh.migration_revision; reviewed_disposition_digest = $reviewedDispositionDigest; backup_id = $backupIdValue; backup_path = "$backupRelative/"; backup_before_mutation = $true; workspace_check = $workspaceCheck; expected_post_state_digest = $record.expected_post_state_digest }
}

function Remove-EmptyMigrationDirectories {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$CreatedPaths)
    $directories = @($CreatedPaths | ForEach-Object { Split-Path -Parent (Get-ProjectPath $Root $_) } | Sort-Object Length -Descending -Unique)
    foreach ($directory in $directories) {
        if ($directory -eq $Root -or -not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        if (@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) { [IO.Directory]::Delete($directory) }
    }
}

function Invoke-Rollback {
    param([Parameter(Mandatory = $true)][string]$Root)
    if (-not $ConfirmRollback.IsPresent) { throw "CONFIRMATION_REQUIRED" }
    if ([string]::IsNullOrWhiteSpace($BackupId) -or $BackupId -cnotmatch '^[0-9a-f]{24}$') { throw "BACKUP_ID_INVALID" }
    $backupRelative = ".agents/.migration-backups/$BackupId"; $backupRoot = Get-ProjectPath $Root $backupRelative
    $manifestPath = Join-Path $backupRoot "manifest.json"; $hashPath = Join-Path $backupRoot "manifest.sha256"; $recordPath = Join-Path $backupRoot "apply-record.json"; $recordHashPath = Join-Path $backupRoot "apply-record.sha256"; $completionPath = Join-Path $backupRoot "apply-complete.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $hashPath -PathType Leaf) -or -not (Test-Path -LiteralPath $recordPath -PathType Leaf) -or -not (Test-Path -LiteralPath $recordHashPath -PathType Leaf)) { throw "BACKUP_INCOMPLETE" }
    $manifestText = Read-Utf8Text $manifestPath; $expectedManifestHash = (Read-Utf8Text $hashPath).Trim()
    if ((Get-Sha256Text $manifestText) -cne $expectedManifestHash) { throw "BACKUP_INTEGRITY_FAILED" }
    $recordText = Read-Utf8Text $recordPath; $expectedRecordHash = (Read-Utf8Text $recordHashPath).Trim()
    if ((Get-Sha256Text $recordText) -cne $expectedRecordHash) { throw "BACKUP_INTEGRITY_FAILED" }
    try { $manifest = $manifestText | ConvertFrom-Json -AsHashtable -Depth 100 -ErrorAction Stop; $record = $recordText | ConvertFrom-Json -AsHashtable -Depth 100 -ErrorAction Stop }
    catch { throw "BACKUP_INVALID" }
    if ([string](Get-HashtableValue $manifest "backup_id") -cne $BackupId -or [string](Get-HashtableValue $record "backup_id") -cne $BackupId -or [string](Get-HashtableValue $manifest "migration_revision") -cne [string](Get-HashtableValue $record "migration_revision") -or [string](Get-HashtableValue $manifest "plan_digest") -cne [string](Get-HashtableValue $record "plan_digest") -or [string](Get-HashtableValue $manifest "reviewed_disposition_digest") -cne [string](Get-HashtableValue $record "reviewed_disposition_digest")) { throw "APPLY_IDENTITY_MISMATCH" }
    $preState = @(Get-HashtableValue $manifest "pre_state")
    $postState = @(Get-HashtableValue $record "expected_post_state")
    $completedApply = Test-Path -LiteralPath $completionPath -PathType Leaf
    if ($completedApply) {
        $completionText = Read-Utf8Text $completionPath
        if ((Get-Sha256Text $completionText) -cne [string](Get-HashtableValue $record "completion_marker_sha256")) { throw "BACKUP_INTEGRITY_FAILED" }
        try { $completion = $completionText | ConvertFrom-Json -AsHashtable -Depth 50 -ErrorAction Stop }
        catch { throw "BACKUP_INTEGRITY_FAILED" }
        if ([string](Get-HashtableValue $completion "backup_id") -cne $BackupId -or [string](Get-HashtableValue $completion "migration_revision") -cne [string](Get-HashtableValue $record "migration_revision") -or [string](Get-HashtableValue $completion "reviewed_disposition_digest") -cne [string](Get-HashtableValue $record "reviewed_disposition_digest") -or [string](Get-HashtableValue $completion "expected_post_state_digest") -cne [string](Get-HashtableValue $record "expected_post_state_digest")) { throw "APPLY_IDENTITY_MISMATCH" }
        Assert-StateMatches $Root $postState -ExactScope
    }
    else {
        Assert-InterruptedApplyStateSafe $Root $preState $postState @((Get-HashtableValue $record "managed_paths"))
    }
    foreach ($item in $preState) {
        if ([string](Get-HashtableValue $item "presence") -cne "file") { continue }
        try { $bytes = [Convert]::FromBase64String([string](Get-HashtableValue $item "content_base64")) }
        catch { throw "BACKUP_INTEGRITY_FAILED" }
        if ((Get-Sha256Bytes $bytes) -cne [string](Get-HashtableValue $item "sha256") -or $bytes.Length -ne [long](Get-HashtableValue $item "length")) { throw "BACKUP_INTEGRITY_FAILED" }
    }
    foreach ($item in $preState) {
        $path = [string](Get-HashtableValue $item "path"); $presence = [string](Get-HashtableValue $item "presence")
        $full = Get-ProjectPath $Root $path
        if ($presence -ceq "file") {
            $bytes = [Convert]::FromBase64String([string](Get-HashtableValue $item "content_base64"))
            $parent = Split-Path -Parent $full; if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
            [IO.File]::WriteAllBytes($full, $bytes)
        }
        elseif ($presence -ceq "directory") {
            if (-not (Test-Path -LiteralPath $full)) { [IO.Directory]::CreateDirectory($full) | Out-Null }
            elseif (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "STATE_CONFLICT" }
        }
        elseif (Test-Path -LiteralPath $full -PathType Leaf) { [IO.File]::Delete($full) }
    }
    $preByPath = @{}
    foreach ($item in $preState) { $preByPath[[string](Get-HashtableValue $item "path")] = $item }
    $createdPaths = @($postState | Where-Object {
            $path = [string](Get-HashtableValue $_ "path")
            [string](Get-HashtableValue $_ "presence") -ceq "file" -and
            $preByPath.ContainsKey($path) -and
            [string](Get-HashtableValue $preByPath[$path] "presence") -ceq "absent"
        } | ForEach-Object { [string](Get-HashtableValue $_ "path") })
    foreach ($path in $createdPaths) { $full = Get-ProjectPath $Root $path; if (Test-Path -LiteralPath $full -PathType Leaf) { [IO.File]::Delete($full) } }
    Remove-EmptyMigrationDirectories $Root $createdPaths
    $createdDirectories = @($postState | Where-Object {
            $path = [string](Get-HashtableValue $_ "path")
            [string](Get-HashtableValue $_ "presence") -ceq "directory" -and
            $preByPath.ContainsKey($path) -and
            [string](Get-HashtableValue $preByPath[$path] "presence") -ceq "absent"
        } | ForEach-Object { Get-ProjectPath $Root ([string](Get-HashtableValue $_ "path")) } | Sort-Object Length -Descending -Unique)
    foreach ($directory in $createdDirectories) {
        if ((Test-Path -LiteralPath $directory -PathType Container) -and @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) { [IO.Directory]::Delete($directory) }
    }
    $expectedPre = @($preState | ForEach-Object { [ordered]@{ path = [string](Get-HashtableValue $_ "path"); presence = [string](Get-HashtableValue $_ "presence"); sha256 = Get-HashtableValue $_ "sha256"; length = [long](Get-HashtableValue $_ "length") } })
    Assert-StateMatches $Root $expectedPre -ExactScope
    return [ordered]@{ schema_version = 1; operation = "rollback"; status = "rolled-back"; reason_codes = @(); migration_revision = [string](Get-HashtableValue $manifest "migration_revision"); backup_id = $BackupId; backup_retained = $true; restored_state_digest = Get-StateDigest $expectedPre }
}

function Write-Result {
    param([Parameter(Mandatory = $true)][object]$Result)
    if ($Json.IsPresent) { $Result | ConvertTo-Json -Depth 100 }
    else {
        Write-Output ("Migration {0}: {1}" -f $Result.operation, $Result.status)
        if (@($Result.reason_codes).Count -gt 0) { Write-Output ("Reasons: {0}" -f (@($Result.reason_codes) -join ", ")) }
        if ($Result.migration_revision) { Write-Output ("Revision: {0}" -f $Result.migration_revision) }
        if ($Result.backup_id) { Write-Output ("Backup: {0}" -f $Result.backup_id) }
    }
}

$root = ""
try {
    $root = Get-NormalizedProjectRoot $ProjectRoot
    $result = switch ($Mode) {
        "Analyze" {
            $candidate = Invoke-Analyze $root
            if ([string]::IsNullOrWhiteSpace($DispositionEvidence)) { $candidate }
            else { Resolve-ReviewedDisposition $root $candidate $DispositionEvidence }
        }
        "Apply" { Invoke-Apply $root }
        "Rollback" { Invoke-Rollback $root }
    }
    Write-Result $result
}
catch {
    $code = [string]$_.Exception.Message
    if ($code -notmatch '^[A-Z][A-Z0-9_]+$') { $code = "MIGRATION_OPERATION_FAILED" }
    $failure = [ordered]@{ schema_version = 1; operation = $Mode.ToLowerInvariant(); status = "blocked"; reason_codes = @($code); migration_revision = $null; backup_id = $(if ($Mode -ceq "Rollback") { $BackupId } else { $null }) }
    Write-Result $failure
    exit 1
}
