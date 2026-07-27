param(
    [string]$ProjectRoot = (Get-Location).Path,
    [ValidateSet("start", "phase", "resume")]
    [string]$Gate = "start",
    [switch]$Json,
    [switch]$Brief,
    [switch]$IncludeTemplates,
    [string]$Query = ""
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

function Test-SourceCheckoutRuntime {
    param([Parameter(Mandatory = $true)][string]$RuntimeRoot)

    try {
        if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { return $false }

        $global:LASTEXITCODE = 0
        $inside = @(& git -C $RuntimeRoot rev-parse --is-inside-work-tree 2>$null)
        if ($LASTEXITCODE -ne 0 -or (($inside | Select-Object -First 1) -as [string]).Trim() -cne "true") {
            $global:LASTEXITCODE = 0
            return $false
        }

        $topLevel = @(& git -C $RuntimeRoot rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or $topLevel.Count -lt 1) {
            $global:LASTEXITCODE = 0
            return $false
        }
        $runtimeFull = [System.IO.Path]::GetFullPath($RuntimeRoot).TrimEnd([char[]]"\/")
        $topLevelFull = [System.IO.Path]::GetFullPath(([string]$topLevel[0]).Trim()).TrimEnd([char[]]"\/")
        $comparison = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            [System.StringComparison]::OrdinalIgnoreCase
        } else {
            [System.StringComparison]::Ordinal
        }
        if (-not $runtimeFull.Equals($topLevelFull, $comparison)) {
            $global:LASTEXITCODE = 0
            return $false
        }

        $tracked = @(& git -C $RuntimeRoot ls-files --error-unmatch -- `
                "scripts/status.ps1" `
                "skills/project-context-gate/scripts/context_gate.ps1" 2>$null)
        $trackedExitCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        return $trackedExitCode -eq 0 -and $tracked.Count -eq 2
    } catch {
        $global:LASTEXITCODE = 0
        return $false
    }
}

function Get-TrustedStatusProvider {
    param([Parameter(Mandatory = $true)][string]$RuntimeRoot)

    $statusRelativePath = "scripts/status.ps1"
    $statusScript = Test-TrustedHelperFile -RuntimeRoot $RuntimeRoot -RelativePath $statusRelativePath
    if ([string]::IsNullOrWhiteSpace($statusScript)) { return $null }

    $manifestPath = Test-TrustedHelperFile -RuntimeRoot $RuntimeRoot -RelativePath "install-manifest.json"
    if ([string]::IsNullOrWhiteSpace($manifestPath)) {
        if (Test-SourceCheckoutRuntime -RuntimeRoot $RuntimeRoot) {
            return [ordered]@{ path = $statusScript; provenance = "source-checkout" }
        }
        return $null
    }

    try {
        $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
        $schemaProperty = if (Test-ContextGateObject -Value $manifest) { $manifest.PSObject.Properties["schema_version"] } else { $null }
        $itemsProperty = if (Test-ContextGateObject -Value $manifest) { $manifest.PSObject.Properties["items"] } else { $null }
        if ($null -eq $schemaProperty -or -not (Test-ContextGateInteger -Value $schemaProperty.Value) -or [int64]$schemaProperty.Value -ne 2 -or
            $null -eq $itemsProperty -or $itemsProperty.Value -isnot [System.Array]) {
            return $null
        }

        $providerItems = @($itemsProperty.Value | Where-Object {
                (Test-ContextGateObject -Value $_) -and [string]$_.name -ceq "runtime-status-provider"
            })
        if ($providerItems.Count -ne 1) { return $null }
        $providerItem = $providerItems[0]
        $filesProperty = $providerItem.PSObject.Properties["files"]
        if ([string]$providerItem.source -cne "scripts" -or [string]$providerItem.destination -cne "scripts" -or
            [string]$providerItem.mode -cne "copy" -or $providerItem.managed -isnot [bool] -or -not [bool]$providerItem.managed -or
            $null -eq $filesProperty -or $filesProperty.Value -isnot [System.Array]) {
            return $null
        }

        $expectedFiles = @("lib/path-guard.ps1", "lib/runtime-status-action.ps1", "status.ps1")
        $fileRecords = @($providerItem.files)
        $recordPaths = @($fileRecords | ForEach-Object { [string]$_.path } | Sort-Object)
        if (($recordPaths -join "`n") -cne (($expectedFiles | Sort-Object) -join "`n")) { return $null }

        foreach ($record in $fileRecords) {
            if (-not (Test-ContextGateObject -Value $record)) { return $null }
            $relativePath = [string]$record.path
            $installedHash = [string]$record.installed_sha256
            if ($installedHash -cnotmatch '^[0-9a-f]{64}$') { return $null }
            $managedPath = Test-TrustedHelperFile -RuntimeRoot $RuntimeRoot -RelativePath ("scripts/{0}" -f $relativePath)
            if ([string]::IsNullOrWhiteSpace($managedPath)) { return $null }
            $currentHash = (Get-FileHash -LiteralPath $managedPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            if ($currentHash -cne $installedHash) { return $null }
        }

        return [ordered]@{ path = $statusScript; provenance = "manifest-managed-copy" }
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
            provenance = "unresolved"
        }
    }
}

function Get-ProjectTemplateStatus {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $result = New-ProjectTemplateStatus
    $runtime = Get-TrustedRuntimeRoot
    $result.helper.trust = [string]$runtime.trust
    if ([string]$runtime.trust -ne "trusted" -or [string]::IsNullOrWhiteSpace([string]$runtime.root)) { return $result }

    $statusProvider = Get-TrustedStatusProvider -RuntimeRoot ([string]$runtime.root)
    if ($null -eq $statusProvider -or [string]::IsNullOrWhiteSpace([string]$statusProvider.path)) {
        $result.reason = "status-helper-missing"
        return $result
    }
    $statusScript = [string]$statusProvider.path
    $result.helper.availability = "available"
    $result.helper.provenance = [string]$statusProvider.provenance

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
    $Lines.Add(("- helper provenance: {0}" -f [string]$ProjectTemplate.helper.provenance)) | Out-Null
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

    $hasQueryMatch = ($Payload -is [System.Collections.IDictionary]) -and $Payload.Contains("matched_context_entries")
    if ($hasQueryMatch) {
        $lines.Add("Context metadata matches (matched, not loaded):") | Out-Null
        $lines.Add(("- query: {0}" -f [string]$Payload["query"])) | Out-Null
        $entryList = @($Payload["matched_context_entries"])
        if ($entryList.Count -eq 0) {
            $lines.Add("- (no matches)") | Out-Null
        } else {
            foreach ($entry in $entryList) {
                $lines.Add(("- {0} [fields: {1}; terms: {2}]" -f $entry.path, ($entry.matched_fields -join ", "), ($entry.matched_terms -join ", "))) | Out-Null
            }
        }
        if ($Payload.Contains("match_reason_codes") -and @($Payload["match_reason_codes"]).Count -gt 0) {
            $lines.Add(("- reasons: {0}" -f (@($Payload["match_reason_codes"]) -join ", "))) | Out-Null
        }
        $lines.Add("- Matched entries are metadata hits only; they have not been loaded, applied, or authorized.") | Out-Null
        $lines.Add("") | Out-Null
    }

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

# Get-QueryTerms: 按空白切分 Query，ordinal-ignore-case 去重，保留首次写法。
function Get-QueryTerms {
    param([string]$RawQuery)

    $terms = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($token in @($RawQuery -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if ($seen.Add($token)) {
            $terms.Add($token)
        }
    }
    return @($terms.ToArray())
}

# Test-SafeRelativeContextPath: 验证相对路径安全（无 ..、非绝对、不逃逸 context root）。
function Test-SafeRelativeContextPath {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $false }
    $normalized = $RelativePath -replace '\\', '/'
    $segments = @($normalized -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($segments.Count -eq 0) { return $false }
    foreach ($segment in $segments) {
        if ($segment -eq "." -or $segment -eq "..") { return $false }
    }
    return $true
}

# Read-ContextEntryMetadata: 流式读取条目文件的 metadata 区域（Summary / Keywords）。
# 遇到后续非 metadata heading 时停止，不读取正文。
function Read-ContextEntryMetadata {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $result = [ordered]@{ summary = ""; keywords = "" }
    try {
        $reader = [System.IO.StreamReader]::new($FilePath, [System.Text.Encoding]::UTF8, $true)
    } catch {
        return $result
    }
    try {
        $currentSection = ""
        $summaryLines = New-Object 'System.Collections.Generic.List[string]'
        $keywordsLines = New-Object 'System.Collections.Generic.List[string]'
        $metadataHeadings = @("summary", "keywords")
        while ($null -ne ($line = $reader.ReadLine())) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^##\s+(.+)$') {
                $heading = $Matches[1].Trim()
                $headingLower = $heading.ToLowerInvariant()
                if ($headingLower -in $metadataHeadings) {
                    $currentSection = $headingLower
                    continue
                }
                # 遇到非 metadata heading，metadata 区域结束
                break
            }
            if ($currentSection -eq "summary") {
                $summaryLines.Add($line)
            }
            elseif ($currentSection -eq "keywords") {
                $keywordsLines.Add($line)
            }
        }
        $result.summary = ($summaryLines -join " ").Trim()
        $result.keywords = ($keywordsLines -join " ").Trim()
    } catch {
        # fail-soft：读取异常不中断 gate
    } finally {
        $reader.Dispose()
    }
    return $result
}

# Get-IndexTableEntries: 解析 README/index 中的条目索引表（File / Summary / Keywords）。
# 支持中文列名（文件/摘要/关键词）和英文列名。
function Get-IndexTableEntries {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $entries = New-Object 'System.Collections.Generic.List[object]'
    try {
        $lines = [System.IO.File]::ReadAllLines($FilePath, [System.Text.Encoding]::UTF8)
    } catch {
        return @($entries.ToArray())
    }

    $headerCols = $null
    $fileCol = -1
    $summaryCol = -1
    $keywordsCol = -1
    $inTable = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith("|")) {
            if ($inTable) { break }
            continue
        }
        $cells = @($trimmed -split '\|' | ForEach-Object { $_.Trim() })
        # 去除首尾空元素（由 | 开头和结尾产生）
        if ($cells.Count -gt 0 -and $cells[0] -eq "") { $cells = $cells[1..($cells.Count - 1)] }
        if ($cells.Count -gt 0 -and $cells[$cells.Count - 1] -eq "") { $cells = $cells[0..($cells.Count - 2)] }

        if ($null -eq $headerCols) {
            # 检测是否为表头行
            $lowerCells = @($cells | ForEach-Object { $_.ToLowerInvariant() })
            $fc = [array]::IndexOf($lowerCells, "file")
            if ($fc -lt 0) { $fc = [array]::IndexOf($lowerCells, ([regex]::Unescape('\u6587\u4ef6'))) }
            $sc = [array]::IndexOf($lowerCells, "summary")
            if ($sc -lt 0) { $sc = [array]::IndexOf($lowerCells, ([regex]::Unescape('\u6458\u8981'))) }
            $kc = [array]::IndexOf($lowerCells, "keywords")
            if ($kc -lt 0) { $kc = [array]::IndexOf($lowerCells, ([regex]::Unescape('\u5173\u952e\u8bcd'))) }
            if ($fc -ge 0 -and ($sc -ge 0 -or $kc -ge 0)) {
                $headerCols = $cells
                $fileCol = $fc
                $summaryCol = $sc
                $keywordsCol = $kc
                $inTable = $true
                continue
            }
            continue
        }

        # 跳过分隔行（--- | --- | ---）
        if ($trimmed -match '^\|[\s\-:|]+\|$') { continue }

        if ($cells.Count -gt [Math]::Max($fileCol, [Math]::Max($summaryCol, $keywordsCol))) {
            $fileValue = if ($fileCol -ge 0 -and $fileCol -lt $cells.Count) { $cells[$fileCol].Trim('`', ' ') } else { "" }
            $summaryValue = if ($summaryCol -ge 0 -and $summaryCol -lt $cells.Count) { $cells[$summaryCol] } else { "" }
            $keywordsValue = if ($keywordsCol -ge 0 -and $keywordsCol -lt $cells.Count) { $cells[$keywordsCol] } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($fileValue)) {
                $entries.Add([ordered]@{
                    file = $fileValue
                    summary = $summaryValue
                    keywords = $keywordsValue
                })
            }
        }
    }
    return @($entries.ToArray())
}

# Test-ContextPathReparseSafe: 检查 entry 路径及 context root 以下全部祖先是否含 reparse point。
# 拒绝 symlink、junction 或其他 reparse path，不打开文件。
function Test-ContextPathReparseSafe {
    param(
        [Parameter(Mandatory = $true)][string]$EntryPath,
        [Parameter(Mandatory = $true)][string]$ContextDirFull
    )

    try {
        $entryFull = [System.IO.Path]::GetFullPath($EntryPath)
        $contextFull = [System.IO.Path]::GetFullPath($ContextDirFull)
        $separator = [System.IO.Path]::DirectorySeparatorChar
        $contextPrefix = $contextFull.TrimEnd([char[]]"\/")

        # 获取 entry 相对于 context root 的路径段
        $comparison = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            [System.StringComparison]::OrdinalIgnoreCase
        } else {
            [System.StringComparison]::Ordinal
        }
        if (-not $entryFull.StartsWith($contextPrefix + $separator, $comparison)) { return $false }

        $relativePart = $entryFull.Substring($contextPrefix.Length + 1)
        $segments = @($relativePart -split [regex]::Escape($separator) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($segments.Count -eq 0) { return $false }

        # 逐级检查 context root 以下每个祖先（含 entry 本身）
        $current = $contextFull
        foreach ($segment in $segments) {
            $current = Join-Path $current $segment
            if (-not (Test-Path -LiteralPath $current)) { return $false }
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

# Find-ContextMetadataMatches: 对 .agents/context/ 执行确定性 metadata 匹配。
# 返回 matched_context_entries 数组和 reason_codes。
function Find-ContextMetadataMatches {
    param(
        [Parameter(Mandatory = $true)][string]$ContextDir,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string[]]$Terms
    )

    $reasonCodes = New-Object 'System.Collections.Generic.List[string]'
    $matchMap = @{}

    if (-not (Test-Path -LiteralPath $ContextDir)) {
        $reasonCodes.Add("context-directory-missing")
        return [ordered]@{ entries = @(); reason_codes = @($reasonCodes.ToArray()) }
    }

    $contextDirFull = [System.IO.Path]::GetFullPath($ContextDir)
    $projectRootFull = [System.IO.Path]::GetFullPath($ProjectRoot)

    # 收集所有 index/README 文件
    $indexFiles = @()
    try {
        $indexFiles = @(Get-ChildItem -LiteralPath $ContextDir -Recurse -File | Where-Object {
            $_.Name -in @("README.md", "index.md", "index.json")
        })
    } catch {
        $reasonCodes.Add("context-enumeration-failed")
        return [ordered]@{ entries = @(); reason_codes = @($reasonCodes.ToArray()) }
    }

    if ($indexFiles.Count -eq 0) {
        $reasonCodes.Add("context-index-missing")
    }

    # 从 index 表提取 metadata
    foreach ($indexFile in $indexFiles) {
        if ($indexFile.Extension -ceq ".json") {
            # JSON index：尝试解析，未知 schema 时 fail-soft
            try {
                $jsonContent = [System.IO.File]::ReadAllText($indexFile.FullName, [System.Text.Encoding]::UTF8)
                $jsonPayload = $jsonContent | ConvertFrom-Json
                if ($null -ne $jsonPayload -and $null -ne $jsonPayload.PSObject.Properties["entries"]) {
                    foreach ($entry in @($jsonPayload.entries)) {
                        if ($null -eq $entry) { continue }
                        $fileProp = $entry.PSObject.Properties["file"]
                        if ($null -eq $fileProp -or [string]::IsNullOrWhiteSpace([string]$fileProp.Value)) { continue }
                        $relativePath = [string]$fileProp.Value
                        if (-not (Test-SafeRelativeContextPath -RelativePath $relativePath)) {
                            $reasonCodes.Add("unsafe-index-path-ignored")
                            continue
                        }
                        $summaryText = ""
                        $keywordsText = ""
                        $sumProp = $entry.PSObject.Properties["summary"]
                        $kwProp = $entry.PSObject.Properties["keywords"]
                        if ($null -ne $sumProp) { $summaryText = [string]$sumProp.Value }
                        if ($null -ne $kwProp) { $keywordsText = [string]$kwProp.Value }
                        $indexDir = $indexFile.DirectoryName
                        $entryFullPath = [System.IO.Path]::GetFullPath((Join-Path $indexDir $relativePath))
                        $normalizedRel = $entryFullPath.Substring($projectRootFull.TrimEnd('\', '/').Length).TrimStart([char[]]"\/") -replace '\\', '/'
                        Add-MatchCandidate -MatchMap $matchMap -NormalizedPath $normalizedRel -FullPath $entryFullPath -ContextDirFull $contextDirFull -Summary $summaryText -Keywords $keywordsText -SourceField "index" -Terms $Terms -ReasonCodes $reasonCodes
                    }
                } else {
                    $reasonCodes.Add("unknown-json-index-schema")
                }
            } catch {
                $reasonCodes.Add("json-index-parse-failed")
            }
            continue
        }

        # Markdown index 表
        $tableEntries = Get-IndexTableEntries -FilePath $indexFile.FullName
        foreach ($tableEntry in $tableEntries) {
            $relativePath = [string]$tableEntry.file
            if (-not (Test-SafeRelativeContextPath -RelativePath $relativePath)) {
                $reasonCodes.Add("unsafe-index-path-ignored")
                continue
            }
            $indexDir = $indexFile.DirectoryName
            $entryFullPath = [System.IO.Path]::GetFullPath((Join-Path $indexDir $relativePath))
            $normalizedRel = $entryFullPath.Substring($projectRootFull.TrimEnd('\', '/').Length).TrimStart([char[]]"\/") -replace '\\', '/'
            Add-MatchCandidate -MatchMap $matchMap -NormalizedPath $normalizedRel -FullPath $entryFullPath -ContextDirFull $contextDirFull -Summary ([string]$tableEntry.summary) -Keywords ([string]$tableEntry.keywords) -SourceField "index" -Terms $Terms -ReasonCodes $reasonCodes
        }
    }

    # 检测 context 内的 reparse point 目录（junction/symlink），PS7 不跟踪但需报告
    try {
        $reparseDirs = @(Get-ChildItem -LiteralPath $ContextDir -Recurse -Directory -Force | Where-Object {
            ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        })
        if ($reparseDirs.Count -gt 0) {
            $reasonCodes.Add("unsafe-context-path-ignored")
        }
    } catch {
        # fail-soft：枚举异常不中断
    }

    # 从条目文件前部 metadata 匹配
    $entryFiles = @()
    try {
        $entryFiles = @(Get-ChildItem -LiteralPath $ContextDir -Recurse -File | Where-Object {
            $_.Name -notin @("README.md", "index.md", "index.json", "case_template.md") -and
            $_.Extension -in @(".md", ".txt")
        })
    } catch {
        $reasonCodes.Add("context-enumeration-failed")
    }

    foreach ($entryFile in $entryFiles) {
        $normalizedRel = $entryFile.FullName.Substring($projectRootFull.TrimEnd('\', '/').Length).TrimStart([char[]]"\/") -replace '\\', '/'

        # 物理路径安全检查：拒绝 reparse point（读取前）
        if (-not (Test-ContextPathReparseSafe -EntryPath $entryFile.FullName -ContextDirFull $contextDirFull)) {
            $reasonCodes.Add("unsafe-context-path-ignored")
            continue
        }

        $metadata = Read-ContextEntryMetadata -FilePath $entryFile.FullName
        $hasSummary = -not [string]::IsNullOrWhiteSpace([string]$metadata.summary)
        $hasKeywords = -not [string]::IsNullOrWhiteSpace([string]$metadata.keywords)
        if (-not $hasSummary -and -not $hasKeywords) {
            continue
        }
        # metadata 不完整：仅有其中一个字段
        if ($hasSummary -xor $hasKeywords) {
            $reasonCodes.Add("context-metadata-incomplete")
        }
        Add-MatchCandidate -MatchMap $matchMap -NormalizedPath $normalizedRel -FullPath $entryFile.FullName -ContextDirFull $contextDirFull -Summary ([string]$metadata.summary) -Keywords ([string]$metadata.keywords) -SourceField "entry" -Terms $Terms -ReasonCodes $reasonCodes
    }

    # 按规范化相对路径 ordinal 排序，确保确定性
    $keysList = New-Object 'System.Collections.Generic.List[string]'
    foreach ($k in $matchMap.Keys) { $keysList.Add($k) }
    $keysList.Sort([System.StringComparer]::Ordinal)
    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($key in $keysList) {
        $results.Add($matchMap[$key])
    }

    if ($results.Count -eq 0) {
        $reasonCodes.Add("no-matches")
    }

    # reason codes：ordinal 去重 + 固定顺序输出
    $canonicalOrder = @(
        "context-directory-missing",
        "context-enumeration-failed",
        "context-index-missing",
        "context-metadata-incomplete",
        "unsafe-context-path-ignored",
        "unsafe-index-path-ignored",
        "unknown-json-index-schema",
        "json-index-parse-failed",
        "no-matches"
    )
    $seenReasons = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $dedupedReasons = New-Object 'System.Collections.Generic.List[string]'
    foreach ($code in $canonicalOrder) {
        if ($reasonCodes.Contains($code) -and $seenReasons.Add($code)) {
            $dedupedReasons.Add($code)
        }
    }

    return [ordered]@{ entries = @($results.ToArray()); reason_codes = @($dedupedReasons.ToArray()) }
}

# Add-MatchCandidate: 对单个候选条目执行 term 匹配并合并到 matchMap。
function Add-MatchCandidate {
    param(
        [hashtable]$MatchMap,
        [string]$NormalizedPath,
        [string]$FullPath,
        [string]$ContextDirFull,
        [string]$Summary,
        [string]$Keywords,
        [string]$SourceField,
        [string[]]$Terms,
        [System.Collections.Generic.List[string]]$ReasonCodes
    )

    # 物理路径安全检查：拒绝 reparse point（读取前）
    if (Test-Path -LiteralPath $FullPath) {
        if (-not (Test-ContextPathReparseSafe -EntryPath $FullPath -ContextDirFull $ContextDirFull)) {
            $ReasonCodes.Add("unsafe-context-path-ignored")
            return
        }
    }

    # 逻辑安全检查：确保路径在 context root 内
    try {
        $fullResolved = [System.IO.Path]::GetFullPath($FullPath)
        $separator = [System.IO.Path]::DirectorySeparatorChar
        $contextPrefix = $ContextDirFull.TrimEnd([char[]]"\/") + $separator
        $comparison = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            [System.StringComparison]::OrdinalIgnoreCase
        } else {
            [System.StringComparison]::Ordinal
        }
        if (-not $fullResolved.StartsWith($contextPrefix, $comparison)) {
            $ReasonCodes.Add("unsafe-index-path-ignored")
            return
        }
    } catch {
        $ReasonCodes.Add("unsafe-index-path-ignored")
        return
    }

    # 固定字段顺序：keywords, summary
    $fieldTexts = [ordered]@{
        keywords = $Keywords
        summary = $Summary
    }

    $matchedFields = New-Object 'System.Collections.Generic.List[string]'
    $matchedTerms = New-Object 'System.Collections.Generic.List[string]'

    foreach ($term in $Terms) {
        $termMatched = $false
        foreach ($fieldName in $fieldTexts.Keys) {
            $fieldValue = [string]$fieldTexts[$fieldName]
            if ([string]::IsNullOrWhiteSpace($fieldValue)) { continue }
            if ($fieldValue.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                if (-not $matchedFields.Contains($fieldName)) {
                    $matchedFields.Add($fieldName)
                }
                $termMatched = $true
            }
        }
        if ($termMatched -and -not $matchedTerms.Contains($term)) {
            $matchedTerms.Add($term)
        }
    }

    if ($matchedFields.Count -eq 0) { return }

    # 合并到已有记录（同一 entry 可能由 index 和 entry metadata 同时命中）
    if ($MatchMap.ContainsKey($NormalizedPath)) {
        $existing = $MatchMap[$NormalizedPath]
        foreach ($f in $matchedFields) {
            if ($existing.matched_fields -notcontains $f) {
                $existing.matched_fields = @($existing.matched_fields) + @($f)
            }
        }
        foreach ($t in $matchedTerms) {
            if ($existing.matched_terms -notcontains $t) {
                $existing.matched_terms = @($existing.matched_terms) + @($t)
            }
        }
        # 重新按固定顺序排列 matched_fields
        $existing.matched_fields = @(Sort-MatchedFields -Fields $existing.matched_fields)
        # matched_terms 按 Query 顺序（即 Terms 数组顺序）
        $existing.matched_terms = @(Sort-MatchedTerms -Terms $existing.matched_terms -QueryOrder $Terms)
    } else {
        $MatchMap[$NormalizedPath] = [ordered]@{
            path = $NormalizedPath
            matched_fields = @(Sort-MatchedFields -Fields @($matchedFields.ToArray()))
            matched_terms = @(Sort-MatchedTerms -Terms @($matchedTerms.ToArray()) -QueryOrder $Terms)
        }
    }
}

# Sort-MatchedFields: 固定字段顺序（keywords 在 summary 前）。
function Sort-MatchedFields {
    param([string[]]$Fields)
    $order = @("keywords", "summary")
    return @($order | Where-Object { $Fields -contains $_ })
}

# Sort-MatchedTerms: 按 Query 原始顺序排列 matched terms。
function Sort-MatchedTerms {
    param(
        [string[]]$Terms,
        [string[]]$QueryOrder
    )
    return @($QueryOrder | Where-Object { $term = $_; @($Terms | Where-Object { $_ -ieq $term }).Count -gt 0 })
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

# Query 模式：增量匹配 .agents/context/ metadata
$queryResult = $null
$queryTerms = @()
if (-not [string]::IsNullOrWhiteSpace($Query)) {
    $queryTerms = Get-QueryTerms -RawQuery $Query
    if ($queryTerms.Count -gt 0) {
        $queryResult = Find-ContextMetadataMatches -ContextDir $contextDir -ProjectRoot $root -Terms $queryTerms
        $payload.query = $Query
        $payload.matched_context_entries = $queryResult.entries
        $payload.match_status = if ($queryResult.entries.Count -gt 0) { "matched" } else { "no-match" }
        $payload.match_reason_codes = $queryResult.reason_codes
    }
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

if ($null -ne $queryResult) {
    Write-Host "Context metadata matches (matched, not loaded):"
    Write-Host ("- query: {0}" -f $Query)
    if ($queryResult.entries.Count -eq 0) {
        Write-Host "- (no matches)"
    } else {
        foreach ($entry in $queryResult.entries) {
            Write-Host ("- {0} [fields: {1}; terms: {2}]" -f $entry.path, ($entry.matched_fields -join ", "), ($entry.matched_terms -join ", "))
        }
    }
    if ($queryResult.reason_codes.Count -gt 0) {
        Write-Host ("- reasons: {0}" -f ($queryResult.reason_codes -join ", "))
    }
    Write-Host "- Matched entries are metadata hits only; they have not been loaded, applied, or authorized."
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
