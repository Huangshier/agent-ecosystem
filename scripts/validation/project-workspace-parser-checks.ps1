#requires -Version 7.6

[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$defaultRepositoryRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    [System.IO.Path]::GetFullPath($defaultRepositoryRoot)
}
else {
    [System.IO.Path]::GetFullPath($RepositoryRoot)
}
. (Join-Path $scriptDir "powershell-runtime-requirement.ps1")
Assert-AgentEcosystemPowerShellRuntime

if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-workspace-parser-{0}" -f ([Guid]::NewGuid().ToString("N")))
}
$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null

$parserPath = Join-Path $repoRoot "skills/project-workspace/scripts/read-project-assets.ps1"
$schemaRoot = Join-Path $repoRoot "schemas/project-workspace"
$templateRoot = Join-Path $repoRoot "templates/project/assets"
$fixtureRoot = Join-Path $scriptDir "project-workspace-fixtures"
$fixtureProject = Join-Path $fixtureRoot "new-project"
$caseManifestPath = Join-Path $fixtureRoot "cases.json"
$hardeningManifestPath = Join-Path $fixtureRoot "hardening-cases.json"
$pwshPath = Resolve-AgentEcosystemPwshExecutable

if ([string]::IsNullOrWhiteSpace($pwshPath)) {
    throw "pwsh is required for project workspace parser fixtures."
}

$results = New-Object 'System.Collections.Generic.List[object]'

# Add-CheckResult: records one named fixture outcome in the verifier summary and returns no value.
function Add-CheckResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet("PASS", "FAIL")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $results.Add([ordered]@{
        name = $Name
        status = $Status
        detail = $Detail
    })
}

# Get-ProjectFingerprint: returns a stable SHA-256 digest of every file path and byte hash below a fixture root.
function Get-ProjectFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)) {
        $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $lines.Add("$relative|$hash")
    }
    $payload = [Text.Encoding]::UTF8.GetBytes(($lines.ToArray() -join "`n"))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($payload)).ToLowerInvariant()
}

# New-FixtureProject: copies the self-contained new-project fixture to a unique scratch child and returns that path.
function New-FixtureProject {
    param([Parameter(Mandatory = $true)][string]$Name)

    $destination = Join-Path $scratchRootFull $Name
    if (Test-Path -LiteralPath $destination) {
        throw "Fixture destination already exists: $destination"
    }
    Copy-Item -LiteralPath $fixtureProject -Destination $destination -Recurse
    return $destination
}

# Invoke-ParserProcess: runs the parser in an isolated pwsh process and returns its exit code, raw JSON text, and parsed payload.
function Invoke-ParserProcess {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$ExplicitAssetPath = "",
        [string]$ParserScriptPath = ""
    )

    $scriptPath = if ([string]::IsNullOrWhiteSpace($ParserScriptPath)) { $parserPath } else { $ParserScriptPath }
    $arguments = @(
        "-NoProfile", "-NonInteractive", "-File", $scriptPath,
        "-ProjectRoot", $ProjectRoot,
        "-Json"
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitAssetPath)) {
        $arguments += @("-AssetPath", $ExplicitAssetPath)
    }
    $output = @(& $pwshPath @arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = [int]$LASTEXITCODE
    $text = $output -join "`n"
    $payload = $null
    try {
        $payload = $text | ConvertFrom-Json -Depth 30 -ErrorAction Stop
    }
    catch {
        throw "Parser did not return valid JSON. Exit=$exitCode Output=$text"
    }
    return [ordered]@{
        exit_code = $exitCode
        text = $text
        payload = $payload
    }
}

# Read-AssetText: reads one fixture file as strict UTF-8 and returns its full text.
function Read-AssetText {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

# Write-AssetText: writes a mutated scratch fixture as UTF-8 without BOM; checked-in fixtures are never passed here.
function Write-AssetText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

# Write-EncodingFixture: writes the copied asset with an explicit byte encoding so parser checks exercise real byte inputs.
function Write-EncodingFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$EncodingName
    )

    $text = Read-AssetText -Path $Path
    if ($EncodingName -ceq "malformed-utf8") {
        $encoding = [System.Text.UTF8Encoding]::new($false, $true)
        $prefixText = $text.Substring(0, $text.IndexOf("title: ", [StringComparison]::Ordinal) + 7)
        $suffixText = $text.Substring($prefixText.Length)
        $prefixBytes = $encoding.GetBytes($prefixText)
        $suffixBytes = $encoding.GetBytes($suffixText)
        $invalidBytes = [byte[]](0xC3, 0x28)
        [System.IO.File]::WriteAllBytes($Path, [byte[]]($prefixBytes + $invalidBytes + $suffixBytes))
        return
    }

    $encoding = switch ($EncodingName) {
        "utf8" { [System.Text.UTF8Encoding]::new($false, $true); break }
        "utf8-bom" { [System.Text.UTF8Encoding]::new($true, $true); break }
        "utf16-le-bom" { [System.Text.UnicodeEncoding]::new($false, $true, $true); break }
        "utf16-be-bom" { [System.Text.UnicodeEncoding]::new($true, $true, $true); break }
        "utf32-bom" { [System.Text.UTF32Encoding]::new($false, $true, $true); break }
        default { throw "Unknown encoding fixture: $EncodingName" }
    }
    [System.IO.File]::WriteAllBytes($Path, [byte[]]($encoding.GetPreamble() + $encoding.GetBytes($text)))
}

# Assert-EncodingFixtureBytes: proves encoding cases use the intended raw byte prefix or malformed sequence.
function Assert-EncodingFixtureBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$EncodingName
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $matchesPrefix = {
        param([byte[]]$Expected)
        if ($bytes.Length -lt $Expected.Length) { return $false }
        for ($index = 0; $index -lt $Expected.Length; $index++) {
            if ($bytes[$index] -ne $Expected[$index]) { return $false }
        }
        return $true
    }
    switch ($EncodingName) {
        "utf8" {
            if (& $matchesPrefix ([byte[]](0xEF, 0xBB, 0xBF))) { throw "UTF-8 no-BOM fixture unexpectedly contains a BOM." }
        }
        "utf8-bom" {
            if (-not (& $matchesPrefix ([byte[]](0xEF, 0xBB, 0xBF)))) { throw "UTF-8 BOM fixture does not contain the expected BOM." }
        }
        "utf16-le-bom" {
            if (-not (& $matchesPrefix ([byte[]](0xFF, 0xFE)))) { throw "UTF-16 LE fixture does not contain the expected BOM." }
        }
        "utf16-be-bom" {
            if (-not (& $matchesPrefix ([byte[]](0xFE, 0xFF)))) { throw "UTF-16 BE fixture does not contain the expected BOM." }
        }
        "utf32-bom" {
            if (-not (& $matchesPrefix ([byte[]](0xFF, 0xFE, 0x00, 0x00)))) { throw "UTF-32 fixture does not contain the expected BOM." }
        }
        "malformed-utf8" {
            $found = $false
            for ($index = 0; $index -lt ($bytes.Length - 1); $index++) {
                if ($bytes[$index] -eq 0xC3 -and $bytes[$index + 1] -eq 0x28) {
                    $found = $true
                    break
                }
            }
            if (-not $found) { throw "Malformed UTF-8 fixture does not contain the intended invalid byte sequence." }
        }
        default { throw "Unknown encoding fixture assertion: $EncodingName" }
    }
}

# Remove-FrontMatterField: removes one top-level field and its indented children from a scratch fixture.
function Remove-FrontMatterField {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Field
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.UTF8Encoding]::new($false, $true))) {
        $lines.Add($line)
    }
    $start = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -cmatch ("^{0}:" -f [regex]::Escape($Field))) {
            $start = $index
            break
        }
        if ($lines[$index] -ceq "---") { break }
    }
    if ($start -lt 0) { throw "Fixture field '$Field' was not found in $Path" }
    $count = 1
    while ($start + $count -lt $lines.Count -and $lines[$start + $count] -cmatch '^  ') {
        $count++
    }
    $lines.RemoveRange($start, $count)
    [System.IO.File]::WriteAllLines($Path, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
}

# Set-FrontMatterField: replaces the first scalar field line in a scratch fixture with a deterministic test value.
function Set-FrontMatterField {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Field,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    $text = Read-AssetText -Path $Path
    $pattern = "(?m)^{0}:[^\r\n]*$" -f [regex]::Escape($Field)
    if (-not [regex]::IsMatch($text, $pattern)) {
        throw "Fixture field '$Field' was not found in $Path"
    }
    $fieldPattern = [regex]::new($pattern)
    Write-AssetText -Path $Path -Text ($fieldPattern.Replace($text, ("{0}: {1}" -f $Field, $Value), 1))
}

# Add-UnknownFrontMatterField: inserts one unsupported top-level key before the scratch fixture's closing delimiter.
function Add-UnknownFrontMatterField {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = Read-AssetText -Path $Path
    $closing = $text.IndexOf("`n---", 4, [StringComparison]::Ordinal)
    if ($closing -lt 0) { throw "Fixture closing frontmatter delimiter was not found in $Path" }
    $updated = $text.Insert($closing, "`nunexpected: rejected")
    Write-AssetText -Path $Path -Text $updated
}

# Add-GitWorktreeFrontMatter: inserts a valid nested git mapping with the supplied worktree value into a scratch Work asset.
function Add-GitWorktreeFrontMatter {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Worktree
    )

    $text = Read-AssetText -Path $Path
    $closing = $text.IndexOf("`n---", 4, [StringComparison]::Ordinal)
    if ($closing -lt 0) { throw "Fixture closing frontmatter delimiter was not found in $Path" }
    $updated = $text.Insert($closing, "`ngit:`n  branch: fixture`n  worktree: $Worktree")
    Write-AssetText -Path $Path -Text $updated
}

# Apply-FixtureMutation: applies the manifest-selected negative or identity mutation only inside the supplied scratch project.
function Apply-FixtureMutation {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][object]$Case
    )

    $assetPath = Join-Path $ProjectRoot ([string]$Case.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $mutation = [string]$Case.mutation
    if ($mutation -ceq "none" -or $mutation -ceq "explicit-input-path") { return }
    if ($mutation.StartsWith("remove:")) {
        Remove-FrontMatterField -Path $assetPath -Field $mutation.Substring(7)
        return
    }
    if ($mutation.StartsWith("set:")) {
        $assignment = $mutation.Substring(4)
        $separator = $assignment.IndexOf('=')
        if ($separator -lt 1) { throw "Invalid set mutation: $mutation" }
        Set-FrontMatterField -Path $assetPath -Field $assignment.Substring(0, $separator) -Value $assignment.Substring($separator + 1)
        return
    }
    if ($mutation.StartsWith("encoding:")) {
        Write-EncodingFixture -Path $assetPath -EncodingName $mutation.Substring(9)
        return
    }
    if ($mutation -ceq "add:unexpected") {
        Add-UnknownFrontMatterField -Path $assetPath
        return
    }
    if ($mutation -ceq "add:unsafe-git-worktree") {
        Add-GitWorktreeFrontMatter -Path $assetPath -Worktree "../outside"
        return
    }
    if ($mutation -ceq "add:reparse-git-worktree") {
        $outside = Join-Path $scratchRootFull ("{0}-outside" -f [string]$Case.name)
        New-Item -ItemType Directory -Force -Path $outside | Out-Null
        $link = Join-Path $ProjectRoot "linked-worktree"
        if ($IsWindows) {
            New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
        }
        else {
            New-Item -ItemType SymbolicLink -Path $link -Target $outside | Out-Null
        }
        Add-GitWorktreeFrontMatter -Path $assetPath -Worktree "linked-worktree"
        return
    }
    if ($mutation -ceq "malformed-frontmatter") {
        $text = Read-AssetText -Path $assetPath
        $titlePattern = [regex]::new('(?m)^title:.*$')
        Write-AssetText -Path $assetPath -Text ($titlePattern.Replace($text, 'title fixture is malformed', 1))
        return
    }
    if ($mutation -ceq "replace:empty") {
        Write-AssetText -Path $assetPath -Text ""
        return
    }
    if ($mutation -ceq "copy-with-same-id") {
        $duplicate = Join-Path (Split-Path -Parent $assetPath) "duplicate-work.md"
        Copy-Item -LiteralPath $assetPath -Destination $duplicate
        return
    }
    if ($mutation -ceq "path-id-differs-from-frontmatter-id") {
        $destination = Join-Path $ProjectRoot "docs/specs/conflicting-spec"
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
        Copy-Item -LiteralPath $assetPath -Destination (Join-Path $destination "spec.md")
        return
    }
    throw "Unknown fixture mutation: $mutation"
}

# Test-ExpectedCodes: asserts that every manifest-required finding code is present in the parser payload.
function Test-ExpectedCodes {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [string[]]$ExpectedCodes = @()
    )

    $actualCodes = @($Payload.findings | ForEach-Object { [string]$_.code } | Sort-Object -Unique)
    foreach ($code in @($ExpectedCodes)) {
        if ($actualCodes -cnotcontains $code) {
            throw "Expected finding code '$code' was not returned. Actual: $($actualCodes -join ', ')"
        }
    }
}

# Get-ParserFindingSummary: returns a compact diagnostic summary for failed parser fixture assertions.
function Get-ParserFindingSummary {
    param([Parameter(Mandatory = $true)][object]$Payload)

    $summaries = @($Payload.findings | ForEach-Object {
        $location = @([string]$_.path, [string]$_.field) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        "{0}{1}" -f [string]$_.code, $(if ($location.Count -gt 0) { "[$($location -join ':')]" } else { "" })
    })
    if ($summaries.Count -eq 0) { return "none" }
    return ($summaries -join "; ")
}

# New-ParserRepositoryCopy: creates an isolated parser checkout so canonical-schema failure modes can be tested without changing this repository.
function New-ParserRepositoryCopy {
    param([Parameter(Mandatory = $true)][string]$Name)

    $copyRoot = Join-Path $scratchRootFull $Name
    $copyParserDir = Join-Path $copyRoot "skills/project-workspace/scripts"
    $copySchemaDir = Join-Path $copyRoot "schemas/project-workspace"
    $copyValidationDir = Join-Path $copyRoot "scripts/validation"
    $copyLibDir = Join-Path $copyRoot "scripts/lib"
    foreach ($directory in @($copyParserDir, $copySchemaDir, $copyValidationDir, $copyLibDir)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    Copy-Item -LiteralPath $parserPath -Destination (Join-Path $copyParserDir (Split-Path -Leaf $parserPath))
    foreach ($schemaFile in @(Get-ChildItem -LiteralPath $schemaRoot -File -Filter "*.json")) {
        Copy-Item -LiteralPath $schemaFile.FullName -Destination (Join-Path $copySchemaDir $schemaFile.Name)
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/validation/powershell-runtime-requirement.ps1") -Destination (Join-Path $copyValidationDir "powershell-runtime-requirement.ps1")
    Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/lib/path-guard.ps1") -Destination (Join-Path $copyLibDir "path-guard.ps1")
    return $copyRoot
}

foreach ($requiredPath in @($parserPath, $schemaRoot, $templateRoot, $fixtureProject, $caseManifestPath, $hardeningManifestPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required project workspace fixture dependency is missing: $requiredPath"
    }
}

$cases = @(Get-Content -LiteralPath $caseManifestPath -Raw | ConvertFrom-Json -Depth 20)
$hardeningCases = @(Get-Content -LiteralPath $hardeningManifestPath -Raw | ConvertFrom-Json -Depth 20)
$allReadOnly = $true
$commandInert = $true

foreach ($case in $cases) {
    $caseName = [string]$case.name
    try {
        $project = New-FixtureProject -Name ("case-{0}" -f $caseName)
        Apply-FixtureMutation -ProjectRoot $project -Case $case
        $before = Get-ProjectFingerprint -Root $project
        $explicitPath = if ([string]$case.mutation -ceq "explicit-input-path") { [string]$case.input_path } elseif ([string]$case.mutation -ceq "none") { [string]$case.path } else { "" }
        $invocation = Invoke-ParserProcess -ProjectRoot $project -ExplicitAssetPath $explicitPath
        $after = Get-ProjectFingerprint -Root $project
        if ($before -cne $after) {
            $allReadOnly = $false
            throw "Parser changed fixture input files."
        }
        if ([string]$case.expected -ceq "valid") {
            if ($invocation.exit_code -ne 0 -or [string]$invocation.payload.status -cne "PASS" -or [int]$invocation.payload.finding_count -ne 0) {
                $findingSummary = Get-ParserFindingSummary -Payload $invocation.payload
                throw "Expected a valid parser result. Exit=$($invocation.exit_code) Status=$($invocation.payload.status) Findings=$findingSummary"
            }
        }
        else {
            if ($invocation.exit_code -eq 0 -or [string]$invocation.payload.status -cne "FAIL" -or [int]$invocation.payload.finding_count -lt 1) {
                throw "Expected an invalid parser result. Exit=$($invocation.exit_code) Status=$($invocation.payload.status)"
            }
            Test-ExpectedCodes -Payload $invocation.payload -ExpectedCodes @($case.expected_codes)
        }
        if ($caseName -ceq "command-inertness") {
            if ($invocation.text -match 'fixture-command-must-not-run' -or (Test-Path -LiteralPath (Join-Path $project 'fixture-command-must-not-run'))) {
                $commandInert = $false
                throw "Procedure body command marker was evaluated or emitted."
            }
        }
        Add-CheckResult -Name $caseName -Status "PASS" -Detail ("Expected {0} result and stable input fingerprint." -f [string]$case.expected)
    }
    catch {
        if ($caseName -ceq "command-inertness") { $commandInert = $false }
        Add-CheckResult -Name $caseName -Status "FAIL" -Detail $_.Exception.Message
    }
}

$templateTargets = [ordered]@{
    "work-item" = ".agents/work/example-work-item.md"
    "context" = ".agents/context/example-context.md"
    "procedure" = ".agents/procedures/example-procedure.md"
    "spec" = "docs/specs/example-spec/spec.md"
}
$templateCount = 0
foreach ($templateName in @($templateTargets.Keys)) {
    try {
        $project = Join-Path $scratchRootFull ("template-{0}" -f $templateName)
        New-Item -ItemType Directory -Force -Path $project | Out-Null
        $relativeTarget = [string]$templateTargets[$templateName]
        $target = Join-Path $project $relativeTarget.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $templateRoot "$templateName.md") -Destination $target
        $before = Get-ProjectFingerprint -Root $project
        $invocation = Invoke-ParserProcess -ProjectRoot $project -ExplicitAssetPath $relativeTarget
        $after = Get-ProjectFingerprint -Root $project
        if ($before -cne $after) { $allReadOnly = $false; throw "Parser changed the canonical template copy." }
        if ($invocation.exit_code -ne 0 -or [string]$invocation.payload.status -cne "PASS" -or [int]$invocation.payload.asset_count -ne 1) {
            $findingSummary = Get-ParserFindingSummary -Payload $invocation.payload
            throw "Canonical template did not pass its parser contract. Exit=$($invocation.exit_code) Status=$($invocation.payload.status) Findings=$findingSummary"
        }
        $templateCount++
        Add-CheckResult -Name ("template-{0}" -f $templateName) -Status "PASS" -Detail "Canonical template passed from its canonical project path."
    }
    catch {
        Add-CheckResult -Name ("template-{0}" -f $templateName) -Status "FAIL" -Detail $_.Exception.Message
    }
}

$baselineScenarioCount = $results.Count
$baselinePassCount = @($results | Where-Object status -eq "PASS").Count
$baselineFailCount = @($results | Where-Object status -eq "FAIL").Count
$baselineContract = ($baselineScenarioCount -eq 34 -and $baselinePassCount -eq 34 -and $baselineFailCount -eq 0)

foreach ($case in $hardeningCases) {
    $caseName = [string]$case.name
    try {
        $project = New-FixtureProject -Name ("hardening-case-{0}" -f $caseName)
        Apply-FixtureMutation -ProjectRoot $project -Case $case
        if ([string]$case.mutation -like "encoding:*") {
            Assert-EncodingFixtureBytes -Path (Join-Path $project ([string]$case.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)) -EncodingName ([string]$case.mutation).Substring(9)
        }
        $before = Get-ProjectFingerprint -Root $project
        $invocation = Invoke-ParserProcess -ProjectRoot $project -ExplicitAssetPath ([string]$case.path)
        $after = Get-ProjectFingerprint -Root $project
        if ($before -cne $after) {
            $allReadOnly = $false
            throw "Parser changed hardening fixture input files."
        }
        if ([string]$case.expected -ceq "valid") {
            if ($invocation.exit_code -ne 0 -or [string]$invocation.payload.status -cne "PASS" -or [int]$invocation.payload.finding_count -ne 0) {
                $findingSummary = Get-ParserFindingSummary -Payload $invocation.payload
                throw "Expected a valid hardening parser result. Exit=$($invocation.exit_code) Status=$($invocation.payload.status) Findings=$findingSummary"
            }
        }
        else {
            if ($invocation.exit_code -eq 0 -or [string]$invocation.payload.status -cne "FAIL" -or [int]$invocation.payload.finding_count -lt 1) {
                throw "Expected an invalid hardening parser result. Exit=$($invocation.exit_code) Status=$($invocation.payload.status)"
            }
            Test-ExpectedCodes -Payload $invocation.payload -ExpectedCodes @($case.expected_codes)
        }
        Add-CheckResult -Name $caseName -Status "PASS" -Detail ("Expected {0} hardening result with stable input fingerprint." -f [string]$case.expected)
    }
    catch {
        Add-CheckResult -Name $caseName -Status "FAIL" -Detail $_.Exception.Message
    }
}

try {
    $project = New-FixtureProject -Name "context-readme-non-authority"
    $readmePath = Join-Path $project ".agents/context/README.md"
    Write-AssetText -Path $readmePath -Text "# Legacy Context Index`n`nPreserved non-authority documentation.`n"
    $before = Get-ProjectFingerprint -Root $project
    $invocation = Invoke-ParserProcess -ProjectRoot $project
    $after = Get-ProjectFingerprint -Root $project
    $readmeReferenced = @($invocation.payload.assets + $invocation.payload.findings | Where-Object { [string]$_.path -ceq ".agents/context/README.md" }).Count -gt 0
    if ($before -cne $after) { $allReadOnly = $false; throw "Parser changed the Context README fixture." }
    if ($invocation.exit_code -ne 0 -or [string]$invocation.payload.status -cne "PASS" -or
        [int]$invocation.payload.asset_count -ne 4 -or $readmeReferenced) {
        throw "The exact Context README was not excluded from canonical enumeration."
    }
    Add-CheckResult -Name "context-readme-non-authority" -Status "PASS" -Detail "The exact .agents/context/README.md is ignored as preserved non-authority documentation without changing its bytes."
}
catch {
    Add-CheckResult -Name "context-readme-non-authority" -Status "FAIL" -Detail $_.Exception.Message
}

try {
    $project = New-FixtureProject -Name "context-readme-case-sensitive"
    $lowercaseRelative = ".agents/context/readme.md"
    Write-AssetText -Path (Join-Path $project $lowercaseRelative) -Text "# Lowercase Context Candidate`n"
    $before = Get-ProjectFingerprint -Root $project
    $invocation = Invoke-ParserProcess -ProjectRoot $project
    $after = Get-ProjectFingerprint -Root $project
    $lowercaseFinding = @($invocation.payload.findings | Where-Object { [string]$_.path -ceq $lowercaseRelative }).Count -gt 0
    if ($before -cne $after) { $allReadOnly = $false; throw "Parser changed the lowercase Context fixture." }
    if ($invocation.exit_code -eq 0 -or [string]$invocation.payload.status -cne "FAIL" -or -not $lowercaseFinding) {
        throw "A lowercase canonical Context candidate was incorrectly exempted as README.md."
    }
    Add-CheckResult -Name "context-readme-case-sensitive" -Status "PASS" -Detail "The README.md exemption is case-sensitive; lowercase readme.md remains a parsed canonical candidate."
}
catch {
    Add-CheckResult -Name "context-readme-case-sensitive" -Status "FAIL" -Detail $_.Exception.Message
}

try {
    $project = New-FixtureProject -Name "context-noncanonical-name-fails-closed"
    $noncanonicalRelative = ".agents/context/README-copy.md"
    Write-AssetText -Path (Join-Path $project $noncanonicalRelative) -Text "# Noncanonical Context Filename`n"
    $before = Get-ProjectFingerprint -Root $project
    $invocation = Invoke-ParserProcess -ProjectRoot $project
    $after = Get-ProjectFingerprint -Root $project
    $noncanonicalFinding = @($invocation.payload.findings | Where-Object { [string]$_.path -ceq $noncanonicalRelative }).Count -gt 0
    if ($before -cne $after) { $allReadOnly = $false; throw "Parser changed the noncanonical Context fixture." }
    if ($invocation.exit_code -eq 0 -or [string]$invocation.payload.status -cne "FAIL" -or -not $noncanonicalFinding) {
        throw "A noncanonical Context filename was silently excluded with README.md."
    }
    Add-CheckResult -Name "context-noncanonical-name-fails-closed" -Status "PASS" -Detail "Only the exact README.md exemption applies; another noncanonical Context filename remains a failing candidate."
}
catch {
    Add-CheckResult -Name "context-noncanonical-name-fails-closed" -Status "FAIL" -Detail $_.Exception.Message
}

try {
    $parserCommand = Get-Command -Name $parserPath -ErrorAction Stop
    if (@($parserCommand.Parameters.Keys) -icontains "SchemaRoot") {
        throw "Product parser still exposes the removed SchemaRoot parameter."
    }
    Add-CheckResult -Name "schema-root-removed" -Status "PASS" -Detail "Product parser parameters do not expose SchemaRoot."
}
catch {
    Add-CheckResult -Name "schema-root-removed" -Status "FAIL" -Detail $_.Exception.Message
}

try {
    $project = New-FixtureProject -Name "schema-authority-custom-relaxation"
    $assetPath = Join-Path $project ".agents/work/fixture-work-item.md"
    Add-UnknownFrontMatterField -Path $assetPath
    $customSchemaDir = Join-Path $project "custom-schemas"
    New-Item -ItemType Directory -Force -Path $customSchemaDir | Out-Null
    $customSchemaText = Get-Content -LiteralPath (Join-Path $schemaRoot "work-item.v1.schema.json") -Raw
    $customSchemaText = $customSchemaText.Replace('"additionalProperties": false', '"additionalProperties": true')
    [System.IO.File]::WriteAllText((Join-Path $customSchemaDir "work-item.v1.schema.json"), $customSchemaText, [System.Text.UTF8Encoding]::new($false))
    $invocation = Invoke-ParserProcess -ProjectRoot $project -ExplicitAssetPath ".agents/work/fixture-work-item.md"
    if ($invocation.exit_code -eq 0 -or [string]$invocation.payload.status -cne "FAIL") {
        throw "A custom relaxed schema changed the parser result for a canonical v1 asset."
    }
    Test-ExpectedCodes -Payload $invocation.payload -ExpectedCodes @("unknown-field")
    Add-CheckResult -Name "schema-authority-custom-relaxation" -Status "PASS" -Detail "Custom schema files cannot relax canonical v1 validation."
}
catch {
    Add-CheckResult -Name "schema-authority-custom-relaxation" -Status "FAIL" -Detail $_.Exception.Message
}

try {
    $copyRoot = New-ParserRepositoryCopy -Name "schema-authority-missing-canonical"
    $schemaPath = Join-Path $copyRoot "schemas/project-workspace/work-item.v1.schema.json"
    Remove-Item -LiteralPath $schemaPath -Force
    $project = New-FixtureProject -Name "schema-authority-missing-project"
    $copyParser = Join-Path $copyRoot "skills/project-workspace/scripts/read-project-assets.ps1"
    $invocation = Invoke-ParserProcess -ProjectRoot $project -ExplicitAssetPath ".agents/work/fixture-work-item.md" -ParserScriptPath $copyParser
    if ($invocation.exit_code -eq 0 -or [string]$invocation.payload.status -cne "FAIL") {
        throw "Missing canonical schema did not fail closed."
    }
    Test-ExpectedCodes -Payload $invocation.payload -ExpectedCodes @("schema-load-failed")
    Add-CheckResult -Name "schema-authority-missing-canonical" -Status "PASS" -Detail "Missing canonical schema returned stable schema-load-failed."
}
catch {
    Add-CheckResult -Name "schema-authority-missing-canonical" -Status "FAIL" -Detail $_.Exception.Message
}

try {
    $copyRoot = New-ParserRepositoryCopy -Name "schema-authority-corrupt-canonical"
    $schemaPath = Join-Path $copyRoot "schemas/project-workspace/work-item.v1.schema.json"
    [System.IO.File]::WriteAllText($schemaPath, '{"type":', [System.Text.UTF8Encoding]::new($false))
    $project = New-FixtureProject -Name "schema-authority-corrupt-project"
    $copyParser = Join-Path $copyRoot "skills/project-workspace/scripts/read-project-assets.ps1"
    $invocation = Invoke-ParserProcess -ProjectRoot $project -ExplicitAssetPath ".agents/work/fixture-work-item.md" -ParserScriptPath $copyParser
    if ($invocation.exit_code -eq 0 -or [string]$invocation.payload.status -cne "FAIL") {
        throw "Corrupt canonical schema did not fail closed."
    }
    Test-ExpectedCodes -Payload $invocation.payload -ExpectedCodes @("schema-load-failed")
    Add-CheckResult -Name "schema-authority-corrupt-canonical" -Status "PASS" -Detail "Corrupt canonical schema returned stable schema-load-failed."
}
catch {
    Add-CheckResult -Name "schema-authority-corrupt-canonical" -Status "FAIL" -Detail $_.Exception.Message
}

$failures = @($results | Where-Object status -eq "FAIL")
$assetTypes = @($cases | Where-Object expected -eq "valid" | ForEach-Object { [string]$_.asset_type } | Sort-Object -Unique)
$summary = [ordered]@{
    schema_version = 1
    status = $(if ($failures.Count -eq 0 -and $baselineContract -and $allReadOnly -and $commandInert -and $templateCount -eq 4 -and $assetTypes.Count -eq 4) { "PASS" } else { "FAIL" })
    scenario_count = $results.Count
    pass = @($results | Where-Object status -eq "PASS").Count
    fail = $failures.Count
    baseline_scenario_count = $baselineScenarioCount
    baseline_pass = $baselinePassCount
    baseline_fail = $baselineFailCount
    baseline_contract = $baselineContract
    hardening_scenario_count = @($hardeningCases).Count + 7
    canonical_sources_read_only = $allReadOnly
    command_inert = $commandInert
    template_count = $templateCount
    asset_type_count = $assetTypes.Count
    cases = @($results.ToArray())
}

if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 10
}
else {
    Write-Output ("project-workspace parser fixtures: PASS={0} FAIL={1}" -f $summary.pass, $summary.fail)
    foreach ($failure in $failures) {
        Write-Output ("[FAIL] {0}: {1}" -f $failure.name, $failure.detail)
    }
}

if ($summary.status -ne "PASS") {
    exit 1
}
exit 0
