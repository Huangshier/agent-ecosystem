param(
    [string[]]$ProjectDir = @((Get-Location).Path),
    [string]$HubDir = ""
)

$ErrorActionPreference = "Stop"

function Get-TrimmedString {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value).Trim()
}

function Get-GitValue {
    param(
        [string]$RepoDir,
        [string[]]$GitArgs
    )

    try {
        $probe = (& git -C $RepoDir @GitArgs 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($probe)) {
            return ([string]$probe).Trim()
        }
    } catch {}

    return ""
}

function Get-TemplateTreeHash {
    param(
        [string]$HubRoot
    )

    $templateRoot = Join-Path $HubRoot "templates"
    $projectRootTemplate = Join-Path $templateRoot "project-root"
    $projectAgentTemplate = Join-Path $templateRoot "project-agent"
    $records = @()
    $roots = @(
        @{ Label = "project-root"; Path = $projectRootTemplate },
        @{ Label = "project-agent"; Path = $projectAgentTemplate }
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

$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $git) {
    throw "Git is not installed or not in PATH."
}

$hasDrift = $false

foreach ($project in $ProjectDir) {
    $projectFull = (Resolve-Path -LiteralPath $project).Path
    $lockPath = Join-Path $projectFull ".agents\hub.lock.json"

    Write-Output ("Project: {0}" -f $projectFull)

    if (-not (Test-Path -LiteralPath $lockPath)) {
        Write-Output ("Lock file: missing ({0})" -f $lockPath)
        Write-Output "Status: missing_lock"
        Write-Output ""
        $hasDrift = $true
        continue
    }

    $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
    $effectiveHubDir = if (-not [string]::IsNullOrWhiteSpace($HubDir)) {
        $HubDir
    } else {
        Get-TrimmedString -Value $lock.hub_dir
    }

    Write-Output ("Lock file: {0}" -f $lockPath)
    Write-Output ("Locked hub dir: {0}" -f (Get-TrimmedString -Value $lock.hub_dir))
    Write-Output ("Locked hub remote: {0}" -f (Get-TrimmedString -Value $lock.hub_remote))
    Write-Output ("Locked hub branch: {0}" -f (Get-TrimmedString -Value $lock.hub_branch))
    Write-Output ("Locked hub commit: {0}" -f (Get-TrimmedString -Value $lock.hub_commit))

    if ([string]::IsNullOrWhiteSpace($effectiveHubDir) -or -not (Test-Path -LiteralPath $effectiveHubDir)) {
        Write-Output ("Resolved hub dir: {0}" -f $effectiveHubDir)
        Write-Output "Status: invalid_hub_dir"
        Write-Output ""
        $hasDrift = $true
        continue
    }

    $hubGitDir = Join-Path $effectiveHubDir ".git"
    if (-not (Test-Path -LiteralPath $hubGitDir)) {
        Write-Output ("Resolved hub dir: {0}" -f $effectiveHubDir)
        Write-Output "Status: hub_not_git"
        Write-Output ""
        $hasDrift = $true
        continue
    }

    $currentRemote = Get-GitValue -RepoDir $effectiveHubDir -GitArgs @("config", "--get", "remote.origin.url")
    $currentBranch = Get-GitValue -RepoDir $effectiveHubDir -GitArgs @("rev-parse", "--abbrev-ref", "HEAD")
    $currentCommit = Get-GitValue -RepoDir $effectiveHubDir -GitArgs @("rev-parse", "--verify", "HEAD")
    $currentDirty = -not [string]::IsNullOrWhiteSpace((Get-GitValue -RepoDir $effectiveHubDir -GitArgs @("status", "--porcelain")))
    $currentTemplateHash = Get-TemplateTreeHash -HubRoot $effectiveHubDir

    Write-Output ("Resolved hub dir: {0}" -f $effectiveHubDir)
    Write-Output ("Current hub remote: {0}" -f $currentRemote)
    Write-Output ("Current hub branch: {0}" -f $currentBranch)
    Write-Output ("Current hub commit: {0}" -f $currentCommit)
    Write-Output ("Current hub dirty: {0}" -f $currentDirty)
    Write-Output ("Current template hash: {0}" -f $currentTemplateHash)

    $differences = @()
    $lockedRemote = Get-TrimmedString -Value $lock.hub_remote
    $lockedBranch = Get-TrimmedString -Value $lock.hub_branch
    $lockedCommit = Get-TrimmedString -Value $lock.hub_commit
    $lockedTemplateHash = Get-TrimmedString -Value $lock.template_tree_hash_sha256
    $lockedDirty = $false

    if ($lock.PSObject.Properties.Name -contains "hub_dirty") {
        $lockedDirty = [bool]$lock.hub_dirty
        Write-Output ("Locked hub dirty: {0}" -f $lockedDirty)
    }
    if (-not [string]::IsNullOrWhiteSpace($lockedTemplateHash)) {
        Write-Output ("Locked template hash: {0}" -f $lockedTemplateHash)
    }

    if (-not [string]::IsNullOrWhiteSpace($lockedRemote) -and [string]::IsNullOrWhiteSpace($currentRemote)) {
        $differences += "hub_remote drift: current hub remote could not be resolved"
    }
    if (-not [string]::IsNullOrWhiteSpace($lockedBranch) -and [string]::IsNullOrWhiteSpace($currentBranch)) {
        $differences += "hub_branch drift: current hub branch could not be resolved"
    }
    if (-not [string]::IsNullOrWhiteSpace($lockedCommit) -and [string]::IsNullOrWhiteSpace($currentCommit)) {
        $differences += "hub_commit drift: current hub commit could not be resolved"
    }
    if (-not [string]::IsNullOrWhiteSpace($lockedRemote) -and -not [string]::IsNullOrWhiteSpace($currentRemote) -and $lockedRemote -ne $currentRemote) {
        $differences += ("hub_remote drift: lock={0} current={1}" -f $lockedRemote, $currentRemote)
    }
    if (-not [string]::IsNullOrWhiteSpace($lockedBranch) -and -not [string]::IsNullOrWhiteSpace($currentBranch) -and $lockedBranch -ne $currentBranch) {
        $differences += ("hub_branch drift: lock={0} current={1}" -f $lockedBranch, $currentBranch)
    }
    if (-not [string]::IsNullOrWhiteSpace($lockedCommit) -and -not [string]::IsNullOrWhiteSpace($currentCommit) -and $lockedCommit -ne $currentCommit) {
        $differences += ("hub_commit drift: lock={0} current={1}" -f $lockedCommit, $currentCommit)
    }
    if (-not [string]::IsNullOrWhiteSpace($lockedTemplateHash) -and [string]::IsNullOrWhiteSpace($currentTemplateHash)) {
        $differences += "template tree drift: current template hash could not be resolved"
    }
    if (-not [string]::IsNullOrWhiteSpace($lockedTemplateHash) -and -not [string]::IsNullOrWhiteSpace($currentTemplateHash) -and $lockedTemplateHash -ne $currentTemplateHash) {
        $differences += ("template tree drift: lock={0} current={1}" -f $lockedTemplateHash, $currentTemplateHash)
    }
    if ($lockedDirty) {
        $differences += "hub_dirty: lock was created from a dirty hub; reinstall bootstrap after committing or discarding hub changes"
    }
    if ($currentDirty) {
        $differences += "hub_dirty: current hub has uncommitted changes; commit or discard them before treating the lock as reproducible"
    }

    if ($differences.Count -eq 0) {
        Write-Output "Status: in_sync"
    } else {
        Write-Output "Status: drift"
        $differences | ForEach-Object { Write-Output ("- {0}" -f $_) }
        $hasDrift = $true
    }

    Write-Output ""
}

if ($hasDrift) {
    exit 1
}
