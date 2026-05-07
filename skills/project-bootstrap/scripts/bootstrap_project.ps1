param(
    [string]$ProjectDir = (Get-Location).Path,
    [string]$HubDir = "$env:USERPROFILE\.agents\knowledge-hub",
    [switch]$OverwriteTemplates,
    [switch]$AnalyzeMemoryUpgrade,
    [switch]$PlanMemoryUpgrade,
    [switch]$ApplyMemoryUpgrade,
    [switch]$SkipMemoryUpgradeAnalysis,
    [string]$UpgradePlan = ""
)

$ErrorActionPreference = "Stop"

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Copy-TemplateFile {
    param(
        [string]$Source,
        [string]$Destination,
        [bool]$AllowOverwrite
    )

    $destinationDir = Split-Path -Parent $Destination
    Ensure-Dir -Path $destinationDir

    if (-not (Test-Path -LiteralPath $Destination)) {
        # Target missing, copy directly
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return "copied"
    }

    # Compare content hash
    $sourceHash = (Get-FileHash -Path $Source -Algorithm SHA256).Hash
    $destHash = (Get-FileHash -Path $Destination -Algorithm SHA256).Hash

    if ($sourceHash -eq $destHash) {
        # Content identical, skip
        return "skipped"
    }

    # Content differs
    if ($AllowOverwrite) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return "updated"
    }

    return "skipped"
}

function Get-TemplateTreeHash {
    param(
        [string]$ProjectRootTemplate,
        [string]$ProjectAgentTemplate
    )

    $records = @()
    $roots = @(
        @{ Label = "project-root"; Path = $ProjectRootTemplate },
        @{ Label = "project-agent"; Path = $ProjectAgentTemplate }
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root.Path)) {
            continue
        }

        Get-ChildItem -LiteralPath $root.Path -Recurse -File |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($root.Path.Length).TrimStart([char[]]"\/")
                $relative = $relative -replace "\\", "/"
                $fileHash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                $records += ("{0}/{1}:{2}" -f $root.Label, $relative, $fileHash)
            }
    }

    $content = $records -join "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $ProjectDir)) {
    throw "Project directory does not exist: $ProjectDir"
}

$templateRoot = Join-Path $HubDir "templates"
$projectRootTemplate = Join-Path $templateRoot "project-root"
$projectAgentTemplate = Join-Path $templateRoot "project-agent"

$missingTemplateFolders = @()
if (-not (Test-Path -LiteralPath $projectRootTemplate)) {
    $missingTemplateFolders += $projectRootTemplate
}
if (-not (Test-Path -LiteralPath $projectAgentTemplate)) {
    $missingTemplateFolders += $projectAgentTemplate
}

if ($missingTemplateFolders.Count -gt 0) {
    $initHubScript = Join-Path $PSScriptRoot "init_hub.ps1"
    if (Test-Path -LiteralPath $initHubScript) {
        Write-Warning ("Hub templates missing; initializing hub at {0} from bundled bootstrap assets." -f $HubDir)
        & $initHubScript -HubDir $HubDir | Out-Null
    }
}

if (-not (Test-Path -LiteralPath $projectRootTemplate)) {
    throw "Missing template folder: $projectRootTemplate. Run scripts/init_hub.ps1 -HubDir `"$HubDir`" or install the knowledge-hub repository."
}
if (-not (Test-Path -LiteralPath $projectAgentTemplate)) {
    throw "Missing template folder: $projectAgentTemplate. Run scripts/init_hub.ps1 -HubDir `"$HubDir`" or install the knowledge-hub repository."
}

$copiedCount = 0
$skippedCount = 0
$updatedCount = 0

Get-ChildItem -Path $projectRootTemplate -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($projectRootTemplate.Length).TrimStart([char[]]"\/")
    $destination = Join-Path $ProjectDir $relative
    $result = Copy-TemplateFile -Source $_.FullName -Destination $destination -AllowOverwrite $OverwriteTemplates.IsPresent
    if ($result -eq "copied") { $copiedCount++ }
    elseif ($result -eq "updated") { $updatedCount++ }
    else { $skippedCount++ }
}

$projectAgentDir = Join-Path $ProjectDir ".agents"
Ensure-Dir -Path $projectAgentDir

Get-ChildItem -Path $projectAgentTemplate -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($projectAgentTemplate.Length).TrimStart([char[]]"\/")
    $destination = Join-Path $projectAgentDir $relative
    $result = Copy-TemplateFile -Source $_.FullName -Destination $destination -AllowOverwrite $OverwriteTemplates.IsPresent
    if ($result -eq "copied") { $copiedCount++ }
    elseif ($result -eq "updated") { $updatedCount++ }
    else { $skippedCount++ }
}

$git = Get-Command git -ErrorAction SilentlyContinue
$hubCommit = "UNKNOWN"
$hubBranch = "UNKNOWN"
$hubRemote = ""
$hubDirty = $false
if (($null -ne $git) -and (Test-Path -LiteralPath (Join-Path $HubDir ".git"))) {
    try {
        $commitProbe = (& git -C $HubDir rev-parse --verify HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($commitProbe)) {
            $hubCommit = $commitProbe.Trim()
        }
    } catch {}

    try {
        $branchProbe = (& git -C $HubDir rev-parse --abbrev-ref HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branchProbe)) {
            $hubBranch = $branchProbe.Trim()
        }
    } catch {}

    try {
        $remoteProbe = (& git -C $HubDir config --get remote.origin.url 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($remoteProbe)) {
            $hubRemote = $remoteProbe.Trim()
        }
    } catch {}

    try {
        $dirtyProbe = (& git -C $HubDir status --porcelain 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($dirtyProbe)) {
            $hubDirty = $true
        }
    } catch {}
}

$templateTreeHash = Get-TemplateTreeHash -ProjectRootTemplate $projectRootTemplate -ProjectAgentTemplate $projectAgentTemplate

$lockData = [ordered]@{
    schema_version = 1
    installed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    installer = "project-bootstrap"
    project_dir = (Resolve-Path -LiteralPath $ProjectDir).Path
    hub_dir = $HubDir
    hub_remote = $hubRemote
    hub_branch = $hubBranch
    hub_commit = $hubCommit
    hub_dirty = [bool]$hubDirty
    template_source = "templates/project-root + templates/project-agent"
    template_tree_hash_sha256 = $templateTreeHash
    overwrite_templates = [bool]$OverwriteTemplates.IsPresent
}

$lockPath = Join-Path $projectAgentDir "hub.lock.json"
$lockData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $lockPath -Encoding UTF8

Write-Output "Project bootstrap complete."
Write-Output "Project: $ProjectDir"
Write-Output "Hub: $HubDir"
Write-Output ("Template files copied: {0}, updated: {1}, skipped: {2}" -f $copiedCount, $updatedCount, $skippedCount)
Write-Output "Lock file: $lockPath"

$memoryUpgradeScript = Join-Path $PSScriptRoot "memory_upgrade.ps1"
if ($AnalyzeMemoryUpgrade.IsPresent -or $PlanMemoryUpgrade.IsPresent -or $ApplyMemoryUpgrade.IsPresent) {
    if (-not (Test-Path -LiteralPath $memoryUpgradeScript)) {
        throw "Memory upgrade helper not found: $memoryUpgradeScript"
    }

    if ($ApplyMemoryUpgrade.IsPresent) {
        & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Apply -UpgradePlan $UpgradePlan
    } elseif ($PlanMemoryUpgrade.IsPresent) {
        & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Plan
    } else {
        & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Analyze
    }
} elseif (-not $SkipMemoryUpgradeAnalysis.IsPresent -and (Test-Path -LiteralPath $memoryUpgradeScript)) {
    try {
        $analysisJson = & $memoryUpgradeScript -ProjectDir $ProjectDir -Mode Analyze -Json | ConvertFrom-Json
        $findingCount = @($analysisJson.findings).Count
        if ($findingCount -gt 0) {
            Write-Output ("Memory upgrade candidates detected: {0}" -f $findingCount)
            Write-Output "Run with -PlanMemoryUpgrade to create a reviewable proposal, then -ApplyMemoryUpgrade -UpgradePlan <path> after review."
        }
    } catch {
        Write-Warning "Memory upgrade analysis failed: $($_.Exception.Message)"
    }
}
