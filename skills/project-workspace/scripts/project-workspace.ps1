#requires -Version 7.6

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][Alias("Mode")][ValidateSet("discover", "check", "create-work", "checkpoint", "set-status", "complete", "recover-work", "create-context", "create-procedure", "promote-skill", "create-spec")][string]$Operation,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$Query = "",
    [Alias("MaxResults")][ValidateRange(1, 100)][int]$Limit = 5,
    [Alias("AssetType")][string[]]$Type = @(),
    [Alias("State")][string[]]$Status = @(),
    [switch]$CurrentBranchOnly,
    [string]$Id = "",
    [string]$Title = "",
    [string]$Summary = "",
    [string]$Next = "",
    [string]$ContinuityReason = "",
    [string]$BaseRevision = "",
    [string]$GitBranch = "",
    [string]$GitWorktree = "",
    [string]$GitLastVerifiedCommit = "",
    [string[]]$Verified = @(),
    [string[]]$Boundary = @(),
    [string[]]$Blocker = @(),
    [Alias("Keyword")][string[]]$Keywords = @(),
    [string[]]$Evidence = @(),
    [Alias("Trigger")][string[]]$Triggers = @(),
    [Alias("SideEffect")][string[]]$SideEffects = @(),
    [string]$Kind = "",
    [Alias("Precondition")][string[]]$Preconditions = @(),
    [Alias("Step")][string[]]$Steps = @(),
    [string[]]$Validation = @(),
    [Alias("StopBoundary", "Stop")][string[]]$StopBoundaries = @(),
    [string[]]$Authorization = @(),
    [Alias("Goal")][string[]]$Goals = @(),
    [Alias("NonGoal")][string[]]$NonGoals = @(),
    [Alias("Tradeoff")][string[]]$Tradeoffs = @(),
    [string[]]$Acceptance = @(),
    [string[]]$RelatedWork = @(),
    [string[]]$Supersedes = @(),
    [Alias("Name")][string]$SkillName = "",
    [switch]$Analyze,
    [switch]$Apply,
    [string]$AnalyzeEvidence = "",
    [switch]$ConfirmPromotion,
    [string]$Updated = "",
    [switch]$ResultPersisted,
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

# Get-CanonicalFileRecords: enumerate the four canonical project asset roots and return cache-local metadata.
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

# Get-PromotedSkillFileRecords: enumerate promoted Agent Skills only as a disposable discover projection input.
# Skill files are never returned by the canonical parser and never become a canonical project asset authority.
function Get-PromotedSkillFileRecords {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $records = New-Object 'System.Collections.Generic.List[object]'
    $skillRoot = Join-Path $Root ".agents/skills"
    if (-not (Test-Path -LiteralPath $skillRoot -PathType Container)) { return @() }
    foreach ($directory in @(Get-ChildItem -LiteralPath $skillRoot -Directory -Force | Sort-Object Name)) {
        $file = Join-Path $directory.FullName "SKILL.md"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $relative = [IO.Path]::GetRelativePath($Root, $file).Replace('\', '/')
        try {
            Assert-ProjectPath -Root $Root -RelativePath $relative | Out-Null
        }
        catch {
            Add-Finding -Findings $Findings -Code "unsafe-path" -Path $relative -Message "Promoted Skill path cannot be resolved safely inside the project root."
            continue
        }
        $item = Get-Item -LiteralPath $file -Force
        [void]$records.Add([ordered]@{
            path = $relative
            type = "skill"
            size = [long]$item.Length
            mtime = $item.LastWriteTimeUtc.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
            full_path = $item.FullName
        })
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

# Load internal responsibilities without changing the single external Skill/command surface.
$internalModules = @(
    "project-workspace-catalog.ps1",
    "project-workspace-glossary-query.ps1",
    "project-workspace-git.ps1",
    "project-workspace-revision-check.ps1",
    "project-workspace-authoring.ps1",
    "project-continuity.ps1"
)
foreach ($internalModule in $internalModules) {
    $internalModulePath = Join-Path $scriptDir $internalModule
    if (-not (Test-Path -LiteralPath $internalModulePath -PathType Leaf)) {
        throw ("Project workspace internal module is missing: {0}" -f $internalModule)
    }
    . $internalModulePath
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

    $canonicalFileRecords = @()
    $skillFileRecords = @()
    try { $canonicalFileRecords = @(Get-CanonicalFileRecords -Root $rootFull -Findings $findings) }
    catch { Add-Finding -Findings $findings -Code "canonical-enumeration" -Path "" -Message "Canonical project assets could not be enumerated safely." }
    try { $skillFileRecords = @(Get-PromotedSkillFileRecords -Root $rootFull -Findings $findings) }
    catch { Add-Finding -Findings $findings -Code "skill-enumeration" -Path "" -Message "Promoted Skill projections could not be enumerated safely." }
    $fileRecords = @($canonicalFileRecords) + @($skillFileRecords)
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
                $parsedCanonical = Convert-ParserAssetsToCatalog -Root $rootFull -FileRecords $fileRecords -Paths $changedPaths -Findings $findings
                $parsedSkills = Convert-PromotedSkillsToCatalog -Root $rootFull -FileRecords $fileRecords -Paths $changedPaths -Findings $findings
                if ($parsedCanonical.success -and $parsedSkills.success) {
                    $changedRecords = @($parsedCanonical.records) + @($parsedSkills.records)
                    $merged = Merge-IncrementalCatalog -OldCatalog $catalogRead.payload -FileRecords $fileRecords -ChangedRecords $changedRecords
                    $catalog = New-CatalogPayload -DirectoryFingerprint $directoryFingerprint -SchemaFingerprint $schemaFingerprint -GlossaryFingerprint ([string]$glossary.fingerprint) -Assets $merged
                    $cacheReason = "changed_paths"
                }
            }
            else {
                $parsedCanonical = Convert-ParserAssetsToCatalog -Root $rootFull -FileRecords $fileRecords -Paths @() -Findings $findings
                $parsedSkills = Convert-PromotedSkillsToCatalog -Root $rootFull -FileRecords $fileRecords -Paths @() -Findings $findings
                if ($parsedCanonical.success -and $parsedSkills.success) {
                    $records = @($parsedCanonical.records) + @($parsedSkills.records)
                    $catalog = New-CatalogPayload -DirectoryFingerprint $directoryFingerprint -SchemaFingerprint $schemaFingerprint -GlossaryFingerprint ([string]$glossary.fingerprint) -Assets $records
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

# Write-OperationResult: keep human output compact and JSON output structured.
function Write-OperationResult {
    param([Parameter(Mandatory = $true)][object]$Result)

    if ($Json.IsPresent) {
        $Result | ConvertTo-Json -Depth 50
    }
    else {
        Write-Output ("project-workspace {0}: {1}" -f $Result.operation, $Result.status)
        if ($Result.operation -eq "discover") { Write-Output ("results={0} cache={1}" -f $Result.result_count, $Result.catalog.action) }
        elseif ($Result.operation -eq "check") { Write-Output ("read_only={0} revisions={1}" -f $Result.read_only, @($Result.revisions).Count) }
        elseif ($Result.operation -eq "recover-work") { Write-Output ("read_only={0} classification={1} degraded={2}" -f $Result.read_only, $Result.classification, $Result.degraded) }
        else { Write-Output ("result={0} path={1}" -f $Result.result, $Result.path) }
        foreach ($finding in @($Result.findings)) { Write-Output ("[{0}] {1} {2}" -f $finding.severity, $finding.code, $finding.path) }
    }
}

try {
    $result = if ($Operation -ceq "discover") {
        Invoke-DiscoverOperation -Root $ProjectRoot
    }
    elseif ($Operation -ceq "check") {
        Invoke-CheckOperation -Root $ProjectRoot
    }
    elseif ($Operation -in @("create-context", "create-procedure", "promote-skill", "create-spec")) {
        Invoke-AuthoringOperation -Operation $Operation -Root (Resolve-AuthoringRoot -Root $ProjectRoot) -BoundParameters $PSBoundParameters
    }
    else {
        Invoke-ContinuityOperation -Operation $Operation -Root $ProjectRoot -BoundParameters $PSBoundParameters
    }
    Write-OperationResult -Result $result
    $exitCode = if ([string]$result.status -ceq "PASS") { 0 } else { 1 }
}
catch {
    $failureMessage = "Project workspace operation failed closed."
    $failure = [ordered]@{
        operation = $Operation
        status = "FAIL"
        read_only = ($Operation -in @("check", "recover-work") -or ($Operation -ceq "promote-skill" -and $Analyze.IsPresent))
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
