# Internal Glossary parsing and deterministic query responsibilities for project-workspace.
# This file is dot-sourced only by project-workspace.ps1; it is not a public command.

# Convert a restricted glossary scalar into a public-safe value. Glossary is
# intentionally parsed as a small YAML subset; arbitrary YAML features are not
# needed for discovery and would make fail-closed behavior less predictable.
function Convert-GlossaryScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $text = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        Add-Finding -Findings $Findings -Code "glossary-format" -Path $Path -Message "Glossary scalar values must not be empty."
        return $null
    }
    if ($text -match '[`$]|(?:^|\s)(?:[&*!]|!!|<<?|>>?)(?:\s|$)|[{}\[\]|>]') {
        Add-Finding -Findings $Findings -Code "glossary-unsafe" -Path $Path -Message "Glossary values contain unsupported YAML syntax."
        return $null
    }
    if (($text.StartsWith('"') -and -not $text.EndsWith('"')) -or ($text.StartsWith("'") -and -not $text.EndsWith("'"))) {
        Add-Finding -Findings $Findings -Code "glossary-format" -Path $Path -Message "Glossary quoted values must be closed on the same line."
        return $null
    }
    if (($text.StartsWith('"') -and $text.EndsWith('"')) -or ($text.StartsWith("'") -and $text.EndsWith("'"))) {
        if ($text.Length -lt 2) {
            Add-Finding -Findings $Findings -Code "glossary-format" -Path $Path -Message "Glossary quoted values must contain text."
            return $null
        }
        $text = $text.Substring(1, $text.Length - 2)
        if ($text.Contains('"') -or $text.Contains("'")) {
            Add-Finding -Findings $Findings -Code "glossary-format" -Path $Path -Message "Nested or escaped glossary quotes are not supported."
            return $null
        }
    }
    if (-not (Test-PublicSafeText -Text $text)) {
        Add-Finding -Findings $Findings -Code "glossary-unsafe" -Path $Path -Message "Glossary values contain disallowed path or sensitive material."
        return $null
    }
    return $text
}

# Read-Glossary: parse and validate the evidence-backed, one-level glossary.
function Read-Glossary {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $path = Assert-ProjectPath -Root $Root -RelativePath $glossaryRelativePath -AllowMissing
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [ordered]@{ state = "absent"; fingerprint = "absent"; terms = @(); path = $glossaryRelativePath }
    }

    $glossaryFindingStart = $Findings.Count
    $text = $null
    try { $text = Read-StrictUtf8Text -Path $path }
    catch {
        Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Message "Glossary must be strict UTF-8 text."
        return [ordered]@{ state = "invalid"; fingerprint = ""; terms = @(); path = $glossaryRelativePath }
    }
    $fingerprint = Get-Sha256 -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($text))
    $lines = @($text -split "`n")
    $top = [ordered]@{}
    $terms = New-Object 'System.Collections.Generic.List[object]'
    $current = $null
    $currentField = ""
    $currentValues = $null

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $lineNumber = $index + 1
        $line = [string]$lines[$index]
        if ($line -match "`t") {
            Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary indentation must use spaces, not tabs."
            continue
        }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '#') {
            Add-Finding -Findings $Findings -Code "glossary-unsafe" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary comments are not accepted in the strict input subset."
            continue
        }
        $indent = $line.Length - $line.TrimStart(' ').Length
        if (($indent % 2) -ne 0) {
            Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary indentation must use two-space levels."
            continue
        }
        $content = $line.Substring($indent)
        if ($indent -eq 0) {
            if ($content -notmatch '^([A-Za-z][A-Za-z0-9_-]*):[ ]*(.*)$') {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary top-level entries must use key: value syntax."
                continue
            }
            $key = [string]$Matches[1]
            $value = [string]$Matches[2]
            if ($top.Contains($key)) {
                Add-Finding -Findings $Findings -Code "glossary-conflict" -Path $glossaryRelativePath -Field $key -Message "Glossary top-level keys must be unique."
                continue
            }
            if ($key -eq "schema") {
                $parsed = Convert-GlossaryScalar -Value $value -Path $glossaryRelativePath -Findings $Findings
                if ($null -ne $parsed) { $top[$key] = $parsed }
                continue
            }
            if ($key -eq "terms" -and [string]::IsNullOrWhiteSpace($value)) {
                $top[$key] = $true
                $current = $null
                $currentField = ""
                $currentValues = $null
                continue
            }
            Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field $key -Message "Unsupported glossary top-level field or inline value."
            continue
        }

        if ($indent -eq 2 -and $content -match '^-[ ]+(.*)$') {
            if (-not $top.Contains("terms")) {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary terms must be declared before term entries."
                continue
            }
            $current = [ordered]@{}
            $currentField = ""
            $currentValues = $null
            [void]$terms.Add($current)
            $entry = [string]$Matches[1]
            if ($entry -notmatch '^([A-Za-z][A-Za-z0-9_-]*):[ ]*(.*)$') {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Each glossary term must start with a field."
                continue
            }
            $field = [string]$Matches[1]
            $value = [string]$Matches[2]
            if ($field -notin @("canonical", "aliases", "symbols", "relations", "evidence")) {
                Add-Finding -Findings $Findings -Code "glossary-unknown-field" -Path $glossaryRelativePath -Field $field -Message "Unknown glossary term field."
                continue
            }
            if ($field -eq "canonical" -and -not [string]::IsNullOrWhiteSpace($value)) {
                $parsed = Convert-GlossaryScalar -Value $value -Path $glossaryRelativePath -Findings $Findings
                if ($null -ne $parsed) { $current[$field] = $parsed }
            }
            elseif ([string]::IsNullOrWhiteSpace($value)) {
                if ($field -eq "canonical") {
                    Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field $field -Message "Glossary canonical values must be scalar text."
                }
                else {
                    $current[$field] = New-Object 'System.Collections.Generic.List[string]'
                    $currentField = $field
                    $currentValues = $current[$field]
                }
            }
            else {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field $field -Message "Glossary list fields must use indented list entries."
            }
            continue
        }

        if ($indent -eq 4 -and $content -match '^([A-Za-z][A-Za-z0-9_-]*):[ ]*(.*)$') {
            if ($null -eq $current) {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary term field appears before a term entry."
                continue
            }
            $field = [string]$Matches[1]
            $value = [string]$Matches[2]
            if ($field -notin @("canonical", "aliases", "symbols", "relations", "evidence")) {
                Add-Finding -Findings $Findings -Code "glossary-unknown-field" -Path $glossaryRelativePath -Field $field -Message "Unknown glossary term field."
                continue
            }
            if ($current.Contains($field)) {
                Add-Finding -Findings $Findings -Code "glossary-conflict" -Path $glossaryRelativePath -Field $field -Message "Glossary term fields must be unique."
                continue
            }
            if ($field -eq "canonical") {
                $parsed = Convert-GlossaryScalar -Value $value -Path $glossaryRelativePath -Findings $Findings
                if ($null -ne $parsed) { $current[$field] = $parsed }
                $currentField = ""
                $currentValues = $null
            }
            elseif ([string]::IsNullOrWhiteSpace($value)) {
                $current[$field] = New-Object 'System.Collections.Generic.List[string]'
                $currentField = $field
                $currentValues = $current[$field]
            }
            else {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field $field -Message "Glossary list fields must use indented list entries."
            }
            continue
        }

        if ($indent -eq 6 -and $content -match '^-[ ]+(.*)$') {
            if ($null -eq $currentValues -or [string]::IsNullOrWhiteSpace($currentField)) {
                Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary list item has no active list field."
                continue
            }
            $parsed = Convert-GlossaryScalar -Value ([string]$Matches[1]) -Path $glossaryRelativePath -Findings $Findings
            if ($null -ne $parsed) { [void]$currentValues.Add($parsed) }
            continue
        }

        Add-Finding -Findings $Findings -Code "glossary-format" -Path $glossaryRelativePath -Field ("line.{0}" -f $lineNumber) -Message "Glossary structure is outside the supported strict YAML subset."
    }

    if (-not $top.Contains("schema") -or [string]$top["schema"] -cne "agent-ecosystem/glossary/v1") {
        Add-Finding -Findings $Findings -Code "glossary-schema" -Path $glossaryRelativePath -Field "schema" -Message "Glossary schema must be agent-ecosystem/glossary/v1."
    }
    if (-not $top.Contains("terms") -or $terms.Count -eq 0) {
        Add-Finding -Findings $Findings -Code "glossary-schema" -Path $glossaryRelativePath -Field "terms" -Message "Glossary must contain at least one term."
    }

    $normalizedTerms = New-Object 'System.Collections.Generic.List[object]'
    $owners = @{}
    $canonicalOwners = @{}
    foreach ($term in @($terms.ToArray())) {
        foreach ($field in @("aliases", "symbols", "relations", "evidence")) {
            if (-not $term.Contains($field)) { $term[$field] = New-Object 'System.Collections.Generic.List[string]' }
        }
        if (-not $term.Contains("canonical")) {
            Add-Finding -Findings $Findings -Code "glossary-schema" -Path $glossaryRelativePath -Field "canonical" -Message "Each glossary term requires canonical text."
            continue
        }
        $canonical = [string]$term.canonical
        $canonicalKey = Normalize-SearchText -Text $canonical
        if ([string]::IsNullOrWhiteSpace($canonicalKey)) {
            Add-Finding -Findings $Findings -Code "glossary-schema" -Path $glossaryRelativePath -Field "canonical" -Message "Glossary canonical text must normalize to a non-empty value."
            continue
        }
        if ($canonicalOwners.ContainsKey($canonicalKey)) {
            Add-Finding -Findings $Findings -Code "glossary-conflict" -Path $glossaryRelativePath -Field "canonical" -Message "Glossary canonical terms must be unique after normalization."
        }
        else { $canonicalOwners[$canonicalKey] = $canonical }
        if (@($term.evidence).Count -eq 0) {
            Add-Finding -Findings $Findings -Code "glossary-evidence" -Path $glossaryRelativePath -Field "evidence" -Message "Every glossary term requires direct evidence."
        }
        $keysForTerm = @($canonical) + @($term.aliases) + @($term.symbols)
        foreach ($value in $keysForTerm) {
            $key = Normalize-SearchText -Text ([string]$value)
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if ($owners.ContainsKey($key) -and [string]$owners[$key] -cne $canonical) {
                Add-Finding -Findings $Findings -Code "glossary-conflict" -Path $glossaryRelativePath -Field "terms" -Message "Glossary aliases and symbols must resolve to one canonical term."
            }
            else { $owners[$key] = $canonical }
        }
        foreach ($relation in @($term.relations)) {
            $relationKey = Normalize-SearchText -Text ([string]$relation)
            if ([string]::IsNullOrWhiteSpace($relationKey) -or $relationKey -ceq $canonicalKey) {
                Add-Finding -Findings $Findings -Code "glossary-cycle" -Path $glossaryRelativePath -Field "relations" -Message "Glossary relations must not be empty or self-referential."
            }
        }
        [void]$normalizedTerms.Add([ordered]@{
            canonical = $canonical
            canonical_key = $canonicalKey
            aliases = @($term.aliases | ForEach-Object { [string]$_ })
            symbols = @($term.symbols | ForEach-Object { [string]$_ })
            relations = @($term.relations | ForEach-Object { [string]$_ })
            evidence = @($term.evidence | ForEach-Object { [string]$_ })
        })
    }

    $knownCanonicalKeys = @($canonicalOwners.Keys)
    foreach ($term in @($normalizedTerms.ToArray())) {
        foreach ($relation in @($term.relations)) {
            $relationKey = Normalize-SearchText -Text $relation
            if ($knownCanonicalKeys -notcontains $relationKey) {
                Add-Finding -Findings $Findings -Code "glossary-unknown" -Path $glossaryRelativePath -Field "relations" -Message "Glossary relations must target declared canonical terms."
            }
        }
    }
    $byKey = @{}
    foreach ($term in @($normalizedTerms.ToArray())) { $byKey[$term.canonical_key] = $term }
    $visit = @{}
    function Visit-GlossaryRelation {
        param([string]$Key)
        if ($visit[$Key] -eq "active") {
            Add-Finding -Findings $Findings -Code "glossary-cycle" -Path $glossaryRelativePath -Field "relations" -Message "Glossary relations must not contain cycles."
            return
        }
        if ($visit[$Key] -eq "done" -or -not $byKey.ContainsKey($Key)) { return }
        $visit[$Key] = "active"
        foreach ($relation in @($byKey[$Key].relations)) {
            $relationKey = Normalize-SearchText -Text $relation
            if ($byKey.ContainsKey($relationKey)) { Visit-GlossaryRelation -Key $relationKey }
        }
        $visit[$Key] = "done"
    }
    foreach ($key in @($byKey.Keys | Sort-Object)) { Visit-GlossaryRelation -Key $key }

    if ($Findings.Count -gt $glossaryFindingStart) {
        return [ordered]@{ state = "invalid"; fingerprint = $fingerprint; terms = @(); path = $glossaryRelativePath }
    }
    return [ordered]@{ state = "valid"; fingerprint = $fingerprint; terms = @($normalizedTerms.ToArray()); path = $glossaryRelativePath }
}

# Get-AssetCorpus: build a deterministic search surface from catalog metadata only.
function Get-AssetCorpus {
    param([Parameter(Mandatory = $true)][object]$Asset)

    $values = New-Object 'System.Collections.Generic.List[string]'
    foreach ($field in @("id", "path", "schema", "status", "title", "summary", "updated", "kind", "exposure")) {
        $value = [string](Get-PropertyValue $Asset $field)
        if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$values.Add($value) }
    }
    foreach ($field in @("keywords", "triggers", "side_effects", "related_work", "supersedes")) {
        foreach ($value in @(Get-ValueArray -Value (Get-PropertyValue $Asset $field))) {
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { [void]$values.Add([string]$value) }
        }
    }
    return @($values.ToArray())
}

# Get-GlossaryExpansion: resolve only persisted canonical terms and one relation hop.
function Get-GlossaryExpansion {
    param(
        [Parameter(Mandatory = $true)][object]$Glossary,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Query,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][string[]]$QueryTerms
    )

    $expanded = New-Object 'System.Collections.Generic.List[object]'
    if ($Glossary.state -cne "valid" -or [string]::IsNullOrWhiteSpace($Query)) { return @() }
    $terms = @($Glossary.terms)
    $byCanonical = @{}
    foreach ($term in $terms) { $byCanonical[[string]$term.canonical_key] = $term }
    foreach ($term in $terms) {
        $canonicalMatched = Test-TextMatch -Candidate ([string]$term.canonical) -QueryTerms @($QueryTerms)
        $aliasMatched = @($term.aliases | Where-Object { Test-TextMatch -Candidate ([string]$_) -QueryTerms @($QueryTerms) }).Count -gt 0
        $symbolMatched = @($term.symbols | Where-Object { Test-TextMatch -Candidate ([string]$_) -QueryTerms @($QueryTerms) }).Count -gt 0
        $relationMatched = @($term.relations | Where-Object { Test-TextMatch -Candidate ([string]$_) -QueryTerms @($QueryTerms) }).Count -gt 0
        if ($canonicalMatched -or $aliasMatched -or $symbolMatched -or $relationMatched) {
            # NOTE: A term can match through multiple glossary surfaces. The
            # public reason precedence is direct > alias > symbol > relation.
            $reason = if ($canonicalMatched) { "direct_match" } elseif ($aliasMatched) { "alias_match" } elseif ($symbolMatched) { "symbol_match" } else { "relation_match" }
            [void]$expanded.Add([ordered]@{ term = $term; reason = $reason })
            if ($canonicalMatched -or $aliasMatched -or $symbolMatched) {
                foreach ($relation in @($term.relations)) {
                    $relationKey = Normalize-SearchText -Text ([string]$relation)
                    if ($byCanonical.ContainsKey($relationKey)) {
                        [void]$expanded.Add([ordered]@{ term = $byCanonical[$relationKey]; reason = "relation_match" })
                    }
                }
            }
        }
    }
    $reasonRank = @{ direct_match = 0; alias_match = 1; symbol_match = 2; relation_match = 3 }
    $bestByCanonical = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($candidate in @($expanded.ToArray())) {
        $key = [string]$candidate.term.canonical_key
        if (-not $bestByCanonical.ContainsKey($key) -or [int]$reasonRank[[string]$candidate.reason] -lt [int]$reasonRank[[string]$bestByCanonical[$key].reason]) {
            $bestByCanonical[$key] = $candidate
        }
    }
    $deduplicated = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $bestByCanonical.Values) { [void]$deduplicated.Add($candidate) }
    $deduplicated.Sort([System.Comparison[object]]{
            param($left, $right)
            $comparison = [StringComparer]::Ordinal.Compare([string]$left.term.canonical_key, [string]$right.term.canonical_key)
            if ($comparison -ne 0) { return $comparison }
            return ([int]$reasonRank[[string]$left.reason]).CompareTo([int]$reasonRank[[string]$right.reason])
        })
    return @($deduplicated.ToArray())
}

# Get-SearchResults: apply query, glossary, filters, branch policy, scoring, and stable sorting.
function Get-SearchResults {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Assets,
        [Parameter(Mandatory = $true)][object]$Glossary,
        [Parameter(Mandatory = $true)][object]$GitState,
        [AllowEmptyString()][string]$Query = "",
        [Parameter(Mandatory = $true)][int]$Limit,
        [string[]]$Types = @(),
        [string[]]$Statuses = @(),
        [switch]$CurrentBranchOnly,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $normalizedQuery = Normalize-SearchText -Text $Query
    $queryTerms = @(Get-SearchTerms -Text $Query)
    $typeFilter = @($Types | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Normalize-SearchText -Text ([string]$_) })
    $statusFilter = @($Statuses | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Normalize-SearchText -Text ([string]$_) })
    foreach ($type in $typeFilter) {
        if ($type -notin @("work", "context", "procedure", "spec")) { Add-Finding -Findings $Findings -Code "invalid-filter" -Path "" -Field "type" -Message "Type filter contains an unsupported asset type." }
    }
    $excludedStatuses = @("archived", "implemented", "superseded")
    $results = New-Object 'System.Collections.Generic.List[object]'
    $assetList = [System.Collections.Generic.List[object]]::new()
    foreach ($asset in @(Get-ValueArray -Value $Assets)) { if ($null -ne $asset) { [void]$assetList.Add($asset) } }
    $assetList.Sort([System.Comparison[object]]{
            param($left, $right)
            foreach ($field in @("path", "type", "id")) {
                $comparison = [StringComparer]::Ordinal.Compare([string](Get-PropertyValue $left $field), [string](Get-PropertyValue $right $field))
                if ($comparison -ne 0) { return $comparison }
            }
            return 0
        })
    $expansions = Get-GlossaryExpansion -Glossary $Glossary -Query $Query -QueryTerms @($queryTerms)
    $seenCandidates = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($asset in @($assetList.ToArray())) {
        if ($null -eq $asset) { continue }
        $candidateIdentity = "{0}`0{1}" -f [string](Get-PropertyValue $asset "type"), [string](Get-PropertyValue $asset "id")
        if (-not $seenCandidates.Add($candidateIdentity)) { continue }
        $type = Normalize-SearchText -Text ([string](Get-PropertyValue $asset "type"))
        $status = Normalize-SearchText -Text ([string](Get-PropertyValue $asset "status"))
        if ($typeFilter.Count -gt 0 -and $typeFilter -notcontains $type) { continue }
        if ($statusFilter.Count -gt 0) {
            if ($statusFilter -notcontains $status) { continue }
        }
        elseif ($excludedStatuses -contains $status) { continue }

        $reasonSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $score = 0
        if ([string]::IsNullOrWhiteSpace($normalizedQuery)) {
            [void]$reasonSet.Add("default")
            $score = 1
        }
        else {
            foreach ($value in @(Get-AssetCorpus -Asset $asset)) {
                if (Test-TextMatch -Candidate $value -QueryTerms @($queryTerms)) {
                    [void]$reasonSet.Add("direct_match")
                    $score = [math]::Max($score, 100)
                    break
                }
            }
            foreach ($expansion in @($expansions)) {
                $term = $expansion.term
                $termValues = @($term.canonical) + @($term.aliases) + @($term.symbols)
                $termMatched = @($termValues | Where-Object {
                        $candidate = [string]$_
                        @((Get-AssetCorpus -Asset $asset) | Where-Object { Test-PhraseMatch -Candidate ([string]$_) -Phrase $candidate }).Count -gt 0
                    }).Count -gt 0
                if ($termMatched) {
                    $reason = [string]$expansion.reason
                    [void]$reasonSet.Add($reason)
                    $reasonScore = switch ($reason) { "alias_match" { 90 } "symbol_match" { 80 } "relation_match" { 40 } default { 100 } }
                    $score = [math]::Max($score, $reasonScore)
                }
            }
            if ($reasonSet.Count -eq 0) { continue }
        }

        $anchor = Test-GitAnchor -Asset $asset -Root $ProjectRoot -GitState $GitState -Findings $Findings
        $branchState = "none"
        $branch = ""
        if ($null -ne $anchor) {
            $branch = [string]$anchor.branch
            $branchState = [string]$anchor.branch_state
            if ($branchState -eq "branch_match") {
                [void]$reasonSet.Add("branch_match")
                $score += 20
            }
            elseif ($branchState -eq "branch_mismatch") {
                [void]$reasonSet.Add("branch_mismatch")
                $score = [math]::Max(0, $score - 10)
            }
        }
        if ($CurrentBranchOnly.IsPresent -and $branchState -ne "branch_match") { continue }
        $reasonOrder = @("direct_match", "alias_match", "symbol_match", "relation_match", "branch_match", "branch_mismatch", "default")
        $reasonCodes = @($reasonOrder | Where-Object { $reasonSet.Contains($_) })
        $statusRank = switch ($status) { "active" { 4 } "draft" { 3 } "accepted" { 3 } "paused" { 2 } "blocked" { 2 } "deferred" { 1 } default { 0 } }
        $updated = [string](Get-PropertyValue $asset "updated")
        [void]$results.Add([ordered]@{
            type = [string](Get-PropertyValue $asset "type")
            id = [string](Get-PropertyValue $asset "id")
            path = [string](Get-PropertyValue $asset "path")
            schema = [string](Get-PropertyValue $asset "schema")
            status = [string](Get-PropertyValue $asset "status")
            title = [string](Get-PropertyValue $asset "title")
            summary = [string](Get-PropertyValue $asset "summary")
            score = [int]$score
            reason_codes = @($reasonCodes)
            branch = $branch
            branch_state = $branchState
            _status_rank = $statusRank
            _updated_sort = $updated
        })
    }
    $sorted = [System.Collections.Generic.List[object]]::new()
    foreach ($result in @($results.ToArray())) { [void]$sorted.Add($result) }
    $sorted.Sort([System.Comparison[object]]{
            param($left, $right)
            $comparison = ([int]$right.score).CompareTo([int]$left.score)
            if ($comparison -ne 0) { return $comparison }
            $comparison = ([int]$right._status_rank).CompareTo([int]$left._status_rank)
            if ($comparison -ne 0) { return $comparison }
            $comparison = [StringComparer]::Ordinal.Compare([string]$right._updated_sort, [string]$left._updated_sort)
            if ($comparison -ne 0) { return $comparison }
            foreach ($field in @("path", "type", "id")) {
                $comparison = [StringComparer]::Ordinal.Compare([string](Get-PropertyValue $left $field), [string](Get-PropertyValue $right $field))
                if ($comparison -ne 0) { return $comparison }
            }
            return 0
        })
    $limited = @($sorted.ToArray() | Select-Object -First $Limit)
    foreach ($item in $limited) {
        $item.Remove("_status_rank")
        $item.Remove("_updated_sort")
    }
    return @($limited)
}
