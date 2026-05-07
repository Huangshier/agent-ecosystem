param(
    [Parameter(Mandatory = $true)]
    [string]$Query,
    [string]$HubDir = "$env:USERPROFILE\.agents\knowledge-hub",
    [int]$MaxResults = 5,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-PreventionRule {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    $lines = @(Get-Content -LiteralPath $Path)
    $capture = $false
    $result = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in $lines) {
        if ($line -match '^\s*##\s+Prevention Rule\s*$') {
            $capture = $true
            continue
        }
        if ($capture -and $line -match '^\s*##\s+') {
            break
        }
        if ($capture) {
            $trimmed = $line.Trim()
            if ($trimmed.Length -gt 0) {
                $result.Add($trimmed)
            }
        }
    }
    return (($result | Select-Object -First 6) -join " ")
}

$experienceDir = Join-Path $HubDir "knowledge\experience"
$indexPath = Join-Path $experienceDir "index.json"
if (-not (Test-Path -LiteralPath $indexPath)) {
    throw "Experience index not found: $indexPath"
}

$index = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
$entries = @($index.entries)
$queryLower = $Query.ToLowerInvariant()
$queryWords = @($queryLower -split '[^a-z0-9_+\.-]+' | Where-Object { $_.Length -gt 0 })

$results = foreach ($entry in $entries) {
    $keywords = @($entry.keywords | ForEach-Object { [string]$_ })
    $hayKeywords = ($keywords -join " ").ToLowerInvariant()
    $hayTitle = ([string]$entry.title).ToLowerInvariant()
    $score = 0

    foreach ($word in $queryWords) {
        if ($hayKeywords.Contains($word)) { $score += 3 }
        if ($hayTitle.Contains($word)) { $score += 2 }
    }
    if ($Query -and $hayKeywords.Contains($queryLower)) { $score += 5 }
    if ($Query -and $hayTitle.Contains($queryLower)) { $score += 4 }

    if ($score -gt 0) {
        $filePath = Join-Path $experienceDir $entry.hub_file
        [ordered]@{
            score = $score
            title = $entry.title
            keywords = @($keywords)
            hub_file = $entry.hub_file
            path = $filePath
            prevention_rule = Get-PreventionRule -Path $filePath
        }
    }
}

$ranked = @($results | Sort-Object score -Descending | Select-Object -First $MaxResults)

if ($Json.IsPresent) {
    [ordered]@{
        query = $Query
        index = $indexPath
        results = $ranked
    } | ConvertTo-Json -Depth 8
    return
}

Write-Output ("Experience search: {0}" -f $Query)
Write-Output ("Index: {0}" -f $indexPath)
if ($ranked.Count -eq 0) {
    Write-Output "No matching experience entries."
    return
}

foreach ($result in $ranked) {
    Write-Output ("[{0}] {1}" -f $result.score, $result.title)
    Write-Output ("  File: {0}" -f $result.path)
    if ($result.prevention_rule) {
        Write-Output ("  Prevention: {0}" -f $result.prevention_rule)
    }
}
