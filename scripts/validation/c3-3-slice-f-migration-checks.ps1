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
$legacyTemplateRoot = Join-Path $repositoryRoot "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en"
$c33TemplateRoot = Join-Path $repositoryRoot "skills/project-bootstrap/assets/c3-3-project-template/en"
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

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function New-WorkflowSpecLiteText {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Slug = $Id
    )
    return @"
# Work Spec

- **Title**: $Title
- **Slug**: $Slug
- **Status**: $Status

## 1. Summary

This public fixture exercises the official workflow-spec-lite legacy shape.

## 4. Goals

- Preserve the complete legacy Spec body.
- Map legacy lifecycle metadata deterministically.

## 5. Non-Goals

- Do not infer status from project memory.

## 9. Proposed Approach

Parse the published numbered headings and retain this body sentinel: legacy-body-preserved.

## 10. Acceptance / Evidence

- The canonical Spec has the path-derived id, metadata title, and mapped status.
"@
}

function Set-LanguageMigrationProvenance {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Actions,
        [string]$SourceLanguage = "zh-CN",
        [string]$TargetLanguage = "en"
    )
    $migrationDir = Join-Path $Root ".agents/language-migration/20260810-000000"
    $proposalPath = Join-Path $migrationDir "proposal.json"
    $resultPath = Join-Path $migrationDir "result.json"
    $proposalActions = New-Object 'System.Collections.Generic.List[object]'
    $resultActions = New-Object 'System.Collections.Generic.List[object]'
    foreach ($action in $Actions) {
        $relative = [string]$action.relative_path
        $actionName = [string]$action.action
        $manualReview = [bool]$action.manual_review
        $currentPath = Join-Path $Root $relative
        $currentText = if (Test-Path -LiteralPath $currentPath -PathType Leaf) { [IO.File]::ReadAllText($currentPath, [Text.UTF8Encoding]::new($false, $true)) } else { "" }
        $hash = Get-TextSha256 $currentText
        [void]$proposalActions.Add([ordered]@{
                relative_path = $relative
                action = $actionName
                approved = [bool]($actionName -in @("replace-template", "add-target-template") -or $manualReview)
                manual_review = $manualReview
                target_template_hash_sha256 = $hash
            })
        $resultText = if ($actionName -ceq "already-target-template") { "preserved" } elseif ($actionName -in @("replace-template", "add-target-template")) { "written-target-template" } else { "written-target-template-with-manual-review-source" }
        [void]$resultActions.Add([ordered]@{
                relative_path = $relative
                action = $actionName
                result = $resultText
                final_hash_sha256 = $hash
            })
    }
    Write-Utf8NoBom -Path $proposalPath -Text ([ordered]@{
            schema_version = 1
            project = $Root
            source_language = $SourceLanguage
            target_language = $TargetLanguage
            actions = @($proposalActions.ToArray())
        } | ConvertTo-Json -Depth 20)
    Write-Utf8NoBom -Path $resultPath -Text ([ordered]@{
            schema_version = 1
            project = $Root
            source_language = $SourceLanguage
            target_language = $TargetLanguage
            proposal = $proposalPath
            actions = @($resultActions.ToArray())
        } | ConvertTo-Json -Depth 20)
    $lockPath = Join-Path $Root ".agents/hub.lock.json"
    $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
    $lock.project_language = $TargetLanguage
    $lock.language_migration = [ordered]@{
        schema_version = 1
        source_language = $SourceLanguage
        target_language = $TargetLanguage
        proposal = $proposalPath
        result = $resultPath
    }
    Write-Utf8NoBom -Path $lockPath -Text ($lock | ConvertTo-Json -Depth 30)
    return [ordered]@{ proposal = $proposalPath; result = $resultPath }
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

function Get-DirectorySnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force |
            ForEach-Object { [IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/') } |
            Where-Object { $_ -notmatch '(?i)^\.agents/\.migration-backups(?:/|$)' } |
            Sort-Object -Unique
    )
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
    Write-Utf8NoBom -Path (Join-Path $Root "AGENTS.md") -Text ([IO.File]::ReadAllText((Join-Path $legacyTemplateRoot "project-root/AGENTS.md"), [Text.UTF8Encoding]::new($false, $true)))
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/AGENTS.md") -Text ([IO.File]::ReadAllText((Join-Path $legacyTemplateRoot "project-agent/AGENTS.md"), [Text.UTF8Encoding]::new($false, $true)))
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
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/context/README.md") -Text @"
# Legacy Context Index

This documentation is preserved byte-for-byte and is not canonical Context authority.
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
    Write-Utf8NoBom -Path (Join-Path $Root "docs/specs/legacy-spec/spec.md") -Text (New-WorkflowSpecLiteText -Id "legacy-spec" -Title "Legacy Project Memory Specification" -Status "Done")
    Write-Utf8NoBom -Path (Join-Path $Root "docs/specs/archive/retired-work/spec.md") -Text @"
# Retired Historical Specification

This archived material is preserved byte-for-byte and is not canonical Spec authority.
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
            $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
            if ($relative -cmatch '^\.agents/(?:work|context|procedures)/[a-z0-9]+(?:-[a-z0-9]+)*\.md$' -or
                $relative -cmatch '^docs/specs/[a-z0-9]+(?:-[a-z0-9]+)*/spec\.md$') {
                [void]$records.Add($relative)
            }
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
$contextReadmeRelative = ".agents/context/README.md"
$archiveSpecRelative = "docs/specs/archive/retired-work/spec.md"
$immediateSpecRelative = "docs/specs/legacy-spec/spec.md"
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
    scaffold_layout_migrated = $false
    scaffold_conflict = $false
    rollback_layout_exact = $false
    context_readme_preserved = $false
    archive_spec_preserved = $false
    immediate_spec_canonical = $false
    unsupported_nested_spec_rejected = $false
    non_authority_backup_scope = $false
}

try {
    New-Item -ItemType Directory -Force -Path $scratchRoot, $runtimeRoot | Out-Null
    New-LegacyFixture -Root $baseRoot
    Copy-Fixture -Source $baseRoot -Destination $pristineRoot
    Write-Utf8NoBom -Path (Join-Path $runtimeRoot "runtime-sentinel.txt") -Text "Runtime sentinel must remain untouched.`n"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $isolatedMigrationScript) | Out-Null
    Copy-Item -LiteralPath $migrationScript -Destination $isolatedMigrationScript -Force
    foreach ($templateRelative in @(
            "skills/project-bootstrap/assets/c3-3-project-template/en",
            "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root",
            "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent"
        )) {
        $source = Join-Path $repositoryRoot $templateRelative
        $destination = Join-Path $isolatedRuntimeRoot $templateRelative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
    }
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
    $scaffoldPlanPaths = @($analyzeOne.payload.plan.actions | ForEach-Object { [string]$_.path })
    $scaffoldPlanComplete = (
        @("AGENTS.md", ".agents/AGENTS.md", ".agents/README.md", ".agents/.gitignore") | Where-Object { $scaffoldPlanPaths -notcontains $_ }
    ).Count -eq 0 -and @($analyzeOne.payload.evidence.scaffold_contract.directories).Count -eq 5
    $readOnly = ($beforeAnalyzeTree -ceq $afterAnalyzeTree -and (Test-SnapshotEqual -Before $beforeAnalyzeSnapshot -After $afterAnalyzeSnapshot) -and
        @((Get-BackupFiles -ProjectRoot $baseRoot)).Count -eq 0)
    Add-Case -Name "analyze-deterministic-read-only" -Passed ($deterministic -and $readOnly -and $scaffoldPlanComplete) -Detail ("Analyze repeatable={0} read_only={1} scaffold_plan={2} first_exit={3} second_exit={4} first_status={5} second_status={6} reasons={7} human={8}." -f $deterministic, $readOnly, $scaffoldPlanComplete, $analyzeOne.exit_code, $analyzeTwo.exit_code, (Get-StatusText $analyzeOne.payload), (Get-StatusText $analyzeTwo.payload), (@($analyzeOne.payload.reason_codes) -join ','), (@($analyzeOne.payload.human_disposition | ForEach-Object { '{0}:{1}' -f $_.path, $_.reason_code }) -join ','))
    $evidence.analyze_deterministic = $deterministic
    $evidence.analyze_read_only = $readOnly

    $contextReadmeAnalyzePreserved = (
        @($analyzeOne.payload.human_disposition | Where-Object { [string]$_.path -ceq $contextReadmeRelative }).Count -eq 0 -and
        @($analyzeOne.payload.plan.actions | Where-Object { [string]$_.path -ceq $contextReadmeRelative }).Count -eq 0
    )
    Add-Case -Name "context-readme-preserved-non-authority" -Passed $contextReadmeAnalyzePreserved -Detail "Analyze excludes only the exact legacy Context README from canonical migration actions and human disposition."

    $archiveSpecAnalyzePreserved = (
        @($analyzeOne.payload.human_disposition | Where-Object { [string]$_.path -ceq $archiveSpecRelative }).Count -eq 0 -and
        @($analyzeOne.payload.plan.actions | Where-Object { [string]$_.path -ceq $archiveSpecRelative }).Count -eq 0
    )
    Add-Case -Name "archive-spec-preserved-non-authority" -Passed $archiveSpecAnalyzePreserved -Detail "Analyze excludes an archived nested Spec from canonical actions and SPEC_PATH_UNSUPPORTED disposition."

    $immediateSpecActions = @($analyzeOne.payload.plan.actions | Where-Object {
            [string]$_.path -ceq $immediateSpecRelative -and [string]$_.action -ceq "change" -and [string]$_.reason_code -ceq "LEGACY_SPEC_PROMOTED"
        })
    $legacySpecBody = New-WorkflowSpecLiteText -Id "legacy-spec" -Title "Legacy Project Memory Specification" -Status "Done"
    $immediateSpecCanonical = (
        $immediateSpecActions.Count -eq 1 -and
        [string]$immediateSpecActions[0].content -match '(?m)^id: legacy-spec$' -and
        [string]$immediateSpecActions[0].content -match '(?m)^title: "Legacy Project Memory Specification"$' -and
        [string]$immediateSpecActions[0].content -match '(?m)^status: implemented$' -and
        [string]$immediateSpecActions[0].content -match '(?m)^## 10\. Acceptance / Evidence$' -and
        [string]$immediateSpecActions[0].content -like "*$legacySpecBody*"
    )
    Add-Case -Name "workflow-spec-lite-numbered-metadata-promoted" -Passed $immediateSpecCanonical -Detail "The official numbered headings, Acceptance / Evidence, Proposed Approach, metadata Title, path Slug, Done status, and complete legacy body are promoted deterministically."
    $evidence.immediate_spec_canonical = $immediateSpecCanonical

    $statusMappings = [ordered]@{
        Draft = "draft"
        Active = "accepted"
        Done = "implemented"
        Archived = "archived"
        Superseded = "superseded"
    }
    $statusMappingPass = $true
    foreach ($legacyStatus in $statusMappings.Keys) {
        $statusRoot = Join-Path $scratchRoot ("legacy-spec-status-{0}" -f $legacyStatus.ToLowerInvariant())
        Copy-Fixture -Source $pristineRoot -Destination $statusRoot
        $statusBody = New-WorkflowSpecLiteText -Id "legacy-spec" -Title ("{0} legacy Spec" -f $legacyStatus) -Status $legacyStatus
        Write-Utf8NoBom -Path (Join-Path $statusRoot $immediateSpecRelative) -Text $statusBody
        $statusAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $statusRoot
        $statusAction = @($statusAnalyze.payload.plan.actions | Where-Object { [string]$_.path -ceq $immediateSpecRelative -and [string]$_.reason_code -ceq "LEGACY_SPEC_PROMOTED" })
        $mapped = [string]$statusMappings[$legacyStatus]
        $statusPass = ((Test-InvocationPass -Invocation $statusAnalyze) -and $statusAction.Count -eq 1 -and
            [string]$statusAction[0].content -match ("(?m)^status: {0}$" -f [regex]::Escape($mapped)) -and
            [string]$statusAction[0].content -like "*$statusBody*")
        $statusMappingPass = $statusMappingPass -and $statusPass
    }
    Add-Case -Name "workflow-spec-lite-status-mapping" -Passed $statusMappingPass -Detail "Draft, Active, Done, Archived, and Superseded map to canonical lifecycle values without consulting process or plan content."

    $unsupportedStatusPass = $true
    foreach ($legacyStatus in @("Deferred", "Experimental")) {
        $statusRoot = Join-Path $scratchRoot ("legacy-spec-blocked-{0}" -f $legacyStatus.ToLowerInvariant())
        Copy-Fixture -Source $pristineRoot -Destination $statusRoot
        Write-Utf8NoBom -Path (Join-Path $statusRoot $immediateSpecRelative) -Text (New-WorkflowSpecLiteText -Id "legacy-spec" -Title "Blocked legacy Spec" -Status $legacyStatus)
        $beforeStatusAnalyze = Get-TreeFingerprint -Root $statusRoot
        $statusAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $statusRoot
        $statusDisposition = @($statusAnalyze.payload.human_disposition | Where-Object { [string]$_.path -ceq $immediateSpecRelative -and [string]$_.reason_code -ceq "SPEC_STATUS_REQUIRES_DISPOSITION" }).Count -eq 1
        $statusClosed = ((Test-InvocationBlocked -Invocation $statusAnalyze) -and $statusDisposition -and $beforeStatusAnalyze -ceq (Get-TreeFingerprint -Root $statusRoot) -and @((Get-BackupFiles -ProjectRoot $statusRoot)).Count -eq 0)
        $unsupportedStatusPass = $unsupportedStatusPass -and $statusClosed
    }
    Add-Case -Name "workflow-spec-lite-unsupported-status-fails-closed" -Passed $unsupportedStatusPass -Detail "Deferred and unknown legacy status values require human disposition without writes."

    $slugRoot = Join-Path $scratchRoot "legacy-spec-slug-mismatch"
    Copy-Fixture -Source $pristineRoot -Destination $slugRoot
    Write-Utf8NoBom -Path (Join-Path $slugRoot $immediateSpecRelative) -Text (New-WorkflowSpecLiteText -Id "legacy-spec" -Title "Slug mismatch" -Status "Draft" -Slug "different-spec")
    $slugBefore = Get-TreeFingerprint -Root $slugRoot
    $slugAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $slugRoot
    $slugDisposition = @($slugAnalyze.payload.human_disposition | Where-Object { [string]$_.path -ceq $immediateSpecRelative -and [string]$_.reason_code -ceq "SPEC_SLUG_MISMATCH" }).Count -eq 1
    $slugClosed = ((Test-InvocationBlocked -Invocation $slugAnalyze) -and $slugDisposition -and $slugBefore -ceq (Get-TreeFingerprint -Root $slugRoot) -and @((Get-BackupFiles -ProjectRoot $slugRoot)).Count -eq 0)
    Add-Case -Name "workflow-spec-lite-slug-mismatch-fails-closed" -Passed $slugClosed -Detail "A non-empty legacy Slug that differs from docs/specs/<id> requires human disposition without writes."

    # A completed project-bootstrap language migration may prove that custom
    # scaffold and nested Context index bytes are exact target templates.
    $provenanceRoot = Join-Path $scratchRoot "verified-language-provenance"
    Copy-Fixture -Source $pristineRoot -Destination $provenanceRoot
    $provenanceFiles = [ordered]@{
        "AGENTS.md" = "# Proven target-language root entrypoint`n`nThis public fixture is not a bundled scaffold byte match.`n"
        ".agents/context/business/README.md" = [IO.File]::ReadAllText((Join-Path $legacyTemplateRoot "project-agent/context/business/README.md"), [Text.UTF8Encoding]::new($false, $true))
        ".agents/context/experience/README.md" = [IO.File]::ReadAllText((Join-Path $legacyTemplateRoot "project-agent/context/experience/README.md"), [Text.UTF8Encoding]::new($false, $true))
        ".agents/context/experience/cases/case_template.md" = [IO.File]::ReadAllText((Join-Path $legacyTemplateRoot "project-agent/context/experience/cases/case_template.md"), [Text.UTF8Encoding]::new($false, $true))
        ".agents/context/tech/README.md" = [IO.File]::ReadAllText((Join-Path $legacyTemplateRoot "project-agent/context/tech/README.md"), [Text.UTF8Encoding]::new($false, $true))
    }
    foreach ($relative in $provenanceFiles.Keys) { Write-Utf8NoBom -Path (Join-Path $provenanceRoot $relative) -Text ([string]$provenanceFiles[$relative]) }
    $pureActions = @(
        [ordered]@{ relative_path = "AGENTS.md"; action = "replace-template"; manual_review = $false },
        [ordered]@{ relative_path = ".agents/context/business/README.md"; action = "replace-template"; manual_review = $false },
        [ordered]@{ relative_path = ".agents/context/experience/README.md"; action = "already-target-template"; manual_review = $false },
        [ordered]@{ relative_path = ".agents/context/experience/cases/case_template.md"; action = "replace-template"; manual_review = $false },
        [ordered]@{ relative_path = ".agents/context/tech/README.md"; action = "add-target-template"; manual_review = $false }
    )
    [void](Set-LanguageMigrationProvenance -Root $provenanceRoot -Actions $pureActions)
    $provenanceBefore = Get-FileSnapshot -Root $provenanceRoot
    $provenanceAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $provenanceRoot
    $provenanceAfter = Get-FileSnapshot -Root $provenanceRoot
    $verifiedRoot = @($provenanceAnalyze.payload.plan.actions | Where-Object { [string]$_.path -ceq "AGENTS.md" -and [string]$_.reason_code -ceq "LEGACY_ENTRYPOINT_REPLACED" }).Count -eq 1
    $verifiedNested = @($pureActions | Where-Object { [string]$_.relative_path -like ".agents/context/*" } | ForEach-Object {
            $relative = [string]$_.relative_path
            @($provenanceAnalyze.payload.plan.actions | Where-Object { [string]$_.path -ceq $relative -and [string]$_.action -ceq "preserve" -and [string]$_.reason_code -ceq "LANGUAGE_MIGRATION_TEMPLATE_PRESERVED_NON_AUTHORITY" }).Count -eq 1
        } | Where-Object { -not $_ }).Count -eq 0
    $provenancePass = ((Test-InvocationPass -Invocation $provenanceAnalyze) -and $verifiedRoot -and $verifiedNested -and (Test-SnapshotEqual -Before $provenanceBefore -After $provenanceAfter))
    Add-Case -Name "verified-language-migration-templates" -Passed $provenancePass -Detail "All three pure-template actions can prove a custom legacy scaffold and preserve nested Context template/index bytes as non-authority."

    $invalidProvenancePass = $true
    foreach ($kind in @("missing", "forged", "stale", "outside", "language", "action-path")) {
        $invalidRoot = Join-Path $scratchRoot ("invalid-language-provenance-{0}" -f $kind)
        Copy-Fixture -Source $provenanceRoot -Destination $invalidRoot
        $invalidLockPath = Join-Path $invalidRoot ".agents/hub.lock.json"
        $invalidLock = Get-Content -LiteralPath $invalidLockPath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
        $proposalPath = [string]$invalidLock.language_migration.proposal
        $resultPath = [string]$invalidLock.language_migration.result
        # Copy-Fixture changes the root, so first rewrite otherwise-valid project/path bindings.
        $proposal = Get-Content -LiteralPath $proposalPath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
        $newProposalPath = Join-Path $invalidRoot ".agents/language-migration/20260810-000000/proposal.json"
        $newResultPath = Join-Path $invalidRoot ".agents/language-migration/20260810-000000/result.json"
        $proposal.project = $invalidRoot
        $result.project = $invalidRoot
        $result.proposal = $newProposalPath
        $invalidLock.language_migration.proposal = $newProposalPath
        $invalidLock.language_migration.result = $newResultPath
        Write-Utf8NoBom -Path $newProposalPath -Text ($proposal | ConvertTo-Json -Depth 30)
        Write-Utf8NoBom -Path $newResultPath -Text ($result | ConvertTo-Json -Depth 30)
        switch ($kind) {
            "missing" { [IO.File]::Delete($newResultPath) }
            "forged" {
                $result.actions[0].final_hash_sha256 = "0" * 64
                Write-Utf8NoBom -Path $newResultPath -Text ($result | ConvertTo-Json -Depth 30)
            }
            "stale" { Add-Content -LiteralPath (Join-Path $invalidRoot "AGENTS.md") -Value "stale bytes" }
            "outside" { $invalidLock.language_migration.result = "../outside-result.json" }
            "language" {
                $result.target_language = "zh-CN"
                Write-Utf8NoBom -Path $newResultPath -Text ($result | ConvertTo-Json -Depth 30)
            }
            "action-path" {
                $result.actions[0].relative_path = "AGENTS-copy.md"
                Write-Utf8NoBom -Path $newResultPath -Text ($result | ConvertTo-Json -Depth 30)
            }
        }
        Write-Utf8NoBom -Path $invalidLockPath -Text ($invalidLock | ConvertTo-Json -Depth 30)
        $invalidBefore = Get-TreeFingerprint -Root $invalidRoot
        $invalidAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $invalidRoot
        $untrustedRoot = @($invalidAnalyze.payload.human_disposition | Where-Object { [string]$_.path -ceq "AGENTS.md" -and [string]$_.reason_code -ceq "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED" }).Count -eq 1
        $invalidClosed = ((Test-InvocationBlocked -Invocation $invalidAnalyze) -and $untrustedRoot -and $invalidBefore -ceq (Get-TreeFingerprint -Root $invalidRoot) -and @((Get-BackupFiles -ProjectRoot $invalidRoot)).Count -eq 0)
        $invalidProvenancePass = $invalidProvenancePass -and $invalidClosed
    }
    Add-Case -Name "invalid-language-migration-provenance-fails-closed" -Passed $invalidProvenancePass -Detail "Missing, forged, stale, out-of-root, language-mismatched, and action-path-mismatched provenance grants no template trust and produces no writes."

    $manualReviewPass = $true
    $manualActions = [ordered]@{
        "merge-with-manual-review" = ".agents/context/business/README.md"
        "route-hot-memory-manual-review" = ".agents/notes.md"
        "preserve-manual-review" = ".agents/context/experience/README.md"
    }
    foreach ($manualAction in $manualActions.Keys) {
        $manualRoot = Join-Path $scratchRoot ("manual-review-language-provenance-{0}" -f $manualAction)
        Copy-Fixture -Source $pristineRoot -Destination $manualRoot
        $manualRelative = [string]$manualActions[$manualAction]
        Write-Utf8NoBom -Path (Join-Path $manualRoot $manualRelative) -Text "# Project-specific legacy content`n`nThis content has no deterministic canonical markers and requires a maintainer decision.`n"
        [void](Set-LanguageMigrationProvenance -Root $manualRoot -Actions @([ordered]@{ relative_path = $manualRelative; action = $manualAction; manual_review = $true }))
        $manualBefore = Get-TreeFingerprint -Root $manualRoot
        $manualAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $manualRoot
        $manualDisposition = @($manualAnalyze.payload.human_disposition | Where-Object { [string]$_.path -ceq $manualRelative -and [string]$_.reason_code -ceq "CONTEXT_MARKERS_MISSING" }).Count -eq 1
        $manualPreserve = @($manualAnalyze.payload.plan.actions | Where-Object { [string]$_.path -ceq $manualRelative -and [string]$_.action -ceq "preserve" }).Count
        $manualClosed = ((Test-InvocationBlocked -Invocation $manualAnalyze) -and $manualDisposition -and $manualPreserve -eq 0 -and $manualBefore -ceq (Get-TreeFingerprint -Root $manualRoot))
        $manualReviewPass = $manualReviewPass -and $manualClosed
    }
    Add-Case -Name "manual-review-language-provenance-stays-human" -Passed $manualReviewPass -Detail "merge, hot-memory routing, and preserve manual-review provenance are never downgraded to preserved non-authority."

    $provenanceApplyBefore = Get-FileSnapshot -Root $provenanceRoot
    $provenanceApplied = Invoke-Migration -Mode "Apply" -ProjectRoot $provenanceRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $provenanceAnalyze.payload) -ConfirmMigration
    $provenanceApplyAfter = Get-FileSnapshot -Root $provenanceRoot
    $nestedBytesPreserved = @($pureActions | Where-Object { [string]$_.relative_path -like ".agents/context/*" } | ForEach-Object {
            $relative = [string]$_.relative_path
            [string]$provenanceApplyBefore[$relative] -ceq [string]$provenanceApplyAfter[$relative]
        } | Where-Object { -not $_ }).Count -eq 0
    $provenanceBackupId = Get-BackupIdFromResult -Payload $provenanceApplied.payload
    $provenanceRolledBack = Invoke-Migration -Mode "Rollback" -ProjectRoot $provenanceRoot -BackupId $provenanceBackupId -ConfirmRollback
    $provenanceRollbackExact = (Test-SnapshotEqual -Before $provenanceApplyBefore -After (Get-FileSnapshot -Root $provenanceRoot))
    $provenanceLifecyclePass = ((Test-InvocationPass -Invocation $provenanceApplied) -and [string]$provenanceApplied.payload.workspace_check -ceq "PASS" -and
        $nestedBytesPreserved -and (Test-InvocationPass -Invocation $provenanceRolledBack) -and $provenanceRollbackExact -and @((Get-BackupFiles -ProjectRoot $provenanceRoot)).Count -gt 0)
    Add-Case -Name "verified-language-template-apply-rollback" -Passed $provenanceLifecyclePass -Detail "Fixture Apply passes the workspace check without changing nested template/index bytes; Rollback restores the exact pre-state and retains the backup."

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
    $unsupportedNestedRelative = "docs/specs/custom/nested/spec.md"
    Write-Utf8NoBom -Path (Join-Path $unsupportedRoot $unsupportedNestedRelative) -Text @"
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
    $unsupportedDisposition = @($unsupported.payload.human_disposition | Where-Object {
            [string]$_.path -ceq $unsupportedNestedRelative -and [string]$_.reason_code -ceq "SPEC_PATH_UNSUPPORTED"
        }).Count -eq 1
    $unsupportedClosed = ((Test-InvocationBlocked -Invocation $unsupported) -and $unsupportedDisposition -and
        $unsupportedBefore -ceq (Get-TreeFingerprint -Root $unsupportedRoot) -and @((Get-BackupFiles -ProjectRoot $unsupportedRoot)).Count -eq 0)
    Add-Case -Name "unsupported-nested-spec-fails-closed" -Passed $unsupportedClosed -Detail "A non-archive nested Spec remains HUMAN_DISPOSITION_REQUIRED / SPEC_PATH_UNSUPPORTED without backup or target writes."
    $evidence.analyze_fail_closed = ($ambiguousClosed -and $unsupportedClosed)
    $evidence.unsupported_nested_spec_rejected = $unsupportedClosed

    # Project-local scaffold is migratable only when both legacy authority
    # files match the frozen legacy templates exactly.  Custom content must
    # block Analyze and Apply without creating backup or target state.
    $scaffoldConflictPass = $true
    foreach ($relative in @("AGENTS.md", ".agents/AGENTS.md")) {
        $customRoot = Join-Path $scratchRoot ("custom-scaffold-{0}" -f ($relative -replace '[^A-Za-z0-9]+', '-').Trim('-'))
        Copy-Fixture -Source $pristineRoot -Destination $customRoot
        Add-Content -LiteralPath (Join-Path $customRoot $relative) -Value "`nProject-local scaffold customization.`n"
        $customBefore = Get-TreeFingerprint -Root $customRoot
        $customAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $customRoot
        $customApply = Invoke-Migration -Mode "Apply" -ProjectRoot $customRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $customAnalyze.payload) -ConfirmMigration
        $customDisposition = @($customAnalyze.payload.human_disposition | Where-Object { [string]$_.path -ceq $relative -and [string]$_.reason_code -ceq "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED" }).Count -eq 1
        $customRejected = ((Test-InvocationBlocked -Invocation $customAnalyze) -and (Test-InvocationBlocked -Invocation $customApply) -and
            $customDisposition -and $customBefore -ceq (Get-TreeFingerprint -Root $customRoot) -and @((Get-BackupFiles -ProjectRoot $customRoot)).Count -eq 0)
        $scaffoldConflictPass = $scaffoldConflictPass -and $customRejected
    }
    Add-Case -Name "modified-legacy-scaffold-fails-closed" -Passed $scaffoldConflictPass -Detail "Modified root or project-agent legacy authority is routed to HUMAN_DISPOSITION_REQUIRED; Analyze and Apply preserve it without backup or target writes."
    $evidence.scaffold_conflict = $scaffoldConflictPass

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
    $beforeApplyDirectories = @(Get-DirectorySnapshot -Root $baseRoot)
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

    $targetAgents = [IO.File]::ReadAllText((Join-Path $c33TemplateRoot "AGENTS.md"), [Text.UTF8Encoding]::new($false, $true))
    $targetReadme = [IO.File]::ReadAllText((Join-Path $c33TemplateRoot ".agents/README.md"), [Text.UTF8Encoding]::new($false, $true))
    $targetGitignore = [IO.File]::ReadAllText((Join-Path $c33TemplateRoot ".agents/.gitignore"), [Text.UTF8Encoding]::new($false, $true))
    $migratedAgents = Get-Content -LiteralPath (Join-Path $baseRoot "AGENTS.md") -Raw
    $canonicalDirectories = @(".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")
    $layoutMigrated = (
        $migratedAgents -ceq $targetAgents -and
        $migratedAgents -notmatch '(?i)\.agents/(?:AGENTS\.md|process\.txt|plan\.md|commands)' -and
        (Get-Content -LiteralPath (Join-Path $baseRoot ".agents/README.md") -Raw) -ceq $targetReadme -and
        (Get-Content -LiteralPath (Join-Path $baseRoot ".agents/.gitignore") -Raw) -ceq $targetGitignore -and
        -not (Test-Path -LiteralPath (Join-Path $baseRoot ".agents/AGENTS.md")) -and
        @($canonicalDirectories | Where-Object { -not (Test-Path -LiteralPath (Join-Path $baseRoot $_) -PathType Container) }).Count -eq 0 -and
        [string]$applied.payload.workspace_check -ceq "PASS"
    )
    Add-Case -Name "successful-migration-layout" -Passed $layoutMigrated -Detail "Apply installs the frozen C3.3 entrypoint, README, ignore contract, and canonical directories; retires legacy project-agent authority; and passes project-workspace check."
    $evidence.scaffold_layout_migrated = $layoutMigrated

    $contextReadmeApplyPreserved = ([string]$beforeApplySnapshot[$contextReadmeRelative] -ceq [string]$afterApplySnapshot[$contextReadmeRelative])
    $archiveSpecApplyPreserved = ([string]$beforeApplySnapshot[$archiveSpecRelative] -ceq [string]$afterApplySnapshot[$archiveSpecRelative])
    Add-Case -Name "non-authority-bytes-preserved-on-apply" -Passed ($contextReadmeApplyPreserved -and $archiveSpecApplyPreserved -and $layoutMigrated) -Detail "Apply preserves Context README and archived Spec bytes while the post-migration workspace check passes."

    $lockPath = Join-Path $baseRoot ".agents/hub.lock.json"
    $lockAfterApply = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -Depth 30
    $languagePreserved = ([string]$lockAfterApply.project_language -ceq "en" -and [string]$lockAfterApply.workspace_model -ceq "c3.3" -and
        (@($lockAfterApply.workspace_roots) -join "`n") -ceq (@(".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs") -join "`n"))
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

    $backupManifest = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json -Depth 100
    $contextReadmeBackup = @($backupManifest.pre_state | Where-Object { [string]$_.path -ceq $contextReadmeRelative })
    $archiveSpecBackup = @($backupManifest.pre_state | Where-Object { [string]$_.path -ceq $archiveSpecRelative })
    $nonAuthorityBackupScope = (
        $contextReadmeBackup.Count -eq 1 -and [string]$contextReadmeBackup[0].content_base64 -ceq [string]$beforeApplySnapshot[$contextReadmeRelative] -and
        $archiveSpecBackup.Count -eq 1 -and [string]$archiveSpecBackup[0].content_base64 -ceq [string]$beforeApplySnapshot[$archiveSpecRelative]
    )
    Add-Case -Name "non-authority-paths-in-complete-backup" -Passed $nonAuthorityBackupScope -Detail "The complete pre-state backup binds preserved Context README and archived Spec bytes without making them migration actions."
    $evidence.non_authority_backup_scope = $nonAuthorityBackupScope

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

    $rollbackDirectories = @(Get-DirectorySnapshot -Root $baseRoot)
    $rollbackSnapshot = Get-FileSnapshot -Root $baseRoot
    $contextReadmeRollbackPreserved = ([string]$beforeApplySnapshot[$contextReadmeRelative] -ceq [string]$rollbackSnapshot[$contextReadmeRelative])
    $archiveSpecRollbackPreserved = ([string]$beforeApplySnapshot[$archiveSpecRelative] -ceq [string]$rollbackSnapshot[$archiveSpecRelative])
    $layoutRollbackExact = (
        ($beforeApplyDirectories -join "`n") -ceq ($rollbackDirectories -join "`n") -and
        [string]$beforeApplySnapshot["AGENTS.md"] -ceq [string]$rollbackSnapshot["AGENTS.md"] -and
        [string]$beforeApplySnapshot[".agents/AGENTS.md"] -ceq [string]$rollbackSnapshot[".agents/AGENTS.md"] -and
        -not (Test-Path -LiteralPath (Join-Path $baseRoot ".agents/README.md")) -and
        -not (Test-Path -LiteralPath (Join-Path $baseRoot ".agents/.gitignore")) -and
        @($canonicalDirectories | Where-Object {
                $relative = $_
                $beforeApplyDirectories -notcontains $relative -and (Test-Path -LiteralPath (Join-Path $baseRoot $relative))
            }).Count -eq 0 -and
        $backupRetained
    )
    Add-Case -Name "rollback-layout-exactness" -Passed $layoutRollbackExact -Detail "Rollback restores the legacy entrypoint and project-agent authority, removes migration-created C3.3 scaffold files and empty directories, and retains the backup."
    $evidence.rollback_layout_exact = $layoutRollbackExact
    Add-Case -Name "non-authority-bytes-preserved-on-rollback" -Passed ($contextReadmeRollbackPreserved -and $archiveSpecRollbackPreserved) -Detail "Rollback leaves the preserved Context README and archived Spec byte-identical to their pre-Apply state."
    $evidence.context_readme_preserved = ($contextReadmeAnalyzePreserved -and $contextReadmeApplyPreserved -and $contextReadmeRollbackPreserved -and $layoutMigrated)
    $evidence.archive_spec_preserved = ($archiveSpecAnalyzePreserved -and $archiveSpecApplyPreserved -and $archiveSpecRollbackPreserved)

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
    $mutationKinds = @("legacy", "target", "language", "workspace", "archive")
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
            "archive" { Add-Content -LiteralPath (Join-Path $mutationRoot $archiveSpecRelative) -Value "`nArchive mutation after Analyze.`n" }
        }
        $beforeRejectedApply = Get-TreeFingerprint -Root $mutationRoot
        $rejectedApply = Invoke-Migration -Mode "Apply" -ProjectRoot $mutationRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $mutationAnalyze.payload) -ConfirmMigration
        $mutationRejected = ((Test-InvocationBlocked -Invocation $rejectedApply) -and $beforeRejectedApply -ceq (Get-TreeFingerprint -Root $mutationRoot) -and @((Get-BackupFiles -ProjectRoot $mutationRoot)).Count -eq 0)
        $mutationPass = $mutationPass -and $mutationRejected
        Add-Case -Name ("apply-rejects-{0}-mutation" -f $kind) -Passed $mutationRejected -Detail ("Apply rejects the {0} mutation after Analyze without creating target or backup files." -f $kind)
    }
    $evidence.mutation_rejection = $mutationPass

    # Rollback rejects every canonical target mutation, as well as project-local
    # Skill/metadata edits.  Each copy derives from the same single fixture.
    $rollbackMutationKinds = @("work", "context", "procedure", "spec", "skill", "metadata", "archive")
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
            "archive" { Add-Content -LiteralPath (Join-Path $mutationRoot $archiveSpecRelative) -Value "`nArchive mutation before Rollback.`n" }
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
