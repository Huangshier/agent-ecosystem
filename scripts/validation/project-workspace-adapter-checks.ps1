#requires -Version 7.6

<##
Focused C3.3 Slice G1 verifier for the explicit project-workspace adapter.

The verifier owns only temporary projects.  It never treats the adapter output as
canonical authority: every mutation is checked against a source snapshot, a
target snapshot, and the two Git-ignore surfaces.  The same fixture is mutated
between scenarios so the lifecycle assertions exercise real state transitions
instead of independent happy-path projects.
##>

[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion -lt [version]"7.6") {
    throw "Project workspace adapter checks require PowerShell 7.6 or newer."
}

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    [IO.Path]::GetFullPath((Join-Path $scriptDir "../.."))
}
else {
    [IO.Path]::GetFullPath($RepositoryRoot)
}

$dispatcher = Join-Path $repoRoot "skills/project-workspace/scripts/project-workspace.ps1"
$adapterModule = Join-Path $repoRoot "skills/project-workspace/scripts/project-workspace-adapter.ps1"
$bootstrapScript = Join-Path $repoRoot "skills/project-bootstrap/scripts/bootstrap_project.ps1"
$hubRoot = Join-Path $repoRoot "knowledge-hub"
$uninstallScript = Join-Path $repoRoot "scripts/uninstall.ps1"
$installScript = Join-Path $repoRoot "scripts/install.ps1"
$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source

if (-not (Test-Path -LiteralPath $dispatcher -PathType Leaf)) {
    throw "Project workspace dispatcher is missing: $dispatcher"
}

$scratchParent = if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    [IO.Path]::GetTempPath()
}
else {
    [IO.Path]::GetFullPath($ScratchRoot)
}
$runRoot = Join-Path $scratchParent ("project-workspace-adapter-{0}" -f ([Guid]::NewGuid().ToString("N")))
$projectRoot = Join-Path $runRoot "project"
$bootstrapRoot = Join-Path $runRoot "bootstrap"
$runtimeRoot = Join-Path $runRoot "runtime"
$cases = New-Object 'System.Collections.Generic.List[object]'

function Add-Case {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet("PASS", "FAIL")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    [void]$cases.Add([ordered]@{
            name = $Name
            status = $Status
            detail = $Detail
        })
}

function Invoke-Case {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    try {
        $result = @(& $Action)
        $detail = @($result | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Last 1)
        Add-Case -Name $Name -Status "PASS" -Detail $(if ($detail.Count -gt 0) { [string]$detail[0] } else { "Behavior assertions passed." })
    }
    catch {
        Add-Case -Name $Name -Status "FAIL" -Detail (Get-SafeDetail -Message $_.Exception.Message)
    }
}

function Get-SafeDetail {
    param([AllowEmptyString()][string]$Message)

    $safe = [string]$Message
    foreach ($path in @($runRoot, $repoRoot, $projectRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $safe = $safe.Replace($path, "<scratch>", [StringComparison]::OrdinalIgnoreCase)
        }
    }
    return $safe
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Write-Utf8Bytes {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [IO.File]::WriteAllBytes($Path, [Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Get-ExecutableFlag {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)

    $unixModeProperty = $File.PSObject.Properties["UnixFileMode"]
    if ($null -eq $unixModeProperty) { return $false }
    return ([string]$unixModeProperty.Value -match "Execute")
}

function Set-ExecutableFlag {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][bool]$Executable
    )

    if (-not $Executable -or $IsWindows) { return }
    $mode = [IO.File]::GetUnixFileMode($Path)
    $mode = $mode -bor [IO.UnixFileMode]::UserExecute
    [IO.File]::SetUnixFileMode($Path, $mode)
}

function Get-TreeRecords {
    param([Parameter(Mandatory = $true)][string]$Root)

    $records = New-Object 'System.Collections.Generic.List[string]'
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]"/\")
    foreach ($item in @(Get-ChildItem -LiteralPath $rootFull -Recurse -Force | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($rootFull, $item.FullName).Replace('\', '/')
        $isLink = ($item.PSObject.Properties["LinkType"] -and -not [string]::IsNullOrWhiteSpace([string]$item.LinkType)) -or
            (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
        if ($item.PSIsContainer) {
            [void]$records.Add(("D|{0}|link={1}" -f $relative, [bool]$isLink))
            continue
        }
        if ($isLink) {
            [void]$records.Add(("L|{0}|{1}" -f $relative, [string]$item.Target))
            continue
        }
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [void]$records.Add(("F|{0}|{1}|{2}|exec={3}" -f $relative, $item.Length, $hash, (Get-ExecutableFlag -File $item)))
    }
    return @($records.ToArray())
}

function Get-TreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    $text = (Get-TreeRecords -Root $Root) -join "`n"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bytes))).Replace('-', '').ToLowerInvariant()
}

function Get-FileSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $snapshot = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $snapshot }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]"/\")
    foreach ($item in @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($rootFull, $item.FullName).Replace('\', '/')
        if ($relative -match '(?i)(^|/)\.agent-ecosystem-adapter\.json$') { continue }
        $snapshot[$relative] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($item.FullName))
    }
    return $snapshot
}

function Test-SnapshotEqual {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Before,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$After
    )

    $beforeKeys = @($Before.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $afterKeys = @($After.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    if (($beforeKeys -join "`n") -cne ($afterKeys -join "`n")) { return $false }
    foreach ($key in $beforeKeys) {
        if ([string]$Before[$key] -cne [string]$After[$key]) { return $false }
    }
    return $true
}

function Get-PropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return ,$Object[$Name] }
    }
    else {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return ,$property.Value }
    }
    return $null
}

function Get-JsonPayload {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Invocation)

    if ($null -ne $Invocation.payload) { return $Invocation.payload }
    $text = [string]$Invocation.text
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return ($text | ConvertFrom-Json -Depth 100 -ErrorAction Stop) }
    catch { return $null }
}

function Invoke-PwshScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @()
    )

    $global:LASTEXITCODE = 0
    $output = @(& $pwshPath -NoProfile -NonInteractive -File $Path @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $text = @($output) -join "`n"
    $payload = $null
    try { $payload = $text | ConvertFrom-Json -Depth 100 -ErrorAction Stop } catch { }
    return [ordered]@{ exit_code = $exitCode; output = @($output); text = $text; payload = $payload }
}

function Invoke-Workspace {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("create-adapter", "rebuild-adapter", "status-adapter", "remove-adapter")][string]$Operation,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$Target = "claude-code",
        [int]$FailureAfterReplacement = 0
    )

    $arguments = @("-Operation", $Operation, "-ProjectRoot", $ProjectRoot, "-Target", $Target, "-Json")
    if ($FailureAfterReplacement -gt 0) {
        $arguments += @("-FailureAfterReplacement", [string]$FailureAfterReplacement)
    }
    $result = Invoke-PwshScript -Path $dispatcher -Arguments $arguments
    $result.payload = Get-JsonPayload -Invocation $result
    return $result
}

function Test-InvocationFailed {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Invocation)

    if ([int]$Invocation.exit_code -ne 0) { return $true }
    $payload = Get-JsonPayload -Invocation $Invocation
    $status = [string](Get-PropertyValue -Object $payload -Name "status")
    return $status -match '(?i)^(FAIL|ERROR|BLOCKED|CONFLICT|REJECTED)$'
}

function Assert-InvocationSuccess {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Invocation,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (Test-InvocationFailed -Invocation $Invocation) {
        throw "$Name did not succeed: $($Invocation.text)"
    }
}

function Assert-InvocationFailed {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Invocation,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-InvocationFailed -Invocation $Invocation)) {
        throw "$Name unexpectedly succeeded: $($Invocation.text)"
    }
}

function Get-ReportedStateValues {
    param([AllowNull()][object]$Object)

    $states = New-Object 'System.Collections.Generic.List[string]'
    $allowed = @("absent", "current", "stale", "modified", "conflict", "unknown", "invalid-ownership", "invalid_ownership")
    function Visit([AllowNull()][object]$Value, [string]$PropertyName) {
        if ($null -eq $Value) { return }
        if ($Value -is [string]) {
            $text = [string]$Value
            if ($PropertyName -match '(?i)(state|status|result|ownership|outcome)' -and $allowed -contains $text.ToLowerInvariant()) {
                [void]$states.Add($text.ToLowerInvariant())
            }
            return
        }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            foreach ($entry in $Value) { Visit -Value $entry -PropertyName $PropertyName }
            return
        }
        foreach ($property in @($Value.PSObject.Properties)) {
            Visit -Value $property.Value -PropertyName ([string]$property.Name)
        }
    }
    Visit -Value $Object -PropertyName ""
    return @($states.ToArray() | Sort-Object -Unique)
}

function Assert-ReportedState {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Invocation,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $payload = Get-JsonPayload -Invocation $Invocation
    $values = @(Get-ReportedStateValues -Object $payload)
    $raw = [string]$Invocation.text
    $pattern = switch ($Expected) {
        "modified" { '(?i)modified|conflict' }
        "unknown" { '(?i)unknown|invalid[-_]ownership' }
        default { "(?i)(?<![A-Za-z0-9_-])$([regex]::Escape($Expected))(?![A-Za-z0-9_-])" }
    }
    if ($values -contains $Expected -or $raw -match $pattern) { return }
    throw "$Name did not report state '$Expected'. Values=$($values -join ','); output=$raw"
}

function Get-AdapterRoot {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path $Root ".claude/skills")
}

function Get-AdapterPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return (Join-Path (Get-AdapterRoot -Root $Root) $Name)
}

function Get-AdapterTransactionRoots {
    param([Parameter(Mandatory = $true)][string]$Root)

    return @(Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -cmatch '^\.agent-ecosystem-adapter-transaction-[0-9a-f]{32}$' })
}

function Get-SourcePath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path $Root ".agents/skills")
}

function Get-MarkerPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return (Join-Path (Get-AdapterPath -Root $Root -Name $Name) ".agent-ecosystem-adapter.json")
}

function Get-GitIgnoreSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $snapshot = [ordered]@{}
    foreach ($relative in @(".gitignore", ".git/info/exclude")) {
        $path = Join-Path $Root ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $snapshot[$relative] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
        }
        else {
            $snapshot[$relative] = $null
        }
    }
    return $snapshot
}

function Assert-PathAbsent {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if (Test-Path -LiteralPath $Path) { throw "$Name unexpectedly exists: $Path" }
}

function Assert-PathPresent {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Name is missing: $Path" }
}

function Assert-ExactMapping {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string[]]$SkillNames
    )

    $sourceRoot = Get-SourcePath -Root $ProjectRoot
    $targetRoot = Get-AdapterRoot -Root $ProjectRoot
    $actualNames = @(Get-ChildItem -LiteralPath $targetRoot -Directory -Force -ErrorAction Stop |
        Where-Object { $_.Name -cne "." -and $_.Name -cne ".." } |
        ForEach-Object { [string]$_.Name } | Sort-Object)
    $expectedNames = @($SkillNames | Sort-Object)
    if (($actualNames -join "`n") -cne ($expectedNames -join "`n")) {
        throw "Target mapping contains unexpected or missing Skill directories. Expected=$($expectedNames -join ','); actual=$($actualNames -join ',')."
    }
    foreach ($name in $SkillNames) {
        $sourceSkill = Join-Path $sourceRoot $name
        $targetSkill = Get-AdapterPath -Root $ProjectRoot -Name $name
        Assert-PathPresent -Path $targetSkill -Name "mapped target $name"
        $sourceFiles = Get-FileSnapshot -Root $sourceSkill
        $targetFiles = Get-FileSnapshot -Root $targetSkill
        if (-not (Test-SnapshotEqual -Before $sourceFiles -After $targetFiles)) {
            throw "Managed copy bytes or relative mapping differ for '$name'."
        }
        $markerPath = Get-MarkerPath -Root $ProjectRoot -Name $name
        Assert-PathPresent -Path $markerPath -Name "ownership marker $name"
        $markerBytes = [IO.File]::ReadAllBytes($markerPath)
        if ($markerBytes.Length -ge 3 -and $markerBytes[0] -eq 0xEF -and $markerBytes[1] -eq 0xBB -and $markerBytes[2] -eq 0xBF) {
            throw "Ownership marker '$name' contains a UTF-8 BOM."
        }
        $markerText = [Text.UTF8Encoding]::new($false, $true).GetString($markerBytes)
        if ($markerText.Contains("`r")) { throw "Ownership marker '$name' is not LF-normalized." }
        $markerFields = @("schema_version", "owner", "adapter_target", "representation", "lifecycle", "source", "target", "content_sha256")
        $lastMarkerFieldIndex = -1
        foreach ($field in $markerFields) {
            $fieldIndex = $markerText.IndexOf(('"{0}"' -f $field), [StringComparison]::Ordinal)
            if ($fieldIndex -lt 0 -or $fieldIndex -le $lastMarkerFieldIndex) {
                throw "Ownership marker '$name' does not use the frozen deterministic field order."
            }
            $lastMarkerFieldIndex = $fieldIndex
        }
        $marker = $markerText | ConvertFrom-Json -Depth 20
        if ([int]$marker.schema_version -ne 1 -or
            [string]$marker.owner -cne "agent-ecosystem" -or
            [string]$marker.adapter_target -cne "claude-code" -or
            [string]$marker.representation -cne "managed-copy" -or
            [string]$marker.lifecycle -cne "derived" -or
            [string]$marker.source -cne (".agents/skills/{0}" -f $name) -or
            [string]$marker.target -cne (".claude/skills/{0}" -f $name) -or
            [string]$marker.content_sha256 -notmatch '^sha256:[0-9a-f]{64}$') {
            throw "Ownership marker contract is invalid for '$name'."
        }
    }
}

function New-FixtureProject {
    param([Parameter(Mandatory = $true)][string]$Root)

    New-Item -ItemType Directory -Force -Path (Join-Path $Root ".agents/skills/alpha"), (Join-Path $Root ".agents/skills/beta"), (Join-Path $Root ".git/info") | Out-Null
    Write-Utf8Bytes -Path (Join-Path $Root ".agents/skills/alpha/SKILL.md") -Text "---`r`nname: alpha`r`ndescription: Alpha fixture`r`n---`r`n`r`nalpha body`r`n"
    Write-Utf8Bytes -Path (Join-Path $Root ".agents/skills/alpha/nested.txt") -Text "accent: café`r`nline-two`r`n"
    Write-Utf8Bytes -Path (Join-Path $Root ".agents/skills/beta/SKILL.md") -Text "---`nname: beta`ndescription: Beta fixture`n---`n`nbeta body`n"
    Write-Utf8Bytes -Path (Join-Path $Root ".agents/skills/beta/exec.sh") -Text "#!/bin/sh`nprintf beta`n"
    Set-ExecutableFlag -Path (Join-Path $Root ".agents/skills/beta/exec.sh") -Executable (-not $IsWindows)
    Write-Utf8NoBom -Path (Join-Path $Root ".gitignore") -Text "# adapter verifier fixture`nignored.txt`n"
    Write-Utf8NoBom -Path (Join-Path $Root ".git/info/exclude") -Text "# adapter verifier exclude`nlocal.txt`n"
}

function Restore-AlphaCanonicalFixture {
    $alphaRoot = Join-Path (Get-SourcePath -Root $projectRoot) "alpha"
    New-Item -ItemType Directory -Force -Path $alphaRoot | Out-Null
    Write-Utf8Bytes -Path (Join-Path $alphaRoot "SKILL.md") -Text "---`r`nname: alpha`r`ndescription: Restored`r`n---`r`n`nrestored`r`n"
    Write-Utf8Bytes -Path (Join-Path $alphaRoot "nested.txt") -Text "restored café`r`n"
}

function New-SymbolicLinkFixture {
    param(
        [Parameter(Mandatory = $true)][string]$LinkPath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    try {
        if (Test-Path -LiteralPath $LinkPath) { Remove-Item -LiteralPath $LinkPath -Force -Recurse }
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-AdapterFailureSeam {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$FailBeforeBackupRestore
    )

    if (-not (Test-Path -LiteralPath $adapterModule -PathType Leaf)) {
        throw "Adapter module seam is missing: $adapterModule"
    }

    . (Join-Path $repoRoot "scripts/lib/path-guard.ps1")
    . $adapterModule
    $command = Get-Command Invoke-AdapterOperation -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw "Invoke-AdapterOperation seam is not exported by adapter module." }

    $parameters = @{}
    foreach ($name in @($command.Parameters.Keys)) {
        switch -Regex ($name) {
            '^Operation$' { $parameters[$name] = "rebuild-adapter"; break }
            '^(Root|ProjectRoot)$' { $parameters[$name] = $ProjectRoot; break }
            '^Target$' { $parameters[$name] = "claude-code"; break }
            '^FailureAfterReplacement$' { $parameters[$name] = 1; break }
            '^FailBeforeBackupRestore$' {
                if ($FailBeforeBackupRestore.IsPresent) { $parameters[$name] = $true }
                break
            }
            '^Json$' { $parameters[$name] = $true; break }
        }
    }
    if (-not $parameters.ContainsKey("FailureAfterReplacement")) {
        throw "Invoke-AdapterOperation does not expose FailureAfterReplacement seam."
    }
    if ($FailBeforeBackupRestore.IsPresent -and -not $parameters.ContainsKey("FailBeforeBackupRestore")) {
        throw "Invoke-AdapterOperation does not expose FailBeforeBackupRestore seam."
    }
    try {
        $output = @(& $command @parameters 2>&1)
        $payload = @($output | Where-Object {
                $_ -is [System.Collections.IDictionary] -or $null -ne $_.PSObject.Properties["status"]
            } | Select-Object -Last 1)
        $payload = if ($payload.Count -gt 0) { $payload[0] } else { $null }
        $rawText = @($output | ForEach-Object { [string]$_ }) -join "`n"
        if ($null -eq $payload -and -not [string]::IsNullOrWhiteSpace($rawText)) {
            try { $payload = $rawText | ConvertFrom-Json -Depth 50 -ErrorAction Stop } catch { }
        }
        $text = if ($null -ne $payload) { $payload | ConvertTo-Json -Depth 50 -Compress } else { $rawText }
        return [ordered]@{
            exit_code = if ($null -ne $payload -and [string]$payload.status -ceq "FAIL") { 1 } else { 0 }
            payload = $payload
            text = $text
            output = @($output)
        }
    }
    catch {
        return [ordered]@{ exit_code = 1; payload = $null; text = $_.Exception.Message; output = @($_.Exception.Message) }
    }
}

try {
    New-Item -ItemType Directory -Force -Path $runRoot, $projectRoot, $bootstrapRoot | Out-Null
    New-FixtureProject -Root $projectRoot

    Invoke-Case -Name "bootstrap-default-no-adapter" -Action {
        $invocation = Invoke-PwshScript -Path $bootstrapScript -Arguments @(
            "-ProjectDir", $bootstrapRoot,
            "-HubDir", $hubRoot,
            "-ProjectLanguage", "en",
            "-SkipMemoryUpgradeAnalysis"
        )
        if ([int]$invocation.exit_code -ne 0) { throw "Bootstrap failed: $($invocation.text)" }
        Assert-PathAbsent -Path (Join-Path $bootstrapRoot ".claude/skills") -Name "bootstrap adapter target"
        "Bootstrap may create Claude project guardrails, but never materializes the adapter target by default."
    }

    Invoke-Case -Name "status-absent" -Action {
        $status = Invoke-Workspace -Operation "status-adapter" -ProjectRoot $projectRoot
        Assert-ReportedState -Invocation $status -Expected "absent" -Name "absent status"
        "An unmaterialized Claude target is reported as absent without writes."
    }

    Invoke-Case -Name "unsupported-target-fails-closed" -Action {
        $beforeSource = Get-TreeFingerprint -Root (Get-SourcePath -Root $projectRoot)
        $beforeTarget = Get-TreeFingerprint -Root (Join-Path $projectRoot ".claude")
        $run = Invoke-Workspace -Operation "create-adapter" -ProjectRoot $projectRoot -Target "zcode"
        Assert-InvocationFailed -Invocation $run -Name "unsupported target"
        if ((Get-TreeFingerprint -Root (Get-SourcePath -Root $projectRoot)) -cne $beforeSource -or
            (Get-TreeFingerprint -Root (Join-Path $projectRoot ".claude")) -cne $beforeTarget) {
            throw "Unsupported target changed project state."
        }
        "Only the frozen claude-code adapter target is accepted."
    }

    Invoke-Case -Name "explicit-create-exact-mapping" -Action {
        $beforeCanonical = Get-TreeFingerprint -Root (Get-SourcePath -Root $projectRoot)
        $beforeIgnore = Get-GitIgnoreSnapshot -Root $projectRoot
        $run = Invoke-Workspace -Operation "create-adapter" -ProjectRoot $projectRoot
        Assert-InvocationSuccess -Invocation $run -Name "create-adapter"
        Assert-ExactMapping -ProjectRoot $projectRoot -SkillNames @("alpha", "beta")
        if (@(Get-AdapterTransactionRoots -Root $projectRoot).Count -ne 0) { throw "Successful adapter transaction retained a transaction root." }
        if ((Get-TreeFingerprint -Root (Get-SourcePath -Root $projectRoot)) -cne $beforeCanonical) { throw "Create modified canonical Skills." }
        if (-not (Test-SnapshotEqual -Before $beforeIgnore -After (Get-GitIgnoreSnapshot -Root $projectRoot))) { throw "Create modified Git ignore surfaces." }
        "Managed-copy output exactly mirrors .agents/skills and writes only derived markers."
    }

    Invoke-Case -Name "deterministic-create-and-current" -Action {
        $before = Get-TreeRecords -Root (Get-AdapterRoot -Root $projectRoot)
        $run = Invoke-Workspace -Operation "create-adapter" -ProjectRoot $projectRoot
        Assert-InvocationSuccess -Invocation $run -Name "idempotent create-adapter"
        if (((Get-TreeRecords -Root (Get-AdapterRoot -Root $projectRoot)) -join "`n") -cne ($before -join "`n")) { throw "Repeated create changed deterministic adapter bytes." }
        $status = Invoke-Workspace -Operation "status-adapter" -ProjectRoot $projectRoot
        Assert-ReportedState -Invocation $status -Expected "current" -Name "current status"
        "Repeated create is byte-stable and reports current ownership."
    }

    Invoke-Case -Name "stale-rebuild-and-byte-contract" -Action {
        $sourceAlpha = Join-Path (Get-SourcePath -Root $projectRoot) "alpha/SKILL.md"
        $targetBefore = Get-FileSnapshot -Root (Get-AdapterPath -Root $projectRoot -Name "alpha")
        Write-Utf8Bytes -Path $sourceAlpha -Text "---`r`nname: alpha`r`ndescription: Changed`r`n---`r`n`r`nchanged café`r`n"
        $status = Invoke-Workspace -Operation "status-adapter" -ProjectRoot $projectRoot
        Assert-ReportedState -Invocation $status -Expected "stale" -Name "stale status"
        if (-not (Test-SnapshotEqual -Before $targetBefore -After (Get-FileSnapshot -Root (Get-AdapterPath -Root $projectRoot -Name "alpha")))) { throw "Read-only stale status changed target bytes." }
        $rebuild = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
        Assert-InvocationSuccess -Invocation $rebuild -Name "stale rebuild-adapter"
        Assert-ExactMapping -ProjectRoot $projectRoot -SkillNames @("alpha", "beta")
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path (Get-AdapterPath -Root $projectRoot -Name "alpha") "SKILL.md"))) -ne
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($sourceAlpha))) { throw "Rebuild did not preserve source bytes/newlines/encoding." }
        $rebuildTree = Get-TreeRecords -Root (Get-AdapterRoot -Root $projectRoot)
        $repeat = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
        Assert-InvocationSuccess -Invocation $repeat -Name "deterministic repeat rebuild-adapter"
        if (((Get-TreeRecords -Root (Get-AdapterRoot -Root $projectRoot)) -join "`n") -cne ($rebuildTree -join "`n")) { throw "Repeated rebuild changed deterministic adapter bytes." }
        "Stale output is rebuilt from unchanged bytes without canonical rewrites."
    }

    Invoke-Case -Name "modified-conflict-protection" -Action {
        $targetFile = Join-Path (Get-AdapterPath -Root $projectRoot -Name "alpha") "nested.txt"
        Write-Utf8NoBom -Path $targetFile -Text "user modification`n"
        $beforeTarget = Get-TreeFingerprint -Root (Get-AdapterRoot -Root $projectRoot)
        $status = Invoke-Workspace -Operation "status-adapter" -ProjectRoot $projectRoot
        Assert-ReportedState -Invocation $status -Expected "modified" -Name "modified status"
        $rebuild = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
        Assert-InvocationFailed -Invocation $rebuild -Name "modified rebuild-adapter"
        if ((Get-TreeFingerprint -Root (Get-AdapterRoot -Root $projectRoot)) -cne $beforeTarget) { throw "Modified target was overwritten or partially rebuilt." }
        $remove = Invoke-Workspace -Operation "remove-adapter" -ProjectRoot $projectRoot
        Assert-InvocationFailed -Invocation $remove -Name "modified remove-adapter"
        if ((Get-TreeFingerprint -Root (Get-AdapterRoot -Root $projectRoot)) -cne $beforeTarget) { throw "Modified target was removed despite conflict protection." }
        Write-Utf8Bytes -Path $targetFile -Text ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Get-FileSnapshot -Root (Get-SourcePath -Root $projectRoot))["alpha/nested.txt"])))
        "Modified managed payload is reported and preserved; rebuild fails closed."
    }

    Invoke-Case -Name "unowned-collision-protection" -Action {
        $targetBeta = Get-AdapterPath -Root $projectRoot -Name "beta"
        try {
            if (Test-Path -LiteralPath $targetBeta) { Remove-Item -LiteralPath $targetBeta -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $targetBeta | Out-Null
            Write-Utf8NoBom -Path (Join-Path $targetBeta "user.txt") -Text "unowned user content`n"
            $before = Get-TreeFingerprint -Root $targetBeta
            $status = Invoke-Workspace -Operation "status-adapter" -ProjectRoot $projectRoot
            Assert-ReportedState -Invocation $status -Expected "modified" -Name "unowned status"
            $create = Invoke-Workspace -Operation "create-adapter" -ProjectRoot $projectRoot
            Assert-InvocationFailed -Invocation $create -Name "unowned create-adapter"
            if ((Get-TreeFingerprint -Root $targetBeta) -cne $before) { throw "Unowned target was overwritten." }
            $remove = Invoke-Workspace -Operation "remove-adapter" -ProjectRoot $projectRoot
            Assert-InvocationFailed -Invocation $remove -Name "unowned remove-adapter"
            if ((Get-TreeFingerprint -Root $targetBeta) -cne $before) { throw "Unowned target was removed." }
            "Unowned target collision is modified/conflict and remains untouched."
        }
        finally {
            if (Test-Path -LiteralPath $targetBeta) { Remove-Item -LiteralPath $targetBeta -Recurse -Force }
            $restore = Invoke-Workspace -Operation "create-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $restore -Name "unowned fixture recovery create-adapter"
        }
    }

    Invoke-Case -Name "source-deleted-orphan-and-explicit-remove" -Action {
        $sourceAlpha = Join-Path (Get-SourcePath -Root $projectRoot) "alpha"
        $targetAlpha = Get-AdapterPath -Root $projectRoot -Name "alpha"
        $beforeTarget = Get-TreeFingerprint -Root $targetAlpha
        try {
            Remove-Item -LiteralPath $sourceAlpha -Recurse -Force
            $status = Invoke-Workspace -Operation "status-adapter" -ProjectRoot $projectRoot
            Assert-ReportedState -Invocation $status -Expected "stale" -Name "orphan status"
            $rebuild = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
            if ((Get-TreeFingerprint -Root $targetAlpha) -cne $beforeTarget) { throw "Rebuild cleaned or changed a source-deleted orphan." }
            if (-not (Test-Path -LiteralPath $targetAlpha -PathType Container)) { throw "Source-deleted orphan was removed by rebuild." }
            $remove = Invoke-Workspace -Operation "remove-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $remove -Name "explicit remove-adapter"
            Assert-PathAbsent -Path $targetAlpha -Name "removed orphan target"
            Assert-PathAbsent -Path (Get-AdapterPath -Root $projectRoot -Name "beta") -Name "removed current target"
            "Rebuild retains source-deleted stale output; only explicit remove cleans it."
        }
        finally {
            Restore-AlphaCanonicalFixture
            $removeBaseline = Invoke-Workspace -Operation "remove-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $removeBaseline -Name "orphan fixture recovery remove-adapter"
            $createBaseline = Invoke-Workspace -Operation "create-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $createBaseline -Name "orphan fixture recovery create-adapter"
        }
    }

    # The orphan case leaves the shared fixture at the current restored baseline.

    Invoke-Case -Name "target-wide-no-partial" -Action {
        $alphaSource = Join-Path (Get-SourcePath -Root $projectRoot) "alpha/SKILL.md"
        $betaTarget = Get-AdapterPath -Root $projectRoot -Name "beta"
        try {
            $create = Invoke-Workspace -Operation "create-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $create -Name "target-wide setup create-adapter"
            Write-Utf8Bytes -Path $alphaSource -Text "---`nname: alpha`ndescription: target-wide mutation`n---`n`nchanged`n"
            $betaFile = Join-Path $betaTarget "SKILL.md"
            Write-Utf8NoBom -Path $betaFile -Text "user conflict`n"
            $before = Get-TreeRecords -Root (Get-AdapterRoot -Root $projectRoot)
            $rebuild = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
            Assert-InvocationFailed -Invocation $rebuild -Name "target-wide rebuild"
            if (((Get-TreeRecords -Root (Get-AdapterRoot -Root $projectRoot)) -join "`n") -cne ($before -join "`n")) { throw "Target-wide preflight allowed a partial replacement." }
            "Any candidate conflict blocks the complete target-wide operation before partial success."
        }
        finally {
            Restore-AlphaCanonicalFixture
            if (Test-Path -LiteralPath $betaTarget) { Remove-Item -LiteralPath $betaTarget -Recurse -Force }
            $restore = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $restore -Name "target-wide fixture recovery rebuild-adapter"
        }
    }

    Invoke-Case -Name "replacement-rollback" -Action {
        $sourceAlpha = Join-Path (Get-SourcePath -Root $projectRoot) "alpha/SKILL.md"
        try {
            $clean = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $clean -Name "rollback clean rebuild"
            Write-Utf8Bytes -Path $sourceAlpha -Text "---`nname: alpha`ndescription: rollback mutation`n---`n`nrollback candidate`n"
            $beforeTarget = Get-TreeRecords -Root (Get-AdapterRoot -Root $projectRoot)
            $beforeSource = Get-TreeFingerprint -Root (Get-SourcePath -Root $projectRoot)
            $seam = Invoke-AdapterFailureSeam -ProjectRoot $projectRoot
            $seamPayload = $seam.payload
            if ($null -eq $seamPayload -or [string]$seamPayload.status -cne "FAIL" -or [string]$seamPayload.rollback -cne "restored" -or [bool]$seamPayload.partial_success) {
                throw "Replacement failure seam contract mismatch: $($seam.text)"
            }
            if (((Get-TreeRecords -Root (Get-AdapterRoot -Root $projectRoot)) -join "`n") -cne ($beforeTarget -join "`n")) { throw "Replacement failure left a partial target replacement." }
            if ((Get-TreeFingerprint -Root (Get-SourcePath -Root $projectRoot)) -cne $beforeSource) { throw "Replacement failure modified canonical source." }
            if (@(Get-AdapterTransactionRoots -Root $projectRoot).Count -ne 0) { throw "Successful rollback retained a transaction root." }
            "Injected replacement failure restores the pre-operation adapter and canonical snapshots."
        }
        finally {
            Restore-AlphaCanonicalFixture
            $recover = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $recover -Name "post-rollback recovery rebuild-adapter"
        }
    }

    Invoke-Case -Name "rollback-failure-retains-recovery-evidence" -Action {
        $sourceAlpha = Join-Path (Get-SourcePath -Root $projectRoot) "alpha/SKILL.md"
        try {
            $clean = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $clean -Name "rollback failure clean rebuild"
            Write-Utf8Bytes -Path $sourceAlpha -Text "---`nname: alpha`ndescription: rollback failure mutation`n---`n`nrollback failure candidate`n"
            $beforeSource = Get-TreeFingerprint -Root (Get-SourcePath -Root $projectRoot)
            $seam = Invoke-AdapterFailureSeam -ProjectRoot $projectRoot -FailBeforeBackupRestore
            $seamPayload = $seam.payload
            $finding = @($seamPayload.findings | Where-Object {
                    [string]$_.code -ceq "adapter-rollback-failed-recovery-retained" -and
                    [string]$_.message -match '(?i)recovery evidence was retained'
                })
            if ([int]$seam.exit_code -eq 0 -or $null -eq $seamPayload -or [string]$seamPayload.status -cne "FAIL" -or
                [string]$seamPayload.rollback -cne "failed" -or [bool]$seamPayload.partial_success -or $finding.Count -ne 1) {
                throw "Rollback failure seam contract mismatch: $($seam.text)"
            }
            $transactionRoots = @(Get-AdapterTransactionRoots -Root $projectRoot)
            if ($transactionRoots.Count -ne 1) { throw "Rollback failure did not retain exactly one transaction root." }
            $backupAlpha = Join-Path $transactionRoots[0].FullName "backup/alpha"
            $recoveryAlpha = Join-Path $transactionRoots[0].FullName "recovery/alpha"
            Assert-PathPresent -Path (Join-Path $backupAlpha "SKILL.md") -Name "retained rollback backup"
            Assert-PathPresent -Path (Join-Path $recoveryAlpha "SKILL.md") -Name "retained rollback recovery"
            if ((Get-TreeFingerprint -Root (Get-SourcePath -Root $projectRoot)) -cne $beforeSource) { throw "Rollback failure modified canonical source." }
            "Failed rollback reports FAIL without partial success and retains backup/recovery evidence."
        }
        finally {
            Restore-AlphaCanonicalFixture
            $recover = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $recover -Name "post-rollback-failure recovery rebuild-adapter"
            foreach ($transactionRoot in @(Get-AdapterTransactionRoots -Root $projectRoot)) {
                Remove-Item -LiteralPath $transactionRoot.FullName -Recurse -Force
            }
        }
    }

    Invoke-Case -Name "runtime-uninstall-zero-project-cleanup" -Action {
        $create = Invoke-Workspace -Operation "create-adapter" -ProjectRoot $projectRoot
        Assert-InvocationSuccess -Invocation $create -Name "uninstall setup create-adapter"
        $beforeProject = Get-TreeFingerprint -Root $projectRoot
        $install = Invoke-PwshScript -Path $installScript -Arguments @("-Profile", "minimal", "-TargetDir", $runtimeRoot)
        if ([int]$install.exit_code -ne 0) { throw "Scratch runtime install failed: $($install.text)" }
        $uninstall = Invoke-PwshScript -Path $uninstallScript -Arguments @("-TargetDir", $runtimeRoot, "-Json")
        if ([int]$uninstall.exit_code -ne 0) { throw "Scratch runtime uninstall failed: $($uninstall.text)" }
        if ((Get-TreeFingerprint -Root $projectRoot) -cne $beforeProject) { throw "Runtime uninstall changed project adapter or canonical assets." }
        Assert-PathPresent -Path (Get-AdapterRoot -Root $projectRoot) -Name "project adapter after runtime uninstall"
        "Runtime uninstall does not scan or clean project-local adapter output."
    }

    Invoke-Case -Name "git-ignore-surfaces-unchanged" -Action {
        $before = Get-GitIgnoreSnapshot -Root $projectRoot
        $status = Invoke-Workspace -Operation "status-adapter" -ProjectRoot $projectRoot
        Assert-ReportedState -Invocation $status -Expected "current" -Name "Git ignore status"
        $after = Get-GitIgnoreSnapshot -Root $projectRoot
        if (-not (Test-SnapshotEqual -Before $before -After $after)) { throw "Adapter operation changed .gitignore or .git/info/exclude." }
        "Adapter lifecycle leaves Git ignore and commit-policy surfaces untouched."
    }

    Invoke-Case -Name "posix-executable-preservation" -Action {
        $sourceExec = Join-Path (Get-SourcePath -Root $projectRoot) "beta/exec.sh"
        $targetExec = Join-Path (Get-AdapterPath -Root $projectRoot -Name "beta") "exec.sh"
        if (-not $IsWindows) {
            if (-not (Get-ExecutableFlag -File (Get-Item -LiteralPath $sourceExec))) { throw "Fixture executable bit was not set on POSIX host." }
            if (-not (Get-ExecutableFlag -File (Get-Item -LiteralPath $targetExec))) { throw "Managed copy did not preserve POSIX executable flag." }
            "POSIX executable flag was preserved as the normalized portable behavior."
        }
        else {
            "POSIX executable flag is not expressible on this host; regular-file bytes remain covered."
        }
    }

    Invoke-Case -Name "links-reparse-fail-closed" -Action {
        $linkPath = Join-Path (Get-SourcePath -Root $projectRoot) "alpha/link.txt"
        $targetPath = Join-Path (Get-SourcePath -Root $projectRoot) "alpha/SKILL.md"
        $created = New-SymbolicLinkFixture -LinkPath $linkPath -TargetPath $targetPath
        if (-not $created) { return "Host does not permit a temporary symbolic link; link safety remains platform-gated." }
        try {
            $adapterRoot = Get-AdapterRoot -Root $projectRoot
            if (Test-Path -LiteralPath $adapterRoot) { Remove-Item -LiteralPath $adapterRoot -Recurse -Force }
            $before = Get-TreeFingerprint -Root (Get-SourcePath -Root $projectRoot)
            $run = Invoke-Workspace -Operation "create-adapter" -ProjectRoot $projectRoot
            Assert-InvocationFailed -Invocation $run -Name "symbolic-link create-adapter"
            Assert-PathAbsent -Path $adapterRoot -Name "link-rejected adapter output"
            if ((Get-TreeFingerprint -Root (Get-SourcePath -Root $projectRoot)) -cne $before) { throw "Link rejection changed canonical source." }

            Remove-Item -LiteralPath $linkPath -Force -Recurse
            $clean = Invoke-Workspace -Operation "create-adapter" -ProjectRoot $projectRoot
            Assert-InvocationSuccess -Invocation $clean -Name "link safety clean create-adapter"
            $targetLink = Join-Path (Get-AdapterPath -Root $projectRoot -Name "alpha") "target-link.txt"
            $targetLinkCreated = New-SymbolicLinkFixture -LinkPath $targetLink -TargetPath $targetPath
            if (-not $targetLinkCreated) { throw "Host created a source link but not a target link." }
            try {
                $targetBefore = Get-TreeFingerprint -Root $adapterRoot
                $targetStatus = Invoke-Workspace -Operation "status-adapter" -ProjectRoot $projectRoot
                Assert-ReportedState -Invocation $targetStatus -Expected "unknown" -Name "target symbolic-link status"
                $targetRebuild = Invoke-Workspace -Operation "rebuild-adapter" -ProjectRoot $projectRoot
                Assert-InvocationFailed -Invocation $targetRebuild -Name "target symbolic-link rebuild"
                if ((Get-TreeFingerprint -Root $adapterRoot) -cne $targetBefore) { throw "Target link rejection changed adapter output." }
            }
            finally {
                if (Test-Path -LiteralPath $targetLink) { Remove-Item -LiteralPath $targetLink -Force -Recurse }
            }
        }
        finally {
            if (Test-Path -LiteralPath $linkPath) { Remove-Item -LiteralPath $linkPath -Force -Recurse }
        }
        "Symbolic-link/reparse payload is rejected before any adapter write."
    }
}
catch {
    Add-Case -Name "verifier-runtime" -Status "FAIL" -Detail (Get-SafeDetail -Message $_.Exception.Message)
}
finally {
    if (Test-Path -LiteralPath $runRoot) {
        Remove-Item -LiteralPath $runRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$failures = @($cases | Where-Object status -eq "FAIL")
$summary = [ordered]@{
    schema_version = 1
    status = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }
    scenario_count = $cases.Count
    pass = @($cases | Where-Object status -eq "PASS").Count
    fail = $failures.Count
    cross_platform_contract = $true
    cases = @($cases.ToArray())
}

if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 30
}
else {
    Write-Output ("Project workspace adapter checks: PASS={0} FAIL={1}" -f $summary.pass, $summary.fail)
    foreach ($case in @($summary.cases)) { Write-Output ("[{0}] {1}" -f $case.status, $case.name) }
}

if ($summary.status -ne "PASS") { exit 1 }
exit 0
