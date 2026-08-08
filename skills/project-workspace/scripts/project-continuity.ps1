# Internal Work continuity write/CAS/recovery responsibilities for project-workspace.
# This file is dot-sourced only by project-workspace.ps1.  It deliberately keeps
# the canonical Markdown parser as the sole schema and content authority.

$script:ContinuityStatuses = @("active", "paused", "blocked", "deferred")
$script:ContinuityReasons = @("unfinished", "external-wait", "blocked", "cross-boundary", "user-paused", "parallel-slices")
$script:ContinuityChangedFields = @(
    "title",
    "status",
    "summary",
    "next",
    "git.branch",
    "git.worktree",
    "git.last_verified_commit",
    "verified",
    "boundaries",
    "blockers"
)

function New-ContinuityFinding {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [string]$Field = "",
        [string]$Message = "",
        [ValidateSet("error", "warning")][string]$Severity = "error"
    )
    return [ordered]@{
        code = $Code
        path = ""
        field = $Field
        severity = $Severity
        message = $(if ([string]::IsNullOrWhiteSpace($Message)) { "Project workspace continuity operation failed closed." } else { $Message })
    }
}

function New-ContinuityResult {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Status,
        [object[]]$Findings = @(),
        [System.Collections.IDictionary]$Extra = $null
    )
    $result = [ordered]@{
        operation = $Operation
        status = $Status
        findings = @($Findings)
    }
    if ($null -ne $Extra) {
        foreach ($key in @($Extra.Keys)) { $result[$key] = $Extra[$key] }
    }
    return $result
}

function Get-ContinuityBound {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($BoundParameters -is [hashtable]) { return $BoundParameters.ContainsKey($Name) }
    if ($BoundParameters.PSObject.Methods.Name -contains "ContainsKey") { return $BoundParameters.ContainsKey($Name) }
    if ($BoundParameters.PSObject.Methods.Name -contains "Contains") { return $BoundParameters.Contains($Name) }
    return @($BoundParameters.Keys | ForEach-Object { [string]$_ }) -ccontains $Name
}

function Get-ContinuityString {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return [string]$Value
}

function ConvertTo-ContinuityYamlScalar {
    param([AllowEmptyString()][string]$Value)
    # JSON string quoting is a deterministic, YAML-compatible scalar encoding.
    return ($Value | ConvertTo-Json -Compress -Depth 3)
}

function Test-ContinuityScalar {
    param(
        [AllowEmptyString()][string]$Value,
        [switch]$AllowEmpty,
        [switch]$Path
    )
    if (-not $AllowEmpty.IsPresent -and [string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value.Contains("`r") -or $Value.Contains("`n") -or $Value.Contains("`0")) { return $false }
    if (-not (Test-PublicSafeText -Text $Value)) { return $false }
    if ($Path.IsPresent -and -not (Test-SafeProjectRelativePath -Path $Value)) { return $false }
    return $true
}

function Get-ContinuityUtcNow {
    return [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'", [Globalization.CultureInfo]::InvariantCulture)
}

function Test-ContinuityRevision {
    param([AllowEmptyString()][string]$Revision)
    return ($Revision -match '^sha256:[0-9a-f]{64}$')
}

function Test-ContinuityWorktreeAnchor {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [AllowEmptyString()][string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    if (-not (Test-ContinuityScalar -Value $Value -Path)) { return $false }
    try {
        $rootPhysical = Resolve-ExistingPhysicalPath -Path $Root -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
        $anchorPhysical = Resolve-PhysicalPathForWrite -Path (Join-Path $Root $Value)
        return (Test-PathIsEqualOrChild -Path $anchorPhysical -Root $rootPhysical)
    }
    catch { return $false }
}

function Get-ContinuityWorkRelativePath {
    param([Parameter(Mandatory = $true)][string]$Id)
    return (".agents/work/{0}.md" -f $Id)
}

function Resolve-ContinuityRoot {
    param([Parameter(Mandatory = $true)][string]$Root)
    $rootFull = Get-NormalizedFullPath -Path $Root
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) { throw "project root is not a directory" }
    return $rootFull
}

function Get-ContinuityBody {
    param([Parameter(Mandatory = $true)][string]$Text)
    $match = [regex]::Match($Text, '\A---\n.*?\n---(?:\n(?:\n)?|\z)', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { throw "canonical frontmatter delimiters are missing" }
    return $Text.Substring($match.Length)
}

function Get-ContinuityMetadataMap {
    param([Parameter(Mandatory = $true)][object]$Metadata)
    $map = [ordered]@{}
    foreach ($name in @("schema", "id", "title", "status", "updated", "summary", "next")) {
        $map[$name] = Get-ContinuityString (Get-PropertyValue $Metadata $name)
    }
    $git = Get-PropertyValue $Metadata "git"
    if ($null -ne $git) {
        $gitMap = [ordered]@{}
        foreach ($name in @("branch", "worktree", "last_verified_commit")) {
            $value = Get-ContinuityString (Get-PropertyValue $git $name)
            if (-not [string]::IsNullOrWhiteSpace($value)) { $gitMap[$name] = $value }
        }
        if ($gitMap.Count -gt 0) { $map.git = $gitMap }
    }
    return $map
}

function Get-ContinuityMetadataValue {
    param(
        [Parameter(Mandatory = $true)][object]$Metadata,
        [Parameter(Mandatory = $true)][string]$Field
    )
    if ($Field.StartsWith("git.", [StringComparison]::Ordinal)) {
        $git = Get-PropertyValue $Metadata "git"
        return Get-ContinuityString (Get-PropertyValue $git $Field.Substring(4))
    }
    return Get-ContinuityString (Get-PropertyValue $Metadata $Field)
}

function Set-ContinuityMetadataValue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Metadata,
        [Parameter(Mandatory = $true)][string]$Field,
        [AllowEmptyString()][string]$Value
    )
    if ($Field.StartsWith("git.", [StringComparison]::Ordinal)) {
        if (-not $Metadata.Contains("git") -or $null -eq $Metadata.git) { $Metadata.git = [ordered]@{} }
        $git = $Metadata.git
        $gitField = $Field.Substring(4)
        if ([string]::IsNullOrWhiteSpace($Value)) { $git.Remove($gitField) }
        else { $git[$gitField] = $Value }
        if ($git.Count -eq 0) { $Metadata.Remove("git") }
        return
    }
    $Metadata[$Field] = $Value
}

function ConvertTo-ContinuityFrontMatter {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Metadata,
        [Parameter(Mandatory = $true)][string]$Revision
    )
    $lines = New-Object 'System.Collections.Generic.List[string]'
    [void]$lines.Add("---")
    [void]$lines.Add(("schema: {0}" -f (ConvertTo-ContinuityYamlScalar -Value ([string]$Metadata.schema))))
    [void]$lines.Add(("id: {0}" -f (ConvertTo-ContinuityYamlScalar -Value ([string]$Metadata.id))))
    [void]$lines.Add(("title: {0}" -f (ConvertTo-ContinuityYamlScalar -Value ([string]$Metadata.title))))
    [void]$lines.Add(("status: {0}" -f (ConvertTo-ContinuityYamlScalar -Value ([string]$Metadata.status))))
    # The bounded parser intentionally treats quoted RFC3339 text as JSON and
    # PowerShell would materialize it as DateTime. Keep this schema string plain.
    [void]$lines.Add(("updated: {0}" -f ([string]$Metadata.updated)))
    [void]$lines.Add(("revision: {0}" -f (ConvertTo-ContinuityYamlScalar -Value $Revision)))
    [void]$lines.Add(("summary: {0}" -f (ConvertTo-ContinuityYamlScalar -Value ([string]$Metadata.summary))))
    [void]$lines.Add(("next: {0}" -f (ConvertTo-ContinuityYamlScalar -Value ([string]$Metadata.next))))
    if ($Metadata.Contains("git") -and $null -ne $Metadata.git -and $Metadata.git.Count -gt 0) {
        [void]$lines.Add("git:")
        foreach ($field in @("branch", "worktree", "last_verified_commit")) {
            if ($Metadata.git.Contains($field) -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.git[$field])) {
                [void]$lines.Add(("  {0}: {1}" -f $field, (ConvertTo-ContinuityYamlScalar -Value ([string]$Metadata.git[$field]))))
            }
        }
    }
    [void]$lines.Add("---")
    return ($lines.ToArray() -join "`n")
}

function New-ContinuityManagedBody {
    return "## Verified`n`n## Boundaries`n`n## Blockers`n"
}

function Get-ContinuitySectionState {
    param([Parameter(Mandatory = $true)][string]$Body)
    $lines = @([regex]::Split($Body, "`n"))
    $managed = [ordered]@{}
    foreach ($heading in @("Verified", "Boundaries", "Blockers")) {
        $exact = New-Object 'System.Collections.Generic.List[int]'
        $near = New-Object 'System.Collections.Generic.List[int]'
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ([string]$lines[$i] -ceq ("## {0}" -f $heading)) { [void]$exact.Add($i) }
            elseif ([string]$lines[$i] -match ("^##\s+{0}\s*$" -f [regex]::Escape($heading))) { [void]$near.Add($i) }
        }
        if ($exact.Count -gt 1 -or $near.Count -gt 0) { throw ("ambiguous managed section: {0}" -f $heading) }
        if ($exact.Count -eq 0) {
            $managed[$heading] = [ordered]@{ present = $false; start = -1; end = -1; content = $null }
            continue
        }
        $start = $exact[0]
        $end = $lines.Count
        for ($j = $start + 1; $j -lt $lines.Count; $j++) {
            if ([string]$lines[$j] -match '^##(?:\s|$)') { $end = $j; break }
        }
        $contentLines = if ($end -gt ($start + 1)) { @($lines[($start + 1)..($end - 1)]) } else { @() }
        $content = ($contentLines -join "`n").Trim()
        $managed[$heading] = [ordered]@{ present = $true; start = $start; end = $end; content = $content }
    }
    return [ordered]@{ lines = $lines; sections = $managed }
}

function ConvertTo-ContinuitySectionContent {
    param([AllowEmptyCollection()][string[]]$Values = @())
    if (@($Values).Count -eq 0) { return "" }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($value in @($Values)) {
        [void]$lines.Add(("- {0}" -f $value))
    }
    return ($lines.ToArray() -join "`n")
}

function Set-ContinuityManagedSections {
    param(
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Updates
    )
    $state = Get-ContinuitySectionState -Body $Body
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @($state.lines)) { [void]$lines.Add([string]$line) }
    $existing = @($Updates.Keys | Where-Object { $Updates[$_].provided -and $state.sections.Contains($_) -and $state.sections[$_].present })
    foreach ($heading in @($existing | Sort-Object { [int]$state.sections[$_].start } -Descending)) {
        $section = $state.sections[$heading]
        $start = [int]$section.start
        $end = [int]$section.end
        $replacement = @(("## {0}" -f $heading), "")
        $content = [string]$Updates[$heading].content
        if (-not [string]::IsNullOrEmpty($content)) { $replacement = @(("## {0}" -f $heading), "", $content, "") }
        $newLines = New-Object 'System.Collections.Generic.List[string]'
        for ($i = 0; $i -lt $start; $i++) { [void]$newLines.Add($lines[$i]) }
        foreach ($line in $replacement) { [void]$newLines.Add($line) }
        for ($i = $end; $i -lt $lines.Count; $i++) { [void]$newLines.Add($lines[$i]) }
        $lines = $newLines
    }
    $missing = @($Updates.Keys | Where-Object { $Updates[$_].provided -and -not $state.sections[$_].present })
    foreach ($heading in @($missing | Sort-Object { [array]::IndexOf(@("Verified", "Boundaries", "Blockers"), $_) })) {
        while ($lines.Count -gt 0 -and [string]::IsNullOrEmpty([string]$lines[$lines.Count - 1])) { $lines.RemoveAt($lines.Count - 1) }
        if ($lines.Count -gt 0) { [void]$lines.Add("") }
        [void]$lines.Add(("## {0}" -f $heading))
        [void]$lines.Add("")
        $content = [string]$Updates[$heading].content
        if (-not [string]::IsNullOrEmpty($content)) { [void]$lines.Add($content); [void]$lines.Add("") }
    }
    return ($lines.ToArray() -join "`n")
}

function New-ContinuityCandidateText {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Metadata,
        [Parameter(Mandatory = $true)][string]$Body
    )
    $frontMatter = ConvertTo-ContinuityFrontMatter -Metadata $Metadata -Revision ("sha256:{0}" -f ("0" * 64))
    return (("{0}`n`n{1}" -f $frontMatter, $Body) -replace "`r`n", "`n" -replace "`r", "`n")
}

function New-ContinuityTempDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ("project-workspace-continuity-" + [Guid]::NewGuid().ToString("N"))
    [IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

function Write-ContinuityText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text,
        [switch]$CreateNew
    )
    $encoding = [Text.UTF8Encoding]::new($false)
    $mode = if ($CreateNew.IsPresent) { [IO.FileMode]::CreateNew } else { [IO.FileMode]::Create }
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, $mode, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $bytes = $encoding.GetBytes(($Text -replace "`r`n", "`n" -replace "`r", "`n"))
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Test-ContinuityCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $tempRoot = New-ContinuityTempDirectory
    try {
        $candidateRelative = Get-ContinuityWorkRelativePath -Id $Id
        $candidatePath = Join-Path $tempRoot $candidateRelative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $candidatePath)) | Out-Null
        Write-ContinuityText -Path $candidatePath -Text $Text
        $parser = Invoke-CanonicalParser -Root $tempRoot -Paths @($candidateRelative)
        if ($null -eq $parser.payload -or [string]$parser.payload.status -cne "PASS") { throw "canonical parser rejected candidate" }
        $asset = @($parser.payload.assets | Where-Object { [string]$_.path -ceq $candidateRelative }) | Select-Object -First 1
        if ($null -eq $asset -or [bool]$asset.valid -ne $true -or [string]$asset.id -cne $Id -or [string]$asset.type -cne "work") { throw "canonical parser rejected candidate identity" }
        $actualRevision = Get-RevisionHash -Path $candidatePath
        $metadata = Get-PropertyValue $asset "metadata"
        if ([string](Get-PropertyValue $metadata "revision") -cne $actualRevision) { throw "candidate revision is not self-consistent" }
        $git = Get-PropertyValue $metadata "git"
        $worktree = Get-ContinuityString (Get-PropertyValue $git "worktree")
        if (-not (Test-ContinuityWorktreeAnchor -Root $Root -Value $worktree)) { throw "candidate Git worktree is unsafe in the actual project root" }
        return [ordered]@{ valid = $true; text = $Text; revision = $actualRevision; metadata = $metadata }
    }
    catch {
        return [ordered]@{ valid = $false; reason = "candidate-invalid" }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Get-ContinuitySnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id
    )
    $relative = Get-ContinuityWorkRelativePath -Id $Id
    try { $path = Assert-ProjectPath -Root $Root -RelativePath $relative -AllowMissing } catch { return [ordered]@{ state = "invalid"; path = $relative } }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [ordered]@{ state = "missing"; path = $relative } }
    try {
        $parser = Invoke-CanonicalParser -Root $Root -Paths @($relative)
        if ($null -eq $parser.payload -or [string]$parser.payload.status -cne "PASS") { return [ordered]@{ state = "malformed"; path = $relative } }
        $asset = @($parser.payload.assets | Where-Object { [string]$_.path -ceq $relative }) | Select-Object -First 1
        if ($null -eq $asset -or [bool]$asset.valid -ne $true -or [string]$asset.type -cne "work" -or [string]$asset.id -cne $Id) { return [ordered]@{ state = "malformed"; path = $relative } }
        $metadata = Get-PropertyValue $asset "metadata"
        $declared = Get-ContinuityString (Get-PropertyValue $metadata "revision")
        $actual = Get-RevisionHash -Path $path
        if ($declared -cne $actual) { return [ordered]@{ state = "revision-mismatch"; path = $relative; declared_revision = $declared; current_revision = $actual } }
        $text = Read-StrictUtf8Text -Path $path
        $body = Get-ContinuityBody -Text $text
        $bytes = [IO.File]::ReadAllBytes($path)
        return [ordered]@{
            state = "valid"
            path = $relative
            full_path = $path
            text = $text
            body = $body
            metadata = $metadata
            revision = $actual
            byte_hash = Get-Sha256 -Bytes $bytes
        }
    }
    catch { return [ordered]@{ state = "malformed"; path = $relative } }
}

function Get-ContinuityGitMap {
    param([object]$Metadata)
    $git = Get-PropertyValue $Metadata "git"
    return [ordered]@{
        branch = Get-ContinuityString (Get-PropertyValue $git "branch")
        worktree = Get-ContinuityString (Get-PropertyValue $git "worktree")
        last_verified_commit = Get-ContinuityString (Get-PropertyValue $git "last_verified_commit")
    }
}

function New-ContinuityMetadata {
    param(
        [string]$Id,
        [string]$Title,
        [string]$Status,
        [string]$Updated,
        [string]$Summary,
        [string]$Next,
        [string]$GitBranch,
        [string]$GitWorktree,
        [string]$GitLastVerifiedCommit
    )
    $metadata = [ordered]@{
        schema = "agent-ecosystem/work-item/v1"
        id = $Id
        title = $Title
        status = $Status
        updated = $Updated
        revision = "sha256:{0}" -f ("0" * 64)
        summary = $Summary
        next = $Next
    }
    $git = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($GitBranch)) { $git.branch = $GitBranch }
    if (-not [string]::IsNullOrWhiteSpace($GitWorktree)) { $git.worktree = $GitWorktree }
    if (-not [string]::IsNullOrWhiteSpace($GitLastVerifiedCommit)) { $git.last_verified_commit = $GitLastVerifiedCommit }
    if ($git.Count -gt 0) { $metadata.git = $git }
    return $metadata
}

function Get-ContinuityRequestMetadata {
    param(
        [Parameter(Mandatory = $true)][object]$Snapshot,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    $metadata = Get-ContinuityMetadataMap -Metadata $Snapshot.metadata
    foreach ($pair in @(
        @{ parameter = "Title"; field = "title" },
        @{ parameter = "Status"; field = "status" },
        @{ parameter = "Summary"; field = "summary" },
        @{ parameter = "Next"; field = "next" },
        @{ parameter = "GitBranch"; field = "git.branch" },
        @{ parameter = "GitWorktree"; field = "git.worktree" },
        @{ parameter = "GitLastVerifiedCommit"; field = "git.last_verified_commit" }
    )) {
        if (Get-ContinuityBound -BoundParameters $BoundParameters -Name $pair.parameter) {
            $raw = $BoundParameters[$pair.parameter]
            if ($pair.parameter -ceq "Status") {
                $value = [string](@($raw)[0])
            }
            else { $value = Get-ContinuityString $raw }
            Set-ContinuityMetadataValue -Metadata $metadata -Field $pair.field -Value $value
        }
    }
    if (Get-ContinuityBound -BoundParameters $BoundParameters -Name "Updated") { $metadata.updated = Get-ContinuityString $BoundParameters.Updated }
    return $metadata
}

function Get-ContinuitySectionUpdates {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters)
    $updates = [ordered]@{}
    foreach ($pair in @(@{ parameter = "Verified"; heading = "Verified" }, @{ parameter = "Boundary"; heading = "Boundaries" }, @{ parameter = "Blocker"; heading = "Blockers" })) {
        $provided = Get-ContinuityBound -BoundParameters $BoundParameters -Name $pair.parameter
        $values = if ($provided) { @($BoundParameters[$pair.parameter] | ForEach-Object { [string]$_ }) } else { @() }
        foreach ($value in $values) {
            if (-not (Test-ContinuityScalar -Value $value)) { throw ("invalid section value: {0}" -f $pair.parameter) }
        }
        $updates[$pair.heading] = [ordered]@{ provided = $provided; values = $values; content = ConvertTo-ContinuitySectionContent -Values $values }
    }
    return $updates
}

function Get-ContinuityChangedFields {
    param(
        [Parameter(Mandatory = $true)][object]$Current,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters,
        [System.Collections.IDictionary]$SectionUpdates = $null
    )
    $changed = New-Object 'System.Collections.Generic.List[string]'
    $metadata = $Current.metadata
    foreach ($field in @($script:ContinuityChangedFields)) {
        $requested = $false
        $requestValue = ""
        switch -Regex ($field) {
            '^title$' { $requested = Get-ContinuityBound $BoundParameters "Title"; if ($requested) { $requestValue = Get-ContinuityString $BoundParameters.Title }; break }
            '^status$' { $requested = Get-ContinuityBound $BoundParameters "Status"; if ($requested) { $requestValue = [string]@($BoundParameters.Status)[0] }; break }
            '^summary$' { $requested = Get-ContinuityBound $BoundParameters "Summary"; if ($requested) { $requestValue = Get-ContinuityString $BoundParameters.Summary }; break }
            '^next$' { $requested = Get-ContinuityBound $BoundParameters "Next"; if ($requested) { $requestValue = Get-ContinuityString $BoundParameters.Next }; break }
            '^git\.branch$' { $requested = Get-ContinuityBound $BoundParameters "GitBranch"; if ($requested) { $requestValue = Get-ContinuityString $BoundParameters.GitBranch }; break }
            '^git\.worktree$' { $requested = Get-ContinuityBound $BoundParameters "GitWorktree"; if ($requested) { $requestValue = Get-ContinuityString $BoundParameters.GitWorktree }; break }
            '^git\.last_verified_commit$' { $requested = Get-ContinuityBound $BoundParameters "GitLastVerifiedCommit"; if ($requested) { $requestValue = Get-ContinuityString $BoundParameters.GitLastVerifiedCommit }; break }
            '^verified$' { $requested = $null -ne $SectionUpdates -and $SectionUpdates.Contains("Verified") -and $SectionUpdates.Verified.provided; if ($requested) { $requestValue = [string]$SectionUpdates.Verified.content }; break }
            '^boundaries$' { $requested = $null -ne $SectionUpdates -and $SectionUpdates.Contains("Boundaries") -and $SectionUpdates.Boundaries.provided; if ($requested) { $requestValue = [string]$SectionUpdates.Boundaries.content }; break }
            '^blockers$' { $requested = $null -ne $SectionUpdates -and $SectionUpdates.Contains("Blockers") -and $SectionUpdates.Blockers.provided; if ($requested) { $requestValue = [string]$SectionUpdates.Blockers.content }; break }
        }
        if (-not $requested) { continue }
        if ($field -in @("verified", "boundaries", "blockers")) {
            $sectionName = switch ($field) { "verified" { "Verified" } "boundaries" { "Boundaries" } default { "Blockers" } }
            $currentSections = Get-ContinuitySectionState -Body $Current.body
            $section = $currentSections.sections[$sectionName]
            $currentValue = if ($section.present) { [string]$section.content } else { $null }
            if ($null -eq $currentValue -or $currentValue -cne $requestValue) { [void]$changed.Add($field) }
        }
        elseif ((Get-ContinuityMetadataValue -Metadata $metadata -Field $field) -cne $requestValue) { [void]$changed.Add($field) }
    }
    return @($changed.ToArray())
}

function Assert-ContinuityId {
    param([Parameter(Mandatory = $true)][string]$Id)
    if ($Id -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "invalid work id" }
}

function Assert-ContinuityOperationParameters {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    $allowed = switch ($Operation) {
        "create-work" { @("Operation", "Mode", "ProjectRoot", "Id", "Title", "Summary", "Next", "ContinuityReason", "Status", "GitBranch", "GitWorktree", "GitLastVerifiedCommit", "Updated", "Json", "NoExit") }
        "checkpoint" { @("Operation", "Mode", "ProjectRoot", "Id", "BaseRevision", "Title", "Status", "Summary", "Next", "Verified", "Boundary", "Blocker", "GitBranch", "GitWorktree", "GitLastVerifiedCommit", "Updated", "Json", "NoExit") }
        "set-status" { @("Operation", "Mode", "ProjectRoot", "Id", "BaseRevision", "Status", "Updated", "Json", "NoExit") }
        "complete" { @("Operation", "Mode", "ProjectRoot", "Id", "BaseRevision", "ResultPersisted", "Json", "NoExit") }
        "recover-work" { @("Operation", "Mode", "ProjectRoot", "Id", "Json", "NoExit") }
        default { @() }
    }
    $common = @("Verbose", "Debug", "ErrorAction", "WarningAction", "InformationAction", "ProgressAction", "ErrorVariable", "WarningVariable", "InformationVariable", "OutVariable", "OutBuffer", "PipelineVariable")
    foreach ($key in @($BoundParameters.Keys)) {
        if ($key -notin $allowed -and $key -notin $common) { throw "unsupported parameter" }
    }
}

function Assert-ContinuityCreateInput {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    foreach ($name in @("Id", "Title", "Summary", "Next", "ContinuityReason")) {
        if (-not (Get-ContinuityBound $BoundParameters $name)) { throw ("missing parameter: {0}" -f $name) }
    }
    Assert-ContinuityId -Id ([string]$BoundParameters.Id)
    foreach ($name in @("Title", "Summary", "Next")) { if (-not (Test-ContinuityScalar -Value ([string]$BoundParameters[$name]))) { throw ("invalid parameter: {0}" -f $name) } }
    $reason = [string]$BoundParameters.ContinuityReason
    if ($reason -cnotin $script:ContinuityReasons) { throw "invalid continuity reason" }
    if (Get-ContinuityBound $BoundParameters "Status") {
        $statuses = @($BoundParameters.Status)
        if ($statuses.Count -ne 1 -or [string]$statuses[0] -cnotin $script:ContinuityStatuses) { throw "invalid status" }
    }
    foreach ($pair in @(@{ n = "GitBranch"; path = $false }, @{ n = "GitWorktree"; path = $true }, @{ n = "GitLastVerifiedCommit"; path = $false }, @{ n = "Updated"; path = $false })) {
        if (Get-ContinuityBound $BoundParameters $pair.n) {
            $v = [string]$BoundParameters[$pair.n]
            if ([string]::IsNullOrWhiteSpace($v)) { continue }
            if (-not (Test-ContinuityScalar -Value $v -Path:$pair.path)) { throw ("invalid parameter: {0}" -f $pair.n) }
        }
    }
    if (Get-ContinuityBound $BoundParameters "GitWorktree") {
        if (-not (Test-ContinuityWorktreeAnchor -Root $Root -Value ([string]$BoundParameters.GitWorktree))) { throw "invalid parameter: GitWorktree" }
    }
}

function Assert-ContinuityUpdateInput {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    if (-not (Get-ContinuityBound $BoundParameters "Id")) { throw "missing parameter: Id" }
    Assert-ContinuityId -Id ([string]$BoundParameters.Id)
    if (-not (Get-ContinuityBound $BoundParameters "BaseRevision") -or -not (Test-ContinuityRevision -Revision ([string]$BoundParameters.BaseRevision))) { throw "invalid base revision" }
    if ($Operation -ceq "set-status") {
        if (-not (Get-ContinuityBound $BoundParameters "Status") -or @($BoundParameters.Status).Count -ne 1 -or [string]@($BoundParameters.Status)[0] -cnotin $script:ContinuityStatuses) { throw "invalid status" }
        if (Get-ContinuityBound $BoundParameters "Updated") {
            $updated = [string]$BoundParameters.Updated
            if (-not (Test-ContinuityScalar -Value $updated)) { throw "invalid parameter: Updated" }
        }
        return
    }
    if ($Operation -ceq "complete") { return }
    if (Get-ContinuityBound $BoundParameters "Status") {
        if (@($BoundParameters.Status).Count -ne 1 -or [string]@($BoundParameters.Status)[0] -cnotin $script:ContinuityStatuses) { throw "invalid status" }
    }
    foreach ($name in @("Title", "Summary", "Next", "GitBranch", "GitWorktree", "GitLastVerifiedCommit", "Updated")) {
        if (-not (Get-ContinuityBound $BoundParameters $name)) { continue }
        $v = [string]$BoundParameters[$name]
        if ($name -eq "GitWorktree") {
            if (-not [string]::IsNullOrWhiteSpace($v) -and -not (Test-ContinuityScalar -Value $v -Path)) { throw ("invalid parameter: {0}" -f $name) }
        }
        elseif ($name -in @("Title", "Summary", "Next")) {
            if (-not (Test-ContinuityScalar -Value $v)) { throw ("invalid parameter: {0}" -f $name) }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($v) -and -not (Test-ContinuityScalar -Value $v)) { throw ("invalid parameter: {0}" -f $name) }
    }
    if (Get-ContinuityBound $BoundParameters "GitWorktree") {
        if (-not (Test-ContinuityWorktreeAnchor -Root $Root -Value ([string]$BoundParameters.GitWorktree))) { throw "invalid parameter: GitWorktree" }
    }
}

function New-ContinuityCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Metadata,
        [Parameter(Mandatory = $true)][string]$Body
    )
    $placeholder = New-ContinuityCandidateText -Metadata $Metadata -Body $Body
    $tempRoot = New-ContinuityTempDirectory
    try {
        $relative = Get-ContinuityWorkRelativePath -Id $Id
        $path = Join-Path $tempRoot $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        Write-ContinuityText -Path $path -Text $placeholder
        $revision = Get-RevisionHash -Path $path
        $final = ((ConvertTo-ContinuityFrontMatter -Metadata $Metadata -Revision $revision) + "`n`n" + $Body) -replace "`r`n", "`n" -replace "`r", "`n"
        $candidate = Test-ContinuityCandidate -Root $Root -Id $Id -Text $final
        if (-not $candidate.valid) { throw "candidate-invalid" }
        return [ordered]@{ text = $final; revision = $revision }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Write-ContinuityCreateNew {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $relative = Get-ContinuityWorkRelativePath -Id $Id
    $workDirectory = Join-Path $Root ".agents/work"
    $rootPhysical = Resolve-ExistingPhysicalPath -Path $Root -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    $workDirectoryPhysical = Resolve-PhysicalPathForWrite -Path $workDirectory
    if (-not (Test-PathIsEqualOrChild -Path $workDirectoryPhysical -Root $rootPhysical)) { throw "canonical Work directory resolves outside project root" }
    if (-not (Test-Path -LiteralPath $workDirectory -PathType Container)) { [IO.Directory]::CreateDirectory($workDirectory) | Out-Null }
    Assert-ProjectPath -Root $Root -RelativePath ".agents/work" -AllowMissing | Out-Null
    $target = Assert-ProjectPath -Root $Root -RelativePath $relative -AllowMissing
    $temp = Join-Path $workDirectory (".continuity-{0}-{1}.tmp" -f $Id, [Guid]::NewGuid().ToString("N"))
    try {
        Write-ContinuityText -Path $temp -Text $Text -CreateNew
        [IO.File]::Move($temp, $target, $false)
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } }
}

function Assert-ContinuityMutationTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    # Re-resolve both the canonical file and its parent immediately before a
    # mutation.  This is a fail-closed optimistic path guard, not a lock or a
    # claim of linearizable filesystem concurrency.
    $rootPhysical = Resolve-ExistingPhysicalPath -Path $Root -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    $target = Assert-ProjectPath -Root $Root -RelativePath $RelativePath
    $targetPhysical = Resolve-ExistingPhysicalPath -Path $target -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    if (-not (Test-PathIsEqualOrChild -Path $targetPhysical -Root $rootPhysical)) { throw "canonical Work target resolves outside project root" }
    $parent = Split-Path -Parent $target
    $parentPhysical = Resolve-ExistingPhysicalPath -Path $parent -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    if (-not (Test-PathIsEqualOrChild -Path $parentPhysical -Root $rootPhysical)) { throw "canonical Work parent resolves outside project root" }
    return $target
}

function Write-ContinuityReplace {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][object]$Snapshot,
        [Parameter(Mandatory = $true)][string]$Text
    )
    # Re-check lexical and physical containment immediately before creating the
    # replacement file; a path link can change after the initial snapshot.
    $target = Assert-ContinuityMutationTarget -Root $Root -RelativePath ([string]$Snapshot.path)
    $directory = Split-Path -Parent $target
    $temp = Join-Path $directory (".continuity-{0}-{1}.tmp" -f ([string]$Snapshot.metadata.id), [Guid]::NewGuid().ToString("N"))
    try {
        Write-ContinuityText -Path $temp -Text $Text -CreateNew
        # NOTE: The final read is deliberately adjacent to the atomic replace.
        # This is an optimistic fail-closed guard, not a linearizable lock.
        $latest = Get-ContinuitySnapshot -Root $Root -Id $Id
        if ($latest.state -ne "valid") { return [ordered]@{ state = "invalid"; snapshot = $latest } }
        if ([string]$latest.byte_hash -cne [string]$Snapshot.byte_hash -or [string]$latest.revision -cne [string]$Snapshot.revision) { return [ordered]@{ state = "conflict"; snapshot = $latest } }
        $target = Assert-ContinuityMutationTarget -Root $Root -RelativePath ([string]$Snapshot.path)
        [IO.File]::Move($temp, $target, $true)
        return [ordered]@{ state = "written"; snapshot = $latest }
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } }
}

function Remove-ContinuityWork {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][object]$Snapshot
    )
    $latest = Get-ContinuitySnapshot -Root $Root -Id $Id
    if ($latest.state -ne "valid") { return [ordered]@{ state = "invalid"; snapshot = $latest } }
    if ([string]$latest.byte_hash -cne [string]$Snapshot.byte_hash -or [string]$latest.revision -cne [string]$Snapshot.revision) { return [ordered]@{ state = "conflict"; snapshot = $latest } }
    try {
        $target = Assert-ContinuityMutationTarget -Root $Root -RelativePath ([string]$latest.path)
        [IO.File]::Delete($target)
        return [ordered]@{ state = "deleted"; snapshot = $latest }
    }
    catch { return [ordered]@{ state = "delete-failed"; snapshot = $latest } }
}

function New-ContinuityConflictResult {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Expected,
        [AllowEmptyString()][string]$Current = "",
        [string[]]$Changed = @()
    )
    return New-ContinuityResult -Operation $Operation -Status "revision-conflict" -Extra ([ordered]@{
        id = $Id
        expected_revision = $Expected
        current_revision = $Current
        changed_fields = @($Changed)
        current_path = Get-ContinuityWorkRelativePath -Id $Id
    })
}

function Invoke-ContinuityCreateWork {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    Assert-ContinuityCreateInput -Root $Root -BoundParameters $BoundParameters
    $id = [string]$BoundParameters.Id
    $relative = Get-ContinuityWorkRelativePath -Id $id
    try { $target = Assert-ProjectPath -Root $Root -RelativePath $relative -AllowMissing } catch { throw "unsafe work path" }
    if (Test-Path -LiteralPath $target) { return New-ContinuityResult -Operation "create-work" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "duplicate-work" -Message "A canonical Work with this id already exists.")) -Extra ([ordered]@{ id = $id; path = $relative }) }
    $status = if (Get-ContinuityBound $BoundParameters "Status") { [string]@($BoundParameters.Status)[0] } else { "active" }
    $updated = if (Get-ContinuityBound -BoundParameters $BoundParameters -Name "Updated") { [string]$BoundParameters.Updated } else { Get-ContinuityUtcNow }
    $metadata = New-ContinuityMetadata -Id $id -Title ([string]$BoundParameters.Title) -Status $status -Updated $updated -Summary ([string]$BoundParameters.Summary) -Next ([string]$BoundParameters.Next) -GitBranch (Get-ContinuityString $BoundParameters.GitBranch) -GitWorktree (Get-ContinuityString $BoundParameters.GitWorktree) -GitLastVerifiedCommit (Get-ContinuityString $BoundParameters.GitLastVerifiedCommit)
    try { $candidate = New-ContinuityCandidate -Root $Root -Id $id -Metadata $metadata -Body (New-ContinuityManagedBody) } catch { return New-ContinuityResult -Operation "create-work" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "candidate-invalid" -Message "Generated Work did not pass the canonical parser.")) -Extra ([ordered]@{ id = $id; path = $relative }) }
    try { Write-ContinuityCreateNew -Root $Root -Id $id -Text $candidate.text }
    catch {
        if (Test-Path -LiteralPath (Join-Path $Root $relative)) { return New-ContinuityResult -Operation "create-work" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "duplicate-work" -Message "A canonical Work with this id already exists.")) -Extra ([ordered]@{ id = $id; path = $relative }) }
        return New-ContinuityResult -Operation "create-work" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "write-failed" -Message "Canonical Work could not be created.")) -Extra ([ordered]@{ id = $id; path = $relative })
    }
    return New-ContinuityResult -Operation "create-work" -Status "PASS" -Extra ([ordered]@{ id = $id; path = $relative; result = "created"; revision = [string]$candidate.revision; read_only = $false })
}

function Invoke-ContinuityCheckpoint {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    Assert-ContinuityUpdateInput -Root $Root -Operation "checkpoint" -BoundParameters $BoundParameters
    $id = [string]$BoundParameters.Id
    $snapshot = Get-ContinuitySnapshot -Root $Root -Id $id
    if ($snapshot.state -ne "valid") { return New-ContinuityResult -Operation "checkpoint" -Status "FAIL" -Findings @((New-ContinuityFinding -Code ("work-{0}" -f $snapshot.state) -Message "Canonical Work is not valid for checkpoint.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    try { $sectionUpdates = Get-ContinuitySectionUpdates -BoundParameters $BoundParameters; $newBody = Set-ContinuityManagedSections -Body $snapshot.body -Updates $sectionUpdates } catch { return New-ContinuityResult -Operation "checkpoint" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "sections-ambiguous" -Message "Managed Work sections are ambiguous or invalid.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    $metadata = Get-ContinuityRequestMetadata -Snapshot $snapshot -BoundParameters $BoundParameters
    if (-not (Get-ContinuityBound $BoundParameters "Updated")) { $metadata.updated = Get-ContinuityUtcNow }
    if ([string]$metadata.updated -eq [string](Get-PropertyValue $snapshot.metadata "updated") -and $BoundParameters.Keys.Count -le 2) { $metadata.updated = Get-ContinuityUtcNow }
    $expected = [string]$BoundParameters.BaseRevision
    if ($expected -cne [string]$snapshot.revision) { return New-ContinuityConflictResult -Operation "checkpoint" -Id $id -Expected $expected -Current ([string]$snapshot.revision) -Changed @(Get-ContinuityChangedFields -Current $snapshot -BoundParameters $BoundParameters -SectionUpdates $sectionUpdates) }
    try { $candidate = New-ContinuityCandidate -Root $Root -Id $id -Metadata $metadata -Body $newBody } catch { return New-ContinuityResult -Operation "checkpoint" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "candidate-invalid" -Message "Checkpoint candidate did not pass the canonical parser.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    try { $mutation = Write-ContinuityReplace -Root $Root -Id $id -Snapshot $snapshot -Text $candidate.text }
    catch { return New-ContinuityResult -Operation "checkpoint" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "write-failed" -Message "Canonical Work could not be atomically replaced.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    if ($mutation.state -eq "conflict") { return New-ContinuityConflictResult -Operation "checkpoint" -Id $id -Expected $expected -Current ([string]$mutation.snapshot.revision) -Changed @(Get-ContinuityChangedFields -Current $mutation.snapshot -BoundParameters $BoundParameters -SectionUpdates $sectionUpdates) }
    if ($mutation.state -ne "written") { return New-ContinuityResult -Operation "checkpoint" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "concurrent-change" -Message "Canonical Work changed during the final write guard.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    return New-ContinuityResult -Operation "checkpoint" -Status "PASS" -Extra ([ordered]@{ id = $id; path = $snapshot.path; result = "updated"; previous_revision = $expected; revision = [string]$candidate.revision; read_only = $false })
}

function Invoke-ContinuitySetStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    Assert-ContinuityUpdateInput -Root $Root -Operation "set-status" -BoundParameters $BoundParameters
    $id = [string]$BoundParameters.Id
    $snapshot = Get-ContinuitySnapshot -Root $Root -Id $id
    if ($snapshot.state -ne "valid") { return New-ContinuityResult -Operation "set-status" -Status "FAIL" -Findings @((New-ContinuityFinding -Code ("work-{0}" -f $snapshot.state) -Message "Canonical Work is not valid for status update.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    $metadata = Get-ContinuityRequestMetadata -Snapshot $snapshot -BoundParameters $BoundParameters
    $metadata.updated = if (Get-ContinuityBound $BoundParameters "Updated") { [string]$BoundParameters.Updated } else { Get-ContinuityUtcNow }
    $expected = [string]$BoundParameters.BaseRevision
    if ($expected -cne [string]$snapshot.revision) { return New-ContinuityConflictResult -Operation "set-status" -Id $id -Expected $expected -Current ([string]$snapshot.revision) -Changed @(Get-ContinuityChangedFields -Current $snapshot -BoundParameters $BoundParameters) }
    try { $candidate = New-ContinuityCandidate -Root $Root -Id $id -Metadata $metadata -Body $snapshot.body } catch { return New-ContinuityResult -Operation "set-status" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "candidate-invalid" -Message "Status candidate did not pass the canonical parser.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    try { $mutation = Write-ContinuityReplace -Root $Root -Id $id -Snapshot $snapshot -Text $candidate.text }
    catch { return New-ContinuityResult -Operation "set-status" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "write-failed" -Message "Canonical Work could not be atomically replaced.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    if ($mutation.state -eq "conflict") { return New-ContinuityConflictResult -Operation "set-status" -Id $id -Expected $expected -Current ([string]$mutation.snapshot.revision) -Changed @(Get-ContinuityChangedFields -Current $mutation.snapshot -BoundParameters $BoundParameters) }
    if ($mutation.state -ne "written") { return New-ContinuityResult -Operation "set-status" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "concurrent-change" -Message "Canonical Work changed during the final write guard.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    return New-ContinuityResult -Operation "set-status" -Status "PASS" -Extra ([ordered]@{ id = $id; path = $snapshot.path; result = "updated"; previous_revision = $expected; revision = [string]$candidate.revision; read_only = $false })
}

function Invoke-ContinuityComplete {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    Assert-ContinuityUpdateInput -Root $Root -Operation "complete" -BoundParameters $BoundParameters
    if (-not (Get-ContinuityBound $BoundParameters "ResultPersisted") -or -not [bool]$BoundParameters.ResultPersisted) { return New-ContinuityResult -Operation "complete" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "result-not-persisted" -Message "Completion requires explicit persisted-result confirmation.")) -Extra ([ordered]@{ id = [string]$BoundParameters.Id; path = Get-ContinuityWorkRelativePath -Id ([string]$BoundParameters.Id) }) }
    $id = [string]$BoundParameters.Id
    $snapshot = Get-ContinuitySnapshot -Root $Root -Id $id
    if ($snapshot.state -ne "valid") { return New-ContinuityResult -Operation "complete" -Status "FAIL" -Findings @((New-ContinuityFinding -Code ("work-{0}" -f $snapshot.state) -Message "Canonical Work is not valid for completion.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    $expected = [string]$BoundParameters.BaseRevision
    if ($expected -cne [string]$snapshot.revision) { return New-ContinuityConflictResult -Operation "complete" -Id $id -Expected $expected -Current ([string]$snapshot.revision) -Changed @() }
    $mutation = Remove-ContinuityWork -Root $Root -Id $id -Snapshot $snapshot
    if ($mutation.state -eq "conflict") { return New-ContinuityConflictResult -Operation "complete" -Id $id -Expected $expected -Current ([string]$mutation.snapshot.revision) -Changed @() }
    if ($mutation.state -eq "invalid") { return New-ContinuityResult -Operation "complete" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "concurrent-change" -Message "Canonical Work changed during the final delete guard.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    if ($mutation.state -ne "deleted") { return New-ContinuityResult -Operation "complete" -Status "FAIL" -Findings @((New-ContinuityFinding -Code "delete-failed" -Message "Canonical Work could not be deleted.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path }) }
    return New-ContinuityResult -Operation "complete" -Status "PASS" -Extra ([ordered]@{ id = $id; path = $snapshot.path; result = "deleted"; previous_revision = $expected; read_only = $false })
}

function Resolve-ContinuityWorktreeRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Worktree
    )
    if ([string]::IsNullOrWhiteSpace($Worktree)) { return $Root }
    try {
        $path = Assert-ProjectPath -Root $Root -RelativePath $Worktree -AllowMissing
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { return $null }
        return $path
    }
    catch { return $null }
}

function Invoke-ContinuityRecoverWork {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    if (-not (Get-ContinuityBound $BoundParameters "Id")) { throw "missing parameter: Id" }
    Assert-ContinuityId -Id ([string]$BoundParameters.Id)
    $id = [string]$BoundParameters.Id
    $snapshot = Get-ContinuitySnapshot -Root $Root -Id $id
    if ($snapshot.state -ne "valid") { return New-ContinuityResult -Operation "recover-work" -Status "FAIL" -Findings @((New-ContinuityFinding -Code ("work-{0}" -f $snapshot.state) -Message "Canonical Work cannot be selected for recovery.")) -Extra ([ordered]@{ id = $id; path = $snapshot.path; read_only = $true }) }
    $anchor = Get-ContinuityGitMap -Metadata $snapshot.metadata
    $anchorBranchSafe = Test-ContinuityScalar -Value $anchor.branch -AllowEmpty
    $anchorWorktreeSafe = ([string]::IsNullOrWhiteSpace($anchor.worktree) -or (Test-ContinuityScalar -Value $anchor.worktree -Path))
    $anchorCommitSafe = ([string]::IsNullOrWhiteSpace($anchor.last_verified_commit) -or $anchor.last_verified_commit -match '^[0-9a-fA-F]{7,64}$')
    $base = [ordered]@{
        id = $id
        path = $snapshot.path
        revision = [string]$snapshot.revision
        read_only = $true
        classification = $null
        degraded = $false
        reason_code = "none"
        anchor = [ordered]@{
            branch = $(if ($anchorBranchSafe) { [string]$anchor.branch } else { "" })
            worktree = $(if ($anchorWorktreeSafe) { [string]$anchor.worktree } else { "" })
            last_verified_commit = $(if ($anchorCommitSafe) { ([string]$anchor.last_verified_commit).ToLowerInvariant() } else { "" })
        }
    }
    if (-not $anchorBranchSafe -or -not $anchorWorktreeSafe) { $base.degraded = $true; $base.reason_code = "unsafe-git-anchor"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
    $probeRoot = Resolve-ContinuityWorktreeRoot -Root $Root -Worktree $anchor.worktree
    if ($null -eq $probeRoot) { $base.degraded = $true; $base.reason_code = "worktree-unavailable"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
    $gitFindings = New-Object 'System.Collections.Generic.List[object]'
    $git = Get-GitState -Root $probeRoot -Findings $gitFindings
    $gitBranchSafe = ($git.state -ne "available" -or (Test-ContinuityScalar -Value ([string]$git.branch) -AllowEmpty))
    $gitHeadSafe = ($git.state -ne "available" -or [string]$git.head -match '^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$')
    $base.git = [ordered]@{ state = $git.state; branch = $(if ($git.state -eq "available" -and $gitBranchSafe) { [string]$git.branch } else { "" }); head = $(if ($git.state -eq "available" -and $gitHeadSafe) { ([string]$git.head).ToLowerInvariant() } else { "" }); staged = $git.staged; unstaged = $git.unstaged; untracked = $git.untracked; status_count = $git.status_count; shallow = $git.shallow; detached = $git.detached }
    if ($git.state -ne "available") { $base.degraded = $true; $base.reason_code = "git-unavailable"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
    if (-not $gitBranchSafe -or -not $gitHeadSafe) { $base.degraded = $true; $base.reason_code = "unsafe-git-state"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
    if ($git.detached -and -not [string]::IsNullOrWhiteSpace($anchor.branch)) { $base.degraded = $true; $base.reason_code = "detached-head"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
    if ($anchor.branch -and $git.branch -cne $anchor.branch) { $base.classification = "diverged"; $base.reason_code = "branch-mismatch"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
    $anchorCommit = $anchor.last_verified_commit
    if ([string]::IsNullOrWhiteSpace($anchorCommit)) { $base.degraded = $true; $base.reason_code = "missing-commit-anchor"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
    if (-not $anchorCommitSafe) { $base.degraded = $true; $base.reason_code = "invalid-commit-anchor"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
    $resolved = Invoke-GitProbe -Root $probeRoot -Arguments @("rev-parse", ($anchorCommit + "^{commit}"))
    if ([int]$resolved.exit_code -ne 0 -or [string]$resolved.text -notmatch '^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$') {
        $base.degraded = $true
        $base.reason_code = if ([bool]$git.shallow) { "shallow-history-unknown" } else { "missing-commit-anchor" }
        return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base
    }
    $anchorFull = ([string]$resolved.text).ToLowerInvariant(); $head = ([string]$git.head).ToLowerInvariant()
    if ($anchorFull.Length -ne $head.Length) { $base.degraded = $true; $base.reason_code = "oid-algorithm-mismatch"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
    $relation = "exact"
    if ($anchorFull -cne $head) {
        $ancestor = Invoke-GitProbe -Root $probeRoot -Arguments @("merge-base", "--is-ancestor", $anchorFull, "HEAD")
        if ([int]$ancestor.exit_code -eq 0) { $relation = "advanced" }
        elseif ([int]$ancestor.exit_code -eq 1 -and [bool]$git.shallow) { $base.degraded = $true; $base.reason_code = "shallow-history-unknown"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
        elseif ([int]$ancestor.exit_code -eq 1) { $relation = "diverged" }
        else { $base.degraded = $true; $base.reason_code = "ancestry-unavailable"; return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base }
    }
    $base.base_relation = $relation
    $base.anchor.resolved_commit = $anchorFull
    if ($relation -eq "diverged") { $base.classification = "diverged" }
    elseif ([bool]$git.staged -or [bool]$git.unstaged -or [bool]$git.untracked) { $base.classification = "dirty" }
    elseif ($relation -eq "advanced") { $base.classification = "advanced" }
    else { $base.classification = "exact" }
    return New-ContinuityResult -Operation "recover-work" -Status "PASS" -Extra $base
}

function Invoke-ContinuityOperation {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    Assert-ContinuityOperationParameters -Operation $Operation -BoundParameters $BoundParameters
    $rootFull = Resolve-ContinuityRoot -Root $Root
    switch ($Operation) {
        "create-work" { return Invoke-ContinuityCreateWork -Root $rootFull -BoundParameters $BoundParameters }
        "checkpoint" { return Invoke-ContinuityCheckpoint -Root $rootFull -BoundParameters $BoundParameters }
        "set-status" { return Invoke-ContinuitySetStatus -Root $rootFull -BoundParameters $BoundParameters }
        "complete" { return Invoke-ContinuityComplete -Root $rootFull -BoundParameters $BoundParameters }
        "recover-work" { return Invoke-ContinuityRecoverWork -Root $rootFull -BoundParameters $BoundParameters }
        default { throw "unsupported continuity operation" }
    }
}
