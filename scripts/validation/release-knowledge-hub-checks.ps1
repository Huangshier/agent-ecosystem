# release-knowledge-hub-checks.ps1
# Extracted from scripts/validate-release.ps1 Invoke-ReleaseValidationRuntimeAndKnowledgeHubChecks (Phase 3).
# Runs knowledge hub catalog, experience search, experience promotion, and duplicate helper hash checks.
# Depends on: release-test-helper.ps1 (Add-Check, Get-FileText, Get-MissingRequiredText), path-guard.ps1 (Join-PathParts).
# Scope: script-level $repoRoot, $scratchRootFull, $script:evidence, $checks.

# Invoke-ReleaseKnowledgeHubChecks: No parameters; runs knowledge hub catalog, experience search,
# experience promotion closure, and duplicate helper hash checks in the original order.
function Invoke-ReleaseKnowledgeHubChecks {

try {
    $catalogPath = "knowledge-hub/knowledge-catalog.md"
    $catalogText = Get-FileText -RelativePath $catalogPath
    $catalogRequiredTokens = @(
        "knowledge/experience/windows-powershell-command-chaining.md",
        "knowledge/experience/stacked-pr-merge-incident-recovery.md",
        "knowledge/patterns/context-gate-spec-validation-loop.md",
        "knowledge/patterns/test-strategy.md",
        "knowledge/patterns/test-driven-development.md",
        "knowledge/patterns/eval-driven-skill-iteration.md",
        "knowledge/standards/public-knowledge-boundary.md",
        "knowledge/standards/bilingual-public-private-routing.md",
        "knowledge/domain-packs/embedded-core/catalog.md"
    )
    $missingCatalogTokens = @(Get-MissingRequiredText -Text $catalogText -RequiredText $catalogRequiredTokens)

    $patternsIndexPath = "knowledge-hub/knowledge/patterns/README.md"
    $patternsIndexText = Get-FileText -RelativePath $patternsIndexPath
    $patternsIndexRequiredTokens = @(
        "test-strategy.md",
        "test-driven-development.md"
    )
    $missingPatternsIndexTokens = @(Get-MissingRequiredText -Text $patternsIndexText -RequiredText $patternsIndexRequiredTokens)

    $metadataFiles = @(
        "knowledge-hub/knowledge/experience/windows-powershell-command-chaining.md",
        "knowledge-hub/knowledge/experience/stacked-pr-merge-incident-recovery.md",
        "knowledge-hub/knowledge/patterns/context-gate-spec-validation-loop.md",
        "knowledge-hub/knowledge/patterns/test-strategy.md",
        "knowledge-hub/knowledge/patterns/test-driven-development.md",
        "knowledge-hub/knowledge/patterns/eval-driven-skill-iteration.md",
        "knowledge-hub/knowledge/standards/public-knowledge-boundary.md",
        "knowledge-hub/knowledge/standards/bilingual-public-private-routing.md",
        "knowledge-hub/knowledge/domain-packs/embedded-core/catalog.md",
        "knowledge-hub/knowledge/domain-packs/embedded-core/validation-checklist.md"
    )
    $metadataErrors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($metadataFile in $metadataFiles) {
        $metadataText = Get-FileText -RelativePath $metadataFile
        foreach ($field in @("Maturity:", "Scope:", "Source:", "Last reviewed:")) {
            if ($metadataText -notmatch ("(?m)^{0}\s*.+" -f [regex]::Escape($field))) {
                $metadataErrors.Add("$metadataFile missing $field")
            }
        }
    }

    if ($missingCatalogTokens.Count -gt 0 -or $missingPatternsIndexTokens.Count -gt 0 -or $metadataErrors.Count -gt 0) {
        Add-Check "knowledge hub catalog" "FAIL" "Knowledge catalog or entry metadata is incomplete." ([ordered]@{
            missing_catalog_entries = @($missingCatalogTokens)
            missing_patterns_index_entries = @($missingPatternsIndexTokens)
            metadata_errors = @($metadataErrors.ToArray())
        })
    }
    else {
        Add-Check "knowledge hub catalog" "PASS" "Catalog links experience, patterns, and standards entries with required metadata." ([ordered]@{
            catalog = $catalogPath
            entries = @($catalogRequiredTokens)
            patterns_index = $patternsIndexPath
            patterns_index_entries = @($patternsIndexRequiredTokens)
            metadata_files = @($metadataFiles)
        })
    }
}
catch {
    Add-Check "knowledge hub catalog" "FAIL" $_.Exception.Message
}

try {
    $indexPath = Join-PathParts $repoRoot "knowledge-hub" "knowledge" "experience" "index.json"
    $index = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
    $searchScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "search_experience.ps1"
    $searchText = & $searchScript -HubDir (Join-PathParts $repoRoot "knowledge-hub") -Query "PowerShell command chaining" -Json
    $search = $searchText | ConvertFrom-Json
    $resultCount = @($search.results).Count
    if ($resultCount -lt 1) {
        throw "Experience search returned no matching entries."
    }
    $script:evidence.knowledge_hub = [ordered]@{
        index_path = $indexPath
        index_entries = @($index.entries).Count
        search_query = "PowerShell command chaining"
        search_results = $resultCount
        top_result = [string]$search.results[0].title
    }
    Add-Check "knowledge hub experience search" "PASS" "Experience index parsed and search returned public workflow experience." $evidence.knowledge_hub
}
catch {
    Add-Check "knowledge hub experience search" "FAIL" $_.Exception.Message
}

try {
    $tempHub = Join-PathParts $scratchRootFull "experience-promote-hub"
    $tempProject = Join-PathParts $scratchRootFull "experience-promote-project"
    Assert-PathInsideRoot -Path $tempHub -Root $scratchRootFull
    Assert-PathInsideRoot -Path $tempProject -Root $scratchRootFull
    Copy-Item -LiteralPath (Join-PathParts $repoRoot "knowledge-hub") -Destination $tempHub -Recurse -Force
    New-Item -ItemType Directory -Force -Path (Join-PathParts $tempProject ".agents" "context" "experience") | Out-Null

    $candidatePath = Join-PathParts $tempProject ".agents" "context" "experience" "validation-promote-closure.md"
    $candidateText = @"
# Validation Promote Closure

## Summary
Temporary cross-project validation lesson used only by release validation.

## Keywords
validation promote closure, release gate, temporary hub

Scope: Cross-project reusable
Global candidate: Yes

## Prevention Rule
Validate experience promotion with a temporary hub so the public source tree is not mutated during release checks.
"@
    Set-Content -LiteralPath $candidatePath -Value $candidateText -Encoding UTF8

    $promoteScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "promote_experience.ps1"
    $rebuildScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "rebuild_experience_index.ps1"
    $searchScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "search_experience.ps1"
    $promoteOutput = @(& $promoteScript -ProjectDir $tempProject -HubDir $tempHub -ProjectTag "validation")
    & $rebuildScript -HubDir $tempHub | Out-Host
    $registryPath = Join-PathParts $tempHub "knowledge" "experience" "index.json"
    $registryHashAfterRebuild = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash
    & $rebuildScript -HubDir $tempHub | Out-Host
    $registryHashAfterNoop = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash
    if ($registryHashAfterNoop -ne $registryHashAfterRebuild) {
        throw "No-op experience index rebuild changed the registry file."
    }

    $searchText = & $searchScript -HubDir $tempHub -Query "validation promote closure" -Json
    $search = $searchText | ConvertFrom-Json
    $resultCount = @($search.results).Count
    if ($resultCount -lt 1) {
        throw "Promoted experience could not be found by search."
    }

    $topResult = $search.results[0]
    if ([string]$topResult.title -ne "Validation Promote Closure") {
        throw ("Unexpected promoted experience search result: {0}" -f [string]$topResult.title)
    }

    Add-Check "experience promote closure" "PASS" "Temporary experience promotion, index rebuild, and search passed without mutating public source." ([ordered]@{
        temp_hub = $tempHub
        temp_project = $tempProject
        promote_output = @($promoteOutput)
        noop_rebuild_preserved_hash = $true
        search_results = $resultCount
        top_result = [string]$topResult.title
    })
}
catch {
    Add-Check "experience promote closure" "FAIL" $_.Exception.Message
}

try {
    $helperPairs = @(
        @("knowledge-hub/scripts/rebuild_experience_index.ps1", "skills/project-bootstrap/scripts/rebuild_experience_index.ps1"),
        @("knowledge-hub/scripts/promote_experience.ps1", "skills/project-bootstrap/scripts/promote_experience.ps1")
    )
    $helperErrors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($pair in $helperPairs) {
        $left = Join-PathParts $repoRoot $pair[0]
        $right = Join-PathParts $repoRoot $pair[1]
        $leftHash = (Get-FileHash -LiteralPath $left -Algorithm SHA256).Hash
        $rightHash = (Get-FileHash -LiteralPath $right -Algorithm SHA256).Hash
        $script:evidence.duplicate_helpers += [ordered]@{
            preferred = $pair[0]
            compatibility_copy = $pair[1]
            hash_sha256 = $leftHash
            identical = ($leftHash -eq $rightHash)
        }
        if ($leftHash -ne $rightHash) {
            $helperErrors.Add(("{0} differs from {1}" -f $pair[0], $pair[1]))
        }
    }
    if ($helperErrors.Count -gt 0) {
        Add-Check "duplicate helper hash" "FAIL" "Compatibility helper hashes differ." @($helperErrors.ToArray())
    }
    else {
        Add-Check "duplicate helper hash" "PASS" "Compatibility helper hashes match preferred knowledge hub scripts." $evidence.duplicate_helpers
    }
}
catch {
    Add-Check "duplicate helper hash" "FAIL" $_.Exception.Message
}

}
