function Join-ProjectLanguageCodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Resolve-ProjectLanguageCode {
    param(
        [AllowEmptyString()][string]$Language,
        [switch]$AllowAliases
    )

    if ([string]::IsNullOrWhiteSpace($Language)) { return "" }
    $normalized = $Language.Trim().ToLowerInvariant()
    if ($normalized -eq "en") { return "en" }
    if ($normalized -eq "zh-cn") { return "zh-CN" }
    if ($AllowAliases.IsPresent) {
        if ($normalized -in @("en-us", "english")) { return "en" }
        $zhAliases = @(
            "zh", "zh-hans", "chinese", "simplified-chinese", "simplified chinese",
            (Join-ProjectLanguageCodePoints @(0x4E2D, 0x6587)),
            (Join-ProjectLanguageCodePoints @(0x7B80, 0x4F53, 0x4E2D, 0x6587))
        )
        if ($normalized -in $zhAliases) { return "zh-CN" }
    }
    throw "Unsupported project language."
}

function Read-ProjectGuideLanguageCode {
    param([string]$ProjectPath)
    $guidePath = Join-Path (Join-Path $ProjectPath ".agents") "AGENTS.md"
    if (-not (Test-Path -LiteralPath $guidePath -PathType Leaf)) { return "" }
    $guideText = [System.IO.File]::ReadAllText($guidePath)
    $hasEnglishMarker = $guideText -match '(?im)^\s*Project memory language:\s*English\.\s*$'
    $languageLabel = Join-ProjectLanguageCodePoints @(0x9879, 0x76EE, 0x8BB0, 0x5FC6, 0x8BED, 0x8A00, 0xFF1A)
    $simplifiedChinese = Join-ProjectLanguageCodePoints @(0x7B80, 0x4F53, 0x4E2D, 0x6587, 0x3002)
    $hasChineseMarker = $guideText -match ("(?im)^\s*{0}\s*{1}\s*$" -f [regex]::Escape($languageLabel), [regex]::Escape($simplifiedChinese))
    if ($hasEnglishMarker -and $hasChineseMarker) { throw "Conflicting project memory language declarations." }
    if ($hasChineseMarker) { return "zh-CN" }
    if ($hasEnglishMarker) { return "en" }
    return ""
}
