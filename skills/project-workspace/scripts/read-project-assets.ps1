#requires -Version 7.6

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string[]]$AssetPath = @(),
    [string]$SchemaRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "../../.."))
. (Join-Path $repoRoot "scripts/validation/powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime
. (Join-Path $repoRoot "scripts/lib/path-guard.ps1")

$schemaFiles = [ordered]@{
    work = "work-item.v1.schema.json"
    context = "context.v1.schema.json"
    procedure = "procedure.v1.schema.json"
    spec = "spec.v1.schema.json"
}
$schemaUris = [ordered]@{
    work = "agent-ecosystem/work-item/v1"
    context = "agent-ecosystem/context/v1"
    procedure = "agent-ecosystem/procedure/v1"
    spec = "agent-ecosystem/spec/v1"
}

# Add-AssetFinding: appends one structured parser finding; it returns no value and never changes project files.
function Add-AssetFinding {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path,
        [string]$Field = "",
        [Parameter(Mandatory = $true)][string]$Message
    )

    $Findings.Add([ordered]@{
        code = $Code
        path = $Path
        field = $Field
        message = $Message
    })
}

# Throw-FrontMatterError: raises a typed frontmatter error with a stable code and optional field for the caller to report.
function Throw-FrontMatterError {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [string]$Field = "",
        [Parameter(Mandatory = $true)][string]$Message
    )

    $exception = [System.IO.InvalidDataException]::new($Message)
    $exception.Data["asset_code"] = $Code
    $exception.Data["asset_field"] = $Field
    throw $exception
}

# Get-ObjectPropertyNames: returns deterministic property names for dictionaries or PowerShell objects; null yields an empty list.
function Get-ObjectPropertyNames {
    param([object]$Object)

    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.Keys | ForEach-Object { [string]$_ })
    }
    if ($null -eq $Object) {
        return @()
    }
    return @($Object.PSObject.Properties.Name)
}

# Get-ObjectPropertyValue: returns one named value without unrolling list values; missing properties return null.
function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            Write-Output -NoEnumerate $Object[$Name]
            return
        }
        return $null
    }
    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    Write-Output -NoEnumerate $property.Value
}

# Test-ObjectHasProperty: reports whether a dictionary or PowerShell object explicitly contains the requested property.
function Test-ObjectHasProperty {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }
    return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
}

# Test-IsMapping: reports whether a parsed value is an object-like YAML mapping.
function Test-IsMapping {
    param([object]$Value)

    return ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject])
}

# Test-IsList: reports whether a parsed value is a non-string YAML sequence.
function Test-IsList {
    param([object]$Value)

    return ($null -ne $Value -and $Value -is [System.Collections.IList] -and $Value -isnot [string])
}

# Test-SafeProjectRelativePath: accepts only non-empty, non-rooted paths without dot segments or invalid file-name characters.
function Test-SafeProjectRelativePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path)) {
        return $false
    }
    if ($Path -match '^[A-Za-z]:' -or $Path -match '(^|[\\/])\.\.?(?:[\\/]|$)') {
        return $false
    }
    $segments = @($Path -split '[\\/]')
    if ($segments.Count -eq 0 -or @($segments | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        return $false
    }
    foreach ($segment in $segments) {
        if ($segment.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            return $false
        }
    }
    return $true
}

# Test-ProjectRelativePathBoundary: verifies lexical containment and, when the target exists, rejects links that escape the physical root.
function Test-ProjectRelativePathBoundary {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$PhysicalRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if (-not (Test-SafeProjectRelativePath -Path $RelativePath)) {
        return $false
    }
    $fullPath = Get-NormalizedFullPath -Path (Join-Path $Root $RelativePath)
    if (-not (Test-PathIsEqualOrChild -Path $fullPath -Root $Root)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return $true
    }
    try {
        $visitedLinks = New-Object 'System.Collections.Generic.List[string]'
        $physicalPath = Resolve-ExistingPhysicalPath -Path $fullPath -VisitedLinks $visitedLinks
        return (Test-PathIsEqualOrChild -Path $physicalPath -Root $PhysicalRoot)
    }
    catch {
        return $false
    }
}

# ConvertTo-NormalizedRelativePath: returns a slash-normalized path relative to the supplied project root.
function ConvertTo-NormalizedRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    return [System.IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
}

# Get-CanonicalAssetDescriptor: maps a canonical relative path to its asset type and path-derived id; other paths return null.
function Get-CanonicalAssetDescriptor {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $match = [regex]::Match($RelativePath, '^\.agents/work/(?<id>[a-z0-9]+(?:-[a-z0-9]+)*)\.md$', 'CultureInvariant')
    if ($match.Success) {
        return [ordered]@{ type = "work"; path_id = $match.Groups["id"].Value }
    }
    $match = [regex]::Match($RelativePath, '^\.agents/context/(?<id>[a-z0-9]+(?:-[a-z0-9]+)*)\.md$', 'CultureInvariant')
    if ($match.Success) {
        return [ordered]@{ type = "context"; path_id = $match.Groups["id"].Value }
    }
    $match = [regex]::Match($RelativePath, '^\.agents/procedures/(?<id>[a-z0-9]+(?:-[a-z0-9]+)*)\.md$', 'CultureInvariant')
    if ($match.Success) {
        return [ordered]@{ type = "procedure"; path_id = $match.Groups["id"].Value }
    }
    $match = [regex]::Match($RelativePath, '^docs/specs/(?<id>[a-z0-9]+(?:-[a-z0-9]+)*)/spec\.md$', 'CultureInvariant')
    if ($match.Success) {
        return [ordered]@{ type = "spec"; path_id = $match.Groups["id"].Value }
    }
    return $null
}

# ConvertFrom-FrontMatterScalar: parses the deliberately constrained scalar subset and rejects executable or complex YAML forms.
function ConvertFrom-FrontMatterScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Field = ""
    )

    $value = $Text.Trim()
    if ($value -eq "[]") {
        Write-Output -NoEnumerate ([System.Collections.ArrayList]::new())
        return
    }
    if ($value.StartsWith('[') -or $value.StartsWith('{') -or $value.StartsWith('&') -or
        $value.StartsWith('*') -or $value.StartsWith('!') -or $value -in @('|', '>')) {
        Throw-FrontMatterError -Code "malformed-frontmatter" -Field $Field -Message "Unsupported YAML syntax in field '$Field'."
    }
    if ($value.StartsWith('"')) {
        if (-not $value.EndsWith('"') -or $value.Length -lt 2) {
            Throw-FrontMatterError -Code "malformed-frontmatter" -Field $Field -Message "Malformed quoted scalar in field '$Field'."
        }
        try {
            return ($value | ConvertFrom-Json -ErrorAction Stop)
        }
        catch {
            Throw-FrontMatterError -Code "malformed-frontmatter" -Field $Field -Message "Malformed quoted scalar in field '$Field'."
        }
    }
    if ($value.StartsWith("'")) {
        if (-not $value.EndsWith("'") -or $value.Length -lt 2) {
            Throw-FrontMatterError -Code "malformed-frontmatter" -Field $Field -Message "Malformed quoted scalar in field '$Field'."
        }
        return $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    if ($value -match '^(?:null|~)$') {
        return $null
    }
    if ($value -match '^(?:true|false)$') {
        return [bool]::Parse($value)
    }
    if ($value -match '^-?(?:0|[1-9][0-9]*)$') {
        $integer = 0L
        if ([long]::TryParse($value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$integer)) {
            return $integer
        }
    }
    if ($value -match '^-?(?:0|[1-9][0-9]*)\.[0-9]+$') {
        $decimal = 0D
        if ([decimal]::TryParse($value, [Globalization.NumberStyles]::Number, [Globalization.CultureInfo]::InvariantCulture, [ref]$decimal)) {
            return $decimal
        }
    }
    if ($value -match '\s+#') {
        Throw-FrontMatterError -Code "malformed-frontmatter" -Field $Field -Message "Inline YAML comments are not supported in field '$Field'."
    }
    return $value
}

# ConvertFrom-AssetFrontMatter: parses bounded frontmatter lines into scalar, list, or one-level object values without evaluating tags.
function ConvertFrom-AssetFrontMatter {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Lines)

    $result = [ordered]@{}
    $currentKey = ""
    $currentKind = ""

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $rawLine = [string]$Lines[$index]
        if ($rawLine.Contains("`t")) {
            Throw-FrontMatterError -Code "malformed-frontmatter" -Message "Tabs are not allowed in YAML frontmatter."
        }
        if ([string]::IsNullOrWhiteSpace($rawLine) -or $rawLine.TrimStart().StartsWith('#')) {
            continue
        }
        $indent = $rawLine.Length - $rawLine.TrimStart(' ').Length
        $content = $rawLine.Substring($indent)

        if ($indent -eq 0) {
            $match = [regex]::Match($content, '^(?<key>[a-z][a-z0-9_]*):(?:[ ](?<value>.*))?$')
            if (-not $match.Success) {
                Throw-FrontMatterError -Code "malformed-frontmatter" -Message ("Malformed YAML at frontmatter line {0}." -f ($index + 1))
            }
            $key = $match.Groups["key"].Value
            if ($result.Contains($key)) {
                Throw-FrontMatterError -Code "malformed-frontmatter" -Field $key -Message "Duplicate YAML key '$key'."
            }
            $rawValue = $match.Groups["value"].Value
            $currentKey = $key
            $currentKind = ""
            if (-not [string]::IsNullOrEmpty($rawValue)) {
                $result[$key] = ConvertFrom-FrontMatterScalar -Text $rawValue -Field $key
                $currentKey = ""
            }
            continue
        }

        if ($indent -ne 2 -or [string]::IsNullOrWhiteSpace($currentKey)) {
            Throw-FrontMatterError -Code "malformed-frontmatter" -Message ("Unsupported YAML indentation at frontmatter line {0}." -f ($index + 1))
        }

        if ($content.StartsWith('- ')) {
            if ([string]::IsNullOrEmpty($currentKind)) {
                $result[$currentKey] = [System.Collections.ArrayList]::new()
                $currentKind = "list"
            }
            if ($currentKind -ne "list") {
                Throw-FrontMatterError -Code "malformed-frontmatter" -Field $currentKey -Message "YAML field '$currentKey' mixes list and object values."
            }
            $itemText = $content.Substring(2)
            if ([string]::IsNullOrWhiteSpace($itemText)) {
                Throw-FrontMatterError -Code "malformed-frontmatter" -Field $currentKey -Message "YAML list '$currentKey' contains an empty item."
            }
            [void]$result[$currentKey].Add((ConvertFrom-FrontMatterScalar -Text $itemText -Field $currentKey))
            continue
        }

        $childMatch = [regex]::Match($content, '^(?<key>[a-z][a-z0-9_]*):[ ](?<value>.+)$')
        if (-not $childMatch.Success) {
            Throw-FrontMatterError -Code "malformed-frontmatter" -Field $currentKey -Message ("Malformed nested YAML at frontmatter line {0}." -f ($index + 1))
        }
        if ([string]::IsNullOrEmpty($currentKind)) {
            $result[$currentKey] = [ordered]@{}
            $currentKind = "object"
        }
        if ($currentKind -ne "object") {
            Throw-FrontMatterError -Code "malformed-frontmatter" -Field $currentKey -Message "YAML field '$currentKey' mixes object and list values."
        }
        $childKey = $childMatch.Groups["key"].Value
        if ($result[$currentKey].Contains($childKey)) {
            Throw-FrontMatterError -Code "malformed-frontmatter" -Field ("{0}.{1}" -f $currentKey, $childKey) -Message "Duplicate YAML key '$currentKey.$childKey'."
        }
        $result[$currentKey][$childKey] = ConvertFrom-FrontMatterScalar -Text $childMatch.Groups["value"].Value -Field ("{0}.{1}" -f $currentKey, $childKey)
    }

    if (-not [string]::IsNullOrWhiteSpace($currentKey) -and -not $result.Contains($currentKey)) {
        $result[$currentKey] = $null
    }
    return $result
}

# Read-AssetFrontMatter: reads only a UTF-8 frontmatter prefix, bounded to 256 lines and 65,536 characters, and ignores the body.
function Read-AssetFrontMatter {
    param([Parameter(Mandatory = $true)][string]$Path)

    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    $reader = [System.IO.StreamReader]::new($Path, $encoding, $true, 4096)
    try {
        $firstLine = $reader.ReadLine()
        if ($null -eq $firstLine) {
            Throw-FrontMatterError -Code "empty-file" -Message "Asset file is empty."
        }
        if ($firstLine -cne "---") {
            Throw-FrontMatterError -Code "frontmatter-missing" -Message "Asset file must start with a YAML frontmatter delimiter."
        }
        $lines = New-Object 'System.Collections.Generic.List[string]'
        $characterCount = 0
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ($line -ceq "---") {
                return ConvertFrom-AssetFrontMatter -Lines @($lines.ToArray())
            }
            $lines.Add($line)
            $characterCount += $line.Length
            if ($lines.Count -gt 256 -or $characterCount -gt 65536) {
                Throw-FrontMatterError -Code "frontmatter-too-large" -Message "Asset frontmatter exceeds the supported size limit."
            }
        }
        Throw-FrontMatterError -Code "malformed-frontmatter" -Message "Asset frontmatter closing delimiter is missing."
    }
    catch [System.Text.DecoderFallbackException] {
        Throw-FrontMatterError -Code "invalid-utf8" -Message "Asset frontmatter is not valid UTF-8."
    }
    finally {
        $reader.Dispose()
    }
}

# Get-PatternFindingCode: converts a schema pattern failure into the stable finding code for the affected field.
function Get-PatternFindingCode {
    param([string]$FieldPath)

    if ($FieldPath -ceq "id" -or $FieldPath -like "*.id") { return "invalid-id" }
    if ($FieldPath -ceq "revision" -or $FieldPath -like "*.revision") { return "invalid-revision" }
    if ($FieldPath -ceq "updated" -or $FieldPath -like "*.updated") { return "invalid-updated" }
    return "invalid-field-format"
}

# Test-ValueAgainstSchema: validates one parsed value against the supported schema subset and appends all discovered findings.
function Test-ValueAgainstSchema {
    param(
        [object]$Value,
        [Parameter(Mandatory = $true)][object]$Schema,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FieldPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $schemaType = [string]$Schema.type
    $typeValid = switch ($schemaType) {
        "object" { Test-IsMapping -Value $Value }
        "array" { Test-IsList -Value $Value }
        "string" { $Value -is [string] }
        default { $true }
    }
    if (-not $typeValid) {
        Add-AssetFinding -Findings $Findings -Code "invalid-field-type" -Path $RelativePath -Field $FieldPath -Message "Field '$FieldPath' must be of type '$schemaType'."
        return
    }

    if ($schemaType -ceq "object") {
        $properties = $Schema.properties
        $allowedNames = @($properties.PSObject.Properties.Name)
        $valueNames = @(Get-ObjectPropertyNames -Object $Value)
        foreach ($name in @($valueNames | Sort-Object)) {
            if ($allowedNames -cnotcontains $name) {
                $childPath = if ([string]::IsNullOrWhiteSpace($FieldPath)) { $name } else { "$FieldPath.$name" }
                Add-AssetFinding -Findings $Findings -Code "unknown-field" -Path $RelativePath -Field $childPath -Message "Unknown field '$childPath' is not allowed."
            }
        }
        if (Test-ObjectHasProperty -Object $Schema -Name "required") {
            foreach ($name in @($Schema.required)) {
                if (-not (Test-ObjectHasProperty -Object $Value -Name ([string]$name))) {
                    $childPath = if ([string]::IsNullOrWhiteSpace($FieldPath)) { [string]$name } else { "$FieldPath.$name" }
                    Add-AssetFinding -Findings $Findings -Code "required-field-missing" -Path $RelativePath -Field $childPath -Message "Required field '$childPath' is missing."
                }
            }
        }
        foreach ($name in @($valueNames | Sort-Object)) {
            if ($allowedNames -ccontains $name) {
                $childSchema = $properties.PSObject.Properties[$name].Value
                $childValue = $null
                if ($Value -is [System.Collections.IDictionary]) {
                    $childValue = $Value[$name]
                }
                else {
                    $childValue = $Value.PSObject.Properties[$name].Value
                }
                $childPath = if ([string]::IsNullOrWhiteSpace($FieldPath)) { $name } else { "$FieldPath.$name" }
                Test-ValueAgainstSchema -Value $childValue -Schema $childSchema -RelativePath $RelativePath -FieldPath $childPath -Findings $Findings
            }
        }
        return
    }

    if ($schemaType -ceq "array") {
        $minimum = if (Test-ObjectHasProperty -Object $Schema -Name "minItems") { $Schema.minItems } else { $null }
        if ($null -ne $minimum -and $Value.Count -lt [int]$minimum) {
            Add-AssetFinding -Findings $Findings -Code "invalid-field-value" -Path $RelativePath -Field $FieldPath -Message "Field '$FieldPath' must contain at least $minimum item(s)."
        }
        if ((Test-ObjectHasProperty -Object $Schema -Name "uniqueItems") -and [bool]$Schema.uniqueItems) {
            $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach ($item in @($Value)) {
                if (-not $seen.Add(([string]$item))) {
                    Add-AssetFinding -Findings $Findings -Code "invalid-field-value" -Path $RelativePath -Field $FieldPath -Message "Field '$FieldPath' must not contain duplicate values."
                    break
                }
            }
        }
        $itemSchema = if (Test-ObjectHasProperty -Object $Schema -Name "items") { $Schema.items } else { $null }
        if ($null -ne $itemSchema) {
            for ($index = 0; $index -lt $Value.Count; $index++) {
                Test-ValueAgainstSchema -Value $Value[$index] -Schema $itemSchema -RelativePath $RelativePath -FieldPath ("{0}[{1}]" -f $FieldPath, $index) -Findings $Findings
            }
        }
        return
    }

    if ($schemaType -ceq "string") {
        $hasConstant = Test-ObjectHasProperty -Object $Schema -Name "const"
        $constant = if ($hasConstant) { $Schema.const } else { $null }
        if ($hasConstant -and [string]$Value -cne [string]$constant) {
            $code = if ($FieldPath -ceq "schema") { "invalid-schema-version" } else { "invalid-field-value" }
            Add-AssetFinding -Findings $Findings -Code $code -Path $RelativePath -Field $FieldPath -Message "Field '$FieldPath' has an unsupported value."
            return
        }
        if (Test-ObjectHasProperty -Object $Schema -Name "enum") {
            $enum = @($Schema.enum)
            if ($enum -cnotcontains [string]$Value) {
                Add-AssetFinding -Findings $Findings -Code "invalid-enum" -Path $RelativePath -Field $FieldPath -Message "Field '$FieldPath' is not one of the allowed values."
            }
        }
        $minimumLength = if (Test-ObjectHasProperty -Object $Schema -Name "minLength") { $Schema.minLength } else { $null }
        if ($null -ne $minimumLength -and ([string]$Value).Length -lt [int]$minimumLength) {
            Add-AssetFinding -Findings $Findings -Code "invalid-field-value" -Path $RelativePath -Field $FieldPath -Message "Field '$FieldPath' must not be empty."
        }
        $pattern = if (Test-ObjectHasProperty -Object $Schema -Name "pattern") { [string]$Schema.pattern } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($pattern) -and -not [regex]::IsMatch([string]$Value, $pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
            $code = Get-PatternFindingCode -FieldPath $FieldPath
            Add-AssetFinding -Findings $Findings -Code $code -Path $RelativePath -Field $FieldPath -Message "Field '$FieldPath' does not match the required format."
        }
        $format = if (Test-ObjectHasProperty -Object $Schema -Name "format") { [string]$Schema.format } else { "" }
        if ($format -ceq "project-relative-path" -and -not (Test-SafeProjectRelativePath -Path ([string]$Value))) {
            Add-AssetFinding -Findings $Findings -Code "unsafe-path" -Path $RelativePath -Field $FieldPath -Message "Field '$FieldPath' must be a safe project-relative path."
        }
    }
}

# Get-CanonicalAssetPaths: returns only immediate Markdown assets under the four canonical project roots in stable order.
function Get-CanonicalAssetPaths {
    param([Parameter(Mandatory = $true)][string]$Root)

    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativeDirectory in @('.agents/work', '.agents/context', '.agents/procedures')) {
        $directory = Join-Path $Root $relativeDirectory
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            continue
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -Filter '*.md' -Force)) {
            $paths.Add((ConvertTo-NormalizedRelativePath -Root $Root -Path $file.FullName))
        }
    }

    $specRoot = Join-Path $Root 'docs/specs'
    if (Test-Path -LiteralPath $specRoot -PathType Container) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $specRoot -Directory -Force)) {
            $candidate = Join-Path $directory.FullName 'spec.md'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $paths.Add((ConvertTo-NormalizedRelativePath -Root $Root -Path $candidate))
            }
        }
    }
    return @($paths.ToArray() | Sort-Object -Unique)
}

$findings = New-Object 'System.Collections.Generic.List[object]'
$assets = New-Object 'System.Collections.Generic.List[object]'
$schemasByType = [ordered]@{}
$typeByUri = [ordered]@{}

$projectRootFull = ""
try {
    $projectRootFull = Get-NormalizedFullPath -Path $ProjectRoot
    if (-not (Test-Path -LiteralPath $projectRootFull -PathType Container)) {
        throw "Project root does not exist or is not a directory."
    }
}
catch {
    Add-AssetFinding -Findings $findings -Code "project-root-invalid" -Path "" -Message "Project root does not exist or is not a directory."
}

if ([string]::IsNullOrWhiteSpace($SchemaRoot)) {
    $SchemaRoot = Join-Path $repoRoot 'schemas/project-workspace'
}
$schemaRootFull = Get-NormalizedFullPath -Path $SchemaRoot
foreach ($type in @($schemaFiles.Keys)) {
    $schemaPath = Join-Path $schemaRootFull $schemaFiles[$type]
    try {
        $schemaText = [System.IO.File]::ReadAllText($schemaPath, [System.Text.UTF8Encoding]::new($false, $true))
        $schema = $schemaText | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        $schemasByType[$type] = $schema
        $typeByUri[$schemaUris[$type]] = $type
    }
    catch {
        Add-AssetFinding -Findings $findings -Code "schema-load-failed" -Path $schemaFiles[$type] -Message ("Unable to load schema for asset type '$type'.")
    }
}

$selectedPaths = New-Object 'System.Collections.Generic.List[string]'
if (-not [string]::IsNullOrWhiteSpace($projectRootFull)) {
    if (@($AssetPath).Count -gt 0) {
        foreach ($requestedPath in @($AssetPath)) {
            if (-not (Test-SafeProjectRelativePath -Path $requestedPath)) {
                Add-AssetFinding -Findings $findings -Code "unsafe-path" -Path ([string]$requestedPath) -Message "Asset path must be a safe project-relative canonical path."
                continue
            }
            $normalizedPath = $requestedPath.Replace('\', '/')
            if ($null -eq (Get-CanonicalAssetDescriptor -RelativePath $normalizedPath)) {
                Add-AssetFinding -Findings $findings -Code "unsafe-path" -Path $normalizedPath -Message "Asset path is outside the canonical project asset roots."
                continue
            }
            $selectedPaths.Add($normalizedPath)
        }
    }
    else {
        foreach ($path in @(Get-CanonicalAssetPaths -Root $projectRootFull)) {
            $selectedPaths.Add($path)
        }
    }
}

$physicalProjectRoot = ""
if (-not [string]::IsNullOrWhiteSpace($projectRootFull)) {
    try {
        $visitedRootLinks = New-Object 'System.Collections.Generic.List[string]'
        $physicalProjectRoot = Resolve-ExistingPhysicalPath -Path $projectRootFull -VisitedLinks $visitedRootLinks
    }
    catch {
        Add-AssetFinding -Findings $findings -Code "project-root-invalid" -Path "" -Message "Project root physical path cannot be resolved safely."
    }
}

$identities = @{}
foreach ($relativePath in @($selectedPaths.ToArray() | Sort-Object)) {
    $descriptor = Get-CanonicalAssetDescriptor -RelativePath $relativePath
    $fullPath = Get-NormalizedFullPath -Path (Join-Path $projectRootFull $relativePath)
    if (-not (Test-PathIsEqualOrChild -Path $fullPath -Root $projectRootFull)) {
        Add-AssetFinding -Findings $findings -Code "unsafe-path" -Path $relativePath -Message "Asset path escapes the project root."
        continue
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Add-AssetFinding -Findings $findings -Code "asset-path-missing" -Path $relativePath -Message "Asset path does not exist."
        continue
    }
    try {
        $visitedLinks = New-Object 'System.Collections.Generic.List[string]'
        $physicalPath = Resolve-ExistingPhysicalPath -Path $fullPath -VisitedLinks $visitedLinks
        if ([string]::IsNullOrWhiteSpace($physicalProjectRoot) -or -not (Test-PathIsEqualOrChild -Path $physicalPath -Root $physicalProjectRoot)) {
            throw "Asset physical path escapes the project root."
        }
    }
    catch {
        Add-AssetFinding -Findings $findings -Code "unsafe-path" -Path $relativePath -Message "Asset physical path cannot be resolved inside the project root."
        continue
    }

    $findingStart = $findings.Count
    $metadata = $null
    try {
        $metadata = Read-AssetFrontMatter -Path $fullPath
    }
    catch {
        $code = [string]$_.Exception.Data["asset_code"]
        if ([string]::IsNullOrWhiteSpace($code)) { $code = "malformed-frontmatter" }
        $field = [string]$_.Exception.Data["asset_field"]
        Add-AssetFinding -Findings $findings -Code $code -Path $relativePath -Field $field -Message $_.Exception.Message
    }

    $assetType = [string]$descriptor.type
    $assetId = ""
    $schemaUri = ""
    if ($null -ne $metadata) {
        $assetId = [string](Get-ObjectPropertyValue -Object $metadata -Name "id")
        $schemaUri = [string](Get-ObjectPropertyValue -Object $metadata -Name "schema")
        $schemaType = [string](Get-ObjectPropertyValue -Object $typeByUri -Name $schemaUri)
        if ([string]::IsNullOrWhiteSpace($schemaType)) {
            Add-AssetFinding -Findings $findings -Code "invalid-schema-version" -Path $relativePath -Field "schema" -Message "Asset schema URI or version is not supported."
        }
        else {
            if ($schemaType -cne $assetType) {
                Add-AssetFinding -Findings $findings -Code "asset-type-mismatch" -Path $relativePath -Field "schema" -Message "Asset schema type does not match its canonical path."
            }
            Test-ValueAgainstSchema -Value $metadata -Schema $schemasByType[$schemaType] -RelativePath $relativePath -FieldPath "" -Findings $findings
        }
        $gitMetadata = if ($metadata -is [System.Collections.IDictionary]) {
            $metadata["git"]
        }
        else {
            $metadata.PSObject.Properties["git"].Value
        }
        if ((Test-IsMapping -Value $gitMetadata) -and (Test-ObjectHasProperty -Object $gitMetadata -Name "worktree")) {
            $worktree = if ($gitMetadata -is [System.Collections.IDictionary]) {
                $gitMetadata["worktree"]
            }
            else {
                $gitMetadata.PSObject.Properties["worktree"].Value
            }
            if ($worktree -is [string] -and
                (Test-SafeProjectRelativePath -Path $worktree) -and
                -not (Test-ProjectRelativePathBoundary -Root $projectRootFull -PhysicalRoot $physicalProjectRoot -RelativePath $worktree)) {
                Add-AssetFinding -Findings $findings -Code "unsafe-path" -Path $relativePath -Field "git.worktree" -Message "Field 'git.worktree' resolves outside the project root."
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($assetId) -and $assetId -cne [string]$descriptor.path_id) {
            Add-AssetFinding -Findings $findings -Code "id-path-mismatch" -Path $relativePath -Field "id" -Message "Asset id must match its canonical path identity."
        }
        if (-not [string]::IsNullOrWhiteSpace($assetId)) {
            $identity = "{0}:{1}" -f $assetType, $assetId
            if ($identities.ContainsKey($identity)) {
                Add-AssetFinding -Findings $findings -Code "identity-conflict" -Path $relativePath -Field "id" -Message ("Asset identity conflicts with '{0}'." -f $identities[$identity])
            }
            else {
                $identities[$identity] = $relativePath
            }
        }
    }

    $assets.Add([ordered]@{
        type = $assetType
        id = $assetId
        path = $relativePath
        schema = $schemaUri
        valid = ($findings.Count -eq $findingStart)
        finding_codes = @()
    })
}

$sortedFindings = @($findings.ToArray() | Sort-Object path, field, code, message)
foreach ($asset in @($assets.ToArray())) {
    $codes = @($sortedFindings | Where-Object { $_.path -ceq [string]$asset.path } | ForEach-Object { [string]$_.code } | Sort-Object -Unique)
    $asset.valid = ($codes.Count -eq 0)
    $asset.finding_codes = @($codes)
}
$sortedAssets = @($assets.ToArray() | Sort-Object path, type, id)
$result = [ordered]@{
    schema_version = 1
    parser = "project-workspace-read-only-assets"
    status = $(if ($sortedFindings.Count -eq 0) { "PASS" } else { "FAIL" })
    asset_count = $sortedAssets.Count
    finding_count = $sortedFindings.Count
    assets = $sortedAssets
    findings = $sortedFindings
}

if ($Json.IsPresent) {
    $result | ConvertTo-Json -Depth 20
}
else {
    Write-Output ("Project workspace asset parser: {0} assets={1} findings={2}" -f $result.status, $result.asset_count, $result.finding_count)
    foreach ($asset in $result.assets) {
        Write-Output ("[{0}] {1} {2} {3}" -f $(if ($asset.valid) { "PASS" } else { "FAIL" }), $asset.type, $asset.id, $asset.path)
    }
    foreach ($finding in $result.findings) {
        Write-Output ("[FAIL] {0} path={1} field={2} | {3}" -f $finding.code, $finding.path, $finding.field, $finding.message)
    }
}

if ($result.status -ne "PASS") {
    exit 1
}
