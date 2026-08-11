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
        [string]$DispositionEvidence = "",
        [string]$BackupId = "",
        [string]$ScriptPath = $migrationScript,
        [switch]$ConfirmMigration,
        [switch]$ConfirmRollback
    )

    $arguments = @("-Mode", $Mode, "-ProjectRoot", $ProjectRoot, "-Json")
    if (-not [string]::IsNullOrWhiteSpace($AnalyzeEvidence)) {
        $arguments += @("-AnalyzeEvidence", $AnalyzeEvidence)
    }
    if (-not [string]::IsNullOrWhiteSpace($DispositionEvidence)) {
        $arguments += @("-DispositionEvidence", $DispositionEvidence)
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

function Copy-JsonObject {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ((Get-CanonicalJson -Payload $Value) | ConvertFrom-Json -AsHashtable -Depth 100)
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

function Set-ReviewedDispositionFixture {
    param([Parameter(Mandatory = $true)][string]$Root)

    $rootContract = [IO.File]::ReadAllText((Join-Path $Root "AGENTS.md"), [Text.UTF8Encoding]::new($false, $true))
    Write-Utf8NoBom -Path (Join-Path $Root "AGENTS.md") -Text ($rootContract + "`nProject-specific legacy root behavior awaiting reviewed replacement.`n")
    $projectAgent = [IO.File]::ReadAllText((Join-Path $Root ".agents/AGENTS.md"), [Text.UTF8Encoding]::new($false, $true))
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/AGENTS.md") -Text ($projectAgent + "`nReviewed legacy authority customization.`n")
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/process.txt") -Text @"
# Completed process record

The bounded public fixture migration review finished before this migration candidate.
This file remains useful historical evidence but is not durable authority.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/plan.md") -Text @"
# Retired planning record

All listed actions were completed in a prior session.
This file is retained only as non-authority project history.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/notes.md") -Text @"
# Legacy review notes

The reviewer retained one source policy and one evidence-routing fact.
These lines require deliberate consolidation and must not be inferred automatically.
"@
    $oldContext = Join-Path $Root ".agents/context/verified-context.md"
    if (Test-Path -LiteralPath $oldContext -PathType Leaf) { [IO.File]::Delete($oldContext) }
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/context/legacy-stable-facts.md") -Text @"
# Legacy stable facts

The public fixture has one stable implementation fact and one compatibility boundary.
The reviewed target must consolidate these bytes with the separate legacy notes source.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/context/legacy-reference.md") -Text @"
# Legacy reference notes

This markerless reference remains useful documentation, but review determined that it is not Context authority.
"@
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/commands/legacy-release.md") -Text @"
# Legacy release notes

This synthetic command note is incomplete and requires a reviewed canonical Procedure replacement.
"@
    Write-Utf8NoBom -Path (Join-Path $Root "docs/specs/legacy-proposal/spec.md") -Text @"
# Legacy proposal

This synthetic proposal lacks the complete canonical Spec contract and requires reviewed replacement.
"@
}

function New-ReviewedDispositionEvidence {
    param([Parameter(Mandatory = $true)][object]$Analyze)

    $human = @($Analyze.human_disposition | Sort-Object path, reason_code | ForEach-Object {
            [ordered]@{ path = [string]$_.path; reason_code = [string]$_.reason_code }
        })
    $rootTarget = [IO.File]::ReadAllText((Join-Path $c33TemplateRoot "AGENTS.md"), [Text.UTF8Encoding]::new($false, $true))
    $contextTarget = @"
---
schema: agent-ecosystem/context/v1
id: reviewed-legacy-facts
title: "Reviewed legacy facts"
status: active
updated: 2026-01-01T00:00:00Z
summary: "Consolidated public fixture facts approved by a maintainer."
keywords:
  - "migration"
  - "reviewed-disposition"
evidence:
  - "Reviewed from .agents/context/legacy-stable-facts.md and .agents/notes.md"
---

# Reviewed legacy facts

- The fixture migration boundary is project-local.
- Historical notes remain evidence, not a second durable authority.
"@.TrimStart()
    $procedureTarget = @"
---
schema: agent-ecosystem/procedure/v1
id: reviewed-release
title: "Reviewed release procedure"
kind: workflow
exposure: internal
summary: "Run a bounded synthetic release verification."
triggers:
  - "verify the synthetic release fixture"
side_effects:
  - "read-only fixture inspection"
---

Confirm the synthetic fixture state, inspect the expected evidence, and report the result without external writes.
"@.TrimStart()
    $specTarget = @"
---
schema: agent-ecosystem/spec/v1
id: reviewed-replacement
title: "Reviewed replacement specification"
status: accepted
updated: 2026-01-01T00:00:00Z
summary: "Define a bounded synthetic migration replacement."
related_work: []
supersedes: []
---

The replacement covers only the synthetic fixture. It excludes lifecycle changes and succeeds when the canonical asset validates.
"@.TrimStart()
    $sourceSha = @{}
    foreach ($file in @($Analyze.evidence.files)) {
        if ([string]$file.presence -ceq "file") { $sourceSha[[string]$file.path] = [string]$file.sha256 }
    }
    return [ordered]@{
        schema_version = 1
        project_root = [string]$Analyze.evidence.project_root
        migration_revision = [string]$Analyze.migration_revision
        state_digest = [string]$Analyze.evidence.state_digest
        plan_digest = [string]$Analyze.plan.plan_digest
        human_disposition = $human
        decisions = @(
            [ordered]@{ path = "AGENTS.md"; reason_code = "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED"; disposition = "replace-root-contract"; target = "AGENTS.md"; content = $rootTarget },
            [ordered]@{ path = ".agents/AGENTS.md"; reason_code = "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED"; disposition = "retire-legacy-source" },
            [ordered]@{ path = ".agents/process.txt"; reason_code = "LEGACY_WORK_NOT_DETERMINISTIC"; disposition = "preserve-non-authority" },
            [ordered]@{ path = ".agents/plan.md"; reason_code = "LEGACY_WORK_NOT_DETERMINISTIC"; disposition = "preserve-non-authority" },
            [ordered]@{ path = ".agents/context/legacy-stable-facts.md"; reason_code = "CONTEXT_MARKERS_MISSING"; disposition = "create-context-and-retire-sources"; source_paths = @(".agents/context/legacy-stable-facts.md", ".agents/notes.md"); target = ".agents/context/reviewed-legacy-facts.md"; content = $contextTarget },
            [ordered]@{ path = ".agents/context/legacy-reference.md"; reason_code = "CONTEXT_MARKERS_MISSING"; disposition = "preserve-non-authority" },
            [ordered]@{ path = ".agents/notes.md"; reason_code = "CONTEXT_MARKERS_MISSING"; disposition = "retire-legacy-source" },
            [ordered]@{ path = ".agents/commands/legacy-release.md"; reason_code = "PROCEDURE_MARKERS_MISSING"; disposition = "create-procedure-and-retire-source"; source_sha256 = $sourceSha[".agents/commands/legacy-release.md"]; target = ".agents/procedures/reviewed-release.md"; content = $procedureTarget },
            [ordered]@{ path = "docs/specs/legacy-proposal/spec.md"; reason_code = "SPEC_MARKERS_MISSING"; disposition = "create-spec-and-retire-source"; source_sha256 = $sourceSha["docs/specs/legacy-proposal/spec.md"]; target = "docs/specs/reviewed-replacement/spec.md"; content = $specTarget }
        )
    }
}

function Set-RecognizedRootCustomNestedFixture {
    param([Parameter(Mandatory = $true)][string]$Root)

    $trustedRoot = @"
# Proven legacy root contract

This public fixture root is trusted only through completed language-migration provenance.
"@
    $sentinel = "reviewed-nested-authority-sentinel"
    $legacyNested = [IO.File]::ReadAllText((Join-Path $Root ".agents/AGENTS.md"), [Text.UTF8Encoding]::new($false, $true))
    $customNested = $legacyNested + "`n- Preserve the $sentinel rule in the final root contract.`n"
    $canonicalRoot = [IO.File]::ReadAllText((Join-Path $c33TemplateRoot "AGENTS.md"), [Text.UTF8Encoding]::new($false, $true)).TrimEnd()
    $finalRoot = $canonicalRoot + "`n- Preserve the $sentinel rule in the final root contract.`n"
    Write-Utf8NoBom -Path (Join-Path $Root "AGENTS.md") -Text $trustedRoot
    Write-Utf8NoBom -Path (Join-Path $Root ".agents/AGENTS.md") -Text $customNested
    [void](Set-LanguageMigrationProvenance -Root $Root -Actions @([ordered]@{ relative_path = "AGENTS.md"; action = "replace-template"; manual_review = $false }))
    return [ordered]@{ root_before = $trustedRoot; nested_before = $customNested; final_root = $finalRoot; sentinel = $sentinel }
}

function New-RecognizedRootDispositionEvidence {
    param(
        [Parameter(Mandatory = $true)][object]$Analyze,
        [Parameter(Mandatory = $true)][string]$FinalRootContent
    )

    return [ordered]@{
        schema_version = 1
        project_root = [string]$Analyze.evidence.project_root
        migration_revision = [string]$Analyze.migration_revision
        state_digest = [string]$Analyze.evidence.state_digest
        plan_digest = [string]$Analyze.plan.plan_digest
        human_disposition = @($Analyze.human_disposition | Sort-Object path, reason_code | ForEach-Object {
                [ordered]@{ path = [string]$_.path; reason_code = [string]$_.reason_code }
            })
        decisions = @(
            [ordered]@{ path = ".agents/AGENTS.md"; reason_code = "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED"; disposition = "replace-root-contract"; target = "AGENTS.md"; content = $FinalRootContent }
        )
    }
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
$contextTemplateRelative = ".agents/context/decision-template.md"
$contextStableTemplateRelative = ".agents/context/stable-fact-template.md"
$contextIndexRelative = ".agents/context/context-index.md"
$contextBlankTemplateRelative = ".agents/context/blank-template.md"
$contextAmbiguousFilenameTermRelatives = @(
    ".agents/context/ambiguous-template.md",
    ".agents/context/ambiguous-index.md",
    ".agents/context/ambiguous-placeholder.md"
)
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
    reviewed_disposition_resolved_plan = $false
    reviewed_disposition_fail_closed = $false
    reviewed_disposition_backup_order = $false
    reviewed_disposition_apply = $false
    reviewed_disposition_rollback = $false
    reviewed_disposition_stale = $false
    reviewed_existing_spec_same_path = $false
    recognized_root_nested_merge = $false
    recognized_root_nested_backup = $false
    recognized_root_nested_rollback = $false
    recognized_root_nested_fail_closed = $false
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
        @($analyzeOne.payload.plan.actions | Where-Object {
                [string]$_.path -ceq $contextReadmeRelative -and [string]$_.action -ceq "preserve" -and
                [string]$_.reason_code -cin @("TEMPLATE_PRESERVED_NON_AUTHORITY", "LANGUAGE_MIGRATION_TEMPLATE_PRESERVED_NON_AUTHORITY")
            }).Count -eq 1
    )
    Add-Case -Name "context-readme-preserved-non-authority" -Passed $contextReadmeAnalyzePreserved -Detail "Analyze explicitly preserves a Context README as non-authority without canonical promotion or human disposition."

    $contextStableTemplateRoot = Join-Path $scratchRoot "context-stable-template-name"
    Copy-Fixture -Source $baseRoot -Destination $contextStableTemplateRoot
    Write-Utf8NoBom -Path (Join-Path $contextStableTemplateRoot $contextStableTemplateRelative) -Text @"
# Template classification history

## Summary

Records a stable migration fact about Context classification behavior.

## Keywords

migration, context, classification

## Verified Facts

Filename terms do not override complete stable Context markers.
"@
    $contextStableTemplateBefore = Get-TreeFingerprint -Root $contextStableTemplateRoot
    $contextStableTemplateAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $contextStableTemplateRoot
    $contextStableTemplatePromoted = (
        @($contextStableTemplateAnalyze.payload.human_disposition | Where-Object { [string]$_.path -ceq $contextStableTemplateRelative }).Count -eq 0 -and
        @($contextStableTemplateAnalyze.payload.plan.actions | Where-Object {
                @($_.source_paths) -ccontains $contextStableTemplateRelative -and [string]$_.action -in @("create", "change") -and
                [string]$_.reason_code -ceq "LEGACY_CONTEXT_PROMOTED"
            }).Count -eq 1 -and
        @($contextStableTemplateAnalyze.payload.plan.actions | Where-Object {
                [string]$_.path -ceq $contextStableTemplateRelative -and [string]$_.reason_code -ceq "TEMPLATE_PRESERVED_NON_AUTHORITY"
            }).Count -eq 0 -and
        $contextStableTemplateBefore -ceq (Get-TreeFingerprint -Root $contextStableTemplateRoot) -and @((Get-BackupFiles -ProjectRoot $contextStableTemplateRoot)).Count -eq 0
    )
    Add-Case -Name "context-template-filename-stable-fact-promoted" -Passed $contextStableTemplatePromoted -Detail "A stable Context candidate with template in its filename follows the normal marker contract and is not preserved as non-authority."

    $contextTemplateRoot = Join-Path $scratchRoot "context-template"
    Copy-Fixture -Source $baseRoot -Destination $contextTemplateRoot
    Write-Utf8NoBom -Path (Join-Path $contextTemplateRoot $contextTemplateRelative) -Text @"
# Decision template

## Summary
Template for documenting a future project decision.

## Keywords
TODO: Add decision keywords.
"@
    $contextTemplateBefore = Get-TreeFingerprint -Root $contextTemplateRoot
    $contextTemplateAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $contextTemplateRoot
    $contextTemplateAnalyzePreserved = (
        @($contextTemplateAnalyze.payload.human_disposition | Where-Object { [string]$_.path -ceq $contextTemplateRelative }).Count -eq 0 -and
        @($contextTemplateAnalyze.payload.plan.actions | Where-Object {
                [string]$_.path -ceq $contextTemplateRelative -and [string]$_.action -ceq "preserve" -and [string]$_.reason_code -ceq "TEMPLATE_PRESERVED_NON_AUTHORITY"
            }).Count -eq 1 -and
        @($contextTemplateAnalyze.payload.plan.actions | Where-Object {
                @($_.source_paths) -ccontains $contextTemplateRelative -and [string]$_.action -in @("create", "change")
            }).Count -eq 0 -and
        $contextTemplateBefore -ceq (Get-TreeFingerprint -Root $contextTemplateRoot) -and @((Get-BackupFiles -ProjectRoot $contextTemplateRoot)).Count -eq 0
    )
    Add-Case -Name "context-real-template-preserved-non-authority" -Passed $contextTemplateAnalyzePreserved -Detail "Explicit content-level template and fill-in signals preserve a real synthetic template as non-authority."

    $contextBlankTemplateRoot = Join-Path $scratchRoot "context-blank-template-name"
    Copy-Fixture -Source $baseRoot -Destination $contextBlankTemplateRoot
    Write-Utf8NoBom -Path (Join-Path $contextBlankTemplateRoot $contextBlankTemplateRelative) -Text "  `n`t`n"
    $contextBlankTemplateBefore = Get-TreeFingerprint -Root $contextBlankTemplateRoot
    $contextBlankTemplateAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $contextBlankTemplateRoot
    $contextBlankTemplateStaysHuman = (
        @($contextBlankTemplateAnalyze.payload.human_disposition | Where-Object {
                [string]$_.path -ceq $contextBlankTemplateRelative -and [string]$_.reason_code -ceq "CONTEXT_MARKERS_MISSING"
            }).Count -eq 1 -and
        @($contextBlankTemplateAnalyze.payload.plan.actions | Where-Object {
                [string]$_.path -ceq $contextBlankTemplateRelative -or @($_.source_paths) -ccontains $contextBlankTemplateRelative
            }).Count -eq 0 -and
        (Test-InvocationBlocked -Invocation $contextBlankTemplateAnalyze) -and
        $contextBlankTemplateBefore -ceq (Get-TreeFingerprint -Root $contextBlankTemplateRoot) -and @((Get-BackupFiles -ProjectRoot $contextBlankTemplateRoot)).Count -eq 0
    )
    Add-Case -Name "context-blank-template-name-stays-human" -Passed $contextBlankTemplateStaysHuman -Detail "A whitespace-only Context candidate with template in its filename requires human disposition and is not preserved as non-authority."

    $contextAmbiguousFilenameTermRoot = Join-Path $scratchRoot "context-ambiguous-filename-terms"
    Copy-Fixture -Source $baseRoot -Destination $contextAmbiguousFilenameTermRoot
    foreach ($relative in $contextAmbiguousFilenameTermRelatives) {
        Write-Utf8NoBom -Path (Join-Path $contextAmbiguousFilenameTermRoot $relative) -Text "# Unclassified context note`n`nThis synthetic note has no stable Context markers or explicit template role.`n"
    }
    $contextAmbiguousFilenameTermBefore = Get-TreeFingerprint -Root $contextAmbiguousFilenameTermRoot
    $contextAmbiguousFilenameTermAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $contextAmbiguousFilenameTermRoot
    $contextAmbiguousFilenameTermsStayHuman = $true
    foreach ($relative in $contextAmbiguousFilenameTermRelatives) {
        $hasDisposition = @($contextAmbiguousFilenameTermAnalyze.payload.human_disposition | Where-Object {
                [string]$_.path -ceq $relative -and [string]$_.reason_code -ceq "CONTEXT_MARKERS_MISSING"
            }).Count -eq 1
        $hasDeterministicAction = @($contextAmbiguousFilenameTermAnalyze.payload.plan.actions | Where-Object {
                [string]$_.path -ceq $relative -or @($_.source_paths) -ccontains $relative
            }).Count -gt 0
        $contextAmbiguousFilenameTermsStayHuman = $contextAmbiguousFilenameTermsStayHuman -and $hasDisposition -and -not $hasDeterministicAction
    }
    $contextAmbiguousFilenameTermsStayHuman = (
        $contextAmbiguousFilenameTermsStayHuman -and (Test-InvocationBlocked -Invocation $contextAmbiguousFilenameTermAnalyze) -and
        $contextAmbiguousFilenameTermBefore -ceq (Get-TreeFingerprint -Root $contextAmbiguousFilenameTermRoot) -and @((Get-BackupFiles -ProjectRoot $contextAmbiguousFilenameTermRoot)).Count -eq 0
    )
    Add-Case -Name "context-filename-only-terms-stay-human" -Passed $contextAmbiguousFilenameTermsStayHuman -Detail "Template, index, and placeholder filename terms remain ambiguity signals when content provides neither stable Context markers nor explicit non-authority evidence."

    $contextIndexRoot = Join-Path $scratchRoot "context-explicit-index"
    Copy-Fixture -Source $baseRoot -Destination $contextIndexRoot
    Write-Utf8NoBom -Path (Join-Path $contextIndexRoot $contextIndexRelative) -Text @"
# Context index

This document is an index for context entries.

- [Architecture](architecture.md)
- [Operations](operations.md)
"@
    $contextIndexBefore = Get-TreeFingerprint -Root $contextIndexRoot
    $contextIndexAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $contextIndexRoot
    $contextIndexPreserved = (
        @($contextIndexAnalyze.payload.human_disposition | Where-Object { [string]$_.path -ceq $contextIndexRelative }).Count -eq 0 -and
        @($contextIndexAnalyze.payload.plan.actions | Where-Object {
                [string]$_.path -ceq $contextIndexRelative -and [string]$_.action -ceq "preserve" -and
                [string]$_.reason_code -ceq "TEMPLATE_PRESERVED_NON_AUTHORITY"
            }).Count -eq 1 -and
        @($contextIndexAnalyze.payload.plan.actions | Where-Object {
                @($_.source_paths) -ccontains $contextIndexRelative -and [string]$_.action -in @("create", "change")
            }).Count -eq 0 -and
        $contextIndexBefore -ceq (Get-TreeFingerprint -Root $contextIndexRoot) -and @((Get-BackupFiles -ProjectRoot $contextIndexRoot)).Count -eq 0
    )
    Add-Case -Name "context-explicit-index-preserved-non-authority" -Passed $contextIndexPreserved -Detail "An explicit content-level Context index remains deterministically preserved alongside the README regression fixture."

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
    Write-Utf8NoBom -Path (Join-Path $ambiguousRoot ".agents/context/context-guidance.md") -Text @"
# Context guidance

## Summary
Use this document to add entries for project knowledge.

## Keywords
context, instructions
"@
    $ambiguousBefore = Get-TreeFingerprint -Root $ambiguousRoot
    $ambiguous = Invoke-Migration -Mode "Analyze" -ProjectRoot $ambiguousRoot
    $ambiguousGuidanceDisposition = @($ambiguous.payload.human_disposition | Where-Object {
            [string]$_.path -ceq ".agents/context/context-guidance.md" -and [string]$_.reason_code -ceq "CONTEXT_MARKERS_MISSING"
        }).Count -eq 1
    $ambiguousGuidancePromotion = @($ambiguous.payload.plan.actions | Where-Object {
            @($_.source_paths) -ccontains ".agents/context/context-guidance.md" -and [string]$_.action -in @("create", "change")
        }).Count
    $ambiguousClosed = ((Test-InvocationBlocked -Invocation $ambiguous) -and $ambiguousGuidanceDisposition -and $ambiguousGuidancePromotion -eq 0 -and
        $ambiguousBefore -ceq (Get-TreeFingerprint -Root $ambiguousRoot) -and @((Get-BackupFiles -ProjectRoot $ambiguousRoot)).Count -eq 0)
    Add-Case -Name "ambiguous-input-fails-closed" -Passed $ambiguousClosed -Detail "Markerless and structurally complete instructional candidates require human disposition without canonical promotion, backup, or writes."

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

    # Reviewed human dispositions are explicit, candidate-bound input.  The
    # fixture is public-only and models custom legacy authority, completed
    # process/plan history, and two Context sources consolidated into one.
    $reviewedRoot = Join-Path $scratchRoot "reviewed-disposition"
    Copy-Fixture -Source $pristineRoot -Destination $reviewedRoot
    Set-ReviewedDispositionFixture -Root $reviewedRoot
    $reviewedBefore = Get-FileSnapshot -Root $reviewedRoot
    $reviewedBeforeTree = Get-TreeFingerprint -Root $reviewedRoot
    $reviewedCandidate = Invoke-Migration -Mode "Analyze" -ProjectRoot $reviewedRoot
    $expectedReviewedHuman = @(
        "AGENTS.md:SCAFFOLD_CUSTOM_OR_UNRECOGNIZED",
        ".agents/AGENTS.md:SCAFFOLD_CUSTOM_OR_UNRECOGNIZED",
        ".agents/process.txt:LEGACY_WORK_NOT_DETERMINISTIC",
        ".agents/plan.md:LEGACY_WORK_NOT_DETERMINISTIC",
        ".agents/context/legacy-stable-facts.md:CONTEXT_MARKERS_MISSING",
        ".agents/context/legacy-reference.md:CONTEXT_MARKERS_MISSING",
        ".agents/notes.md:CONTEXT_MARKERS_MISSING",
        ".agents/commands/legacy-release.md:PROCEDURE_MARKERS_MISSING",
        "docs/specs/legacy-proposal/spec.md:SPEC_MARKERS_MISSING"
    ) | Sort-Object
    $actualReviewedHuman = @($reviewedCandidate.payload.human_disposition | ForEach-Object { "{0}:{1}" -f $_.path, $_.reason_code } | Sort-Object)
    $blockedWithoutDisposition = Invoke-Migration -Mode "Apply" -ProjectRoot $reviewedRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $reviewedCandidate.payload) -ConfirmMigration
    $blockedCandidatePass = ((Test-InvocationBlocked -Invocation $reviewedCandidate) -and
        @($reviewedCandidate.payload.reason_codes) -ccontains "HUMAN_DISPOSITION_REQUIRED" -and
        ($actualReviewedHuman -join "`n") -ceq ($expectedReviewedHuman -join "`n") -and
        (Test-InvocationBlocked -Invocation $blockedWithoutDisposition) -and
        $reviewedBeforeTree -ceq (Get-TreeFingerprint -Root $reviewedRoot) -and @((Get-BackupFiles -ProjectRoot $reviewedRoot)).Count -eq 0)
    Add-Case -Name "blocked-analyze-without-disposition-stays-blocked" -Passed $blockedCandidatePass -Detail "A blocked Analyze remains non-applicable without reviewed disposition evidence and creates no backup or target mutation."

    $reviewedEvidenceObject = New-ReviewedDispositionEvidence -Analyze $reviewedCandidate.payload
    $reviewedEvidenceJson = Get-CanonicalJson -Payload $reviewedEvidenceObject
    $reviewedCandidateFresh = Invoke-Migration -Mode "Analyze" -ProjectRoot $reviewedRoot
    $reviewedBindingStable = (
        [string]$reviewedEvidenceObject.migration_revision -ceq [string]$reviewedCandidateFresh.payload.migration_revision -and
        [string]$reviewedEvidenceObject.state_digest -ceq [string]$reviewedCandidateFresh.payload.evidence.state_digest -and
        [string]$reviewedEvidenceObject.plan_digest -ceq [string]$reviewedCandidateFresh.payload.plan.plan_digest
    )
    $reviewedResolved = Invoke-Migration -Mode "Analyze" -ProjectRoot $reviewedRoot -DispositionEvidence $reviewedEvidenceJson
    $resolvedActions = @($reviewedResolved.payload.plan.actions)
    $resolvedSemantics = (
        @($resolvedActions | Where-Object { [string]$_.path -ceq "AGENTS.md" -and [string]$_.action -ceq "change" -and [string]$_.reason_code -ceq "REVIEWED_ROOT_CONTRACT_REPLACED" }).Count -eq 1 -and
        @($resolvedActions | Where-Object { [string]$_.path -ceq ".agents/AGENTS.md" -and [string]$_.action -ceq "remove" }).Count -eq 1 -and
        @($resolvedActions | Where-Object { [string]$_.path -cin @(".agents/process.txt", ".agents/plan.md") -and [string]$_.action -ceq "preserve" -and [string]$_.reason_code -ceq "REVIEWED_NON_AUTHORITY_PRESERVED" }).Count -eq 2 -and
        @($resolvedActions | Where-Object { [string]$_.path -ceq ".agents/context/reviewed-legacy-facts.md" -and [string]$_.action -ceq "create" -and @($_.source_paths).Count -eq 2 }).Count -eq 1 -and
        @($resolvedActions | Where-Object { [string]$_.path -cin @(".agents/context/legacy-stable-facts.md", ".agents/notes.md") -and [string]$_.action -ceq "remove" }).Count -eq 2 -and
        @($resolvedActions | Where-Object { [string]$_.path -ceq ".agents/context/legacy-reference.md" -and [string]$_.action -ceq "preserve" -and [string]$_.reason_code -ceq "REVIEWED_NON_AUTHORITY_PRESERVED" }).Count -eq 1 -and
        @($resolvedActions | Where-Object { [string]$_.path -ceq ".agents/procedures/reviewed-release.md" -and [string]$_.action -ceq "create" -and [string]$_.reason_code -ceq "REVIEWED_PROCEDURE_CREATED" }).Count -eq 1 -and
        @($resolvedActions | Where-Object { [string]$_.path -ceq ".agents/commands/legacy-release.md" -and [string]$_.action -ceq "remove" }).Count -eq 1 -and
        @($resolvedActions | Where-Object { [string]$_.path -ceq "docs/specs/reviewed-replacement/spec.md" -and [string]$_.action -ceq "create" -and [string]$_.reason_code -ceq "REVIEWED_SPEC_CREATED" }).Count -eq 1 -and
        @($resolvedActions | Where-Object { [string]$_.path -ceq "docs/specs/legacy-proposal/spec.md" -and [string]$_.action -ceq "remove" }).Count -eq 1
    )
    $resolvedReadOnly = ($reviewedBeforeTree -ceq (Get-TreeFingerprint -Root $reviewedRoot) -and @((Get-BackupFiles -ProjectRoot $reviewedRoot)).Count -eq 0)
    $resolvedPlanPass = ((Test-InvocationPass -Invocation $reviewedResolved) -and [bool]$reviewedResolved.payload.eligible -and
        @($reviewedResolved.payload.reason_codes).Count -eq 0 -and [int]$reviewedResolved.payload.plan.plan_version -eq 2 -and
        -not [string]::IsNullOrWhiteSpace([string]$reviewedResolved.payload.reviewed_disposition.reviewed_disposition_digest) -and
        $resolvedSemantics -and $resolvedReadOnly)
    Add-Case -Name "complete-reviewed-disposition-resolves-eligible-plan" -Passed $resolvedPlanPass -Detail ("Exact evidence exit={0} status={1} reasons={2} binding_stable={3} semantics={4} read_only={5}." -f $reviewedResolved.exit_code, (Get-StatusText $reviewedResolved.payload), (@($reviewedResolved.payload.reason_codes) -join ','), $reviewedBindingStable, $resolvedSemantics, $resolvedReadOnly)
    $evidence.reviewed_disposition_resolved_plan = $resolvedPlanPass

    $invalidDispositionCases = [Collections.Generic.List[object]]::new()
    $missingDecision = Copy-JsonObject $reviewedEvidenceObject
    $missingDecision.decisions = @($missingDecision.decisions | Select-Object -First ($missingDecision.decisions.Count - 1))
    $invalidDispositionCases.Add([ordered]@{ name = "missing"; evidence = $missingDecision; code = "DISPOSITION_DECISION_MISSING" })
    $extraDecision = Copy-JsonObject $reviewedEvidenceObject
    $extraDecision.decisions = @($extraDecision.decisions) + @([ordered]@{ path = ".agents/unknown.md"; reason_code = "CONTEXT_MARKERS_MISSING"; disposition = "retire-legacy-source" })
    $invalidDispositionCases.Add([ordered]@{ name = "extra"; evidence = $extraDecision; code = "DISPOSITION_DECISION_EXTRA" })
    $duplicateDecision = Copy-JsonObject $reviewedEvidenceObject
    $duplicateDecision.decisions = @($duplicateDecision.decisions) + @($duplicateDecision.decisions[0])
    $invalidDispositionCases.Add([ordered]@{ name = "duplicate"; evidence = $duplicateDecision; code = "DISPOSITION_DECISION_DUPLICATE" })
    $mismatchDecision = Copy-JsonObject $reviewedEvidenceObject
    $mismatchDecision.decisions[0].reason_code = "CONTEXT_MARKERS_MISSING"
    $invalidDispositionCases.Add([ordered]@{ name = "path-reason"; evidence = $mismatchDecision; code = "DISPOSITION_PATH_REASON_MISMATCH" })
    foreach ($binding in @("migration_revision", "state_digest", "plan_digest")) {
        $staleEvidence = Copy-JsonObject $reviewedEvidenceObject
        $staleEvidence[$binding] = "0" * 64
        $invalidDispositionCases.Add([ordered]@{ name = "stale-$binding"; evidence = $staleEvidence; code = "DISPOSITION_EVIDENCE_STALE" })
    }
    $staleProjectRoot = Copy-JsonObject $reviewedEvidenceObject
    $staleProjectRoot.project_root = Join-Path $scratchRoot "different-project"
    $invalidDispositionCases.Add([ordered]@{ name = "stale-project-root"; evidence = $staleProjectRoot; code = "DISPOSITION_EVIDENCE_STALE" })
    $unsupportedDecision = Copy-JsonObject $reviewedEvidenceObject
    $unsupportedDecision.decisions[0].disposition = "infer-project-intent"
    $invalidDispositionCases.Add([ordered]@{ name = "unsupported"; evidence = $unsupportedDecision; code = "DISPOSITION_UNSUPPORTED" })
    $invalidTarget = Copy-JsonObject $reviewedEvidenceObject
    $invalidTarget.decisions[4].target = "../outside.md"
    $invalidDispositionCases.Add([ordered]@{ name = "invalid-target"; evidence = $invalidTarget; code = "DISPOSITION_TARGET_INVALID" })
    $collidingTarget = Copy-JsonObject $reviewedEvidenceObject
    $collidingTarget.decisions[4].target = ".agents/context/README.md"
    $invalidDispositionCases.Add([ordered]@{ name = "target-collision"; evidence = $collidingTarget; code = "DISPOSITION_TARGET_COLLISION" })
    $invalidContent = Copy-JsonObject $reviewedEvidenceObject
    $invalidContent.decisions[4].content = "# Invalid canonical Context`n"
    $invalidDispositionCases.Add([ordered]@{ name = "invalid-content"; evidence = $invalidContent; code = "DISPOSITION_CONTENT_INVALID" })
    $missingSourceBinding = Copy-JsonObject $reviewedEvidenceObject
    [void]$missingSourceBinding.decisions[7].Remove("source_sha256")
    $invalidDispositionCases.Add([ordered]@{ name = "missing-source-binding"; evidence = $missingSourceBinding; code = "DISPOSITION_EVIDENCE_INVALID" })
    $candidateMismatch = Copy-JsonObject $reviewedEvidenceObject
    $candidateMismatch.decisions[7].source_sha256 = "0" * 64
    $invalidDispositionCases.Add([ordered]@{ name = "candidate-mismatch"; evidence = $candidateMismatch; code = "DISPOSITION_SOURCE_MISMATCH" })
    $specCandidateMismatch = Copy-JsonObject $reviewedEvidenceObject
    $specCandidateMismatch.decisions[8].source_sha256 = "0" * 64
    $invalidDispositionCases.Add([ordered]@{ name = "spec-candidate-mismatch"; evidence = $specCandidateMismatch; code = "DISPOSITION_SOURCE_MISMATCH" })
    $procedureCollision = Copy-JsonObject $reviewedEvidenceObject
    $procedureCollision.decisions[7].target = [string](@($reviewedCandidate.payload.plan.actions | Where-Object {
                [string]$_.path -cmatch '^\.agents/procedures/[a-z0-9]+(?:-[a-z0-9]+)*\.md$'
            } | Select-Object -First 1)[0].path)
    $invalidDispositionCases.Add([ordered]@{ name = "procedure-target-collision"; evidence = $procedureCollision; code = "DISPOSITION_TARGET_COLLISION" })
    $invalidProcedureContent = Copy-JsonObject $reviewedEvidenceObject
    $invalidProcedureContent.decisions[7].content = "# Incomplete Procedure`n"
    $invalidDispositionCases.Add([ordered]@{ name = "invalid-procedure-content"; evidence = $invalidProcedureContent; code = "DISPOSITION_CONTENT_INVALID" })
    $invalidSpecContent = Copy-JsonObject $reviewedEvidenceObject
    $invalidSpecContent.decisions[8].content = "# Incomplete Spec`n"
    $invalidDispositionCases.Add([ordered]@{ name = "invalid-spec-content"; evidence = $invalidSpecContent; code = "DISPOSITION_CONTENT_INVALID" })
    $specTargetCollision = Copy-JsonObject $reviewedEvidenceObject
    $specTargetCollision.decisions[8].target = "docs/specs/legacy-spec/spec.md"
    $invalidDispositionCases.Add([ordered]@{ name = "spec-target-collision"; evidence = $specTargetCollision; code = "DISPOSITION_TARGET_COLLISION" })
    $invalidDispositionPass = $true
    foreach ($case in $invalidDispositionCases) {
        $beforeInvalid = Get-TreeFingerprint -Root $reviewedRoot
        $invalidResult = Invoke-Migration -Mode "Analyze" -ProjectRoot $reviewedRoot -DispositionEvidence (Get-CanonicalJson -Payload $case.evidence)
        $casePass = ((Test-InvocationBlocked -Invocation $invalidResult) -and $invalidResult.text -match [regex]::Escape([string]$case.code) -and
            $beforeInvalid -ceq (Get-TreeFingerprint -Root $reviewedRoot) -and @((Get-BackupFiles -ProjectRoot $reviewedRoot)).Count -eq 0)
        $invalidDispositionPass = $invalidDispositionPass -and $casePass
        Add-Case -Name ("reviewed-disposition-{0}-fails-closed" -f $case.name) -Passed $casePass -Detail ("{0} expected={1} actual={2} read_only={3}." -f $case.name, $case.code, (@($invalidResult.payload.reason_codes) -join ','), ($beforeInvalid -ceq (Get-TreeFingerprint -Root $reviewedRoot)))
    }
    $resolvedWithoutDisposition = Invoke-Migration -Mode "Apply" -ProjectRoot $reviewedRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $reviewedResolved.payload) -ConfirmMigration
    $resolvedEvidenceRequired = ((Test-InvocationBlocked -Invocation $resolvedWithoutDisposition) -and $resolvedWithoutDisposition.text -match "DISPOSITION_EVIDENCE_REQUIRED" -and
        $reviewedBeforeTree -ceq (Get-TreeFingerprint -Root $reviewedRoot) -and @((Get-BackupFiles -ProjectRoot $reviewedRoot)).Count -eq 0)
    Add-Case -Name "resolved-apply-requires-same-disposition-evidence" -Passed $resolvedEvidenceRequired -Detail ("Resolved Apply without disposition exit={0} reasons={1}." -f $resolvedWithoutDisposition.exit_code, (@($resolvedWithoutDisposition.payload.reason_codes) -join ','))
    $evidence.reviewed_disposition_fail_closed = ($invalidDispositionPass -and $resolvedEvidenceRequired -and $blockedCandidatePass)

    $staleSourceRoot = Join-Path $scratchRoot "reviewed-disposition-stale-source"
    Copy-Fixture -Source $pristineRoot -Destination $staleSourceRoot
    Set-ReviewedDispositionFixture -Root $staleSourceRoot
    $staleSourceCandidate = Invoke-Migration -Mode "Analyze" -ProjectRoot $staleSourceRoot
    $staleSourceEvidenceObject = New-ReviewedDispositionEvidence -Analyze $staleSourceCandidate.payload
    $staleSourceEvidenceJson = Get-CanonicalJson -Payload $staleSourceEvidenceObject
    $staleSourceResolved = Invoke-Migration -Mode "Analyze" -ProjectRoot $staleSourceRoot -DispositionEvidence $staleSourceEvidenceJson
    Add-Content -LiteralPath (Join-Path $staleSourceRoot ".agents/notes.md") -Value "`nMutation after reviewed Analyze.`n"
    $afterSourceMutation = Get-TreeFingerprint -Root $staleSourceRoot
    $staleSourceApply = Invoke-Migration -Mode "Apply" -ProjectRoot $staleSourceRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $staleSourceResolved.payload) -DispositionEvidence $staleSourceEvidenceJson -ConfirmMigration
    $staleSourcePass = ((Test-InvocationBlocked -Invocation $staleSourceApply) -and $staleSourceApply.text -match "DISPOSITION_EVIDENCE_STALE" -and
        $afterSourceMutation -ceq (Get-TreeFingerprint -Root $staleSourceRoot) -and @((Get-BackupFiles -ProjectRoot $staleSourceRoot)).Count -eq 0)
    Add-Case -Name "post-analyze-disposition-source-mutation-is-stale" -Passed $staleSourcePass -Detail ("Post-Analyze source mutation exit={0} reasons={1}." -f $staleSourceApply.exit_code, (@($staleSourceApply.payload.reason_codes) -join ','))
    $evidence.reviewed_disposition_stale = $staleSourcePass

    $reviewedPreApplySnapshot = Get-FileSnapshot -Root $reviewedRoot
    $reviewedPreApplyDirectories = @(Get-DirectorySnapshot -Root $reviewedRoot)
    $reviewedApplied = Invoke-Migration -Mode "Apply" -ProjectRoot $reviewedRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $reviewedResolved.payload) -DispositionEvidence $reviewedEvidenceJson -ConfirmMigration
    $reviewedBackupId = Get-BackupIdFromResult -Payload $reviewedApplied.payload
    $reviewedBackupPath = Get-BackupPathFromResult -ProjectRoot $reviewedRoot -Payload $reviewedApplied.payload
    $reviewedManifest = if (Test-Path -LiteralPath $reviewedBackupPath -PathType Leaf) { Get-Content -LiteralPath $reviewedBackupPath -Raw | ConvertFrom-Json -Depth 100 } else { $null }
    $reviewedPreStatePaths = @($reviewedManifest.pre_state | ForEach-Object { [string]$_.path })
    $dispositionScopeBackedUp = (@("AGENTS.md", ".agents/AGENTS.md", ".agents/process.txt", ".agents/plan.md", ".agents/context/legacy-stable-facts.md", ".agents/context/legacy-reference.md", ".agents/notes.md", ".agents/context/reviewed-legacy-facts.md", ".agents/commands/legacy-release.md", ".agents/procedures/reviewed-release.md", "docs/specs/legacy-proposal/spec.md", "docs/specs/reviewed-replacement/spec.md") | Where-Object { $reviewedPreStatePaths -cnotcontains $_ }).Count -eq 0
    $reviewedBackupOrder = ((Test-InvocationPass -Invocation $reviewedApplied) -and (Test-BackupBeforeApply -Payload $reviewedApplied.payload -ProjectRoot $reviewedRoot) -and
        $dispositionScopeBackedUp -and -not [string]::IsNullOrWhiteSpace([string]$reviewedApplied.payload.reviewed_disposition_digest))
    Add-Case -Name "reviewed-disposition-backup-before-mutation" -Passed $reviewedBackupOrder -Detail ("Reviewed Apply exit={0} reasons={1} backup={2} complete_scope={3}." -f $reviewedApplied.exit_code, (@($reviewedApplied.payload.reason_codes) -join ','), $reviewedBackupId, $dispositionScopeBackedUp)
    $evidence.reviewed_disposition_backup_order = $reviewedBackupOrder

    $rootTargetContent = [string]$reviewedEvidenceObject.decisions[0].content
    $contextTargetContent = [string]$reviewedEvidenceObject.decisions[4].content
    $procedureTargetContent = [string]$reviewedEvidenceObject.decisions[7].content
    $specTargetContent = [string]$reviewedEvidenceObject.decisions[8].content
    $reviewedAfterSnapshot = Get-FileSnapshot -Root $reviewedRoot
    $workspaceEntrypoint = Join-Path $repositoryRoot "skills/project-workspace/scripts/project-workspace.ps1"
    $workspaceCheckOutput = @(& pwsh -NoProfile -NonInteractive -File $workspaceEntrypoint -Operation check -ProjectRoot $reviewedRoot -Json 2>&1 | ForEach-Object { [string]$_ })
    $workspaceCheckExit = $LASTEXITCODE
    $reviewedDiscoveryRoot = Join-Path $scratchRoot "reviewed-disposition-discovery"
    Copy-Fixture -Source $reviewedRoot -Destination $reviewedDiscoveryRoot
    $workspaceDiscoverOutput = @(& pwsh -NoProfile -NonInteractive -File $workspaceEntrypoint -Operation discover -ProjectRoot $reviewedDiscoveryRoot -Json 2>&1 | ForEach-Object { [string]$_ })
    $workspaceDiscoverExit = $LASTEXITCODE
    $workspaceCheckPayload = if ($workspaceCheckExit -eq 0) { (@($workspaceCheckOutput) -join "`n") | ConvertFrom-Json -Depth 100 } else { $null }
    $workspaceDiscoverPayload = if ($workspaceDiscoverExit -eq 0) { (@($workspaceDiscoverOutput) -join "`n") | ConvertFrom-Json -Depth 100 } else { $null }
    $reviewedLock = Get-Content -LiteralPath (Join-Path $reviewedRoot ".agents/hub.lock.json") -Raw | ConvertFrom-Json -Depth 100
    $reviewedNonAuthorityEntry = @($reviewedLock.migration_non_authority.entries | Where-Object {
            [string]$_.path -ceq ".agents/context/legacy-reference.md" -and [string]$_.evidence_kind -ceq "reviewed-disposition" -and
            [string]$_.evidence_sha256 -ceq [string]$reviewedResolved.payload.reviewed_disposition.reviewed_disposition_digest
        })
    $actualWorkspaceNonAuthority = (
        $workspaceCheckExit -eq 0 -and [string]$workspaceCheckPayload.status -ceq "PASS" -and
        $workspaceDiscoverExit -eq 0 -and (@($workspaceDiscoverPayload.assets | Where-Object { [string]$_.path -ceq ".agents/context/legacy-reference.md" }).Count -eq 0) -and
        $reviewedNonAuthorityEntry.Count -eq 1
    )
    $reviewedMutationPass = ((Test-InvocationPass -Invocation $reviewedApplied) -and [string]$reviewedApplied.payload.workspace_check -ceq "PASS" -and
        [IO.File]::ReadAllText((Join-Path $reviewedRoot "AGENTS.md"), [Text.UTF8Encoding]::new($false, $true)) -ceq $rootTargetContent -and
        -not (Test-Path -LiteralPath (Join-Path $reviewedRoot ".agents/AGENTS.md")) -and
        [string]$reviewedPreApplySnapshot[".agents/process.txt"] -ceq [string]$reviewedAfterSnapshot[".agents/process.txt"] -and
        [string]$reviewedPreApplySnapshot[".agents/plan.md"] -ceq [string]$reviewedAfterSnapshot[".agents/plan.md"] -and
        [string]$reviewedPreApplySnapshot[".agents/context/legacy-reference.md"] -ceq [string]$reviewedAfterSnapshot[".agents/context/legacy-reference.md"] -and
        -not (Test-Path -LiteralPath (Join-Path $reviewedRoot ".agents/context/legacy-stable-facts.md")) -and
        -not (Test-Path -LiteralPath (Join-Path $reviewedRoot ".agents/notes.md")) -and
        [IO.File]::ReadAllText((Join-Path $reviewedRoot ".agents/context/reviewed-legacy-facts.md"), [Text.UTF8Encoding]::new($false, $true)) -ceq $contextTargetContent -and
        -not (Test-Path -LiteralPath (Join-Path $reviewedRoot ".agents/commands/legacy-release.md")) -and
        [IO.File]::ReadAllText((Join-Path $reviewedRoot ".agents/procedures/reviewed-release.md"), [Text.UTF8Encoding]::new($false, $true)) -ceq $procedureTargetContent -and
        -not (Test-Path -LiteralPath (Join-Path $reviewedRoot "docs/specs/legacy-proposal/spec.md")) -and
        [IO.File]::ReadAllText((Join-Path $reviewedRoot "docs/specs/reviewed-replacement/spec.md"), [Text.UTF8Encoding]::new($false, $true)) -ceq $specTargetContent -and
        $actualWorkspaceNonAuthority)
    Add-Case -Name "reviewed-disposition-apply-mutations" -Passed $reviewedMutationPass -Detail ("Reviewed Apply status={0} reasons={1} workspace={2} actual_non_authority={3}." -f (Get-StatusText $reviewedApplied.payload), (@($reviewedApplied.payload.reason_codes) -join ','), [string]$reviewedApplied.payload.workspace_check, $actualWorkspaceNonAuthority)
    $evidence.reviewed_disposition_apply = $reviewedMutationPass

    $reviewedLockPath = Join-Path $reviewedRoot ".agents/hub.lock.json"
    $reviewedLockText = [IO.File]::ReadAllText($reviewedLockPath, [Text.UTF8Encoding]::new($false, $true))
    $staleNonAuthorityLock = $reviewedLockText | ConvertFrom-Json -Depth 100
    $staleNonAuthorityEntries = @($staleNonAuthorityLock.migration_non_authority.entries | Where-Object { [string]$_.path -ceq ".agents/context/legacy-reference.md" })
    $staleNonAuthorityClosed = $false
    if ($staleNonAuthorityEntries.Count -eq 1) {
        $staleNonAuthorityEntries[0].sha256 = "0" * 64
        Write-Utf8NoBom -Path $reviewedLockPath -Text (($staleNonAuthorityLock | ConvertTo-Json -Depth 100) + "`n")
        $staleWorkspaceOutput = @(& pwsh -NoProfile -NonInteractive -File $workspaceEntrypoint -Operation check -ProjectRoot $reviewedRoot -Json 2>&1 | ForEach-Object { [string]$_ })
        $staleWorkspaceExit = $LASTEXITCODE
        Write-Utf8NoBom -Path $reviewedLockPath -Text $reviewedLockText
        $staleNonAuthorityClosed = ($staleWorkspaceExit -ne 0 -and (@($staleWorkspaceOutput) -join "`n") -match [regex]::Escape(".agents/context/legacy-reference.md"))
    }
    Add-Case -Name "stale-non-authority-metadata-fails-closed" -Passed $staleNonAuthorityClosed -Detail "A stale source digest grants no parser/discovery exemption and the actual workspace check fails closed."

    $reviewedRolledBack = Invoke-Migration -Mode "Rollback" -ProjectRoot $reviewedRoot -BackupId $reviewedBackupId -ConfirmRollback
    $reviewedRollbackPass = ((Test-InvocationPass -Invocation $reviewedRolledBack) -and
        (Test-SnapshotEqual -Before $reviewedPreApplySnapshot -After (Get-FileSnapshot -Root $reviewedRoot)) -and
        ($reviewedPreApplyDirectories -join "`n") -ceq ((Get-DirectorySnapshot -Root $reviewedRoot) -join "`n") -and
        (Test-Path -LiteralPath (Join-Path $reviewedRoot (Join-Path ".agents/.migration-backups" $reviewedBackupId)) -PathType Container))
    Add-Case -Name "reviewed-disposition-rollback-exact" -Passed $reviewedRollbackPass -Detail ("Reviewed Rollback exit={0} status={1} reasons={2} backup={3}." -f $reviewedRolledBack.exit_code, (Get-StatusText $reviewedRolledBack.payload), (@($reviewedRolledBack.payload.reason_codes) -join ','), $reviewedBackupId)
    $evidence.reviewed_disposition_rollback = $reviewedRollbackPass

    # A marker-incomplete Spec may already occupy its canonical identity path.
    # Reviewed replacement must update those bytes in place without inventing a
    # new Spec id, while retaining the same evidence and rollback boundaries.
    $existingSpecRoot = Join-Path $scratchRoot "reviewed-existing-immediate-spec"
    Copy-Fixture -Source $pristineRoot -Destination $existingSpecRoot
    $existingSpecRelative = "docs/specs/legacy-spec/spec.md"
    $existingSpecPath = Join-Path $existingSpecRoot $existingSpecRelative
    $existingSpecLegacy = @"
# Existing immediate specification

This synthetic Spec already has its durable path identity but lacks canonical frontmatter.
"@
    Write-Utf8NoBom -Path $existingSpecPath -Text $existingSpecLegacy
    $existingSpecCanonical = @"
---
schema: agent-ecosystem/spec/v1
id: legacy-spec
title: "Reviewed existing specification"
status: accepted
updated: 2026-01-01T00:00:00Z
summary: "Replace an existing immediate Spec without changing its identity."
related_work: []
supersedes: []
---

The reviewed replacement is limited to this synthetic same-path migration fixture.
"@.TrimStart()
    $existingSpecBefore = Get-FileSnapshot -Root $existingSpecRoot
    $existingSpecBeforeDirectories = @(Get-DirectorySnapshot -Root $existingSpecRoot)
    $existingSpecBeforeTree = Get-TreeFingerprint -Root $existingSpecRoot
    $existingSpecAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $existingSpecRoot
    $existingSpecHuman = @($existingSpecAnalyze.payload.human_disposition | ForEach-Object {
            [ordered]@{ path = [string]$_.path; reason_code = [string]$_.reason_code }
        })
    $existingSpecSource = @($existingSpecAnalyze.payload.evidence.files | Where-Object {
            [string]$_.path -ceq $existingSpecRelative -and [string]$_.presence -ceq "file"
        })
    $existingSpecEvidence = [ordered]@{
        schema_version = 1
        project_root = [string]$existingSpecAnalyze.payload.evidence.project_root
        migration_revision = [string]$existingSpecAnalyze.payload.migration_revision
        state_digest = [string]$existingSpecAnalyze.payload.evidence.state_digest
        plan_digest = [string]$existingSpecAnalyze.payload.plan.plan_digest
        human_disposition = $existingSpecHuman
        decisions = @([ordered]@{
                path = $existingSpecRelative
                reason_code = "SPEC_MARKERS_MISSING"
                disposition = "create-spec-and-retire-source"
                source_sha256 = [string]$existingSpecSource[0].sha256
                target = $existingSpecRelative
                content = $existingSpecCanonical
            })
    }
    $existingSpecEvidenceJson = Get-CanonicalJson -Payload $existingSpecEvidence
    $existingSpecResolved = Invoke-Migration -Mode "Analyze" -ProjectRoot $existingSpecRoot -DispositionEvidence $existingSpecEvidenceJson
    $existingSpecActions = @($existingSpecResolved.payload.plan.actions | Where-Object { [string]$_.path -ceq $existingSpecRelative })
    $existingSpecAnalyzeReadOnly = (
        (Test-InvocationBlocked -Invocation $existingSpecAnalyze) -and
        $existingSpecHuman.Count -eq 1 -and [string]$existingSpecHuman[0].path -ceq $existingSpecRelative -and
        [string]$existingSpecHuman[0].reason_code -ceq "SPEC_MARKERS_MISSING" -and
        $existingSpecSource.Count -eq 1 -and
        $existingSpecBeforeTree -ceq (Get-TreeFingerprint -Root $existingSpecRoot) -and
        @((Get-BackupFiles -ProjectRoot $existingSpecRoot)).Count -eq 0
    )
    $existingSpecResolvedPlan = (
        (Test-InvocationPass -Invocation $existingSpecResolved) -and
        $existingSpecActions.Count -eq 1 -and [string]$existingSpecActions[0].action -ceq "change" -and
        [string]$existingSpecActions[0].reason_code -ceq "REVIEWED_SPEC_REPLACED" -and
        (@($existingSpecActions[0].source_paths) -join "`n") -ceq $existingSpecRelative -and
        [string]$existingSpecActions[0].content -ceq $existingSpecCanonical -and
        $existingSpecBeforeTree -ceq (Get-TreeFingerprint -Root $existingSpecRoot)
    )

    $existingSpecInvalidPass = $true
    foreach ($invalidExistingSpec in @(
            [ordered]@{ name = "stale-source"; mutate = "source"; code = "DISPOSITION_SOURCE_MISMATCH" },
            [ordered]@{ name = "malformed-content"; mutate = "malformed"; code = "DISPOSITION_CONTENT_INVALID" },
            [ordered]@{ name = "id-path-mismatch"; mutate = "id"; code = "DISPOSITION_CONTENT_INVALID" }
        )) {
        $invalidEvidence = Copy-JsonObject $existingSpecEvidence
        switch ([string]$invalidExistingSpec.mutate) {
            "source" { $invalidEvidence.decisions[0].source_sha256 = "0" * 64 }
            "malformed" { $invalidEvidence.decisions[0].content = "# Incomplete Spec`n" }
            "id" { $invalidEvidence.decisions[0].content = $existingSpecCanonical -replace '(?m)^id: legacy-spec$', 'id: different-spec' }
        }
        $beforeInvalidExistingSpec = Get-TreeFingerprint -Root $existingSpecRoot
        $invalidExistingSpecResult = Invoke-Migration -Mode "Analyze" -ProjectRoot $existingSpecRoot -DispositionEvidence (Get-CanonicalJson -Payload $invalidEvidence)
        $invalidExistingSpecPass = (
            (Test-InvocationBlocked -Invocation $invalidExistingSpecResult) -and
            $invalidExistingSpecResult.text -match [regex]::Escape([string]$invalidExistingSpec.code) -and
            $beforeInvalidExistingSpec -ceq (Get-TreeFingerprint -Root $existingSpecRoot) -and
            @((Get-BackupFiles -ProjectRoot $existingSpecRoot)).Count -eq 0
        )
        $existingSpecInvalidPass = $existingSpecInvalidPass -and $invalidExistingSpecPass
    }

    $existingSpecApply = Invoke-Migration -Mode "Apply" -ProjectRoot $existingSpecRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $existingSpecResolved.payload) -DispositionEvidence $existingSpecEvidenceJson -ConfirmMigration
    $existingSpecBackupId = Get-BackupIdFromResult -Payload $existingSpecApply.payload
    $assetParser = Join-Path $repositoryRoot "skills/project-workspace/scripts/read-project-assets.ps1"
    $existingSpecParserOutput = @(& $pwshPath -NoProfile -NonInteractive -File $assetParser -ProjectRoot $existingSpecRoot -AssetPath $existingSpecRelative -Json 2>&1 | ForEach-Object { [string]$_ })
    $existingSpecParserExit = $LASTEXITCODE
    $existingSpecParserPayload = if ($existingSpecParserExit -eq 0) { (@($existingSpecParserOutput) -join "`n") | ConvertFrom-Json -Depth 100 } else { $null }
    $existingSpecApplyPass = (
        (Test-InvocationPass -Invocation $existingSpecApply) -and [string]$existingSpecApply.payload.workspace_check -ceq "PASS" -and
        [IO.File]::ReadAllText($existingSpecPath, [Text.UTF8Encoding]::new($false, $true)) -ceq $existingSpecCanonical -and
        $existingSpecParserExit -eq 0 -and [string]$existingSpecParserPayload.status -ceq "PASS" -and
        [int]$existingSpecParserPayload.asset_count -eq 1 -and [string]$existingSpecParserPayload.assets[0].id -ceq "legacy-spec"
    )
    $existingSpecRollback = Invoke-Migration -Mode "Rollback" -ProjectRoot $existingSpecRoot -BackupId $existingSpecBackupId -ConfirmRollback
    $existingSpecRollbackPass = (
        (Test-InvocationPass -Invocation $existingSpecRollback) -and
        (Test-SnapshotEqual -Before $existingSpecBefore -After (Get-FileSnapshot -Root $existingSpecRoot)) -and
        ($existingSpecBeforeDirectories -join "`n") -ceq ((Get-DirectorySnapshot -Root $existingSpecRoot) -join "`n") -and
        [IO.File]::ReadAllText($existingSpecPath, [Text.UTF8Encoding]::new($false, $true)) -ceq $existingSpecLegacy
    )
    $existingSpecSamePathPass = ($existingSpecAnalyzeReadOnly -and $existingSpecResolvedPlan -and $existingSpecInvalidPass -and $existingSpecApplyPass -and $existingSpecRollbackPass)
    Add-Case -Name "reviewed-existing-immediate-spec-same-path-replacement" -Passed $existingSpecSamePathPass -Detail ("Analyze_read_only={0} resolved_change={1} invalid_fail_closed={2} parser={3} apply={4} rollback_exact={5}." -f $existingSpecAnalyzeReadOnly, $existingSpecResolvedPlan, $existingSpecInvalidPass, ([string]$existingSpecParserPayload.status -ceq "PASS"), $existingSpecApplyPass, $existingSpecRollbackPass)
    $evidence.reviewed_existing_spec_same_path = $existingSpecSamePathPass

    # A provenance-recognized root already has one automatic replacement
    # action.  A custom nested authority may replace that action with the full
    # reviewed final root contract while retiring itself in the same decision.
    $recognizedRoot = Join-Path $scratchRoot "recognized-root-custom-nested"
    Copy-Fixture -Source $pristineRoot -Destination $recognizedRoot
    $recognizedFixture = Set-RecognizedRootCustomNestedFixture -Root $recognizedRoot
    $recognizedBeforeSnapshot = Get-FileSnapshot -Root $recognizedRoot
    $recognizedBeforeDirectories = @(Get-DirectorySnapshot -Root $recognizedRoot)
    $recognizedBeforeTree = Get-TreeFingerprint -Root $recognizedRoot
    $recognizedCandidate = Invoke-Migration -Mode "Analyze" -ProjectRoot $recognizedRoot
    $recognizedCandidateRootActions = @($recognizedCandidate.payload.plan.actions | Where-Object { [string]$_.path -ceq "AGENTS.md" })
    $recognizedCandidateShape = (
        (Test-InvocationBlocked -Invocation $recognizedCandidate) -and
        @($recognizedCandidate.payload.human_disposition).Count -eq 1 -and
        [string]$recognizedCandidate.payload.human_disposition[0].path -ceq ".agents/AGENTS.md" -and
        [string]$recognizedCandidate.payload.human_disposition[0].reason_code -ceq "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED" -and
        $recognizedCandidateRootActions.Count -eq 1 -and
        [string]$recognizedCandidateRootActions[0].action -ceq "change" -and
        [string]$recognizedCandidateRootActions[0].reason_code -ceq "LEGACY_ENTRYPOINT_REPLACED"
    )
    $recognizedDisposition = New-RecognizedRootDispositionEvidence -Analyze $recognizedCandidate.payload -FinalRootContent ([string]$recognizedFixture.final_root)
    $recognizedDispositionJson = Get-CanonicalJson -Payload $recognizedDisposition
    $recognizedResolved = Invoke-Migration -Mode "Analyze" -ProjectRoot $recognizedRoot -DispositionEvidence $recognizedDispositionJson
    $recognizedResolvedRootActions = @($recognizedResolved.payload.plan.actions | Where-Object { [string]$_.path -ceq "AGENTS.md" })
    $recognizedResolvedNestedActions = @($recognizedResolved.payload.plan.actions | Where-Object { [string]$_.path -ceq ".agents/AGENTS.md" })
    $recognizedResolvedPass = ($recognizedCandidateShape -and (Test-InvocationPass -Invocation $recognizedResolved) -and [bool]$recognizedResolved.payload.eligible -and
        $recognizedResolvedRootActions.Count -eq 1 -and [string]$recognizedResolvedRootActions[0].action -ceq "change" -and
        [string]$recognizedResolvedRootActions[0].reason_code -ceq "REVIEWED_ROOT_CONTRACT_REPLACED" -and
        [string]$recognizedResolvedRootActions[0].content -ceq [string]$recognizedFixture.final_root -and
        $recognizedResolvedNestedActions.Count -eq 1 -and [string]$recognizedResolvedNestedActions[0].action -ceq "remove" -and
        $recognizedBeforeTree -ceq (Get-TreeFingerprint -Root $recognizedRoot) -and @((Get-BackupFiles -ProjectRoot $recognizedRoot)).Count -eq 0)
    Add-Case -Name "recognized-root-custom-nested-resolved-plan" -Passed $recognizedResolvedPass -Detail ("Candidate shape={0}; resolved exit={1} status={2} root_actions={3} nested_actions={4}." -f $recognizedCandidateShape, $recognizedResolved.exit_code, (Get-StatusText $recognizedResolved.payload), $recognizedResolvedRootActions.Count, $recognizedResolvedNestedActions.Count)
    $evidence.recognized_root_nested_merge = $recognizedResolvedPass

    $recognizedApplied = Invoke-Migration -Mode "Apply" -ProjectRoot $recognizedRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $recognizedResolved.payload) -DispositionEvidence $recognizedDispositionJson -ConfirmMigration
    $recognizedBackupId = Get-BackupIdFromResult -Payload $recognizedApplied.payload
    $recognizedBackupPath = Get-BackupPathFromResult -ProjectRoot $recognizedRoot -Payload $recognizedApplied.payload
    $recognizedManifest = if (Test-Path -LiteralPath $recognizedBackupPath -PathType Leaf) { Get-Content -LiteralPath $recognizedBackupPath -Raw | ConvertFrom-Json -Depth 100 } else { $null }
    $recognizedRootBackup = @($recognizedManifest.pre_state | Where-Object { [string]$_.path -ceq "AGENTS.md" })
    $recognizedNestedBackup = @($recognizedManifest.pre_state | Where-Object { [string]$_.path -ceq ".agents/AGENTS.md" })
    $recognizedBackupPass = ((Test-InvocationPass -Invocation $recognizedApplied) -and (Test-BackupBeforeApply -Payload $recognizedApplied.payload -ProjectRoot $recognizedRoot) -and
        $recognizedRootBackup.Count -eq 1 -and [string]$recognizedRootBackup[0].content_base64 -ceq [string]$recognizedBeforeSnapshot["AGENTS.md"] -and
        $recognizedNestedBackup.Count -eq 1 -and [string]$recognizedNestedBackup[0].content_base64 -ceq [string]$recognizedBeforeSnapshot[".agents/AGENTS.md"])
    $recognizedAppliedRoot = [IO.File]::ReadAllText((Join-Path $recognizedRoot "AGENTS.md"), [Text.UTF8Encoding]::new($false, $true))
    $recognizedApplyPass = ($recognizedBackupPass -and [string]$recognizedApplied.payload.workspace_check -ceq "PASS" -and
        $recognizedAppliedRoot -ceq [string]$recognizedFixture.final_root -and $recognizedAppliedRoot -match [regex]::Escape([string]$recognizedFixture.sentinel) -and
        -not (Test-Path -LiteralPath (Join-Path $recognizedRoot ".agents/AGENTS.md")))
    Add-Case -Name "recognized-root-custom-nested-apply-backup" -Passed $recognizedApplyPass -Detail ("Apply exit={0} workspace={1} backup={2} root_backed={3} nested_backed={4}." -f $recognizedApplied.exit_code, [string]$recognizedApplied.payload.workspace_check, $recognizedBackupId, ($recognizedRootBackup.Count -eq 1), ($recognizedNestedBackup.Count -eq 1))
    $evidence.recognized_root_nested_backup = $recognizedApplyPass

    $recognizedRolledBack = Invoke-Migration -Mode "Rollback" -ProjectRoot $recognizedRoot -BackupId $recognizedBackupId -ConfirmRollback
    $recognizedRollbackPass = ((Test-InvocationPass -Invocation $recognizedRolledBack) -and
        (Test-SnapshotEqual -Before $recognizedBeforeSnapshot -After (Get-FileSnapshot -Root $recognizedRoot)) -and
        ($recognizedBeforeDirectories -join "`n") -ceq ((Get-DirectorySnapshot -Root $recognizedRoot) -join "`n") -and
        (Test-Path -LiteralPath (Join-Path $recognizedRoot (Join-Path ".agents/.migration-backups" $recognizedBackupId)) -PathType Container))
    Add-Case -Name "recognized-root-custom-nested-rollback-exact" -Passed $recognizedRollbackPass -Detail ("Rollback exit={0} status={1} backup={2}." -f $recognizedRolledBack.exit_code, (Get-StatusText $recognizedRolledBack.payload), $recognizedBackupId)
    $evidence.recognized_root_nested_rollback = $recognizedRollbackPass

    $missingRootAction = Join-Path $scratchRoot "recognized-root-missing-auto-action"
    Copy-Fixture -Source $pristineRoot -Destination $missingRootAction
    $missingRootFixture = Set-RecognizedRootCustomNestedFixture -Root $missingRootAction
    $missingLockPath = Join-Path $missingRootAction ".agents/hub.lock.json"
    $missingLock = Get-Content -LiteralPath $missingLockPath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
    [void]$missingLock.Remove("language_migration")
    Write-Utf8NoBom -Path $missingLockPath -Text ($missingLock | ConvertTo-Json -Depth 30)
    $missingRootAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $missingRootAction
    $missingRootEvidence = New-RecognizedRootDispositionEvidence -Analyze $missingRootAnalyze.payload -FinalRootContent ([string]$missingRootFixture.final_root)
    $missingRootEvidence.decisions = @($missingRootEvidence.decisions) + @([ordered]@{ path = "AGENTS.md"; reason_code = "SCAFFOLD_CUSTOM_OR_UNRECOGNIZED"; disposition = "replace-root-contract"; target = "AGENTS.md"; content = [string]$missingRootFixture.final_root })
    $missingRootBefore = Get-TreeFingerprint -Root $missingRootAction
    $missingRootResolved = Invoke-Migration -Mode "Analyze" -ProjectRoot $missingRootAction -DispositionEvidence (Get-CanonicalJson -Payload $missingRootEvidence)
    $missingRootClosed = ((Test-InvocationBlocked -Invocation $missingRootResolved) -and $missingRootResolved.text -match "DISPOSITION_TARGET_COLLISION" -and
        $missingRootBefore -ceq (Get-TreeFingerprint -Root $missingRootAction) -and @((Get-BackupFiles -ProjectRoot $missingRootAction)).Count -eq 0)
    Add-Case -Name "recognized-root-missing-auto-action-fails-closed" -Passed $missingRootClosed -Detail ("Missing automatic root action exit={0} reasons={1}." -f $missingRootResolved.exit_code, (@($missingRootResolved.payload.reason_codes) -join ','))

    $collidingRootAction = Join-Path $scratchRoot "recognized-root-colliding-auto-action"
    Copy-Fixture -Source $pristineRoot -Destination $collidingRootAction
    $collidingRootFixture = Set-RecognizedRootCustomNestedFixture -Root $collidingRootAction
    Write-Utf8NoBom -Path (Join-Path $collidingRootAction "AGENTS.md") -Text ([IO.File]::ReadAllText((Join-Path $c33TemplateRoot "AGENTS.md"), [Text.UTF8Encoding]::new($false, $true)))
    $collidingRootAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $collidingRootAction
    $collidingRootEvidence = New-RecognizedRootDispositionEvidence -Analyze $collidingRootAnalyze.payload -FinalRootContent ([string]$collidingRootFixture.final_root)
    $collidingRootBefore = Get-TreeFingerprint -Root $collidingRootAction
    $collidingRootResolved = Invoke-Migration -Mode "Analyze" -ProjectRoot $collidingRootAction -DispositionEvidence (Get-CanonicalJson -Payload $collidingRootEvidence)
    $collidingRootClosed = ((Test-InvocationBlocked -Invocation $collidingRootResolved) -and $collidingRootResolved.text -match "DISPOSITION_TARGET_COLLISION" -and
        $collidingRootBefore -ceq (Get-TreeFingerprint -Root $collidingRootAction) -and @((Get-BackupFiles -ProjectRoot $collidingRootAction)).Count -eq 0)
    Add-Case -Name "recognized-root-unexpected-auto-action-fails-closed" -Passed $collidingRootClosed -Detail ("Unexpected automatic root action exit={0} reasons={1}." -f $collidingRootResolved.exit_code, (@($collidingRootResolved.payload.reason_codes) -join ','))

    $staleRecognizedRoot = Join-Path $scratchRoot "recognized-root-stale-nested"
    Copy-Fixture -Source $pristineRoot -Destination $staleRecognizedRoot
    $staleRecognizedFixture = Set-RecognizedRootCustomNestedFixture -Root $staleRecognizedRoot
    $staleRecognizedAnalyze = Invoke-Migration -Mode "Analyze" -ProjectRoot $staleRecognizedRoot
    $staleRecognizedEvidence = New-RecognizedRootDispositionEvidence -Analyze $staleRecognizedAnalyze.payload -FinalRootContent ([string]$staleRecognizedFixture.final_root)
    $staleRecognizedEvidenceJson = Get-CanonicalJson -Payload $staleRecognizedEvidence
    $staleRecognizedResolved = Invoke-Migration -Mode "Analyze" -ProjectRoot $staleRecognizedRoot -DispositionEvidence $staleRecognizedEvidenceJson
    Add-Content -LiteralPath (Join-Path $staleRecognizedRoot ".agents/AGENTS.md") -Value "`nMutation after resolved Analyze.`n"
    $staleRecognizedBeforeApply = Get-TreeFingerprint -Root $staleRecognizedRoot
    $staleRecognizedApply = Invoke-Migration -Mode "Apply" -ProjectRoot $staleRecognizedRoot -AnalyzeEvidence (Get-CanonicalJson -Payload $staleRecognizedResolved.payload) -DispositionEvidence $staleRecognizedEvidenceJson -ConfirmMigration
    $staleRecognizedClosed = ((Test-InvocationBlocked -Invocation $staleRecognizedApply) -and $staleRecognizedApply.text -match "DISPOSITION_EVIDENCE_STALE" -and
        $staleRecognizedBeforeApply -ceq (Get-TreeFingerprint -Root $staleRecognizedRoot) -and @((Get-BackupFiles -ProjectRoot $staleRecognizedRoot)).Count -eq 0)
    Add-Case -Name "recognized-root-stale-nested-evidence-fails-closed" -Passed $staleRecognizedClosed -Detail ("Stale nested evidence exit={0} reasons={1}." -f $staleRecognizedApply.exit_code, (@($staleRecognizedApply.payload.reason_codes) -join ','))
    $evidence.recognized_root_nested_fail_closed = ($missingRootClosed -and $collidingRootClosed -and $staleRecognizedClosed)

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
