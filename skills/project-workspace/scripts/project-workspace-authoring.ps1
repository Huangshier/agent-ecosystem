# Internal Context, Procedure, Spec, and Procedure-to-Skill authoring responsibilities.
# This file is dot-sourced only by project-workspace.ps1.  It never writes the
# disposable Catalog; discover remains the only Catalog writer.

$script:AuthoringCommonParameters = @(
    "Operation", "Mode", "ProjectRoot", "Json", "NoExit",
    "Verbose", "Debug", "ErrorAction", "WarningAction", "InformationAction",
    "ProgressAction", "ErrorVariable", "WarningVariable", "InformationVariable",
    "OutVariable", "OutBuffer", "PipelineVariable"
)

function Resolve-AuthoringRoot {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Resolve-ContinuityRoot -Root $Root)
}

function New-AuthoringFinding {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [AllowEmptyString()][string]$Path = "",
        [string]$Field = "",
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("error", "warning")][string]$Severity = "error"
    )
    return [ordered]@{
        code = $Code
        path = $Path
        field = $Field
        severity = $Severity
        message = $Message
    }
}

function New-AuthoringFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][bool]$ReadOnly,
        [Parameter(Mandatory = $true)][string]$Code,
        [AllowEmptyString()][string]$Path = "",
        [string]$Field = "",
        [Parameter(Mandatory = $true)][string]$Message,
        [System.Collections.IDictionary]$Extra = $null
    )
    $result = [ordered]@{
        operation = $Operation
        status = "FAIL"
        read_only = $ReadOnly
        findings = @((New-AuthoringFinding -Code $Code -Path $Path -Field $Field -Message $Message))
    }
    if ($null -ne $Extra) {
        foreach ($key in @($Extra.Keys)) { $result[$key] = $Extra[$key] }
    }
    return $result
}

function Get-AuthoringBound {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($BoundParameters -is [hashtable]) { return [bool]$BoundParameters.ContainsKey($Name) }
    if ($BoundParameters.PSObject.Methods.Name -contains "ContainsKey") { return [bool]$BoundParameters.ContainsKey($Name) }
    if ($BoundParameters.PSObject.Methods.Name -contains "Contains") { return [bool]$BoundParameters.Contains($Name) }
    return (@($BoundParameters.Keys | ForEach-Object { [string]$_ }) -ccontains $Name)
}

function Get-AuthoringValue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters,
        [Parameter(Mandatory = $true)][string[]]$Names,
        [object]$Default = $null
    )
    foreach ($name in @($Names)) {
        if (Get-AuthoringBound -BoundParameters $BoundParameters -Name $name) {
            return ,$BoundParameters[$name]
        }
    }
    return ,$Default
}

function Get-AuthoringList {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters,
        [Parameter(Mandatory = $true)][string[]]$Names
    )
    $value = Get-AuthoringValue -BoundParameters $BoundParameters -Names $Names
    if ($null -eq $value) { return @() }
    if ($value -is [string]) { return @([string]$value) }
    return @($value | ForEach-Object { [string]$_ })
}

function Test-AuthoringId {
    param([AllowEmptyString()][string]$Id)
    return ($Id -match '^[a-z0-9]+(?:-[a-z0-9]+)*$')
}

function Test-AuthoringDateTime {
    param([AllowEmptyString()][string]$Value)
    if ($Value -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})$') { return $false }
    try {
        [DateTimeOffset]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) | Out-Null
        return $true
    }
    catch { return $false }
}

function Assert-AuthoringScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Value
    )
    if (-not (Test-ContinuityScalar -Value $Value)) { throw ("invalid parameter: {0}" -f $Name) }
}

function Assert-AuthoringList {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyCollection()][string[]]$Values = @(),
        [switch]$Required
    )
    if ($Required.IsPresent -and @($Values).Count -eq 0) { throw ("missing parameter: {0}" -f $Name) }
    foreach ($value in @($Values)) { Assert-AuthoringScalar -Name $Name -Value ([string]$value) }
}

function Assert-AuthoringUpdated {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters,
        [string]$Default = ""
    )
    $value = if (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Updated") { [string]$BoundParameters.Updated } else { $Default }
    if ([string]::IsNullOrWhiteSpace($value)) { return (Get-ContinuityUtcNow) }
    if (-not (Test-AuthoringDateTime -Value $value)) { throw "invalid parameter: Updated" }
    return $value
}

function Get-AuthoringCanonicalPath {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("context", "procedure", "spec", "skill")][string]$Type,
        [Parameter(Mandatory = $true)][string]$Id
    )
    switch ($Type) {
        "context" { return ".agents/context/{0}.md" -f $Id }
        "procedure" { return ".agents/procedures/{0}.md" -f $Id }
        "spec" { return "docs/specs/{0}/spec.md" -f $Id }
        "skill" { return ".agents/skills/{0}/SKILL.md" -f $Id }
    }
}

function ConvertTo-AuthoringYamlScalar {
    param([AllowEmptyString()][string]$Value)
    return (ConvertTo-ContinuityYamlScalar -Value $Value)
}

function Add-AuthoringMetadataList {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object]$Lines,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyCollection()][string[]]$Values = @()
    )
    if (@($Values).Count -eq 0) {
        [void]$Lines.Add(("{0}: []" -f $Name))
        return
    }
    [void]$Lines.Add(("{0}:" -f $Name))
    foreach ($value in @($Values)) {
        [void]$Lines.Add(("  - {0}" -f (ConvertTo-AuthoringYamlScalar -Value ([string]$value))))
    }
}

function New-AuthoringFrontMatter {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Metadata)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    [void]$lines.Add("---")
    foreach ($field in @($Metadata.Keys)) {
        $value = $Metadata[$field]
        if ($value -is [System.Collections.IList] -and $value -isnot [string]) {
            Add-AuthoringMetadataList -Lines $lines -Name ([string]$field) -Values @($value | ForEach-Object { [string]$_ })
        }
        elseif ([string]$field -ceq "updated") {
            [void]$lines.Add(("updated: {0}" -f ([string]$value)))
        }
        else {
            [void]$lines.Add(("{0}: {1}" -f $field, (ConvertTo-AuthoringYamlScalar -Value ([string]$value))))
        }
    }
    [void]$lines.Add("---")
    return ($lines.ToArray() -join "`n")
}

function Add-AuthoringBodySection {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object]$Lines,
        [Parameter(Mandatory = $true)][string]$Heading,
        [AllowEmptyCollection()][string[]]$Values = @(),
        [switch]$Numbered
    )
    [void]$Lines.Add(("## {0}" -f $Heading))
    [void]$Lines.Add("")
    for ($index = 0; $index -lt @($Values).Count; $index++) {
        $prefix = if ($Numbered.IsPresent) { "{0}." -f ($index + 1) } else { "-" }
        [void]$Lines.Add(("{0} {1}" -f $prefix, [string]$Values[$index]))
    }
    [void]$Lines.Add("")
}

function New-ContextBody {
    param(
        [Parameter(Mandatory = $true)][string]$Summary,
        [Parameter(Mandatory = $true)][string[]]$Evidence
    )
    $lines = New-Object 'System.Collections.Generic.List[string]'
    Add-AuthoringBodySection -Lines $lines -Heading "Context" -Values @($Summary)
    Add-AuthoringBodySection -Lines $lines -Heading "Evidence" -Values $Evidence
    return (($lines.ToArray() -join "`n").TrimEnd() + "`n")
}

function New-ProcedureBody {
    param(
        [Parameter(Mandatory = $true)][string[]]$Preconditions,
        [Parameter(Mandatory = $true)][string[]]$Steps,
        [Parameter(Mandatory = $true)][string[]]$Validation,
        [Parameter(Mandatory = $true)][string[]]$StopBoundaries,
        [Parameter(Mandatory = $true)][string[]]$Authorization
    )
    $lines = New-Object 'System.Collections.Generic.List[string]'
    Add-AuthoringBodySection -Lines $lines -Heading "Preconditions" -Values $Preconditions
    Add-AuthoringBodySection -Lines $lines -Heading "Steps" -Values $Steps -Numbered
    Add-AuthoringBodySection -Lines $lines -Heading "Validation" -Values $Validation
    Add-AuthoringBodySection -Lines $lines -Heading "Stop Boundaries" -Values $StopBoundaries
    Add-AuthoringBodySection -Lines $lines -Heading "Authorization" -Values $Authorization
    return (($lines.ToArray() -join "`n").TrimEnd() + "`n")
}

function New-SpecBody {
    param(
        [Parameter(Mandatory = $true)][string[]]$Goals,
        [Parameter(Mandatory = $true)][string[]]$NonGoals,
        [Parameter(Mandatory = $true)][string[]]$Tradeoffs,
        [Parameter(Mandatory = $true)][string[]]$Acceptance
    )
    $lines = New-Object 'System.Collections.Generic.List[string]'
    Add-AuthoringBodySection -Lines $lines -Heading "Goals" -Values $Goals
    Add-AuthoringBodySection -Lines $lines -Heading "Non-goals" -Values $NonGoals
    Add-AuthoringBodySection -Lines $lines -Heading "Tradeoffs" -Values $Tradeoffs
    Add-AuthoringBodySection -Lines $lines -Heading "Acceptance" -Values $Acceptance
    return (($lines.ToArray() -join "`n").TrimEnd() + "`n")
}

function Get-AuthoringCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Text
    )
    if ($Type -ceq "skill") {
        $skill = Read-PromotedSkill -Root $Root -RelativePath $RelativePath -Text $Text
        if ([string]$skill.name -cne $Id -or [string]$skill.path -cne $RelativePath) { throw "standard Agent Skill candidate identity was rejected" }
        return [ordered]@{ text = $Text; path = $RelativePath; type = $Type; id = $Id }
    }
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-authoring-{0}" -f ([Guid]::NewGuid().ToString("N")))
    try {
        $candidatePath = Join-Path $tempRoot $RelativePath
        [IO.Directory]::CreateDirectory((Split-Path -Parent $candidatePath)) | Out-Null
        Write-ContinuityText -Path $candidatePath -Text $Text
        $parser = Invoke-CanonicalParser -Root $tempRoot -Paths @($RelativePath)
        if ($null -eq $parser.payload -or [string]$parser.payload.status -cne "PASS") { throw "canonical parser rejected candidate" }
        $asset = @($parser.payload.assets | Where-Object { [string]$_.path -ceq $RelativePath }) | Select-Object -First 1
        if ($null -eq $asset -or [bool]$asset.valid -ne $true -or [string]$asset.type -cne $Type -or [string]$asset.id -cne $Id) { throw "canonical parser rejected candidate identity" }
        return [ordered]@{ text = $Text; path = $RelativePath; type = $Type; id = $Id }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Write-AuthoringCreateNew {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $target = Assert-ProjectPath -Root $Root -RelativePath $RelativePath -AllowMissing
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    $rootPhysical = Resolve-ExistingPhysicalPath -Path $Root -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    $parentPhysical = Resolve-PhysicalPathForWrite -Path $parent
    if (-not (Test-PathIsEqualOrChild -Path $parentPhysical -Root $rootPhysical)) { throw "authoring parent escapes project root" }
    $tempName = ".authoring-{0}-{1}.tmp" -f ([IO.Path]::GetFileNameWithoutExtension($target)), ([Guid]::NewGuid().ToString("N"))
    $temp = Join-Path $parent $tempName
    try {
        Write-ContinuityText -Path $temp -Text $Text -CreateNew
        [IO.File]::Move($temp, $target, $false)
    }
    finally {
        if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Remove-AuthoringFile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )
    if (-not (Test-Path -LiteralPath (Join-Path $Root $RelativePath) -PathType Leaf)) { return }
    $target = Assert-ProjectPath -Root $Root -RelativePath $RelativePath
    $rootPhysical = Resolve-ExistingPhysicalPath -Path $Root -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    $targetPhysical = Resolve-ExistingPhysicalPath -Path $target -VisitedLinks (New-Object 'System.Collections.Generic.List[string]')
    if (-not (Test-PathIsEqualOrChild -Path $targetPhysical -Root $rootPhysical)) { throw "authoring target escapes project root" }
    [IO.File]::Delete($target)
}

function Write-AuthoringBytesCreateNew {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )
    $target = Assert-ProjectPath -Root $Root -RelativePath $RelativePath -AllowMissing
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    $stream = $null
    try {
        $stream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Write($Bytes, 0, $Bytes.Length)
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Assert-AuthoringOperationParameters {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    $allowed = switch ($Operation) {
        "create-context" { @("Id", "Title", "Summary", "Status", "Keywords", "Keyword", "Evidence", "Updated") }
        "create-procedure" { @("Id", "Title", "Summary", "Kind", "Triggers", "Trigger", "SideEffects", "SideEffect", "Preconditions", "Precondition", "Steps", "Step", "Validation", "StopBoundaries", "StopBoundary", "Stop", "Authorization", "Updated") }
        "create-spec" { @("Id", "Title", "Summary", "Status", "RelatedWork", "Supersedes", "Goals", "Goal", "NonGoals", "NonGoal", "Tradeoffs", "Tradeoff", "Acceptance", "Updated") }
        "promote-skill" { @("Id", "SkillName", "Name", "Analyze", "Apply", "AnalyzeEvidence", "ConfirmPromotion") }
        default { @() }
    }
    foreach ($key in @($BoundParameters.Keys)) {
        if ($key -notin $allowed -and $key -notin $script:AuthoringCommonParameters) { throw "unsupported parameter" }
    }
}

function Get-AuthoringCreateRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    if (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Id")) { throw "missing parameter: Id" }
    if (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Title")) { throw "missing parameter: Title" }
    if (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Summary")) { throw "missing parameter: Summary" }
    $id = [string]$BoundParameters.Id
    if (-not (Test-AuthoringId -Id $id)) { throw "invalid parameter: Id" }
    Assert-AuthoringScalar -Name "Title" -Value ([string]$BoundParameters.Title)
    Assert-AuthoringScalar -Name "Summary" -Value ([string]$BoundParameters.Summary)
    $updated = Assert-AuthoringUpdated -BoundParameters $BoundParameters

    if ($Operation -ceq "create-context") {
        $keywords = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Keywords", "Keyword")
        $evidence = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Evidence")
        if (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Keywords") -and -not (Get-AuthoringBound -BoundParameters -Name "Keyword")) { throw "missing parameter: Keywords" }
        if (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Evidence")) { throw "missing parameter: Evidence" }
        Assert-AuthoringList -Name "Keywords" -Values $keywords
        Assert-AuthoringList -Name "Evidence" -Values $evidence -Required
        $statusValues = if (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Status") { @($BoundParameters.Status) } else { @("active") }
        if (@($statusValues).Count -ne 1 -or [string]@($statusValues)[0] -notin @("active", "superseded", "archived")) { throw "invalid status" }
        $metadata = [ordered]@{
            schema = "agent-ecosystem/context/v1"
            id = $id
            title = [string]$BoundParameters.Title
            status = [string]@($statusValues)[0]
            updated = $updated
            summary = [string]$BoundParameters.Summary
            keywords = @($keywords)
            evidence = @($evidence)
        }
        return [ordered]@{ type = "context"; id = $id; relative_path = Get-AuthoringCanonicalPath -Type context -Id $id; metadata = $metadata; body = New-ContextBody -Summary ([string]$BoundParameters.Summary) -Evidence $evidence }
    }

    if ($Operation -ceq "create-procedure") {
        if (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Kind")) { throw "missing parameter: Kind" }
        $kind = [string]$BoundParameters.Kind
        if ($kind -notin @("command", "workflow")) { throw "invalid procedure kind" }
        foreach ($name in @("Triggers", "SideEffects", "Preconditions", "Steps", "Validation", "StopBoundaries", "Authorization")) {
            $alias = switch ($name) { "Triggers" { "Trigger" } "SideEffects" { "SideEffect" } "Preconditions" { "Precondition" } "Steps" { "Step" } "StopBoundaries" { "StopBoundary" } default { "" } }
            if (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name $name) -and ([string]::IsNullOrWhiteSpace($alias) -or -not (Get-AuthoringBound -BoundParameters $BoundParameters -Name $alias))) { throw ("missing parameter: {0}" -f $name) }
        }
        $triggers = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Triggers", "Trigger")
        $sideEffects = Get-AuthoringList -BoundParameters $BoundParameters -Names @("SideEffects", "SideEffect")
        $preconditions = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Preconditions", "Precondition")
        $steps = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Steps", "Step")
        $validation = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Validation")
        $stopBoundaries = Get-AuthoringList -BoundParameters $BoundParameters -Names @("StopBoundaries", "StopBoundary", "Stop")
        $authorization = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Authorization")
        Assert-AuthoringList -Name "Triggers" -Values $triggers
        Assert-AuthoringList -Name "SideEffects" -Values $sideEffects -Required
        Assert-AuthoringList -Name "Preconditions" -Values $preconditions -Required
        Assert-AuthoringList -Name "Steps" -Values $steps -Required
        Assert-AuthoringList -Name "Validation" -Values $validation -Required
        Assert-AuthoringList -Name "StopBoundaries" -Values $stopBoundaries -Required
        Assert-AuthoringList -Name "Authorization" -Values $authorization -Required
        $metadata = [ordered]@{
            schema = "agent-ecosystem/procedure/v1"
            id = $id
            title = [string]$BoundParameters.Title
            kind = $kind
            exposure = "internal"
            summary = [string]$BoundParameters.Summary
            triggers = @($triggers)
            side_effects = @($sideEffects)
        }
        return [ordered]@{ type = "procedure"; id = $id; relative_path = Get-AuthoringCanonicalPath -Type procedure -Id $id; metadata = $metadata; body = New-ProcedureBody -Preconditions $preconditions -Steps $steps -Validation $validation -StopBoundaries $stopBoundaries -Authorization $authorization }
    }

    if ($Operation -ceq "create-spec") {
        foreach ($name in @("Goals", "NonGoals", "Tradeoffs", "Acceptance")) {
            $alias = switch ($name) { "Goals" { "Goal" } "NonGoals" { "NonGoal" } "Tradeoffs" { "Tradeoff" } default { "" } }
            if (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name $name) -and ([string]::IsNullOrWhiteSpace($alias) -or -not (Get-AuthoringBound -BoundParameters $BoundParameters -Name $alias))) { throw ("missing parameter: {0}" -f $name) }
        }
        $relatedWork = Get-AuthoringList -BoundParameters $BoundParameters -Names @("RelatedWork")
        $supersedes = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Supersedes")
        $goals = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Goals", "Goal")
        $nonGoals = Get-AuthoringList -BoundParameters $BoundParameters -Names @("NonGoals", "NonGoal")
        $tradeoffs = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Tradeoffs", "Tradeoff")
        $acceptance = Get-AuthoringList -BoundParameters $BoundParameters -Names @("Acceptance")
        foreach ($value in @($relatedWork) + @($supersedes)) { if (-not (Test-AuthoringId -Id ([string]$value))) { throw "invalid spec reference" } }
        Assert-AuthoringList -Name "Goals" -Values $goals -Required
        Assert-AuthoringList -Name "NonGoals" -Values $nonGoals -Required
        Assert-AuthoringList -Name "Tradeoffs" -Values $tradeoffs -Required
        Assert-AuthoringList -Name "Acceptance" -Values $acceptance -Required
        $statusValues = if (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Status") { @($BoundParameters.Status) } else { @("draft") }
        if (@($statusValues).Count -ne 1 -or [string]@($statusValues)[0] -notin @("draft", "accepted", "implemented", "superseded", "archived")) { throw "invalid status" }
        $metadata = [ordered]@{
            schema = "agent-ecosystem/spec/v1"
            id = $id
            title = [string]$BoundParameters.Title
            status = [string]@($statusValues)[0]
            updated = $updated
            summary = [string]$BoundParameters.Summary
            related_work = @($relatedWork)
            supersedes = @($supersedes)
        }
        return [ordered]@{ type = "spec"; id = $id; relative_path = Get-AuthoringCanonicalPath -Type spec -Id $id; metadata = $metadata; body = New-SpecBody -Goals $goals -NonGoals $nonGoals -Tradeoffs $tradeoffs -Acceptance $acceptance }
    }
    throw "unsupported authoring operation"
}

function Invoke-AuthoringCreate {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    try { $request = Get-AuthoringCreateRequest -Operation $Operation -BoundParameters $BoundParameters }
    catch { return New-AuthoringFailure -Operation $Operation -ReadOnly $false -Code "invalid-input" -Message $_.Exception.Message }
    $relative = [string]$request.relative_path
    try { $target = Assert-ProjectPath -Root $Root -RelativePath $relative -AllowMissing } catch { return New-AuthoringFailure -Operation $Operation -ReadOnly $false -Code "unsafe-path" -Path $relative -Message "Canonical authoring path is not safe." }
    if (Test-Path -LiteralPath $target -PathType Leaf) { return New-AuthoringFailure -Operation $Operation -ReadOnly $false -Code "duplicate-asset" -Path $relative -Message "A canonical asset with this identity already exists." }
    $text = (New-AuthoringFrontMatter -Metadata $request.metadata) + "`n`n" + [string]$request.body
    try { Get-AuthoringCandidate -Root $Root -RelativePath $relative -Type ([string]$request.type) -Id ([string]$request.id) -Text $text | Out-Null }
    catch { return New-AuthoringFailure -Operation $Operation -ReadOnly $false -Code "candidate-invalid" -Path $relative -Message "Generated canonical asset did not pass the existing parser." }
    try { Write-AuthoringCreateNew -Root $Root -RelativePath $relative -Text $text }
    catch {
        $code = if (Test-Path -LiteralPath $target -PathType Leaf) { "duplicate-asset" } else { "write-failed" }
        return New-AuthoringFailure -Operation $Operation -ReadOnly $false -Code $code -Path $relative -Message "Canonical asset could not be created."
    }
    return [ordered]@{
        operation = $Operation
        status = "PASS"
        read_only = $false
        result = "created"
        type = [string]$request.type
        id = [string]$request.id
        path = $relative
        catalog_written = $false
        findings = @()
    }
}

function Get-AuthoringProcedureBody {
    param([Parameter(Mandatory = $true)][string]$Text)
    $lines = @($Text -split "`n")
    if ($lines.Count -lt 3 -or $lines[0] -cne "---") { throw "procedure frontmatter missing" }
    $closing = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ([string]$lines[$index] -ceq "---") { $closing = $index; break }
    }
    if ($closing -lt 0) { throw "procedure frontmatter closing delimiter missing" }
    return (($lines[($closing + 1)..($lines.Count - 1)] -join "`n").Trim())
}

function Test-AuthoringProcedureSections {
    param([Parameter(Mandatory = $true)][string]$Body)
    foreach ($heading in @("Preconditions", "Steps", "Validation", "Stop Boundaries", "Authorization")) {
        if ($Body -notmatch ("(?m)^## {0}\s*$" -f [regex]::Escape($heading))) { return $false }
    }
    return $true
}

function Get-AuthoringProcedureSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id
    )
    $relative = Get-AuthoringCanonicalPath -Type procedure -Id $Id
    $path = Assert-ProjectPath -Root $Root -RelativePath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "procedure does not exist" }
    $parser = Invoke-CanonicalParser -Root $Root -Paths @($relative)
    if ($null -eq $parser.payload -or [string]$parser.payload.status -cne "PASS") { throw "procedure is not canonical" }
    $asset = @($parser.payload.assets | Where-Object { [string]$_.path -ceq $relative }) | Select-Object -First 1
    if ($null -eq $asset -or [bool]$asset.valid -ne $true -or [string]$asset.type -cne "procedure" -or [string]$asset.id -cne $Id) { throw "procedure identity is invalid" }
    $text = Read-StrictUtf8Text -Path $path
    $body = Get-AuthoringProcedureBody -Text $text
    if (-not (Test-AuthoringProcedureSections -Body $body)) { throw "procedure body is missing a required boundary section" }
    if (-not (Test-PublicSafeText -Text $text)) { throw "procedure contains unsafe output material" }
    $metadata = Get-PropertyValue -Object $asset -Name "metadata"
    return [ordered]@{
        id = $Id
        path = $relative
        full_path = $path
        text = $text
        body = $body
        metadata = $metadata
        normalized_hash = Get-NormalizedTextHash -Path $path
        bytes = [IO.File]::ReadAllBytes($path)
    }
}

# Get-AuthoringPromotionEvidence: bind the current Procedure and deterministic candidate to one reusable evidence hash.
function Get-AuthoringPromotionEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$ProcedurePath,
        [Parameter(Mandatory = $true)][string]$ProcedureHash,
        [Parameter(Mandatory = $true)][string]$SkillPath,
        [Parameter(Mandatory = $true)][string]$SkillName,
        [Parameter(Mandatory = $true)][string]$CandidateHash
    )

    $lines = @(
        "promotion-contract=agent-ecosystem/procedure-to-skill/v1",
        ("procedure_path={0}" -f $ProcedurePath),
        ("procedure_hash={0}" -f $ProcedureHash),
        ("skill_path={0}" -f $SkillPath),
        ("skill_name={0}" -f $SkillName),
        ("candidate_hash={0}" -f $CandidateHash),
        "delete_source=true"
    )
    return Get-Sha256 -Bytes ([Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n")))
}

function New-AuthoringSkillPlan {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    if (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Id")) { throw "missing parameter: Id" }
    $procedureId = [string]$BoundParameters.Id
    if (-not (Test-AuthoringId -Id $procedureId)) { throw "invalid parameter: Id" }
    $snapshot = Get-AuthoringProcedureSnapshot -Root $Root -Id $procedureId
    $skillName = if (Get-AuthoringBound -BoundParameters $BoundParameters -Name "SkillName") { [string]$BoundParameters.SkillName } else { $procedureId }
    if ([string]::IsNullOrWhiteSpace($skillName)) { $skillName = $procedureId }
    if (-not (Test-AuthoringId -Id $skillName) -or $skillName.Length -gt 64) { throw "invalid parameter: SkillName" }
    $skillPath = Get-AuthoringCanonicalPath -Type skill -Id $skillName
    $skillTarget = Assert-ProjectPath -Root $Root -RelativePath $skillPath -AllowMissing
    if (Test-Path -LiteralPath $skillTarget -PathType Leaf) { throw "target Skill already exists" }
    $procedureMetadata = $snapshot.metadata
    $triggers = @(Get-StringList (Get-PropertyValue -Object $procedureMetadata -Name "triggers"))
    $sideEffects = @(Get-StringList (Get-PropertyValue -Object $procedureMetadata -Name "side_effects"))
    $description = "{0} Use when {1}." -f ([string](Get-PropertyValue -Object $procedureMetadata -Name "summary")), $(if ($triggers.Count -gt 0) { $triggers -join "; " } else { "the caller explicitly selects this promoted Skill" })
    if ([string]::IsNullOrWhiteSpace($description) -or $description.Length -gt 1024) { throw "generated Skill description exceeds the Agent Skills limit" }
    $skillMetadata = [ordered]@{
        name = $skillName
        description = $description
    }
    $boundaryLines = @(
        "## Promotion boundary",
        "",
        ("- Original Procedure: {0} (deleted only by explicit Apply)." -f $snapshot.path),
        "- Agent-native discovery does not grant execution authorization.",
        "- Procedure authorization and side_effects remain explicit and unchanged.",
        ("- Declared side_effects: {0}." -f ($sideEffects -join "; ")),
        "- This Skill does not execute itself during discovery or analysis.",
        ""
    )
    $skillBody = (($snapshot.body.TrimEnd()) + "`n`n" + ($boundaryLines -join "`n") + "`n")
    $text = (New-AuthoringFrontMatter -Metadata $skillMetadata) + "`n`n" + $skillBody
    Get-AuthoringCandidate -Root $Root -RelativePath $skillPath -Type "skill" -Id $skillName -Text $text | Out-Null
    $candidateHash = Get-Sha256 -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($text))
    $evidence = Get-AuthoringPromotionEvidence -ProcedurePath $snapshot.path -ProcedureHash $snapshot.normalized_hash -SkillPath $skillPath -SkillName $skillName -CandidateHash $candidateHash
    return [ordered]@{
        procedure = $snapshot
        skill_name = $skillName
        skill_path = $skillPath
        skill_full_path = $skillTarget
        skill_metadata = $skillMetadata
        skill_text = $text
        candidate_hash = $candidateHash
        evidence = $evidence
        side_effects = @($sideEffects)
        authorization_boundary = @(
            "Original Procedure authorization section is preserved in the generated Skill body.",
            "Promotion changes discovery exposure only; it does not authorize implicit execution."
        )
        manual_conditions = @(
            "The Procedure has been used repeatedly and is stable.",
            "The Procedure inputs, outputs, and stop conditions are stable.",
            "The Procedure clearly benefits from Agent-native discovery.",
            "The Skill description is not prone to accidental triggering.",
            "The authorization and side_effects boundaries are clear.",
            "The caller has reviewed the generated Skill candidate and understands that Apply deletes the original Procedure."
        )
    }
}

function Get-AuthoringPlanResult {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Plan
    )
    return [ordered]@{
        operation = $Operation
        status = "PASS"
        read_only = $true
        result = "analyzed"
        source_procedure = [string]$Plan.procedure.path
        source_hash = [string]$Plan.procedure.normalized_hash
        candidate_path = [string]$Plan.skill_path
        candidate = [string]$Plan.skill_text
        candidate_hash = [string]$Plan.candidate_hash
        evidence = [string]$Plan.evidence
        evidence_hash = [string]$Plan.evidence
        delete_source = $true
        authority_before = "procedure"
        authority_after_apply = "skill"
        catalog_written = $false
        boundary_changes = @(
            "Internal Procedure becomes project-local Agent Skill discovery surface.",
            "Original Procedure is deleted only during explicit Apply.",
            "Authorization and side_effects remain explicit; discovery is not execution authorization."
        )
        authorization = @($Plan.authorization_boundary)
        side_effects = @($Plan.side_effects)
        manual_conditions = @($Plan.manual_conditions)
        apply_requires = @("Analyze evidence", "ConfirmPromotion")
        findings = @()
    }
}

function Invoke-AuthoringPromoteApply {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Plan
    )
    $operation = "promote-skill"
    try { Write-AuthoringCreateNew -Root $Root -RelativePath ([string]$Plan.skill_path) -Text ([string]$Plan.skill_text) }
    catch { return New-AuthoringFailure -Operation $operation -ReadOnly $false -Code "skill-write-failed" -Path ([string]$Plan.skill_path) -Message "Skill could not be created; the original Procedure was retained." }

    $sourceStillSame = $false
    try { $sourceStillSame = (Get-NormalizedTextHash -Path ([string]$Plan.procedure.full_path)) -ceq [string]$Plan.procedure.normalized_hash } catch { $sourceStillSame = $false }
    if (-not $sourceStillSame) {
        try { Remove-AuthoringFile -Root $Root -RelativePath ([string]$Plan.skill_path) } catch { }
        return New-AuthoringFailure -Operation $operation -ReadOnly $false -Code "procedure-changed" -Path ([string]$Plan.procedure.path) -Message "The Procedure changed before deletion; the new Skill was removed and the original was retained." -Extra ([ordered]@{ recovery = "skill-removed"; no_dual_authority = $true })
    }

    try { Remove-AuthoringFile -Root $Root -RelativePath ([string]$Plan.procedure.path) }
    catch {
        try { Remove-AuthoringFile -Root $Root -RelativePath ([string]$Plan.skill_path) } catch { }
        return New-AuthoringFailure -Operation $operation -ReadOnly $false -Code "procedure-delete-failed" -Path ([string]$Plan.procedure.path) -Message "The original Procedure could not be deleted; the new Skill was removed." -Extra ([ordered]@{ recovery = "skill-removed"; no_dual_authority = $true })
    }

    $verified = $false
    try {
        $skill = Read-PromotedSkill -Root $Root -RelativePath ([string]$Plan.skill_path)
        $verified = ([string]$skill.normalized_hash -ceq [string]$Plan.candidate_hash -and
            -not (Test-Path -LiteralPath (Join-Path $Root ([string]$Plan.procedure.path))))
    }
    catch { $verified = $false }
    if (-not $verified) {
        $recovered = $false
        try {
            Remove-AuthoringFile -Root $Root -RelativePath ([string]$Plan.skill_path)
            Write-AuthoringBytesCreateNew -Root $Root -RelativePath ([string]$Plan.procedure.path) -Bytes ([byte[]]$Plan.procedure.bytes)
            $recovered = $true
        }
        catch { $recovered = $false }
        return New-AuthoringFailure -Operation $operation -ReadOnly $false -Code "promotion-verify-failed" -Path ([string]$Plan.skill_path) -Message "Promotion verification failed; minimal recovery was attempted." -Extra ([ordered]@{ recovery = if ($recovered) { "procedure-restored-skill-removed" } else { "recovery-failed" }; no_dual_authority = $recovered })
    }
    return [ordered]@{
        operation = $operation
        status = "PASS"
        read_only = $false
        result = "promoted"
        source_procedure = [string]$Plan.procedure.path
        skill_path = [string]$Plan.skill_path
        procedure_deleted = $true
        skill_created = $true
        no_dual_authority = $true
        catalog_written = $false
        authorization = @($Plan.authorization_boundary)
        side_effects = @($Plan.side_effects)
        findings = @()
    }
}

function Invoke-AuthoringPromote {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    $analyze = Get-AuthoringBound -BoundParameters $BoundParameters -Name "Analyze"
    $apply = Get-AuthoringBound -BoundParameters $BoundParameters -Name "Apply"
    if ($analyze -and $apply) { return New-AuthoringFailure -Operation "promote-skill" -ReadOnly $false -Code "invalid-mode" -Message "Analyze and Apply are mutually exclusive." }
    if (-not $analyze -and -not $apply) { return New-AuthoringFailure -Operation "promote-skill" -ReadOnly $false -Code "explicit-mode-required" -Message "promote-skill requires explicit Analyze or Apply." }
    if ($analyze -and (Get-AuthoringBound -BoundParameters $BoundParameters -Name "AnalyzeEvidence")) {
        return New-AuthoringFailure -Operation "promote-skill" -ReadOnly $true -Code "invalid-mode" -Message "Analyze cannot consume Apply evidence."
    }
    if ($apply -and (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name "AnalyzeEvidence") -or [string]::IsNullOrWhiteSpace([string]$BoundParameters.AnalyzeEvidence))) {
        return New-AuthoringFailure -Operation "promote-skill" -ReadOnly $false -Code "analyze-evidence-required" -Message "Apply requires evidence returned by Analyze."
    }
    if ($apply -and (-not (Get-AuthoringBound -BoundParameters $BoundParameters -Name "ConfirmPromotion") -or -not [bool]$BoundParameters.ConfirmPromotion)) {
        return New-AuthoringFailure -Operation "promote-skill" -ReadOnly $false -Code "confirmation-required" -Message "Apply requires explicit confirmation of the promotion conditions."
    }
    try { $plan = New-AuthoringSkillPlan -Root $Root -BoundParameters $BoundParameters }
    catch {
        return New-AuthoringFailure -Operation "promote-skill" -ReadOnly ([bool]$analyze) -Code "promotion-not-ready" -Message $_.Exception.Message
    }
    if ($analyze) { return Get-AuthoringPlanResult -Operation "promote-skill" -Plan $plan }
    if ([string]$BoundParameters.AnalyzeEvidence -cne [string]$plan.evidence) {
        return New-AuthoringFailure -Operation "promote-skill" -ReadOnly $false -Code "stale-analyze-evidence" -Path ([string]$plan.procedure.path) -Message "Analyze evidence does not match the current Procedure and candidate baseline." -Extra ([ordered]@{ expected_evidence = [string]$plan.evidence; current_source_hash = [string]$plan.procedure.normalized_hash; candidate_hash = [string]$plan.candidate_hash })
    }
    return Invoke-AuthoringPromoteApply -Root $Root -Plan $plan
}

function Invoke-AuthoringOperation {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters
    )
    $isAnalyze = ($Operation -ceq "promote-skill" -and (Get-AuthoringBound -BoundParameters $BoundParameters -Name "Analyze"))
    try {
        Assert-AuthoringOperationParameters -Operation $Operation -BoundParameters $BoundParameters
        $rootFull = Resolve-ContinuityRoot -Root $Root
        switch ($Operation) {
            "create-context" { return Invoke-AuthoringCreate -Operation $Operation -Root $rootFull -BoundParameters $BoundParameters }
            "create-procedure" { return Invoke-AuthoringCreate -Operation $Operation -Root $rootFull -BoundParameters $BoundParameters }
            "create-spec" { return Invoke-AuthoringCreate -Operation $Operation -Root $rootFull -BoundParameters $BoundParameters }
            "promote-skill" { return Invoke-AuthoringPromote -Root $rootFull -BoundParameters $BoundParameters }
            default { return New-AuthoringFailure -Operation $Operation -ReadOnly $false -Code "unsupported-operation" -Message "Unsupported authoring operation." }
        }
    }
    catch {
        return New-AuthoringFailure -Operation $Operation -ReadOnly $isAnalyze -Code "authoring-failed-closed" -Message "Project workspace authoring failed closed."
    }
}
