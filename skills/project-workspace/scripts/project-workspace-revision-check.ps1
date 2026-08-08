# Internal canonical-reference, revision, and strictly read-only check responsibilities.
# This file is dot-sourced only by project-workspace.ps1.

# Get-CanonicalReferenceChecks: validate the currently defined canonical ID
# edges without repairing source metadata or the disposable Catalog cache.
function Get-CanonicalReferenceChecks {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Assets,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $identitySet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $typesById = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($asset in @($Assets)) {
        $type = [string](Get-PropertyValue $asset "type")
        $id = [string](Get-PropertyValue $asset "id")
        if ($type -notin @("work", "context", "procedure", "spec") -or [string]::IsNullOrWhiteSpace($id)) { continue }
        [void]$identitySet.Add(("{0}`0{1}" -f $type, $id))
        if (-not $typesById.ContainsKey($id)) {
            $typesById[$id] = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        }
        [void]$typesById[$id].Add($type)
    }

    $checks = New-Object 'System.Collections.Generic.List[object]'
    $referenceContract = [ordered]@{
        spec = @(
            [ordered]@{ field = "related_work"; expected_type = "work" },
            [ordered]@{ field = "supersedes"; expected_type = "spec" }
        )
    }
    foreach ($asset in @($Assets | Sort-Object path, type, id)) {
        $sourceType = [string](Get-PropertyValue $asset "type")
        if (-not $referenceContract.Contains($sourceType)) { continue }
        $sourceId = [string](Get-PropertyValue $asset "id")
        $sourcePath = [string](Get-PropertyValue $asset "path")
        $metadata = Get-PropertyValue $asset "metadata"
        if ($null -eq $metadata) { continue }
        $metadataFields = @(Get-PropertyNames -Object $metadata)

        foreach ($contract in @($referenceContract[$sourceType])) {
            $field = [string]$contract.field
            $expectedType = [string]$contract.expected_type
            if ($metadataFields -cnotcontains $field) { continue }
            $values = Get-PropertyValue $metadata $field
            if (-not (Test-CatalogJsonArray -Value $values)) {
                Add-Finding -Findings $Findings -Code "reference-wrong-type" -Path $sourcePath -Field $field -Message "Canonical reference fields must be JSON-compatible lists of canonical IDs."
                [void]$checks.Add([ordered]@{
                    source_type = $sourceType
                    source_id = $sourceId
                    path = $sourcePath
                    field = $field
                    ordinal = 0
                    target_id = ""
                    expected_type = $expectedType
                    state = "wrong_type"
                    finding_codes = @("reference-wrong-type")
                })
                continue
            }

            $seenTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            $ordinal = 0
            foreach ($value in $values) {
                $fieldPath = "{0}[{1}]" -f $field, $ordinal
                $codes = New-Object 'System.Collections.Generic.List[string]'
                $targetId = ""
                if ($value -isnot [string]) {
                    Add-Finding -Findings $Findings -Code "reference-wrong-type" -Path $sourcePath -Field $fieldPath -Message "Canonical reference values must be string IDs."
                    [void]$codes.Add("reference-wrong-type")
                }
                else {
                    $targetId = [string]$value
                    if (-not $seenTargets.Add($targetId)) {
                        Add-Finding -Findings $Findings -Code "reference-duplicate" -Path $sourcePath -Field $fieldPath -Message "Canonical reference lists must not repeat an ID."
                        [void]$codes.Add("reference-duplicate")
                    }
                    if ($sourceType -ceq $expectedType -and $sourceId -ceq $targetId) {
                        Add-Finding -Findings $Findings -Code "reference-self" -Path $sourcePath -Field $fieldPath -Message "Canonical references must not target the source asset itself."
                        [void]$codes.Add("reference-self")
                    }
                    $targetIdentity = "{0}`0{1}" -f $expectedType, $targetId
                    if (-not $identitySet.Contains($targetIdentity)) {
                        if ($typesById.ContainsKey($targetId)) {
                            Add-Finding -Findings $Findings -Code "reference-wrong-type" -Path $sourcePath -Field $fieldPath -Message "Canonical reference ID exists only under a different asset type."
                            [void]$codes.Add("reference-wrong-type")
                        }
                        else {
                            Add-Finding -Findings $Findings -Code "reference-missing" -Path $sourcePath -Field $fieldPath -Message "Canonical reference target is missing."
                            [void]$codes.Add("reference-missing")
                        }
                    }
                }

                $state = if ($codes.Contains("reference-wrong-type")) {
                    "wrong_type"
                }
                elseif ($codes.Contains("reference-self")) {
                    "self_reference"
                }
                elseif ($codes.Contains("reference-duplicate")) {
                    "duplicate"
                }
                elseif ($codes.Contains("reference-missing")) {
                    "missing"
                }
                else {
                    "resolved"
                }
                [void]$checks.Add([ordered]@{
                    source_type = $sourceType
                    source_id = $sourceId
                    path = $sourcePath
                    field = $field
                    ordinal = $ordinal
                    target_id = $targetId
                    expected_type = $expectedType
                    state = $state
                    finding_codes = @($codes.ToArray())
                })
                $ordinal++
            }
        }
    }
    return @($checks.ToArray() | Sort-Object path, field, ordinal, expected_type, target_id)
}

# Get-RevisionChecks: validate Work revision hashes without writing the source file or cache.
function Get-RevisionChecks {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Assets,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $checks = New-Object 'System.Collections.Generic.List[object]'
    foreach ($asset in @($Assets | Where-Object { [string](Get-PropertyValue $_ "type") -ceq "work" } | Sort-Object path)) {
        $path = [string](Get-PropertyValue $asset "path")
        $fullPath = Assert-ProjectPath -Root $Root -RelativePath $path
        $metadata = Get-PropertyValue $asset "metadata"
        $expected = [string](Get-PropertyValue $metadata "revision")
        if ([string]::IsNullOrWhiteSpace($expected)) {
            $expected = ""
            $state = "revision_missing"
            Add-Finding -Findings $Findings -Code "revision_missing" -Path $path -Field "revision" -Message "Work item revision is missing."
            $actual = ""
        }
        else {
            try { $actual = Get-RevisionHash -Path $fullPath }
            catch {
                $actual = ""
                Add-Finding -Findings $Findings -Code "revision_invalid" -Path $path -Field "revision" -Message "Work item revision could not be normalized as UTF-8 content."
            }
            $state = if ($actual -ceq $expected) { "revision_match" } else { "revision_mismatch" }
            if ($state -eq "revision_mismatch") { Add-Finding -Findings $Findings -Code "revision_mismatch" -Path $path -Field "revision" -Message "Work item revision does not match normalized source content." }
        }
        [void]$checks.Add([ordered]@{ path = $path; expected_revision = $expected; actual_revision = $actual; state = $state })
    }
    return @($checks.ToArray())
}

# Invoke-CheckOperation: strict read-only validation of source, cache, Git, and Work revisions.
function Invoke-CheckOperation {
    param([Parameter(Mandatory = $true)][string]$Root)

    $findings = New-Object 'System.Collections.Generic.List[object]'
    $rootFull = Get-NormalizedFullPath -Path $Root
    try {
        if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) { throw "project root is not a directory" }
    }
    catch { Add-Finding -Findings $findings -Code "project-root-invalid" -Path "" -Message "Project root does not exist or is not a safe directory." }
    $canonicalFileRecords = @()
    $skillFileRecords = @()
    try { $canonicalFileRecords = @(Get-CanonicalFileRecords -Root $rootFull -Findings $findings) }
    catch { Add-Finding -Findings $findings -Code "canonical-enumeration" -Path "" -Message "Canonical project assets could not be enumerated safely." }
    try { $skillFileRecords = @(Get-PromotedSkillFileRecords -Root $rootFull -Findings $findings) }
    catch { Add-Finding -Findings $findings -Code "skill-enumeration" -Path "" -Message "Promoted Skill projections could not be enumerated safely." }
    $fileRecords = @($canonicalFileRecords) + @($skillFileRecords)
    $directoryFingerprint = ""
    $schemaFingerprint = ""
    try { $directoryFingerprint = Get-DirectoryFingerprint -Records $fileRecords } catch { Add-Finding -Findings $findings -Code "directory-fingerprint" -Path "" -Message "Canonical directory fingerprint could not be computed." }
    try { Read-SchemaContract -Findings $findings; $schemaFingerprint = Get-SchemaFingerprint } catch { Add-Finding -Findings $findings -Code "schema-invalid" -Path "schemas/project-workspace" -Message "Project workspace schema fingerprint could not be computed." }
    $glossary = Read-Glossary -Root $rootFull -Findings $findings
    $parserInvocation = Invoke-CanonicalParser -Root $rootFull -Paths @()
    $currentRecordsResult = Convert-ParserAssetsToCatalog -Root $rootFull -FileRecords $fileRecords -Paths @() -ParserInvocation $parserInvocation -Findings $findings
    $currentRecords = @($currentRecordsResult.records)
    $references = @()
    if ($null -ne $parserInvocation.payload) {
        $references = @(Get-CanonicalReferenceChecks -Assets @(Get-ValueArray -Value $parserInvocation.payload.assets) -Findings $findings)
    }
    $catalogFindings = New-Object 'System.Collections.Generic.List[object]'
    $catalogRead = $null
    try { $catalogRead = Get-CatalogReadResult -Root $rootFull -Findings $catalogFindings }
    catch { $catalogRead = [ordered]@{ state = "missing"; path = $catalogRelativePath; payload = $null } }
    $catalogShapeValid = $false
    if ($catalogRead.state -eq "present") { $catalogShapeValid = Test-CatalogShape -Catalog $catalogRead.payload -Findings $catalogFindings }
    if ($catalogRead.state -eq "missing") {
        Add-Finding -Findings $findings -Code "catalog-missing" -Path $catalogRelativePath -Message "Catalog cache is absent; discover may rebuild it." -Severity warning
    }
    elseif (-not $catalogShapeValid) {
        foreach ($finding in @($catalogFindings.ToArray())) { [void]$findings.Add($finding) }
    }
    $catalogFresh = $null
    if ($catalogShapeValid) {
        $catalog = $catalogRead.payload
        $fingerprintsMatch = ([string](Get-PropertyValue $catalog "directory_fingerprint") -ceq $directoryFingerprint -and [string](Get-PropertyValue $catalog "schema_fingerprint") -ceq $schemaFingerprint -and [string](Get-PropertyValue $catalog "glossary_fingerprint") -ceq [string]$glossary.fingerprint)
        $catalogFresh = ($fingerprintsMatch -and (Test-CatalogMatchesFiles -Catalog $catalog -FileRecords $fileRecords))
        if (-not $catalogFresh) { Add-Finding -Findings $findings -Code "catalog-stale" -Path $catalogRelativePath -Message "Catalog fingerprints or canonical file metadata are stale." }
        $catalogByPath = @{}
        foreach ($cached in @(Get-ValueArray -Value (Get-PropertyValue $catalog "assets"))) { $catalogByPath[[string](Get-PropertyValue $cached "path")] = $cached }
        foreach ($record in @($currentRecords)) {
            $path = [string]$record.path
            if (-not $catalogByPath.ContainsKey($path) -or -not (Test-CatalogRecordEquality -Left $record -Right $catalogByPath[$path] -Findings $findings)) {
                Add-Finding -Findings $findings -Code "catalog-content" -Path $path -Message "Catalog metadata or content hash differs from canonical Markdown."
            }
        }
    }
    $revisions = @()
    if ($null -ne $parserInvocation.payload -and [string]$parserInvocation.payload.status -ceq "PASS") {
        $revisions = @(Get-RevisionChecks -Root $rootFull -Assets @($parserInvocation.payload.assets) -Findings $findings)
    }
    $gitFindings = New-Object 'System.Collections.Generic.List[object]'
    $git = Get-GitState -Root $rootFull -Findings $gitFindings
    foreach ($finding in @($gitFindings.ToArray())) { [void]$findings.Add($finding) }
    $anchors = New-Object 'System.Collections.Generic.List[object]'
    foreach ($record in @($currentRecords | Where-Object { $null -ne (Get-PropertyValue $_ "git") } | Sort-Object path)) {
        $anchor = Test-GitAnchor -Asset $record -Root $rootFull -GitState $git -Findings $findings
        if ($null -ne $anchor) {
            [void]$anchors.Add([ordered]@{
                path = [string]$record.path
                branch = [string]$anchor.branch
                branch_state = [string]$anchor.branch_state
                worktree_present = $anchor.worktree_present
                worktree_state = [string]$anchor.worktree_state
                commit_presence = [string]$anchor.commit_presence
                commit_state = [string]$anchor.commit_state
            })
        }
    }
    $assetStates = @($currentRecords | Sort-Object path | ForEach-Object { [ordered]@{ type = [string]$_.type; id = [string]$_.id; path = [string]$_.path; state = "canonical_valid" } })
    $catalogSummaryRead = $catalogRead
    $cacheSummary = New-CacheSummary -ReadResult $catalogSummaryRead -Action "not-written" -Catalog $(if ($catalogShapeValid) { $catalogRead.payload } else { $null }) -Fresh $catalogFresh -Reason $(if ($catalogRead.state -eq "missing") { "missing" } elseif (-not $catalogShapeValid) { "invalid" } else { "read_only_check" })
    $output = [ordered]@{
        operation = "check"
        status = Get-OperationStatus -Findings $findings
        read_only = $true
        catalog = $cacheSummary
        glossary = [ordered]@{ state = [string]$glossary.state; fingerprint = [string]$glossary.fingerprint; term_count = @($glossary.terms).Count }
        git = $git
        assets = $assetStates
        references = @($references)
        anchors = @($anchors.ToArray())
        revisions = @($revisions)
        findings = @(Get-SortedFindings -Findings $findings)
    }
    return $output
}
