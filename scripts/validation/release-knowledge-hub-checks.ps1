# release-knowledge-hub-checks.ps1
# Extracted from scripts/validate-release.ps1 Invoke-ReleaseValidationRuntimeAndKnowledgeHubChecks (Phase 3).
# Runs platform-neutral knowledge hub catalog, lifecycle, promotion, and duplicate helper hash checks.
# Depends on: release-test-helper.ps1 (Add-Check, Get-FileText, Get-MissingRequiredText), path-guard.ps1 (Join-PathParts).
# Scope: script-level $repoRoot, $scratchRootFull, $script:evidence, $checks.

. (Join-Path $PSScriptRoot "release-knowledge-candidate-checks.ps1")

# Invoke-ReleaseKnowledgeHubChecks: No parameters; runs platform-neutral knowledge governance checks.
function Invoke-ReleaseKnowledgeHubChecks {

function Get-ExperiencePublicSafeMetadataErrors {
    param([object]$Registry)

    $errors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in @($Registry.entries)) {
        $entryId = if ($entry.id) { [string]$entry.id } else { [string]$entry.hub_file }
        foreach ($field in @("source_project", "source_file", "source_relative_path")) {
            if ($entry.PSObject.Properties.Name -contains $field) {
                $errors.Add(("entry {0} contains forbidden legacy field {1}" -f $entryId, $field))
            }
        }

        foreach ($property in @($entry.PSObject.Properties)) {
            foreach ($value in @($property.Value)) {
                $text = [string]$value
                if ([string]::IsNullOrWhiteSpace($text)) {
                    continue
                }
                if ($text -match '^[A-Za-z]:[\\/]' -or $text -match '^\\\\' -or $text -match '^/(Users|home|private|tmp|var|mnt|Volumes)(/|$)') {
                    $errors.Add(("entry {0} field {1} contains absolute path-like metadata" -f $entryId, $property.Name))
                }
            }
        }
    }

    return @($errors.ToArray())
}

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
        "knowledge/domain-packs/embedded-core/catalog.md",
        "knowledge/domain-packs/testing-core/catalog.md"
    )
    $missingCatalogTokens = @(Get-MissingRequiredText -Text $catalogText -RequiredText $catalogRequiredTokens)

    $domainPacksIndexPath = "knowledge-hub/knowledge/domain-packs/README.md"
    $domainPacksIndexText = Get-FileText -RelativePath $domainPacksIndexPath
    $domainPacksIndexRequiredTokens = @(
        "embedded-core/catalog.md",
        "testing-core/catalog.md"
    )
    $missingDomainPacksIndexTokens = @(Get-MissingRequiredText -Text $domainPacksIndexText -RequiredText $domainPacksIndexRequiredTokens)

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
        "knowledge-hub/knowledge/domain-packs/embedded-core/validation-checklist.md",
        "knowledge-hub/knowledge/domain-packs/testing-core/catalog.md",
        "knowledge-hub/knowledge/domain-packs/testing-core/validation-checklist.md"
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

    if ($missingCatalogTokens.Count -gt 0 -or $missingDomainPacksIndexTokens.Count -gt 0 -or $missingPatternsIndexTokens.Count -gt 0 -or $metadataErrors.Count -gt 0) {
        Add-Check "knowledge hub catalog" "FAIL" "Knowledge catalog or entry metadata is incomplete." ([ordered]@{
            missing_catalog_entries = @($missingCatalogTokens)
            missing_domain_packs_index_entries = @($missingDomainPacksIndexTokens)
            missing_patterns_index_entries = @($missingPatternsIndexTokens)
            metadata_errors = @($metadataErrors.ToArray())
        })
    }
    else {
        Add-Check "knowledge hub catalog" "PASS" "Catalog links experience, patterns, and standards entries with required metadata." ([ordered]@{
            catalog = $catalogPath
            entries = @($catalogRequiredTokens)
            domain_packs_index = $domainPacksIndexPath
            domain_packs_index_entries = @($domainPacksIndexRequiredTokens)
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
    $experienceDir = Join-PathParts $repoRoot "knowledge-hub" "knowledge" "experience"
    $indexPath = Join-PathParts $experienceDir "index.json"
    $indexRaw = Get-Content -LiteralPath $indexPath -Raw
    $index = $indexRaw | ConvertFrom-Json
    $allowedMaturity = @("draft", "verified", "proven", "deprecated")
    $lifecycleErrors = New-Object 'System.Collections.Generic.List[string]'
    $experienceFiles = @(
        Get-ChildItem -LiteralPath $experienceDir -File -Filter "*.md" |
            Where-Object { $_.Name -ne "README.md" } |
            Sort-Object Name
    )
    $entriesByFile = @{}
    foreach ($entry in @($index.entries)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.hub_file)) {
            $entriesByFile[[string]$entry.hub_file] = $entry
        }
    }

    if ([int]$index.schema_version -lt 2) {
        $lifecycleErrors.Add(("experience index schema_version should be >= 2, got {0}" -f [string]$index.schema_version))
    }

    foreach ($file in $experienceFiles) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $metadata = [ordered]@{}
        foreach ($field in @("Maturity", "Scope", "Source", "Last reviewed", "Decay policy")) {
            $match = [regex]::Match($text, ("(?m)^{0}\s*:\s*(.+?)\s*$" -f [regex]::Escape($field)))
            if (-not $match.Success) {
                $lifecycleErrors.Add(("{0} missing {1}" -f $file.Name, $field))
                $metadata[$field] = ""
            }
            else {
                $metadata[$field] = $match.Groups[1].Value.Trim()
            }
        }

        $maturity = ([string]$metadata["Maturity"]).ToLowerInvariant()
        if ($maturity -notin $allowedMaturity) {
            $lifecycleErrors.Add(("{0} has invalid Maturity: {1}" -f $file.Name, [string]$metadata["Maturity"]))
        }

        if ([string]$metadata["Last reviewed"] -notmatch '^\d{4}-\d{2}-\d{2}$') {
            $lifecycleErrors.Add(("{0} Last reviewed is not YYYY-MM-DD: {1}" -f $file.Name, [string]$metadata["Last reviewed"]))
        }

        if (-not $entriesByFile.ContainsKey($file.Name)) {
            $lifecycleErrors.Add(("{0} is missing from experience index" -f $file.Name))
            continue
        }

        $entry = $entriesByFile[$file.Name]
        $comparisons = [ordered]@{
            maturity = $maturity
            scope = [string]$metadata["Scope"]
            source = [string]$metadata["Source"]
            reviewed_at = [string]$metadata["Last reviewed"]
            decay_policy = [string]$metadata["Decay policy"]
        }
        foreach ($key in $comparisons.Keys) {
            if ([string]$entry.$key -ne [string]$comparisons[$key]) {
                $lifecycleErrors.Add(("{0} index {1} mismatch: markdown='{2}' index='{3}'" -f $file.Name, $key, [string]$comparisons[$key], [string]$entry.$key))
            }
        }
    }

    $searchScriptPath = Join-PathParts $repoRoot "knowledge-hub" "scripts" "search_experience.ps1"
    $searchScriptText = Get-Content -LiteralPath $searchScriptPath -Raw
    if ($searchScriptText -match "last_accessed") {
        $lifecycleErrors.Add("search_experience.ps1 must not implement last_accessed read-path mutation.")
    }

    if ($indexRaw -match "last_accessed") {
        $lifecycleErrors.Add("experience index must not record runtime last_accessed telemetry.")
    }

    $publicSafeMetadataErrors = @(Get-ExperiencePublicSafeMetadataErrors -Registry $index)
    foreach ($metadataError in $publicSafeMetadataErrors) {
        $lifecycleErrors.Add($metadataError)
    }

    if ($lifecycleErrors.Count -gt 0) {
        Add-Check "experience lifecycle metadata" "FAIL" "Experience lifecycle metadata is incomplete or inconsistent." ([ordered]@{
            errors = @($lifecycleErrors.ToArray())
        })
    }
    else {
        Add-Check "experience lifecycle metadata" "PASS" "Experience Markdown lifecycle metadata matches the generated index without search-path telemetry mutation." ([ordered]@{
            index_path = $indexPath
            schema_version = [int]$index.schema_version
            experience_files = @($experienceFiles | ForEach-Object { $_.Name })
            allowed_maturity = @($allowedMaturity)
            search_read_path_mutates_last_accessed = $false
        })
    }
}
catch {
    Add-Check "experience lifecycle metadata" "FAIL" $_.Exception.Message
}

try {
    $tempHub = Join-PathParts $scratchRootFull "experience-promote-hub"
    $tempProject = Join-PathParts $scratchRootFull "experience-promote-project"
    Assert-PathInsideRoot -Path $tempHub -Root $scratchRootFull
    Assert-PathInsideRoot -Path $tempProject -Root $scratchRootFull
    Copy-Item -LiteralPath (Join-PathParts $repoRoot "knowledge-hub") -Destination $tempHub -Recurse -Force
    New-Item -ItemType Directory -Force -Path (Join-PathParts $tempProject ".agents" "context" "experience") | Out-Null

    $candidatePath = Join-PathParts $tempProject ".agents" "context" "experience" "validation-promote-closure.md"
    $aliasesOnlyCandidatePath = Join-PathParts $tempProject ".agents" "context" "experience" "validation-localized-alias-only.md"
	    $candidateText = @"
# 验证晋升闭环

Scope: Cross-project reusable
Global candidate: Yes
Maturity: draft
Source: public-safe release validation fixture
Last reviewed: 2026-07-07
Decay policy: Temporary fixture only; regenerate during release validation and do not promote to public source.

## Summary
仅用于 release validation 的临时跨项目经验；正文和 metadata 值保留中文。

## Keywords
验证, 晋升,

release gate, temporary hub

## Prevention Rule
Validate experience promotion with a temporary hub so the public source tree is not mutated during release checks.
Boundary sentinel: KW_BOUNDARY_S2E8K1
"@
    Set-Content -LiteralPath $candidatePath -Value $candidateText -Encoding UTF8

    $aliasesOnlyCandidateText = @"
# 仅中文别名候选

## 摘要
这条临时经验只使用中文 metadata aliases，不应被默认晋升。

## 关键词
验证, 别名, 临时

范围: 跨项目可复用
全局候选: 是
Maturity: draft
Source: public-safe release validation fixture
Last reviewed: 2026-07-07
Decay policy: Temporary fixture only; regenerate during release validation and do not promote to public source.
"@
    Set-Content -LiteralPath $aliasesOnlyCandidatePath -Value $aliasesOnlyCandidateText -Encoding UTF8
    $aliasesOnlyCandidateHash = (Get-FileHash -LiteralPath $aliasesOnlyCandidatePath -Algorithm SHA256).Hash.ToLowerInvariant()

    $promoteScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "promote_experience.ps1"
    $rebuildScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "rebuild_experience_index.ps1"
    $searchScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "search_experience.ps1"
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        throw "git is required to validate the public worktree experience promotion fixture."
    }
    & git -C $tempHub init | Out-Null

    $promoteOutput = @(& $promoteScript -ProjectDir $tempProject -HubDir $tempHub -ProjectTag "validation")
    $registryPath = Join-PathParts $tempHub "knowledge" "experience" "index.json"
    $promotedRegistry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $promotionMetadataErrors = @(Get-ExperiencePublicSafeMetadataErrors -Registry $promotedRegistry)
    if ($promotionMetadataErrors.Count -gt 0) {
        throw ("Experience promotion wrote unsafe public metadata: {0}" -f ($promotionMetadataErrors -join "; "))
    }

    $promotedEntry = @($promotedRegistry.entries | Where-Object { [string]$_.title -eq "验证晋升闭环" } | Select-Object -First 1)
    if ($promotedEntry.Count -lt 1) {
        throw "Localized validation entry with English anchors was not found in the temporary registry."
    }
    $indexedKeywords = @($promotedEntry[0].keywords | ForEach-Object { [string]$_ })
	    foreach ($keyword in @("验证", "晋升")) {
	        if ($indexedKeywords -notcontains $keyword) {
	            throw ("Promoted localized validation entry is missing indexed Chinese keyword: {0}" -f $keyword)
	        }
	    }
	    foreach ($keyword in @("release gate", "temporary hub")) {
	        if ($indexedKeywords -notcontains $keyword) {
	            throw ("Promoted localized validation entry is missing indexed keyword from multiline block: {0}" -f $keyword)
	        }
	    }
	    if ($indexedKeywords -contains "KW_BOUNDARY_S2E8K1") {
	        throw "Boundary sentinel token KW_BOUNDARY_S2E8K1 leaked into keywords from Prevention Rule section."
	    }
    $promotedPath = Join-PathParts $tempHub "knowledge" "experience" ([string]$promotedEntry[0].hub_file)
    $promotedText = Get-Content -LiteralPath $promotedPath -Raw
    foreach ($anchor in @("## Summary", "## Keywords", "Scope: Cross-project reusable", "Global candidate: Yes", "Maturity:", "Source:", "Last reviewed:", "Decay policy:")) {
        if ($promotedText -notmatch [regex]::Escape($anchor)) {
            throw ("Promoted localized validation entry is missing English anchor: {0}" -f $anchor)
        }
    }
    $aliasesOnlyEntries = @($promotedRegistry.entries | Where-Object {
        [string]$_.title -eq "仅中文别名候选" -or [string]$_.hash_sha256 -eq $aliasesOnlyCandidateHash
    })
    if ($aliasesOnlyEntries.Count -ne 0) {
        throw "Aliases-only localized validation candidate was promoted unexpectedly."
    }
    $promotionSummary = @($promoteOutput | Where-Object { $_ -match '^Promotion summary:' } | Select-Object -First 1)
    if ($promotionSummary.Count -ne 1 -or [string]$promotionSummary[0] -notmatch 'skipped_not_candidate=1\b') {
        throw "Aliases-only localized validation candidate did not increment skipped_not_candidate exactly once."
    }
    $promotedEntry[0] | Add-Member -NotePropertyName "source_project" -NotePropertyValue $tempProject -Force
    $promotedEntry[0] | Add-Member -NotePropertyName "source_file" -NotePropertyValue $candidatePath -Force
    $promotedEntry[0] | Add-Member -NotePropertyName "source_relative_path" -NotePropertyValue ".agents/context/experience/validation-promote-closure.md" -Force
    $promotedRegistry | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $registryPath -Encoding UTF8

    & $rebuildScript -HubDir $tempHub | Out-Host
    $rebuiltRegistry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $rebuildMetadataErrors = @(Get-ExperiencePublicSafeMetadataErrors -Registry $rebuiltRegistry)
    if ($rebuildMetadataErrors.Count -gt 0) {
        throw ("Experience rebuild propagated unsafe public metadata: {0}" -f ($rebuildMetadataErrors -join "; "))
    }
    $rebuiltEntry = @($rebuiltRegistry.entries | Where-Object { [string]$_.hash_sha256 -eq [string]$promotedEntry[0].hash_sha256 } | Select-Object -First 1)
    if ($rebuiltEntry.Count -ne 1) {
        throw "Rebuilt localized validation entry was not found by hash."
    }
    $expectedLifecycle = [ordered]@{
        maturity = "draft"
        scope = "Cross-project reusable"
        source = "public-safe release validation fixture"
        reviewed_at = "2026-07-07"
        decay_policy = "Temporary fixture only; regenerate during release validation and do not promote to public source."
    }
    foreach ($field in $expectedLifecycle.Keys) {
        if ([string]$rebuiltEntry[0].$field -ne [string]$expectedLifecycle[$field]) {
            throw ("Rebuilt localized validation lifecycle field mismatch for {0}: expected '{1}', got '{2}'" -f $field, [string]$expectedLifecycle[$field], [string]$rebuiltEntry[0].$field)
        }
    }

    $registryHashAfterRebuild = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash
    & $rebuildScript -HubDir $tempHub | Out-Host
    $registryHashAfterNoop = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash
    if ($registryHashAfterNoop -ne $registryHashAfterRebuild) {
        throw "No-op experience index rebuild changed the registry file."
    }

    $searchText = & $searchScript -HubDir $tempHub -Query "验证 晋升" -Json
    $search = $searchText | ConvertFrom-Json
    $resultCount = @($search.results).Count
    if ($resultCount -lt 1) {
        throw "Promoted experience could not be found by search."
    }

    $topResult = $search.results[0]
    if ([string]$topResult.title -ne "验证晋升闭环") {
        throw ("Unexpected promoted experience search result: {0}" -f [string]$topResult.title)
    }
    if ([string]::IsNullOrWhiteSpace([string]$topResult.prevention_rule)) {
        throw "Promoted localized experience search result is missing prevention_rule."
    }

    Add-Check "experience promote closure" "PASS" "Localized experience with English anchors promoted, rebuilt, and searched; aliases-only candidate was skipped without mutating public source." ([ordered]@{
        temp_hub = $tempHub
        temp_project = $tempProject
        promote_output = @($promoteOutput)
        public_worktree_fixture = $true
        promotion_public_safe_metadata = $true
        rebuild_dropped_legacy_source_paths = $true
        noop_rebuild_preserved_hash = $true
        localized_body_with_english_anchors_promoted = $true
        localized_keywords_indexed = @($indexedKeywords)
        aliases_only_candidate_skipped = $true
        aliases_only_registry_entry_count = $aliasesOnlyEntries.Count
        skipped_not_candidate = 1
        rebuilt_lifecycle_metadata = $expectedLifecycle
        search_prevention_rule_present = $true
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
        @("knowledge-hub/scripts/promote_experience.ps1", "skills/project-bootstrap/scripts/promote_experience.ps1"),
        @("knowledge-hub/scripts/manage_candidates.ps1", "skills/project-bootstrap/scripts/manage_candidates.ps1")
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
