[CmdletBinding()]
param(
    [ValidateSet("Discover", "Intake", "List", "Export", "Triage")]
    [string]$Mode = "Discover",
    [string]$InboxDir = "",
    [string[]]$ProjectRoot = @(),
    [string[]]$Language = @(),
    [ValidateSet("pending_review", "accepted", "rejected", "superseded")]
    [string]$Status = "pending_review",
    [string]$CandidateId = "",
    [string]$SupersededBy = "",
    [string[]]$MergeCandidateId = @(),
    [string]$ReviewedBy = "",
    [string]$ReviewNote = "",
    [string]$ObservedOn = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd"),
    [switch]$Json
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$script:AllowedStatuses = @("pending_review", "accepted", "rejected", "superseded")
$script:Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:PathComparison = if ($env:OS -eq "Windows_NT") {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($full.Equals($root, $script:PathComparison)) {
        return $root
    }
    return $full.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Get-PathWithSeparator {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FullPath -Path $Path) + [System.IO.Path]::DirectorySeparatorChar
}

function Test-PathContainedBy {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $pathFull = Get-FullPath -Path $Path
    $rootFull = Get-FullPath -Path $Root
    if ($pathFull.Equals($rootFull, $script:PathComparison)) {
        return $true
    }
    return $pathFull.StartsWith((Get-PathWithSeparator -Path $rootFull), $script:PathComparison)
}

function Assert-NoReparsePoint {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must not be a reparse point: $Path"
    }
}

function Read-Utf8Text {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        return [System.IO.File]::ReadAllText((Get-FullPath -Path $Path), $script:Utf8Strict)
    }
    catch {
        throw "File is not strict UTF-8 or could not be read: $Path. $($_.Exception.Message)"
    }
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $normalized = ($Text -replace "`r`n", "`n")
    [System.IO.File]::WriteAllText((Get-FullPath -Path $Path), $normalized, $script:Utf8NoBom)
}

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $script:Utf8NoBom.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Sha256File {
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead((Get-FullPath -Path $Path))
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

function Normalize-SingleLine {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [switch]$Lowercase
    )
    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormKC)
    $normalized = [regex]::Replace($normalized.Trim(), '\s+', ' ')
    if ($Lowercase.IsPresent) {
        $normalized = $normalized.ToLowerInvariant()
    }
    return $normalized
}

function Normalize-MultilineText {
    param([Parameter(Mandatory = $true)][string]$Text)
    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormKC)
    $normalized = $normalized -replace "`r`n", "`n"
    $normalized = [regex]::Replace($normalized.Trim(), '\s+', ' ')
    return $normalized
}

function Sort-OrdinalStrings {
    param([object[]]$Values = @())
    $strings = [string[]]@($Values | ForEach-Object { [string]$_ })
    [System.Array]::Sort($strings, [System.StringComparer]::Ordinal)
    return @($strings)
}

function Get-TitleSlug {
    param([Parameter(Mandatory = $true)][string]$Title)
    $slug = (Normalize-SingleLine -Text $Title -Lowercase)
    $slug = [regex]::Replace($slug, '[^\p{L}\p{Nd}]+', '-')
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = "candidate"
    }
    if ($slug.Length -gt 48) {
        $slug = $slug.Substring(0, 48).TrimEnd('-')
    }
    return $slug
}

function Assert-IsoDate {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Field
    )
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Value, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        throw "$Field must use YYYY-MM-DD: $Value"
    }
}

function Get-MarkdownSection {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Heading
    )
    $pattern = '(?ms)^##\s+' + [regex]::Escape($Heading) + '\s*\r?\n(?<body>.*?)(?=^##\s+|\z)'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        return ""
    }
    return $match.Groups['body'].Value.Trim()
}

function Get-ExperienceTitle {
    param([Parameter(Mandatory = $true)][string]$Text)
    $match = [regex]::Match($Text, '(?m)^#\s+(?<title>[^#\r\n].*)$')
    if (-not $match.Success) {
        throw "Experience candidate is missing a level-one title."
    }
    return (Normalize-SingleLine -Text $match.Groups['title'].Value)
}

function Get-ExperienceKeywords {
    param([Parameter(Mandatory = $true)][string]$Text)
    $body = Get-MarkdownSection -Text $Text -Heading "Keywords"
    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "Experience candidate is missing the canonical ## Keywords section."
    }
    $items = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @($body -split "`r?`n")) {
        $value = $line.Trim()
        $bullet = [regex]::Match($value, '^[-*]\s+(?<value>.+)$')
        if ($bullet.Success) {
            $value = $bullet.Groups['value'].Value
        }
        elseif ($value -notmatch ',' -or $value -match ':') {
            continue
        }
        foreach ($part in @($value -split ',')) {
            if ([string]::IsNullOrWhiteSpace($part)) {
                continue
            }
            $keyword = Normalize-SingleLine -Text $part
            if (-not [string]::IsNullOrWhiteSpace($keyword) -and -not $items.Contains($keyword)) {
                $items.Add($keyword)
            }
        }
    }
    return @(Sort-OrdinalStrings -Values $items.ToArray())
}

function Test-GlobalCandidateAnchor {
    param([Parameter(Mandatory = $true)][string]$Text)
    $patterns = @(
        '(?im)^\s*[-*]?\s*\*{0,2}Global candidate\*{0,2}\s*:\s*Yes\b',
        '(?im)^\s*[-*]?\s*\*{0,2}Scope\*{0,2}\s*:\s*Cross-project reusable\b'
    )
    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }
    return $false
}

function Assert-PublicSafeValue {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Field
    )
    if ($Value -match '(?i)(^|[\s"''(])(?:[A-Za-z]:[\\/]|\\\\|/(?:Users|home|private|tmp|var|mnt|Volumes)/)') {
        throw "Public-safe field '$Field' contains an absolute path. Move local review pointers under _local."
    }
    if ($Value -match '(?i)\b(?:access|sensitive)[ _-]?(?:material|value)\s*[:=]\s*\S+') {
        throw "Public-safe field '$Field' contains access material."
    }
}

function New-DiscoveredCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$ProjectLanguage,
        [Parameter(Mandatory = $true)][string]$Date
    )

    $text = Read-Utf8Text -Path $SourceFile
    if (-not (Test-GlobalCandidateAnchor -Text $text)) {
        return $null
    }
    $title = Get-ExperienceTitle -Text $text
    $summaryBody = Get-MarkdownSection -Text $text -Heading "Summary"
    if ([string]::IsNullOrWhiteSpace($summaryBody)) {
        throw "Experience candidate is missing the canonical ## Summary section: $SourceFile"
    }
    $summary = Normalize-MultilineText -Text $summaryBody
    $keywords = @(Get-ExperienceKeywords -Text $text)
    $languageValue = Normalize-SingleLine -Text $ProjectLanguage
    if ([string]::IsNullOrWhiteSpace($languageValue)) {
        throw "Language must be supplied explicitly for every project root."
    }

    Assert-PublicSafeValue -Value $title -Field "title"
    Assert-PublicSafeValue -Value $summary -Field "summary"
    foreach ($keyword in $keywords) {
        Assert-PublicSafeValue -Value $keyword -Field "keywords"
    }

    $normalizedTitle = Normalize-SingleLine -Text $title -Lowercase
    $normalizedSummary = Normalize-MultilineText -Text $summary
    $summaryHash = Get-Sha256Text -Text $normalizedSummary
    $dedupeKey = "{0}|{1}|{2}" -f $languageValue.ToLowerInvariant(), $normalizedTitle, $summaryHash
    $dedupeHash = Get-Sha256Text -Text $dedupeKey
    $candidateId = "candidate-$dedupeHash"
    $sourceHash = Get-Sha256File -Path $SourceFile
    $rootFull = Get-FullPath -Path $Root
    $sourceFull = Get-FullPath -Path $SourceFile
    $relative = $sourceFull.Substring($rootFull.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar).Replace('\', '/')
    $rootIdentity = $rootFull.Replace('\', '/')
    $relativeIdentity = $relative
    if ($env:OS -eq "Windows_NT") {
        $rootIdentity = $rootIdentity.ToLowerInvariant()
        $relativeIdentity = $relativeIdentity.ToLowerInvariant()
    }
    $sourceKey = Get-Sha256Text -Text ($rootIdentity + "|" + $relativeIdentity + "|" + $sourceHash)

    return [pscustomobject][ordered]@{
        schema_version = 1
        candidate_id = $candidateId
        dedupe_key = $dedupeKey
        language = $languageValue
        title = $title
        normalized_title = $normalizedTitle
        summary = $summary
        normalized_summary_hash = $summaryHash
        keywords = @($keywords)
        status = "pending_review"
        occurrence_count = 1
        first_seen_on = $Date
        last_seen_on = $Date
        reviewed_on = ""
        superseded_by = ""
        merged_from = @()
        _local = [pscustomobject][ordered]@{
            sources = @(
                [pscustomobject][ordered]@{
                    source_key = $sourceKey
                    project_root = $rootFull
                    source_file = $sourceFull
                    source_hash = $sourceHash
                    observed_on = $Date
                }
            )
            reviews = @()
        }
    }
}

function Get-ProjectLanguages {
    param(
        [Parameter(Mandatory = $true)][string[]]$Roots,
        [Parameter(Mandatory = $true)][string[]]$Languages
    )
    if ($Languages.Count -eq 1 -and $Roots.Count -gt 1) {
        return @($Roots | ForEach-Object { $Languages[0] })
    }
    if ($Languages.Count -ne $Roots.Count) {
        throw "Language must contain one value for all roots or one value per ProjectRoot. Language detection is intentionally not performed."
    }
    return @($Languages)
}

function Find-ProjectCandidates {
    param(
        [Parameter(Mandatory = $true)][string[]]$Roots,
        [Parameter(Mandatory = $true)][string[]]$Languages,
        [Parameter(Mandatory = $true)][string]$Date,
        [string]$WritableInbox = ""
    )

    if ($Roots.Count -eq 0) {
        throw "ProjectRoot is required for explicit legacy/import discovery."
    }
    $resolvedLanguages = @(Get-ProjectLanguages -Roots $Roots -Languages $Languages)
    $results = New-Object 'System.Collections.Generic.List[object]'
    for ($index = 0; $index -lt $Roots.Count; $index++) {
        $root = Get-FullPath -Path $Roots[$index]
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            throw "Project root not found: $root"
        }
        Assert-NoReparsePoint -Path $root -Label "Project root"
        if (-not [string]::IsNullOrWhiteSpace($WritableInbox)) {
            $inbox = Get-FullPath -Path $WritableInbox
            if ((Test-PathContainedBy -Path $inbox -Root $root) -or (Test-PathContainedBy -Path $root -Root $inbox)) {
                throw "Project root and writable inbox must not overlap: project=$root inbox=$inbox"
            }
        }

        $experienceDir = Join-Path (Join-Path (Join-Path $root ".agents") "context") "experience"
        if (-not (Test-Path -LiteralPath $experienceDir -PathType Container)) {
            continue
        }
        Assert-NoReparsePoint -Path $experienceDir -Label "Project experience directory"
        foreach ($directory in @(Get-ChildItem -LiteralPath $experienceDir -Directory -Recurse -Force | Sort-Object FullName)) {
            Assert-NoReparsePoint -Path $directory.FullName -Label "Project experience subdirectory"
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $experienceDir -File -Recurse -Filter "*.md" -Force | Sort-Object FullName)) {
            Assert-NoReparsePoint -Path $file.FullName -Label "Project experience file"
            $candidate = New-DiscoveredCandidate -Root $root -SourceFile $file.FullName -ProjectLanguage $resolvedLanguages[$index] -Date $Date
            if ($null -ne $candidate) {
                $results.Add($candidate)
            }
        }
    }
    return @($results.ToArray() | Sort-Object candidate_id)
}

function Get-CandidateFilename {
    param([Parameter(Mandatory = $true)][object]$Candidate)
    $shortHash = (Get-Sha256Text -Text ([string]$Candidate.dedupe_key)).Substring(0, 12)
    return "{0}-{1}-{2}.md" -f [string]$Candidate.first_seen_on, (Get-TitleSlug -Title ([string]$Candidate.title)), $shortHash
}

function ConvertTo-CandidateMarkdown {
    param([Parameter(Mandatory = $true)][object]$Candidate)
    $jsonText = $Candidate | ConvertTo-Json -Depth 12 -Compress
    $jsonText = $jsonText -replace "`r`n", "`n"
    $keywordLines = @($Candidate.keywords | ForEach-Object { "- $_" }) -join "`n"
    return "---`n$jsonText`n---`n# $($Candidate.title)`n`n## Summary`n`n$($Candidate.summary)`n`n## Keywords`n`n$keywordLines`n"
}

function ConvertFrom-CandidateMarkdown {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $match = [regex]::Match($Text, '(?s)\A---\r?\n(?<json>.*?)\r?\n---\r?\n(?<body>.*)\z')
    if (-not $match.Success) {
        throw "Malformed candidate front matter: $Path"
    }
    try {
        $candidate = $match.Groups['json'].Value | ConvertFrom-Json
    }
    catch {
        throw "Malformed candidate JSON front matter: $Path. $($_.Exception.Message)"
    }
    $candidate | Add-Member -NotePropertyName "__path" -NotePropertyValue $Path -Force
    $candidate | Add-Member -NotePropertyName "__body" -NotePropertyValue $match.Groups['body'].Value -Force
    return $candidate
}

function Test-RequiredProperty {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path
    )
    if ($Object.PSObject.Properties.Name -notcontains $Name) {
        throw "Candidate is missing required property '$Name': $Path"
    }
}

function Assert-Candidate {
    param([Parameter(Mandatory = $true)][object]$Candidate)
    $path = if ($Candidate.PSObject.Properties.Name -contains "__path") { [string]$Candidate.__path } else { [string]$Candidate.candidate_id }
    foreach ($property in @("schema_version", "candidate_id", "dedupe_key", "language", "title", "normalized_title", "summary", "normalized_summary_hash", "keywords", "status", "occurrence_count", "first_seen_on", "last_seen_on", "reviewed_on", "superseded_by", "merged_from", "_local")) {
        Test-RequiredProperty -Object $Candidate -Name $property -Path $path
    }
    if ([int]$Candidate.schema_version -ne 1) {
        throw "Unsupported candidate schema_version in ${path}: $($Candidate.schema_version)"
    }
    if ($script:AllowedStatuses -notcontains [string]$Candidate.status) {
        throw "Unsupported candidate status in ${path}: $($Candidate.status)"
    }
    Assert-IsoDate -Value ([string]$Candidate.first_seen_on) -Field "first_seen_on"
    Assert-IsoDate -Value ([string]$Candidate.last_seen_on) -Field "last_seen_on"
    if (-not [string]::IsNullOrWhiteSpace([string]$Candidate.reviewed_on)) {
        Assert-IsoDate -Value ([string]$Candidate.reviewed_on) -Field "reviewed_on"
    }
    $normalizedTitle = Normalize-SingleLine -Text ([string]$Candidate.title) -Lowercase
    if ($normalizedTitle -cne [string]$Candidate.normalized_title) {
        throw "Conflicting normalized_title metadata: $path"
    }
    $summaryHash = Get-Sha256Text -Text (Normalize-MultilineText -Text ([string]$Candidate.summary))
    if ($summaryHash -cne [string]$Candidate.normalized_summary_hash) {
        throw "Conflicting normalized_summary_hash metadata: $path"
    }
    $dedupeKey = "{0}|{1}|{2}" -f ([string]$Candidate.language).ToLowerInvariant(), $normalizedTitle, $summaryHash
    if ($dedupeKey -cne [string]$Candidate.dedupe_key) {
        throw "Conflicting dedupe metadata: $path"
    }
    $candidateId = "candidate-$(Get-Sha256Text -Text $dedupeKey)"
    if ($candidateId -cne [string]$Candidate.candidate_id) {
        throw "Conflicting candidate_id metadata: $path"
    }
    foreach ($field in @("title", "summary")) {
        Assert-PublicSafeValue -Value ([string]$Candidate.$field) -Field $field
    }
    foreach ($keyword in @($Candidate.keywords)) {
        Assert-PublicSafeValue -Value ([string]$keyword) -Field "keywords"
    }
    if ($Candidate._local.PSObject.Properties.Name -notcontains "sources" -or $Candidate._local.PSObject.Properties.Name -notcontains "reviews") {
        throw "Candidate _local must contain sources and reviews: $path"
    }
    $sourceKeys = @($Candidate._local.sources | ForEach-Object { [string]$_.source_key })
    if (@($sourceKeys | Sort-Object -Unique).Count -ne $sourceKeys.Count) {
        throw "Candidate contains duplicate local source occurrence IDs: $path"
    }
    if ([int]$Candidate.occurrence_count -ne $sourceKeys.Count) {
        throw "Candidate occurrence_count does not match _local.sources: $path"
    }
    if ([string]$Candidate.status -eq "superseded" -and [string]::IsNullOrWhiteSpace([string]$Candidate.superseded_by)) {
        throw "Superseded candidate must name superseded_by: $path"
    }
    if ([string]$Candidate.status -ne "superseded" -and -not [string]::IsNullOrWhiteSpace([string]$Candidate.superseded_by)) {
        throw "Only superseded candidates may set superseded_by: $path"
    }
    if ($Candidate.PSObject.Properties.Name -contains "__body") {
        $bodyTitle = Get-ExperienceTitle -Text ([string]$Candidate.__body)
        $bodySummary = Normalize-MultilineText -Text (Get-MarkdownSection -Text ([string]$Candidate.__body) -Heading "Summary")
        if ($bodyTitle -cne [string]$Candidate.title -or $bodySummary -cne [string]$Candidate.summary) {
            throw "Candidate body conflicts with front matter: $path"
        }
    }
}

function Read-CandidateInbox {
    param([Parameter(Mandatory = $true)][string]$Path)
    $inbox = Get-FullPath -Path $Path
    if (-not (Test-Path -LiteralPath $inbox)) {
        return @()
    }
    if (-not (Test-Path -LiteralPath $inbox -PathType Container)) {
        throw "Inbox path is not a directory: $inbox"
    }
    Assert-NoReparsePoint -Path $inbox -Label "Candidate inbox"
    $items = @(Get-ChildItem -LiteralPath $inbox -Force | Sort-Object Name)
    foreach ($item in $items) {
        if ($item.PSIsContainer -or $item.Extension -cne ".md") {
            throw "Candidate inbox contains an unsupported entry: $($item.FullName)"
        }
        Assert-NoReparsePoint -Path $item.FullName -Label "Candidate entry"
    }
    $candidates = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in $items) {
        $candidate = ConvertFrom-CandidateMarkdown -Path $item.FullName -Text (Read-Utf8Text -Path $item.FullName)
        Assert-Candidate -Candidate $candidate
        $expectedName = Get-CandidateFilename -Candidate $candidate
        if ($item.Name -cne $expectedName) {
            throw "Candidate filename is not canonical. Expected '$expectedName', found '$($item.Name)'."
        }
        $candidates.Add($candidate)
    }
    Assert-InboxConsistency -Candidates @($candidates.ToArray())
    return @($candidates.ToArray() | Sort-Object candidate_id)
}

function Assert-InboxConsistency {
    param([Parameter(Mandatory = $true)][object[]]$Candidates)
    $ids = @{}
    $dedupe = @{}
    foreach ($candidate in $Candidates) {
        $id = [string]$candidate.candidate_id
        $key = [string]$candidate.dedupe_key
        if ($ids.ContainsKey($id)) {
            throw "Duplicate candidate_id detected: $id"
        }
        if ($dedupe.ContainsKey($key)) {
            throw "Duplicate dedupe_key detected in separate entries: $key"
        }
        $ids[$id] = $candidate
        $dedupe[$key] = $candidate
    }
    foreach ($candidate in $Candidates) {
        $id = [string]$candidate.candidate_id
        $target = [string]$candidate.superseded_by
        if (-not [string]::IsNullOrWhiteSpace($target) -and -not $ids.ContainsKey($target)) {
            throw "Candidate $id references missing superseded_by target: $target"
        }
        foreach ($mergedId in @($candidate.merged_from)) {
            $merged = [string]$mergedId
            if ($merged -eq $id -or -not $ids.ContainsKey($merged)) {
                throw "Candidate $id has invalid merged_from reference: $merged"
            }
        }
        $visited = @{}
        $current = $candidate
        while (-not [string]::IsNullOrWhiteSpace([string]$current.superseded_by)) {
            $currentId = [string]$current.candidate_id
            if ($visited.ContainsKey($currentId)) {
                throw "Candidate superseded_by cycle detected at: $currentId"
            }
            $visited[$currentId] = $true
            $current = $ids[[string]$current.superseded_by]
        }
    }
}

function Remove-InternalProperties {
    param([Parameter(Mandatory = $true)][object]$Candidate)
    foreach ($name in @("__path", "__body")) {
        if ($Candidate.PSObject.Properties.Name -contains $name) {
            $Candidate.PSObject.Properties.Remove($name)
        }
    }
    return $Candidate
}

function Copy-CandidateObject {
    param([Parameter(Mandatory = $true)][object]$Candidate)
    $copy = ($Candidate | ConvertTo-Json -Depth 12) | ConvertFrom-Json
    return (Remove-InternalProperties -Candidate $copy)
}

function Merge-SourceOccurrences {
    param(
        [Parameter(Mandatory = $true)][object]$Target,
        [Parameter(Mandatory = $true)][object[]]$Sources
    )
    $sourceMap = @{}
    foreach ($source in @($Target._local.sources) + @($Sources | ForEach-Object { $_._local.sources })) {
        $sourceMap[[string]$source.source_key] = $source
    }
    $Target._local.sources = @($sourceMap.Values | Sort-Object source_key)
    $Target.occurrence_count = @($Target._local.sources).Count
    $dates = @($Target._local.sources | ForEach-Object { [string]$_.observed_on } | Sort-Object)
    if ($dates.Count -gt 0) {
        $Target.first_seen_on = $dates[0]
        $Target.last_seen_on = $dates[$dates.Count - 1]
    }
}

function Merge-DiscoveredCandidates {
    param([Parameter(Mandatory = $true)][object[]]$Candidates)
    $map = @{}
    foreach ($candidate in $Candidates) {
        $key = [string]$candidate.dedupe_key
        if (-not $map.ContainsKey($key)) {
            $map[$key] = Copy-CandidateObject -Candidate $candidate
        }
        else {
            if ([string]$map[$key].candidate_id -cne [string]$candidate.candidate_id) {
                throw "Conflicting candidate ID for dedupe key: $key"
            }
            Merge-SourceOccurrences -Target $map[$key] -Sources @($candidate)
        }
    }
    return @($map.Values | Sort-Object dedupe_key)
}

function Write-InboxTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Candidates
    )
    $inbox = Get-FullPath -Path $Path
    $parent = [System.IO.Path]::GetDirectoryName($inbox)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "Inbox parent directory must already exist: $parent"
    }
    Assert-NoReparsePoint -Path $parent -Label "Inbox parent"
    Assert-InboxConsistency -Candidates $Candidates
    foreach ($candidate in $Candidates) {
        Assert-Candidate -Candidate $candidate
    }

    $leaf = [System.IO.Path]::GetFileName($inbox)
    $transactionId = [guid]::NewGuid().ToString("N")
    $stage = Join-Path $parent (".{0}.stage.{1}" -f $leaf, $transactionId)
    $backup = Join-Path $parent (".{0}.backup.{1}" -f $leaf, $transactionId)
    if (-not (Test-PathContainedBy -Path $stage -Root $parent) -or -not (Test-PathContainedBy -Path $backup -Root $parent)) {
        throw "Transaction paths escaped the inbox parent."
    }
    [System.IO.Directory]::CreateDirectory($stage) | Out-Null
    try {
        foreach ($candidate in @($Candidates | Sort-Object candidate_id)) {
            $clean = Remove-InternalProperties -Candidate $candidate
            $candidatePath = Join-Path $stage (Get-CandidateFilename -Candidate $clean)
            Write-Utf8Text -Path $candidatePath -Text (ConvertTo-CandidateMarkdown -Candidate $clean)
        }
        [void](Read-CandidateInbox -Path $stage)

        $hadInbox = Test-Path -LiteralPath $inbox
        if ($hadInbox) {
            Move-Item -LiteralPath $inbox -Destination $backup
        }
        try {
            Move-Item -LiteralPath $stage -Destination $inbox
        }
        catch {
            if ($hadInbox -and (Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $inbox)) {
                Move-Item -LiteralPath $backup -Destination $inbox
            }
            throw
        }
        if ($hadInbox -and (Test-Path -LiteralPath $backup)) {
            [System.IO.Directory]::Delete($backup, $true)
        }
    }
    finally {
        if (Test-Path -LiteralPath $stage) {
            [System.IO.Directory]::Delete($stage, $true)
        }
        if (Test-Path -LiteralPath $backup) {
            if (-not (Test-Path -LiteralPath $inbox)) {
                Move-Item -LiteralPath $backup -Destination $inbox
            }
            else {
                [System.IO.Directory]::Delete($backup, $true)
            }
        }
    }
}

function Add-ReviewRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Candidate,
        [Parameter(Mandatory = $true)][string]$Date,
        [Parameter(Mandatory = $true)][string]$Reviewer,
        [Parameter(Mandatory = $true)][string]$Action,
        [string]$Note = ""
    )
    $reviewKey = Get-Sha256Text -Text ("$Date|$Reviewer|$Action|$Note")
    $reviews = @($Candidate._local.reviews)
    if (@($reviews | Where-Object { [string]$_.review_key -eq $reviewKey }).Count -eq 0) {
        $reviews += [pscustomobject][ordered]@{
            review_key = $reviewKey
            reviewed_on = $Date
            reviewed_by = $Reviewer
            action = $Action
            note = $Note
        }
    }
    $Candidate._local.reviews = @($reviews | Sort-Object review_key)
    $Candidate.reviewed_on = $Date
}

function ConvertTo-PublicCandidate {
    param([Parameter(Mandatory = $true)][object]$Candidate)
    $public = [pscustomobject][ordered]@{
        schema_version = 1
        candidate_id = [string]$Candidate.candidate_id
        dedupe_key = [string]$Candidate.dedupe_key
        language = [string]$Candidate.language
        title = [string]$Candidate.title
        summary = [string]$Candidate.summary
        keywords = @(Sort-OrdinalStrings -Values @($Candidate.keywords))
        status = [string]$Candidate.status
        occurrence_count = [int]$Candidate.occurrence_count
        first_seen_on = [string]$Candidate.first_seen_on
        last_seen_on = [string]$Candidate.last_seen_on
        reviewed_on = [string]$Candidate.reviewed_on
        superseded_by = [string]$Candidate.superseded_by
        merged_from = @($Candidate.merged_from | ForEach-Object { [string]$_ } | Sort-Object)
    }
    $serialized = $public | ConvertTo-Json -Depth 8 -Compress
    Assert-PublicSafeValue -Value $serialized -Field "public export"
    if ($serialized -match '"_local"|project_root|source_file|source_hash|reviewed_by|raw[_ ]?log|transcript|private repository mapping') {
        throw "Public export contains local-only or raw evidence fields."
    }
    return $public
}

function Write-CandidateOutput {
    param(
        [Parameter(Mandatory = $true)][object[]]$Candidates,
        [switch]$AsJson,
        [switch]$Public
    )
    $items = if ($Public.IsPresent) {
        @($Candidates | Sort-Object candidate_id | ForEach-Object { ConvertTo-PublicCandidate -Candidate $_ })
    }
    else {
        @($Candidates | Sort-Object candidate_id)
    }
    if ($AsJson.IsPresent) {
        [pscustomobject][ordered]@{
            schema_version = 1
            count = $items.Count
            candidates = @($items)
        } | ConvertTo-Json -Depth 12
        return
    }
    foreach ($item in $items) {
        Write-Output ("{0} | {1} | {2} | {3} | occurrences={4} | {5}" -f [string]$item.candidate_id, [string]$item.status, [string]$item.language, [string]$item.title, [int]$item.occurrence_count, [string]$item.summary)
    }
}

Assert-IsoDate -Value $ObservedOn -Field "ObservedOn"

switch ($Mode) {
    "Discover" {
        if ($ProjectRoot.Count -eq 0) {
            if ([string]::IsNullOrWhiteSpace($InboxDir)) {
                throw "Discover defaults to the candidate inbox. Supply InboxDir, or explicitly supply ProjectRoot and Language for legacy/import scanning."
            }
            Write-CandidateOutput -Candidates @(Read-CandidateInbox -Path $InboxDir) -AsJson:$Json.IsPresent
        }
        else {
            $discovered = @(Find-ProjectCandidates -Roots $ProjectRoot -Languages $Language -Date $ObservedOn)
            Write-CandidateOutput -Candidates @(Merge-DiscoveredCandidates -Candidates $discovered) -AsJson:$Json.IsPresent
        }
    }
    "Intake" {
        if ([string]::IsNullOrWhiteSpace($InboxDir)) {
            throw "InboxDir is required for Intake. No runtime or home directory is auto-detected."
        }
        $existing = @(Read-CandidateInbox -Path $InboxDir)
        $discovered = @(Find-ProjectCandidates -Roots $ProjectRoot -Languages $Language -Date $ObservedOn -WritableInbox $InboxDir)
        $incoming = @(Merge-DiscoveredCandidates -Candidates $discovered)
        if ($incoming.Count -eq 0) {
            Write-Output "Candidate intake: discovered=0 changed=0"
            break
        }
        $map = @{}
        foreach ($candidate in $existing) {
            $map[[string]$candidate.dedupe_key] = Copy-CandidateObject -Candidate $candidate
        }
        $created = 0
        $merged = 0
        foreach ($candidate in $incoming) {
            $key = [string]$candidate.dedupe_key
            if ($map.ContainsKey($key)) {
                if ([string]$map[$key].candidate_id -cne [string]$candidate.candidate_id) {
                    throw "Existing candidate conflicts with incoming dedupe metadata: $key"
                }
                $before = [int]$map[$key].occurrence_count
                Merge-SourceOccurrences -Target $map[$key] -Sources @($candidate)
                if ([int]$map[$key].occurrence_count -gt $before) {
                    $merged++
                }
            }
            else {
                $map[$key] = Copy-CandidateObject -Candidate $candidate
                $created++
            }
        }
        $updated = @($map.Values | Sort-Object candidate_id)
        Write-InboxTransaction -Path $InboxDir -Candidates $updated
        Write-Output ("Candidate intake: discovered={0} created={1} merged={2} total={3}" -f $incoming.Count, $created, $merged, $updated.Count)
    }
    "List" {
        if ([string]::IsNullOrWhiteSpace($InboxDir)) {
            throw "InboxDir is required for List."
        }
        $items = @(Read-CandidateInbox -Path $InboxDir)
        if ($PSBoundParameters.ContainsKey("Status")) {
            $items = @($items | Where-Object { [string]$_.status -eq $Status })
        }
        Write-CandidateOutput -Candidates $items -AsJson:$Json.IsPresent
    }
    "Export" {
        if ([string]::IsNullOrWhiteSpace($InboxDir)) {
            throw "InboxDir is required for Export. Export writes only to stdout."
        }
        $items = @(Read-CandidateInbox -Path $InboxDir)
        if ($PSBoundParameters.ContainsKey("Status")) {
            $items = @($items | Where-Object { [string]$_.status -eq $Status })
        }
        Write-CandidateOutput -Candidates $items -AsJson:$Json.IsPresent -Public
    }
    "Triage" {
        if ([string]::IsNullOrWhiteSpace($InboxDir) -or [string]::IsNullOrWhiteSpace($CandidateId)) {
            throw "InboxDir and CandidateId are required for Triage."
        }
        if ([string]::IsNullOrWhiteSpace($ReviewedBy)) {
            throw "ReviewedBy is required for an explicit human triage decision."
        }
        $items = @(Read-CandidateInbox -Path $InboxDir | ForEach-Object { Copy-CandidateObject -Candidate $_ })
        $byId = @{}
        foreach ($item in $items) {
            $byId[[string]$item.candidate_id] = $item
        }
        if (-not $byId.ContainsKey($CandidateId)) {
            throw "CandidateId not found: $CandidateId"
        }
        $target = $byId[$CandidateId]
        if ($Status -eq "superseded") {
            if ([string]::IsNullOrWhiteSpace($SupersededBy) -or -not $byId.ContainsKey($SupersededBy) -or $SupersededBy -eq $CandidateId) {
                throw "A superseded triage decision requires an existing, different SupersededBy candidate ID."
            }
            $target.superseded_by = $SupersededBy
        }
        else {
            if (-not [string]::IsNullOrWhiteSpace($SupersededBy)) {
                throw "SupersededBy is valid only when Status is superseded."
            }
            $target.superseded_by = ""
        }
        $target.status = $Status
        Add-ReviewRecord -Candidate $target -Date $ObservedOn -Reviewer $ReviewedBy -Action ("status:$Status") -Note $ReviewNote

        foreach ($sourceId in @($MergeCandidateId | Sort-Object -Unique)) {
            if ([string]::IsNullOrWhiteSpace($sourceId)) {
                continue
            }
            if ($sourceId -eq $CandidateId -or -not $byId.ContainsKey($sourceId)) {
                throw "MergeCandidateId must reference an existing candidate other than the target: $sourceId"
            }
            $source = $byId[$sourceId]
            $source.status = "superseded"
            $source.superseded_by = $CandidateId
            Add-ReviewRecord -Candidate $source -Date $ObservedOn -Reviewer $ReviewedBy -Action ("merged-into:$CandidateId") -Note $ReviewNote
            $target.merged_from = @(@($target.merged_from) + $sourceId | Sort-Object -Unique)
        }
        Assert-InboxConsistency -Candidates $items
        Write-InboxTransaction -Path $InboxDir -Candidates $items
        Write-Output ("Candidate triage: candidate_id={0} status={1} merged={2}" -f $CandidateId, $Status, @($MergeCandidateId).Count)
    }
}
