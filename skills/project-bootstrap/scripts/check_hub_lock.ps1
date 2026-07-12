param(
    [string[]]$ProjectDir = @((Get-Location).Path),
    [string]$HubDir = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "project_language.ps1")

function Join-PathParts {
    param([string]$Root, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Children)
    $path = $Root
    foreach ($child in $Children) {
        foreach ($segment in @($child -split '[\\/]+')) {
            if (-not [string]::IsNullOrWhiteSpace($segment)) { $path = Join-Path $path $segment }
        }
    }
    return $path
}

function Get-TrimmedString {
    param($Value)
    if ($null -eq $Value) { return "" }
    return ([string]$Value).Trim()
}

function Invoke-GitProbe {
    param([string]$RepoDir, [string[]]$GitArgs)
    try {
        $output = @(& git -C $RepoDir @GitArgs 2>$null)
        return [ordered]@{ success = ($LASTEXITCODE -eq 0); value = ($output -join "`n").Trim() }
    } catch { return [ordered]@{ success = $false; value = "" } }
}

function Get-TemplateTreeHash {
    param([string]$HubRoot, [string]$ProjectLanguage)
    $templateRoot = Join-PathParts $HubRoot "templates" "languages" $ProjectLanguage
    $records = @()
    foreach ($root in @(
            @{ Label = "project-root"; Path = (Join-Path $templateRoot "project-root") },
            @{ Label = "project-agent"; Path = (Join-Path $templateRoot "project-agent") }
        )) {
        if (-not (Test-Path -LiteralPath $root.Path -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $root.Path -Recurse -File | Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($root.Path.Length).TrimStart([char[]]"\/") -replace "\\", "/"
            $records += ("{0}/{1}:{2}" -f $root.Label, $relative, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
        }
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($records -join "`n")))).Replace("-", "").ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function New-LockResult {
    param([string]$Status, [string]$Reason, [AllowNull()][object]$Language, [string[]]$ReasonCodes = @())
    return [ordered]@{
        status = $Status
        reason = $Reason
        project_language = $Language
        reason_codes = @($ReasonCodes | Sort-Object -Unique)
    }
}

function Get-HubLockStatus {
    param([string]$Project, [string]$HubOverride)
    if (-not (Test-Path -LiteralPath $Project -PathType Container)) { return New-LockResult "unknown" "project-not-found" $null @("project-not-found") }
    $projectFull = (Resolve-Path -LiteralPath $Project).Path
    $lockPath = Join-PathParts $projectFull ".agents" "hub.lock.json"
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return New-LockResult "unknown" "missing-lock" $null @("missing-lock") }

    try { $lock = [System.IO.File]::ReadAllText($lockPath) | ConvertFrom-Json }
    catch { return New-LockResult "unknown" "invalid-lock" $null @("invalid-lock") }
    if ($null -eq $lock -or $lock -is [System.Array] -or $lock -is [string] -or $lock -is [ValueType]) {
        return New-LockResult "unknown" "invalid-lock" $null @("invalid-lock")
    }
    $lockSchema = $lock.PSObject.Properties["schema_version"]
    if ($null -eq $lockSchema -or ($lockSchema.Value -isnot [int] -and $lockSchema.Value -isnot [long]) -or [int64]$lockSchema.Value -ne 1) {
        return New-LockResult "unknown" "invalid-lock" $null @("invalid-lock")
    }

    try {
        $lockLanguage = ""
        if ($lock.PSObject.Properties.Name -contains "project_language") {
            $rawLanguage = Get-TrimmedString $lock.project_language
            if (-not [string]::IsNullOrWhiteSpace($rawLanguage)) { $lockLanguage = Resolve-ProjectLanguageCode -Language $rawLanguage }
        }
        $guideLanguage = Read-ProjectGuideLanguageCode -ProjectPath $projectFull
    } catch { return New-LockResult "unknown" "project-language-unresolved" $null @("metadata-unresolved") }
    if (-not [string]::IsNullOrWhiteSpace($lockLanguage) -and -not [string]::IsNullOrWhiteSpace($guideLanguage) -and $lockLanguage -ne $guideLanguage) {
        return New-LockResult "unknown" "project-language-conflict" $null @("metadata-unresolved")
    }
    $language = if (-not [string]::IsNullOrWhiteSpace($lockLanguage)) { $lockLanguage } else { $guideLanguage }
    if ([string]::IsNullOrWhiteSpace($language)) { return New-LockResult "unknown" "project-language-unresolved" $null @("metadata-unresolved") }

    $effectiveHubDir = if (-not [string]::IsNullOrWhiteSpace($HubOverride)) { $HubOverride } else { Get-TrimmedString $lock.hub_dir }
    if ([string]::IsNullOrWhiteSpace($effectiveHubDir) -or -not (Test-Path -LiteralPath $effectiveHubDir -PathType Container)) {
        return New-LockResult "unknown" "invalid-hub-dir" $language @("invalid-hub-dir")
    }
    if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { return New-LockResult "unknown" "git-unavailable" $language @("git-unavailable") }
    $gitRoot = Invoke-GitProbe $effectiveHubDir @("rev-parse", "--show-toplevel")
    if (-not $gitRoot.success -or [string]::IsNullOrWhiteSpace($gitRoot.value)) { return New-LockResult "unknown" "hub-not-git" $language @("hub-not-git") }

    $remote = Invoke-GitProbe $effectiveHubDir @("config", "--get", "remote.origin.url")
    $branch = Invoke-GitProbe $effectiveHubDir @("rev-parse", "--abbrev-ref", "HEAD")
    $commit = Invoke-GitProbe $effectiveHubDir @("rev-parse", "--verify", "HEAD")
    $dirty = Invoke-GitProbe $effectiveHubDir @("status", "--porcelain")
    if (-not $remote.success -or -not $branch.success -or -not $commit.success -or -not $dirty.success) {
        return New-LockResult "unknown" "metadata-unresolved" $language @("metadata-unresolved")
    }

    $lockedRemote = Get-TrimmedString $lock.hub_remote
    $lockedBranch = Get-TrimmedString $lock.hub_branch
    $lockedCommit = Get-TrimmedString $lock.hub_commit
    if ([string]::IsNullOrWhiteSpace($lockedRemote) -or [string]::IsNullOrWhiteSpace($lockedBranch) -or $lockedCommit -cnotmatch '^[0-9a-fA-F]{40}$') {
        return New-LockResult "unknown" "metadata-unresolved" $language @("metadata-unresolved")
    }
    $unknownCodes = @()
    if ($lockedRemote -ne $remote.value) { $unknownCodes += "hub-remote-drift" }
    if ($lockedBranch -ne $branch.value) { $unknownCodes += "hub-branch-drift" }
    if ($lock.PSObject.Properties.Name -contains "hub_dirty" -and $lock.hub_dirty -isnot [bool]) {
        return New-LockResult "unknown" "invalid-lock" $language @("invalid-lock")
    }
    if ($lock.PSObject.Properties.Name -contains "hub_dirty" -and [bool]$lock.hub_dirty) { $unknownCodes += "locked-hub-dirty" }
    if (-not [string]::IsNullOrWhiteSpace($dirty.value)) { $unknownCodes += "current-hub-dirty" }
    if ($unknownCodes.Count -gt 0) { return New-LockResult "unknown" $unknownCodes[0] $language $unknownCodes }

    try { $templateHash = Get-TemplateTreeHash -HubRoot $effectiveHubDir -ProjectLanguage $language }
    catch { return New-LockResult "unknown" "metadata-unresolved" $language @("metadata-unresolved") }
    $lockedTemplateHash = Get-TrimmedString $lock.template_tree_hash_sha256
    if (-not [string]::IsNullOrWhiteSpace($lockedTemplateHash) -and $lockedTemplateHash -cnotmatch '^[0-9a-fA-F]{64}$') {
        return New-LockResult "unknown" "invalid-lock" $language @("invalid-lock")
    }
    $driftCodes = @()
    if ($lockedCommit -ne $commit.value) { $driftCodes += "hub-commit-drift" }
    if ([string]::IsNullOrWhiteSpace($lockedTemplateHash)) { $driftCodes += "template-hash-missing" }
    elseif ($lockedTemplateHash -ne $templateHash) { $driftCodes += "template-tree-drift" }
    if ($driftCodes.Count -gt 0) { return New-LockResult "drift" $driftCodes[0] $language $driftCodes }
    return New-LockResult "in-sync" "hub-lock-in-sync" $language @()
}

$results = @($ProjectDir | ForEach-Object {
        try { Get-HubLockStatus -Project $_ -HubOverride $HubDir }
        catch { New-LockResult "unknown" "internal-error" $null @("internal-error") }
    })
if ($Json.IsPresent) {
    [ordered]@{ schema_version = 1; results = $results } | ConvertTo-Json -Depth 6
    $global:LASTEXITCODE = 0
    return
}

$hasDrift = $false
for ($index = 0; $index -lt $results.Count; $index++) {
    Write-Output ("Project: {0}" -f $ProjectDir[$index])
    $textStatus = switch ([string]$results[$index].reason) {
        "missing-lock" { "missing_lock" }
        "invalid-hub-dir" { "invalid_hub_dir" }
        "hub-not-git" { "hub_not_git" }
        default { if ([string]$results[$index].status -eq "in-sync") { "in_sync" } else { "drift" } }
    }
    Write-Output ("Status: {0}" -f $textStatus)
    Write-Output ("Reason: {0}" -f $results[$index].reason)
    Write-Output ""
    if ([string]$results[$index].status -ne "in-sync") { $hasDrift = $true }
}
if ($hasDrift) { exit 1 }
