# Internal project-local client adapter responsibilities.
# This file is dot-sourced only by project-workspace.ps1. Canonical authority
# remains under .agents/skills; every adapter output is a derived managed copy.

$script:AdapterMarkerName = ".agent-ecosystem-adapter.json"
$script:SupportedAdapterTargets = @("claude-code")
$script:AdapterTarget = $script:SupportedAdapterTargets[0]
$script:AdapterSourceRoot = ".agents/skills"
$script:AdapterTargetRoot = ".claude/skills"
$script:AdapterCommonParameters = @(
    "Operation", "Mode", "ProjectRoot", "Target", "Json", "NoExit",
    "Verbose", "Debug", "ErrorAction", "WarningAction", "InformationAction",
    "ProgressAction", "ErrorVariable", "WarningVariable", "InformationVariable",
    "OutVariable", "OutBuffer", "PipelineVariable"
)

function New-AdapterFinding {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [AllowEmptyString()][string]$Path = "",
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("error", "warning")][string]$Severity = "error"
    )

    return [ordered]@{
        code = $Code
        path = $Path
        field = ""
        severity = $Severity
        message = $Message
    }
}

function New-AdapterFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][bool]$ReadOnly,
        [Parameter(Mandatory = $true)][string]$Code,
        [AllowEmptyString()][string]$Path = "",
        [Parameter(Mandatory = $true)][string]$Message,
        [object[]]$Items = @(),
        [System.Collections.IDictionary]$Extra = $null
    )

    $result = [ordered]@{
        operation = $Operation
        status = "FAIL"
        read_only = $ReadOnly
        adapter_target = $script:AdapterTarget
        supported_adapter_targets = @($script:SupportedAdapterTargets)
        representation = "managed-copy"
        lifecycle = "derived"
        canonical_source = $script:AdapterSourceRoot
        target_root = $script:AdapterTargetRoot
        path = $script:AdapterTargetRoot
        items = @($Items)
        findings = @((New-AdapterFinding -Code $Code -Path $Path -Message $Message))
    }
    if ($null -ne $Extra) {
        foreach ($key in @($Extra.Keys)) { $result[$key] = $Extra[$key] }
    }
    return $result
}

function Test-AdapterBoundParameter {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($BoundParameters -is [hashtable]) { return [bool]$BoundParameters.ContainsKey($Name) }
    if ($BoundParameters.PSObject.Methods.Name -contains "ContainsKey") { return [bool]$BoundParameters.ContainsKey($Name) }
    if ($BoundParameters.PSObject.Methods.Name -contains "Contains") { return [bool]$BoundParameters.Contains($Name) }
    return (@($BoundParameters.Keys | ForEach-Object { [string]$_ }) -ccontains $Name)
}

function Assert-AdapterOperationParameters {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters)

    foreach ($key in @($BoundParameters.Keys)) {
        if ($key -notin $script:AdapterCommonParameters) { throw "unsupported parameter" }
    }
}

function Test-AdapterReparsePoint {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item)
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-AdapterPortableSegment {
    param([AllowEmptyString()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -in @(".", "..")) { return $false }
    if ($Name.Length -gt 255 -or $Name.EndsWith(" ", [StringComparison]::Ordinal) -or $Name.EndsWith(".", [StringComparison]::Ordinal)) { return $false }
    if ($Name -match '[\x00-\x1f<>:"/\\|?*]') { return $false }
    $stem = $Name.Split('.')[0]
    if ($stem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { return $false }
    return $true
}

function Assert-AdapterPortableRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or $RelativePath.Contains('\')) { throw "adapter path is not normalized" }
    foreach ($segment in @($RelativePath -split '/')) {
        if (-not (Test-AdapterPortableSegment -Name $segment)) { throw "adapter path contains a Windows-incompatible segment" }
    }
}

function Assert-AdapterPathChain {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [switch]$RequireLeaf
    )

    $rootFull = Get-NormalizedFullPath -Path $Root
    $rootItem = Get-Item -LiteralPath $rootFull -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer -or (Test-AdapterReparsePoint -Item $rootItem)) { throw "project root is not a regular directory" }
    $cursor = $rootFull
    $segments = @($RelativePath -split '[\\/]')
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $cursor = Get-NormalizedFullPath -Path (Join-Path $cursor $segments[$index])
        if (-not (Test-PathIsEqualOrChild -Path $cursor -Root $rootFull)) { throw "adapter path escapes project root" }
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            if ($RequireLeaf.IsPresent) { throw "required adapter path is missing" }
            break
        }
        if (Test-AdapterReparsePoint -Item $item) { throw "adapter path contains a link or reparse point" }
        if ($index -lt ($segments.Count - 1) -and -not $item.PSIsContainer) { throw "adapter ancestor is not a directory" }
    }
    return (Get-NormalizedFullPath -Path (Join-Path $rootFull $RelativePath))
}

function Get-AdapterExecutableFlag {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) { return $false }
    $mode = [System.IO.File]::GetUnixFileMode($Path)
    $mask = [System.IO.UnixFileMode]::UserExecute -bor [System.IO.UnixFileMode]::GroupExecute -bor [System.IO.UnixFileMode]::OtherExecute
    return (($mode -band $mask) -ne 0)
}

function Set-AdapterExecutableFlag {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][bool]$Executable
    )

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) { return }
    $mode = [System.IO.File]::GetUnixFileMode($Path)
    $mask = [System.IO.UnixFileMode]::UserExecute -bor [System.IO.UnixFileMode]::GroupExecute -bor [System.IO.UnixFileMode]::OtherExecute
    $normalized = if ($Executable) { $mode -bor $mask } else { $mode -band (-bnot $mask) }
    [System.IO.File]::SetUnixFileMode($Path, $normalized)
}

function Get-AdapterTreeSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$ExcludeRootMarker,
        [switch]$RequireSkill
    )

    $rootItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer -or (Test-AdapterReparsePoint -Item $rootItem)) { throw "adapter tree root is not a regular directory" }

    $entryMap = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $caseSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($ExcludeRootMarker.IsPresent) { [void]$caseSet.Add($script:AdapterMarkerName) }
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([ordered]@{ path = $rootItem.FullName; relative = "" })
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath ([string]$directory.path) -Force -ErrorAction Stop)) {
            if (Test-AdapterReparsePoint -Item $item) { throw "adapter tree contains a link or reparse point" }
            $relative = if ([string]::IsNullOrEmpty([string]$directory.relative)) { $item.Name } else { "{0}/{1}" -f $directory.relative, $item.Name }
            Assert-AdapterPortableRelativePath -RelativePath $relative
            if (-not $ExcludeRootMarker.IsPresent -and $relative.Equals($script:AdapterMarkerName, [StringComparison]::OrdinalIgnoreCase)) { throw "canonical Skill occupies the reserved adapter marker name" }
            if ($ExcludeRootMarker.IsPresent -and $relative -ceq $script:AdapterMarkerName) { continue }
            if (-not $caseSet.Add($relative)) { throw "adapter tree contains a case-insensitive path collision" }
            if ($item.PSIsContainer) {
                $entryMap.Add($relative, [ordered]@{ path = $relative; type = "directory"; full_path = $item.FullName; executable = $false; length = 0L })
                $queue.Enqueue([ordered]@{ path = $item.FullName; relative = $relative })
            }
            elseif ($item -is [System.IO.FileInfo]) {
                $entryMap.Add($relative, [ordered]@{ path = $relative; type = "file"; full_path = $item.FullName; executable = [bool](Get-AdapterExecutableFlag -Path $item.FullName); length = [long]$item.Length })
            }
            else { throw "adapter tree contains an unsupported filesystem entry" }
        }
    }

    if ($RequireSkill.IsPresent) {
        if (-not $entryMap.ContainsKey("SKILL.md") -or [string]$entryMap["SKILL.md"].type -cne "file") { throw "canonical Skill is missing regular-file SKILL.md" }
    }

    $paths = [string[]]@($entryMap.Keys)
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    $hash = [System.Security.Cryptography.IncrementalHash]::CreateHash([System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        foreach ($relative in $paths) {
            $entry = $entryMap[$relative]
            $lengthText = ([long]$entry.length).ToString([Globalization.CultureInfo]::InvariantCulture)
            $header = [string]::Concat([string]$entry.type, "`0", [string]$entry.path, "`0", $(if ([bool]$entry.executable) { "1" } else { "0" }), "`0", $lengthText, "`0")
            $hash.AppendData([System.Text.UTF8Encoding]::new($false).GetBytes($header))
            if ([string]$entry.type -ceq "file") { $hash.AppendData([System.IO.File]::ReadAllBytes([string]$entry.full_path)) }
            $hash.AppendData([byte[]]@(0))
        }
        $digest = "sha256:" + ([BitConverter]::ToString($hash.GetHashAndReset())).Replace('-', '').ToLowerInvariant()
    }
    finally { $hash.Dispose() }

    return [ordered]@{
        digest = $digest
        entries = @($paths | ForEach-Object { $entryMap[$_] })
    }
}

function New-AdapterMarkerText {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Digest
    )

    return (@(
        '{',
        '  "schema_version": 1,',
        '  "owner": "agent-ecosystem",',
        '  "adapter_target": "claude-code",',
        '  "representation": "managed-copy",',
        '  "lifecycle": "derived",',
        ('  "source": ".agents/skills/{0}",' -f $Name),
        ('  "target": ".claude/skills/{0}",' -f $Name),
        ('  "content_sha256": "{0}"' -f $Digest),
        '}',
        ''
    ) -join "`n")
}

function Read-AdapterMarker {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or (Test-AdapterReparsePoint -Item $item)) { throw "adapter marker is not a regular file" }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "adapter marker contains a BOM" }
    if ($bytes -contains [byte]13) { throw "adapter marker line endings are not canonical" }
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    $text = $encoding.GetString($bytes)
    $marker = $text | ConvertFrom-Json -Depth 10 -ErrorAction Stop
    $expectedFields = @("schema_version", "owner", "adapter_target", "representation", "lifecycle", "source", "target", "content_sha256")
    $actualFields = @($marker.PSObject.Properties.Name)
    if (($actualFields -join "`0") -cne ($expectedFields -join "`0")) { throw "adapter marker schema is invalid" }
    $digest = [string]$marker.content_sha256
    if ([int]$marker.schema_version -ne 1 -or
        [string]$marker.owner -cne "agent-ecosystem" -or
        [string]$marker.adapter_target -cne $script:AdapterTarget -or
        [string]$marker.representation -cne "managed-copy" -or
        [string]$marker.lifecycle -cne "derived" -or
        [string]$marker.source -cne (".agents/skills/{0}" -f $Name) -or
        [string]$marker.target -cne (".claude/skills/{0}" -f $Name) -or
        $digest -cnotmatch '^sha256:[0-9a-f]{64}$') { throw "adapter marker values are invalid" }
    $expectedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes((New-AdapterMarkerText -Name $Name -Digest $digest))
    if ([Convert]::ToHexString($bytes) -cne [Convert]::ToHexString($expectedBytes)) { throw "adapter marker serialization is not canonical" }
    return [ordered]@{ digest = $digest; payload = $marker }
}

function Copy-AdapterTree {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$SourceSnapshot,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    [System.IO.Directory]::CreateDirectory($Destination) | Out-Null
    foreach ($entry in @($SourceSnapshot.entries)) {
        $relativeNative = ([string]$entry.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $targetPath = Join-Path $Destination $relativeNative
        if ([string]$entry.type -ceq "directory") {
            [System.IO.Directory]::CreateDirectory($targetPath) | Out-Null
            continue
        }
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $targetPath)) | Out-Null
        [System.IO.File]::WriteAllBytes($targetPath, [System.IO.File]::ReadAllBytes([string]$entry.full_path))
        Set-AdapterExecutableFlag -Path $targetPath -Executable ([bool]$entry.executable)
    }
}

function Get-AdapterCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][System.IO.FileSystemInfo]$SourceItem,
        [AllowNull()][System.IO.FileSystemInfo]$TargetItem
    )

    $sourceRelative = "$($script:AdapterSourceRoot)/$Name"
    $targetRelative = "$($script:AdapterTargetRoot)/$Name"
    $candidate = [ordered]@{
        name = $Name
        source = $sourceRelative
        target = $targetRelative
        state = "unknown/invalid-ownership"
        action = "none"
        source_exists = ($null -ne $SourceItem)
        target_exists = ($null -ne $TargetItem)
        source_digest = $null
        marker_digest = $null
        target_digest = $null
        source_snapshot = $null
        ownership_valid = $false
        payload_unchanged = $false
        reason_code = "unknown"
    }

    try {
        if (-not (Test-AdapterPortableSegment -Name $Name)) { throw "adapter Skill name is not portable" }
        if ($null -ne $SourceItem) {
            if (-not $SourceItem.PSIsContainer -or (Test-AdapterReparsePoint -Item $SourceItem)) { throw "canonical Skill is not a regular directory" }
            $sourceSnapshot = Get-AdapterTreeSnapshot -Path $SourceItem.FullName -RequireSkill
            $candidate.source_snapshot = $sourceSnapshot
            $candidate.source_digest = [string]$sourceSnapshot.digest
        }
    }
    catch {
        $candidate.reason_code = "invalid-source"
        return $candidate
    }

    if ($null -eq $TargetItem) {
        $candidate.state = "absent"
        $candidate.reason_code = "target-absent"
        return $candidate
    }
    if (Test-AdapterReparsePoint -Item $TargetItem) {
        $candidate.reason_code = "unsafe-target"
        return $candidate
    }
    if (-not $TargetItem.PSIsContainer) {
        $candidate.state = "modified/conflict"
        $candidate.reason_code = "unowned-collision"
        return $candidate
    }

    $markerPath = Join-Path $TargetItem.FullName $script:AdapterMarkerName
    $markerItem = Get-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $markerItem) {
        $candidate.state = "modified/conflict"
        $candidate.reason_code = "unowned-collision"
        return $candidate
    }

    try {
        $marker = Read-AdapterMarker -Path $markerPath -Name $Name
        $candidate.marker_digest = [string]$marker.digest
        $candidate.ownership_valid = $true
        $targetSnapshot = Get-AdapterTreeSnapshot -Path $TargetItem.FullName -ExcludeRootMarker -RequireSkill
        $candidate.target_digest = [string]$targetSnapshot.digest
    }
    catch {
        $candidate.reason_code = "invalid-ownership"
        return $candidate
    }

    if ([string]$candidate.target_digest -cne [string]$candidate.marker_digest) {
        $candidate.state = "modified/conflict"
        $candidate.reason_code = "payload-modified"
        return $candidate
    }
    $candidate.payload_unchanged = $true
    if ($null -eq $SourceItem -or [string]$candidate.source_digest -cne [string]$candidate.marker_digest) {
        $candidate.state = "stale"
        $candidate.reason_code = if ($null -eq $SourceItem) { "source-deleted" } else { "source-changed" }
        return $candidate
    }
    $candidate.state = "current"
    $candidate.reason_code = "digests-match"
    return $candidate
}

function Get-AdapterSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $rootFull = Get-NormalizedFullPath -Path $Root
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) { throw "project root is not a directory" }
    $sourceRoot = Assert-AdapterPathChain -Root $rootFull -RelativePath $script:AdapterSourceRoot -RequireLeaf
    $sourceRootItem = Get-Item -LiteralPath $sourceRoot -Force
    if (-not $sourceRootItem.PSIsContainer) { throw "canonical Skill root is not a directory" }
    $targetRoot = Assert-AdapterPathChain -Root $rootFull -RelativePath $script:AdapterTargetRoot

    $sources = [System.Collections.Generic.Dictionary[string, System.IO.FileSystemInfo]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @(Get-ChildItem -LiteralPath $sourceRoot -Force -ErrorAction Stop)) {
        if (-not $item.PSIsContainer -and -not (Test-AdapterReparsePoint -Item $item)) { continue }
        if ($sources.ContainsKey($item.Name)) { throw "canonical Skill names contain a case-insensitive collision" }
        $sources.Add($item.Name, $item)
    }

    $targets = [System.Collections.Generic.Dictionary[string, System.IO.FileSystemInfo]]::new([StringComparer]::OrdinalIgnoreCase)
    $targetItems = @()
    if (Test-Path -LiteralPath $targetRoot -PathType Container) { $targetItems = @(Get-ChildItem -LiteralPath $targetRoot -Force -ErrorAction Stop) }
    elseif (Test-Path -LiteralPath $targetRoot) { throw "adapter target root is not a directory" }
    foreach ($item in $targetItems) {
        if ($targets.ContainsKey($item.Name)) { throw "adapter targets contain a case-insensitive collision" }
        $targets.Add($item.Name, $item)
    }

    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $sources.Keys) { [void]$names.Add($name) }
    foreach ($item in $targetItems) {
        $mapped = $sources.ContainsKey($item.Name)
        $markerPresent = $false
        if (-not (Test-AdapterReparsePoint -Item $item) -and $item.PSIsContainer) {
            $markerPresent = $null -ne (Get-Item -LiteralPath (Join-Path $item.FullName $script:AdapterMarkerName) -Force -ErrorAction SilentlyContinue)
        }
        if ($mapped -or $markerPresent) { [void]$names.Add($item.Name) }
    }

    $nameArray = [string[]]@($names)
    [Array]::Sort($nameArray, [StringComparer]::Ordinal)
    $candidates = New-Object 'System.Collections.Generic.List[object]'
    foreach ($nameKey in $nameArray) {
        $sourceItem = if ($sources.ContainsKey($nameKey)) { $sources[$nameKey] } else { $null }
        $targetItem = if ($targets.ContainsKey($nameKey)) { $targets[$nameKey] } else { $null }
        $canonicalName = if ($null -ne $sourceItem) { $sourceItem.Name } else { $targetItem.Name }
        if ($null -ne $sourceItem -and $null -ne $targetItem -and [string]$sourceItem.Name -cne [string]$targetItem.Name) {
            $candidate = Get-AdapterCandidate -Root $rootFull -Name $canonicalName -SourceItem $sourceItem -TargetItem $targetItem
            $candidate.state = "unknown/invalid-ownership"
            $candidate.reason_code = "case-mismatch"
            [void]$candidates.Add($candidate)
            continue
        }
        [void]$candidates.Add((Get-AdapterCandidate -Root $rootFull -Name $canonicalName -SourceItem $sourceItem -TargetItem $targetItem))
    }
    return [ordered]@{ root = $rootFull; source_root = $sourceRoot; target_root = $targetRoot; candidates = @($candidates.ToArray()) }
}

function Get-AdapterPublicItems {
    param([object[]]$Candidates = @())

    return @($Candidates | ForEach-Object {
        [ordered]@{
            name = [string]$_.name
            source = [string]$_.source
            target = [string]$_.target
            state = [string]$_.state
            action = [string]$_.action
            content_sha256 = $(if ($null -ne $_.source_digest) { [string]$_.source_digest } else { [string]$_.marker_digest })
            reason_code = [string]$_.reason_code
        }
    })
}

function Get-AdapterSnapshotKey {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Snapshot)

    $lines = @($Snapshot.candidates | ForEach-Object {
        "{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f $_.name, $_.state, $_.source_exists, $_.target_exists, $_.source_digest, $_.marker_digest, $_.target_digest
    })
    return ($lines -join "`n")
}

function Get-AdapterOverallState {
    param([object[]]$Candidates = @())

    foreach ($state in @("unknown/invalid-ownership", "modified/conflict", "stale", "current", "absent")) {
        if (@($Candidates | Where-Object { [string]$_.state -ceq $state }).Count -gt 0) { return $state }
    }
    return "absent"
}

function Remove-AdapterTransactionRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$TransactionRoot
    )

    $rootFull = Get-NormalizedFullPath -Path $Root
    $transactionFull = Get-NormalizedFullPath -Path $TransactionRoot
    if (-not (Test-PathIsEqualOrChild -Path $transactionFull -Root $rootFull) -or [IO.Path]::GetFileName($transactionFull) -cnotmatch '^\.agent-ecosystem-adapter-transaction-[0-9a-f]{32}$') {
        throw "adapter transaction cleanup path is unsafe"
    }
    if (Test-Path -LiteralPath $transactionFull) { [System.IO.Directory]::Delete($transactionFull, $true) }
}

function Remove-AdapterCreatedParents {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][bool]$ClaudeCreated,
        [Parameter(Mandatory = $true)][bool]$SkillsCreated
    )

    $skillsPath = Join-Path $Root ".claude/skills"
    $claudePath = Join-Path $Root ".claude"
    if ($SkillsCreated -and (Test-Path -LiteralPath $skillsPath -PathType Container) -and @(Get-ChildItem -LiteralPath $skillsPath -Force).Count -eq 0) { [System.IO.Directory]::Delete($skillsPath) }
    if ($ClaudeCreated -and (Test-Path -LiteralPath $claudePath -PathType Container) -and @(Get-ChildItem -LiteralPath $claudePath -Force).Count -eq 0) { [System.IO.Directory]::Delete($claudePath) }
}

function Build-AdapterStagedOutputs {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Snapshot,
        [Parameter(Mandatory = $true)][string]$TransactionRoot
    )

    $stagedRoot = Join-Path $TransactionRoot "staged"
    [System.IO.Directory]::CreateDirectory($stagedRoot) | Out-Null
    foreach ($candidate in @($Snapshot.candidates | Where-Object { [string]$_.action -in @("create", "replace") })) {
        $stagedPath = Join-Path $stagedRoot ([string]$candidate.name)
        Copy-AdapterTree -SourceSnapshot $candidate.source_snapshot -Destination $stagedPath
        $markerText = New-AdapterMarkerText -Name ([string]$candidate.name) -Digest ([string]$candidate.source_digest)
        [System.IO.File]::WriteAllBytes((Join-Path $stagedPath $script:AdapterMarkerName), [System.Text.UTF8Encoding]::new($false).GetBytes($markerText))
        $marker = Read-AdapterMarker -Path (Join-Path $stagedPath $script:AdapterMarkerName) -Name ([string]$candidate.name)
        $payload = Get-AdapterTreeSnapshot -Path $stagedPath -ExcludeRootMarker -RequireSkill
        if ([string]$marker.digest -cne [string]$candidate.source_digest -or [string]$payload.digest -cne [string]$candidate.source_digest) { throw "staged adapter validation failed" }
        $candidate.staged_path = $stagedPath
    }
}

function Restore-AdapterTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Records
    )

    $recoveryRoot = Join-Path $TransactionRoot "recovery"
    [System.IO.Directory]::CreateDirectory($recoveryRoot) | Out-Null
    $restored = $true
    $recordArray = @($Records)
    [Array]::Reverse($recordArray)
    foreach ($record in $recordArray) {
        try {
            if ([bool]$record.installed -and (Test-Path -LiteralPath ([string]$record.target))) {
                $installedSnapshot = Get-AdapterTreeSnapshot -Path ([string]$record.target) -ExcludeRootMarker -RequireSkill
                $installedMarker = Read-AdapterMarker -Path (Join-Path ([string]$record.target) $script:AdapterMarkerName) -Name ([string]$record.name)
                if ([string]$installedSnapshot.digest -cne [string]$record.expected_digest -or [string]$installedMarker.digest -cne [string]$record.expected_digest) { throw "installed output changed before rollback" }
                Move-Item -LiteralPath ([string]$record.target) -Destination (Join-Path $recoveryRoot ([string]$record.name)) -ErrorAction Stop
            }
            if ([bool]$record.backup_moved) {
                if (Test-Path -LiteralPath ([string]$record.target)) { throw "rollback target is occupied" }
                Move-Item -LiteralPath ([string]$record.backup) -Destination ([string]$record.target) -ErrorAction Stop
            }
        }
        catch { $restored = $false }
    }
    return $restored
}

function Invoke-AdapterReplacementTransaction {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Snapshot,
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [ValidateRange(0, 1000)][int]$FailureAfterReplacement = 0
    )

    $targetRoot = [string]$Snapshot.target_root
    $claudePath = Join-Path ([string]$Snapshot.root) ".claude"
    $claudeCreated = -not (Test-Path -LiteralPath $claudePath)
    $skillsCreated = -not (Test-Path -LiteralPath $targetRoot)
    $records = New-Object 'System.Collections.Generic.List[object]'
    $backupRoot = Join-Path $TransactionRoot "backup"
    [System.IO.Directory]::CreateDirectory($backupRoot) | Out-Null
    $replacementCount = 0
    try {
        Assert-AdapterPathChain -Root ([string]$Snapshot.root) -RelativePath $script:AdapterTargetRoot | Out-Null
        [System.IO.Directory]::CreateDirectory($targetRoot) | Out-Null
        Assert-AdapterPathChain -Root ([string]$Snapshot.root) -RelativePath $script:AdapterTargetRoot -RequireLeaf | Out-Null
        foreach ($candidate in @($Snapshot.candidates | Where-Object { [string]$_.action -in @("create", "replace", "remove") })) {
            $targetPath = Join-Path $targetRoot ([string]$candidate.name)
            $backupPath = Join-Path $backupRoot ([string]$candidate.name)
            $record = [ordered]@{ name = [string]$candidate.name; target = $targetPath; backup = $backupPath; backup_moved = $false; installed = $false; expected_digest = [string]$candidate.source_digest }
            [void]$records.Add($record)
            if ([string]$candidate.action -in @("replace", "remove")) {
                Move-Item -LiteralPath $targetPath -Destination $backupPath -ErrorAction Stop
                $record.backup_moved = $true
            }
            if ([string]$candidate.action -in @("create", "replace")) {
                Move-Item -LiteralPath ([string]$candidate.staged_path) -Destination $targetPath -ErrorAction Stop
                $record.installed = $true
                $installed = Get-AdapterTreeSnapshot -Path $targetPath -ExcludeRootMarker -RequireSkill
                $marker = Read-AdapterMarker -Path (Join-Path $targetPath $script:AdapterMarkerName) -Name ([string]$candidate.name)
                if ([string]$installed.digest -cne [string]$candidate.source_digest -or [string]$marker.digest -cne [string]$candidate.source_digest) { throw "installed adapter validation failed" }
            }
            elseif (Test-Path -LiteralPath $targetPath) { throw "adapter remove did not detach the owned output" }
            $replacementCount++
            if ($FailureAfterReplacement -gt 0 -and $replacementCount -eq $FailureAfterReplacement) { throw "injected adapter replacement failure" }
        }
        return [ordered]@{ success = $true; rollback = "not-required"; replacements = $replacementCount; records = @($records.ToArray()); claude_created = $claudeCreated; skills_created = $skillsCreated }
    }
    catch {
        $restored = Restore-AdapterTransaction -TransactionRoot $TransactionRoot -Records @($records.ToArray())
        try { Remove-AdapterCreatedParents -Root ([string]$Snapshot.root) -ClaudeCreated $claudeCreated -SkillsCreated $skillsCreated } catch { $restored = $false }
        return [ordered]@{ success = $false; rollback = if ($restored) { "restored" } else { "failed" }; replacements = $replacementCount; records = @($records.ToArray()); claude_created = $claudeCreated; skills_created = $skillsCreated }
    }
}

function Set-AdapterPlanActions {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Snapshot
    )

    $blockers = New-Object 'System.Collections.Generic.List[object]'
    foreach ($candidate in @($Snapshot.candidates)) {
        switch ($Operation) {
            "create-adapter" {
                if ([string]$candidate.state -ceq "absent") { $candidate.action = "create" }
                elseif ([string]$candidate.state -ceq "current") { $candidate.action = "unchanged" }
                else { [void]$blockers.Add($candidate) }
            }
            "rebuild-adapter" {
                if ([string]$candidate.state -ceq "absent") { $candidate.action = "create" }
                elseif ([string]$candidate.state -ceq "current") { $candidate.action = "unchanged" }
                elseif ([string]$candidate.state -ceq "stale" -and [bool]$candidate.source_exists) { $candidate.action = "replace" }
                elseif ([string]$candidate.state -ceq "stale") { $candidate.action = "retain-stale" }
                else { [void]$blockers.Add($candidate) }
            }
            "remove-adapter" {
                if ([string]$candidate.state -ceq "absent") { $candidate.action = "absent" }
                elseif ([string]$candidate.state -in @("current", "stale") -and [bool]$candidate.ownership_valid -and [bool]$candidate.payload_unchanged) { $candidate.action = "remove" }
                else { [void]$blockers.Add($candidate) }
            }
        }
    }
    return @($blockers.ToArray())
}

function Invoke-AdapterStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Snapshot
    )

    return [ordered]@{
        operation = $Operation
        status = "PASS"
        read_only = $true
        adapter_target = $script:AdapterTarget
        supported_adapter_targets = @($script:SupportedAdapterTargets)
        representation = "managed-copy"
        lifecycle = "derived"
        canonical_source = $script:AdapterSourceRoot
        target_root = $script:AdapterTargetRoot
        path = $script:AdapterTargetRoot
        result = "status"
        overall_state = Get-AdapterOverallState -Candidates $Snapshot.candidates
        items = @(Get-AdapterPublicItems -Candidates $Snapshot.candidates)
        findings = @()
    }
}

function Invoke-AdapterMutation {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Snapshot,
        [ValidateRange(0, 1000)][int]$FailureAfterReplacement = 0
    )

    $blockers = @(Set-AdapterPlanActions -Operation $Operation -Snapshot $Snapshot)
    if ($blockers.Count -gt 0) {
        return New-AdapterFailure -Operation $Operation -ReadOnly $false -Code "adapter-preflight-blocked" -Message "Adapter mutation was blocked before writes by a stale, modified, conflicting, or unknown candidate." -Items (Get-AdapterPublicItems -Candidates $Snapshot.candidates) -Extra ([ordered]@{ preflight_complete = $true; mutation_started = $false; rollback = "not-required" })
    }

    $mutationCandidates = @($Snapshot.candidates | Where-Object { [string]$_.action -in @("create", "replace", "remove") })
    if ($mutationCandidates.Count -eq 0) {
        $resultName = if ($Operation -ceq "remove-adapter") { "absent" } else { "unchanged" }
        return [ordered]@{
            operation = $Operation; status = "PASS"; read_only = $false; adapter_target = $script:AdapterTarget
            supported_adapter_targets = @($script:SupportedAdapterTargets); representation = "managed-copy"; lifecycle = "derived"
            canonical_source = $script:AdapterSourceRoot; target_root = $script:AdapterTargetRoot; path = $script:AdapterTargetRoot
            result = $resultName; preflight_complete = $true; mutation_started = $false; rollback = "not-required"
            items = @(Get-AdapterPublicItems -Candidates $Snapshot.candidates); findings = @()
        }
    }

    $transactionRoot = Join-Path ([string]$Snapshot.root) (".agent-ecosystem-adapter-transaction-{0}" -f ([Guid]::NewGuid().ToString("N")))
    $transaction = $null
    try {
        [System.IO.Directory]::CreateDirectory($transactionRoot) | Out-Null
        if ($Operation -in @("create-adapter", "rebuild-adapter")) { Build-AdapterStagedOutputs -Snapshot $Snapshot -TransactionRoot $transactionRoot }
        $fresh = Get-AdapterSnapshot -Root ([string]$Snapshot.root)
        if ((Get-AdapterSnapshotKey -Snapshot $fresh) -cne (Get-AdapterSnapshotKey -Snapshot $Snapshot)) { throw "adapter candidate set changed after preflight" }
        $transaction = Invoke-AdapterReplacementTransaction -Snapshot $Snapshot -TransactionRoot $transactionRoot -FailureAfterReplacement $FailureAfterReplacement
        if (-not [bool]$transaction.success) {
            return New-AdapterFailure -Operation $Operation -ReadOnly $false -Code "adapter-replacement-failed" -Message "Adapter replacement failed and rollback was attempted." -Items (Get-AdapterPublicItems -Candidates $Snapshot.candidates) -Extra ([ordered]@{ preflight_complete = $true; mutation_started = $true; rollback = [string]$transaction.rollback; partial_success = $false })
        }
        $finalSnapshot = Get-AdapterSnapshot -Root ([string]$Snapshot.root)
        if ($Operation -in @("create-adapter", "rebuild-adapter")) {
            $unexpected = @($finalSnapshot.candidates | Where-Object { [bool]$_.source_exists -and [string]$_.state -cne "current" })
            if ($unexpected.Count -gt 0) { throw "adapter post-mutation validation failed" }
        }
        elseif (@($finalSnapshot.candidates | Where-Object { [bool]$_.target_exists }).Count -gt 0) { throw "adapter remove post-mutation validation failed" }
        $resultName = if ($Operation -ceq "create-adapter") { "created" } elseif ($Operation -ceq "rebuild-adapter") { "rebuilt" } else { "removed" }
        $result = [ordered]@{
            operation = $Operation; status = "PASS"; read_only = $false; adapter_target = $script:AdapterTarget
            supported_adapter_targets = @($script:SupportedAdapterTargets); representation = "managed-copy"; lifecycle = "derived"
            canonical_source = $script:AdapterSourceRoot; target_root = $script:AdapterTargetRoot; path = $script:AdapterTargetRoot
            result = $resultName; preflight_complete = $true; mutation_started = $true; rollback = "not-required"; partial_success = $false
            items = @(Get-AdapterPublicItems -Candidates $finalSnapshot.candidates); findings = @()
        }
        try { Remove-AdapterTransactionRoot -Root ([string]$Snapshot.root) -TransactionRoot $transactionRoot } catch { $result.findings = @((New-AdapterFinding -Code "transaction-cleanup-deferred" -Path "" -Message "Validated adapter outputs were installed, but temporary transaction cleanup was deferred." -Severity warning)) }
        return $result
    }
    catch {
        $mutationStarted = ($null -ne $transaction -and [bool]$transaction.success)
        $rollback = "not-required"
        if ($mutationStarted) {
            $restored = Restore-AdapterTransaction -TransactionRoot $transactionRoot -Records @($transaction.records)
            try { Remove-AdapterCreatedParents -Root ([string]$Snapshot.root) -ClaudeCreated ([bool]$transaction.claude_created) -SkillsCreated ([bool]$transaction.skills_created) } catch { $restored = $false }
            $rollback = if ($restored) { "restored" } else { "failed" }
        }
        if (Test-Path -LiteralPath $transactionRoot) {
            try { Remove-AdapterTransactionRoot -Root ([string]$Snapshot.root) -TransactionRoot $transactionRoot } catch { }
        }
        return New-AdapterFailure -Operation $Operation -ReadOnly $false -Code "adapter-transaction-failed" -Message "Adapter transaction failed closed before reporting success." -Items (Get-AdapterPublicItems -Candidates $Snapshot.candidates) -Extra ([ordered]@{ preflight_complete = $true; mutation_started = $mutationStarted; rollback = $rollback; partial_success = $false })
    }
    finally {
        if (Test-Path -LiteralPath $transactionRoot) {
            try { Remove-AdapterTransactionRoot -Root ([string]$Snapshot.root) -TransactionRoot $transactionRoot } catch { }
        }
    }
}

function Invoke-AdapterOperation {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Root,
        [AllowEmptyString()][string]$Target = "",
        [System.Collections.IDictionary]$BoundParameters = $null,
        [switch]$Json,
        [ValidateRange(0, 1000)][int]$FailureAfterReplacement = 0
    )

    $readOnly = ($Operation -ceq "status-adapter")
    if ($null -ne $BoundParameters) {
        try { Assert-AdapterOperationParameters -BoundParameters $BoundParameters }
        catch { return New-AdapterFailure -Operation $Operation -ReadOnly $readOnly -Code "invalid-parameters" -Message "Adapter operation received unsupported parameters." }
    }
    if ([string]::IsNullOrWhiteSpace($Target)) { return New-AdapterFailure -Operation $Operation -ReadOnly $readOnly -Code "adapter-target-required" -Message "Adapter operation requires -Target claude-code." }
    if ($Target -cne $script:AdapterTarget) { return New-AdapterFailure -Operation $Operation -ReadOnly $readOnly -Code "unsupported-adapter-target" -Message "Only the claude-code adapter target is supported." }
    try { $snapshot = Get-AdapterSnapshot -Root $Root }
    catch { return New-AdapterFailure -Operation $Operation -ReadOnly $readOnly -Code "adapter-workspace-unsafe" -Message "Project adapter source or target paths are missing, unsafe, linked, or otherwise invalid." }
    if ($readOnly) { return Invoke-AdapterStatus -Operation $Operation -Snapshot $snapshot }
    return Invoke-AdapterMutation -Operation $Operation -Snapshot $snapshot -FailureAfterReplacement $FailureAfterReplacement
}
