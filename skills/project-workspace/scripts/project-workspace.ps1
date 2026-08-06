#requires -Version 7.6

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][Alias("Mode")][ValidateSet("discover", "check")][string]$Operation,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$Query = "",
    [Alias("MaxResults")][ValidateRange(1, 100)][int]$Limit = 5,
    [Alias("AssetType")][string[]]$Type = @(),
    [Alias("State")][string[]]$Status = @(),
    [switch]$CurrentBranchOnly,
    [switch]$Json,
    [switch]$NoExit
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "../../.."))
. (Join-Path $repoRoot "scripts/validation/powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime
. (Join-Path $repoRoot "scripts/lib/path-guard.ps1")

$canonicalParserPath = Join-Path $scriptDir "read-project-assets.ps1"
$schemaRoot = Join-Path $repoRoot "schemas/project-workspace"
$catalogRelativePath = ".agents/.cache/catalog.json"
$glossaryRelativePath = ".agents/glossary.yaml"
$catalogSchemaPath = Join-Path $schemaRoot "catalog.v1.schema.json"
$glossarySchemaPath = Join-Path $schemaRoot "glossary.v1.schema.json"

# Add-Finding: append one stable, public-safe finding to an operation result.
function Add-Finding {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path,
        [string]$Field = "",
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("error", "warning")][string]$Severity = "error"
    )

    [void]$Findings.Add([ordered]@{
        code = $Code
        path = $Path
        field = $Field
        severity = $Severity
        message = $Message
    })
}

# Get-PropertyValue: read a dictionary or PSCustomObject property without unrolling lists.
function Get-PropertyValue {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return ,$Object[$Name] }
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return ,$property.Value
}

# Get-PropertyNames: return deterministic property names for schema-shape checks.
function Get-PropertyNames {
    param([object]$Object)

    if ($null -eq $Object) { return @() }
    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.Keys | ForEach-Object { [string]$_ })
    }
    return @($Object.PSObject.Properties.Name)
}

# Get-StringList: normalize a scalar/list metadata value to a string array.
function Get-StringList {
    param([object]$Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @([string]$Value) }
    return @($Value | ForEach-Object { [string]$_ })
}

# Get-ValueArray: flatten property-returned arrays without turning an empty
# array into one empty pseudo-record.
function Get-ValueArray {
    param([AllowNull()][object]$Value)

    $items = New-Object 'System.Collections.Generic.List[object]'
    if ($null -eq $Value) { return @() }
    $pending = New-Object 'System.Collections.Generic.Queue[object]'
    [void]$pending.Enqueue($Value)
    while ($pending.Count -gt 0) {
        $item = $pending.Dequeue()
        if ($null -eq $item) { continue }
        if ($item -is [System.Array] -and $item -isnot [byte[]]) {
            foreach ($child in $item) { if ($null -ne $child) { [void]$pending.Enqueue($child) } }
            continue
        }
        [void]$items.Add($item)
    }
    return @($items.ToArray())
}

# Normalize-SearchText: apply deterministic Unicode, case, punctuation, and whitespace rules.
function Normalize-SearchText {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $value = $Text.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant()
    $value = [regex]::Replace($value, '[^\p{L}\p{N}_.:/\\-]+', ' ', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    return ([regex]::Replace($value, '\s+', ' ', [Text.RegularExpressions.RegexOptions]::CultureInvariant)).Trim()
}

# Get-SearchTerms: return a normalized phrase and stable term set for direct matching.
function Get-SearchTerms {
    param([AllowEmptyString()][string]$Text)

    $normalized = Normalize-SearchText -Text $Text
    if ([string]::IsNullOrWhiteSpace($normalized)) { return @() }
    $searchTerms = New-Object 'System.Collections.Generic.List[string]'
    [void]$searchTerms.Add($normalized)
    foreach ($searchTerm in @($normalized -split ' ' | Where-Object { $_ })) {
        if (-not $searchTerms.Contains($searchTerm)) { [void]$searchTerms.Add($searchTerm) }
    }
    return @($searchTerms.ToArray())
}

# Test-TextMatch: compare a normalized query term/phrase with normalized candidate text.
function Test-TextMatch {
    param(
        [AllowEmptyString()][string]$Candidate,
        [AllowNull()][string[]]$QueryTerms = @()
    )

    $candidateNormalized = Normalize-SearchText -Text $Candidate
    if ([string]::IsNullOrWhiteSpace($candidateNormalized)) { return $false }
    foreach ($searchTerm in @($QueryTerms)) {
        if ([string]::IsNullOrWhiteSpace($searchTerm)) { continue }
        if ($candidateNormalized -ceq $searchTerm -or $candidateNormalized.Contains($searchTerm)) { return $true }
    }
    return $false
}

# Test-PhraseMatch: glossary expansion uses the complete persisted term, not a
# loose single-term match that would over-return unrelated fixture assets.
function Test-PhraseMatch {
    param(
        [AllowEmptyString()][string]$Candidate,
        [AllowEmptyString()][string]$Phrase
    )

    $candidateNormalized = Normalize-SearchText -Text $Candidate
    $phraseNormalized = Normalize-SearchText -Text $Phrase
    if ([string]::IsNullOrWhiteSpace($candidateNormalized) -or [string]::IsNullOrWhiteSpace($phraseNormalized)) { return $false }
    return ($candidateNormalized -ceq $phraseNormalized -or $candidateNormalized.Contains($phraseNormalized))
}

# Test-PublicSafeText: reject obvious absolute-path and sensitive material before structured output.
function Test-PublicSafeText {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $true }
    if ($Text -match '(?i)(?:^|[\s=(])(?:[a-z]:[\\/]|\\\\|/(?:users|home|private|var|tmp)/)') { return $false }
    if ($Text -match '(?i)(?:ghp_|github_pat_|github_token|bearer\s+[a-z0-9._-]{12,}|AKIA[0-9A-Z]{16})') { return $false }
    return $true
}

# Get-Sha256: calculate a lowercase SHA-256 string with the public prefix used by contracts.
function Get-Sha256 {
    param([byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return "sha256:" + ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

# Read-StrictUtf8Text: read UTF-8 without BOM-driven fallback and normalize line endings for hashes.
function Read-StrictUtf8Text {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $offset = 0
    if ($bytes.Length -ge 4 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) -or ($bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF))) {
        throw "UTF-32 is not supported."
    }
    if ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        throw "UTF-16 is not supported."
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $offset = 3
    }
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    return $text.Replace("`r`n", "`n").Replace("`r", "`n")
}

# Get-NormalizedTextHash: content hash that is equivalent for CRLF and LF source files.
function Get-NormalizedTextHash {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = Read-StrictUtf8Text -Path $Path
    return Get-Sha256 -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($text))
}

# Get-RevisionHash: hash normalized Work content after removing only its top-level revision field.
function Get-RevisionHash {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = Read-StrictUtf8Text -Path $Path
    $lines = @($text -split "`n")
    $withoutRevisionLines = New-Object 'System.Collections.Generic.List[string]'
    $inFrontMatter = ($lines.Count -gt 0 -and [string]$lines[0] -ceq "---")
    $frontMatterClosed = $false
    $removed = $false
    foreach ($line in $lines) {
        if ($inFrontMatter -and -not $frontMatterClosed -and [string]$line -ceq "---" -and $withoutRevisionLines.Count -gt 0) {
            $frontMatterClosed = $true
        }
        if ($inFrontMatter -and -not $frontMatterClosed -and -not $removed -and [string]$line -match '^revision:') {
            $removed = $true
            continue
        }
        [void]$withoutRevisionLines.Add([string]$line)
    }
    $withoutRevision = $withoutRevisionLines.ToArray() -join "`n"
    return Get-Sha256 -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($withoutRevision))
}

# Test-SafeProjectRelativePath: keep auxiliary paths within the explicit project root.
function Test-SafeProjectRelativePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path)) { return $false }
    if ($Path -match '^[A-Za-z]:' -or $Path -match '(^|[\\/])\.\.?(?:[\\/]|$)') { return $false }
    $segments = @($Path -split '[\\/]')
    if ($segments.Count -eq 0 -or @($segments | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { return $false }
    foreach ($segment in $segments) {
        if ($segment.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $false }
    }
    return $true
}

# Assert-ProjectPath: validate lexical and physical containment without creating anything.
function Assert-ProjectPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [switch]$AllowMissing
    )

    if (-not (Test-SafeProjectRelativePath -Path $RelativePath)) { throw "unsafe auxiliary path" }
    $full = Get-NormalizedFullPath -Path (Join-Path $Root $RelativePath)
    if (-not (Test-PathIsEqualOrChild -Path $full -Root $Root)) { throw "auxiliary path escapes project root" }
    $rootPhysical = Resolve-ExistingPhysicalPath -Path $Root -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    if (Test-Path -LiteralPath $full) {
        $physical = Resolve-ExistingPhysicalPath -Path $full -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
        if (-not (Test-PathIsEqualOrChild -Path $physical -Root $rootPhysical)) { throw "auxiliary path resolves outside project root" }
    }
    elseif (-not $AllowMissing.IsPresent) {
        throw "auxiliary path is missing"
    }
    else {
        $parent = Split-Path -Parent $full
        if (Test-Path -LiteralPath $parent -PathType Container) {
            $parentPhysical = Resolve-ExistingPhysicalPath -Path $parent -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
            if (-not (Test-PathIsEqualOrChild -Path $parentPhysical -Root $rootPhysical)) { throw "auxiliary path parent resolves outside project root" }
        }
    }
    return $full
}

# Get-CanonicalFileRecords: enumerate only Slice A canonical roots and return cache-local metadata.
function Get-CanonicalFileRecords {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $records = New-Object 'System.Collections.Generic.List[object]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $roots = @(
        [ordered]@{ root = ".agents/work"; type = "work" },
        [ordered]@{ root = ".agents/context"; type = "context" },
        [ordered]@{ root = ".agents/procedures"; type = "procedure" }
    )
    foreach ($rootInfo in $roots) {
        $directory = Join-Path $Root ([string]$rootInfo.root)
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -Filter "*.md" -Force | Sort-Object Name)) {
            $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
            try {
                Assert-ProjectPath -Root $Root -RelativePath $relative | Out-Null
            }
            catch {
                Add-Finding -Findings $Findings -Code "unsafe-path" -Path $relative -Message "Canonical asset path cannot be resolved safely inside the project root."
                continue
            }
            if (-not $seen.Add($relative)) { continue }
            [void]$records.Add([ordered]@{
                path = $relative
                type = [string]$rootInfo.type
                size = [long]$file.Length
                mtime = $file.LastWriteTimeUtc.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
                full_path = $file.FullName
            })
        }
    }

    $specRoot = Join-Path $Root "docs/specs"
    if (Test-Path -LiteralPath $specRoot -PathType Container) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $specRoot -Directory -Force | Sort-Object Name)) {
            $file = Join-Path $directory.FullName "spec.md"
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            $relative = [IO.Path]::GetRelativePath($Root, $file).Replace('\', '/')
            try {
                Assert-ProjectPath -Root $Root -RelativePath $relative | Out-Null
            }
            catch {
                Add-Finding -Findings $Findings -Code "unsafe-path" -Path $relative -Message "Canonical Spec path cannot be resolved safely inside the project root."
                continue
            }
            if (-not $seen.Add($relative)) { continue }
            $item = Get-Item -LiteralPath $file -Force
            [void]$records.Add([ordered]@{
                path = $relative
                type = "spec"
                size = [long]$item.Length
                mtime = $item.LastWriteTimeUtc.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
                full_path = $item.FullName
            })
        }
    }
    return @($records.ToArray() | Sort-Object path)
}

# Get-DirectoryFingerprint: hash only relative path, size, and normalized mtime.
function Get-DirectoryFingerprint {
    param([object[]]$Records = @())

    $lines = @($Records | Sort-Object path | ForEach-Object { "{0}|{1}|{2}" -f $_.path, $_.size, $_.mtime })
    return Get-Sha256 -Bytes ([Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n")))
}

# Get-SchemaFingerprint: hash all canonical v1 schema bytes in stable filename order.
function Get-SchemaFingerprint {
    $files = @(Get-ChildItem -LiteralPath $schemaRoot -File -Filter "*.v1.schema.json" | Sort-Object Name)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in $files) {
        [void]$lines.Add("$($file.Name)|$(Get-NormalizedTextHash -Path $file.FullName)")
    }
    return Get-Sha256 -Bytes ([Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n")))
}

# Invoke-CanonicalParser: call the Slice A parser in-process with its opt-in metadata mode.
function Invoke-CanonicalParser {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string[]]$Paths = @()
    )

    $parameters = @{
        ProjectRoot = $Root
        IncludeMetadata = $true
        NoExit = $true
        Json = $true
    }
    if (@($Paths).Count -gt 0) { $parameters.AssetPath = @($Paths) }
    $output = @(& $canonicalParserPath @parameters)
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    try {
        return [ordered]@{
            payload = ($text | ConvertFrom-Json -Depth 50 -DateKind String -ErrorAction Stop)
            text = $text
        }
    }
    catch {
        return [ordered]@{
            payload = $null
            text = $text
            parse_error = $true
        }
    }
}

# Get-AssetCatalogRecord: select public-safe metadata from a validated parser asset.
function Get-AssetCatalogRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Asset,
        [Parameter(Mandatory = $true)][object]$FileRecord,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $metadata = Get-PropertyValue -Object $Asset -Name "metadata"
    if ($null -eq $metadata -or [bool](Get-PropertyValue -Object $Asset -Name "valid") -ne $true) {
        Add-Finding -Findings $Findings -Code "asset-invalid" -Path ([string]$Asset.path) -Message "Canonical parser did not return valid asset metadata."
        return $null
    }
    $record = [ordered]@{
        type = [string]$Asset.type
        id = [string]$Asset.id
        path = [string]$Asset.path
        schema = [string]$Asset.schema
        status = [string](Get-PropertyValue $metadata "status")
        title = [string](Get-PropertyValue $metadata "title")
        summary = [string](Get-PropertyValue $metadata "summary")
        updated = [string](Get-PropertyValue $metadata "updated")
        keywords = @(Get-StringList (Get-PropertyValue $metadata "keywords"))
        kind = [string](Get-PropertyValue $metadata "kind")
        exposure = [string](Get-PropertyValue $metadata "exposure")
        triggers = @(Get-StringList (Get-PropertyValue $metadata "triggers"))
        side_effects = @(Get-StringList (Get-PropertyValue $metadata "side_effects"))
        related_work = @(Get-StringList (Get-PropertyValue $metadata "related_work"))
        supersedes = @(Get-StringList (Get-PropertyValue $metadata "supersedes"))
        size = [long]$FileRecord.size
        mtime = [string]$FileRecord.mtime
        content_hash = Get-NormalizedTextHash -Path ([string]$FileRecord.full_path)
    }
    $git = Get-PropertyValue $metadata "git"
    if ($null -ne $git) {
        $record.git = [ordered]@{}
        foreach ($field in @("branch", "worktree", "last_verified_commit")) {
            $value = Get-PropertyValue $git $field
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                $record.git[$field] = [string]$value
            }
        }
        if ($record.git.Count -eq 0) { $record.Remove("git") }
    }
    foreach ($field in @("title", "summary", "updated", "status", "kind", "exposure", "path", "id", "schema")) {
        if (-not (Test-PublicSafeText -Text ([string]$record[$field]))) {
            Add-Finding -Findings $Findings -Code "unsafe-output" -Path ([string]$Asset.path) -Field $field -Message "Asset metadata contains disallowed absolute-path or sensitive material."
        }
    }
    foreach ($field in @("keywords", "triggers", "side_effects", "related_work", "supersedes")) {
        foreach ($value in @($record[$field])) {
            if (-not (Test-PublicSafeText -Text ([string]$value))) {
                Add-Finding -Findings $Findings -Code "unsafe-output" -Path ([string]$Asset.path) -Field $field -Message "Asset metadata contains disallowed absolute-path or sensitive material."
            }
        }
    }
    if ($record.Contains("git")) {
        foreach ($field in @($record.git.Keys)) {
            if (-not (Test-PublicSafeText -Text ([string]$record.git[$field]))) {
                Add-Finding -Findings $Findings -Code "unsafe-output" -Path ([string]$Asset.path) -Field ("git.{0}" -f $field) -Message "Git anchor metadata contains disallowed path or sensitive material."
            }
        }
    }
    return $record
}

# Convert a restricted glossary scalar into a public-safe value. Glossary is
# intentionally parsed as a small YAML subset; arbitrary YAML features are not
# needed for discovery and would make fail-closed behavior less predictable.
function Convert-GlossaryScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $text = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        Add-Finding -Findings $Findings -Code "glossary-format" -Path $Path -Message "Glossary scalar values must not be empty."
        return $null
    }
    if ($text -match '[`$]|(?:^|\s)(?:[&*!]|!!|<<?|>>?)(?:\s|$)|[{}\[\]|>]') {
        Add-Finding -Findings $Findings -Code "glossary-unsafe" -Path $Path -Message "Glossary values contain unsupported YAML syntax."
        return $null
    }
    if (($text.StartsWith('"') -and -not $text.EndsWith('"')) -or ($text.StartsWith("'") -and -not $text.EndsWith("'"))) {
        Add-Finding -Findings $Findings -Code "glossary-format" -Path $Path -Message "Glossary quoted values must be closed on the same line."
        return $null
    }
    if (($text.StartsWith('"') -and $text.EndsWith('"')) -or ($text.StartsWith("'") -and $text.EndsWith("'"))) {
        if ($text.Length -lt 2) {
            Add-Finding -Findings $Findings -Code "glossary-format" -Path $Path -Message "Glossary quoted values must contain text."
            return $null
        }
        $text = $text.Substring(1, $text.Length - 2)
        if ($text.Contains('"') -or $text.Contains("'")) {
            Add-Finding -Findings $Findings -Code "glossary-format" -Path $Path -Message "Nested or escaped glossary quotes are not supported."
            return $null
        }
    }
    if (-not (Test-PublicSafeText -Text $text)) {
        Add-Finding -Findings $Findings -Code "glossary-unsafe" -Path $Path -Message "Glossary values contain disallowed path or sensitive material."
        return $null
    }
    return $text
}

# Read-Glossary: parse and validate the evidence-backed, one-level glossary.
function Read-Glossary {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $path = Assert-ProjectPath -Root $Root -RelativePath $glossaryRelativePath -AllowMissing
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [ordered]@{ state = "absent"; fingerprint = "absent"; terms = @(); path = $glossaryRelativePath }
    }

    $glossaryFindingStart = $Findings.Count
    $text = $null
    try { $text = Read-StrictUtf8Text -Path $path }
    catch {
        Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Message "Glossary must be strict UTF-8 text."
        return [ordered]@{ state = "invalid"; fingerprint = ""; terms = @(); path = $glossaryRelativePath }
    }
    $fingerprint = Get-Sha256 -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($text))
    $lines = @($text -split "`n")
    $top = [ordered]@{}
    $terms = New-Object 'System.Collections.Generic.List[object]'
    $current = $null
    $currentField = ""
    $currentValues = $null

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $lineNumber = $index + 1
        $line = [string]$lines[$index]
        if ($line -match "`t") {
            Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary indentation must use spaces, not tabs."
            continue
        }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '#') {
            Add-Finding -Findings $Findings -Code "glossary-unsafe" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary comments are not accepted in the strict input subset."
            continue
        }
        $indent = $line.Length - $line.TrimStart(' ').Length
        if (($indent % 2) -ne 0) {
            Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary indentation must use two-space levels."
            continue
        }
        $content = $line.Substring($indent)
        if ($indent -eq 0) {
            if ($content -notmatch '^([A-Za-z][A-Za-z0-9_-]*):[ ]*(.*)$') {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary top-level entries must use key: value syntax."
                continue
            }
            $key = [string]$Matches[1]
            $value = [string]$Matches[2]
            if ($top.Contains($key)) {
                Add-Finding -Findings $Findings -Code "glossary-conflict" -Path $glossaryRelativePath -Field $key -Message "Glossary top-level keys must be unique."
                continue
            }
            if ($key -eq "schema") {
                $parsed = Convert-GlossaryScalar -Value $value -Path $glossaryRelativePath -Findings $Findings
                if ($null -ne $parsed) { $top[$key] = $parsed }
                continue
            }
            if ($key -eq "terms" -and [string]::IsNullOrWhiteSpace($value)) {
                $top[$key] = $true
                $current = $null
                $currentField = ""
                $currentValues = $null
                continue
            }
            Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field $key -Message "Unsupported glossary top-level field or inline value."
            continue
        }

        if ($indent -eq 2 -and $content -match '^-[ ]+(.*)$') {
            if (-not $top.Contains("terms")) {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary terms must be declared before term entries."
                continue
            }
            $current = [ordered]@{}
            $currentField = ""
            $currentValues = $null
            [void]$terms.Add($current)
            $entry = [string]$Matches[1]
            if ($entry -notmatch '^([A-Za-z][A-Za-z0-9_-]*):[ ]*(.*)$') {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Each glossary term must start with a field."
                continue
            }
            $field = [string]$Matches[1]
            $value = [string]$Matches[2]
            if ($field -notin @("canonical", "aliases", "symbols", "relations", "evidence")) {
                Add-Finding -Findings $Findings -Code "glossary-unknown-field" -Path $glossaryRelativePath -Field $field -Message "Unknown glossary term field."
                continue
            }
            if ($field -eq "canonical" -and -not [string]::IsNullOrWhiteSpace($value)) {
                $parsed = Convert-GlossaryScalar -Value $value -Path $glossaryRelativePath -Findings $Findings
                if ($null -ne $parsed) { $current[$field] = $parsed }
            }
            elseif ([string]::IsNullOrWhiteSpace($value)) {
                if ($field -eq "canonical") {
                    Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field $field -Message "Glossary canonical values must be scalar text."
                }
                else {
                    $current[$field] = New-Object 'System.Collections.Generic.List[string]'
                    $currentField = $field
                    $currentValues = $current[$field]
                }
            }
            else {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field $field -Message "Glossary list fields must use indented list entries."
            }
            continue
        }

        if ($indent -eq 4 -and $content -match '^([A-Za-z][A-Za-z0-9_-]*):[ ]*(.*)$') {
            if ($null -eq $current) {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary term field appears before a term entry."
                continue
            }
            $field = [string]$Matches[1]
            $value = [string]$Matches[2]
            if ($field -notin @("canonical", "aliases", "symbols", "relations", "evidence")) {
                Add-Finding -Findings $Findings -Code "glossary-unknown-field" -Path $glossaryRelativePath -Field $field -Message "Unknown glossary term field."
                continue
            }
            if ($current.Contains($field)) {
                Add-Finding -Findings $Findings -Code "glossary-conflict" -Path $glossaryRelativePath -Field $field -Message "Glossary term fields must be unique."
                continue
            }
            if ($field -eq "canonical") {
                $parsed = Convert-GlossaryScalar -Value $value -Path $glossaryRelativePath -Findings $Findings
                if ($null -ne $parsed) { $current[$field] = $parsed }
                $currentField = ""
                $currentValues = $null
            }
            elseif ([string]::IsNullOrWhiteSpace($value)) {
                $current[$field] = New-Object 'System.Collections.Generic.List[string]'
                $currentField = $field
                $currentValues = $current[$field]
            }
            else {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field $field -Message "Glossary list fields must use indented list entries."
            }
            continue
        }

        if ($indent -eq 6 -and $content -match '^-[ ]+(.*)$') {
            if ($null -eq $currentValues -or [string]::IsNullOrWhiteSpace($currentField)) {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary list item has no active list field."
                continue
            }
            $parsed = Convert-GlossaryScalar -Value ([string]$Matches[1]) -Path $glossaryRelativePath -Findings $Findings
            if ($null -ne $parsed) { [void]$currentValues.Add($parsed) }
            continue
        }

        Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary structure is outside the supported strict YAML subset."
    }

    if (-not $top.Contains("schema") -or [string]$top["schema"] -cne "agent-ecosystem/glossary/v1") {
        Add-Finding -Findings $Findings -Code "glossary-schema" -Path $glossaryRelativePath -Field "schema" -Message "Glossary schema must be agent-ecosystem/glossary/v1."
    }
    if (-not $top.Contains("terms") -or $terms.Count -eq 0) {
        Add-Finding -Findings $Findings -Code "glossary-schema" -Path $glossaryRelativePath -Field "terms" -Message "Glossary must contain at least one term."
    }

    $normalizedTerms = New-Object 'System.Collections.Generic.List[object]'
    $owners = @{}
    $canonicalOwners = @{}
    foreach ($term in @($terms.ToArray())) {
        foreach ($field in @("aliases", "symbols", "relations", "evidence")) {
            if (-not $term.Contains($field)) { $term[$field] = New-Object 'System.Collections.Generic.List[string]' }
        }
        if (-not $term.Contains("canonical")) {
            Add-Finding -Findings $Findings -Code "glossary-schema" -Path $glossaryRelativePath -Field "canonical" -Message "Each glossary term requires canonical text."
            continue
        }
        $canonical = [string]$term.canonical
        $canonicalKey = Normalize-SearchText -Text $canonical
        if ([string]::IsNullOrWhiteSpace($canonicalKey)) {
            Add-Finding -Findings $Findings -Code "glossary-schema" -Path $glossaryRelativePath -Field "canonical" -Message "Glossary canonical text must normalize to a non-empty value."
            continue
        }
        if ($canonicalOwners.ContainsKey($canonicalKey)) {
            Add-Finding -Findings $Findings -Code "glossary-conflict" -Path $glossaryRelativePath -Field "canonical" -Message "Glossary canonical terms must be unique after normalization."
        }
        else { $canonicalOwners[$canonicalKey] = $canonical }
        if (@($term.evidence).Count -eq 0) {
            Add-Finding -Findings $Findings -Code "glossary-evidence" -Path $glossaryRelativePath -Field "evidence" -Message "Every glossary term requires direct evidence."
        }
        $keysForTerm = @($canonical) + @($term.aliases) + @($term.symbols)
        foreach ($value in $keysForTerm) {
            $key = Normalize-SearchText -Text ([string]$value)
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if ($owners.ContainsKey($key) -and [string]$owners[$key] -cne $canonical) {
                Add-Finding -Findings $Findings -Code "glossary-conflict" -Path $glossaryRelativePath -Field "terms" -Message "Glossary aliases and symbols must resolve to one canonical term."
            }
            else { $owners[$key] = $canonical }
        }
        foreach ($relation in @($term.relations)) {
            $relationKey = Normalize-SearchText -Text ([string]$relation)
            if ([string]::IsNullOrWhiteSpace($relationKey) -or $relationKey -ceq $canonicalKey) {
                Add-Finding -Findings $Findings -Code "glossary-cycle" -Path $glossaryRelativePath -Field "relations" -Message "Glossary relations must not be empty or self-referential."
            }
        }
        [void]$normalizedTerms.Add([ordered]@{
            canonical = $canonical
            canonical_key = $canonicalKey
            aliases = @($term.aliases | ForEach-Object { [string]$_ })
            symbols = @($term.symbols | ForEach-Object { [string]$_ })
            relations = @($term.relations | ForEach-Object { [string]$_ })
            evidence = @($term.evidence | ForEach-Object { [string]$_ })
        })
    }

    $knownCanonicalKeys = @($canonicalOwners.Keys)
    foreach ($term in @($normalizedTerms.ToArray())) {
        foreach ($relation in @($term.relations)) {
            $relationKey = Normalize-SearchText -Text $relation
            if ($knownCanonicalKeys -notcontains $relationKey) {
                Add-Finding -Findings $Findings -Code "glossary-unknown" -Path $glossaryRelativePath -Field "relations" -Message "Glossary relations must target declared canonical terms."
            }
        }
    }
    $byKey = @{}
    foreach ($term in @($normalizedTerms.ToArray())) { $byKey[$term.canonical_key] = $term }
    $visit = @{}
    function Visit-GlossaryRelation {
        param([string]$Key)
        if ($visit[$Key] -eq "active") {
            Add-Finding -Findings $Findings -Code "glossary-cycle" -Path $glossaryRelativePath -Field "relations" -Message "Glossary relations must not contain cycles."
            return
        }
        if ($visit[$Key] -eq "done" -or -not $byKey.ContainsKey($Key)) { return }
        $visit[$Key] = "active"
        foreach ($relation in @($byKey[$Key].relations)) {
            $relationKey = Normalize-SearchText -Text $relation
            if ($byKey.ContainsKey($relationKey)) { Visit-GlossaryRelation -Key $relationKey }
        }
        $visit[$Key] = "done"
    }
    foreach ($key in @($byKey.Keys | Sort-Object)) { Visit-GlossaryRelation -Key $key }

    if ($Findings.Count -gt $glossaryFindingStart) {
        return [ordered]@{ state = "invalid"; fingerprint = $fingerprint; terms = @(); path = $glossaryRelativePath }
    }
    return [ordered]@{ state = "valid"; fingerprint = $fingerprint; terms = @($normalizedTerms.ToArray()); path = $glossaryRelativePath }
}

# Get-CatalogReadResult: load only the discardable local cache; never repairs it.
function Get-CatalogReadResult {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $path = Assert-ProjectPath -Root $Root -RelativePath $catalogRelativePath -AllowMissing
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [ordered]@{ state = "missing"; path = $catalogRelativePath; payload = $null }
    }
    try {
        $text = Read-StrictUtf8Text -Path $path
        if ([string]::IsNullOrWhiteSpace($text)) { throw "empty catalog" }
        $payload = $text | ConvertFrom-Json -Depth 50 -DateKind String -ErrorAction Stop
        return [ordered]@{ state = "present"; path = $catalogRelativePath; payload = $payload }
    }
    catch {
        Add-Finding -Findings $Findings -Code "catalog-invalid" -Path $catalogRelativePath -Message "Catalog cache is missing valid UTF-8 JSON and must be rebuilt by discover."
        return [ordered]@{ state = "invalid"; path = $catalogRelativePath; payload = $null }
    }
}

# Test-CatalogShape: validate cache structure and public-safe relative paths.
function Test-CatalogShape {
    param(
        [object]$Catalog,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    if ($null -eq $Catalog) { return $false }
    $allowedCatalogFields = @("schema", "schema_version", "generated_by", "directory_fingerprint", "schema_fingerprint", "glossary_fingerprint", "asset_count", "assets")
    foreach ($propertyName in @(Get-PropertyNames -Object $Catalog)) {
        if ($allowedCatalogFields -notcontains $propertyName) {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field $propertyName -Message "Catalog contains an unsupported top-level field."
        }
    }
    $required = @("schema", "schema_version", "generated_by", "directory_fingerprint", "schema_fingerprint", "glossary_fingerprint", "asset_count", "assets")
    foreach ($field in $required) {
        if ($null -eq (Get-PropertyValue $Catalog $field)) {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field $field -Message "Catalog is missing a required field."
        }
    }
    if ([string](Get-PropertyValue $Catalog "schema") -cne "agent-ecosystem/catalog/v1" -or [int](Get-PropertyValue $Catalog "schema_version") -ne 1 -or [string](Get-PropertyValue $Catalog "generated_by") -cne "project-workspace-discover") {
        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Message "Catalog schema identity is unsupported."
    }
    foreach ($hashField in @("directory_fingerprint", "schema_fingerprint")) {
        if ([string](Get-PropertyValue $Catalog $hashField) -notmatch '^sha256:[0-9a-f]{64}$') {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field $hashField -Message "Catalog fingerprint is not a valid SHA-256 value."
        }
    }
    $glossaryFingerprint = [string](Get-PropertyValue $Catalog "glossary_fingerprint")
    if ($glossaryFingerprint -notmatch '^(?:absent|sha256:[0-9a-f]{64})$') {
        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "glossary_fingerprint" -Message "Catalog glossary fingerprint is invalid."
    }
    $assets = @(Get-ValueArray -Value (Get-PropertyValue $Catalog "assets"))
    if ($null -eq $assets -or $assets -is [string]) {
        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "assets" -Message "Catalog assets must be an array."
        return $false
    }
    $seenPaths = @{}
    $seenIdentities = @{}
    $allowedAssetFields = @("type", "id", "path", "schema", "status", "title", "summary", "updated", "keywords", "kind", "exposure", "triggers", "side_effects", "related_work", "supersedes", "git", "size", "mtime", "content_hash")
    foreach ($asset in @($assets)) {
        if ($null -eq $asset -or $asset -is [string] -or $asset -is [ValueType]) { Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "assets" -Message "Catalog asset records must be objects."; continue }
        foreach ($propertyName in @(Get-PropertyNames -Object $asset)) {
            if ($allowedAssetFields -notcontains $propertyName) {
                Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("assets.{0}" -f $propertyName) -Message "Catalog asset contains an unsupported field."
            }
        }
        $path = [string](Get-PropertyValue $asset "path")
        $type = [string](Get-PropertyValue $asset "type")
        $id = [string](Get-PropertyValue $asset "id")
        if ($path -notmatch '^(?:\.agents/(?:work|context|procedures)/[a-z0-9]+(?:-[a-z0-9]+)*\.md|docs/specs/[a-z0-9]+(?:-[a-z0-9]+)*/spec\.md)$') {
            Add-Finding -Findings $Findings -Code "catalog-path" -Path $catalogRelativePath -Field "assets.path" -Message "Catalog asset path is not canonical and public-safe."
        }
        if (-not (Test-PublicSafeText -Text $path) -or -not (Test-PublicSafeText -Text $id)) {
            Add-Finding -Findings $Findings -Code "unsafe-output" -Path $catalogRelativePath -Field "assets" -Message "Catalog contains disallowed path or identity text."
        }
        if ($seenPaths.ContainsKey($path)) { Add-Finding -Findings $Findings -Code "catalog-duplicate" -Path $catalogRelativePath -Field "assets.path" -Message "Catalog asset paths must be unique." } else { $seenPaths[$path] = $true }
        $identity = "{0}:{1}" -f $type, $id
        if ($seenIdentities.ContainsKey($identity)) { Add-Finding -Findings $Findings -Code "catalog-duplicate" -Path $catalogRelativePath -Field "assets.id" -Message "Catalog asset identities must be unique." } else { $seenIdentities[$identity] = $true }
        foreach ($field in @("type", "id", "path", "schema", "status", "title", "summary", "keywords", "size", "mtime", "content_hash")) {
            if ($null -eq (Get-PropertyValue $asset $field)) { Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("assets.{0}" -f $field) -Message "Catalog asset record is missing a required field." }
        }
        if ($type -notin @("work", "context", "procedure", "spec")) { Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "assets.type" -Message "Catalog asset type is unsupported." }
        if ($id -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "assets.id" -Message "Catalog asset id is not stable kebab-case." }
        if ([string](Get-PropertyValue $asset "content_hash") -notmatch '^sha256:[0-9a-f]{64}$') { Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "assets.content_hash" -Message "Catalog content hash is invalid." }
        foreach ($textField in @("schema", "status", "title", "summary", "mtime")) { if (-not (Test-PublicSafeText -Text ([string](Get-PropertyValue $asset $textField)))) { Add-Finding -Findings $Findings -Code "unsafe-output" -Path $catalogRelativePath -Field ("assets.{0}" -f $textField) -Message "Catalog text contains disallowed path or sensitive material." } }
        foreach ($listField in @("keywords", "triggers", "side_effects", "related_work", "supersedes")) {
            $listValue = Get-PropertyValue $asset $listField
            if ($null -ne $listValue -and $listValue -is [string]) {
                Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("assets.{0}" -f $listField) -Message "Catalog list fields must be arrays."
            }
            foreach ($value in @(Get-ValueArray -Value $listValue)) {
                if ($value -isnot [string]) {
                    Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("assets.{0}" -f $listField) -Message "Catalog list values must be strings."
                }
                elseif (-not (Test-PublicSafeText -Text ([string]$value))) {
                    Add-Finding -Findings $Findings -Code "unsafe-output" -Path $catalogRelativePath -Field ("assets.{0}" -f $listField) -Message "Catalog list text contains disallowed path or sensitive material."
                }
            }
        }
        $cachedGit = Get-PropertyValue $asset "git"
        if ($null -ne $cachedGit) {
            if ($cachedGit -is [string] -or $cachedGit -is [ValueType]) {
                Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "assets.git" -Message "Catalog Git anchors must be objects."
            }
            else {
                $allowedGitFields = @("branch", "worktree", "last_verified_commit")
                foreach ($propertyName in @(Get-PropertyNames -Object $cachedGit)) {
                    if ($allowedGitFields -notcontains $propertyName) {
                        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("assets.git.{0}" -f $propertyName) -Message "Catalog Git anchor contains an unsupported field."
                    }
                    $value = Get-PropertyValue $cachedGit $propertyName
                    if ($value -isnot [string] -or -not (Test-PublicSafeText -Text ([string]$value))) {
                        Add-Finding -Findings $Findings -Code "unsafe-output" -Path $catalogRelativePath -Field ("assets.git.{0}" -f $propertyName) -Message "Catalog Git anchor contains disallowed path or sensitive material."
                    }
                }
            }
        }
    }
    $assetCount = [int](Get-PropertyValue $Catalog "asset_count")
    if ($assetCount -lt 0 -or $assetCount -ne @($assets).Count) { Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "asset_count" -Message "Catalog asset_count does not match assets length." }
    return $true
}

# Invoke-GitText: read-only Git command helper with no path-bearing output.
function Invoke-GitText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    try {
        $output = @(& git -C $Root @Arguments 2>$null)
        if ($LASTEXITCODE -ne 0) { return $null }
        return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    }
    catch { return $null }
}

# Get-GitState: collect branch/worktree facts without modifying the repository.
function Get-GitState {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $inside = Invoke-GitText -Root $Root -Arguments @("rev-parse", "--is-inside-work-tree")
    if ($inside -cne "true") {
        Add-Finding -Findings $Findings -Code "git-unavailable" -Path "" -Message "Git repository metadata is unavailable; discovery remains filesystem-based." -Severity warning
        return [ordered]@{ state = "unavailable"; branch = ""; head = ""; dirty = $null; shallow = $null; detached = $null; anchors = @() }
    }
    $branch = Invoke-GitText -Root $Root -Arguments @("symbolic-ref", "--quiet", "--short", "HEAD")
    $head = Invoke-GitText -Root $Root -Arguments @("rev-parse", "HEAD")
    $shallowText = Invoke-GitText -Root $Root -Arguments @("rev-parse", "--is-shallow-repository")
    $statusText = Invoke-GitText -Root $Root -Arguments @("status", "--porcelain", "--untracked-files=all")
    $detached = [string]::IsNullOrWhiteSpace($branch)
    $dirty = -not [string]::IsNullOrWhiteSpace($statusText)
    $shallow = ($shallowText -ceq "true")
    if ($dirty) { Add-Finding -Findings $Findings -Code "git-dirty" -Path "" -Message "Git worktree has uncommitted changes." -Severity warning }
    if ($shallow) { Add-Finding -Findings $Findings -Code "git-shallow" -Path "" -Message "Git repository is shallow; commit reachability is limited." -Severity warning }
    if ($detached) { Add-Finding -Findings $Findings -Code "git-detached" -Path "" -Message "Git HEAD is detached; branch anchors cannot be matched." -Severity warning }
    return [ordered]@{ state = "available"; branch = [string]$branch; head = [string]$head; dirty = $dirty; shallow = $shallow; detached = $detached; anchors = @() }
}

# Test-GitAnchor: evaluate optional Work anchors against current read-only Git facts.
function Test-GitAnchor {
    param(
        [Parameter(Mandatory = $true)][object]$Asset,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object]$GitState,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $anchor = Get-PropertyValue $Asset "git"
    if ($null -eq $anchor) { return $null }
    $branch = [string](Get-PropertyValue $anchor "branch")
    $worktree = [string](Get-PropertyValue $anchor "worktree")
    $verified = [string](Get-PropertyValue $anchor "last_verified_commit")
    $branchState = "not_checked"
    if (-not [string]::IsNullOrWhiteSpace($branch)) {
        if ($GitState.state -cne "available" -or $GitState.detached) { $branchState = "unavailable" }
        elseif ([string]$GitState.branch -ceq $branch) { $branchState = "branch_match" }
        else {
            $branchState = "branch_mismatch"
            Add-Finding -Findings $Findings -Code "branch_mismatch" -Path ([string]$Asset.path) -Field "git.branch" -Message "Work item Git branch differs from the current branch." -Severity warning
        }
    }
    $commitState = "not_checked"
    if (-not [string]::IsNullOrWhiteSpace($verified)) {
        if ($GitState.state -cne "available") {
            $commitState = "git_unavailable"
        }
        elseif ($verified -notmatch '^[0-9a-fA-F]{7,64}$') {
            $commitState = "invalid_commit"
            Add-Finding -Findings $Findings -Code "git-anchor-invalid" -Path ([string]$Asset.path) -Field "git.last_verified_commit" -Message "Git anchor commit must be a hexadecimal commit id." -Severity warning
        }
        else {
            try {
                & git -C $Root merge-base --is-ancestor $verified HEAD 2>$null | Out-Null
                $reachableExit = $LASTEXITCODE
            }
            catch { $reachableExit = 1 }
            if ($reachableExit -eq 0) { $commitState = "reachable" }
            else {
                $commitState = "unreachable"
                Add-Finding -Findings $Findings -Code "git-anchor-unreachable" -Path ([string]$Asset.path) -Field "git.last_verified_commit" -Message "Git anchor commit is not reachable from current HEAD." -Severity warning
            }
        }
    }
    return [ordered]@{ branch = $branch; worktree = $worktree; last_verified_commit = $verified; branch_state = $branchState; commit_state = $commitState }
}

# Convert-ParserAssetsToCatalog: turn Slice A parser output into cache records.
function Convert-ParserAssetsToCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FileRecords,
        [string[]]$Paths = @(),
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $invocation = Invoke-CanonicalParser -Root $Root -Paths $Paths
    if ($null -eq $invocation.payload) {
        Add-Finding -Findings $Findings -Code "canonical-parser" -Path "" -Message "Canonical parser did not return structured JSON."
        return [ordered]@{ success = $false; records = @() }
    }
    $payload = $invocation.payload
    if ([string]$payload.status -cne "PASS") {
        foreach ($finding in @($payload.findings)) {
            Add-Finding -Findings $Findings -Code ("canonical-{0}" -f [string]$finding.code) -Path ([string]$finding.path) -Field ([string]$finding.field) -Message "Canonical Markdown parser rejected an asset."
        }
        if (@($payload.findings).Count -eq 0) { Add-Finding -Findings $Findings -Code "canonical-parser" -Path "" -Message "Canonical parser reported FAIL without a finding." }
        return [ordered]@{ success = $false; records = @() }
    }
    $byPath = @{}
    foreach ($fileRecord in @($FileRecords)) { $byPath[[string]$fileRecord.path] = $fileRecord }
    $records = New-Object 'System.Collections.Generic.List[object]'
    foreach ($asset in @(Get-ValueArray -Value $payload.assets)) {
        $path = [string]$asset.path
        if (-not $byPath.ContainsKey($path)) {
            Add-Finding -Findings $Findings -Code "canonical-path" -Path $path -Message "Canonical parser returned an asset outside the enumerated project roots."
            continue
        }
        $record = Get-AssetCatalogRecord -Asset $asset -FileRecord $byPath[$path] -Findings $Findings
        if ($null -ne $record) { [void]$records.Add($record) }
    }
    if ($records.Count -ne @($FileRecords | Where-Object { @($Paths).Count -eq 0 -or $Paths -contains $_.path }).Count) {
        Add-Finding -Findings $Findings -Code "canonical-count" -Path "" -Message "Canonical parser asset count does not match the requested canonical file set."
    }
    return [ordered]@{ success = ($Findings.Count -eq 0); records = @($records.ToArray() | Sort-Object path) }
}

# Test-CatalogMatchesFiles: compare the cache's cheap directory view with the current tree.
function Test-CatalogMatchesFiles {
    param(
        [Parameter(Mandatory = $true)][object]$Catalog,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FileRecords
    )

    $assets = @(Get-ValueArray -Value (Get-PropertyValue $Catalog "assets"))
    if ($assets.Count -ne @($FileRecords).Count) { return $false }
    $byPath = @{}
    foreach ($asset in $assets) { $byPath[[string](Get-PropertyValue $asset "path")] = $asset }
    foreach ($fileRecord in @($FileRecords)) {
        $path = [string]$fileRecord.path
        if (-not $byPath.ContainsKey($path)) { return $false }
        $asset = $byPath[$path]
        if ([long](Get-PropertyValue $asset "size") -ne [long]$fileRecord.size) { return $false }
        if ([string](Get-PropertyValue $asset "mtime") -cne [string]$fileRecord.mtime) { return $false }
        if ([string](Get-PropertyValue $asset "type") -cne [string]$fileRecord.type) { return $false }
    }
    return $true
}

# Get-ChangedCanonicalPaths: identify files that need a parser/hash pass for incremental rebuilds.
function Get-ChangedCanonicalPaths {
    param(
        [Parameter(Mandatory = $true)][object]$Catalog,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FileRecords
    )

    $oldByPath = @{}
    foreach ($asset in @(Get-ValueArray -Value (Get-PropertyValue $Catalog "assets"))) { $oldByPath[[string](Get-PropertyValue $asset "path")] = $asset }
    $changed = New-Object 'System.Collections.Generic.List[string]'
    foreach ($fileRecord in @($FileRecords)) {
        $path = [string]$fileRecord.path
        if (-not $oldByPath.ContainsKey($path)) { [void]$changed.Add($path); continue }
        $old = $oldByPath[$path]
        if ([string](Get-PropertyValue $old "type") -cne [string]$fileRecord.type -or
            [long](Get-PropertyValue $old "size") -ne [long]$fileRecord.size -or
            [string](Get-PropertyValue $old "mtime") -cne [string]$fileRecord.mtime) {
            [void]$changed.Add($path)
        }
    }
    return @($changed.ToArray() | Sort-Object)
}

# Merge-IncrementalCatalog: reuse unchanged public records and replace only changed files.
function Merge-IncrementalCatalog {
    param(
        [Parameter(Mandatory = $true)][object]$OldCatalog,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FileRecords,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ChangedRecords
    )

    $changedByPath = @{}
    foreach ($record in @($ChangedRecords)) { $changedByPath[[string]$record.path] = $record }
    $oldByPath = @{}
    foreach ($record in @(Get-ValueArray -Value (Get-PropertyValue $OldCatalog "assets"))) { $oldByPath[[string](Get-PropertyValue $record "path")] = $record }
    $merged = New-Object 'System.Collections.Generic.List[object]'
    foreach ($fileRecord in @($FileRecords | Sort-Object path)) {
        $path = [string]$fileRecord.path
        if ($changedByPath.ContainsKey($path)) { [void]$merged.Add($changedByPath[$path]); continue }
        if ($oldByPath.ContainsKey($path)) { [void]$merged.Add($oldByPath[$path]); continue }
    }
    return @($merged.ToArray() | Sort-Object path)
}

# New-CatalogPayload: construct deterministic JSON with no generation timestamp or absolute path.
function New-CatalogPayload {
    param(
        [Parameter(Mandatory = $true)][string]$DirectoryFingerprint,
        [Parameter(Mandatory = $true)][string]$SchemaFingerprint,
        [Parameter(Mandatory = $true)][string]$GlossaryFingerprint,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Assets
    )

    $orderedAssets = @($Assets | Sort-Object path, type, id)
    return [ordered]@{
        schema = "agent-ecosystem/catalog/v1"
        schema_version = 1
        generated_by = "project-workspace-discover"
        directory_fingerprint = $DirectoryFingerprint
        schema_fingerprint = $SchemaFingerprint
        glossary_fingerprint = $GlossaryFingerprint
        asset_count = $orderedAssets.Count
        assets = @($orderedAssets)
    }
}

# Write-CatalogAtomic: the only write path in Slice B, reachable only from discover.
function Write-CatalogAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object]$Catalog
    )

    $target = Assert-ProjectPath -Root $Root -RelativePath $catalogRelativePath -AllowMissing
    $rootPhysical = Resolve-ExistingPhysicalPath -Path $Root -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    $targetPhysical = Resolve-PhysicalPathForWrite -Path $target
    if (-not (Test-PathIsEqualOrChild -Path $targetPhysical -Root $rootPhysical)) { throw "catalog write path escapes the project root" }
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $parentPhysical = Resolve-ExistingPhysicalPath -Path $parent -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    if (-not (Test-PathIsEqualOrChild -Path $parentPhysical -Root $rootPhysical)) { throw "catalog cache directory escapes the project root" }
    $temp = Join-Path $parent (".catalog.{0}.{1}.tmp" -f $PID, ([guid]::NewGuid().ToString("N")))
    try {
        $json = $Catalog | ConvertTo-Json -Depth 50
        [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $target -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force }
    }
}

# Get-AssetCorpus: build a deterministic search surface from catalog metadata only.
function Get-AssetCorpus {
    param([Parameter(Mandatory = $true)][object]$Asset)

    $values = New-Object 'System.Collections.Generic.List[string]'
    foreach ($field in @("id", "path", "schema", "status", "title", "summary", "updated", "kind", "exposure")) {
        $value = [string](Get-PropertyValue $Asset $field)
        if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$values.Add($value) }
    }
    foreach ($field in @("keywords", "triggers", "side_effects", "related_work", "supersedes")) {
        foreach ($value in @(Get-ValueArray -Value (Get-PropertyValue $Asset $field))) {
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { [void]$values.Add([string]$value) }
        }
    }
    return @($values.ToArray())
}

# Get-GlossaryExpansion: resolve only persisted canonical terms and one relation hop.
function Get-GlossaryExpansion {
    param(
        [Parameter(Mandatory = $true)][object]$Glossary,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Query,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][string[]]$QueryTerms
    )

    $expanded = New-Object 'System.Collections.Generic.List[object]'
    if ($Glossary.state -cne "valid" -or [string]::IsNullOrWhiteSpace($Query)) { return @() }
    $terms = @($Glossary.terms)
    $byCanonical = @{}
    foreach ($term in $terms) { $byCanonical[[string]$term.canonical_key] = $term }
    foreach ($term in $terms) {
        $canonicalMatched = Test-TextMatch -Candidate ([string]$term.canonical) -QueryTerms @($QueryTerms)
        $aliasMatched = @($term.aliases | Where-Object { Test-TextMatch -Candidate ([string]$_) -QueryTerms @($QueryTerms) }).Count -gt 0
        $symbolMatched = @($term.symbols | Where-Object { Test-TextMatch -Candidate ([string]$_) -QueryTerms @($QueryTerms) }).Count -gt 0
        $relationMatched = @($term.relations | Where-Object { Test-TextMatch -Candidate ([string]$_) -QueryTerms @($QueryTerms) }).Count -gt 0
        if ($canonicalMatched -or $aliasMatched -or $symbolMatched -or $relationMatched) {
            $reason = if ($aliasMatched) { "alias_match" } elseif ($symbolMatched) { "symbol_match" } elseif ($relationMatched) { "relation_match" } else { "direct_match" }
            [void]$expanded.Add([ordered]@{ term = $term; reason = $reason })
            if ($canonicalMatched -or $aliasMatched -or $symbolMatched) {
                foreach ($relation in @($term.relations)) {
                    $relationKey = Normalize-SearchText -Text ([string]$relation)
                    if ($byCanonical.ContainsKey($relationKey)) {
                        [void]$expanded.Add([ordered]@{ term = $byCanonical[$relationKey]; reason = "relation_match" })
                    }
                }
            }
        }
    }
    return @($expanded.ToArray())
}

# Get-SearchResults: apply query, glossary, filters, branch policy, scoring, and stable sorting.
function Get-SearchResults {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Assets,
        [Parameter(Mandatory = $true)][object]$Glossary,
        [Parameter(Mandatory = $true)][object]$GitState,
        [AllowEmptyString()][string]$Query = "",
        [Parameter(Mandatory = $true)][int]$Limit,
        [string[]]$Types = @(),
        [string[]]$Statuses = @(),
        [switch]$CurrentBranchOnly,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $normalizedQuery = Normalize-SearchText -Text $Query
    $queryTerms = @(Get-SearchTerms -Text $Query)
    $typeFilter = @($Types | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Normalize-SearchText -Text ([string]$_) })
    $statusFilter = @($Statuses | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Normalize-SearchText -Text ([string]$_) })
    foreach ($type in $typeFilter) {
        if ($type -notin @("work", "context", "procedure", "spec")) { Add-Finding -Findings $Findings -Code "invalid-filter" -Path "" -Field "type" -Message "Type filter contains an unsupported asset type." }
    }
    $excludedStatuses = @("archived", "implemented", "superseded")
    $results = New-Object 'System.Collections.Generic.List[object]'
    $assetList = @(Get-ValueArray -Value $Assets)
    $expansions = Get-GlossaryExpansion -Glossary $Glossary -Query $Query -QueryTerms @($queryTerms)
    foreach ($asset in @($assetList | Sort-Object path, type, id)) {
        if ($null -eq $asset) { continue }
        $type = Normalize-SearchText -Text ([string](Get-PropertyValue $asset "type"))
        $status = Normalize-SearchText -Text ([string](Get-PropertyValue $asset "status"))
        if ($typeFilter.Count -gt 0 -and $typeFilter -notcontains $type) { continue }
        if ($statusFilter.Count -gt 0) {
            if ($statusFilter -notcontains $status) { continue }
        }
        elseif ($excludedStatuses -contains $status) { continue }

        $reasonSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $score = 0
        if ([string]::IsNullOrWhiteSpace($normalizedQuery)) {
            [void]$reasonSet.Add("default")
            $score = 1
        }
        else {
            foreach ($value in @(Get-AssetCorpus -Asset $asset)) {
                if (Test-TextMatch -Candidate $value -QueryTerms @($queryTerms)) {
                    [void]$reasonSet.Add("direct_match")
                    $score = [math]::Max($score, 100)
                    break
                }
            }
            foreach ($expansion in @($expansions)) {
                $term = $expansion.term
                $termValues = @($term.canonical) + @($term.aliases) + @($term.symbols)
                $termMatched = @($termValues | Where-Object {
                        $candidate = [string]$_
                        @((Get-AssetCorpus -Asset $asset) | Where-Object { Test-PhraseMatch -Candidate ([string]$_) -Phrase $candidate }).Count -gt 0
                    }).Count -gt 0
                if ($termMatched) {
                    $reason = [string]$expansion.reason
                    [void]$reasonSet.Add($reason)
                    $reasonScore = switch ($reason) { "alias_match" { 90 } "symbol_match" { 80 } "relation_match" { 40 } default { 100 } }
                    $score = [math]::Max($score, $reasonScore)
                }
            }
            if ($reasonSet.Count -eq 0) { continue }
        }

        $anchor = Test-GitAnchor -Asset $asset -Root $ProjectRoot -GitState $GitState -Findings $Findings
        $branchState = "none"
        $branch = ""
        if ($null -ne $anchor) {
            $branch = [string]$anchor.branch
            $branchState = [string]$anchor.branch_state
            if ($branchState -eq "branch_match") {
                [void]$reasonSet.Add("branch_match")
                $score += 20
            }
            elseif ($branchState -eq "branch_mismatch") {
                [void]$reasonSet.Add("branch_mismatch")
                $score = [math]::Max(0, $score - 10)
            }
        }
        if ($CurrentBranchOnly.IsPresent -and $branchState -ne "branch_match") { continue }
        $reasonOrder = @("direct_match", "alias_match", "symbol_match", "relation_match", "branch_match", "branch_mismatch", "default")
        $reasonCodes = @($reasonOrder | Where-Object { $reasonSet.Contains($_) })
        $statusRank = switch ($status) { "active" { 4 } "draft" { 3 } "accepted" { 3 } "paused" { 2 } "blocked" { 2 } "deferred" { 1 } default { 0 } }
        $updated = [string](Get-PropertyValue $asset "updated")
        [void]$results.Add([ordered]@{
            type = [string](Get-PropertyValue $asset "type")
            id = [string](Get-PropertyValue $asset "id")
            path = [string](Get-PropertyValue $asset "path")
            schema = [string](Get-PropertyValue $asset "schema")
            status = [string](Get-PropertyValue $asset "status")
            title = [string](Get-PropertyValue $asset "title")
            summary = [string](Get-PropertyValue $asset "summary")
            score = [int]$score
            reason_codes = @($reasonCodes)
            branch = $branch
            branch_state = $branchState
            _status_rank = $statusRank
            _updated_sort = $updated
        })
    }
    $sorted = @($results.ToArray() | Sort-Object @{ Expression = { [int]$_.score }; Descending = $true }, @{ Expression = { [int]$_._status_rank }; Descending = $true }, @{ Expression = { [string]$_._updated_sort }; Descending = $true }, @{ Expression = { [string]$_.path }; Descending = $false }, @{ Expression = { [string]$_.id }; Descending = $false })
    $limited = @($sorted | Select-Object -First $Limit)
    foreach ($item in $limited) {
        $item.Remove("_status_rank")
        $item.Remove("_updated_sort")
    }
    return @($limited)
}

# Test-CatalogRecordEquality: compare generated metadata with the discardable cache record.
function Test-CatalogRecordEquality {
    param(
        [Parameter(Mandatory = $true)][object]$Left,
        [Parameter(Mandatory = $true)][object]$Right,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    foreach ($field in @("type", "id", "path", "schema", "status", "title", "summary", "updated", "kind", "exposure", "size", "mtime", "content_hash")) {
        if ([string](Get-PropertyValue $Left $field) -cne [string](Get-PropertyValue $Right $field)) {
            Add-Finding -Findings $Findings -Code "catalog-content-field" -Path ([string](Get-PropertyValue $Left "path")) -Field $field -Message "Catalog scalar field differs from canonical Markdown."
            return $false
        }
    }
    foreach ($field in @("keywords", "triggers", "side_effects", "related_work", "supersedes")) {
        $leftValues = @(Get-ValueArray -Value (Get-PropertyValue $Left $field) | ForEach-Object { [string]$_ })
        $rightValues = @(Get-ValueArray -Value (Get-PropertyValue $Right $field) | ForEach-Object { [string]$_ })
        if (($leftValues -join "`n") -cne ($rightValues -join "`n")) {
            Add-Finding -Findings $Findings -Code "catalog-content-field" -Path ([string](Get-PropertyValue $Left "path")) -Field $field -Message "Catalog list field differs from canonical Markdown."
            return $false
        }
    }
    $leftGit = Get-PropertyValue $Left "git"
    $rightGit = Get-PropertyValue $Right "git"
    if (($null -eq $leftGit) -ne ($null -eq $rightGit)) {
        Add-Finding -Findings $Findings -Code "catalog-content-field" -Path ([string](Get-PropertyValue $Left "path")) -Field "git" -Message "Catalog Git anchor differs from canonical Markdown."
        return $false
    }
    if ($null -ne $leftGit) {
        foreach ($field in @("branch", "worktree", "last_verified_commit")) {
            if ([string](Get-PropertyValue $leftGit $field) -cne [string](Get-PropertyValue $rightGit $field)) {
                Add-Finding -Findings $Findings -Code "catalog-content-field" -Path ([string](Get-PropertyValue $Left "path")) -Field ("git.{0}" -f $field) -Message "Catalog Git anchor differs from canonical Markdown."
                return $false
            }
        }
    }
    return $true
}

# Get-RevisionChecks: validate Work revision hashes without writing the source file or cache.
function Get-RevisionChecks {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Assets,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $checks = New-Object 'System.Collections.Generic.List[object]'
    foreach ($asset in @($Assets | Where-Object { [string](Get-PropertyValue $_ "type") -ceq "work" } | Sort-Object path)) {
        $path = [string](Get-PropertyValue $asset "path")
        $fullPath = Assert-ProjectPath -Root $Root -RelativePath $path
        $metadata = Get-PropertyValue $asset "metadata"
        $expected = [string](Get-PropertyValue $metadata "revision")
        if ([string]::IsNullOrWhiteSpace($expected)) {
            $expected = ""
            $state = "revision_missing"
            Add-Finding -Findings $Findings -Code "revision_missing" -Path $path -Field "revision" -Message "Work item revision is missing."
            $actual = ""
        }
        else {
            try { $actual = Get-RevisionHash -Path $fullPath }
            catch {
                $actual = ""
                Add-Finding -Findings $Findings -Code "revision_invalid" -Path $path -Field "revision" -Message "Work item revision could not be normalized as UTF-8 content."
            }
            $state = if ($actual -ceq $expected) { "revision_match" } else { "revision_mismatch" }
            if ($state -eq "revision_mismatch") { Add-Finding -Findings $Findings -Code "revision_mismatch" -Path $path -Field "revision" -Message "Work item revision does not match normalized source content." }
        }
        [void]$checks.Add([ordered]@{ path = $path; expected_revision = $expected; actual_revision = $actual; state = $state })
    }
    return @($checks.ToArray())
}

# Get-OperationStatus: warnings are observable but do not make read-only
# discovery fail; structural and content errors do.
function Get-OperationStatus {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings)

    if (@($Findings.ToArray() | Where-Object { [string]$_.severity -ceq "error" }).Count -gt 0) { return "FAIL" }
    return "PASS"
}

# Get-SortedFindings: keep JSON findings stable across PowerShell hosts.
function Get-SortedFindings {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings)

    return @($Findings.ToArray() | Sort-Object code, path, field, severity, message)
}

# Read-SchemaContract: validate that the single public schema authority is readable.
function Read-SchemaContract {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings)

    foreach ($path in @($catalogSchemaPath, $glossarySchemaPath)) {
        try {
            $null = (Read-StrictUtf8Text -Path $path | ConvertFrom-Json -Depth 50 -ErrorAction Stop)
        }
        catch {
            Add-Finding -Findings $Findings -Code "schema-invalid" -Path ([string]([IO.Path]::GetRelativePath($repoRoot, $path)).Replace('\', '/')) -Message "Project workspace schema authority is not valid UTF-8 JSON."
        }
    }
}

# New-CacheSummary: expose cache state without returning cache contents or local paths.
function New-CacheSummary {
    param(
        [Parameter(Mandatory = $true)][object]$ReadResult,
        [string]$Action = "not-written",
        [object]$Catalog = $null,
        [Nullable[bool]]$Fresh = $null,
        [string]$Reason = ""
    )

    $summary = [ordered]@{
        path = $catalogRelativePath
        state = [string]$ReadResult.state
        action = $Action
        read_only = ($Action -eq "not-written" -or $Action -eq "reused")
    }
    if ($null -ne $Fresh) { $summary.fresh = [bool]$Fresh }
    if (-not [string]::IsNullOrWhiteSpace($Reason)) { $summary.reason = $Reason }
    if ($null -ne $Catalog) {
        $summary.asset_count = [int](Get-PropertyValue $Catalog "asset_count")
        $summary.directory_fingerprint = [string](Get-PropertyValue $Catalog "directory_fingerprint")
        $summary.schema_fingerprint = [string](Get-PropertyValue $Catalog "schema_fingerprint")
        $summary.glossary_fingerprint = [string](Get-PropertyValue $Catalog "glossary_fingerprint")
    }
    return $summary
}

# Invoke-DiscoverOperation: build/reuse the discardable catalog, then search it.
function Invoke-DiscoverOperation {
    param([Parameter(Mandatory = $true)][string]$Root)

    $findings = New-Object 'System.Collections.Generic.List[object]'
    $rootFull = Get-NormalizedFullPath -Path $Root
    try {
        if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) { throw "project root is not a directory" }
        Assert-ProjectPath -Root $rootFull -RelativePath ".agents" -AllowMissing | Out-Null
    }
    catch {
        Add-Finding -Findings $findings -Code "project-root-invalid" -Path "" -Message "Project root does not exist or is not a safe directory."
    }

    $fileRecords = @()
    try { $fileRecords = @(Get-CanonicalFileRecords -Root $rootFull -Findings $findings) }
    catch { Add-Finding -Findings $findings -Code "canonical-enumeration" -Path "" -Message "Canonical project assets could not be enumerated safely." }
    $directoryFingerprint = ""
    try { $directoryFingerprint = Get-DirectoryFingerprint -Records $fileRecords }
    catch { Add-Finding -Findings $findings -Code "directory-fingerprint" -Path "" -Message "Canonical directory fingerprint could not be computed." }
    $schemaFingerprint = ""
    try { Read-SchemaContract -Findings $findings; $schemaFingerprint = Get-SchemaFingerprint }
    catch { Add-Finding -Findings $findings -Code "schema-invalid" -Path "schemas/project-workspace" -Message "Project workspace schema fingerprint could not be computed." }
    $glossary = Read-Glossary -Root $rootFull -Findings $findings
    $catalogReadFindings = New-Object 'System.Collections.Generic.List[object]'
    $catalogRead = $null
    try { $catalogRead = Get-CatalogReadResult -Root $rootFull -Findings $catalogReadFindings }
    catch { $catalogRead = [ordered]@{ state = "missing"; path = $catalogRelativePath; payload = $null } }
    $cacheShapeFindings = New-Object 'System.Collections.Generic.List[object]'
    $cacheShapeValid = $false
    if ($catalogRead.state -eq "present") { $cacheShapeValid = Test-CatalogShape -Catalog $catalogRead.payload -Findings $cacheShapeFindings }
    $catalog = $null
    $cacheAction = "not-written"
    $cacheReason = ""
    $cacheFresh = $false

    if ($glossary.state -in @("valid", "absent") -and @($findings.ToArray() | Where-Object { [string]$_.severity -ceq "error" }).Count -eq 0) {
        if ($cacheShapeValid -and
            [string](Get-PropertyValue $catalogRead.payload "directory_fingerprint") -ceq $directoryFingerprint -and
            [string](Get-PropertyValue $catalogRead.payload "schema_fingerprint") -ceq $schemaFingerprint -and
            [string](Get-PropertyValue $catalogRead.payload "glossary_fingerprint") -ceq [string]$glossary.fingerprint -and
            (Test-CatalogMatchesFiles -Catalog $catalogRead.payload -FileRecords $fileRecords)) {
            $catalog = $catalogRead.payload
            $cacheAction = "reused"
            $cacheFresh = $true
            $cacheReason = "fingerprints_match"
        }
        else {
            $incremental = $false
            $changedPaths = @()
            if ($cacheShapeValid -and
                [string](Get-PropertyValue $catalogRead.payload "schema_fingerprint") -ceq $schemaFingerprint -and
                [string](Get-PropertyValue $catalogRead.payload "glossary_fingerprint") -ceq [string]$glossary.fingerprint) {
                $incremental = $true
                $changedPaths = @(Get-ChangedCanonicalPaths -Catalog $catalogRead.payload -FileRecords $fileRecords)
                if ($changedPaths.Count -eq 0) { $incremental = $false }
            }
            if ($incremental) {
                $parsed = Convert-ParserAssetsToCatalog -Root $rootFull -FileRecords $fileRecords -Paths $changedPaths -Findings $findings
                if ($parsed.success) {
                    $merged = Merge-IncrementalCatalog -OldCatalog $catalogRead.payload -FileRecords $fileRecords -ChangedRecords $parsed.records
                    $catalog = New-CatalogPayload -DirectoryFingerprint $directoryFingerprint -SchemaFingerprint $schemaFingerprint -GlossaryFingerprint ([string]$glossary.fingerprint) -Assets $merged
                    $cacheReason = "changed_paths"
                }
            }
            else {
                $parsed = Convert-ParserAssetsToCatalog -Root $rootFull -FileRecords $fileRecords -Paths @() -Findings $findings
                if ($parsed.success) {
                    $catalog = New-CatalogPayload -DirectoryFingerprint $directoryFingerprint -SchemaFingerprint $schemaFingerprint -GlossaryFingerprint ([string]$glossary.fingerprint) -Assets $parsed.records
                    $cacheReason = if ($catalogRead.state -eq "missing") { "missing" } elseif ($catalogRead.state -eq "invalid") { "corrupt" } elseif (-not $cacheShapeValid) { "schema_invalid" } elseif ([string](Get-PropertyValue $catalogRead.payload "schema_fingerprint") -cne $schemaFingerprint) { "schema_changed" } elseif ([string](Get-PropertyValue $catalogRead.payload "glossary_fingerprint") -cne [string]$glossary.fingerprint) { "glossary_changed" } else { "directory_changed" }
                }
            }
            if ($null -ne $catalog -and (Get-OperationStatus -Findings $findings) -eq "PASS") {
                try {
                    Write-CatalogAtomic -Root $rootFull -Catalog $catalog
                    $cacheAction = "written"
                }
                catch {
                    Add-Finding -Findings $findings -Code "catalog-write" -Path $catalogRelativePath -Message "Discover could not atomically update the catalog cache."
                    $cacheAction = "not-written"
                }
            }
            else { $cacheAction = "not-written" }
        }
    }
    else {
        $cacheReason = "source_validation_failed"
    }

    $gitFindings = New-Object 'System.Collections.Generic.List[object]'
    $git = Get-GitState -Root $rootFull -Findings $gitFindings
    foreach ($finding in @($gitFindings.ToArray())) { [void]$findings.Add($finding) }
    $results = @()
    if ($null -ne $catalog -and (Get-OperationStatus -Findings $findings) -eq "PASS") {
        $catalogAssets = @(Get-ValueArray -Value (Get-PropertyValue $catalog "assets"))
        $results = @(Get-SearchResults -Assets $catalogAssets -Glossary $glossary -GitState $git -Query $Query -Limit $Limit -Types $Type -Statuses $Status -CurrentBranchOnly:$CurrentBranchOnly -Findings $findings)
    }
    $catalogSummaryRead = if ($null -ne $catalog) { [ordered]@{ state = "present"; path = $catalogRelativePath } } else { $catalogRead }
    $cacheSummary = New-CacheSummary -ReadResult $catalogSummaryRead -Action $cacheAction -Catalog $catalog -Fresh $cacheFresh -Reason $cacheReason
    $output = [ordered]@{
        operation = "discover"
        status = Get-OperationStatus -Findings $findings
        query = [string]$Query
        normalized_query = Normalize-SearchText -Text $Query
        limit = $Limit
        filters = [ordered]@{ type = @($Type); status = @($Status); current_branch_only = [bool]$CurrentBranchOnly.IsPresent }
        catalog = $cacheSummary
        glossary = [ordered]@{ state = [string]$glossary.state; fingerprint = [string]$glossary.fingerprint; term_count = @($glossary.terms).Count }
        git = $git
        result_count = @($results).Count
        results = @($results)
        findings = @(Get-SortedFindings -Findings $findings)
    }
    return $output
}

# Invoke-CheckOperation: strict read-only validation of source, cache, Git, and Work revisions.
function Invoke-CheckOperation {
    param([Parameter(Mandatory = $true)][string]$Root)

    $findings = New-Object 'System.Collections.Generic.List[object]'
    $rootFull = Get-NormalizedFullPath -Path $Root
    try {
        if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) { throw "project root is not a directory" }
    }
    catch { Add-Finding -Findings $findings -Code "project-root-invalid" -Path "" -Message "Project root does not exist or is not a safe directory." }
    $fileRecords = @()
    try { $fileRecords = @(Get-CanonicalFileRecords -Root $rootFull -Findings $findings) }
    catch { Add-Finding -Findings $findings -Code "canonical-enumeration" -Path "" -Message "Canonical project assets could not be enumerated safely." }
    $directoryFingerprint = ""
    $schemaFingerprint = ""
    try { $directoryFingerprint = Get-DirectoryFingerprint -Records $fileRecords } catch { Add-Finding -Findings $findings -Code "directory-fingerprint" -Path "" -Message "Canonical directory fingerprint could not be computed." }
    try { Read-SchemaContract -Findings $findings; $schemaFingerprint = Get-SchemaFingerprint } catch { Add-Finding -Findings $findings -Code "schema-invalid" -Path "schemas/project-workspace" -Message "Project workspace schema fingerprint could not be computed." }
    $glossary = Read-Glossary -Root $rootFull -Findings $findings
    $parserInvocation = Invoke-CanonicalParser -Root $rootFull -Paths @()
    if ($null -eq $parserInvocation.payload) { Add-Finding -Findings $findings -Code "canonical-parser" -Path "" -Message "Canonical parser did not return structured JSON." }
    elseif ([string]$parserInvocation.payload.status -cne "PASS") {
        foreach ($finding in @($parserInvocation.payload.findings)) { Add-Finding -Findings $findings -Code ("canonical-{0}" -f [string]$finding.code) -Path ([string]$finding.path) -Field ([string]$finding.field) -Message "Canonical Markdown parser rejected an asset." }
    }
    $currentRecordsResult = Convert-ParserAssetsToCatalog -Root $rootFull -FileRecords $fileRecords -Paths @() -Findings $findings
    $currentRecords = @($currentRecordsResult.records)
    $catalogFindings = New-Object 'System.Collections.Generic.List[object]'
    $catalogRead = $null
    try { $catalogRead = Get-CatalogReadResult -Root $rootFull -Findings $catalogFindings }
    catch { $catalogRead = [ordered]@{ state = "missing"; path = $catalogRelativePath; payload = $null } }
    $catalogShapeValid = $false
    if ($catalogRead.state -eq "present") { $catalogShapeValid = Test-CatalogShape -Catalog $catalogRead.payload -Findings $catalogFindings }
    if ($catalogRead.state -eq "missing") {
        Add-Finding -Findings $findings -Code "catalog-missing" -Path $catalogRelativePath -Message "Catalog cache is absent; discover may rebuild it." -Severity warning
    }
    elseif (-not $catalogShapeValid) {
        foreach ($finding in @($catalogFindings.ToArray())) { [void]$findings.Add($finding) }
    }
    $catalogFresh = $null
    if ($catalogShapeValid) {
        $catalog = $catalogRead.payload
        $fingerprintsMatch = ([string](Get-PropertyValue $catalog "directory_fingerprint") -ceq $directoryFingerprint -and [string](Get-PropertyValue $catalog "schema_fingerprint") -ceq $schemaFingerprint -and [string](Get-PropertyValue $catalog "glossary_fingerprint") -ceq [string]$glossary.fingerprint)
        $catalogFresh = ($fingerprintsMatch -and (Test-CatalogMatchesFiles -Catalog $catalog -FileRecords $fileRecords))
        if (-not $catalogFresh) { Add-Finding -Findings $findings -Code "catalog-stale" -Path $catalogRelativePath -Message "Catalog fingerprints or canonical file metadata are stale." }
        $catalogByPath = @{}
        foreach ($cached in @(Get-ValueArray -Value (Get-PropertyValue $catalog "assets"))) { $catalogByPath[[string](Get-PropertyValue $cached "path")] = $cached }
        foreach ($record in @($currentRecords)) {
            $path = [string]$record.path
            if (-not $catalogByPath.ContainsKey($path) -or -not (Test-CatalogRecordEquality -Left $record -Right $catalogByPath[$path] -Findings $findings)) {
                Add-Finding -Findings $findings -Code "catalog-content" -Path $path -Message "Catalog metadata or content hash differs from canonical Markdown."
            }
        }
    }
    $revisions = @()
    if ($null -ne $parserInvocation.payload -and [string]$parserInvocation.payload.status -ceq "PASS") {
        $revisions = @(Get-RevisionChecks -Root $rootFull -Assets @($parserInvocation.payload.assets) -Findings $findings)
    }
    $gitFindings = New-Object 'System.Collections.Generic.List[object]'
    $git = Get-GitState -Root $rootFull -Findings $gitFindings
    foreach ($finding in @($gitFindings.ToArray())) { [void]$findings.Add($finding) }
    $anchors = New-Object 'System.Collections.Generic.List[object]'
    foreach ($record in @($currentRecords | Where-Object { $null -ne (Get-PropertyValue $_ "git") } | Sort-Object path)) {
        $anchor = Test-GitAnchor -Asset $record -Root $rootFull -GitState $git -Findings $findings
        if ($null -ne $anchor) { [void]$anchors.Add([ordered]@{ path = [string]$record.path; branch = [string]$anchor.branch; branch_state = [string]$anchor.branch_state; commit_state = [string]$anchor.commit_state }) }
    }
    $assetStates = @($currentRecords | Sort-Object path | ForEach-Object { [ordered]@{ type = [string]$_.type; id = [string]$_.id; path = [string]$_.path; state = "canonical_valid" } })
    $catalogSummaryRead = $catalogRead
    $cacheSummary = New-CacheSummary -ReadResult $catalogSummaryRead -Action "not-written" -Catalog $(if ($catalogShapeValid) { $catalogRead.payload } else { $null }) -Fresh $catalogFresh -Reason $(if ($catalogRead.state -eq "missing") { "missing" } elseif (-not $catalogShapeValid) { "invalid" } else { "read_only_check" })
    $output = [ordered]@{
        operation = "check"
        status = Get-OperationStatus -Findings $findings
        read_only = $true
        catalog = $cacheSummary
        glossary = [ordered]@{ state = [string]$glossary.state; fingerprint = [string]$glossary.fingerprint; term_count = @($glossary.terms).Count }
        git = $git
        assets = $assetStates
        anchors = @($anchors.ToArray())
        revisions = @($revisions)
        findings = @(Get-SortedFindings -Findings $findings)
    }
    return $output
}

# Write-OperationResult: keep human output compact and JSON output structured.
function Write-OperationResult {
    param([Parameter(Mandatory = $true)][object]$Result)

    if ($Json.IsPresent) {
        $Result | ConvertTo-Json -Depth 50
    }
    else {
        Write-Output ("project-workspace {0}: {1}" -f $Result.operation, $Result.status)
        if ($Result.operation -eq "discover") { Write-Output ("results={0} cache={1}" -f $Result.result_count, $Result.catalog.action) }
        else { Write-Output ("read_only={0} revisions={1}" -f $Result.read_only, @($Result.revisions).Count) }
        foreach ($finding in @($Result.findings)) { Write-Output ("[{0}] {1} {2}" -f $finding.severity, $finding.code, $finding.path) }
    }
}

try {
    $result = if ($Operation -ceq "discover") { Invoke-DiscoverOperation -Root $ProjectRoot } else { Invoke-CheckOperation -Root $ProjectRoot }
    Write-OperationResult -Result $result
    $exitCode = if ([string]$result.status -ceq "PASS") { 0 } else { 1 }
}
catch {
    $failureMessage = "Project workspace operation failed closed."
    $failure = [ordered]@{
        operation = $Operation
        status = "FAIL"
        read_only = ($Operation -ceq "check")
        findings = @([ordered]@{ code = "unexpected-error"; path = ""; field = ""; severity = "error"; message = $failureMessage })
    }
    Write-OperationResult -Result $failure
    $exitCode = 1
}

if ($NoExit.IsPresent) {
    $global:LASTEXITCODE = $exitCode
}
else {
    exit $exitCode
}
