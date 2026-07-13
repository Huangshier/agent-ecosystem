[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Join-ContextGatePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Children
    )

    $path = $Root
    foreach ($child in $Children) {
        foreach ($segment in @($child -split '[\\/]+')) {
            if (-not [string]::IsNullOrWhiteSpace($segment)) {
                $path = Join-Path $path $segment
            }
        }
    }
    return $path
}

function Assert-ContextGateCondition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-CurrentPowerShellExecutable {
    $processPath = (Get-Process -Id $PID).Path
    if ([string]::IsNullOrWhiteSpace($processPath) -or -not (Test-Path -LiteralPath $processPath -PathType Leaf)) {
        throw "Unable to resolve the current PowerShell executable."
    }
    return $processPath
}

function Invoke-ContextGateProcess {
    param(
        [Parameter(Mandatory = $true)][string]$PowerShellPath,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [ValidateSet("text", "json", "brief")][string]$Mode
    )

    $arguments = New-Object 'System.Collections.Generic.List[string]'
    $arguments.Add("-NoProfile")
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT -and
        [System.IO.Path]::GetFileName($PowerShellPath) -ieq "powershell.exe") {
        $arguments.Add("-ExecutionPolicy")
        $arguments.Add("Bypass")
    }
    $arguments.Add("-File")
    $arguments.Add($ScriptPath)
    $arguments.Add("-ProjectRoot")
    $arguments.Add($ProjectRoot)
    if ($Mode -eq "json") { $arguments.Add("-Json") }
    if ($Mode -eq "brief") { $arguments.Add("-Brief") }

    $global:LASTEXITCODE = 0
    $output = @(& $PowerShellPath @($arguments.ToArray()) 2>&1)
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($exitCode -ne 0) {
        throw "Context gate $Mode invocation failed with exit code $exitCode."
    }
    return ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
}

function Get-ContextGateProjectSnapshot {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $files = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force | Where-Object {
                $_.FullName -notmatch '[\\/]\.git([\\/]|$)'
            } | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($ProjectRoot.TrimEnd('\', '/').Length).TrimStart([char[]]"\/") -replace '\\', '/'
        $files.Add([ordered]@{
            path = $relative
            length = [int64]$file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    }
    $gitStatus = @(& git -C $ProjectRoot status --short 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Unable to read fixture project git status." }
    $global:LASTEXITCODE = 0
    return [ordered]@{
        files = @($files.ToArray())
        git_status = @($gitStatus)
    }
}

function New-ContextGateFixtureProject {
    param(
        [Parameter(Mandatory = $true)][string]$FixturePath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    $fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
    Assert-ContextGateCondition -Condition ([int]$fixture.schema_version -eq 1) -Message "Unsupported context gate fixture schema."
    New-Item -ItemType Directory -Force -Path $ProjectRoot | Out-Null
    foreach ($record in @($fixture.files)) {
        $target = Join-ContextGatePath $ProjectRoot ([string]$record.path)
        $parent = Split-Path -Parent $target
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        Set-Content -LiteralPath $target -Value ([string]$record.content) -Encoding UTF8
    }

    & git -C $ProjectRoot init --quiet
    if ($LASTEXITCODE -ne 0) { throw "Unable to initialize fixture git repository." }
    & git -C $ProjectRoot config core.autocrlf false
    if ($LASTEXITCODE -ne 0) { throw "Unable to configure fixture git repository." }
    & git -C $ProjectRoot add --all
    if ($LASTEXITCODE -ne 0) { throw "Unable to stage fixture project." }
    & git -C $ProjectRoot -c user.name=context-gate-fixture -c user.email=context-gate-fixture@example.invalid commit --quiet -m "fixture baseline"
    if ($LASTEXITCODE -ne 0) { throw "Unable to commit fixture project baseline." }
    $global:LASTEXITCODE = 0
}

function Test-ContextGateLayout {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$PowerShellPath
    )

    Assert-ContextGateCondition -Condition (Test-Path -LiteralPath $ScriptPath -PathType Leaf) -Message "Context gate script is missing for $Name layout."
    $text = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode text
    foreach ($marker in @("Project Context Gate: start", "Hot files (load now):", "Warm files (active work package):", "Cold files (discovery; open on demand):", "Git state:")) {
        Assert-ContextGateCondition -Condition $text.Contains($marker) -Message "$Name text output is missing marker: $marker"
    }

    $jsonText = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json
    try { $payload = $jsonText | ConvertFrom-Json }
    catch { throw "$Name JSON output is invalid." }
    foreach ($propertyName in @("gate", "project_root", "files", "hot_files", "warm_files", "cold_files", "git", "warnings")) {
        Assert-ContextGateCondition -Condition ($null -ne $payload.PSObject.Properties[$propertyName]) -Message "$Name JSON output is missing '$propertyName'."
    }
    Assert-ContextGateCondition -Condition ([string]$payload.gate -eq "start") -Message "$Name JSON gate is not start."
    Assert-ContextGateCondition -Condition (@($payload.hot_files).Count -eq 4) -Message "$Name JSON hot inventory count is incorrect."
    Assert-ContextGateCondition -Condition (@($payload.warm_files).Count -eq 2) -Message "$Name JSON warm inventory count is incorrect."
    Assert-ContextGateCondition -Condition (@($payload.cold_files).Count -eq 2) -Message "$Name JSON cold inventory count is incorrect."
    Assert-ContextGateCondition -Condition ([string]$payload.git.state -eq "clean") -Message "$Name JSON git state is not clean."
    Assert-ContextGateCondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$payload.git.branch)) -Message "$Name JSON git branch is missing."
    Assert-ContextGateCondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$payload.git.root)) -Message "$Name JSON git root is missing."

    $brief = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode brief
    foreach ($marker in @("Project Context Gate Brief", "Gate: start", "Hot files (load now):", "Active work package files:", "Cold discovery-only files:", "Warnings / boundary notes:", "Next action:")) {
        Assert-ContextGateCondition -Condition $brief.Contains($marker) -Message "$Name brief output is missing marker: $marker"
    }

    return [ordered]@{
        layout = $Name
        modes = @("text", "json", "brief")
        hot_file_count = @($payload.hot_files).Count
        warm_file_count = @($payload.warm_files).Count
        cold_file_count = @($payload.cold_files).Count
        git_state = [string]$payload.git.state
    }
}

$repositoryRootFull = [System.IO.Path]::GetFullPath($RepositoryRoot)
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-context-gate-checks-{0}" -f ([Guid]::NewGuid().ToString("N")))
}
$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null

$fixturePath = Join-ContextGatePath $repositoryRootFull "scripts" "validation" "project-context-gate-fixtures" "inventory-project.json"
$sourceSkillRoot = Join-ContextGatePath $repositoryRootFull "skills" "project-context-gate"
$sourceScript = Join-ContextGatePath $sourceSkillRoot "scripts" "context_gate.ps1"
$projectRoot = Join-ContextGatePath $scratchRootFull "project"
New-ContextGateFixtureProject -FixturePath $fixturePath -ProjectRoot $projectRoot
$before = Get-ContextGateProjectSnapshot -ProjectRoot $projectRoot

$powerShellPath = Get-CurrentPowerShellExecutable
$results = New-Object 'System.Collections.Generic.List[object]'
$results.Add((Test-ContextGateLayout -Name "source" -ScriptPath $sourceScript -ProjectRoot $projectRoot -PowerShellPath $powerShellPath))

$installedSkillRoot = Join-ContextGatePath $scratchRootFull "runtime" "skills" "project-context-gate"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $installedSkillRoot) | Out-Null
Copy-Item -LiteralPath $sourceSkillRoot -Destination $installedSkillRoot -Recurse
$installedScript = Join-ContextGatePath $installedSkillRoot "scripts" "context_gate.ps1"
$results.Add((Test-ContextGateLayout -Name "copy-install" -ScriptPath $installedScript -ProjectRoot $projectRoot -PowerShellPath $powerShellPath))

$after = Get-ContextGateProjectSnapshot -ProjectRoot $projectRoot
$beforeJson = $before | ConvertTo-Json -Depth 6 -Compress
$afterJson = $after | ConvertTo-Json -Depth 6 -Compress
Assert-ContextGateCondition -Condition ($beforeJson -ceq $afterJson) -Message "Context gate changed fixture project files or git status."

$result = [ordered]@{
    schema_version = 1
    status = "PASS"
    powershell = [System.IO.Path]::GetFileName($powerShellPath)
    scenarios = @($results.ToArray())
    scenario_count = $results.Count
    project_read_only = $true
}
if ($Json.IsPresent) { $result | ConvertTo-Json -Depth 8 }
else { Write-Output ("project-context-gate checks: PASS ({0} layouts; read-only)" -f $results.Count) }
