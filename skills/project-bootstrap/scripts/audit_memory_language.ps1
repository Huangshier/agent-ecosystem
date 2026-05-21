[CmdletBinding()]
param(
    [string]$ProjectDir = (Get-Location).Path,
    [ValidateSet("en", "zh-CN")]
    [string]$ExpectedLanguage = "en",
    [switch]$IncludeSpecs,
    [switch]$IncludeCommands,
    [switch]$Json
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

function Resolve-ProjectRoot {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Project directory does not exist: $Path"
    }

    return ([System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)).TrimEnd([char[]]"\/")
}

function Normalize-RelativePath {
    param([string]$Path)
    return (($Path -replace "\\", "/").TrimStart("/"))
}

function ConvertTo-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $fullRoot = ([System.IO.Path]::GetFullPath($Root)).TrimEnd([char[]]"\/")
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return Normalize-RelativePath -Path $fullPath.Substring($fullRoot.Length).TrimStart([char[]]"\/")
    }
    return Normalize-RelativePath -Path $fullPath
}

function Read-Utf8Text {
    param([string]$Path)
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    return [System.IO.File]::ReadAllText($Path, $encoding)
}

function Add-AuditPath {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Set,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $normalized = Normalize-RelativePath -Path $RelativePath
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return
    }

    $fullPath = Join-PathParts $Root $normalized
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        $Set[$normalized] = $true
    }
}

function Add-AuditTree {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Set,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativeRoot,
        [string[]]$Extensions = @(".md", ".txt")
    )

    $scanRoot = Join-PathParts $Root $RelativeRoot
    if (-not (Test-Path -LiteralPath $scanRoot -PathType Container)) {
        return
    }

    foreach ($item in @(Get-ChildItem -LiteralPath $scanRoot -Recurse -File)) {
        $relative = ConvertTo-RelativePath -Root $Root -Path $item.FullName
        if ($relative -like ".agents/_backup/*" -or $relative -like ".agents/upgrade/*" -or $relative -like ".agents/language-migration/*") {
            continue
        }
        if ($item.Extension.ToLowerInvariant() -in $Extensions) {
            $Set[$relative] = $true
        }
    }
}

function Get-AuditRelativePaths {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$WithSpecs,
        [switch]$WithCommands
    )

    $set = @{}

    foreach ($relative in @(
        "AGENTS.md",
        ".agents/AGENTS.md",
        ".agents/process.txt",
        ".agents/plan.md",
        ".agents/notes.md"
    )) {
        Add-AuditPath -Set $set -Root $Root -RelativePath $relative
    }

    Add-AuditTree -Set $set -Root $Root -RelativeRoot ".agents/context"

    if ($WithCommands.IsPresent) {
        Add-AuditTree -Set $set -Root $Root -RelativeRoot ".agents/commands"
    }

    if ($WithSpecs.IsPresent) {
        $specRoot = Join-PathParts $Root "docs" "specs"
        if (Test-Path -LiteralPath $specRoot -PathType Container) {
            foreach ($item in @(Get-ChildItem -LiteralPath $specRoot -Recurse -File -Include "spec.md", "tasks.md")) {
                $relative = ConvertTo-RelativePath -Root $Root -Path $item.FullName
                if ($relative -notlike "docs/specs/_templates/*") {
                    $set[$relative] = $true
                }
            }
        }
    }

    return @($set.Keys | Sort-Object)
}

function Test-DiscoveryHeading {
    param([string]$Line)

    return [regex]::IsMatch(
        $Line,
        '^\s{0,3}#{1,6}\s*(?:[0-9]+[\.)]\s*)?(?:Summary|Keywords|\u6458\u8981|\u5173\u952e\u8bcd)(?:\s*[\(\uff08].*[\)\uff09])?\s*$',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
}

function Test-MarkdownHeading {
    param([string]$Line)
    return [regex]::IsMatch($Line, '^\s{0,3}#{1,6}\s+\S+')
}

function Split-MemoryText {
    param([string]$Text)

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = @($normalized -split "`n")
    $bodyLines = New-Object 'System.Collections.Generic.List[string]'
    $metadataLines = New-Object 'System.Collections.Generic.List[string]'
    $inFence = $false
    $inDiscoveryMetadata = $false

    foreach ($line in $lines) {
        if ($line -match '^\s{0,3}(```|~~~)') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) {
            continue
        }

        if (Test-DiscoveryHeading -Line $line) {
            $inDiscoveryMetadata = $true
            $metadataLines.Add($line) | Out-Null
            continue
        }

        if ($inDiscoveryMetadata -and [string]::IsNullOrWhiteSpace($line)) {
            $metadataLines.Add($line) | Out-Null
            $inDiscoveryMetadata = $false
            continue
        }

        if ($inDiscoveryMetadata -and (Test-MarkdownHeading -Line $line)) {
            $inDiscoveryMetadata = $false
        }

        if ($inDiscoveryMetadata) {
            $metadataLines.Add($line) | Out-Null
            continue
        }

        $bodyLines.Add($line) | Out-Null
    }

    return [ordered]@{
        body = ($bodyLines.ToArray() -join "`n")
        metadata = ($metadataLines.ToArray() -join "`n")
    }
}

function Remove-ProtectedLiterals {
    param([string]$Text)

    $result = $Text
    $result = [regex]::Replace($result, '<!--.*?-->', ' ', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $result = [regex]::Replace($result, '`[^`]*`', ' ')
    $result = [regex]::Replace($result, 'https?://\S+', ' ', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $result = [regex]::Replace($result, '(?m)^\s*(?:PS\s+)?(?:powershell|pwsh|git|gh|npm|pnpm|yarn|python|node|dotnet|uv|idf\.py|esptool\.py)\b.*$', ' ', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $result = [regex]::Replace($result, '(?m)^\s*(?:[A-Za-z]:)?[\\/][^\s,;:\)\]]+', ' ')
    $result = [regex]::Replace($result, '(?m)(?:^|\s)(?:\.{1,2}[\\/]|[A-Za-z0-9_.-]+[\\/])[A-Za-z0-9_.\\/:-]+', ' ')
    $result = [regex]::Replace($result, '\b[A-Za-z0-9_.-]+\.(?:md|txt|ps1|py|js|ts|json|ya?ml|lock|exe|dll|c|h|cpp|hpp|cs|java|go|rs|html|css)\b', ' ', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $result = [regex]::Replace($result, '\B-[A-Za-z][A-Za-z0-9_-]*\b', ' ')
    $result = [regex]::Replace($result, '\b[A-Z][A-Z0-9_]{2,}\b', ' ')
    $result = [regex]::Replace($result, '\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\b', ' ')
    $result = [regex]::Replace($result, '\b[A-Za-z_][A-Za-z0-9_]*\([^)]*\)', ' ')
    $result = [regex]::Replace($result, '\b[A-Za-z]+-[A-Za-z0-9-]+\b', ' ')
    $result = [regex]::Replace($result, '\b[A-Za-z]*[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*\b', ' ')
    return $result
}

function Get-LanguageSignal {
    param([string]$Text)

    $clean = Remove-ProtectedLiterals -Text $Text
    $cjk = [regex]::Matches($clean, '[\u4e00-\u9fff]').Count
    $latinWords = [regex]::Matches($clean, '(?i)\b[a-z]{3,}\b').Count
    $nonWhitespace = [regex]::Matches($clean, '\S').Count

    return [ordered]@{
        cjk_chars = [int]$cjk
        latin_words = [int]$latinWords
        non_whitespace = [int]$nonWhitespace
    }
}

function New-LanguageFinding {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$ExpectedLanguage,
        [Parameter(Mandatory = $true)][object]$BodySignal,
        [Parameter(Mandatory = $true)][object]$MetadataSignal
    )

    $cjk = [int]$BodySignal.cjk_chars
    $latin = [int]$BodySignal.latin_words
    $metadataCjk = [int]$MetadataSignal.cjk_chars
    $metadataLatin = [int]$MetadataSignal.latin_words

    if ($ExpectedLanguage -eq "zh-CN") {
        if ($latin -ge 8 -and $cjk -lt 8) {
            $reason = "narrative body appears English for zh-CN memory"
            $code = "body_likely_english"
            $confidence = "medium"
            if ($metadataCjk -ge 2) {
                $reason = "metadata appears localized but narrative body appears English"
                $code = "metadata_only_localization"
                $confidence = "high"
            }
            return [ordered]@{
                path = $RelativePath
                expected_language = $ExpectedLanguage
                reason = $reason
                severity = "warning"
                confidence = $confidence
                code = $code
                body_signal = $BodySignal
                metadata_signal = $MetadataSignal
            }
        }
        if ($latin -ge 8 -and $cjk -ge 8) {
            return [ordered]@{
                path = $RelativePath
                expected_language = $ExpectedLanguage
                reason = "narrative body appears mixed while expected zh-CN memory"
                severity = "warning"
                confidence = "medium"
                code = "mixed_language_body"
                body_signal = $BodySignal
                metadata_signal = $MetadataSignal
            }
        }
    }
    else {
        if ($cjk -ge 12 -and $latin -lt 5) {
            $reason = "narrative body appears Simplified Chinese for English memory"
            $code = "body_likely_zh_cn"
            $confidence = "medium"
            if ($metadataLatin -ge 2) {
                $reason = "metadata appears English but narrative body appears Simplified Chinese"
                $code = "metadata_only_localization"
                $confidence = "high"
            }
            return [ordered]@{
                path = $RelativePath
                expected_language = $ExpectedLanguage
                reason = $reason
                severity = "warning"
                confidence = $confidence
                code = $code
                body_signal = $BodySignal
                metadata_signal = $MetadataSignal
            }
        }
        if ($cjk -ge 12 -and $latin -ge 5) {
            return [ordered]@{
                path = $RelativePath
                expected_language = $ExpectedLanguage
                reason = "narrative body appears mixed while expected English memory"
                severity = "warning"
                confidence = "medium"
                code = "mixed_language_body"
                body_signal = $BodySignal
                metadata_signal = $MetadataSignal
            }
        }
    }

    return $null
}

$projectRoot = Resolve-ProjectRoot -Path $ProjectDir
$relativePaths = @(Get-AuditRelativePaths -Root $projectRoot -WithSpecs:$IncludeSpecs.IsPresent -WithCommands:$IncludeCommands.IsPresent)
$findings = New-Object 'System.Collections.Generic.List[object]'
$files = New-Object 'System.Collections.Generic.List[object]'

foreach ($relativePath in $relativePaths) {
    $path = Join-PathParts $projectRoot $relativePath
    $text = Read-Utf8Text -Path $path
    $parts = Split-MemoryText -Text $text
    $bodySignal = Get-LanguageSignal -Text ([string]$parts.body)
    $metadataSignal = Get-LanguageSignal -Text ([string]$parts.metadata)
    $finding = New-LanguageFinding -RelativePath $relativePath -ExpectedLanguage $ExpectedLanguage -BodySignal $bodySignal -MetadataSignal $metadataSignal

    $files.Add([ordered]@{
        path = $relativePath
        body_signal = $bodySignal
        metadata_signal = $metadataSignal
        finding = ($null -ne $finding)
    }) | Out-Null

    if ($null -ne $finding) {
        $findings.Add($finding) | Out-Null
    }
}

$result = [ordered]@{
    schema_version = 1
    project_dir = $projectRoot
    expected_language = $ExpectedLanguage
    include_specs = [bool]$IncludeSpecs.IsPresent
    include_commands = [bool]$IncludeCommands.IsPresent
    scanned_files = $relativePaths.Count
    findings = @($findings.ToArray())
    files = @($files.ToArray())
    summary = [ordered]@{
        finding_count = $findings.Count
        warning_count = @($findings | Where-Object { [string]$_.severity -eq "warning" }).Count
    }
}

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 8
}
else {
    if ($findings.Count -eq 0) {
        Write-Output ("PASS: no likely body-level language findings across {0} file(s)." -f $relativePaths.Count)
    }
    else {
        foreach ($finding in @($findings.ToArray())) {
            Write-Output ("WARN {0}: {1}" -f $finding.path, $finding.reason)
        }
        Write-Output ("Summary: {0} warning(s) across {1} scanned file(s)." -f $findings.Count, $relativePaths.Count)
    }
}
