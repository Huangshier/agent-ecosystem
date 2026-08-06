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
        [string]$ExplicitAssetPath = ""
    )

    $arguments = @(
        "-NoProfile", "-NonInteractive", "-File", $parserPath,
        "-ProjectRoot", $ProjectRoot,
        "-SchemaRoot", $schemaRoot,
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

foreach ($requiredPath in @($parserPath, $schemaRoot, $templateRoot, $fixtureProject, $caseManifestPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required project workspace fixture dependency is missing: $requiredPath"
    }
}

$cases = @(Get-Content -LiteralPath $caseManifestPath -Raw | ConvertFrom-Json -Depth 20)
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
                throw "Expected a valid parser result. Exit=$($invocation.exit_code) Status=$($invocation.payload.status)"
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
            throw "Canonical template did not pass its parser contract."
        }
        $templateCount++
        Add-CheckResult -Name ("template-{0}" -f $templateName) -Status "PASS" -Detail "Canonical template passed from its canonical project path."
    }
    catch {
        Add-CheckResult -Name ("template-{0}" -f $templateName) -Status "FAIL" -Detail $_.Exception.Message
    }
}

$failures = @($results | Where-Object status -eq "FAIL")
$assetTypes = @($cases | Where-Object expected -eq "valid" | ForEach-Object { [string]$_.asset_type } | Sort-Object -Unique)
$summary = [ordered]@{
    schema_version = 1
    status = $(if ($failures.Count -eq 0 -and $allReadOnly -and $commandInert -and $templateCount -eq 4 -and $assetTypes.Count -eq 4) { "PASS" } else { "FAIL" })
    scenario_count = $results.Count
    pass = @($results | Where-Object status -eq "PASS").Count
    fail = $failures.Count
    project_read_only = $allReadOnly
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
