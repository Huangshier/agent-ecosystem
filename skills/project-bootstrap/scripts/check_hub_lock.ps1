param(
    [string[]]$ProjectDir = @((Get-Location).Path),
    [string]$HubDir = "",
    [string]$RuntimeDir = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "project_language.ps1")
. (Join-Path $PSScriptRoot "managed_copy_hub_provenance.ps1")

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

function New-HubLockFacts {
    param([string]$Project)
    return [ordered]@{
        status = "unknown"; reason = "internal-error"; reason_codes = @("internal-error"); project_language = $null
        project_path = $Project; lock_path = ""; locked_hub_dir = ""; locked_hub_remote = ""; locked_hub_branch = ""
        locked_hub_commit = ""; locked_hub_dirty = $null; resolved_hub_dir = ""; current_hub_remote = ""
        current_hub_branch = ""; current_hub_commit = ""; current_hub_dirty = $null; current_template_hash = ""
        locked_template_hash = ""; differences = @()
    }
}

function Set-HubLockOutcome {
    param([System.Collections.IDictionary]$Facts, [string]$Status, [string]$Reason, [string[]]$ReasonCodes)
    $Facts.status = $Status
    $Facts.reason = $Reason
    $Facts.reason_codes = @($ReasonCodes | Sort-Object -Unique)
    return $Facts
}

function Get-HubLockFacts {
    param([string]$Project, [string]$HubOverride, [string]$RuntimeRoot)
    $facts = New-HubLockFacts -Project $Project
    if (-not (Test-Path -LiteralPath $Project -PathType Container)) {
        return Set-HubLockOutcome $facts "unknown" "project-not-found" @("project-not-found")
    }
    $facts.project_path = (Resolve-Path -LiteralPath $Project).Path
    $facts.lock_path = Join-PathParts $facts.project_path ".agents" "hub.lock.json"
    if (-not (Test-Path -LiteralPath $facts.lock_path -PathType Leaf)) {
        return Set-HubLockOutcome $facts "unknown" "missing-lock" @("missing-lock")
    }

    try { $lock = [System.IO.File]::ReadAllText($facts.lock_path) | ConvertFrom-Json }
    catch { return Set-HubLockOutcome $facts "unknown" "invalid-lock" @("invalid-lock") }
    if ($null -eq $lock -or $lock -is [System.Array] -or $lock -is [string] -or $lock -is [ValueType]) {
        return Set-HubLockOutcome $facts "unknown" "invalid-lock" @("invalid-lock")
    }
    $lockSchema = $lock.PSObject.Properties["schema_version"]
    if ($null -eq $lockSchema -or ($lockSchema.Value -isnot [int] -and $lockSchema.Value -isnot [long]) -or [int64]$lockSchema.Value -ne 1) {
        return Set-HubLockOutcome $facts "unknown" "invalid-lock" @("invalid-lock")
    }

    $facts.locked_hub_dir = Get-TrimmedString $lock.hub_dir
    $facts.locked_hub_remote = Get-TrimmedString $lock.hub_remote
    $facts.locked_hub_branch = Get-TrimmedString $lock.hub_branch
    $facts.locked_hub_commit = Get-TrimmedString $lock.hub_commit
    $facts.locked_template_hash = Get-TrimmedString $lock.template_tree_hash_sha256
    if ($lock.PSObject.Properties.Name -contains "hub_dirty") {
        if ($lock.hub_dirty -isnot [bool]) { return Set-HubLockOutcome $facts "unknown" "invalid-lock" @("invalid-lock") }
        $facts.locked_hub_dirty = [bool]$lock.hub_dirty
    }

    try {
        $lockLanguage = ""
        if ($lock.PSObject.Properties.Name -contains "project_language") {
            $rawLanguage = Get-TrimmedString $lock.project_language
            if (-not [string]::IsNullOrWhiteSpace($rawLanguage)) { $lockLanguage = Resolve-ProjectLanguageCode -Language $rawLanguage }
        }
        $guideLanguage = Read-ProjectGuideLanguageCode -ProjectPath $facts.project_path
    } catch { return Set-HubLockOutcome $facts "unknown" "project-language-unresolved" @("metadata-unresolved") }
    if ($lockLanguage -and $guideLanguage -and $lockLanguage -ne $guideLanguage) {
        return Set-HubLockOutcome $facts "unknown" "project-language-conflict" @("metadata-unresolved")
    }
    $facts.project_language = if ($lockLanguage) { $lockLanguage } else { $guideLanguage }
    if (-not $facts.project_language) { return Set-HubLockOutcome $facts "unknown" "project-language-unresolved" @("metadata-unresolved") }

    $facts.resolved_hub_dir = if ($HubOverride) { $HubOverride } else { $facts.locked_hub_dir }
    if (-not $facts.resolved_hub_dir -or -not (Test-Path -LiteralPath $facts.resolved_hub_dir -PathType Container)) {
        return Set-HubLockOutcome $facts "unknown" "invalid-hub-dir" @("invalid-hub-dir")
    }
    if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { return Set-HubLockOutcome $facts "unknown" "git-unavailable" @("git-unavailable") }
    $gitRoot = Invoke-GitProbe $facts.resolved_hub_dir @("rev-parse", "--show-toplevel")
    if (-not $gitRoot.success -or -not $gitRoot.value) {
        $hasLockedGitMetadata = -not [string]::IsNullOrWhiteSpace($facts.locked_hub_remote) -or
            (-not [string]::IsNullOrWhiteSpace($facts.locked_hub_branch) -and $facts.locked_hub_branch -ne "UNKNOWN") -or
            (-not [string]::IsNullOrWhiteSpace($facts.locked_hub_commit) -and $facts.locked_hub_commit -ne "UNKNOWN")
        $trustedManagedCopy = -not [string]::IsNullOrWhiteSpace($RuntimeRoot) -and
            (Test-TrustedManagedCopyHub -RuntimeDir $RuntimeRoot -HubDir $facts.resolved_hub_dir)
        if ($hasLockedGitMetadata -and -not $trustedManagedCopy) {
            return Set-HubLockOutcome $facts "unknown" "hub-not-git" @("hub-not-git")
        }
        if ($facts.locked_hub_dirty) {
            return Set-HubLockOutcome $facts "unknown" "locked-hub-dirty" @("locked-hub-dirty")
        }
        try { $facts.current_template_hash = Get-TemplateTreeHash $facts.resolved_hub_dir $facts.project_language }
        catch { return Set-HubLockOutcome $facts "unknown" "metadata-unresolved" @("metadata-unresolved") }
        if ($facts.locked_template_hash -and $facts.locked_template_hash -cnotmatch '^[0-9a-fA-F]{64}$') {
            return Set-HubLockOutcome $facts "unknown" "invalid-lock" @("invalid-lock")
        }
        if (-not $facts.locked_template_hash) {
            $facts.differences += "template tree drift: lock does not contain a template hash"
            return Set-HubLockOutcome $facts "drift" "template-hash-missing" @("template-hash-missing")
        }
        if ($facts.locked_template_hash -ne $facts.current_template_hash) {
            $facts.differences += ("template tree drift: lock={0} current={1}" -f $facts.locked_template_hash, $facts.current_template_hash)
            return Set-HubLockOutcome $facts "drift" "template-tree-drift" @("template-tree-drift")
        }
        return Set-HubLockOutcome $facts "in-sync" "hub-lock-in-sync" @()
    }

    $remote = Invoke-GitProbe $facts.resolved_hub_dir @("config", "--get", "remote.origin.url")
    $branch = Invoke-GitProbe $facts.resolved_hub_dir @("rev-parse", "--abbrev-ref", "HEAD")
    $commit = Invoke-GitProbe $facts.resolved_hub_dir @("rev-parse", "--verify", "HEAD")
    $dirty = Invoke-GitProbe $facts.resolved_hub_dir @("status", "--porcelain")
    if (-not $remote.success -or -not $branch.success -or -not $commit.success -or -not $dirty.success) {
        return Set-HubLockOutcome $facts "unknown" "metadata-unresolved" @("metadata-unresolved")
    }
    $facts.current_hub_remote = $remote.value
    $facts.current_hub_branch = $branch.value
    $facts.current_hub_commit = $commit.value
    $facts.current_hub_dirty = -not [string]::IsNullOrWhiteSpace($dirty.value)

    if (-not $facts.locked_hub_remote -or -not $facts.locked_hub_branch -or $facts.locked_hub_commit -cnotmatch '^[0-9a-fA-F]{40}$') {
        return Set-HubLockOutcome $facts "unknown" "metadata-unresolved" @("metadata-unresolved")
    }
    $unknownCodes = @()
    if ($facts.locked_hub_remote -ne $facts.current_hub_remote) {
        $unknownCodes += "hub-remote-drift"; $facts.differences += ("hub_remote drift: lock={0} current={1}" -f $facts.locked_hub_remote, $facts.current_hub_remote)
    }
    if ($facts.locked_hub_branch -ne $facts.current_hub_branch) {
        $unknownCodes += "hub-branch-drift"; $facts.differences += ("hub_branch drift: lock={0} current={1}" -f $facts.locked_hub_branch, $facts.current_hub_branch)
    }
    if ($facts.locked_hub_dirty) {
        $unknownCodes += "locked-hub-dirty"; $facts.differences += "hub_dirty: lock was created from a dirty hub; reinstall bootstrap after committing or discarding hub changes"
    }
    if ($facts.current_hub_dirty) {
        $unknownCodes += "current-hub-dirty"; $facts.differences += "hub_dirty: current hub has uncommitted changes; commit or discard them before treating the lock as reproducible"
    }
    if ($unknownCodes.Count -gt 0) { return Set-HubLockOutcome $facts "unknown" $unknownCodes[0] $unknownCodes }

    try { $facts.current_template_hash = Get-TemplateTreeHash $facts.resolved_hub_dir $facts.project_language }
    catch { return Set-HubLockOutcome $facts "unknown" "metadata-unresolved" @("metadata-unresolved") }
    if ($facts.locked_template_hash -and $facts.locked_template_hash -cnotmatch '^[0-9a-fA-F]{64}$') {
        return Set-HubLockOutcome $facts "unknown" "invalid-lock" @("invalid-lock")
    }
    $driftCodes = @()
    if ($facts.locked_hub_commit -ne $facts.current_hub_commit) {
        $driftCodes += "hub-commit-drift"; $facts.differences += ("hub_commit drift: lock={0} current={1}" -f $facts.locked_hub_commit, $facts.current_hub_commit)
    }
    if (-not $facts.locked_template_hash) {
        $driftCodes += "template-hash-missing"; $facts.differences += "template tree drift: lock does not contain a template hash"
    } elseif ($facts.locked_template_hash -ne $facts.current_template_hash) {
        $driftCodes += "template-tree-drift"; $facts.differences += ("template tree drift: lock={0} current={1}" -f $facts.locked_template_hash, $facts.current_template_hash)
    }
    if ($driftCodes.Count -gt 0) { return Set-HubLockOutcome $facts "drift" $driftCodes[0] $driftCodes }
    return Set-HubLockOutcome $facts "in-sync" "hub-lock-in-sync" @()
}

function Write-HubLockText {
    param([System.Collections.IDictionary]$Facts)
    Write-Output ("Project: {0}" -f $Facts.project_path)
    Write-Output ("Lock file: {0}" -f $(if ($Facts.lock_path) { $Facts.lock_path } else { "missing" }))
    Write-Output ("Locked hub dir: {0}" -f $Facts.locked_hub_dir)
    Write-Output ("Locked hub remote: {0}" -f $Facts.locked_hub_remote)
    Write-Output ("Locked hub branch: {0}" -f $Facts.locked_hub_branch)
    Write-Output ("Locked hub commit: {0}" -f $Facts.locked_hub_commit)
    if ($null -ne $Facts.locked_hub_dirty) { Write-Output ("Locked hub dirty: {0}" -f $Facts.locked_hub_dirty) }
    Write-Output ("Resolved hub dir: {0}" -f $Facts.resolved_hub_dir)
    Write-Output ("Current hub remote: {0}" -f $Facts.current_hub_remote)
    Write-Output ("Current hub branch: {0}" -f $Facts.current_hub_branch)
    Write-Output ("Current hub commit: {0}" -f $Facts.current_hub_commit)
    Write-Output ("Current hub dirty: {0}" -f $Facts.current_hub_dirty)
    Write-Output ("Template language: {0}" -f $Facts.project_language)
    Write-Output ("Current template hash: {0}" -f $Facts.current_template_hash)
    Write-Output ("Locked template hash: {0}" -f $Facts.locked_template_hash)
    $textStatus = switch ($Facts.reason) {
        "missing-lock" { "missing_lock" }
        "invalid-hub-dir" { "invalid_hub_dir" }
        "hub-not-git" { "hub_not_git" }
        default { if ($Facts.status -eq "in-sync") { "in_sync" } else { "drift" } }
    }
    Write-Output ("Status: {0}" -f $textStatus)
    foreach ($difference in $Facts.differences) { Write-Output ("- {0}" -f $difference) }
    Write-Output ""
}

$facts = @($ProjectDir | ForEach-Object {
        try { Get-HubLockFacts -Project $_ -HubOverride $HubDir -RuntimeRoot $RuntimeDir }
        catch { Set-HubLockOutcome (New-HubLockFacts -Project $_) "unknown" "internal-error" @("internal-error") }
    })

if ($Json.IsPresent) {
    $results = @($facts | ForEach-Object {
        [ordered]@{ status = $_.status; reason = $_.reason; project_language = $_.project_language; reason_codes = @($_.reason_codes) }
    })
    [ordered]@{ schema_version = 1; results = $results } | ConvertTo-Json -Depth 6
    $global:LASTEXITCODE = 0
    return
}

foreach ($item in $facts) { Write-HubLockText -Facts $item }
if (@($facts | Where-Object { $_.status -ne "in-sync" }).Count -gt 0) { exit 1 }
