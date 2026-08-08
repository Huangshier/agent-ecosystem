# Internal Catalog validation, invalidation, rebuild, and cache-write responsibilities.
# This file is dot-sourced only by project-workspace.ps1; discover remains the sole caller of writes.

# Get-CatalogReadResult: load only the discardable local cache; never repairs it.
function Get-CatalogReadResult {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $path = Assert-ProjectPath -Root $Root -RelativePath $catalogRelativePath -AllowMissing
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [ordered]@{ state = "missing"; path = $catalogRelativePath; payload = $null }
    }
    try {
        $text = Read-StrictUtf8Text -Path $path
        if ([string]::IsNullOrWhiteSpace($text)) { throw "empty catalog" }
        $payload = $text | ConvertFrom-Json -Depth 50 -DateKind String -NoEnumerate -ErrorAction Stop
        return [ordered]@{ state = "present"; path = $catalogRelativePath; payload = $payload }
    }
    catch {
        Add-Finding -Findings $Findings -Code "catalog-invalid" -Path $catalogRelativePath -Message "Catalog cache is missing valid UTF-8 JSON and must be rebuilt by discover."
        return [ordered]@{ state = "invalid"; path = $catalogRelativePath; payload = $null }
    }
}

# Test-CatalogJsonObject: recognize only JSON object shapes emitted by ConvertFrom-Json.
function Test-CatalogJsonObject {
    param([AllowNull()][object]$Value)

    return ($null -ne $Value -and ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]))
}

# Test-CatalogJsonArray: distinguish an actual JSON array from a scalar object.
function Test-CatalogJsonArray {
    param([AllowNull()][object]$Value)

    return ($null -ne $Value -and $Value -is [System.Array] -and $Value -isnot [byte[]])
}

# Test-CatalogJsonInteger: reject strings, booleans, and fractional JSON numbers.
function Test-CatalogJsonInteger {
    param([AllowNull()][object]$Value)

    return ($Value -is [sbyte] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64])
}

# Test-CatalogShape: validate the complete cache contract without trusting coercions.
function Test-CatalogShape {
    param(
        [object]$Catalog,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $findingStart = $Findings.Count
    if (-not (Test-CatalogJsonObject -Value $Catalog)) {
        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "" -Message "Catalog root must be a JSON object."
        return $false
    }

    $allowedCatalogFields = @("schema", "schema_version", "generated_by", "directory_fingerprint", "schema_fingerprint", "glossary_fingerprint", "asset_count", "assets")
    $catalogFields = @(Get-PropertyNames -Object $Catalog)
    foreach ($propertyName in $catalogFields) {
        if ($allowedCatalogFields -cnotcontains $propertyName) {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field $propertyName -Message "Catalog contains an unsupported top-level field."
        }
    }
    foreach ($field in $allowedCatalogFields) {
        if ($catalogFields -cnotcontains $field) {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field $field -Message "Catalog is missing a required field."
        }
    }

    $schema = Get-PropertyValue $Catalog "schema"
    if ($schema -isnot [string] -or [string]$schema -cne "agent-ecosystem/catalog/v1") {
        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "schema" -Message "Catalog schema identity is unsupported."
    }
    $schemaVersion = Get-PropertyValue $Catalog "schema_version"
    if (-not (Test-CatalogJsonInteger -Value $schemaVersion) -or [long]$schemaVersion -ne 1) {
        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "schema_version" -Message "Catalog schema_version must be integer 1."
    }
    $generatedBy = Get-PropertyValue $Catalog "generated_by"
    if ($generatedBy -isnot [string] -or [string]$generatedBy -cne "project-workspace-discover") {
        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "generated_by" -Message "Catalog generator identity is unsupported."
    }
    foreach ($hashField in @("directory_fingerprint", "schema_fingerprint")) {
        $hashValue = Get-PropertyValue $Catalog $hashField
        if ($hashValue -isnot [string] -or [string]$hashValue -notmatch '^sha256:[0-9a-f]{64}$') {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field $hashField -Message "Catalog fingerprint is not a valid SHA-256 value."
        }
    }
    $glossaryFingerprint = Get-PropertyValue $Catalog "glossary_fingerprint"
    if ($glossaryFingerprint -isnot [string] -or [string]$glossaryFingerprint -notmatch '^(?:absent|sha256:[0-9a-f]{64})$') {
        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "glossary_fingerprint" -Message "Catalog glossary fingerprint is invalid."
    }

    $assetsValue = Get-PropertyValue $Catalog "assets"
    if (-not (Test-CatalogJsonArray -Value $assetsValue)) {
        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "assets" -Message "Catalog assets must be a JSON array."
        return ($Findings.Count -eq $findingStart)
    }
    # NOTE: Iterate the outer JSON array directly. Recursive flattening would
    # turn a contract-invalid nested array into an apparently valid record.
    $assets = $assetsValue
    $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $seenIdentities = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $allowedAssetFields = @("type", "id", "path", "schema", "status", "title", "summary", "updated", "keywords", "kind", "exposure", "triggers", "side_effects", "related_work", "supersedes", "git", "size", "mtime", "content_hash")
    $requiredAssetFields = @("type", "id", "path", "schema", "status", "title", "summary", "keywords", "size", "mtime", "content_hash")
    $assetIndex = 0
    foreach ($asset in $assets) {
        $assetField = "assets[{0}]" -f $assetIndex
        $assetIndex++
        if (-not (Test-CatalogJsonObject -Value $asset)) {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field $assetField -Message "Catalog asset records must be JSON objects."
            continue
        }
        $assetFields = @(Get-PropertyNames -Object $asset)
        foreach ($propertyName in $assetFields) {
            if ($allowedAssetFields -cnotcontains $propertyName) {
                Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.{1}" -f $assetField, $propertyName) -Message "Catalog asset contains an unsupported field."
            }
        }
        foreach ($field in $requiredAssetFields) {
            if ($assetFields -cnotcontains $field) {
                Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.{1}" -f $assetField, $field) -Message "Catalog asset record is missing a required field."
            }
        }

        foreach ($field in @("type", "id", "path", "schema", "status", "title", "summary", "mtime")) {
            if ($assetFields -ccontains $field -and (Get-PropertyValue $asset $field) -isnot [string]) {
                Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.{1}" -f $assetField, $field) -Message "Catalog scalar field must be a string."
            }
        }
        foreach ($field in @("updated", "kind", "exposure")) {
            if ($assetFields -ccontains $field -and (Get-PropertyValue $asset $field) -isnot [string]) {
                Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.{1}" -f $assetField, $field) -Message "Optional Catalog scalar field must be a string."
            }
        }

        $type = [string](Get-PropertyValue $asset "type")
        $id = [string](Get-PropertyValue $asset "id")
        $path = [string](Get-PropertyValue $asset "path")
        $assetSchema = [string](Get-PropertyValue $asset "schema")
        if ($type -notin @("work", "context", "procedure", "skill", "spec")) {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.type" -f $assetField) -Message "Catalog asset type is unsupported."
        }
        if ($id -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.id" -f $assetField) -Message "Catalog asset id is not stable kebab-case."
        }
        $expectedSchemas = @{ work = "agent-ecosystem/work-item/v1"; context = "agent-ecosystem/context/v1"; procedure = "agent-ecosystem/procedure/v1"; skill = "agent-ecosystem/skill/v1"; spec = "agent-ecosystem/spec/v1" }
        if ($expectedSchemas.ContainsKey($type) -and $assetSchema -cne [string]$expectedSchemas[$type]) {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.schema" -f $assetField) -Message "Catalog asset schema does not match its type."
        }
        $expectedPath = switch ($type) {
            "work" { ".agents/work/{0}.md" -f $id }
            "context" { ".agents/context/{0}.md" -f $id }
            "procedure" { ".agents/procedures/{0}.md" -f $id }
            "skill" { ".agents/skills/{0}/SKILL.md" -f $id }
            "spec" { "docs/specs/{0}/spec.md" -f $id }
            default { "" }
        }
        if ([string]::IsNullOrWhiteSpace($expectedPath) -or $path -cne $expectedPath) {
            Add-Finding -Findings $Findings -Code "catalog-path" -Path $catalogRelativePath -Field ("{0}.path" -f $assetField) -Message "Catalog asset path does not match its canonical type and id."
        }
        if (-not (Test-PublicSafeText -Text $path) -or -not (Test-PublicSafeText -Text $id)) {
            Add-Finding -Findings $Findings -Code "unsafe-output" -Path $catalogRelativePath -Field $assetField -Message "Catalog contains disallowed path or identity text."
        }
        if (-not $seenPaths.Add($path)) {
            Add-Finding -Findings $Findings -Code "catalog-duplicate" -Path $catalogRelativePath -Field ("{0}.path" -f $assetField) -Message "Catalog asset paths must be unique."
        }
        $identity = "{0}:{1}" -f $type, $id
        if (-not $seenIdentities.Add($identity)) {
            Add-Finding -Findings $Findings -Code "catalog-duplicate" -Path $catalogRelativePath -Field ("{0}.id" -f $assetField) -Message "Catalog asset identities must be unique."
        }

        $size = Get-PropertyValue $asset "size"
        if (-not (Test-CatalogJsonInteger -Value $size) -or [long]$size -lt 0) {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.size" -f $assetField) -Message "Catalog asset size must be a non-negative integer."
        }
        $mtime = Get-PropertyValue $asset "mtime"
        if ($mtime -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$mtime)) {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.mtime" -f $assetField) -Message "Catalog asset mtime must be non-empty string metadata."
        }
        $contentHash = Get-PropertyValue $asset "content_hash"
        if ($contentHash -isnot [string] -or [string]$contentHash -notmatch '^sha256:[0-9a-f]{64}$') {
            Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.content_hash" -f $assetField) -Message "Catalog content hash is invalid."
        }

        foreach ($textField in @("schema", "status", "title", "summary", "updated", "kind", "exposure", "mtime")) {
            if ($assetFields -ccontains $textField -and (Get-PropertyValue $asset $textField) -is [string] -and -not (Test-PublicSafeText -Text ([string](Get-PropertyValue $asset $textField)))) {
                Add-Finding -Findings $Findings -Code "unsafe-output" -Path $catalogRelativePath -Field ("{0}.{1}" -f $assetField, $textField) -Message "Catalog text contains disallowed path or sensitive material."
            }
        }
        foreach ($listField in @("keywords", "triggers", "side_effects", "related_work", "supersedes")) {
            if ($assetFields -cnotcontains $listField) { continue }
            $listValue = Get-PropertyValue $asset $listField
            if (-not (Test-CatalogJsonArray -Value $listValue)) {
                Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.{1}" -f $assetField, $listField) -Message "Catalog list fields must be JSON arrays."
                continue
            }
            $valueIndex = 0
            foreach ($value in $listValue) {
                $valueField = "{0}.{1}[{2}]" -f $assetField, $listField, $valueIndex
                $valueIndex++
                if ($value -isnot [string]) {
                    Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field $valueField -Message "Catalog list values must be strings."
                    continue
                }
                if (-not (Test-PublicSafeText -Text ([string]$value))) {
                    Add-Finding -Findings $Findings -Code "unsafe-output" -Path $catalogRelativePath -Field $valueField -Message "Catalog list text contains disallowed path or sensitive material."
                }
            }
        }

        if ($assetFields -ccontains "git") {
            $cachedGit = Get-PropertyValue $asset "git"
            if (-not (Test-CatalogJsonObject -Value $cachedGit)) {
                Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field ("{0}.git" -f $assetField) -Message "Catalog Git anchors must be JSON objects."
            }
            else {
                $allowedGitFields = @("branch", "worktree", "last_verified_commit")
                foreach ($propertyName in @(Get-PropertyNames -Object $cachedGit)) {
                    $gitField = "{0}.git.{1}" -f $assetField, $propertyName
                    if ($allowedGitFields -cnotcontains $propertyName) {
                        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field $gitField -Message "Catalog Git anchor contains an unsupported field."
                        continue
                    }
                    $value = Get-PropertyValue $cachedGit $propertyName
                    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$value)) {
                        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field $gitField -Message "Catalog Git anchor values must be non-empty strings."
                        continue
                    }
                    if (-not (Test-PublicSafeText -Text ([string]$value))) {
                        Add-Finding -Findings $Findings -Code "unsafe-output" -Path $catalogRelativePath -Field $gitField -Message "Catalog Git anchor contains disallowed path or sensitive material."
                    }
                    if ($propertyName -ceq "worktree" -and -not (Test-SafeProjectRelativePath -Path ([string]$value))) {
                        Add-Finding -Findings $Findings -Code "catalog-path" -Path $catalogRelativePath -Field $gitField -Message "Catalog Git worktree anchor must be project-relative."
                    }
                }
            }
        }
    }

    $assetCount = Get-PropertyValue $Catalog "asset_count"
    if (-not (Test-CatalogJsonInteger -Value $assetCount) -or [long]$assetCount -lt 0 -or [long]$assetCount -ne $assets.Count) {
        Add-Finding -Findings $Findings -Code "catalog-schema" -Path $catalogRelativePath -Field "asset_count" -Message "Catalog asset_count must be a non-negative integer equal to assets length."
    }
    return ($Findings.Count -eq $findingStart)
}

# Convert-ParserAssetsToCatalog: turn Slice A parser output into cache records.
function Convert-ParserAssetsToCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FileRecords,
        [string[]]$Paths = @(),
        [AllowNull()][object]$ParserInvocation = $null,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $invocation = if ($null -ne $ParserInvocation) { $ParserInvocation } else { Invoke-CanonicalParser -Root $Root -Paths $Paths }
    if ($null -eq $invocation.payload) {
        Add-Finding -Findings $Findings -Code "canonical-parser" -Path "" -Message "Canonical parser did not return structured JSON."
        return [ordered]@{ success = $false; records = @() }
    }
    $payload = $invocation.payload
    if ([string]$payload.status -cne "PASS") {
        foreach ($finding in @($payload.findings)) {
            Add-Finding -Findings $Findings -Code ("canonical-{0}" -f [string]$finding.code) -Path ([string]$finding.path) -Field ([string]$finding.field) -Message "Canonical Markdown parser rejected an asset."
        }
        if (@($payload.findings).Count -eq 0) { Add-Finding -Findings $Findings -Code "canonical-parser" -Path "" -Message "Canonical parser reported FAIL without a finding." }
        return [ordered]@{ success = $false; records = @() }
    }
    $byPath = @{}
    foreach ($fileRecord in @($FileRecords)) { $byPath[[string]$fileRecord.path] = $fileRecord }
    $records = New-Object 'System.Collections.Generic.List[object]'
    foreach ($asset in @(Get-ValueArray -Value $payload.assets)) {
        $path = [string]$asset.path
        if (-not $byPath.ContainsKey($path)) {
            Add-Finding -Findings $Findings -Code "canonical-path" -Path $path -Message "Canonical parser returned an asset outside the enumerated project roots."
            continue
        }
        $record = Get-AssetCatalogRecord -Asset $asset -FileRecord $byPath[$path] -Findings $Findings
        if ($null -ne $record) { [void]$records.Add($record) }
    }
    if ($records.Count -ne @($FileRecords | Where-Object { @($Paths).Count -eq 0 -or $Paths -contains $_.path }).Count) {
        Add-Finding -Findings $Findings -Code "canonical-count" -Path "" -Message "Canonical parser asset count does not match the requested canonical file set."
    }
    return [ordered]@{ success = ($Findings.Count -eq 0); records = @($records.ToArray() | Sort-Object path) }
}

# Test-CatalogMatchesFiles: compare the cache's cheap directory view with the current tree.
function Test-CatalogMatchesFiles {
    param(
        [Parameter(Mandatory = $true)][object]$Catalog,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FileRecords
    )

    $assets = @(Get-ValueArray -Value (Get-PropertyValue $Catalog "assets"))
    if ($assets.Count -ne @($FileRecords).Count) { return $false }
    $byPath = @{}
    foreach ($asset in $assets) { $byPath[[string](Get-PropertyValue $asset "path")] = $asset }
    foreach ($fileRecord in @($FileRecords)) {
        $path = [string]$fileRecord.path
        if (-not $byPath.ContainsKey($path)) { return $false }
        $asset = $byPath[$path]
        if ([long](Get-PropertyValue $asset "size") -ne [long]$fileRecord.size) { return $false }
        if ([string](Get-PropertyValue $asset "mtime") -cne [string]$fileRecord.mtime) { return $false }
        if ([string](Get-PropertyValue $asset "type") -cne [string]$fileRecord.type) { return $false }
    }
    return $true
}

# Get-ChangedCanonicalPaths: identify files that need a parser/hash pass for incremental rebuilds.
function Get-ChangedCanonicalPaths {
    param(
        [Parameter(Mandatory = $true)][object]$Catalog,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FileRecords
    )

    $oldByPath = @{}
    foreach ($asset in @(Get-ValueArray -Value (Get-PropertyValue $Catalog "assets"))) { $oldByPath[[string](Get-PropertyValue $asset "path")] = $asset }
    $changed = New-Object 'System.Collections.Generic.List[string]'
    foreach ($fileRecord in @($FileRecords)) {
        $path = [string]$fileRecord.path
        if (-not $oldByPath.ContainsKey($path)) { [void]$changed.Add($path); continue }
        $old = $oldByPath[$path]
        if ([string](Get-PropertyValue $old "type") -cne [string]$fileRecord.type -or
            [long](Get-PropertyValue $old "size") -ne [long]$fileRecord.size -or
            [string](Get-PropertyValue $old "mtime") -cne [string]$fileRecord.mtime) {
            [void]$changed.Add($path)
        }
    }
    return @($changed.ToArray() | Sort-Object)
}

# Merge-IncrementalCatalog: reuse unchanged public records and replace only changed files.
function Merge-IncrementalCatalog {
    param(
        [Parameter(Mandatory = $true)][object]$OldCatalog,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FileRecords,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ChangedRecords
    )

    $changedByPath = @{}
    foreach ($record in @($ChangedRecords)) { $changedByPath[[string]$record.path] = $record }
    $oldByPath = @{}
    foreach ($record in @(Get-ValueArray -Value (Get-PropertyValue $OldCatalog "assets"))) { $oldByPath[[string](Get-PropertyValue $record "path")] = $record }
    $merged = New-Object 'System.Collections.Generic.List[object]'
    foreach ($fileRecord in @($FileRecords | Sort-Object path)) {
        $path = [string]$fileRecord.path
        if ($changedByPath.ContainsKey($path)) { [void]$merged.Add($changedByPath[$path]); continue }
        if ($oldByPath.ContainsKey($path)) { [void]$merged.Add($oldByPath[$path]); continue }
    }
    return @($merged.ToArray() | Sort-Object path)
}

# New-CatalogPayload: construct deterministic JSON with no generation timestamp or absolute path.
function New-CatalogPayload {
    param(
        [Parameter(Mandatory = $true)][string]$DirectoryFingerprint,
        [Parameter(Mandatory = $true)][string]$SchemaFingerprint,
        [Parameter(Mandatory = $true)][string]$GlossaryFingerprint,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Assets
    )

    $orderedAssets = @($Assets | Sort-Object path, type, id)
    return [ordered]@{
        schema = "agent-ecosystem/catalog/v1"
        schema_version = 1
        generated_by = "project-workspace-discover"
        directory_fingerprint = $DirectoryFingerprint
        schema_fingerprint = $SchemaFingerprint
        glossary_fingerprint = $GlossaryFingerprint
        asset_count = $orderedAssets.Count
        assets = @($orderedAssets)
    }
}

# Write-CatalogAtomic: the only write path in Slice B, reachable only from discover.
function Write-CatalogAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object]$Catalog
    )

    $target = Assert-ProjectPath -Root $Root -RelativePath $catalogRelativePath -AllowMissing
    $rootPhysical = Resolve-ExistingPhysicalPath -Path $Root -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    $targetPhysical = Resolve-PhysicalPathForWrite -Path $target
    if (-not (Test-PathIsEqualOrChild -Path $targetPhysical -Root $rootPhysical)) { throw "catalog write path escapes the project root" }
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $parentPhysical = Resolve-ExistingPhysicalPath -Path $parent -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    if (-not (Test-PathIsEqualOrChild -Path $parentPhysical -Root $rootPhysical)) { throw "catalog cache directory escapes the project root" }
    $temp = Join-Path $parent (".catalog.{0}.{1}.tmp" -f $PID, ([guid]::NewGuid().ToString("N")))
    try {
        $json = $Catalog | ConvertTo-Json -Depth 50
        [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $target -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force }
    }
}

# Test-CatalogRecordEquality: compare generated metadata with the discardable cache record.
function Test-CatalogRecordEquality {
    param(
        [Parameter(Mandatory = $true)][object]$Left,
        [Parameter(Mandatory = $true)][object]$Right,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    foreach ($field in @("type", "id", "path", "schema", "status", "title", "summary", "updated", "kind", "exposure", "size", "mtime", "content_hash")) {
        if ([string](Get-PropertyValue $Left $field) -cne [string](Get-PropertyValue $Right $field)) {
            Add-Finding -Findings $Findings -Code "catalog-content-field" -Path ([string](Get-PropertyValue $Left "path")) -Field $field -Message "Catalog scalar field differs from canonical Markdown."
            return $false
        }
    }
    foreach ($field in @("keywords", "triggers", "side_effects", "related_work", "supersedes")) {
        $leftValues = @(Get-ValueArray -Value (Get-PropertyValue $Left $field) | ForEach-Object { [string]$_ })
        $rightValues = @(Get-ValueArray -Value (Get-PropertyValue $Right $field) | ForEach-Object { [string]$_ })
        if (($leftValues -join "`n") -cne ($rightValues -join "`n")) {
            Add-Finding -Findings $Findings -Code "catalog-content-field" -Path ([string](Get-PropertyValue $Left "path")) -Field $field -Message "Catalog list field differs from canonical Markdown."
            return $false
        }
    }
    $leftGit = Get-PropertyValue $Left "git"
    $rightGit = Get-PropertyValue $Right "git"
    if (($null -eq $leftGit) -ne ($null -eq $rightGit)) {
        Add-Finding -Findings $Findings -Code "catalog-content-field" -Path ([string](Get-PropertyValue $Left "path")) -Field "git" -Message "Catalog Git anchor differs from canonical Markdown."
        return $false
    }
    if ($null -ne $leftGit) {
        foreach ($field in @("branch", "worktree", "last_verified_commit")) {
            if ([string](Get-PropertyValue $leftGit $field) -cne [string](Get-PropertyValue $rightGit $field)) {
                Add-Finding -Findings $Findings -Code "catalog-content-field" -Path ([string](Get-PropertyValue $Left "path")) -Field ("git.{0}" -f $field) -Message "Catalog Git anchor differs from canonical Markdown."
                return $false
            }
        }
    }
    return $true
}

# New-CacheSummary: expose cache state without returning cache contents or local paths.
function New-CacheSummary {
    param(
        [Parameter(Mandatory = $true)][object]$ReadResult,
        [string]$Action = "not-written",
        [object]$Catalog = $null,
        [Nullable[bool]]$Fresh = $null,
        [string]$Reason = ""
    )

    $summary = [ordered]@{
        path = $catalogRelativePath
        state = [string]$ReadResult.state
        action = $Action
        read_only = ($Action -eq "not-written" -or $Action -eq "reused")
    }
    if ($null -ne $Fresh) { $summary.fresh = [bool]$Fresh }
    if (-not [string]::IsNullOrWhiteSpace($Reason)) { $summary.reason = $Reason }
    if ($null -ne $Catalog) {
        $summary.asset_count = [int](Get-PropertyValue $Catalog "asset_count")
        $summary.directory_fingerprint = [string](Get-PropertyValue $Catalog "directory_fingerprint")
        $summary.schema_fingerprint = [string](Get-PropertyValue $Catalog "schema_fingerprint")
        $summary.glossary_fingerprint = [string](Get-PropertyValue $Catalog "glossary_fingerprint")
    }
    return $summary
}
