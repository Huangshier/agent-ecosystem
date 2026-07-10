param(
    [string]$ProjectDir = (Get-Location).Path,
    [string]$HubDir = "$env:USERPROFILE\.agents\knowledge-hub",
    [string]$ProjectTag = "",
    [string]$File = "",
    [switch]$IncludeAll,
    [switch]$Commit
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

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
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

    # Backward compatibility: plain array format.
    return @{
        schema_version = 1
        updated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        entries = @($parsed)
    }
}

function Save-Registry {
    param(
        [string]$RegistryPath,
        [array]$Entries
    )

    if (Test-Path -LiteralPath $RegistryPath) {
        $raw = Get-Content -LiteralPath $RegistryPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.PSObject.Properties.Name -contains "entries") {
                $existingEntriesJson = ConvertTo-Json -InputObject @($parsed.entries) -Depth 8 -Compress
                $newEntriesJson = ConvertTo-Json -InputObject @($Entries) -Depth 8 -Compress
                if ($existingEntriesJson -eq $newEntriesJson) {
                    return
                }
            }
        }
    }

    $payload = [ordered]@{
        schema_version = 1
        updated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        entries = @($Entries)
    }
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RegistryPath -Encoding UTF8
}

function Resolve-SourceFile {
    param(
        [string]$ProjectRoot,
        [string]$ExperienceRoot,
        [string]$UserInput
    )
    if ([System.IO.Path]::IsPathRooted($UserInput)) {
        return $UserInput
    }

    $candidate1 = Join-Path $ExperienceRoot $UserInput
    if (Test-Path -LiteralPath $candidate1) {
        return $candidate1
    }

    $candidate2 = Join-Path $ProjectRoot $UserInput
    return $candidate2
}

function Test-GlobalCandidate {
    param([string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $candidatePatterns = @(
        '(?im)^\s*[-*]?\s*\*{0,2}Global\s+(hub\s+)?candidate\*{0,2}\s*:\s*(Yes|True)\b',
        '(?im)^\s*[-*]?\s*\*{0,2}Scope\*{0,2}\s*:\s*Cross-project reusable\b'
    )

    foreach ($pattern in $candidatePatterns) {
        if ($raw -match $pattern) {
            return $true
        }
    }

    return $false
}

function Test-RegistryConsistency {
    param(
        [string]$ExperienceDir,
        [array]$Entries
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $Entries) {
        $hubFile = [string]$entry.hub_file
        if ([string]::IsNullOrWhiteSpace($hubFile)) {
            $errors.Add(("entry {0} is missing hub_file" -f $entry.id))
            continue
        }

        $entryPath = Join-Path $ExperienceDir $hubFile
        if (-not (Test-Path -LiteralPath $entryPath)) {
            $errors.Add(("entry {0} points to missing file: {1}" -f $entry.id, $hubFile))
            continue
        }

        $expectedHash = [string]$entry.hash_sha256
        if (-not [string]::IsNullOrWhiteSpace($expectedHash)) {
            $actualHash = (Get-FileHash -LiteralPath $entryPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
                $errors.Add(("entry {0} hash mismatch for {1}: index={2} actual={3}" -f $entry.id, $hubFile, $expectedHash, $actualHash))
            }
        }
    }

    return @($errors.ToArray())
}

$projectFull = (Resolve-Path -LiteralPath $ProjectDir).Path
$sourceExperienceDir = Join-PathParts $projectFull ".agents" "context" "experience"
if (-not (Test-Path -LiteralPath $sourceExperienceDir)) {
    throw "Project experience directory not found: $sourceExperienceDir"
}

$hubExperienceDir = Join-PathParts $HubDir "knowledge" "experience"
Ensure-Dir -Path $hubExperienceDir
$registryPath = Join-PathParts $hubExperienceDir "index.json"
$registry = Load-Registry -RegistryPath $registryPath
$entries = @($registry.entries)

$existingHashes = @{}
$entries | ForEach-Object {
    if ($_.hash_sha256) {
        $existingHashes[$_.hash_sha256] = $true
    }
}

$sourceFiles = @()
if (-not [string]::IsNullOrWhiteSpace($File)) {
    $resolvedFile = Resolve-SourceFile -ProjectRoot $projectFull -ExperienceRoot $sourceExperienceDir -UserInput $File
    if (-not (Test-Path -LiteralPath $resolvedFile)) {
        throw "Specified file not found: $resolvedFile"
    }
    if ([System.IO.Path]::GetExtension($resolvedFile) -ne ".md") {
        throw "Only .md files can be promoted. Got: $resolvedFile"
    }
    $sourceFiles = @(Get-Item -LiteralPath $resolvedFile)
} else {
    $sourceFiles = @(Get-ChildItem -LiteralPath $sourceExperienceDir -File -Filter "*.md" | Where-Object { $_.Name -ne "README.md" })
}

if ($sourceFiles.Count -eq 0) {
    Write-Output "No promotable experience files found."
    return
}

$projectKey = if ([string]::IsNullOrWhiteSpace($ProjectTag)) { Split-Path -Leaf $projectFull } else { $ProjectTag }
$projectSlug = Normalize-Slug -Text $projectKey
$sourceProjectTag = if ([string]::IsNullOrWhiteSpace($ProjectTag)) { "" } else { $ProjectTag }

$promoted = 0
$skippedDuplicate = 0
$skippedReadme = 0
$skippedNotCandidate = 0

foreach ($fileItem in $sourceFiles) {
    if ($fileItem.Name -eq "README.md") {
        $skippedReadme++
        continue
    }
    if (-not $IncludeAll.IsPresent -and -not (Test-GlobalCandidate -Path $fileItem.FullName)) {
        $skippedNotCandidate++
        continue
    }

    $hash = (Get-FileHash -LiteralPath $fileItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($existingHashes.ContainsKey($hash)) {
        $skippedDuplicate++
        continue
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileItem.Name)
    $fileSlug = Normalize-Slug -Text $baseName
    $targetBase = Normalize-Slug -Text ("{0}-{1}" -f $projectSlug, $fileSlug)
    $targetName = "{0}.md" -f $targetBase
    $targetPath = Join-Path $hubExperienceDir $targetName

    if (Test-Path -LiteralPath $targetPath) {
        $targetName = "{0}-{1}.md" -f $targetBase, $hash.Substring(0, 8)
        $targetPath = Join-Path $hubExperienceDir $targetName
    }

    Copy-Item -LiteralPath $fileItem.FullName -Destination $targetPath -Force

    $title = ""
    $previewLines = Get-Content -LiteralPath $fileItem.FullName -TotalCount 30
    foreach ($line in $previewLines) {
        $match = [regex]::Match($line, '^\s*#\s+(.+)$')
        if ($match.Success) {
            $title = $match.Groups[1].Value.Trim()
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = $baseName
    }

    # Extract keywords from ## Keywords section, fallback to title words
    $keywords = @()
    $inKw = $false
    $kwLines = @()
    foreach ($kl in $previewLines) {
        if ($kl -match '^\s*##\s+Keywords\s*$') { $inKw = $true; continue }
        if ($inKw) {
            if ($kl -match '^\s*##\s+') { break }
            $kt = $kl.Trim()
            if ($kt.Length -gt 0) {
                $kwLines += $kt
            }
        }
    }
    $kwText = ($kwLines -join ' ')
    if ($kwText.Length -gt 0) {
        $keywords = @($kwText -split '\s*,\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    }
    if ($keywords.Count -eq 0) {
        $keywords = @($title -split '[\s\-_]+' | Where-Object { $_.Length -gt 2 })
    }

    $entries += [ordered]@{
        id = "{0}-{1}" -f (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"), $hash.Substring(0, 8)
        promoted_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        source_kind = "project-local"
        source_project_tag = $sourceProjectTag
        source_ref = ""
        hash_sha256 = $hash
        title = $title
        keywords = @($keywords)
        hub_file = $targetName
    }

    $existingHashes[$hash] = $true
    $promoted++
}

if ($promoted -gt 0) {
    Save-Registry -RegistryPath $registryPath -Entries $entries
    $registryErrors = Test-RegistryConsistency -ExperienceDir $hubExperienceDir -Entries $entries
    if ($registryErrors.Count -gt 0) {
        $registryErrors | ForEach-Object { Write-Warning $_ }
        throw ("Experience registry consistency check failed: {0} issue(s)" -f $registryErrors.Count)
    }
}

if ($Commit.IsPresent) {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (($null -ne $git) -and (Test-Path -LiteralPath (Join-Path $HubDir ".git"))) {
        git -C $HubDir add knowledge/experience | Out-Null
        try {
            $dirty = git -C $HubDir status --porcelain
            if ($dirty) {
                git -C $HubDir commit -m ("Promote experience from {0}" -f $projectKey) | Out-Null
            }
        } catch {
            Write-Warning "Hub commit failed. Commit manually if needed."
        }
    } else {
        Write-Warning "Git repository not detected for hub. Skipped commit."
    }
}

Write-Output ("Promotion summary: promoted={0}, skipped_duplicate={1}, skipped_readme={2}, skipped_not_candidate={3}" -f $promoted, $skippedDuplicate, $skippedReadme, $skippedNotCandidate)
Write-Output "Hub experience dir: $hubExperienceDir"
Write-Output "Registry: $registryPath"
