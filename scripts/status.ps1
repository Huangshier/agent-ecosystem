[CmdletBinding()]
param(
    [string]$RuntimeDir = (Join-Path $HOME ".agents"),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

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
        }
        findings = @()
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
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $Manifest.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    if ($property.Value -is [System.Array]) {
        return ,$property.Value
    }
    return $property.Value
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
    if ($RawValue -isnot [string] -or [string]$RawValue -notmatch $Pattern) {
        Add-RuntimeFinding -List $Findings -Code $InvalidCode -Severity "warning" -Message $InvalidMessage
        return New-ProvenanceValue -Value $null -Reason "invalid-value"
    }
    return New-ProvenanceValue -Value ([string]$RawValue) -Reason "recorded"
}

function Get-RuntimeStatusPayload {
    param([Parameter(Mandatory = $true)][string]$Root)

    $payload = New-RuntimePayload
    $findings = New-Object 'System.Collections.Generic.List[object]'
    $manifestPath = Join-Path $Root "install-manifest.json"

    if (-not (Test-Path -LiteralPath $Root -PathType Container) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.missing" -Severity "warning" -Message "Runtime install manifest was not found."
        $payload.findings = @($findings.ToArray())
        return $payload
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        $payload.runtime.manifest_status = "invalid"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.invalid_json" -Severity "error" -Message "Runtime install manifest is not valid JSON."
        $payload.findings = @($findings.ToArray())
        return $payload
    }

    $rawSchemaVersion = Get-ManifestPropertyValue -Manifest $manifest -Name "schema_version"
    if (-not (Test-IntegerValue -Value $rawSchemaVersion)) {
        $payload.runtime.manifest_status = "invalid"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.schema_invalid" -Severity "error" -Message "Runtime install manifest schema version is invalid."
        $payload.findings = @($findings.ToArray())
        return $payload
    }

    $schemaVersion = [int64]$rawSchemaVersion
    $payload.runtime.manifest_schema_version = $schemaVersion
    if ($schemaVersion -eq 1) {
        $payload.runtime.manifest_status = "legacy"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "legacy-manifest"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "legacy-manifest"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.legacy" -Severity "warning" -Message "Runtime install manifest uses the supported legacy schema."
        $payload.findings = @($findings.ToArray())
        return $payload
    }
    if ($schemaVersion -ne 2) {
        $payload.runtime.manifest_status = "unsupported"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "unsupported-schema"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "unsupported-schema"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.unsupported_schema" -Severity "warning" -Message "Runtime install manifest uses an unsupported schema version."
        $payload.findings = @($findings.ToArray())
        return $payload
    }

    $payload.runtime.manifest_status = "current"
    $hasInvalidField = $false
    $sourceIdentity = Get-ManifestPropertyValue -Manifest $manifest -Name "source_identity"
    if ($sourceIdentity -isnot [string] -or [string]$sourceIdentity -cne "agent-ecosystem") {
        $payload.runtime.manifest_status = "invalid"
        $payload.runtime.release_version = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        $payload.runtime.source_commit = New-ProvenanceValue -Value $null -Reason "manifest-invalid"
        Add-RuntimeFinding -List $findings -Code "runtime.manifest.source_identity_invalid" -Severity "error" -Message "Runtime install manifest source identity is invalid."
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
