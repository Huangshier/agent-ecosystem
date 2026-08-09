# Focused C3.3 Slice F verifier for project migration and rollback.
#
# The fixture is intentionally created below the host temporary directory.  No
# repository or installed runtime files are ever used as mutation targets.  A
# migration implementation may evolve its JSON field names; assertions below
# therefore prefer the observable status, tree, and canonical target semantics
# over incidental diagnostic text.

[CmdletBinding()]
param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion -lt [version]"7.6") {
    throw "C3.3 Slice F migration checks require PowerShell 7.6 or newer."
}

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$migrationScript = Join-Path $repositoryRoot "scripts/migrate-project.ps1"
$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source

$cases = New-Object 'System.Collections.Generic.List[object]'

function Add-Case {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    [void]$cases.Add([ordered]@{
            name = $Name
            status = if ($Passed) { "PASS" } else { "FAIL" }
            detail = $Detail
        })
}

function Assert-Migration {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-TreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath $Root -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)) {
            $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
            if ($relative -match '(?i)^\.agents/\.migration-backups(?:/|$)') { continue }
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            [void]$lines.Add(("{0}|{1}|{2}" -f $relative, $file.Length, $hash))
        }
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($lines.ToArray() -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-FileSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $snapshot = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $snapshot
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
        if ($relative -match '(?i)^\.agents/\.migration-backups(?:/|$)') { continue }
        $snapshot[$relative] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
    }
    return $snapshot
}

function Test-SnapshotEqual {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Before,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$After
    )

    $beforeKeys = @($Before.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $afterKeys = @($After.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    if ((@($beforeKeys) -join "`n") -cne (@($afterKeys) -join "`n")) {
        return $false
    }
    foreach ($key in $beforeKeys) {
        if ([string]$Before[$key] -cne [string]$After[$key]) {
            return $false
        }
    }
    return $true
}

function Get-PropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    if ($null -eq $Object) { return $null }
    foreach ($name in @($Names)) {
        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($name)) { return ,$Object[$name] }
        }
        else {
            $property = $Object.PSObject.Properties[$name]
            if ($null -ne $property) { return ,$property.Value }
        }
    }
    return $null
}

function Get-JsonCandidates {
    param([Parameter(Mandatory = $true)][string[]]$Lines)

    $candidates = New-Object 'System.Collections.Generic.List[object]'
    $text = @($Lines) -join "`n"
    try {
        $parsed = $text | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        if ($null -ne $parsed) { [void]$candidates.Add($parsed) }
    }
    catch {
        return @()
    }
    return @($candidates.ToArray())
}

function Invoke-Migration {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$AnalyzeEvidence = "",
        [string]$BackupId = "",
        [string]$ScriptPath = $migrationScript,
        [switch]$ConfirmMigration,
        [switch]$ConfirmRollback
    )

    $arguments = @("-Mode", $Mode, "-ProjectRoot", $ProjectRoot, "-Json")
    if (-not [string]::IsNullOrWhiteSpace($AnalyzeEvidence)) {
        $arguments += @("-AnalyzeEvidence", $AnalyzeEvidence)
    }
    if (-not [string]::IsNullOrWhiteSpace($BackupId)) {
        $arguments += @("-BackupId", $BackupId)
    }
    if ($ConfirmMigration.IsPresent) { $arguments += "-ConfirmMigration" }
    if ($ConfirmRollback.IsPresent) { $arguments += "-ConfirmRollback" }

    $global:LASTEXITCODE = 0
    $output = @(& $pwshPath -NoProfile -NonInteractive -File $ScriptPath @arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $payload = $null
    foreach ($candidate in @(Get-JsonCandidates -Lines $output)) {
        $payload = $candidate
    }
    return [ordered]@{
        mode = $Mode
        exit_code = $exitCode
        output = @($output)
        payload = $payload
        text = @($output) -join "`n"
    }
}

function Get-StatusText {
    param([AllowNull()][object]$Payload)

    return [string](Get-PropertyValue -Object $Payload -Names @("status", "result", "outcome", "state"))
}

function Test-InvocationPass {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Invocation)

    if ([int]$Invocation.exit_code -ne 0 -or $null -eq $Invocation.payload) { return $false }
    $status = (Get-StatusText -Payload $Invocation.payload).ToLowerInvariant()
    return ($status -notin @("fail", "failed", "error", "rejected", "blocked", "conflict"))
}

function Test-InvocationBlocked {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Invocation)

    if ($null -eq $Invocation.payload) {
        return ([int]$Invocation.exit_code -ne 0)
    }
    $status = (Get-StatusText -Payload $Invocation.payload).ToLowerInvariant()
    return ([int]$Invocation.exit_code -ne 0 -or $status -in @("fail", "failed", "error", "rejected", "blocked", "conflict"))
}

function Get-CanonicalJson {
    param([AllowNull()][object]$Payload)

    if ($null -eq $Payload) { return "" }
    return ($Payload | ConvertTo-Json -Depth 100 -Compress)
}

function Get-StringLeaves {
    param([AllowNull()][object]$Object)

    $values = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $Object) { return @() }
    if ($Object -is [string]) {
        [void]$values.Add([string]$Object)
        return @($values.ToArray())
    }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in @($Object.Keys | Sort-Object { [string]$_ })) {
            [void]$values.Add([string]$key)
            foreach ($value in @(Get-StringLeaves -Object $Object[$key])) { [void]$values.Add($value) }
        }
        return @($values.ToArray())
    }
    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string]) {
        foreach ($value in $Object) {
            foreach ($leaf in @(Get-StringLeaves -Object $value)) { [void]$values.Add($leaf) }
        }
        return @($values.ToArray())
    }
    foreach ($property in @($Object.PSObject.Properties)) {
        [void]$values.Add([string]$property.Name)
        foreach ($value in @(Get-StringLeaves -Object $property.Value)) { [void]$values.Add($value) }
    }
    return @($values.ToArray())
}

function Get-FirstNamedLeaf {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in @($Object.Keys)) {
            if ($Names -contains ([string]$key)) {
                $value = $Object[$key]
                if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) { return [string]$value }
                if ($value -is [bool] -or $value -is [ValueType]) { return $value }
                $nested = Get-FirstNamedLeaf -Object $value -Names $Names
                if ($null -ne $nested) { return $nested }
            }
            $nested = Get-FirstNamedLeaf -Object $Object[$key] -Names $Names
            if ($null -ne $nested) { return $nested }
        }
        return $null
    }
    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string]) {
        foreach ($value in $Object) {
            $nested = Get-FirstNamedLeaf -Object $value -Names $Names
            if ($null -ne $nested) { return $nested }
        }
        return $null
    }
    foreach ($property in @($Object.PSObject.Properties)) {
        if ($Names -contains ([string]$property.Name)) {
            if ($property.Value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) { return [string]$property.Value }
            if ($property.Value -is [bool] -or $property.Value -is [ValueType]) { return $property.Value }
            $nested = Get-FirstNamedLeaf -Object $property.Value -Names $Names
            if ($null -ne $nested) { return $nested }
        }
        $nested = Get-FirstNamedLeaf -Object $property.Value -Names $Names
        if ($null -ne $nested) { return $nested }
    }
    return $null
}

function Get-BackupFiles {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force |
            Where-Object {
                $relative = [IO.Path]::GetRelativePath($ProjectRoot, $_.FullName).Replace('\', '/')
                $relative -match '(?i)(^|/)\.migration-backups(/|$)' -or
                $_.Name -match '(?i)(backup|migration|apply-record|manifest).*(json|sha256|manifest)$|(^|[-_.])backup([-_.]|$)'
            } |
            Sort-Object FullName
    )
}

function Get-BackupIdFromResult {
    param([AllowNull()][object]$Payload)

    $value = Get-FirstNamedLeaf -Object $Payload -Names @("backup_id", "backupId", "id")
    if ($null -eq $value) { return "" }
    return [string]$value
}

function Get-BackupPathFromResult {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [AllowNull()][object]$Payload
    )

    $value = Get-FirstNamedLeaf -Object $Payload -Names @("backup_manifest", "backup_path", "backup_dir", "backup_root", "manifest_path")
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        $candidate = [string]$value
        if ([IO.Path]::IsPathRooted($candidate) -and (Test-Path -LiteralPath $candidate)) { return $candidate }
        $relative = $candidate.Replace('/', [IO.Path]::DirectorySeparatorChar).Replace('\', [IO.Path]::DirectorySeparatorChar)
        $path = Join-Path $ProjectRoot $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
        if (Test-Path -LiteralPath $path -PathType Container) {
            $manifestInDirectory = Join-Path $path "manifest.json"
            if (Test-Path -LiteralPath $manifestInDirectory -PathType Leaf) { return $manifestInDirectory }
        }
    }
    $backupId = Get-BackupIdFromResult -Payload $Payload
    if (-not [string]::IsNullOrWhiteSpace($backupId)) {
        $candidate = Join-Path $ProjectRoot (Join-Path ".agents/.migration-backups" $backupId)
        $manifest = Join-Path $candidate "manifest.json"
        if (Test-Path -LiteralPath $manifest -PathType Leaf) { return $manifest }
    }
    $files = @(Get-BackupFiles -ProjectRoot $ProjectRoot)
    if ($files.Count -gt 0) { return $files[0].FullName }
    return ""
}

function Test-BackupBeforeApply {
    param(
        [AllowNull()][object]$Payload,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    $explicit = Get-FirstNamedLeaf -Object $Payload -Names @("backup_before_apply", "backup_before_mutation", "backup_completed_before_apply")
    if ($null -ne $explicit -and [string]$explicit -match '(?i)^(true|yes|pass|ok)$') { return $true }
    # The public result names the retained backup and its post-state digest.
    # Verify the durable manifest pair and apply record rather than relying on
    # filesystem mtimes (which are coarse and can be rewritten by a copy).
    $backupId = Get-BackupIdFromResult -Payload $Payload
    $backupRoot = ""
    if (-not [string]::IsNullOrWhiteSpace($backupId)) {
        $backupRoot = Join-Path $ProjectRoot (Join-Path ".agents/.migration-backups" $backupId)
    }
    if (Test-Path -LiteralPath $backupRoot -PathType Container) {
        $manifestPath = Join-Path $backupRoot "manifest.json"
        $manifestHashPath = Join-Path $backupRoot "manifest.sha256"
        $recordPath = Join-Path $backupRoot "apply-record.json"
        if ((Test-Path -LiteralPath $manifestPath -PathType Leaf) -and
            (Test-Path -LiteralPath $manifestHashPath -PathType Leaf) -and
            (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
            try {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 100
                $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json -Depth 100
                $recordKind = [string](Get-PropertyValue -Object $record -Names @("record_kind"))
                $backupKind = [string](Get-PropertyValue -Object $manifest -Names @("backup_kind"))
                $recordDigest = [string](Get-PropertyValue -Object $record -Names @("expected_post_state_digest"))
                $resultDigest = [string](Get-PropertyValue -Object $Payload -Names @("expected_post_state_digest"))
                $preState = Get-PropertyValue -Object $manifest -Names @("pre_state")
                $postState = Get-PropertyValue -Object $record -Names @("expected_post_state")
                if ($backupKind -ceq "c3.3-project-migration" -and $recordKind -ceq "c3.3-project-migration-apply" -and
                    $null -ne $preState -and $null -ne $postState -and
                    -not [string]::IsNullOrWhiteSpace($recordDigest) -and $recordDigest -ceq $resultDigest) {
                    return $true
                }
            }
            catch {
                return $false
            }
        }
    }
    $leaves = @(Get-StringLeaves -Object $Payload)
    $backupIndex = -1
    $applyIndex = -1
    for ($index = 0; $index -lt $leaves.Count; $index++) {
        if ($backupIndex -lt 0 -and [string]$leaves[$index] -match '(?i)backup.{0,24}(complete|create|write|before|manifest)') { $backupIndex = $index }
        if ($applyIndex -lt 0 -and [string]$leaves[$index] -match '(?i)(apply|mutation|target).{0,24}(start|write|complete|manifest)') { $applyIndex = $index }
    }
    if ($backupIndex -ge 0 -and $applyIndex -ge 0) { return ($backupIndex -lt $applyIndex) }
    foreach ($file in @(Get-BackupFiles -ProjectRoot $ProjectRoot)) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if ([string]$text -match '(?i)backup' -and [string]$text -match '(?i)(apply|mutation)') {
            if ([string]$text -match '(?is)backup.{0,200}(apply|mutation)') { return $true }
            if ([string]$text -match '(?is)(apply|mutation).{0,200}backup') { return $false }
        }
    }
    return $false
}

function New-LegacyFixture {
    param([Parameter(Mandatory = $true)][string]$Root)

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Utf8NoBom -Path (Join-Path $Root "AGENTS.md") -Text @"
# Project Agent Entrypoint

Read `.agents/AGENTS.md`, `.agents/process.txt`, `.agents/plan.md`, and the
relevant command card before non-trivial work.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/AGENTS.md") -Text @"
# Project Agent Guide

## Project Language Policy

Project memory language: English.

## Working Rules

- Preserve project-owned memory.
- Keep commands, paths, APIs, filenames, and raw errors unchanged.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/process.txt") -Text @"
Current State
- Status: active
- Objective: finish the bounded migration of this project memory.

Completed
- Public-safe source inventory verified.

Next Actions
- Review the migration result and run the workspace verifier.

Blocking Issues
- None.

Last Updated
- 2026-08-01
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/plan.md") -Text @"
# Active Plan

Project memory language: English.

Active Spec
- `docs/specs/legacy-spec/spec.md`

Current Task
- Complete the project memory migration.
- Status: active

This Session
- [ ] Review the extracted Work, Context, Procedure, and Spec.
- [ ] Run the migration validation command.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/notes.md") -Text @"
# Verified Notes

## Verified

- The project memory source is public-safe.
- The migration boundary is project-local.
- The source language is English and must remain English.

## Stable Facts

- Runtime files are outside the project-local workspace.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/context/verified-context.md") -Text @"
# Verified Context

## Summary

A stable, public-safe project memory fact.

## Keywords

migration, workspace, continuity

## Verified Facts

The bounded fixture inventory was reviewed.

This fact is stable and suitable for a canonical Context asset.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/commands/migrate-project.md") -Text @"
# Migrate Project Memory

Kind: workflow
Summary: Review and apply the bounded project-memory migration.

## Purpose

Review and apply the bounded project-memory migration.

## Preconditions

- The project root is known.
- Analyze evidence is current.

## Steps

1. Run Analyze and inspect the deterministic evidence.
2. Confirm the migration and run Apply.
3. Validate the four canonical assets and retain the backup.

## Validation

- Analyze is read-only and repeatable.
- Apply writes only canonical Work, Context, Procedure, and Spec assets.
- Rollback restores the exact pre-apply tree.

## Stop Boundaries

- Stop when evidence is missing, stale, ambiguous, or unsupported.
- Stop before touching project-local Skill or metadata changes.

## Authorization

- Apply and Rollback require explicit confirmation.
"@
    # A deterministic legacy-form Spec under docs/specs is normalized in place;
    # it is not duplicated and remains the one canonical Spec authority.
    Write-Utf8NoBom -Path (Join-Path $Root "docs/specs/legacy-spec/spec.md") -Text @"
---
id: legacy-spec
title: Legacy Project Memory Specification
---

## Scope

Move this bounded project-memory record into the C3.3 canonical workspace.

## Goals

- Preserve the project language and public-safe literals.
- Produce one Work, Context, Procedure, and Spec asset.

## Non-Goals

- Do not alter runtime files or add a compatibility mirror.
- Do not overwrite project-owned files.

## Acceptance

- The canonical workspace is complete.
- Rollback restores the exact original tree.

## Design

Use one evidence-gated migration with a retained backup and fail-closed rollback.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/hub.lock.json") -Text (@{
            schema_version = 1
            project_language = "en"
            workspace_model = "legacy"
            workspace_state = "not-enabled"
        } | ConvertTo-Json -Depth 10)
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/skills/local-project/SKILL.md") -Text @"
---
name: local-project
description: A project-local Skill that remains outside migration authority.
---

Keep this local Skill unchanged.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/project-metadata.json") -Text (@{
            owner = "project-local"
            marker = "metadata-sentinel"
        } | ConvertTo-Json -Depth 10)
    Write-Utf8NoBom -Path (Join-Path $Root "project-owned.txt") -Text "Project-owned sentinel; migration must not overwrite it.`n"
}

function Copy-Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        [IO.Directory]::Delete($Destination, $true)
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Get-CanonicalTargetFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    $records = New-Object 'System.Collections.Generic.List[object]'
    foreach ($relativeRoot in @(".agents/work", ".agents/context", ".agents/procedures", "docs/specs")) {
        $path = Join-Path $Root $relativeRoot
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $path -Recurse -File -Force | Sort-Object FullName)) {
            [void]$records.Add([IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/'))
        }
    }
    return @($records.ToArray())
}

function Test-CanonicalTargetShape {
    param([Parameter(Mandatory = $true)][string]$Root)

    $files = @(Get-CanonicalTargetFiles -Root $Root)
    $work = @($files | Where-Object { $_ -match '^\.agents/work/[^/]+\.md$' })
    $context = @($files | Where-Object { $_ -match '^\.agents/context/[^/]+\.md$' })
    $procedure = @($files | Where-Object { $_ -match '^\.agents/procedures/[^/]+\.md$' })
    $spec = @($files | Where-Object { $_ -match '^docs/specs/[^/]+/spec\.md$' })
    # notes.md and each legacy .agents/context card are Context inputs; this
    # fixture intentionally has two Context outputs while retaining one asset
    # in every canonical category.
    return ($work.Count -eq 1 -and $context.Count -ge 2 -and $procedure.Count -eq 1 -and $spec.Count -eq 1)
}

function Set-TargetMutation {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Kind
    )

    switch ($Kind) {
        "work" {
            $path = @(Get-CanonicalTargetFiles -Root $Root | Where-Object { $_ -match '^\.agents/work/' })[0]
        }
        "context" {
            $path = @(Get-CanonicalTargetFiles -Root $Root | Where-Object { $_ -match '^\.agents/context/' })[0]
        }
        "procedure" {
            $path = @(Get-CanonicalTargetFiles -Root $Root | Where-Object { $_ -match '^\.agents/procedures/' })[0]
        }
        "spec" {
            $path = @(Get-CanonicalTargetFiles -Root $Root | Where-Object { $_ -match '^docs/specs/' })[0]
        }
        default { throw "Unknown migration target mutation kind: $Kind" }
    }
    Assert-Migration -Condition (-not [string]::IsNullOrWhiteSpace([string]$path)) -Message "Migration did not create the expected $Kind target before mutation."
    Add-Content -LiteralPath (Join-Path $Root $path) -Value "`nTarget mutation sentinel.`n"
}

$scratchRoot = Join-Path ([IO.Path]::GetTempPath()) ("agent-ecosystem-c33-slice-f-{0}" -f ([Guid]::NewGuid().ToString("N")))
$baseRoot = Join-Path $scratchRoot "base-project"
$pristineRoot = Join-Path $scratchRoot "pristine-project"
$runtimeRoot = Join-Path $scratchRoot "runtime"
$isolatedRuntimeRoot = Join-Path $scratchRoot "isolated-runtime"
$isolatedMigrationScript = Join-Path $isolatedRuntimeRoot "scripts/migrate-project.ps1"
$evidence = [ordered]@{
    analyze_deterministic = $false
    analyze_read_only = $false
    analyze_fail_closed = $false
    apply_gates = $false
    fresh_apply = $false
    backup_order = $false
    canonical_targets = $false
    language_preserved = $false
    rollback_exact = $false
    runtime_sentinel = $false
    backup_retained = $false
    rollback_analyze = $false
    mutation_rejection = $false
    rollback_integrity = $false
    interrupted_apply_rollback = $false
    interrupted_apply_conflict = $false
}

try {
    New-Item -ItemType Directory -Force -Path $scratchRoot, $runtimeRoot | Out-Null
    New-LegacyFixture -Root $baseRoot
    Copy-Fixture -Source $baseRoot -Destination $pristineRoot
    Write-Utf8NoBom -Path (Join-Path $runtimeRoot "runtime-sentinel.txt") -Text "Runtime sentinel must remain untouched.`n"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $isolatedMigrationScript) | Out-Null
    Copy-Item -LiteralPath $migrationScript -Destination $isolatedMigrationScript -Force
    $runtimeBefore = Get-FileSnapshot -Root $runtimeRoot

    if (-not (Test-Path -LiteralPath $migrationScript -PathType Leaf)) {
        throw "Migration provider is missing: scripts/migrate-project.ps1"
    }

    # Analyze is strictly read-only and repeatable.  Full payload equality also
    # catches random IDs/timestamps that would make Apply evidence unsafe.
    $beforeAnalyzeSnapshot = Get-FileSnapshot -Root $baseRoot
    $beforeAnalyzeTree = Get-TreeFingerprint -Root $baseRoot
    $analyzeOne = Invoke-Migration -Mode "Analyze" -ProjectRoot $baseRoot
    $analyzeTwo = Invoke-Migration -Mode "Analyze" -ProjectRoot $baseRoot
    $afterAnalyzeSnapshot = Get-FileSnapshot -Root $baseRoot
    $afterAnalyzeTree = Get-TreeFingerprint -Root $baseRoot
    $deterministic = ((Test-InvocationPass -Invocation $analyzeOne) -and (Test-InvocationPass -Invocation $analyzeTwo) -and
        (Get-CanonicalJson -Payload $analyzeOne.payload) -ceq (Get-CanonicalJson -Payload $analyzeTwo.payload))
    $readOnly = ($beforeAnalyzeTree -ceq $afterAnalyzeTree -and (Test-SnapshotEqual -Before $beforeAnalyzeSnapshot -After $afterAnalyzeSnapshot) -and
        @((Get-BackupFiles -ProjectRoot $baseRoot)).Count -eq 0)
    Add-Case -Name "analyze-deterministic-read-only" -Passed ($deterministic -and $readOnly) -Detail ("Analyze repeatable={0} read_only={1} first_exit={2} second_exit={3} first_status={4} second_status={5}." -f $deterministic, $readOnly, $analyzeOne.exit_code, $analyzeTwo.exit_code, (Get-StatusText $analyzeOne.payload), (Get-StatusText $analyzeTwo.payload))
    $evidence.analyze_deterministic = $deterministic
    $evidence.analyze_read_only = $readOnly

    # Ambiguous and unsupported sources are refused before any target write.
    $ambiguousRoot = Join-Path $scratchRoot "ambiguous-project"
    Copy-Fixture -Source $baseRoot -Destination $ambiguousRoot
    # A markerless candidate requires human disposition; the implementation
    # must not guess how to classify it as canonical Context.
    Write-Utf8NoBom -Path (Join-Path $ambiguousRoot ".agents/context/ambiguous.md") -Text "# Ambiguous legacy context`n`nNo deterministic Summary or Keywords markers.`n"
    $ambiguousBefore = Get-TreeFingerprint -Root $ambiguousRoot
    $ambiguous = Invoke-Migration -Mode "Analyze" -ProjectRoot $ambiguousRoot
    $ambiguousClosed = ((Test-InvocationBlocked -Invocation $ambiguous) -and $ambiguousBefore -ceq (Get-TreeFingerprint -Root $ambiguousRoot) -and @((Get-BackupFiles -ProjectRoot $ambiguousRoot)).Count -eq 0)
    Add-Case -Name "ambiguous-input-fails-closed" -Passed $ambiguousClosed -Detail "Ambiguous legacy extraction is rejected without creating a backup or target asset."

    $unsupportedRoot = Join-Path $scratchRoot "unsupported-project"
    Copy-Fixture -Source $baseRoot -Destination $unsupportedRoot
    Write-Utf8NoBom -Path (Join-Path $unsupportedRoot "docs/specs/unsupported_name/spec.md") -Text @"
# Unsupported specification path

## Scope
An unsupported legacy specification path.

## Non-Goals
Do not migrate this unsupported path.

## Acceptance
The analyzer must fail closed.

## Design
No compatibility mirror.
"@
    $unsupportedBefore = Get-TreeFingerprint -Root $unsupportedRoot
    $unsupported = Invoke-Migration -Mode "Analyze" -ProjectRoot $unsupportedRoot
    $unsupportedClosed = ((Test-InvocationBlocked -Invocation $unsupported) -and $unsupportedBefore -ceq (Get-TreeFingerprint -Root $unsupportedRoot) -and @((Get-BackupFiles -ProjectRoot $unsupportedRoot)).Count -eq 0)
    Add-Case -Name "unsupported-input-fails-closed" -Passed $unsupportedClosed -Detail "Unsupported legacy input is rejected without creating a backup or target asset."
    $evidence.analyze_fail_closed = ($ambiguousClosed -and $unsupportedClosed)

    # Apply requires both the reviewed Analyze JSON and explicit confirmation.
    $missingEvidenceBefore = Get-TreeFingerprint -Root $baseRoot
    $missingEvidence = Invoke-Migration -Mode "Apply" -ProjectRoot $baseRoot -ConfirmMigration
    $missingEvidenceClosed = ((Test-InvocationBlocked -Invocation $missingEvidence) -and $missingEvidenceBefore -ceq (Get-TreeFingerprint -Root $baseRoot) -and @((Get-BackupFiles -ProjectRoot $baseRoot)).Count -eq 0)
    $missingConfirmationBefore = Get-TreeFingerprint -Root $baseRoot
    $missingConfirmation = Invoke-Migration -Mode "Apply" -ProjectRoot $baseRoot -AnalyzeEvidence ([string](Get-CanonicalJson -Payload $analyzeOne.payload))
    $missingConfirmationClosed = ((Test-InvocationBlocked -Invocation $missingConfirmation) -and $missingConfirmationBefore -ceq (Get-TreeFingerprint -Root $baseRoot) -and @((Get-BackupFiles -ProjectRoot $baseRoot)).Count -eq 0)
    Add-Case -Name "apply-requires-evidence-and-confirmation" -Passed ($missingEvidenceClosed -and $missingConfirmationClosed) -Detail "Apply rejects missing Analyze evidence and missing explicit confirmation without writes."
    $evidence.apply_gates = ($missingEvidenceClosed -and $missingConfirmationClosed)

    # A valid fresh Apply creates one asset in each canonical root.
    $beforeApplySnapshot = Get-FileSnapshot -Root $baseRoot
    $beforeApplyTree = Get-TreeFingerprint -Root $baseRoot
    $analysisEvidenceJson = Get-CanonicalJson -Payload $analyzeOne.payload
    $applied = Invoke-Migration -Mode "Apply" -ProjectRoot $baseRoot -AnalyzeEvidence $analysisEvidenceJson -ConfirmMigration
    $afterApplySnapshot = Get-FileSnapshot -Root $baseRoot
    $afterApplyTree = Get-TreeFingerprint -Root $baseRoot
    $freshApply = Test-InvocationPass -Invocation $applied
    $targetShape = Test-CanonicalTargetShape -Root $baseRoot
    $targetFiles = @(Get-CanonicalTargetFiles -Root $baseRoot)
    $allowedTargetFiles = @($targetFiles | Where-Object { $_ -match '^\.agents/(work|context|procedures)/[^/]+\.md$' -or $_ -match '^docs/specs/[^/]+/spec\.md$' })
    $onlyCanonicalTargets = ($targetFiles.Count -eq 5 -and $allowedTargetFiles.Count -eq $targetFiles.Count)
    $projectOwnedPreserved = ([string]$beforeApplySnapshot["project-owned.txt"] -ceq [string]$afterApplySnapshot["project-owned.txt"] -and
        [string]$beforeApplySnapshot[".agents/skills/local-project/SKILL.md"] -ceq [string]$afterApplySnapshot[".agents/skills/local-project/SKILL.md"] -and
        [string]$beforeApplySnapshot[".agents/project-metadata.json"] -ceq [string]$afterApplySnapshot[".agents/project-metadata.json"])
    $retiredSources = @(
        ".agents/process.txt", ".agents/plan.md", ".agents/notes.md",
        ".agents/context/verified-context.md", ".agents/commands/migrate-project.md"
    )
    $sourceRetired = (@($retiredSources | Where-Object { Test-Path -LiteralPath (Join-Path $baseRoot $_) -PathType Leaf }).Count -eq 0)
    $freshApply = ($freshApply -and $targetShape -and $onlyCanonicalTargets -and $projectOwnedPreserved -and $sourceRetired -and $beforeApplyTree -cne $afterApplyTree)
    Add-Case -Name "fresh-apply-canonical-assets" -Passed $freshApply -Detail ("Fresh Apply exit={0} status={1} reasons={2} targets={3} shape={4} allowed={5} preserved={6} retired={7}." -f $applied.exit_code, (Get-StatusText $applied.payload), (@($applied.payload.reason_codes) -join ','), ($targetFiles -join ','), $targetShape, $onlyCanonicalTargets, $projectOwnedPreserved, $sourceRetired)
    $evidence.fresh_apply = $freshApply
    $evidence.canonical_targets = ($targetShape -and $onlyCanonicalTargets -and $projectOwnedPreserved)

    $lockPath = Join-Path $baseRoot ".agents/hub.lock.json"
    $lockAfterApply = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -Depth 30
    $languagePreserved = ([string]$lockAfterApply.project_language -ceq "en")
    $evidence.language_preserved = $languagePreserved
    Add-Case -Name "language-preserved" -Passed $languagePreserved -Detail "Apply keeps the legacy project memory language unchanged."

    $backupId = Get-BackupIdFromResult -Payload $applied.payload
    $backupPath = Get-BackupPathFromResult -ProjectRoot $baseRoot -Payload $applied.payload
    $backupOrder = (Test-BackupBeforeApply -Payload $applied.payload -ProjectRoot $baseRoot)
    $backupFilesAfterApply = @(Get-BackupFiles -ProjectRoot $baseRoot)
    $backupExists = ($backupFilesAfterApply.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($backupPath))
    $backupOrder = ($freshApply -and $backupExists -and $backupOrder)
    Add-Case -Name "backup-before-target-mutation" -Passed $backupOrder -Detail "Apply evidence proves the backup manifest is written before target mutation without using file timestamps."
    $evidence.backup_order = $backupOrder

    # Rollback must restore bytes and tree shape exactly, preserve its backup,
    # and never touch a runtime directory outside ProjectRoot.
    $rollbackBefore = Get-TreeFingerprint -Root $baseRoot
    $rollback = Invoke-Migration -Mode "Rollback" -ProjectRoot $baseRoot -BackupId $backupId -ConfirmRollback
    $rollbackAfter = Get-TreeFingerprint -Root $baseRoot
    $runtimeAfter = Get-FileSnapshot -Root $runtimeRoot
    $rollbackExact = ((Test-InvocationPass -Invocation $rollback) -and $rollbackBefore -cne $rollbackAfter -and
        $rollbackAfter -ceq $beforeApplyTree -and (Test-SnapshotEqual -Before $beforeApplySnapshot -After (Get-FileSnapshot -Root $baseRoot)))
    $runtimeStable = (Test-SnapshotEqual -Before $runtimeBefore -After $runtimeAfter)
    $backupRetained = (@(Get-BackupFiles -ProjectRoot $baseRoot).Count -gt 0)
    Add-Case -Name "rollback-exact-restore" -Passed ($rollbackExact -and $runtimeStable -and $backupRetained) -Detail ("Rollback exit={0} status={1} reasons={2} exact={3} runtime={4} backup_retained={5} backup_id={6}." -f $rollback.exit_code, (Get-StatusText $rollback.payload), (@($rollback.payload.reason_codes) -join ','), $rollbackExact, $runtimeStable, $backupRetained, $backupId)
    $evidence.rollback_exact = $rollbackExact
    $evidence.runtime_sentinel = $runtimeStable
    $evidence.backup_retained = $backupRetained

    $postRollbackAnalyzeBefore = Get-TreeFingerprint -Root $baseRoot
    $postRollbackAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $baseRoot
    $postRollbackAnalyzeAfter = Get-TreeFingerprint -Root $baseRoot
    $rollbackAnalyze = ((Test-InvocationPass -Invocation $postRollbackAnalyze) -and $postRollbackAnalyzeBefore -ceq $postRollbackAnalyzeAfter)
    Add-Case -Name "rollback-followed-by-analyze" -Passed $rollbackAnalyze -Detail "A restored project remains analyzable and Analyze remains read-only after Rollback."
    $evidence.rollback_analyze = $rollbackAnalyze

    # An isolated Runtime copy intentionally omits project-workspace so Apply
    # fails only after executing its declared target mutations.  Rollback
    # evidence must already be complete and integrity-protected at that point.
    $interruptedRoot = Join-Path $scratchRoot "interrupted-apply"
    Copy-Fixture -Source $pristineRoot -Destination $interruptedRoot
    $interruptedBeforeSnapshot = Get-FileSnapshot -Root $interruptedRoot
    $interruptedBeforeTree = Get-TreeFingerprint -Root $interruptedRoot
    $interruptedAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $interruptedRoot -ScriptPath $isolatedMigrationScript
    Assert-Migration -Condition (Test-InvocationPass -Invocation $interruptedAnalyze) -Message "Interrupted-Apply fixture Analyze failed."
    $interruptedBackupId = [string]$interruptedAnalyze.payload.backup_requirements.backup_id
    $interruptedApply = Invoke-Migration -Mode "Apply" -ProjectRoot $interruptedRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $interruptedAnalyze.payload) -ConfirmMigration -ScriptPath $isolatedMigrationScript
    $interruptedBackupRoot = Join-Path $interruptedRoot (Join-Path ".agents/.migration-backups" $interruptedBackupId)
    $manifestPath = Join-Path $interruptedBackupRoot "manifest.json"
    $manifestHashPath = Join-Path $interruptedBackupRoot "manifest.sha256"
    $recordPath = Join-Path $interruptedBackupRoot "apply-record.json"
    $recordHashPath = Join-Path $interruptedBackupRoot "apply-record.sha256"
    $rollbackEvidenceFiles = @($manifestPath, $manifestHashPath, $recordPath, $recordHashPath)
    $rollbackEvidenceComplete = (@($rollbackEvidenceFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -eq 4)
    if ($rollbackEvidenceComplete) {
        $manifestText = Get-Content -LiteralPath $manifestPath -Raw
        $recordText = Get-Content -LiteralPath $recordPath -Raw
        $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $recordHash = (Get-FileHash -LiteralPath $recordPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest = $manifestText | ConvertFrom-Json -Depth 100
        $record = $recordText | ConvertFrom-Json -Depth 100
        $rollbackEvidenceComplete = (
            $manifestHash -ceq (Get-Content -LiteralPath $manifestHashPath -Raw).Trim() -and
            $recordHash -ceq (Get-Content -LiteralPath $recordHashPath -Raw).Trim() -and
            @($manifest.pre_state).Count -gt 0 -and @($record.expected_post_state).Count -gt 0 -and
            @($record.managed_paths).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$record.expected_post_state_digest)
        )
    }
    $failedAfterMutation = ((Test-InvocationBlocked -Invocation $interruptedApply) -and $interruptedApply.text -match 'WORKSPACE_CHECK_UNAVAILABLE' -and $interruptedBeforeTree -cne (Get-TreeFingerprint -Root $interruptedRoot))
    $interruptedRollback = Invoke-Migration -Mode "Rollback" -ProjectRoot $interruptedRoot -BackupId $interruptedBackupId -ConfirmRollback -ScriptPath $isolatedMigrationScript
    $interruptedExact = ((Test-InvocationPass -Invocation $interruptedRollback) -and (Test-SnapshotEqual -Before $interruptedBeforeSnapshot -After (Get-FileSnapshot -Root $interruptedRoot)))
    $interruptedBackupRetained = (Test-Path -LiteralPath $interruptedBackupRoot -PathType Container)
    $interruptedPass = ($failedAfterMutation -and $rollbackEvidenceComplete -and $interruptedExact -and $interruptedBackupRetained)
    Add-Case -Name "interrupted-apply-rollback-exact" -Passed $interruptedPass -Detail ("Post-mutation Apply failure={0} evidence_complete={1} rollback_exact={2} backup_retained={3}." -f $failedAfterMutation, $rollbackEvidenceComplete, $interruptedExact, $interruptedBackupRetained)
    $evidence.interrupted_apply_rollback = $interruptedPass

    $interruptedConflictRoot = Join-Path $scratchRoot "interrupted-apply-conflict"
    Copy-Fixture -Source $pristineRoot -Destination $interruptedConflictRoot
    $conflictAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $interruptedConflictRoot -ScriptPath $isolatedMigrationScript
    Assert-Migration -Condition (Test-InvocationPass -Invocation $conflictAnalyze) -Message "Interrupted-Apply conflict fixture Analyze failed."
    $conflictBackupId = [string]$conflictAnalyze.payload.backup_requirements.backup_id
    $conflictApply = Invoke-Migration -Mode "Apply" -ProjectRoot $interruptedConflictRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $conflictAnalyze.payload) -ConfirmMigration -ScriptPath $isolatedMigrationScript
    Assert-Migration -Condition ((Test-InvocationBlocked -Invocation $conflictApply) -and $conflictApply.text -match 'WORKSPACE_CHECK_UNAVAILABLE') -Message "Interrupted-Apply conflict fixture did not fail after mutation."
    Add-Content -LiteralPath (Join-Path $interruptedConflictRoot ".agents/project-metadata.json") -Value "`nHuman post-failure edit.`n"
    $conflictBeforeRollback = Get-FileSnapshot -Root $interruptedConflictRoot
    $conflictRollback = Invoke-Migration -Mode "Rollback" -ProjectRoot $interruptedConflictRoot -BackupId $conflictBackupId -ConfirmRollback -ScriptPath $isolatedMigrationScript
    $interruptedConflictRejected = ((Test-InvocationBlocked -Invocation $conflictRollback) -and (Test-SnapshotEqual -Before $conflictBeforeRollback -After (Get-FileSnapshot -Root $interruptedConflictRoot)))
    Add-Case -Name "interrupted-apply-rejects-third-state" -Passed $interruptedConflictRejected -Detail "Rollback rejects and preserves a human edit made after post-mutation Apply failure."
    $evidence.interrupted_apply_conflict = $interruptedConflictRejected

    # Apply evidence binds all source categories.  A mutation after Analyze in
    # legacy, target, language, or workspace state must fail before writes.
    $mutationKinds = @("legacy", "target", "language", "workspace")
    $mutationPass = $true
    foreach ($kind in $mutationKinds) {
        $mutationRoot = Join-Path $scratchRoot ("apply-mutation-{0}" -f $kind)
        Copy-Fixture -Source $pristineRoot -Destination $mutationRoot
        $mutationAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $mutationRoot
        Assert-Migration -Condition (Test-InvocationPass -Invocation $mutationAnalyze) -Message ("Mutation fixture Analyze failed for {0}." -f $kind)
        switch ($kind) {
            "legacy" { Add-Content -LiteralPath (Join-Path $mutationRoot ".agents/process.txt") -Value "`nMutation after Analyze.`n" }
            "target" {
                New-Item -ItemType Directory -Force -Path (Join-Path $mutationRoot ".agents/work") | Out-Null
                Write-Utf8NoBom -Path (Join-Path $mutationRoot ".agents/work/foreign.md") -Text "foreign target mutation`n"
            }
            "language" {
                $lock = Get-Content -LiteralPath (Join-Path $mutationRoot ".agents/hub.lock.json") -Raw | ConvertFrom-Json -Depth 30
                $lock.project_language = "zh-CN"
                Write-Utf8NoBom -Path (Join-Path $mutationRoot ".agents/hub.lock.json") -Text ($lock | ConvertTo-Json -Depth 30)
            }
            "workspace" {
                $lock = Get-Content -LiteralPath (Join-Path $mutationRoot ".agents/hub.lock.json") -Raw | ConvertFrom-Json -Depth 30
                $lock.workspace_model = "c3.3"
                Write-Utf8NoBom -Path (Join-Path $mutationRoot ".agents/hub.lock.json") -Text ($lock | ConvertTo-Json -Depth 30)
            }
        }
        $beforeRejectedApply = Get-TreeFingerprint -Root $mutationRoot
        $rejectedApply = Invoke-Migration -Mode "Apply" -ProjectRoot $mutationRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $mutationAnalyze.payload) -ConfirmMigration
        $mutationRejected = ((Test-InvocationBlocked -Invocation $rejectedApply) -and $beforeRejectedApply -ceq (Get-TreeFingerprint -Root $mutationRoot) -and @((Get-BackupFiles -ProjectRoot $mutationRoot)).Count -eq 0)
        $mutationPass = $mutationPass -and $mutationRejected
        Add-Case -Name ("apply-rejects-{0}-mutation" -f $kind) -Passed $mutationRejected -Detail ("Apply rejects a {0} mutation after Analyze without creating target or backup files." -f $kind)
    }
    $evidence.mutation_rejection = $mutationPass

    # Rollback rejects every canonical target mutation, as well as project-local
    # Skill/metadata edits.  Each copy derives from the same single fixture.
    $rollbackMutationKinds = @("work", "context", "procedure", "spec", "skill", "metadata")
    $rollbackMutationPass = $true
    foreach ($kind in $rollbackMutationKinds) {
        $mutationRoot = Join-Path $scratchRoot ("rollback-mutation-{0}" -f $kind)
        Copy-Fixture -Source $pristineRoot -Destination $mutationRoot
        $mutationAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $mutationRoot
        Assert-Migration -Condition (Test-InvocationPass -Invocation $mutationAnalyze) -Message ("Rollback mutation fixture Analyze failed for {0}." -f $kind)
        $mutationApplied = Invoke-Migration -Mode "Apply" -ProjectRoot $mutationRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $mutationAnalyze.payload) -ConfirmMigration
        Assert-Migration -Condition (Test-InvocationPass -Invocation $mutationApplied) -Message ("Rollback mutation fixture Apply failed for {0}." -f $kind)
        $mutationBackupId = Get-BackupIdFromResult -Payload $mutationApplied.payload
        switch ($kind) {
            { $_ -in @("work", "context", "procedure", "spec") } { Set-TargetMutation -Root $mutationRoot -Kind $kind }
            "skill" { Add-Content -LiteralPath (Join-Path $mutationRoot ".agents/skills/local-project/SKILL.md") -Value "`nSkill mutation sentinel.`n" }
            "metadata" {
                $metadataPath = Join-Path $mutationRoot ".agents/project-metadata.json"
                $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json -Depth 30
                $metadata.marker = "metadata-mutation"
                Write-Utf8NoBom -Path $metadataPath -Text ($metadata | ConvertTo-Json -Depth 30)
            }
        }
        $beforeRejectedRollback = Get-TreeFingerprint -Root $mutationRoot
        $rejectedRollback = Invoke-Migration -Mode "Rollback" -ProjectRoot $mutationRoot -BackupId $mutationBackupId -ConfirmRollback
        $rollbackRejected = ((Test-InvocationBlocked -Invocation $rejectedRollback) -and $beforeRejectedRollback -ceq (Get-TreeFingerprint -Root $mutationRoot))
        $rollbackMutationPass = $rollbackMutationPass -and $rollbackRejected
        Add-Case -Name ("rollback-rejects-{0}-mutation" -f $kind) -Passed $rollbackRejected -Detail ("Rollback rejects a changed {0} and leaves the changed project untouched." -f $kind)
    }

    # Damage only the backup manifest and verify integrity checks fail closed.
    $integrityRoot = Join-Path $scratchRoot "rollback-backup-integrity"
    Copy-Fixture -Source $pristineRoot -Destination $integrityRoot
    $integrityAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $integrityRoot
    Assert-Migration -Condition (Test-InvocationPass -Invocation $integrityAnalyze) -Message "Backup-integrity fixture Analyze failed."
    $integrityApply = Invoke-Migration -Mode "Apply" -ProjectRoot $integrityRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $integrityAnalyze.payload) -ConfirmMigration
    Assert-Migration -Condition (Test-InvocationPass -Invocation $integrityApply) -Message "Backup-integrity fixture Apply failed."
    $integrityBackupFile = Get-BackupPathFromResult -ProjectRoot $integrityRoot -Payload $integrityApply.payload
    Assert-Migration -Condition (-not [string]::IsNullOrWhiteSpace($integrityBackupFile) -and (Test-Path -LiteralPath $integrityBackupFile -PathType Leaf)) -Message "Apply did not expose a backup manifest for integrity testing."
    Add-Content -LiteralPath $integrityBackupFile -Value "`nbackup integrity mutation`n"
    $integrityBefore = Get-TreeFingerprint -Root $integrityRoot
    $integrityRollback = Invoke-Migration -Mode "Rollback" -ProjectRoot $integrityRoot -BackupId (Get-BackupIdFromResult -Payload $integrityApply.payload) -ConfirmRollback
    $integrityRejected = ((Test-InvocationBlocked -Invocation $integrityRollback) -and $integrityBefore -ceq (Get-TreeFingerprint -Root $integrityRoot))
    Add-Case -Name "rollback-rejects-damaged-backup" -Passed $integrityRejected -Detail "Rollback validates backup integrity before restoring and fails closed when the manifest is damaged."
    $evidence.rollback_integrity = ($rollbackMutationPass -and $integrityRejected)
}
catch {
    Add-Case -Name "verifier-runtime" -Passed $false -Detail ("Focused verifier failed closed before completing its contract: {0}" -f $_.Exception.Message)
}
finally {
    if (Test-Path -LiteralPath $scratchRoot) {
        [IO.Directory]::Delete($scratchRoot, $true)
    }
}

$failures = @($cases | Where-Object { [string]$_.status -ceq "FAIL" })
$summary = [ordered]@{
    schema_version = 1
    status = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }
    verifier = "c3-3-slice-f-migration-checks"
    scenario_count = $cases.Count
    pass = @($cases | Where-Object { [string]$_.status -ceq "PASS" }).Count
    fail = $failures.Count
    evidence = $evidence
    cases = @($cases.ToArray())
}

if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 30
}
else {
    Write-Output ("C3.3 Slice F migration/rollback checks: PASS={0} FAIL={1}" -f $summary.pass, $summary.fail)
    foreach ($case in @($summary.cases)) { Write-Output ("[{0}] {1}" -f $case.status, $case.name) }
}

if ([string]$summary.status -ne "PASS") { exit 1 }
exit 0
