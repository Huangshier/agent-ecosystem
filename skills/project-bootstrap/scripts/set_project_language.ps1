[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ProjectDir = (Get-Location).Path,
    [Parameter(Mandatory = $true)][string]$ProjectLanguage,
    [string]$TemplateRoot = "",
    [switch]$OverwriteScaffold,
    [switch]$SkipOverwriteBackup
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

function Normalize-RelativePath {
    param([string]$Path)
    return (($Path -replace "\\", "/").TrimStart("/"))
}

function Read-Utf8Text {
    param([string]$Path)
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    return [System.IO.File]::ReadAllText($Path, $encoding)
}

function Write-Utf8TextWithBom {
    param(
        [string]$Path,
        [string]$Content
    )
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Join-CodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$script:languageBackupDir = ""
$script:languageBackupStamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$script:languageBackupCount = 0
$script:languageBackupRecords = New-Object 'System.Collections.Generic.List[object]'

function Get-LanguageBackupDir {
    $agentDir = Join-Path $ProjectDir ".agents"
    Ensure-Dir -Path $agentDir
    if ([string]::IsNullOrWhiteSpace($script:languageBackupDir)) {
        $script:languageBackupDir = Join-Path $agentDir ("_backup\language-{0}" -f $script:languageBackupStamp)
        Ensure-Dir -Path $script:languageBackupDir
    }
    return $script:languageBackupDir
}

function Backup-LanguageScaffoldFile {
    param(
        [string]$Path,
        [string]$RelativePath
    )

    $backupDir = Get-LanguageBackupDir
    $backupPath = Join-PathParts $backupDir $RelativePath
    Ensure-Dir -Path (Split-Path -Parent $backupPath)
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    $script:languageBackupCount++
    $script:languageBackupRecords.Add([ordered]@{
        relative_path = $RelativePath
        backup_path = $backupPath
    }) | Out-Null
}

function Resolve-ProjectLanguage {
    param([string]$Language)

    $zhAliases = @(
        "zh",
        "zh-cn",
        "zh-hans",
        "chinese",
        "simplified-chinese",
        "simplified chinese",
        (Join-CodePoints @(0x4E2D, 0x6587)),
        (Join-CodePoints @(0x7B80, 0x4F53, 0x4E2D, 0x6587))
    )

    $normalized = $Language.Trim().ToLowerInvariant()
    if ($normalized -in @("en", "en-us", "english")) {
        return [ordered]@{
            code = "en"
            label = "English"
            marker = "Project memory language: English."
        }
    }

    if ($normalized -in $zhAliases) {
        return [ordered]@{
            code = "zh-CN"
            label = "Simplified Chinese"
            marker = (Join-CodePoints @(0x9879, 0x76EE, 0x8BB0, 0x5FC6, 0x8BED, 0x8A00, 0xFF1A, 0x7B80, 0x4F53, 0x4E2D, 0x6587, 0x3002))
        }
    }

    throw "Unsupported project language: $Language. Supported values: en, en-US, English, zh-CN, zh-Hans, Chinese, Chinese aliases for Simplified Chinese."
}

function Convert-TemplatePathToProjectPath {
    param(
        [string]$TemplateSection,
        [string]$RelativePath
    )

    $normalized = Normalize-RelativePath -Path $RelativePath
    if ($TemplateSection -eq "project-agent") {
        return Normalize-RelativePath -Path (Join-Path ".agents" $normalized)
    }
    return $normalized
}

function Get-LanguageTemplateManifest {
    param(
        [string]$Root,
        [string]$LanguageCode
    )

    $englishRoot = Join-PathParts $Root "en"
    if (-not (Test-Path -LiteralPath $englishRoot)) {
        throw "Missing English template fallback root: $englishRoot"
    }

    $requestedRoot = Join-PathParts $Root $LanguageCode
    if (-not (Test-Path -LiteralPath $requestedRoot)) {
        if ($LanguageCode -eq "en") {
            throw "Missing English template root: $requestedRoot"
        }
    }

    $manifest = New-Object 'System.Collections.Generic.List[object]'
    $warnings = New-Object 'System.Collections.Generic.List[string]'

    foreach ($section in @("project-root", "project-agent")) {
        $englishSection = Join-PathParts $englishRoot $section
        if (-not (Test-Path -LiteralPath $englishSection)) {
            throw "Missing English template section: $englishSection"
        }

        Get-ChildItem -LiteralPath $englishSection -Recurse -File | Sort-Object FullName | ForEach-Object {
            $relative = Normalize-RelativePath -Path $_.FullName.Substring($englishSection.Length).TrimStart([char[]]"\/")
            $projectRelative = Convert-TemplatePathToProjectPath -TemplateSection $section -RelativePath $relative
            $requestedPath = Join-PathParts $requestedRoot $section $relative
            $sourcePath = $requestedPath
            $sourceLanguage = $LanguageCode

            if (-not (Test-Path -LiteralPath $sourcePath)) {
                if ($LanguageCode -eq "en") {
                    throw "Missing English template file: $sourcePath"
                }
                $sourcePath = $_.FullName
                $sourceLanguage = "en"
                $warning = ("Missing {0} template for {1}; falling back to English." -f $LanguageCode, $projectRelative)
                $warnings.Add($warning) | Out-Null
            }

            $manifest.Add([ordered]@{
                relative_path = $projectRelative
                source_path = $sourcePath
                source_language = $sourceLanguage
                section = $section
            }) | Out-Null
        }
    }

    return [ordered]@{
        entries = @($manifest.ToArray())
        warnings = @($warnings.ToArray())
    }
}

function Set-TextFileFromTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    $path = Join-PathParts $ProjectDirFull $RelativePath
    $parent = Split-Path -Parent $path
    Ensure-Dir -Path $parent

    if ((Test-Path -LiteralPath $path) -and -not $OverwriteScaffold.IsPresent) {
        return "skipped"
    }

    if ($PSCmdlet.ShouldProcess($path, "Write localized project memory scaffold")) {
        $templateContent = Read-Utf8Text -Path $SourcePath
        if ((Test-Path -LiteralPath $path) -and $OverwriteScaffold.IsPresent -and -not $SkipOverwriteBackup.IsPresent) {
            $current = Read-Utf8Text -Path $path
            if ($current -ne $templateContent) {
                Backup-LanguageScaffoldFile -Path $path -RelativePath $RelativePath
            }
        }
        Write-Utf8TextWithBom -Path $path -Content $templateContent
    }
    return "written"
}

$ProjectDirFull = [System.IO.Path]::GetFullPath($ProjectDir)
if (-not (Test-Path -LiteralPath $ProjectDirFull)) {
    throw "Project directory does not exist: $ProjectDirFull"
}

if ([string]::IsNullOrWhiteSpace($TemplateRoot)) {
    $skillRoot = Split-Path -Parent $PSScriptRoot
    $TemplateRoot = Join-PathParts $skillRoot "templates" "project-memory"
}

$TemplateRootFull = [System.IO.Path]::GetFullPath($TemplateRoot)
if (-not (Test-Path -LiteralPath $TemplateRootFull)) {
    throw "Project memory template root does not exist: $TemplateRootFull"
}

$resolved = Resolve-ProjectLanguage -Language $ProjectLanguage
$templateManifest = Get-LanguageTemplateManifest -Root $TemplateRootFull -LanguageCode $resolved.code
$scaffoldPaths = New-Object 'System.Collections.Generic.List[string]'
$written = 0
$skipped = 0

foreach ($entry in @($templateManifest.entries)) {
    $relativePath = [string]$entry.relative_path
    $result = Set-TextFileFromTemplate -RelativePath $relativePath -SourcePath ([string]$entry.source_path)
    $scaffoldPaths.Add($relativePath) | Out-Null
    if ($result -eq "written") {
        $written++
    } else {
        $skipped++
    }
}

$resultData = [ordered]@{
    schema_version = 1
    project_dir = $ProjectDirFull
    template_root = $TemplateRootFull
    project_language = $resolved.code
    language_label = $resolved.label
    marker = $resolved.marker
    overwrite_scaffold = [bool]$OverwriteScaffold.IsPresent
    skip_overwrite_backup = [bool]$SkipOverwriteBackup.IsPresent
    files_written = $written
    files_skipped = $skipped
    scaffold_paths = @($scaffoldPaths.ToArray())
    template_warnings = @($templateManifest.warnings)
    fallback_count = @($templateManifest.warnings).Count
    fallback_paths = @($templateManifest.entries | Where-Object { [string]$_.source_language -eq "en" -and $resolved.code -ne "en" } | ForEach-Object { [string]$_.relative_path })
    backup_count = [int]$script:languageBackupCount
    backup_dir = $script:languageBackupDir
    backup_paths = @($script:languageBackupRecords.ToArray())
}

$resultData | ConvertTo-Json -Depth 8
