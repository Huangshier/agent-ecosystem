param(
    [string]$ProjectRoot = (Get-Location).Path,
    [ValidateSet("start", "phase", "resume")]
    [string]$Gate = "start",
    [switch]$Json,
    [switch]$Brief,
    [switch]$IncludeTemplates
)

$ErrorActionPreference = "Stop"

function Resolve-ProjectRoot {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "ProjectRoot does not exist: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Join-PathParts {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Children
    )

    $path = $Root
    foreach ($child in $Children) {
        if ([string]::IsNullOrWhiteSpace($child)) {
            continue
        }
        foreach ($segment in @($child -split '[\\/]+')) {
            if (-not [string]::IsNullOrWhiteSpace($segment)) {
                $path = Join-Path $path $segment
            }
        }
    }
    return $path
}

function Add-FileIfExists {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Path,
        [string]$Tier,
        [string]$Reason
    )

    if (Test-Path -LiteralPath $Path) {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        if (-not ($List | Where-Object { $_.path -eq $resolved })) {
            $List.Add([ordered]@{
                tier = $Tier
                path = $resolved
                reason = $Reason
            })
        }
    }
}

function Find-SpecReferences {
    param(
        [string]$Root,
        [string[]]$SourceFiles
    )

    $refs = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($file in $SourceFiles) {
        if (-not (Test-Path -LiteralPath $file)) {
            continue
        }
        $text = Get-Content -LiteralPath $file -Raw
        $matches = [regex]::Matches($text, 'docs/specs/[A-Za-z0-9._-]+/(spec|tasks)\.md')
        foreach ($match in $matches) {
            [void]$refs.Add($match.Value)
        }
    }

    return $refs | ForEach-Object {
        $candidate = Join-PathParts $Root $_
        if (Test-Path -LiteralPath $candidate) {
            (Resolve-Path -LiteralPath $candidate).Path
        }
    }
}

function Get-GitState {
    param([string]$Root)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        return [ordered]@{
            state = "git_unavailable"
            branch = ""
            status = @()
            root = ""
        }
    }

    $inside = ""
    try {
        $inside = (& git -C $Root rev-parse --is-inside-work-tree 2>$null)
    } catch {}

    if ($LASTEXITCODE -ne 0 -or $inside.Trim() -ne "true") {
        return [ordered]@{
            state = "not_git"
            branch = ""
            status = @()
            root = ""
        }
    }

    $repoRoot = ""
    $branch = ""
    $status = @()
    try { $repoRoot = ((& git -C $Root rev-parse --show-toplevel 2>$null) | Select-Object -First 1).Trim() } catch {}
    try { $branch = ((& git -C $Root rev-parse --abbrev-ref HEAD 2>$null) | Select-Object -First 1).Trim() } catch {}
    try { $status = @(& git -C $Root status --short 2>$null) } catch {}

    return [ordered]@{
        state = if ($status.Count -gt 0) { "dirty" } else { "clean" }
        branch = $branch
        status = @($status)
        root = $repoRoot
    }
}

function Test-ContextGateObject {
    param([AllowNull()][object]$Value)
    return $null -ne $Value -and $Value -isnot [string] -and $Value -isnot [System.Array] -and
        ($Value -is [System.Collections.IDictionary] -or $null -ne $Value.PSObject)
}

function Test-ContextGateInteger {
    param([AllowNull()][object]$Value)
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Get-LinkTargetCandidate {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $targetProperty = $item.PSObject.Properties["Target"]
        if ($null -eq $targetProperty -or $null -eq $targetProperty.Value) { return "" }
        $target = @($targetProperty.Value | Select-Object -First 1)
        if ($target.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$target[0])) { return "" }
        $targetPath = [string]$target[0]
        if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
            $targetPath = Join-Path (Split-Path -Parent $Path) $targetPath
        }
        return [System.IO.Path]::GetFullPath($targetPath)
    } catch {
        return ""
    }
}

function Get-TrustedRuntimeRoot {
    $skillRoot = Split-Path -Parent $PSScriptRoot
    $skillCandidates = New-Object 'System.Collections.Generic.List[string]'

    foreach ($candidate in @(
        (Get-LinkTargetCandidate -Path $skillRoot),
        $skillRoot
    )) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try { $fullCandidate = [System.IO.Path]::GetFullPath($candidate) } catch { continue }
        if ($fullCandidate -notin $skillCandidates) { $skillCandidates.Add($fullCandidate) }
    }

    foreach ($candidate in @($skillCandidates.ToArray())) {
        try {
            if ([System.IO.Path]::GetFileName($candidate.TrimEnd([char[]]"\/")) -cne "project-context-gate") { continue }
            $skillsRoot = Split-Path -Parent $candidate
            if ([System.IO.Path]::GetFileName($skillsRoot.TrimEnd([char[]]"\/")) -cne "skills") { continue }
            $runtimeRoot = Split-Path -Parent $skillsRoot
            if ([string]::IsNullOrWhiteSpace($runtimeRoot)) { continue }
            return [ordered]@{ root = [System.IO.Path]::GetFullPath($runtimeRoot); trust = "trusted" }
        } catch {}
    }

    return [ordered]@{ root = $null; trust = "unresolved" }
}

function Test-TrustedHelperFile {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    try {
        if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $null }
        $segments = @($RelativePath -split '[\\/]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -in @(".", "..") }).Count -gt 0) { return $null }

        $rootFull = [System.IO.Path]::GetFullPath($RuntimeRoot)
        $candidateFull = $rootFull
        foreach ($segment in $segments) { $candidateFull = Join-Path $candidateFull $segment }
        $candidateFull = [System.IO.Path]::GetFullPath($candidateFull)
        $separator = [System.IO.Path]::DirectorySeparatorChar
        $rootPrefix = $rootFull.TrimEnd([char[]]"\\/") + $separator
        $comparison = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            [System.StringComparison]::OrdinalIgnoreCase
        } else {
            [System.StringComparison]::Ordinal
        }
        if (-not $candidateFull.StartsWith($rootPrefix, $comparison)) { return $null }

        $current = $rootFull
        for ($index = 0; $index -lt $segments.Count; $index++) {
            $current = Join-Path $current $segments[$index]
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
            $isLeaf = $index -eq ($segments.Count - 1)
            if (($isLeaf -and $item.PSIsContainer) -or (-not $isLeaf -and -not $item.PSIsContainer)) { return $null }
        }
        return $candidateFull
    } catch {
        return $null
    }
}

function ConvertTo-PowerShellSingleQuotedLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'{0}'" -f $Value.Replace("'", "''")
}

function New-ProjectTemplateStatus {
    return [ordered]@{
        status = "unknown"
        reason = "trusted-runtime-root-unresolved"
        project_language = $null
        guidance = "inspect-manually"
        command = $null
        command_reason = "not-applicable"
        helper = [ordered]@{
            availability = "unavailable"
            trust = "unresolved"
        }
    }
}

function Get-ProjectTemplateStatus {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $result = New-ProjectTemplateStatus
    $runtime = Get-TrustedRuntimeRoot
    $result.helper.trust = [string]$runtime.trust
    if ([string]$runtime.trust -ne "trusted" -or [string]::IsNullOrWhiteSpace([string]$runtime.root)) { return $result }

    $statusScript = Test-TrustedHelperFile -RuntimeRoot ([string]$runtime.root) -RelativePath "scripts/status.ps1"
    if ([string]::IsNullOrWhiteSpace($statusScript)) {
        $result.reason = "status-helper-missing"
        return $result
    }
    $result.helper.availability = "available"

    try {
        $powerShellPath = (Get-Process -Id $PID -ErrorAction Stop).Path
        if ([string]::IsNullOrWhiteSpace($powerShellPath)) { throw "unavailable" }
        $global:LASTEXITCODE = 0
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            # Windows PowerShell 5.1 promotes native stderr to an ErrorRecord under Stop.
            # Keep stderr quarantined and judge the child only by its exit code and stdout.
            $ErrorActionPreference = "Continue"
            $rawOutput = @(& $powerShellPath -NoProfile -File $statusScript -ProjectDir $ProjectRoot -Json 2>$null)
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        $exitCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($exitCode -ne 0) {
            $result.helper.availability = "failed"
            $result.reason = "status-helper-failed"
            return $result
        }
        $jsonText = ($rawOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($jsonText)) {
            $result.helper.availability = "failed"
            $result.reason = "status-helper-empty-output"
            return $result
        }
        try { $payload = $jsonText | ConvertFrom-Json -ErrorAction Stop }
        catch {
            $result.helper.availability = "failed"
            $result.reason = "status-helper-invalid-json"
            return $result
        }

        if (-not (Test-ContextGateObject -Value $payload)) { $result.reason = "status-payload-invalid"; return $result }
        $schemaProperty = $payload.PSObject.Properties["schema_version"]
        $projectProperty = $payload.PSObject.Properties["project"]
        if ($null -eq $schemaProperty -or -not (Test-ContextGateInteger -Value $schemaProperty.Value) -or [int64]$schemaProperty.Value -ne 1) {
            $result.reason = "status-schema-unsupported"
            return $result
        }
        if ($null -eq $projectProperty -or -not (Test-ContextGateObject -Value $projectProperty.Value)) {
            $result.reason = "status-project-invalid"
            return $result
        }

        $project = $projectProperty.Value
        $statusProperty = $project.PSObject.Properties["status"]
        $reasonProperty = $project.PSObject.Properties["reason"]
        $languageProperty = $project.PSObject.Properties["project_language"]
        $status = if ($null -eq $statusProperty) { $null } else { $statusProperty.Value }
        $reason = if ($null -eq $reasonProperty) { $null } else { $reasonProperty.Value }
        $language = if ($null -eq $languageProperty) { "__missing__" } else { $languageProperty.Value }
        $reasonsByStatus = @{
            "current" = @("in-sync")
            "optional-refresh" = @("template-baseline-drift", "memory-scaffold-refresh")
            "migration-required" = @("structural-memory-findings")
            "unknown" = @(
                "not-requested", "baseline-helper-unavailable", "memory-helper-unavailable", "missing-lock", "invalid-lock",
                "project-not-found", "invalid-hub-dir", "hub-not-git", "git-unavailable", "hub-remote-drift",
                "hub-branch-drift", "locked-hub-dirty", "current-hub-dirty", "metadata-unresolved",
                "project-language-unresolved", "project-language-conflict", "internal-error"
            )
        }
        $validStatusReason = $status -is [string] -and @($reasonsByStatus.Keys) -ccontains $status -and
            $reason -is [string] -and $reasonsByStatus[$status] -ccontains $reason
        $validLanguage = $null -ne $languageProperty -and
            ($null -eq $language -or ($language -is [string] -and @("en", "zh-CN") -ccontains $language))
        if (-not $validStatusReason) { $result.reason = "status-project-invalid"; return $result }
        if (-not $validLanguage) { $result.reason = "status-language-invalid"; return $result }

        $result.status = [string]$status
        $result.reason = [string]$reason
        $result.project_language = if ($null -eq $language) { $null } else { [string]$language }
        switch ([string]$status) {
            "current" { $result.guidance = "none" }
            "optional-refresh" {
                $result.guidance = "refresh-available"
                if ($null -ne $result.project_language) {
                    $bootstrapScript = Test-TrustedHelperFile -RuntimeRoot ([string]$runtime.root) -RelativePath "skills/project-bootstrap/scripts/bootstrap_project.ps1"
                    if (-not [string]::IsNullOrWhiteSpace($bootstrapScript)) {
                        $result.command = "& {0} ```{1}  -ProjectDir {2} ```{1}  -ProjectLanguage {3} ```{1}  -RefreshUnmodifiedTemplates" -f
                            (ConvertTo-PowerShellSingleQuotedLiteral $bootstrapScript), [Environment]::NewLine,
                            (ConvertTo-PowerShellSingleQuotedLiteral $ProjectRoot),
                            (ConvertTo-PowerShellSingleQuotedLiteral ([string]$result.project_language))
                        $result.command_reason = "available"
                    } else {
                        $result.command_reason = "trusted-guidance-helper-unavailable"
                    }
                } else {
                    $result.command_reason = "project-language-unavailable"
                }
            }
            "migration-required" {
                $result.guidance = "analyze-migration"
                $upgradeScript = Test-TrustedHelperFile -RuntimeRoot ([string]$runtime.root) -RelativePath "skills/project-bootstrap/scripts/memory_upgrade.ps1"
                if (-not [string]::IsNullOrWhiteSpace($upgradeScript)) {
                    $result.command = "& {0} ```{1}  -ProjectDir {2} ```{1}  -Mode Analyze ```{1}  -Json" -f
                        (ConvertTo-PowerShellSingleQuotedLiteral $upgradeScript), [Environment]::NewLine,
                        (ConvertTo-PowerShellSingleQuotedLiteral $ProjectRoot)
                    $result.command_reason = "available"
                } else {
                    $result.command_reason = "trusted-guidance-helper-unavailable"
                }
            }
            "unknown" { $result.guidance = "inspect-manually" }
        }
    } catch {
        $result.status = "unknown"
        $result.reason = "status-helper-failed"
        $result.project_language = $null
        $result.guidance = "inspect-manually"
        $result.command = $null
        $result.command_reason = "not-applicable"
        $result.helper.availability = "failed"
    }
    return $result
}

function Add-ProjectTemplateWarning {
    param(
        [System.Collections.Generic.List[string]]$Warnings,
        [Parameter(Mandatory = $true)][object]$ProjectTemplate
    )

    switch ([string]$ProjectTemplate.status) {
        "optional-refresh" { $Warnings.Add("PROJECT_TEMPLATE_OPTIONAL_REFRESH: Project templates or scaffold can be refreshed.") }
        "migration-required" { $Warnings.Add("PROJECT_TEMPLATE_MIGRATION_REQUIRED: Analyze project memory migration before refreshing templates.") }
        "unknown" { $Warnings.Add(("PROJECT_TEMPLATE_UNKNOWN: Inspect project template status manually ({0})." -f [string]$ProjectTemplate.reason)) }
    }
}

function Add-ProjectTemplateText {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)][object]$ProjectTemplate
    )

    $Lines.Add(("- status: {0}" -f [string]$ProjectTemplate.status)) | Out-Null
    $Lines.Add(("- reason: {0}" -f [string]$ProjectTemplate.reason)) | Out-Null
    $Lines.Add(("- project language: {0}" -f $(if ($null -eq $ProjectTemplate.project_language) { "unknown" } else { [string]$ProjectTemplate.project_language }))) | Out-Null
    $Lines.Add(("- guidance: {0}" -f [string]$ProjectTemplate.guidance)) | Out-Null
    $Lines.Add(("- helper availability: {0}" -f [string]$ProjectTemplate.helper.availability)) | Out-Null
    $Lines.Add(("- helper trust: {0}" -f [string]$ProjectTemplate.helper.trust)) | Out-Null
    if ($null -ne $ProjectTemplate.command) {
        $Lines.Add("- suggested command (not executed):") | Out-Null
        foreach ($commandLine in @([string]$ProjectTemplate.command -split '\r?\n')) {
            $Lines.Add(("  {0}" -f $commandLine)) | Out-Null
        }
    } elseif ([string]$ProjectTemplate.command_reason -eq "trusted-guidance-helper-unavailable") {
        $Lines.Add("- suggested command: unavailable (trusted guidance helper not found)") | Out-Null
    } elseif ([string]$ProjectTemplate.command_reason -eq "project-language-unavailable") {
        $Lines.Add("- suggested command: unavailable (project language not validated)") | Out-Null
    }
}

# Format-BriefItemList: render context items for brief output.
function Format-BriefItemList {
    param(
        [object[]]$Items,
        [string]$EmptyText
    )

    $itemList = @($Items)
    if ($itemList.Count -eq 0) {
        return @("- $EmptyText")
    }

    return @(
        $itemList | ForEach-Object {
            "- {0} [{1}]" -f $_.path, $_.reason
        }
    )
}

# Write-ContextBrief: emit a copyable agent brief from the context gate payload.
function Write-ContextBrief {
    param([object]$Payload)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $git = $Payload.git
    $statusList = @($git.status)
    $warningList = @($Payload.warnings)

    $lines.Add("Project Context Gate Brief") | Out-Null
    $lines.Add(("Gate: {0}" -f $Payload.gate)) | Out-Null
    $lines.Add(("Project root: {0}" -f $Payload.project_root)) | Out-Null
    $lines.Add("") | Out-Null

    $lines.Add("Git:") | Out-Null
    $lines.Add(("- state: {0}" -f $git.state)) | Out-Null
    if ($git.root) { $lines.Add(("- root: {0}" -f $git.root)) | Out-Null }
    if ($git.branch) { $lines.Add(("- branch: {0}" -f $git.branch)) | Out-Null }
    if ($statusList.Count -gt 0) {
        $lines.Add("- status:") | Out-Null
        foreach ($statusItem in $statusList) {
            $lines.Add(("  - {0}" -f $statusItem)) | Out-Null
        }
    }
    $lines.Add("") | Out-Null

    $lines.Add("Project template status:") | Out-Null
    Add-ProjectTemplateText -Lines $lines -ProjectTemplate $Payload.project_template
    $lines.Add("") | Out-Null

    $lines.Add("Hot files (load now):") | Out-Null
    foreach ($line in Format-BriefItemList -Items $Payload.hot_files -EmptyText "(none)") {
        $lines.Add($line) | Out-Null
    }
    $lines.Add("") | Out-Null

    $lines.Add("Active work package files:") | Out-Null
    foreach ($line in Format-BriefItemList -Items $Payload.warm_files -EmptyText "(none)") {
        $lines.Add($line) | Out-Null
    }
    $lines.Add("") | Out-Null

    $lines.Add("Cold discovery-only files:") | Out-Null
    foreach ($line in Format-BriefItemList -Items $Payload.cold_files -EmptyText "(none)") {
        $lines.Add($line) | Out-Null
    }
    $lines.Add("") | Out-Null

    $lines.Add("Warnings / boundary notes:") | Out-Null
    if ($warningList.Count -eq 0) {
        $lines.Add("- (no warnings)") | Out-Null
    } else {
        foreach ($warning in $warningList) {
            $lines.Add(("- {0}" -f $warning)) | Out-Null
        }
    }
    $lines.Add("- Cold files are discovery-only; open matching entries by Summary, Keywords, or task relevance.") | Out-Null
    $lines.Add("- This script inventories context only; it does not read all cold files or write project memory.") | Out-Null
    if ($git.state -eq "dirty") {
        $lines.Add("- Git is dirty; inspect status before editing or staging changes.") | Out-Null
    }
    $lines.Add("") | Out-Null

    $lines.Add("Next action:") | Out-Null
    $lines.Add("- Read the hot files first.") | Out-Null
    $lines.Add("- For non-trivial active work, read the active work package files.") | Out-Null
    $lines.Add("- Keep cold files closed until their index, Summary, Keywords, or task relevance matches the current work.") | Out-Null
    $lines.Add("- Produce a short constraint capsule before editing.") | Out-Null

    Write-Output ($lines -join [Environment]::NewLine)
}

function Get-ContextDiscoveryFiles {
    param(
        [string]$ContextDir,
        [bool]$IncludeAllTemplates
    )

    if (-not (Test-Path -LiteralPath $ContextDir)) {
        return @()
    }

    $files = Get-ChildItem -LiteralPath $ContextDir -Recurse -File | Sort-Object FullName
    if ($IncludeAllTemplates) {
        return @($files)
    }

    return @(
        $files | Where-Object {
            $_.Name -in @("README.md", "index.md", "index.json") -and
            $_.Name -ne "case_template.md"
        }
    )
}

$root = Resolve-ProjectRoot $ProjectRoot
$contextItems = New-Object 'System.Collections.Generic.List[object]'
$warnings = New-Object 'System.Collections.Generic.List[string]'

$rootAgents = Join-PathParts $root "AGENTS.md"
$agentGuide = Join-PathParts $root ".agents" "AGENTS.md"
$processPath = Join-PathParts $root ".agents" "process.txt"
$planPath = Join-PathParts $root ".agents" "plan.md"
$notesPath = Join-PathParts $root ".agents" "notes.md"

Add-FileIfExists $contextItems $rootAgents "hot" "Root project guidance"
Add-FileIfExists $contextItems $agentGuide "hot" "Primary project agent guide"
Add-FileIfExists $contextItems $processPath "hot" "Current operational state"
Add-FileIfExists $contextItems $planPath "hot" "Current active plan pointer"

$specRefs = Find-SpecReferences -Root $root -SourceFiles @($processPath, $planPath)
foreach ($spec in $specRefs) {
    Add-FileIfExists $contextItems $spec "warm" "Active spec referenced by project memory"
    $specDir = Split-Path -Parent $spec
    foreach ($pairedName in @("spec.md", "tasks.md")) {
        Add-FileIfExists $contextItems (Join-Path $specDir $pairedName) "warm" "Paired active spec artifact"
    }
}

$contextDir = Join-PathParts $root ".agents" "context"
foreach ($file in Get-ContextDiscoveryFiles -ContextDir $contextDir -IncludeAllTemplates $IncludeTemplates.IsPresent) {
    $reason = if ($IncludeTemplates.IsPresent) { "Full context audit requested" } else { "Context discovery index; open matching entries on demand" }
    Add-FileIfExists $contextItems $file.FullName "cold" $reason
}

if (Test-Path -LiteralPath $notesPath) {
    Add-FileIfExists $contextItems $notesPath "cold" "Stable notes; read on demand when relevant"
}

if (-not (Test-Path -LiteralPath $agentGuide) -and -not (Test-Path -LiteralPath $rootAgents)) {
    $warnings.Add("No AGENTS.md or .agents/AGENTS.md found for this project root.")
}
if ((Test-Path -LiteralPath $contextDir) -and -not $IncludeTemplates.IsPresent) {
    $warnings.Add("Context files are listed as cold discovery only. Open specific entries when the task keywords match.")
}

$gitState = Get-GitState -Root $root
$projectTemplate = Get-ProjectTemplateStatus -ProjectRoot $root
Add-ProjectTemplateWarning -Warnings $warnings -ProjectTemplate $projectTemplate
$allFiles = @($contextItems.ToArray())
$hotFiles = @($allFiles | Where-Object { $_.tier -eq "hot" })
$warmFiles = @($allFiles | Where-Object { $_.tier -eq "warm" })
$coldFiles = @($allFiles | Where-Object { $_.tier -eq "cold" })
$warningList = @($warnings.ToArray())
$payload = [ordered]@{
    gate = $Gate
    project_root = $root
    files = $allFiles
    hot_files = $hotFiles
    warm_files = $warmFiles
    cold_files = $coldFiles
    git = $gitState
    project_template = $projectTemplate
    warnings = $warningList
}

if ($Json.IsPresent) {
    $payload | ConvertTo-Json -Depth 8
    return
}

if ($Brief.IsPresent) {
    Write-ContextBrief -Payload $payload
    return
}

Write-Host "Project Context Gate: $Gate"
Write-Host "ProjectRoot: $root"
Write-Host ""

foreach ($tier in @("hot", "warm", "cold")) {
    $label = switch ($tier) {
        "hot" { "Hot files (load now)" }
        "warm" { "Warm files (active work package)" }
        default { "Cold files (discovery; open on demand)" }
    }
    Write-Host "${label}:"
    $tierFiles = @($contextItems | Where-Object { $_.tier -eq $tier })
    if ($tierFiles.Count -eq 0) {
        Write-Host "- (none)"
    } else {
        foreach ($item in $tierFiles) {
            Write-Host ("- {0} [{1}]" -f $item.path, $item.reason)
        }
    }
    Write-Host ""
}

Write-Host "Git state:"
Write-Host ("- state: {0}" -f $gitState.state)
if ($gitState.root) { Write-Host ("- root: {0}" -f $gitState.root) }
if ($gitState.branch) { Write-Host ("- branch: {0}" -f $gitState.branch) }
if ($gitState.status.Count -gt 0) {
    $gitState.status | ForEach-Object { Write-Host ("  {0}" -f $_) }
}
Write-Host ""

Write-Host "Project template status:"
$projectTemplateLines = New-Object 'System.Collections.Generic.List[string]'
Add-ProjectTemplateText -Lines $projectTemplateLines -ProjectTemplate $projectTemplate
$projectTemplateLines | ForEach-Object { Write-Host $_ }
Write-Host ""

if ($warnings.Count -gt 0) {
    Write-Host "Warnings:"
    $warnings | ForEach-Object { Write-Host ("- {0}" -f $_) }
    Write-Host ""
}

Write-Host "Next: read hot files first, warm files for the active task, and cold files only when their index/README matches the task."
