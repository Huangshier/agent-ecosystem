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
        [ValidateSet("text", "json", "brief")][string]$Mode,
        [string]$Query = ""
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
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $arguments.Add("-Query")
        $arguments.Add($Query)
    }

    $global:LASTEXITCODE = 0
    $output = @(& $PowerShellPath @($arguments.ToArray()) 2>&1)
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($exitCode -ne 0) {
        $debugLines = ($output | Select-Object -First 5 | ForEach-Object { [string]$_ }) -join " | "
        throw "Context gate $Mode invocation failed with exit code $exitCode. Output: $debugLines"
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

function Test-QueryMatching {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$PowerShellPath
    )

    $results = New-Object 'System.Collections.Generic.List[object]'

    # 场景 1：无 Query 时不新增 query/matched 字段
    $noQueryJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json
    $noQueryPayload = $noQueryJson | ConvertFrom-Json
    Assert-ContextGateCondition -Condition ($null -eq $noQueryPayload.PSObject.Properties["query"]) -Message "No-Query mode must not add a query field."
    Assert-ContextGateCondition -Condition ($null -eq $noQueryPayload.PSObject.Properties["matched_context_entries"]) -Message "No-Query mode must not add matched_context_entries."
    Assert-ContextGateCondition -Condition ($null -eq $noQueryPayload.PSObject.Properties["match_status"]) -Message "No-Query mode must not add match_status."
    Assert-ContextGateCondition -Condition (-not $noQueryJson.Contains("loaded")) -Message "No-Query JSON must not contain loaded claims."
    Assert-ContextGateCondition -Condition (-not $noQueryJson.Contains("applied")) -Message "No-Query JSON must not contain applied claims."
    Assert-ContextGateCondition -Condition (-not $noQueryJson.Contains("authorized")) -Message "No-Query JSON must not contain authorized claims."
    $results.Add([ordered]@{ name = "no-query-compat"; pass = $true })

    # 场景 2：README Entry Index 的 Summary 命中
    $summaryJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "baud rate calibration"
    $summaryPayload = $summaryJson | ConvertFrom-Json
    Assert-ContextGateCondition -Condition ([string]$summaryPayload.match_status -ceq "matched") -Message "Index Summary match should return matched status."
    $gammaHits = @($summaryPayload.matched_context_entries | Where-Object { [string]$_.path -eq ".agents/context/gamma-case.md" })
    Assert-ContextGateCondition -Condition ($gammaHits.Count -eq 1) -Message "Index Summary should match gamma-case.md."
    Assert-ContextGateCondition -Condition (@($gammaHits[0].matched_terms) -contains "baud") -Message "gamma-case should match term baud."
    $results.Add([ordered]@{ name = "index-summary-hit"; pass = $true })

    # 场景 3：README Entry Index 的 Keywords 命中
    $kwJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "CubeMX"
    $kwPayload = $kwJson | ConvertFrom-Json
    $alphaHits = @($kwPayload.matched_context_entries | Where-Object { [string]$_.path -eq ".agents/context/alpha-case.md" })
    Assert-ContextGateCondition -Condition ($alphaHits.Count -eq 1) -Message "Index Keywords should match alpha-case.md for CubeMX."
    Assert-ContextGateCondition -Condition (@($alphaHits[0].matched_fields) -contains "keywords") -Message "alpha-case CubeMX hit should include keywords field."
    $results.Add([ordered]@{ name = "index-keywords-hit"; pass = $true })

    # 场景 4：entry 前部 Summary 命中
    $entrySumJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "sleep mode"
    $entrySumPayload = $entrySumJson | ConvertFrom-Json
    $deltaHits = @($entrySumPayload.matched_context_entries | Where-Object { [string]$_.path -eq ".agents/context/delta-case.md" })
    Assert-ContextGateCondition -Condition ($deltaHits.Count -eq 1) -Message "Entry Summary should match delta-case.md for sleep."
    Assert-ContextGateCondition -Condition (@($deltaHits[0].matched_fields) -contains "summary") -Message "delta-case sleep hit should include summary field."
    $results.Add([ordered]@{ name = "entry-summary-hit"; pass = $true })

    # 场景 5：entry 前部 Keywords 命中
    $entryKwJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "PWR"
    $entryKwPayload = $entryKwJson | ConvertFrom-Json
    $deltaKwHits = @($entryKwPayload.matched_context_entries | Where-Object { [string]$_.path -eq ".agents/context/delta-case.md" })
    Assert-ContextGateCondition -Condition ($deltaKwHits.Count -eq 1) -Message "Entry Keywords should match delta-case.md for PWR."
    Assert-ContextGateCondition -Condition (@($deltaKwHits[0].matched_fields) -contains "keywords") -Message "delta-case PWR hit should include keywords field."
    $results.Add([ordered]@{ name = "entry-keywords-hit"; pass = $true })

    # 场景 6：同一 entry 由 index 和 entry metadata 同时命中时去重合并
    $mergeJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "SPI DMA"
    $mergePayload = $mergeJson | ConvertFrom-Json
    $alphaMerge = @($mergePayload.matched_context_entries | Where-Object { [string]$_.path -eq ".agents/context/alpha-case.md" })
    Assert-ContextGateCondition -Condition ($alphaMerge.Count -eq 1) -Message "alpha-case must appear exactly once when hit by both index and entry metadata."
    Assert-ContextGateCondition -Condition (@($alphaMerge[0].matched_terms) -contains "SPI") -Message "Merged alpha-case must include SPI."
    Assert-ContextGateCondition -Condition (@($alphaMerge[0].matched_terms) -contains "DMA") -Message "Merged alpha-case must include DMA."
    $results.Add([ordered]@{ name = "dedup-merge"; pass = $true })

    # 场景 7：Query term 只存在于正文时不得命中
    $bodyOnlyJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "interrupt GPIO"
    $bodyOnlyPayload = $bodyOnlyJson | ConvertFrom-Json
    # alpha-case 正文包含 interrupt 和 GPIO，但 metadata 不包含
    $alphaBodyHits = @($bodyOnlyPayload.matched_context_entries | Where-Object { [string]$_.path -eq ".agents/context/alpha-case.md" })
    Assert-ContextGateCondition -Condition ($alphaBodyHits.Count -eq 0) -Message "alpha-case must NOT match terms that only appear in its body."
    # beta-case 的 metadata 包含 EXTI, interrupt, GPIO
    $betaBodyHits = @($bodyOnlyPayload.matched_context_entries | Where-Object { [string]$_.path -eq ".agents/context/beta-case.md" })
    Assert-ContextGateCondition -Condition ($betaBodyHits.Count -eq 1) -Message "beta-case should match interrupt/GPIO from its metadata."
    $results.Add([ordered]@{ name = "body-only-no-match"; pass = $true })

    # 场景 8：metadata 不完整时使用现有字段继续匹配
    $incompleteJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "UART"
    $incompletePayload = $incompleteJson | ConvertFrom-Json
    $gammaIncomplete = @($incompletePayload.matched_context_entries | Where-Object { [string]$_.path -eq ".agents/context/gamma-case.md" })
    Assert-ContextGateCondition -Condition ($gammaIncomplete.Count -eq 1) -Message "gamma-case with incomplete metadata should still match via Keywords."
    Assert-ContextGateCondition -Condition (@($gammaIncomplete[0].matched_fields) -contains "keywords") -Message "gamma-case incomplete metadata should report keywords field."
    $results.Add([ordered]@{ name = "incomplete-metadata"; pass = $true })

    # 场景 9：无匹配
    $noMatchJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "zzzznonexistent"
    $noMatchPayload = $noMatchJson | ConvertFrom-Json
    Assert-ContextGateCondition -Condition ([string]$noMatchPayload.match_status -ceq "no-match") -Message "Non-matching query should return no-match status."
    Assert-ContextGateCondition -Condition (@($noMatchPayload.matched_context_entries).Count -eq 0) -Message "Non-matching query should return empty entries."
    Assert-ContextGateCondition -Condition (@($noMatchPayload.match_reason_codes) -contains "no-matches") -Message "Non-matching query should include no-matches reason."
    $results.Add([ordered]@{ name = "no-match"; pass = $true })

    # 场景 10：不安全 index path 被忽略
    $unsafeJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "escape unsafe absolute"
    $unsafePayload = $unsafeJson | ConvertFrom-Json
    $escapeHits = @($unsafePayload.matched_context_entries | Where-Object { [string]$_.path -like "*escape*" -or [string]$_.path -like "*evil*" })
    Assert-ContextGateCondition -Condition ($escapeHits.Count -eq 0) -Message "Unsafe index paths must not produce matches."
    Assert-ContextGateCondition -Condition (@($unsafePayload.match_reason_codes) -contains "unsafe-index-path-ignored") -Message "Unsafe paths should produce unsafe-index-path-ignored reason."
    $results.Add([ordered]@{ name = "unsafe-path-ignored"; pass = $true })

    # 场景 11：多条目、大小写和名称顺序产生稳定结果
    $orderJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "cubemx extI"
    $orderPayload = $orderJson | ConvertFrom-Json
    $paths = @($orderPayload.matched_context_entries | ForEach-Object { [string]$_.path })
    Assert-ContextGateCondition -Condition ($paths.Count -ge 2) -Message "Multi-term query should match multiple entries."
    # 验证 ordinal 排序：alpha < beta
    $alphaIdx = [array]::IndexOf($paths, ".agents/context/alpha-case.md")
    $betaIdx = [array]::IndexOf($paths, ".agents/context/beta-case.md")
    if ($alphaIdx -ge 0 -and $betaIdx -ge 0) {
        Assert-ContextGateCondition -Condition ($alphaIdx -lt $betaIdx) -Message "Ordinal sort must place alpha before beta."
    }
    # 验证大小写不敏感匹配但保留首次写法
    $alphaOrder = @($orderPayload.matched_context_entries | Where-Object { [string]$_.path -eq ".agents/context/alpha-case.md" })
    if ($alphaOrder.Count -eq 1) {
        Assert-ContextGateCondition -Condition (@($alphaOrder[0].matched_terms) -contains "cubemx") -Message "Case-insensitive match must preserve original query casing."
    }
    $results.Add([ordered]@{ name = "deterministic-order"; pass = $true })

    # 场景 12：text、JSON、Brief 均不出现 loaded、applied 或 authorized 的错误声明
    $jsonModeOutput = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "CubeMX SPI"
    $jsonLower = $jsonModeOutput.ToLowerInvariant()
    Assert-ContextGateCondition -Condition (-not $jsonLower.Contains("loaded")) -Message "JSON output must not contain loaded claims."
    Assert-ContextGateCondition -Condition (-not $jsonLower.Contains("applied")) -Message "JSON output must not contain applied claims."
    Assert-ContextGateCondition -Condition (-not $jsonLower.Contains("authorized")) -Message "JSON output must not contain authorized claims."
    foreach ($mode in @("text", "brief")) {
        $modeOutput = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode $mode -Query "CubeMX SPI"
        # 移除已知免责声明行和 section header 后检查
        $withoutDisclaimer = ($modeOutput -split "`n" | Where-Object {
            -not $_.Contains("Matched entries are metadata hits only") -and
            -not $_.Contains("Context metadata matches (matched, not loaded)")
        }) -join "`n"
        $lowerStripped = $withoutDisclaimer.ToLowerInvariant()
        Assert-ContextGateCondition -Condition (-not $lowerStripped.Contains("loaded")) -Message "$mode output must not claim entries are loaded outside the disclaimer."
        Assert-ContextGateCondition -Condition (-not $lowerStripped.Contains("applied")) -Message "$mode output must not claim entries are applied outside the disclaimer."
        Assert-ContextGateCondition -Condition (-not $lowerStripped.Contains("authorized")) -Message "$mode output must not claim entries are authorized outside the disclaimer."
    }
    $results.Add([ordered]@{ name = "no-false-claims"; pass = $true })

    # 场景 13：text 和 Brief 包含 matched, not loaded 区域
    $textOutput = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode text -Query "CubeMX"
    Assert-ContextGateCondition -Condition $textOutput.Contains("Context metadata matches (matched, not loaded):") -Message "Text output must include matched section header."
    Assert-ContextGateCondition -Condition $textOutput.Contains("Matched entries are metadata hits only") -Message "Text output must include disclaimer."
    $briefOutput = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode brief -Query "CubeMX"
    Assert-ContextGateCondition -Condition $briefOutput.Contains("Context metadata matches (matched, not loaded):") -Message "Brief output must include matched section header."
    Assert-ContextGateCondition -Condition $briefOutput.Contains("Matched entries are metadata hits only") -Message "Brief output must include disclaimer."
    $results.Add([ordered]@{ name = "text-brief-matched-section"; pass = $true })

    # 场景 14：metadata 不完整时返回 context-metadata-incomplete
    $incJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "UART"
    $incPayload = $incJson | ConvertFrom-Json
    Assert-ContextGateCondition -Condition (@($incPayload.match_reason_codes) -contains "context-metadata-incomplete") -Message "gamma-case (Keywords only) should trigger context-metadata-incomplete."
    Assert-ContextGateCondition -Condition (@($incPayload.matched_context_entries).Count -ge 1) -Message "Incomplete metadata entry should still match."
    $results.Add([ordered]@{ name = "metadata-incomplete-reason"; pass = $true })

    # 场景 15：多个相同异常只输出一个 reason（去重）
    $dedupJson = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "SPI UART PWR CubeMX"
    $dedupPayload = $dedupJson | ConvertFrom-Json
    $incompleteCount = @($dedupPayload.match_reason_codes | Where-Object { [string]$_ -ceq "context-metadata-incomplete" }).Count
    Assert-ContextGateCondition -Condition ($incompleteCount -le 1) -Message "Duplicate reason codes must be deduplicated."
    $unsafeCount = @($dedupPayload.match_reason_codes | Where-Object { [string]$_ -ceq "unsafe-index-path-ignored" }).Count
    Assert-ContextGateCondition -Condition ($unsafeCount -le 1) -Message "Duplicate unsafe-index-path-ignored must be deduplicated."
    $results.Add([ordered]@{ name = "reason-dedup"; pass = $true })

    # 场景 16：reason code 顺序固定
    $orderJson2 = Invoke-ContextGateProcess -PowerShellPath $PowerShellPath -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query "SPI UART escape"
    $orderPayload2 = $orderJson2 | ConvertFrom-Json
    $codes = @($orderPayload2.match_reason_codes)
    $canonicalOrder = @("context-directory-missing", "context-enumeration-failed", "context-index-missing", "context-metadata-incomplete", "unsafe-context-path-ignored", "unsafe-index-path-ignored", "unknown-json-index-schema", "json-index-parse-failed", "no-matches")
    $lastIdx = -1
    $orderValid = $true
    foreach ($code in $codes) {
        $idx = [array]::IndexOf($canonicalOrder, [string]$code)
        if ($idx -le $lastIdx) { $orderValid = $false; break }
        $lastIdx = $idx
    }
    Assert-ContextGateCondition -Condition $orderValid -Message "Reason codes must follow canonical fixed order."
    $results.Add([ordered]@{ name = "reason-fixed-order"; pass = $true })

    return @($results.ToArray())
}

function Test-QueryMatchingCrossVersion {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$PS7Path,
        [Parameter(Mandatory = $true)][string]$PS51Path
    )

    $query = "CubeMX SPI DMA EXTI"
    $ps7Json = Invoke-ContextGateProcess -PowerShellPath $PS7Path -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query $query
    $ps51Json = Invoke-ContextGateProcess -PowerShellPath $PS51Path -ScriptPath $ScriptPath -ProjectRoot $ProjectRoot -Mode json -Query $query

    $ps7Payload = $ps7Json | ConvertFrom-Json
    $ps51Payload = $ps51Json | ConvertFrom-Json

    # 比较 paths
    $ps7Paths = @($ps7Payload.matched_context_entries | ForEach-Object { [string]$_.path })
    $ps51Paths = @($ps51Payload.matched_context_entries | ForEach-Object { [string]$_.path })
    Assert-ContextGateCondition -Condition (($ps7Paths -join "`n") -ceq ($ps51Paths -join "`n")) -Message "PS7 and PS5.1 must produce identical result paths in identical order."

    # 比较 matched_fields 和 matched_terms
    for ($i = 0; $i -lt $ps7Paths.Count; $i++) {
        $ps7Entry = $ps7Payload.matched_context_entries[$i]
        $ps51Entry = $ps51Payload.matched_context_entries[$i]
        Assert-ContextGateCondition -Condition ((@($ps7Entry.matched_fields) -join ",") -ceq (@($ps51Entry.matched_fields) -join ",")) -Message "PS7/PS5.1 matched_fields differ for $($ps7Paths[$i])."
        Assert-ContextGateCondition -Condition ((@($ps7Entry.matched_terms) -join ",") -ceq (@($ps51Entry.matched_terms) -join ",")) -Message "PS7/PS5.1 matched_terms differ for $($ps7Paths[$i])."
    }

    # 比较 status 和 reason_codes
    Assert-ContextGateCondition -Condition ([string]$ps7Payload.match_status -ceq [string]$ps51Payload.match_status) -Message "PS7/PS5.1 match_status differs."
    Assert-ContextGateCondition -Condition ((@($ps7Payload.match_reason_codes) -join ",") -ceq (@($ps51Payload.match_reason_codes) -join ",")) -Message "PS7/PS5.1 reason_codes differ."

    return [ordered]@{
        ps7_path = [System.IO.Path]::GetFileName($PS7Path)
        ps51_path = [System.IO.Path]::GetFileName($PS51Path)
        query = $query
        entry_count = $ps7Paths.Count
        paths_identical = $true
        fields_identical = $true
        terms_identical = $true
        status_identical = $true
        reason_codes_identical = $true
    }
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

# Query matching 测试
$queryFixturePath = Join-ContextGatePath $fixtureRoot "query-matching-project.json"
$queryProjectRoot = Join-ContextGatePath $scratchRootFull "query matching project"
New-ContextGateFixtureProject -FixturePath $queryFixturePath -ProjectRoot $queryProjectRoot
$queryBefore = Get-ContextGateProjectSnapshot -ProjectRoot $queryProjectRoot

$queryMatchingResults = Test-QueryMatching -ScriptPath $sourceScript -ProjectRoot $queryProjectRoot -PowerShellPath $powerShellPath

# Cross-version 对照（PS5.1 可用时）
$crossVersionEvidence = $null
$ps51Path = ""
if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
    $ps51Candidate = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $ps51Candidate) { $ps51Path = $ps51Candidate }
}
if (-not [string]::IsNullOrWhiteSpace($ps51Path) -and [System.IO.Path]::GetFileName($powerShellPath) -ine "powershell.exe") {
    $crossVersionEvidence = Test-QueryMatchingCrossVersion -ScriptPath $sourceScript -ProjectRoot $queryProjectRoot -PS7Path $powerShellPath -PS51Path $ps51Path
} elseif (-not [string]::IsNullOrWhiteSpace($ps51Path) -and [System.IO.Path]::GetFileName($powerShellPath) -ieq "powershell.exe") {
    # 当前已经是 PS5.1，尝试找 pwsh
    $pwshCandidate = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $pwshCandidate) {
        $crossVersionEvidence = Test-QueryMatchingCrossVersion -ScriptPath $sourceScript -ProjectRoot $queryProjectRoot -PS7Path $pwshCandidate.Source -PS51Path $ps51Path
    }
}

# 场景 17：缺 index 时 entry metadata 仍可匹配，并返回 context-index-missing
$noIndexProject = Join-ContextGatePath $scratchRootFull "no index project"
New-Item -ItemType Directory -Force -Path (Join-ContextGatePath $noIndexProject ".agents" "context") | Out-Null
Set-Content -LiteralPath (Join-ContextGatePath $noIndexProject "AGENTS.md") -Value "# No Index Fixture" -Encoding UTF8
Set-Content -LiteralPath (Join-ContextGatePath $noIndexProject ".agents" "context" "solo-entry.md") -Value "# Solo`n`n## Summary`n`nIsolated SPI flash configuration.`n`n## Keywords`n`nSPI, flash, NOR`n`n## Body`n`nBody text." -Encoding UTF8
& git -C $noIndexProject init --quiet
& git -C $noIndexProject config core.autocrlf false
& git -C $noIndexProject add --all
& git -C $noIndexProject -c user.name=ctx -c user.email=ctx@example.invalid commit --quiet -m "no-index baseline"
$global:LASTEXITCODE = 0
$noIndexJson = Invoke-ContextGateProcess -PowerShellPath $powerShellPath -ScriptPath $sourceScript -ProjectRoot $noIndexProject -Mode json -Query "SPI flash"
$noIndexPayload = $noIndexJson | ConvertFrom-Json
Assert-ContextGateCondition -Condition (@($noIndexPayload.match_reason_codes) -contains "context-index-missing") -Message "Missing index should produce context-index-missing reason."
Assert-ContextGateCondition -Condition ([string]$noIndexPayload.match_status -ceq "matched") -Message "Entry metadata should still match without index."
$soloHits = @($noIndexPayload.matched_context_entries | Where-Object { [string]$_.path -eq ".agents/context/solo-entry.md" })
Assert-ContextGateCondition -Condition ($soloHits.Count -eq 1) -Message "solo-entry.md should match via its own metadata."
$queryMatchingResults += @([ordered]@{ name = "context-index-missing"; pass = $true })

# 场景 18：context 内 junction/symlink 指向 context 外时不读取、不匹配、返回安全 reason
$junctionProject = Join-ContextGatePath $scratchRootFull "junction project"
$junctionContext = Join-ContextGatePath $junctionProject ".agents" "context"
$externalTarget = Join-ContextGatePath $scratchRootFull "external context payload"
New-Item -ItemType Directory -Force -Path $junctionContext | Out-Null
New-Item -ItemType Directory -Force -Path $externalTarget | Out-Null
Set-Content -LiteralPath (Join-ContextGatePath $junctionProject "AGENTS.md") -Value "# Junction Fixture" -Encoding UTF8
Set-Content -LiteralPath (Join-ContextGatePath $externalTarget "evil-entry.md") -Value "# Evil`n`n## Summary`n`nExternal JUNCTIONSENTINEL payload.`n`n## Keywords`n`njunction, evil, external" -Encoding UTF8
$junctionLinkType = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) { "Junction" } else { "SymbolicLink" }
New-Item -ItemType $junctionLinkType -Path (Join-ContextGatePath $junctionContext "linked-dir") -Target $externalTarget -ErrorAction Stop | Out-Null
& git -C $junctionProject init --quiet
& git -C $junctionProject config core.autocrlf false
& git -C $junctionProject add --all
& git -C $junctionProject -c user.name=ctx -c user.email=ctx@example.invalid commit --quiet -m "junction baseline"
$global:LASTEXITCODE = 0
$junctionJson = Invoke-ContextGateProcess -PowerShellPath $powerShellPath -ScriptPath $sourceScript -ProjectRoot $junctionProject -Mode json -Query "junction evil external"
$junctionPayload = $junctionJson | ConvertFrom-Json
Assert-ContextGateCondition -Condition (-not $junctionJson.Contains("JUNCTIONSENTINEL")) -Message "Junction target content must not be read or leaked."
$evilHits = @($junctionPayload.matched_context_entries | Where-Object { [string]$_.path -like "*linked-dir*" -or [string]$_.path -like "*evil*" })
Assert-ContextGateCondition -Condition ($evilHits.Count -eq 0) -Message "Junction-linked entry must not produce matches."
Assert-ContextGateCondition -Condition (@($junctionPayload.match_reason_codes) -contains "unsafe-context-path-ignored") -Message "Junction path should produce unsafe-context-path-ignored reason."
$queryMatchingResults += @([ordered]@{ name = "junction-reparse-rejected"; pass = $true })

# 验证 query fixture 读写不变
$queryAfter = Get-ContextGateProjectSnapshot -ProjectRoot $queryProjectRoot
$queryBeforeJson = $queryBefore | ConvertTo-Json -Depth 6 -Compress
$queryAfterJson = $queryAfter | ConvertTo-Json -Depth 6 -Compress
Assert-ContextGateCondition -Condition ($queryBeforeJson -ceq $queryAfterJson) -Message "Query matching changed fixture project files or git status."

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
    query_matching_cases = $queryMatchingResults
    query_matching_case_count = $queryMatchingResults.Count
    cross_version_evidence = $crossVersionEvidence
    unresolved_locator_fail_soft = $true
    malicious_project_helper_ignored = $true
    malformed_manifest_rejected = $true
    tampered_managed_provider_rejected = $true
    unreadable_managed_provider_fail_soft = $true
    project_read_only = $true
    query_project_read_only = $true
}
if ($Json.IsPresent) { $result | ConvertTo-Json -Depth 8 }
else { Write-Output ("project-context-gate checks: PASS ({0} layouts; {1} project template cases; {2} query matching cases; read-only)" -f $results.Count, $caseResults.Count, $queryMatchingResults.Count) }
