[CmdletBinding()]
param(
    [string]$RuntimeDir = (Join-Path $HOME ".agents"),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir "lib/path-guard.ps1")

function New-ProvenanceValue {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    return [ordered]@{
        value = $Value
        reason = $Reason
    }
}

function New-RuntimePayload {
    return [ordered]@{
        schema_version = 1
        runtime = [ordered]@{
            manifest_status = "missing"
            manifest_schema_version = $null
            source_identity = $null
            release_version = New-ProvenanceValue -Value $null -Reason "manifest-missing"
            source_commit = New-ProvenanceValue -Value $null -Reason "manifest-missing"
            install_strategy = $null
            profile = $null
            installed_at_utc = $null
            managed_files = [ordered]@{
                status = "unknown"
                reason = "manifest-missing"
                tracked_item_count = 0
                tracked_file_count = 0
                counts = [ordered]@{ current = 0; modified = 0; missing = 0; conflict = 0; unknown = 0 }
                problems = @()
            }
        }
        bridge = [ordered]@{
            status = "not-configured"
            manifest_status = "missing"
            configured_count = 0
            counts = [ordered]@{
                current = 0
                stale = 0
                broken = 0
                conflict = 0
                unknown = 0
            }
            skills = @()
        }
        findings = @()
    }
}

function Test-ReparsePoint {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item)
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-StatusItem {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Get-StatusLinkMode {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item)
    $property = $Item.PSObject.Properties["LinkType"]
    if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        return ([string]$property.Value).ToLowerInvariant()
    }
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) { return "junction" }
    return "symboliclink"
}

function Set-BridgeStatus {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$Root,
        [AllowNull()][object]$InstallManifest,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $bridgeManifestPath = Join-Path $Root "agent-skill-bridge-manifest.json"
    $bridgeManifestItem = Get-StatusItem -Path $bridgeManifestPath
    if ($null -eq $bridgeManifestItem) {
        return
    }
    if ($bridgeManifestItem.PSIsContainer -or (Test-ReparsePoint -Item $bridgeManifestItem)) {
        $Payload.bridge.status = "unknown"
        $Payload.bridge.manifest_status = "invalid"
        Add-RuntimeFinding -List $Findings -Code "bridge.manifest.invalid" -Severity "error" -Message "The Agent skill bridge manifest is not a trusted regular file."
        return
    }

    try {
        $bridgeManifest = [System.IO.File]::ReadAllText($bridgeManifestPath) | ConvertFrom-Json
    }
    catch {
        $Payload.bridge.status = "unknown"
        $Payload.bridge.manifest_status = "invalid"
        Add-RuntimeFinding -List $Findings -Code "bridge.manifest.invalid" -Severity "error" -Message "The Agent skill bridge manifest is not valid JSON."
        return
    }
    if (-not (Test-ManifestObject -Value $bridgeManifest)) {
        $Payload.bridge.status = "unknown"
        $Payload.bridge.manifest_status = "invalid"
        Add-RuntimeFinding -List $Findings -Code "bridge.manifest.invalid" -Severity "error" -Message "The Agent skill bridge manifest must be a JSON object."
        return
    }

    $schemaVersion = Get-ManifestPropertyValue -Manifest $bridgeManifest -Name "schema_version"
    $metadataKind = Get-ManifestPropertyValue -Manifest $bridgeManifest -Name "metadata_kind"
    if (-not (Test-IntegerValue -Value $schemaVersion) -or [int64]$schemaVersion -ne 1 -or
        $metadataKind -isnot [string] -or [string]$metadataKind -cne "agent-specific-skill-link-bridge") {
        $Payload.bridge.status = "unknown"
        $Payload.bridge.manifest_status = "unsupported"
        Add-RuntimeFinding -List $Findings -Code "bridge.manifest.unsupported" -Severity "error" -Message "The Agent skill bridge manifest uses an unsupported contract."
        return
    }
    if ((Get-ManifestPropertyValue -Manifest $bridgeManifest -Name "local_runtime_metadata") -isnot [bool] -or
        -not [bool](Get-ManifestPropertyValue -Manifest $bridgeManifest -Name "local_runtime_metadata") -or
        (Get-ManifestPropertyValue -Manifest $bridgeManifest -Name "commit_policy") -isnot [string] -or
        [string](Get-ManifestPropertyValue -Manifest $bridgeManifest -Name "commit_policy") -cne "do-not-commit") {
        $Payload.bridge.status = "unknown"
        $Payload.bridge.manifest_status = "invalid"
        Add-RuntimeFinding -List $Findings -Code "bridge.manifest.invalid" -Severity "error" -Message "The Agent skill bridge manifest metadata is invalid."
        return
    }

    $Payload.bridge.manifest_status = "current"
    $manifestRuntime = Get-ManifestPropertyValue -Manifest $bridgeManifest -Name "runtime"
    if ($manifestRuntime -isnot [string]) {
        $Payload.bridge.status = "unknown"
        Add-RuntimeFinding -List $Findings -Code "bridge.manifest.invalid" -Severity "error" -Message "The Agent skill bridge manifest runtime metadata is invalid."
        return
    }
    try { $runtimeMatches = Test-PlatformPathEqual -Left ([string]$manifestRuntime) -Right $Root }
    catch { $runtimeMatches = $false }
    if (-not $runtimeMatches) {
        $Payload.bridge.status = "stale"
        Add-RuntimeFinding -List $Findings -Code "bridge.manifest.runtime_mismatch" -Severity "warning" -Message "The Agent skill bridge manifest belongs to a different runtime."
        return
    }

    $records = Get-ManifestPropertyValue -Manifest $bridgeManifest -Name "bridges"
    if ($records -isnot [System.Array] -or @($records).Count -eq 0) {
        $Payload.bridge.status = "unknown"
        Add-RuntimeFinding -List $Findings -Code "bridge.record.invalid" -Severity "error" -Message "The Agent skill bridge records are invalid."
        return
    }

    $results = New-Object 'System.Collections.Generic.List[object]'
    $seenSkills = New-Object 'System.Collections.Generic.List[string]'
    $ownershipAvailable = $null -ne $InstallManifest -and
        (Get-ManifestPropertyValue -Manifest $InstallManifest -Name "skills") -is [System.Array] -and
        (Get-ManifestPropertyValue -Manifest $InstallManifest -Name "items") -is [System.Array] -and
        (Test-IntegerValue -Value (Get-ManifestPropertyValue -Manifest $InstallManifest -Name "schema_version")) -and
        [int64](Get-ManifestPropertyValue -Manifest $InstallManifest -Name "schema_version") -eq 2 -and
        [string](Get-ManifestPropertyValue -Manifest $InstallManifest -Name "source_identity") -ceq "agent-ecosystem"
    foreach ($record in @($records)) {
        if ($null -eq $record -or $record -is [string] -or $record.GetType().IsPrimitive) {
            Add-RuntimeFinding -List $Findings -Code "bridge.record.invalid" -Severity "error" -Message "An Agent skill bridge record is invalid."
            $results.Add([ordered]@{ skill = "invalid"; status = "unknown"; link_mode = $null })
            continue
        }
        $skill = Get-ManifestPropertyValue -Manifest $record -Name "skill"
        $source = Get-ManifestPropertyValue -Manifest $record -Name "source"
        $target = Get-ManifestPropertyValue -Manifest $record -Name "target"
        if ($skill -isnot [string] -or [string]$skill -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            $source -isnot [string] -or $target -isnot [string] -or
            -not [System.IO.Path]::IsPathRooted([string]$source) -or -not [System.IO.Path]::IsPathRooted([string]$target)) {
            Add-RuntimeFinding -List $Findings -Code "bridge.record.invalid" -Severity "error" -Message "An Agent skill bridge record is invalid."
            $results.Add([ordered]@{ skill = if ($skill -is [string] -and [string]$skill -match '^[A-Za-z0-9][A-Za-z0-9._-]*$') { [string]$skill } else { "invalid" }; status = "unknown"; link_mode = $null })
            continue
        }
        $duplicate = @($seenSkills.ToArray() | Where-Object { [string]::Equals($_, [string]$skill, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if ($duplicate) {
            Add-RuntimeFinding -List $Findings -Code "bridge.record.duplicate" -Severity "error" -Message "An Agent skill bridge record is duplicated."
            $results.Add([ordered]@{ skill = [string]$skill; status = "unknown"; link_mode = $null })
            continue
        }
        $seenSkills.Add([string]$skill)

        $recordStatus = "current"
        $linkMode = $null
        $canonicalSkill = $null
        if ($ownershipAvailable) {
            $skillMatches = @(@($InstallManifest.skills) | Where-Object { $_ -is [string] -and [string]::Equals([string]$_, [string]$skill, [System.StringComparison]::Ordinal) })
            if ($skillMatches.Count -eq 1) { $canonicalSkill = [string]$skillMatches[0] }
        }
        if (-not $ownershipAvailable) {
            $recordStatus = "unknown"
            Add-RuntimeFinding -List $Findings -Code "bridge.record.invalid" -Severity "error" -Message "Runtime ownership is unavailable for an Agent skill bridge record."
        }
        elseif ($null -eq $canonicalSkill) {
            $recordStatus = "stale"
            Add-RuntimeFinding -List $Findings -Code "bridge.skill.not_managed" -Severity "warning" -Message "A configured Agent skill is no longer uniquely managed by this runtime."
        }
        else {
            $managedName = "skills/$canonicalSkill"
            $managedItems = @(@($InstallManifest.items) | Where-Object {
                    $_ -and [string]::Equals([string]$_.name, $managedName, [System.StringComparison]::Ordinal) -and
                    [string]::Equals([string]$_.destination, $managedName, [System.StringComparison]::Ordinal) -and
                    [string]::Equals([string]$_.mode, "copy", [System.StringComparison]::Ordinal) -and [bool]$_.managed
                })
            if ($managedItems.Count -ne 1) {
                $recordStatus = "stale"
                Add-RuntimeFinding -List $Findings -Code "bridge.skill.not_managed" -Severity "warning" -Message "A configured Agent skill is no longer uniquely managed by this runtime."
            }
            else {
                $expectedSource = Get-NormalizedFullPath -Path (Join-PathParts $Root "skills" $canonicalSkill)
                try {
                    $sourceMatches = Test-PlatformPathEqual -Left ([string]$source) -Right $expectedSource
                    $targetPath = Get-NormalizedFullPath -Path ([string]$target)
                    $targetNameMatches = [string]::Equals([System.IO.Path]::GetFileName($targetPath), $canonicalSkill, [System.StringComparison]::Ordinal)
                    $targetOutsideRuntime = -not (Test-PathIsEqualOrChild -Path $targetPath -Root $Root)
                    $targetOutsideSource = -not (Test-PathIsEqualOrChild -Path $targetPath -Root $expectedSource)
                    if ($targetNameMatches -and $targetOutsideRuntime -and $targetOutsideSource) {
                        $physicalParent = Resolve-PhysicalPathForWrite -Path (Split-Path -Parent $targetPath)
                        $targetSafe = -not (Test-PathIsEqualOrChild -Path $physicalParent -Root $Root) -and -not (Test-PathIsEqualOrChild -Path $physicalParent -Root $expectedSource)
                    }
                    else { $targetSafe = $false }
                }
                catch { $sourceMatches = $false; $targetSafe = $false }
                if (-not $targetSafe) {
                    $recordStatus = "unknown"
                    Add-RuntimeFinding -List $Findings -Code "bridge.target.unresolvable" -Severity "error" -Message "A configured Agent skill target cannot be inspected safely."
                }
                elseif (-not $sourceMatches) {
                    $recordStatus = "stale"
                    Add-RuntimeFinding -List $Findings -Code "bridge.source.stale" -Severity "warning" -Message "A configured Agent skill source belongs to an older runtime state."
                }
                else {
                    $sourceItem = Get-StatusItem -Path $expectedSource
                    if ($null -eq $sourceItem -or -not $sourceItem.PSIsContainer -or (Test-ReparsePoint -Item $sourceItem)) {
                        $recordStatus = "broken"
                        Add-RuntimeFinding -List $Findings -Code "bridge.source.missing" -Severity "error" -Message "A managed runtime skill source is missing or unavailable."
                    }
                    else {
                        $targetItem = Get-StatusItem -Path $targetPath
                        if ($null -eq $targetItem) {
                            $recordStatus = "stale"
                            Add-RuntimeFinding -List $Findings -Code "bridge.target.missing" -Severity "warning" -Message "A configured Agent skill target is missing."
                        }
                        elseif (-not (Test-ReparsePoint -Item $targetItem)) {
                            $recordStatus = "conflict"
                            Add-RuntimeFinding -List $Findings -Code "bridge.target.not_link" -Severity "error" -Message "A configured Agent skill target is occupied by non-link content."
                        }
                        else {
                            $linkMode = Get-StatusLinkMode -Item $targetItem
                            try {
                                $actualTarget = Get-ReparsePointTargetPath -Item $targetItem -LinkPath $targetPath
                                $actualExists = $null -ne (Get-StatusItem -Path $actualTarget)
                                if (-not $actualExists) {
                                    $recordStatus = "broken"
                                    Add-RuntimeFinding -List $Findings -Code "bridge.target.broken" -Severity "error" -Message "A configured Agent skill link is broken."
                                }
                                else {
                                    $visited = New-Object 'System.Collections.Generic.List[string]'
                                    $resolvedTarget = Resolve-ExistingPhysicalPath -Path $targetPath -VisitedLinks $visited
                                    if (-not (Test-PlatformPathEqual -Left $resolvedTarget -Right $expectedSource)) {
                                        $recordStatus = "conflict"
                                        Add-RuntimeFinding -List $Findings -Code "bridge.target.unexpected" -Severity "error" -Message "A configured Agent skill link points to unexpected content."
                                    }
                                }
                            }
                            catch {
                                if ($recordStatus -eq "current") {
                                    $recordStatus = "unknown"
                                    Add-RuntimeFinding -List $Findings -Code "bridge.target.unresolvable" -Severity "error" -Message "A configured Agent skill link cannot be resolved safely."
                                }
                            }
                        }
                    }
                }
            }
        }
        $results.Add([ordered]@{ skill = [string]$skill; status = $recordStatus; link_mode = $linkMode })
    }

    $Payload.bridge.skills = @($results.ToArray() | Sort-Object { [string]$_.skill })
    $Payload.bridge.configured_count = @($Payload.bridge.skills).Count
    foreach ($status in @("current", "stale", "broken", "conflict", "unknown")) {
        $Payload.bridge.counts[$status] = @($Payload.bridge.skills | Where-Object { [string]$_.status -eq $status }).Count
    }
    foreach ($status in @("conflict", "broken", "stale", "unknown", "current")) {
        if ([int]$Payload.bridge.counts[$status] -gt 0) { $Payload.bridge.status = $status; break }
    }
}

function Add-RuntimeFinding {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$List,
        [Parameter(Mandatory = $true)][string]$Code,
        [ValidateSet("info", "warning", "error")][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $List.Add([object][ordered]@{
            code = $Code
            severity = $Severity
            message = $Message
        })
}

function Test-IntegerValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    return [System.Type]::GetTypeCode($Value.GetType()) -in @(
        [System.TypeCode]::Byte,
        [System.TypeCode]::SByte,
        [System.TypeCode]::Int16,
        [System.TypeCode]::UInt16,
        [System.TypeCode]::Int32,
        [System.TypeCode]::UInt32,
        [System.TypeCode]::Int64,
        [System.TypeCode]::UInt64
    )
}

function Get-ManifestPropertyValue {
    param(
        [AllowNull()][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Manifest) {
        return $null
    }
    $property = $Manifest.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    if ($property.Value -is [System.Array]) {
        return ,$property.Value
    }
    return $property.Value
}

function Test-ManifestObject {
    param([AllowNull()][object]$Value)

    return $null -ne $Value -and
        $Value -isnot [System.Array] -and
        $Value -isnot [string] -and
        -not $Value.GetType().IsPrimitive -and
        $Value -isnot [System.ValueType]
}

function Get-ProvenanceValue {
    param(
        [AllowNull()][object]$RawValue,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$InvalidCode,
        [Parameter(Mandatory = $true)][string]$InvalidMessage,
        [Parameter(Mandatory = $true)][string]$MissingCode,
        [Parameter(Mandatory = $true)][string]$MissingMessage,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    if ($null -eq $RawValue) {
        Add-RuntimeFinding -List $Findings -Code $MissingCode -Severity "info" -Message $MissingMessage
        return New-ProvenanceValue -Value $null -Reason "not-recorded"
    }
    if ($RawValue -isnot [string] -or [string]$RawValue -cnotmatch $Pattern) {
        Add-RuntimeFinding -List $Findings -Code $InvalidCode -Severity "warning" -Message $InvalidMessage
        return New-ProvenanceValue -Value $null -Reason "invalid-value"
    }
    return New-ProvenanceValue -Value ([string]$RawValue) -Reason "recorded"
}

function Set-ManagedFilesUnavailable {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings,
        [string]$Code,
        [ValidateSet("info", "warning", "error")][string]$Severity = "error",
        [string]$Message
    )
    $Payload.runtime.managed_files.status = "unknown"
    $Payload.runtime.managed_files.reason = $Reason
    foreach ($status in @("current", "modified", "missing", "conflict", "unknown")) {
        $Payload.runtime.managed_files.counts[$status] = 0
    }
    $Payload.runtime.managed_files.counts.unknown = [int]$Payload.runtime.managed_files.tracked_file_count
    $Payload.runtime.managed_files.problems = @()
    if (-not [string]::IsNullOrWhiteSpace($Code)) {
        Add-RuntimeFinding -List $Findings -Code $Code -Severity $Severity -Message $Message
    }
}

function Test-CanonicalManagedPath {
    param([AllowNull()][object]$Value)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $false }
    $path = [string]$Value
    return -not [System.IO.Path]::IsPathRooted($path) -and
        $path -cnotmatch '\\' -and $path -cnotmatch '(^|/)\.{1,2}(/|$)' -and
        $path -cnotmatch '//|^/|/$' -and $path -cmatch '^[^:]+$'
}

function Set-ManagedFilesStatus {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $managed = $Payload.runtime.managed_files
    if ([string]$Payload.runtime.install_strategy -eq "dev-link") {
        Set-ManagedFilesUnavailable -Payload $Payload -Reason "dev-link-source-not-recorded" -Findings $Findings `
            -Code "runtime.managed.dev_link_unverifiable" -Severity "info" -Message "Managed files cannot be verified for a development-link runtime."
        return
    }
    if ([string]$Payload.runtime.install_strategy -ne "copy") {
        Set-ManagedFilesUnavailable -Payload $Payload -Reason "contract-invalid" -Findings $Findings `
            -Code "runtime.managed.contract_invalid" -Message "The managed file contract is invalid."
        return
    }

    $items = Get-ManifestPropertyValue -Manifest $Manifest -Name "items"
    if ($items -isnot [System.Array]) {
        Set-ManagedFilesUnavailable -Payload $Payload -Reason "contract-invalid" -Findings $Findings `
            -Code "runtime.managed.contract_invalid" -Message "The managed file contract is invalid."
        return
    }

    $records = New-Object 'System.Collections.Generic.List[object]'
    $seenItems = New-Object 'System.Collections.Generic.List[string]'
    $seenPaths = New-Object 'System.Collections.Generic.List[string]'
    $contractInvalid = $false
    foreach ($item in @($items)) {
        if (-not (Test-ManifestObject -Value $item)) { $contractInvalid = $true; break }
        $destination = Get-ManifestPropertyValue -Manifest $item -Name "destination"
        $mode = Get-ManifestPropertyValue -Manifest $item -Name "mode"
        $isManaged = Get-ManifestPropertyValue -Manifest $item -Name "managed"
        $files = Get-ManifestPropertyValue -Manifest $item -Name "files"
        if (-not (Test-CanonicalManagedPath -Value $destination) -or $mode -isnot [string] -or [string]$mode -cne "copy" -or
            $isManaged -isnot [bool] -or -not [bool]$isManaged -or $files -isnot [System.Array]) { $contractInvalid = $true; break }
        if (@($seenItems.ToArray() | Where-Object { [string]::Equals($_, [string]$destination, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { $contractInvalid = $true; break }
        $seenItems.Add([string]$destination)
        foreach ($file in @($files)) {
            if (-not (Test-ManifestObject -Value $file)) { $contractInvalid = $true; break }
            $relative = Get-ManifestPropertyValue -Manifest $file -Name "path"
            $sourceHash = Get-ManifestPropertyValue -Manifest $file -Name "source_sha256"
            $installedHash = Get-ManifestPropertyValue -Manifest $file -Name "installed_sha256"
            if (-not (Test-CanonicalManagedPath -Value $relative) -or $installedHash -isnot [string] -or [string]$installedHash -cnotmatch '^[0-9a-f]{64}$' -or
                $sourceHash -isnot [string] -or ([string]$sourceHash -cne "" -and [string]$sourceHash -cnotmatch '^[0-9a-f]{64}$')) { $contractInvalid = $true; break }
            $runtimePath = "{0}/{1}" -f [string]$destination, [string]$relative
            if (@($seenPaths.ToArray() | Where-Object { [string]::Equals($_, $runtimePath, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { $contractInvalid = $true; break }
            $seenPaths.Add($runtimePath)
            $records.Add([ordered]@{ item = [string]$destination; relative = [string]$relative; path = $runtimePath; source = [string]$sourceHash; installed = [string]$installedHash })
        }
        if ($contractInvalid) { break }
    }
    if ($contractInvalid) {
        Set-ManagedFilesUnavailable -Payload $Payload -Reason "contract-invalid" -Findings $Findings `
            -Code "runtime.managed.contract_invalid" -Message "The managed file contract is invalid."
        return
    }

    $managed.tracked_item_count = $seenItems.Count
    $managed.tracked_file_count = $records.Count
    $itemStates = @{}
    try {
        foreach ($destination in @($seenItems.ToArray())) {
            $itemPath = Get-NormalizedFullPath -Path (Join-PathParts $Root $destination)
            if (-not (Test-PathIsEqualOrChild -Path $itemPath -Root $Root)) { throw "unsafe" }
            $itemParent = Split-Path -Parent $itemPath
            $physicalItemParent = Resolve-PhysicalPathForWrite -Path $itemParent
            if (-not (Test-PlatformPathEqual -Left $physicalItemParent -Right $itemParent) -or
                -not (Test-PathIsEqualOrChild -Path $physicalItemParent -Root $Root)) {
                $itemStates[$destination] = "conflict"
                continue
            }
            $item = Get-StatusItem -Path $itemPath
            if ($null -eq $item) { $itemStates[$destination] = "missing"; continue }
            if (-not $item.PSIsContainer -or (Test-ReparsePoint -Item $item)) { $itemStates[$destination] = "conflict"; continue }
            $visited = New-Object 'System.Collections.Generic.List[string]'
            $physical = Resolve-ExistingPhysicalPath -Path $itemPath -VisitedLinks $visited
            if (-not (Test-PlatformPathEqual -Left $physical -Right $itemPath)) { throw "unsafe" }
            $itemStates[$destination] = "directory"
        }
    }
    catch {
        Set-ManagedFilesUnavailable -Payload $Payload -Reason "path-unresolvable" -Findings $Findings `
            -Code "runtime.managed.path_unresolvable" -Message "A managed file path cannot be inspected safely."
        return
    }

    $preflight = New-Object 'System.Collections.Generic.List[object]'
    foreach ($record in @($records.ToArray() | Sort-Object { [string]$_.path })) {
        $status = "current"
        $diverged = [string]$record.source -cne [string]$record.installed
        $itemState = [string]$itemStates[[string]$record.item]
        if ($diverged) { $status = "conflict" }
        elseif ($itemState -eq "missing") { $status = "missing" }
        elseif ($itemState -eq "conflict") { $status = "conflict" }
        else {
            try {
                $filePath = Get-NormalizedFullPath -Path (Join-PathParts $Root ([string]$record.path))
                if (-not (Test-PathIsEqualOrChild -Path $filePath -Root $Root)) { throw "unsafe" }
                $itemPath = Get-NormalizedFullPath -Path (Join-PathParts $Root ([string]$record.item))
                $parent = Split-Path -Parent $filePath
                if (-not (Test-PathIsEqualOrChild -Path $parent -Root $itemPath)) { throw "unsafe" }
                $physicalParent = Resolve-PhysicalPathForWrite -Path $parent
                if (-not (Test-PlatformPathEqual -Left $physicalParent -Right $parent) -or
                    -not (Test-PathIsEqualOrChild -Path $physicalParent -Root $itemPath)) {
                    $status = "conflict"
                }
                if ($status -eq "current") {
                    $leaf = Get-StatusItem -Path $filePath
                    if ($null -eq $leaf) { $status = "missing" }
                    elseif ($leaf.PSIsContainer -or (Test-ReparsePoint -Item $leaf)) { $status = "conflict" }
                }
            }
            catch {
                Set-ManagedFilesUnavailable -Payload $Payload -Reason "path-unresolvable" -Findings $Findings `
                    -Code "runtime.managed.path_unresolvable" -Message "A managed file path cannot be inspected safely."
                return
            }
        }
        $preflight.Add([ordered]@{ record = $record; status = $status })
    }

    $problems = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in @($preflight.ToArray())) {
        $record = $entry.record
        $status = [string]$entry.status
        if ($status -eq "current") {
            try {
                $filePath = Get-NormalizedFullPath -Path (Join-PathParts $Root ([string]$record.path))
                $liveHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($liveHash -cne [string]$record.installed) { $status = "modified" }
            }
            catch {
                Set-ManagedFilesUnavailable -Payload $Payload -Reason "path-unresolvable" -Findings $Findings `
                    -Code "runtime.managed.path_unresolvable" -Message "A managed file path cannot be inspected safely."
                return
            }
        }
        $managed.counts[$status] = [int]$managed.counts[$status] + 1
        if ($status -ne "current") { $problems.Add([ordered]@{ scope = "file"; path = [string]$record.path; status = $status }) }
    }
    foreach ($destination in @($seenItems.ToArray() | Sort-Object)) {
        if (@($records.ToArray() | Where-Object { [string]$_.item -ceq $destination }).Count -gt 0) { continue }
        $itemStatus = [string]$itemStates[$destination]
        if ($itemStatus -eq "directory") { continue }
        $problems.Add([ordered]@{ scope = "item"; path = $destination; status = $itemStatus })
    }
    $managed.problems = @($problems.ToArray())
    $managed.reason = "scanned"
    foreach ($status in @("conflict", "missing", "modified", "unknown", "current")) {
        $hasEmptyItemStatus = @($problems.ToArray() | Where-Object { [string]$_.scope -eq "item" -and [string]$_.status -eq $status }).Count -gt 0
        if ([int]$managed.counts[$status] -gt 0 -or $hasEmptyItemStatus -or ($status -eq "current" -and $records.Count -eq 0)) { $managed.status = $status; break }
    }
    foreach ($status in @("modified", "missing", "conflict")) {
        if ([int]$managed.counts[$status] -gt 0 -or @($managed.problems | Where-Object { [string]$_.status -eq $status }).Count -gt 0) {
            $severity = if ($status -eq "conflict") { "error" } else { "warning" }
            Add-RuntimeFinding -List $Findings -Code "runtime.managed.$status" -Severity $severity -Message "One or more managed runtime files report $status."
        }
    }
}

function Get-RuntimeStatusPayload {
    param([Parameter(Mandatory = $true)][string]$Root)

    $payload = New-RuntimePayload
    $findings = New-Object 'System.Collections.Generic.List[object]'
    $manifestPath = Join-Path $Root "install-manifest.json"

    if (-not (Test-Path -LiteralPath $Root -PathType Container) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.missing" -Severity "warning" -Message "Runtime install manifest was not found."
        Set-BridgeStatus -Payload $payload -Root $Root -InstallManifest $null -Findings $findings
        $payload.findings = @($findings.ToArray())
        return $payload
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        $payload.runtime.manifest_status = "invalid"
        $payload.runtime.managed_files.reason = "manifest-invalid"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.invalid_json" -Severity "error" -Message "Runtime install manifest is not valid JSON."
        Set-BridgeStatus -Payload $payload -Root $Root -InstallManifest $null -Findings $findings
        $payload.findings = @($findings.ToArray())
        return $payload
    }
    if (-not (Test-ManifestObject -Value $manifest)) {
        $payload.runtime.manifest_status = "invalid"
        $payload.runtime.managed_files.reason = "manifest-invalid"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.invalid_type" -Severity "error" -Message "Runtime install manifest must be a JSON object."
        Set-BridgeStatus -Payload $payload -Root $Root -InstallManifest $null -Findings $findings
        $payload.findings = @($findings.ToArray())
        return $payload
    }

    $rawSchemaVersion = Get-ManifestPropertyValue -Manifest $manifest -Name "schema_version"
    if (-not (Test-IntegerValue -Value $rawSchemaVersion)) {
        $payload.runtime.manifest_status = "invalid"
        $payload.runtime.managed_files.reason = "manifest-invalid"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.schema_invalid" -Severity "error" -Message "Runtime install manifest schema version is invalid."
        Set-BridgeStatus -Payload $payload -Root $Root -InstallManifest $manifest -Findings $findings
        $payload.findings = @($findings.ToArray())
        return $payload
    }

    $schemaVersion = [int64]$rawSchemaVersion
    $payload.runtime.manifest_schema_version = $schemaVersion
    if ($schemaVersion -eq 1) {
        $payload.runtime.managed_files.reason = "legacy-manifest"
        $payload.runtime.manifest_status = "legacy"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "legacy-manifest"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "legacy-manifest"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.legacy" -Severity "warning" -Message "Runtime install manifest uses the supported legacy schema."
        Set-BridgeStatus -Payload $payload -Root $Root -InstallManifest $manifest -Findings $findings
        $payload.findings = @($findings.ToArray())
        return $payload
    }
    if ($schemaVersion -ne 2) {
        $payload.runtime.managed_files.reason = "unsupported-schema"
        $payload.runtime.manifest_status = "unsupported"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "unsupported-schema"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "unsupported-schema"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.unsupported_schema" -Severity "warning" -Message "Runtime install manifest uses an unsupported schema version."
        Set-BridgeStatus -Payload $payload -Root $Root -InstallManifest $manifest -Findings $findings
        $payload.findings = @($findings.ToArray())
        return $payload
    }

    $payload.runtime.manifest_status = "current"
    $hasInvalidField = $false
    $sourceIdentity = Get-ManifestPropertyValue -Manifest $manifest -Name "source_identity"
    if ($sourceIdentity -isnot [string] -or [string]$sourceIdentity -cne "agent-ecosystem") {
        $payload.runtime.manifest_status = "invalid"
        $payload.runtime.managed_files.reason = "manifest-invalid"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.source_identity_invalid" -Severity "error" -Message "Runtime install manifest source identity is invalid."
        Set-BridgeStatus -Payload $payload -Root $Root -InstallManifest $null -Findings $findings
        $payload.findings = @($findings.ToArray())
        return $payload
    }
    $payload.runtime.source_identity = "agent-ecosystem"

    $releaseVersion = Get-ProvenanceValue `
        -RawValue (Get-ManifestPropertyValue -Manifest $manifest -Name "release_version") `
        -Pattern '^v\d+\.\d+\.\d+$' `
        -InvalidCode "runtime.provenance.release_invalid" `
        -InvalidMessage "Runtime release provenance is invalid." `
        -MissingCode "runtime.provenance.release_not_recorded" `
        -MissingMessage "Runtime release provenance was not recorded." `
        -Findings $findings
    $payload.runtime.release_version = $releaseVersion
    if ([string]$releaseVersion.reason -eq "invalid-value") { $hasInvalidField = $true }

    $sourceCommit = Get-ProvenanceValue `
        -RawValue (Get-ManifestPropertyValue -Manifest $manifest -Name "source_commit") `
        -Pattern '^[0-9a-fA-F]{40}$' `
        -InvalidCode "runtime.provenance.commit_invalid" `
        -InvalidMessage "Runtime source commit provenance is invalid." `
        -MissingCode "runtime.provenance.commit_not_recorded" `
        -MissingMessage "Runtime source commit provenance was not recorded." `
        -Findings $findings
    if ([string]$sourceCommit.reason -eq "recorded") {
        $sourceCommit.value = ([string]$sourceCommit.value).ToLowerInvariant()
    }
    $payload.runtime.source_commit = $sourceCommit
    if ([string]$sourceCommit.reason -eq "invalid-value") { $hasInvalidField = $true }

    $installStrategy = Get-ManifestPropertyValue -Manifest $manifest -Name "install_strategy"
    if ($installStrategy -is [string] -and [string]$installStrategy -cin @("copy", "dev-link")) {
        $payload.runtime.install_strategy = [string]$installStrategy
    }
    else {
        $hasInvalidField = $true
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.install_strategy_invalid" -Severity "error" -Message "Runtime install strategy is invalid."
    }

    $profile = Get-ManifestPropertyValue -Manifest $manifest -Name "profile"
    if ($profile -is [string] -and [string]$profile -cin @("minimal", "recommended", "full", "dev")) {
        $payload.runtime.profile = [string]$profile
    }
    else {
        $hasInvalidField = $true
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.profile_invalid" -Severity "error" -Message "Runtime profile is invalid."
    }

    $installedAt = Get-ManifestPropertyValue -Manifest $manifest -Name "installed_at_utc"
    $parsedTimestamp = [DateTimeOffset]::MinValue
    $timestampValid = $false
    if ($installedAt -is [DateTime]) {
        $parsedTimestamp = [DateTimeOffset]([DateTime]$installedAt)
        $timestampValid = $true
    }
    elseif ($installedAt -is [DateTimeOffset]) {
        $parsedTimestamp = [DateTimeOffset]$installedAt
        $timestampValid = $true
    }
    elseif ($installedAt -is [string] -and ([string]$installedAt) -match '(Z|[+-]\d{2}:\d{2})$') {
        $timestampValid = [DateTimeOffset]::TryParse(
            [string]$installedAt,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsedTimestamp
        )
    }
    if ($timestampValid) {
        $payload.runtime.installed_at_utc = $parsedTimestamp.UtcDateTime.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    else {
        $hasInvalidField = $true
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.installed_at_invalid" -Severity "error" -Message "Runtime installation timestamp is invalid."
    }

    if ($hasInvalidField) {
        $payload.runtime.manifest_status = "invalid"
    }
    if ($payload.runtime.manifest_status -eq "current") {
        Set-ManagedFilesStatus -Payload $payload -Root $Root -Manifest $manifest -Findings $findings
    }
    else {
        Set-ManagedFilesUnavailable -Payload $payload -Reason "manifest-invalid" -Findings $findings
    }
    Set-BridgeStatus -Payload $payload -Root $Root -InstallManifest $manifest -Findings $findings
    $payload.findings = @($findings.ToArray())
    return $payload
}

function Format-ProvenanceText {
    param(
        [Parameter(Mandatory = $true)][object]$Field,
        [switch]$ShortCommit
    )

    if ([string]$Field.reason -eq "recorded") {
        $value = [string]$Field.value
        if ($ShortCommit.IsPresent -and $value.Length -gt 12) {
            return $value.Substring(0, 12)
        }
        return $value
    }
    if ([string]$Field.reason -eq "not-recorded") {
        return "unknown (not recorded)"
    }
    return "unknown ($([string]$Field.reason))"
}

function Write-RuntimeStatusText {
    param([Parameter(Mandatory = $true)][object]$Payload)

    $runtime = $Payload.runtime
    Write-Output "Runtime manifest: $([string]$runtime.manifest_status)"
    Write-Output "Manifest contract: $([string]$runtime.manifest_status)"
    Write-Output "Release version: $(Format-ProvenanceText -Field $runtime.release_version)"
    Write-Output "Source commit: $(Format-ProvenanceText -Field $runtime.source_commit -ShortCommit)"
    Write-Output "Install strategy: $(if ($null -eq $runtime.install_strategy) { 'unknown' } else { [string]$runtime.install_strategy })"
    Write-Output "Profile: $(if ($null -eq $runtime.profile) { 'unknown' } else { [string]$runtime.profile })"
    Write-Output "Installed at: $(if ($null -eq $runtime.installed_at_utc) { 'unknown' } else { [string]$runtime.installed_at_utc })"
    Write-Output "Managed files: $([string]$runtime.managed_files.status)"
    Write-Output "Managed status reason: $([string]$runtime.managed_files.reason)"
    Write-Output "Tracked managed items: $([int]$runtime.managed_files.tracked_item_count)"
    Write-Output "Tracked managed files: $([int]$runtime.managed_files.tracked_file_count)"
    Write-Output "Managed problems: $(@($runtime.managed_files.problems).Count)"
    foreach ($problem in @($runtime.managed_files.problems)) {
        Write-Output ("- {0}: {1}" -f [string]$problem.path, [string]$problem.status)
    }
    Write-Output "Bridge: $([string]$Payload.bridge.status)"
    Write-Output "Bridge manifest: $([string]$Payload.bridge.manifest_status)"
    Write-Output "Configured skills: $([int]$Payload.bridge.configured_count)"
    foreach ($skill in @($Payload.bridge.skills)) {
        $mode = if ($null -eq $skill.link_mode) { "unknown" } else { [string]$skill.link_mode }
        Write-Output ("- {0}: {1} ({2})" -f [string]$skill.skill, [string]$skill.status, $mode)
    }
    Write-Output "Bridge findings: $(@($Payload.findings | Where-Object { [string]$_.code -like 'bridge.*' }).Count)"
    Write-Output "Findings: $(@($Payload.findings).Count)"
    foreach ($finding in @($Payload.findings)) {
        Write-Output ("- [{0}] {1}: {2}" -f [string]$finding.severity, [string]$finding.code, [string]$finding.message)
    }
}

$runtimeRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RuntimeDir)
$statusPayload = Get-RuntimeStatusPayload -Root $runtimeRoot
if ($Json.IsPresent) {
    $statusPayload | ConvertTo-Json -Depth 8
}
else {
    Write-RuntimeStatusText -Payload $statusPayload
}
