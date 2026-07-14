[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

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
    foreach ($marker in @("Project Context Gate: start", "Hot files (load now):", "Warm files (active work package):", "Cold files (discovery; open on demand):", "Git state:", "Project template status:")) {
        Assert-ContextGateCondition -Condition $text.Contains($marker) -Message "$Name text output is missing marker: $marker"
    }

    $jsonText = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json
    try { $payload = $jsonText | ConvertFrom-Json }
    catch { throw "$Name JSON output is invalid." }
    foreach ($propertyName in @("gate", "project_root", "files", "hot_files", "warm_files", "cold_files", "git", "project_template", "warnings")) {
        Assert-ContextGateCondition -Condition ($null -ne $payload.PSObject.Properties[$propertyName]) -Message "$Name JSON output is missing '$propertyName'."
    }
    foreach ($propertyName in @("status", "reason", "project_language", "guidance", "command", "command_reason", "helper")) {
        Assert-ContextGateCondition -Condition ($null -ne $payload.project_template.PSObject.Properties[$propertyName]) -Message "$Name project_template is missing '$propertyName'."
    }
    foreach ($propertyName in @("availability", "trust", "provenance")) {
        Assert-ContextGateCondition -Condition ($null -ne $payload.project_template.helper.PSObject.Properties[$propertyName]) -Message "$Name project_template.helper is missing '$propertyName'."
    }
    Assert-ContextGateCondition -Condition ([string]$payload.gate -eq "start") -Message "$Name JSON gate is not start."
    Assert-ContextGateCondition -Condition (@($payload.hot_files).Count -eq 4) -Message "$Name JSON hot inventory count is incorrect."
    Assert-ContextGateCondition -Condition (@($payload.warm_files).Count -eq 2) -Message "$Name JSON warm inventory count is incorrect."
    Assert-ContextGateCondition -Condition (@($payload.cold_files).Count -eq 2) -Message "$Name JSON cold inventory count is incorrect."
    Assert-ContextGateCondition -Condition ([string]$payload.git.state -eq "clean") -Message "$Name JSON git state is not clean."
    Assert-ContextGateCondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$payload.git.branch)) -Message "$Name JSON git branch is missing."
    Assert-ContextGateCondition -Condition (-not [string]::IsNullOrWhiteSpace([string]$payload.git.root)) -Message "$Name JSON git root is missing."

    $brief = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode brief
    foreach ($marker in @("Project Context Gate Brief", "Gate: start", "Project template status:", "Hot files (load now):", "Active work package files:", "Cold discovery-only files:", "Warnings / boundary notes:", "Next action:")) {
        Assert-ContextGateCondition -Condition $brief.Contains($marker) -Message "$Name brief output is missing marker: $marker"
    }

    return [ordered]@{
        layout = $Name
        modes = @("text", "json", "brief")
        hot_file_count = @($payload.hot_files).Count
        warm_file_count = @($payload.warm_files).Count
        cold_file_count = @($payload.cold_files).Count
        git_state = [string]$payload.git.state
        project_template_status = [string]$payload.project_template.status
    }
}

function New-ContextGateTestRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][string]$SourceSkillRoot,
        [Parameter(Mandatory = $true)][string]$StatusHelperFixture,
        [switch]$SkipGuidanceHelpers
    )

    $skillRoot = Join-ContextGatePath $RuntimeRoot "skills" "project-context-gate"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $skillRoot) | Out-Null
    Copy-Item -LiteralPath $SourceSkillRoot -Destination $skillRoot -Recurse
    $scriptsRoot = Join-ContextGatePath $RuntimeRoot "scripts"
    New-Item -ItemType Directory -Force -Path $scriptsRoot | Out-Null
    Copy-Item -LiteralPath $StatusHelperFixture -Destination (Join-Path $scriptsRoot "status.ps1")
    $libraryRoot = Join-ContextGatePath $scriptsRoot "lib"
    New-Item -ItemType Directory -Force -Path $libraryRoot | Out-Null
    foreach ($name in @("path-guard.ps1", "runtime-status-action.ps1")) {
        Set-Content -LiteralPath (Join-Path $libraryRoot $name) -Value "# managed provider dependency fixture" -Encoding UTF8
    }
    if (-not $SkipGuidanceHelpers.IsPresent) {
        foreach ($relativePath in @(
            "skills/project-bootstrap/scripts/bootstrap_project.ps1",
            "skills/project-bootstrap/scripts/memory_upgrade.ps1"
        )) {
            $helperPath = Join-ContextGatePath $RuntimeRoot $relativePath
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $helperPath) | Out-Null
            Set-Content -LiteralPath $helperPath -Value "throw 'Guidance helper must not be executed by context gate.'" -Encoding UTF8
        }
    }
    Write-ContextGateManagedProviderManifest -RuntimeRoot $RuntimeRoot
    return $skillRoot
}

function Write-ContextGateManagedProviderManifest {
    param([Parameter(Mandatory = $true)][string]$RuntimeRoot)

    $scriptsRoot = Join-ContextGatePath $RuntimeRoot "scripts"
    $records = @(
        foreach ($relativePath in @("lib/path-guard.ps1", "lib/runtime-status-action.ps1", "status.ps1")) {
            $providerPath = Join-ContextGatePath $scriptsRoot $relativePath
            $providerHash = (Get-FileHash -LiteralPath $providerPath -Algorithm SHA256).Hash.ToLowerInvariant()
            [ordered]@{ path = $relativePath; source_sha256 = $providerHash; installed_sha256 = $providerHash }
        }
    )
    [ordered]@{
        schema_version = 2
        items = @([ordered]@{
                name = "runtime-status-provider"
                source = "scripts"
                destination = "scripts"
                mode = "copy"
                managed = $true
                files = $records
            })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $RuntimeRoot "install-manifest.json") -Encoding UTF8
}

function Set-ContextGateStatusCase {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][object]$Case,
        [Parameter(Mandatory = $true)][string]$StatusHelperFixture
    )

    $statusScript = Join-ContextGatePath $RuntimeRoot "scripts" "status.ps1"
    if ([string]$Case.behavior -eq "missing") {
        if (Test-Path -LiteralPath $statusScript) { Remove-Item -LiteralPath $statusScript -Force }
    }
    else {
        Copy-Item -LiteralPath $StatusHelperFixture -Destination $statusScript -Force
        Write-ContextGateManagedProviderManifest -RuntimeRoot $RuntimeRoot
    }
    $Case | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-ContextGatePath $RuntimeRoot "scripts" "status-case.json") -Encoding UTF8
}

function New-ContextGateSkillLink {
    param(
        [Parameter(Mandatory = $true)][string]$LinkPath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LinkPath) | Out-Null
    $itemType = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) { "Junction" } else { "SymbolicLink" }
    New-Item -ItemType $itemType -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
}

function Test-UntrustedGuidanceAncestor {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$PowerShellPath,
        [Parameter(Mandatory = $true)][string]$StatusHelperFixture,
        [Parameter(Mandatory = $true)][object[]]$Cases,
        [Parameter(Mandatory = $true)][string]$ExternalRoot
    )

    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($case in $Cases) {
        Set-ContextGateStatusCase -RuntimeRoot $RuntimeRoot -Case $case -StatusHelperFixture $StatusHelperFixture
        foreach ($mode in @("json", "text", "brief")) {
            $output = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode $mode
            Assert-ContextGateCondition -Condition (-not $output.Contains($ExternalRoot)) -Message "$($case.name) $mode output leaked the external guidance path."
            Assert-ContextGateCondition -Condition (-not $output.Contains("CONTEXT_GATE_UNTRUSTED_GUIDANCE_SENTINEL")) -Message "$($case.name) $mode output leaked the untrusted guidance sentinel."
            if ($mode -eq "json") {
                $payload = $output | ConvertFrom-Json
                Assert-ContextGateCondition -Condition ([string]$payload.project_template.status -ceq [string]$case.expected_status) -Message "$($case.name) lost its validated project status."
                Assert-ContextGateCondition -Condition ($null -eq $payload.project_template.command) -Message "$($case.name) exposed a command through an untrusted ancestor link."
                Assert-ContextGateCondition -Condition ([string]$payload.project_template.command_reason -ceq "trusted-guidance-helper-unavailable") -Message "$($case.name) did not identify the untrusted guidance helper boundary."
            }
            else {
                Assert-ContextGateCondition -Condition $output.Contains("- suggested command: unavailable (trusted guidance helper not found)") -Message "$($case.name) $mode output did not explain that trusted guidance is unavailable."
            }
        }
        $results.Add([ordered]@{ name = [string]$case.name; status_preserved = $true; command = $false })
    }
    return @($results.ToArray())
}

function Test-ProjectTemplateCase {
    param(
        [Parameter(Mandatory = $true)][object]$Case,
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$PowerShellPath,
        [Parameter(Mandatory = $true)][string]$StatusHelperFixture,
        [switch]$CheckTextModes
    )

    Set-ContextGateStatusCase -RuntimeRoot $RuntimeRoot -Case $Case -StatusHelperFixture $StatusHelperFixture
    $jsonText = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json
    Assert-ContextGateCondition -Condition (-not $jsonText.Contains("CONTEXT_GATE_CONFIDENTIAL_SENTINEL")) -Message "$($Case.name) leaked a helper sentinel."
    try { $payload = $jsonText | ConvertFrom-Json }
    catch { throw "$($Case.name) context gate JSON output is invalid." }

    $template = $payload.project_template
    Assert-ContextGateCondition -Condition ([string]$template.status -ceq [string]$Case.expected_status) -Message "$($Case.name) returned unexpected status."
    Assert-ContextGateCondition -Condition ([string]$template.reason -ceq [string]$Case.expected_reason) -Message "$($Case.name) returned unexpected reason."
    Assert-ContextGateCondition -Condition ([string]$template.guidance -ceq [string]$Case.expected_guidance) -Message "$($Case.name) returned unexpected guidance."
    Assert-ContextGateCondition -Condition ([string]$template.helper.trust -ceq "trusted") -Message "$($Case.name) did not report a trusted helper root."
    $expectedProvenance = if ([string]$Case.behavior -ceq "missing") { "unresolved" } else { "manifest-managed-copy" }
    Assert-ContextGateCondition -Condition ([string]$template.helper.provenance -ceq $expectedProvenance) -Message "$($Case.name) did not report the expected helper provenance."
    $hasCommand = $null -ne $template.command -and -not [string]::IsNullOrWhiteSpace([string]$template.command)
    Assert-ContextGateCondition -Condition ($hasCommand -eq [bool]$Case.expects_command) -Message "$($Case.name) command presence is incorrect."
    if ($hasCommand) {
        Assert-ContextGateCondition -Condition ([string]$template.command_reason -ceq "available") -Message "$($Case.name) did not mark its trusted command available."
    }
    elseif ([string]$Case.name -eq "optional-null-language") {
        Assert-ContextGateCondition -Condition ([string]$template.command_reason -ceq "project-language-unavailable") -Message "$($Case.name) did not preserve the language-specific command reason."
    }
    else {
        Assert-ContextGateCondition -Condition ([string]$template.command_reason -ceq "not-applicable") -Message "$($Case.name) returned an unexpected command reason."
    }

    if ($hasCommand) {
        $command = [string]$template.command
        $commandTokens = $null
        $commandErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($command, [ref]$commandTokens, [ref]$commandErrors)
        Assert-ContextGateCondition -Condition (@($commandErrors).Count -eq 0) -Message "$($Case.name) guidance command is not valid PowerShell syntax."
        $quotedProject = "'{0}'" -f $ProjectRoot.Replace("'", "''")
        Assert-ContextGateCondition -Condition $command.Contains($quotedProject) -Message "$($Case.name) command does not safely quote the project path."
        if ([string]$Case.command_kind -eq "refresh") {
            $expectedHelper = Join-ContextGatePath $RuntimeRoot "skills" "project-bootstrap" "scripts" "bootstrap_project.ps1"
            Assert-ContextGateCondition -Condition ($command.Contains($expectedHelper) -and $command.Contains("-RefreshUnmodifiedTemplates") -and -not $command.Contains("-Mode Analyze")) -Message "$($Case.name) refresh command is incorrect."
        }
        if ([string]$Case.command_kind -eq "migration") {
            $expectedHelper = Join-ContextGatePath $RuntimeRoot "skills" "project-bootstrap" "scripts" "memory_upgrade.ps1"
            Assert-ContextGateCondition -Condition ($command.Contains($expectedHelper) -and $command.Contains("-Mode Analyze") -and $command.Contains("-Json") -and -not $command.Contains("bootstrap_project.ps1")) -Message "$($Case.name) migration command is incorrect."
        }
    }

    if ([string]$Case.expected_status -eq "current") {
        Assert-ContextGateCondition -Condition (@($payload.warnings | Where-Object { [string]$_ -like "PROJECT_TEMPLATE_*" }).Count -eq 0) -Message "$($Case.name) incorrectly emitted a project template warning."
    }
    elseif ([string]$Case.expected_status -eq "optional-refresh") {
        Assert-ContextGateCondition -Condition (@($payload.warnings | Where-Object { [string]$_ -like "PROJECT_TEMPLATE_OPTIONAL_REFRESH:*" }).Count -eq 1) -Message "$($Case.name) optional refresh warning is missing."
    }
    elseif ([string]$Case.expected_status -eq "migration-required") {
        Assert-ContextGateCondition -Condition (@($payload.warnings | Where-Object { [string]$_ -like "PROJECT_TEMPLATE_MIGRATION_REQUIRED:*" }).Count -eq 1) -Message "$($Case.name) migration warning is missing."
    }
    else {
        Assert-ContextGateCondition -Condition (@($payload.warnings | Where-Object { [string]$_ -like "PROJECT_TEMPLATE_UNKNOWN:*" }).Count -eq 1) -Message "$($Case.name) unknown warning is missing."
    }

    if ($CheckTextModes.IsPresent) {
        foreach ($mode in @("text", "brief")) {
            $modeText = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode $mode
            Assert-ContextGateCondition -Condition ($modeText.Contains("Project template status:") -and $modeText.Contains("- status: $([string]$Case.expected_status)")) -Message "$($Case.name) $mode output is missing stable project template status."
            Assert-ContextGateCondition -Condition (-not $modeText.Contains("CONTEXT_GATE_CONFIDENTIAL_SENTINEL")) -Message "$($Case.name) $mode output leaked a helper sentinel."
        }
    }
    return [ordered]@{ name = [string]$Case.name; status = [string]$template.status; reason = [string]$template.reason; command = $hasCommand }
}

$repositoryRootFull = [System.IO.Path]::GetFullPath($RepositoryRoot)
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-context-gate-checks-{0}" -f ([Guid]::NewGuid().ToString("N")))
}
$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
New-Item -ItemType Directory -Force -Path $scratchRootFull | Out-Null

$fixtureRoot = Join-ContextGatePath $repositoryRootFull "scripts" "validation" "project-context-gate-fixtures"
$fixturePath = Join-ContextGatePath $fixtureRoot "inventory-project.json"
$casesPath = Join-ContextGatePath $fixtureRoot "project-template-status-cases.json"
$statusHelperFixture = Join-ContextGatePath $fixtureRoot "status-helper.ps1"
$untrustedGuidanceFixture = Join-ContextGatePath $fixtureRoot "untrusted-guidance-helper.ps1"
$sourceSkillRoot = Join-ContextGatePath $repositoryRootFull "skills" "project-context-gate"
$projectRoot = Join-ContextGatePath $scratchRootFull "project with spaces"
New-ContextGateFixtureProject -FixturePath $fixturePath -ProjectRoot $projectRoot
$before = Get-ContextGateProjectSnapshot -ProjectRoot $projectRoot

$powerShellPath = Get-CurrentPowerShellExecutable
$caseFixture = Get-Content -LiteralPath $casesPath -Raw | ConvertFrom-Json
Assert-ContextGateCondition -Condition ([int]$caseFixture.schema_version -eq 1) -Message "Unsupported project template status fixture schema."
$currentCase = @($caseFixture.cases | Where-Object { [string]$_.name -eq "current" })[0]
$results = New-Object 'System.Collections.Generic.List[object]'
$sourceRuntime = $repositoryRootFull
$sourceScript = Join-ContextGatePath $sourceSkillRoot "scripts" "context_gate.ps1"
$results.Add((Test-ContextGateLayout -Name "source" -ScriptPath $sourceScript -ProjectRoot $projectRoot -PowerShellPath $powerShellPath))
$sourcePayload = (Invoke-ContextGateProcess -PowerShellPath $powerShellPath -ScriptPath $sourceScript -ProjectRoot $projectRoot -Mode json) | ConvertFrom-Json
Assert-ContextGateCondition -Condition ([string]$sourcePayload.project_template.helper.provenance -ceq "source-checkout") -Message "Real source checkout did not report source-checkout provenance."

$copyRuntime = Join-ContextGatePath $scratchRootFull "copy runtime"
$installedSkillRoot = New-ContextGateTestRuntime -RuntimeRoot $copyRuntime -SourceSkillRoot $sourceSkillRoot -StatusHelperFixture $statusHelperFixture
Set-ContextGateStatusCase -RuntimeRoot $copyRuntime -Case $currentCase -StatusHelperFixture $statusHelperFixture
$installedScript = Join-ContextGatePath $installedSkillRoot "scripts" "context_gate.ps1"
$results.Add((Test-ContextGateLayout -Name "copy-install" -ScriptPath $installedScript -ProjectRoot $projectRoot -PowerShellPath $powerShellPath))

$bridgeSkillRoot = Join-ContextGatePath $scratchRootFull "agent bridge" "skills" "project-context-gate"
New-ContextGateSkillLink -LinkPath $bridgeSkillRoot -TargetPath $installedSkillRoot
$bridgeScript = Join-ContextGatePath $bridgeSkillRoot "scripts" "context_gate.ps1"
$results.Add((Test-ContextGateLayout -Name "bridge" -ScriptPath $bridgeScript -ProjectRoot $projectRoot -PowerShellPath $powerShellPath))

$unresolvedScript = Join-ContextGatePath $scratchRootFull "unresolved layout" "context_gate.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $unresolvedScript) | Out-Null
Copy-Item -LiteralPath (Join-ContextGatePath $sourceSkillRoot "scripts" "context_gate.ps1") -Destination $unresolvedScript
$unresolvedText = Invoke-ContextGateProcess -PowerShellPath $powerShellPath -ScriptPath $unresolvedScript -ProjectRoot $projectRoot -Mode json
$unresolvedPayload = $unresolvedText | ConvertFrom-Json
Assert-ContextGateCondition -Condition (
    [string]$unresolvedPayload.project_template.status -ceq "unknown" -and
    [string]$unresolvedPayload.project_template.reason -ceq "trusted-runtime-root-unresolved" -and
    [string]$unresolvedPayload.project_template.helper.trust -ceq "unresolved" -and
    $null -eq $unresolvedPayload.project_template.command
) -Message "Unresolved locator did not fail soft without guidance commands."

$caseResults = New-Object 'System.Collections.Generic.List[object]'
foreach ($case in @($caseFixture.cases)) {
    $caseResults.Add((Test-ProjectTemplateCase -Case $case -RuntimeRoot $copyRuntime -ScriptPath $installedScript -ProjectRoot $projectRoot -PowerShellPath $powerShellPath -StatusHelperFixture $statusHelperFixture -CheckTextModes:([string]$case.name -in @("optional-zh", "migration-required", "payload-sentinel"))))
}

$untrustedRuntime = Join-ContextGatePath $scratchRootFull "runtime with untrusted guidance ancestor"
$untrustedSkillRoot = New-ContextGateTestRuntime -RuntimeRoot $untrustedRuntime -SourceSkillRoot $sourceSkillRoot -StatusHelperFixture $statusHelperFixture -SkipGuidanceHelpers
$untrustedScript = Join-ContextGatePath $untrustedSkillRoot "scripts" "context_gate.ps1"
$externalGuidanceRoot = Join-ContextGatePath $scratchRootFull "external guidance payload"
$externalGuidanceScripts = Join-ContextGatePath $externalGuidanceRoot "scripts"
New-Item -ItemType Directory -Force -Path $externalGuidanceScripts | Out-Null
Copy-Item -LiteralPath $untrustedGuidanceFixture -Destination (Join-Path $externalGuidanceScripts "bootstrap_project.ps1")
Copy-Item -LiteralPath $untrustedGuidanceFixture -Destination (Join-Path $externalGuidanceScripts "memory_upgrade.ps1")
New-ContextGateSkillLink -LinkPath (Join-ContextGatePath $untrustedRuntime "skills" "project-bootstrap") -TargetPath $externalGuidanceRoot
$untrustedCases = @($caseFixture.cases | Where-Object { [string]$_.name -in @("optional-zh", "migration-required") })
$untrustedGuidanceResults = @(Test-UntrustedGuidanceAncestor -RuntimeRoot $untrustedRuntime -ScriptPath $untrustedScript -ProjectRoot $projectRoot -PowerShellPath $powerShellPath -StatusHelperFixture $statusHelperFixture -Cases $untrustedCases -ExternalRoot $externalGuidanceRoot)
Assert-ContextGateCondition -Condition ($untrustedGuidanceResults.Count -eq 2) -Message "Untrusted guidance ancestor coverage is incomplete."

$tamperedRuntime = Join-ContextGatePath $scratchRootFull "runtime with tampered managed provider"
$tamperedSkillRoot = New-ContextGateTestRuntime -RuntimeRoot $tamperedRuntime -SourceSkillRoot $sourceSkillRoot -StatusHelperFixture $statusHelperFixture
$tamperedScriptsRoot = Join-ContextGatePath $tamperedRuntime "scripts"
$tamperedLibraryRoot = Join-ContextGatePath $tamperedScriptsRoot "lib"
New-Item -ItemType Directory -Force -Path $tamperedLibraryRoot | Out-Null
foreach ($name in @("path-guard.ps1", "runtime-status-action.ps1")) {
    Set-Content -LiteralPath (Join-Path $tamperedLibraryRoot $name) -Value "# managed provider dependency fixture" -Encoding UTF8
}
$providerRecords = @(
    foreach ($relativePath in @("lib/path-guard.ps1", "lib/runtime-status-action.ps1", "status.ps1")) {
        $providerPath = Join-ContextGatePath $tamperedScriptsRoot $relativePath
        $providerHash = (Get-FileHash -LiteralPath $providerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        [ordered]@{ path = $relativePath; source_sha256 = $providerHash; installed_sha256 = $providerHash }
    }
)
$tamperedManifest = [ordered]@{
    schema_version = 2
    items = @([ordered]@{
            name = "runtime-status-provider"
            source = "scripts"
            destination = "scripts"
            mode = "copy"
            managed = $true
            files = $providerRecords
        })
}
$tamperedManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tamperedRuntime "install-manifest.json") -Encoding UTF8
$tamperMarker = Join-ContextGatePath $tamperedRuntime "TAMPERED_STATUS_EXECUTED"
$tamperedStatus = Join-ContextGatePath $tamperedScriptsRoot "status.ps1"
Set-Content -LiteralPath $tamperedStatus -Value ("Set-Content -LiteralPath '{0}' -Value executed`n'{{}}'" -f $tamperMarker.Replace("'", "''")) -Encoding UTF8
$tamperedPayload = (Invoke-ContextGateProcess -PowerShellPath $powerShellPath -ScriptPath (Join-ContextGatePath $tamperedSkillRoot "scripts" "context_gate.ps1") -ProjectRoot $projectRoot -Mode json) | ConvertFrom-Json
Assert-ContextGateCondition -Condition (
    [string]$tamperedPayload.project_template.status -ceq "unknown" -and
    [string]$tamperedPayload.project_template.reason -ceq "status-helper-missing" -and
    [string]$tamperedPayload.project_template.helper.availability -ceq "unavailable" -and
    [string]$tamperedPayload.project_template.helper.provenance -ceq "unresolved" -and
    -not (Test-Path -LiteralPath $tamperMarker)
) -Message "Context gate executed or trusted a tampered manifest-managed status provider."

$malformedManifestRuntime = Join-ContextGatePath $scratchRootFull "runtime with malformed manifest"
$malformedManifestSkillRoot = New-ContextGateTestRuntime -RuntimeRoot $malformedManifestRuntime -SourceSkillRoot $sourceSkillRoot -StatusHelperFixture $statusHelperFixture
$malformedManifestMarker = Join-ContextGatePath $malformedManifestRuntime "MALFORMED_MANIFEST_PROVIDER_EXECUTED"
$malformedManifestStatus = Join-ContextGatePath $malformedManifestRuntime "scripts" "status.ps1"
Set-Content -LiteralPath $malformedManifestStatus -Value ("Set-Content -LiteralPath '{0}' -Value executed`n'{{}}'" -f $malformedManifestMarker.Replace("'", "''")) -Encoding UTF8
Set-Content -LiteralPath (Join-Path $malformedManifestRuntime "install-manifest.json") -Value '{"schema_version":' -Encoding UTF8
$malformedManifestPayload = (Invoke-ContextGateProcess -PowerShellPath $powerShellPath -ScriptPath (Join-ContextGatePath $malformedManifestSkillRoot "scripts" "context_gate.ps1") -ProjectRoot $projectRoot -Mode json) | ConvertFrom-Json
Assert-ContextGateCondition -Condition (
    [string]$malformedManifestPayload.project_template.status -ceq "unknown" -and
    [string]$malformedManifestPayload.project_template.reason -ceq "status-helper-missing" -and
    [string]$malformedManifestPayload.project_template.helper.availability -ceq "unavailable" -and
    [string]$malformedManifestPayload.project_template.helper.provenance -ceq "unresolved" -and
    -not (Test-Path -LiteralPath $malformedManifestMarker)
) -Message "Context gate executed a provider or failed hard when the install manifest was malformed."

$unreadableProviderRuntime = Join-ContextGatePath $scratchRootFull "runtime with unreadable provider"
$unreadableProviderSkillRoot = New-ContextGateTestRuntime -RuntimeRoot $unreadableProviderRuntime -SourceSkillRoot $sourceSkillRoot -StatusHelperFixture $statusHelperFixture
$unreadableProviderPath = Join-ContextGatePath $unreadableProviderRuntime "scripts" "lib" "path-guard.ps1"
$providerLock = [System.IO.File]::Open($unreadableProviderPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
try {
    $unreadableProviderPayload = (Invoke-ContextGateProcess -PowerShellPath $powerShellPath -ScriptPath (Join-ContextGatePath $unreadableProviderSkillRoot "scripts" "context_gate.ps1") -ProjectRoot $projectRoot -Mode json) | ConvertFrom-Json
} finally {
    $providerLock.Dispose()
}
Assert-ContextGateCondition -Condition (
    [string]$unreadableProviderPayload.project_template.status -ceq "unknown" -and
    [string]$unreadableProviderPayload.project_template.reason -ceq "status-helper-missing" -and
    [string]$unreadableProviderPayload.project_template.helper.availability -ceq "unavailable" -and
    [string]$unreadableProviderPayload.project_template.helper.provenance -ceq "unresolved"
) -Message "Context gate failed hard or resolved provenance while a managed provider file was unreadable during hashing."

Assert-ContextGateCondition -Condition (-not (Test-Path -LiteralPath (Join-ContextGatePath $projectRoot "MALICIOUS_STATUS_EXECUTED"))) -Message "Context gate executed the target project's malicious scripts/status.ps1."

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
    project_template_cases = @($caseResults.ToArray())
    project_template_case_count = $caseResults.Count
    untrusted_guidance_ancestor_cases = $untrustedGuidanceResults
    untrusted_guidance_ancestor_case_count = $untrustedGuidanceResults.Count
    unresolved_locator_fail_soft = $true
    malicious_project_helper_ignored = $true
    malformed_manifest_rejected = $true
    tampered_managed_provider_rejected = $true
    unreadable_managed_provider_fail_soft = $true
    project_read_only = $true
}
if ($Json.IsPresent) { $result | ConvertTo-Json -Depth 8 }
else { Write-Output ("project-context-gate checks: PASS ({0} layouts; {1} project template cases; read-only)" -f $results.Count, $caseResults.Count) }
