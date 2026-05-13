param(
    [string]$HubDir = "$env:USERPROFILE\.agents\knowledge-hub",
    [switch]$Overwrite,
    [switch]$InitializeGit,
    [switch]$CommitInitial
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

function Sync-Tree {
    param(
        [string]$SourceRoot,
        [string]$DestinationRoot,
        [bool]$AllowOverwrite
    )

    $copied = 0
    $skipped = 0
    $updated = 0

    Get-ChildItem -Path $SourceRoot -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($SourceRoot.Length).TrimStart([char[]]"\/")
        $destination = Join-Path $DestinationRoot $relative
        $destinationDir = Split-Path -Parent $destination
        Ensure-Dir -Path $destinationDir

        if (-not (Test-Path -LiteralPath $destination)) {
            # Target missing, copy directly
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
            $copied++
            return
        }

        # Compare content hash
        $sourceHash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
        $destHash = (Get-FileHash -Path $destination -Algorithm SHA256).Hash

        if ($sourceHash -eq $destHash) {
            # Content identical, skip
            $skipped++
            return
        }

        # Content differs
        if ($AllowOverwrite) {
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
            $updated++
        } else {
            $skipped++
        }
    }

    return @{
        copied = $copied
        skipped = $skipped
        updated = $updated
    }
}

function Sync-File {
    param(
        [string]$Source,
        [string]$Destination,
        [bool]$AllowOverwrite
    )

    $destinationDir = Split-Path -Parent $Destination
    Ensure-Dir -Path $destinationDir

    if (-not (Test-Path -LiteralPath $Destination)) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return "copied"
    }

    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $destHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($sourceHash -eq $destHash) {
        return "skipped"
    }

    if ($AllowOverwrite) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return "updated"
    }

    return "skipped"
}

function Remove-LegacyTemplateDirs {
    param([string]$Root)

    $removed = 0
    foreach ($relative in @(
        "templates/project-root",
        "templates/project-agent",
        "templates/project-memory"
    )) {
        $target = Join-PathParts $Root $relative
        if (-not (Test-Path -LiteralPath $target)) {
            continue
        }

        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]"\/")
        $targetFull = [System.IO.Path]::GetFullPath($target)
        if (-not $targetFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove legacy template directory outside hub: $targetFull"
        }

        Remove-Item -LiteralPath $targetFull -Recurse -Force
        $removed++
    }
    return $removed
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$templateRoot = Join-PathParts $skillRoot "assets" "knowledge-hub-template"
$rebuildScript = Join-PathParts $PSScriptRoot "rebuild_experience_index.ps1"

if (-not (Test-Path -LiteralPath $templateRoot)) {
    throw "Hub template not found: $templateRoot"
}

Ensure-Dir -Path $HubDir

# Preserve existing experience index metadata before sync may overwrite it
$experienceDir = Join-PathParts $HubDir "knowledge" "experience"
$indexPath = Join-PathParts $experienceDir "index.json"
$indexBackup = ""
if ($Overwrite.IsPresent -and (Test-Path -LiteralPath $indexPath)) {
    $indexBackup = Join-Path $env:TEMP "hub_index_backup_$([guid]::NewGuid().ToString('N')).json"
    Copy-Item -LiteralPath $indexPath -Destination $indexBackup -Force
}

$sync = Sync-Tree -SourceRoot $templateRoot -DestinationRoot $HubDir -AllowOverwrite $Overwrite.IsPresent
$legacyTemplateDirsRemoved = Remove-LegacyTemplateDirs -Root $HubDir

$runtimeScriptCopied = 0
$runtimeScriptUpdated = 0
$runtimeScriptSkipped = 0
$hubScriptsDir = Join-PathParts $HubDir "scripts"
foreach ($scriptName in @("promote_experience.ps1", "rebuild_experience_index.ps1")) {
    $sourceScript = Join-Path $PSScriptRoot $scriptName
    if (-not (Test-Path -LiteralPath $sourceScript)) {
        continue
    }

    $result = Sync-File -Source $sourceScript -Destination (Join-Path $hubScriptsDir $scriptName) -AllowOverwrite $Overwrite.IsPresent
    if ($result -eq "copied") { $runtimeScriptCopied++ }
    elseif ($result -eq "updated") { $runtimeScriptUpdated++ }
    else { $runtimeScriptSkipped++ }
}

# Restore backed-up index before rebuild so existing metadata can be merged
if ($indexBackup -and (Test-Path -LiteralPath $indexBackup)) {
    Copy-Item -LiteralPath $indexBackup -Destination $indexPath -Force
    Remove-Item -LiteralPath $indexBackup -Force -ErrorAction SilentlyContinue
}

if ((Test-Path -LiteralPath $experienceDir) -and (Test-Path -LiteralPath $rebuildScript)) {
    & $rebuildScript -HubDir $HubDir | Out-Null
}

$git = Get-Command git -ErrorAction SilentlyContinue
$shouldInitializeGit = $InitializeGit.IsPresent -or $CommitInitial.IsPresent
if (($null -ne $git) -and $shouldInitializeGit) {
    if (-not (Test-Path -LiteralPath (Join-Path $HubDir ".git"))) {
        git -C $HubDir init | Out-Null
    }

    if ($CommitInitial.IsPresent) {
        git -C $HubDir add . | Out-Null
        try {
            $dirty = git -C $HubDir status --porcelain
            if ($dirty) {
                git -C $HubDir commit -m "Initialize knowledge hub templates" | Out-Null
            }
        } catch {
            Write-Warning "Initial commit failed. Configure git user.name/user.email and commit manually."
        }
    }
}

Write-Output "Hub ready: $HubDir"
Write-Output ("Files copied: {0}, updated: {1}, skipped: {2}" -f $sync.copied, $sync.updated, $sync.skipped)
Write-Output ("Legacy template directories removed: {0}" -f $legacyTemplateDirsRemoved)
Write-Output ("Runtime scripts copied: {0}, updated: {1}, skipped: {2}" -f $runtimeScriptCopied, $runtimeScriptUpdated, $runtimeScriptSkipped)
