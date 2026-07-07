param(
    [string]$HubDir = "$env:USERPROFILE\.agents\knowledge-hub"
)

$ErrorActionPreference = "Stop"

function Join-PathParts {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Children
    )

    $path = $Root
    foreach ($child in $Children) {
        if ([string]::IsNullOrWhiteSpace($child)) {
            continue
        }
        foreach ($segment in @($child -split '[\\/]+')) {
            if (-not [string]::IsNullOrWhiteSpace($segment)) {
                $path = Join-Path $path $segment
            }
        }
    }
    return $path
}

function Load-Registry {
    param([string]$RegistryPath)

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        return @{
            schema_version = 1
            updated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        }
    }

    $raw = Get-Content -LiteralPath $RegistryPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{
            schema_version = 1
            updated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        }
    }

    $parsed = $raw | ConvertFrom-Json
    if ($parsed.PSObject.Properties.Name -contains "entries") {
        return @{
            schema_version = if ($parsed.schema_version) { $parsed.schema_version } else { 1 }
            updated_at_utc = if ($parsed.updated_at_utc) { $parsed.updated_at_utc } else { (Get-Date).ToUniversalTime().ToString("o") }
            entries = @($parsed.entries)
        }
    }

    return @{
        schema_version = 1
        updated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        entries = @($parsed)
    }
}

function Save-Registry {
    param(
        [string]$RegistryPath,
        [int]$SchemaVersion,
        [array]$Entries
    )

    if (Test-Path -LiteralPath $RegistryPath) {
        $raw = Get-Content -LiteralPath $RegistryPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.PSObject.Properties.Name -contains "entries") {
                $existingSchemaVersion = if ($parsed.schema_version) { [int]$parsed.schema_version } else { 1 }
                $existingEntriesJson = ConvertTo-Json -InputObject @($parsed.entries) -Depth 8 -Compress
                $newEntriesJson = ConvertTo-Json -InputObject @($Entries) -Depth 8 -Compress
                if ($existingSchemaVersion -eq $SchemaVersion -and $existingEntriesJson -eq $newEntriesJson) {
                    return
                }
            }
        }
    }

    $payload = [ordered]@{
        schema_version = $SchemaVersion
        updated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        entries = @($Entries)
    }
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RegistryPath -Encoding UTF8
}

function Normalize-Slug {
    param([string]$Text)

    $slug = $Text.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "experience"
    }
    return $slug
}

function Get-ExperienceTitle {
    param([string]$Path)

    $previewLines = Get-Content -LiteralPath $Path -TotalCount 30
    foreach ($line in $previewLines) {
        $match = [regex]::Match($line, '^\s*#\s+(.+)$')
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($Path)
}

function Get-ExperienceKeywords {
    param([string]$Path)

    $lines = Get-Content -LiteralPath $Path -TotalCount 50
    $inKeywords = $false
    $keywordsText = ""

    foreach ($line in $lines) {
        if ($line -match '^\s*##\s+Keywords\s*$') {
            $inKeywords = $true
            continue
        }
        if ($inKeywords) {
            if ($line -match '^\s*##\s+') {
                break
            }
            $trimmed = $line.Trim()
            if ($trimmed.Length -gt 0) {
                $keywordsText = $trimmed
                break
            }
        }
    }

    if ($keywordsText.Length -gt 0) {
        return @($keywordsText -split '\s*,\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    }

    # Fallback: extract words from title
    $title = Get-ExperienceTitle -Path $Path
    $words = @($title -split '[\s\-_]+' | Where-Object { $_.Length -gt 2 })
    return $words
}

function Get-ExperienceMetadataField {
    param(
        [string]$Path,
        [string]$Field
    )

    $lines = Get-Content -LiteralPath $Path -TotalCount 40
    $pattern = '^\s*{0}\s*:\s*(.+?)\s*$' -f [regex]::Escape($Field)
    foreach ($line in $lines) {
        $match = [regex]::Match($line, $pattern)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }

    return ""
}

function Get-ExperienceLifecycleMetadata {
    param([string]$Path)

    $maturity = (Get-ExperienceMetadataField -Path $Path -Field "Maturity").ToLowerInvariant()
    $lastReviewed = Get-ExperienceMetadataField -Path $Path -Field "Last reviewed"

    return [ordered]@{
        maturity = $maturity
        scope = Get-ExperienceMetadataField -Path $Path -Field "Scope"
        source = Get-ExperienceMetadataField -Path $Path -Field "Source"
        reviewed_at = $lastReviewed
        decay_policy = Get-ExperienceMetadataField -Path $Path -Field "Decay policy"
    }
}

$registrySchemaVersion = 2
$hubExperienceDir = Join-PathParts $HubDir "knowledge" "experience"
if (-not (Test-Path -LiteralPath $hubExperienceDir)) {
    throw "Hub experience directory not found: $hubExperienceDir"
}

$registryPath = Join-PathParts $hubExperienceDir "index.json"
$existingRegistry = Load-Registry -RegistryPath $registryPath
$existingEntries = @($existingRegistry.entries)

$existingByHash = @{}
$existingByFile = @{}
foreach ($entry in $existingEntries) {
    if ($entry.hash_sha256) {
        $existingByHash[$entry.hash_sha256.ToLowerInvariant()] = $entry
    }
    if ($entry.hub_file) {
        $existingByFile[$entry.hub_file] = $entry
    }
}

$entries = @()
$experienceFiles = @(
    Get-ChildItem -LiteralPath $hubExperienceDir -File -Filter "*.md" |
        Where-Object { $_.Name -ne "README.md" } |
        Sort-Object Name
)

foreach ($fileItem in $experienceFiles) {
    $hash = (Get-FileHash -LiteralPath $fileItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $lifecycleMetadata = Get-ExperienceLifecycleMetadata -Path $fileItem.FullName
    $existing = $null
    if ($existingByHash.ContainsKey($hash)) {
        $existing = $existingByHash[$hash]
    } elseif ($existingByFile.ContainsKey($fileItem.Name)) {
        $existing = $existingByFile[$fileItem.Name]
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileItem.Name)
    $entryId = if ($existing -and $existing.id) {
        $existing.id
    } else {
        "reindexed-{0}-{1}" -f (Normalize-Slug -Text $baseName), $hash.Substring(0, 8)
    }

    $promotedAt = if ($existing -and $existing.promoted_at_utc) {
        $existing.promoted_at_utc
    } else {
        $fileItem.LastWriteTimeUtc.ToString("o")
    }

    $entries += [ordered]@{
        id = $entryId
        promoted_at_utc = $promotedAt
        source_project = if ($existing -and $existing.source_project) { $existing.source_project } else { "" }
        source_project_tag = if ($existing -and $existing.source_project_tag) { $existing.source_project_tag } else { "" }
        source_relative_path = if ($existing -and $existing.source_relative_path) { $existing.source_relative_path } else { "" }
        source_file = if ($existing -and $existing.source_file) { $existing.source_file } else { "" }
        hash_sha256 = $hash
        title = Get-ExperienceTitle -Path $fileItem.FullName
        keywords = @(Get-ExperienceKeywords -Path $fileItem.FullName)
        maturity = $lifecycleMetadata.maturity
        scope = $lifecycleMetadata.scope
        source = $lifecycleMetadata.source
        reviewed_at = $lifecycleMetadata.reviewed_at
        decay_policy = $lifecycleMetadata.decay_policy
        hub_file = $fileItem.Name
    }
}

Save-Registry -RegistryPath $registryPath -SchemaVersion $registrySchemaVersion -Entries $entries

Write-Output ("Rebuilt experience index: entries={0}" -f $entries.Count)
Write-Output "Hub experience dir: $hubExperienceDir"
Write-Output "Registry: $registryPath"
