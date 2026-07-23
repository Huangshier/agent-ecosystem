[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidateContractPath,
    [Parameter(Mandatory = $true)][string]$ClassificationPath,
    [Parameter(Mandatory = $true)][string]$FragmentsRoot,
    [Parameter(Mandatory = $true)][string]$GuardBindingPath,
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$RunAttempt,
    [Parameter(Mandatory = $true)][string]$WorkflowIdentity,
    [Parameter(Mandatory = $true)][string]$RoutingContractIdentity,
    [Parameter(Mandatory = $true)][string]$GateContractIdentity,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [ValidateRange(1, 168)][int]$FreshnessHours = 72,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$knownSelfProtectionReasons = @(
    "full-coverage-unproven",
    "unknown-or-ambiguous-input",
    "self-protection-control-surface",
    "not-tier-3",
    "no-control-plane-change"
)

function Read-JsonFile([string]$Path, [string]$Label) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($full)) { throw "$Label does not exist." }
    try { return [System.IO.File]::ReadAllText($full) | ConvertFrom-Json }
    catch { throw "$Label is not valid JSON." }
}
function Get-Sha256Text([string]$Text) {
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant() }
    finally { $hash.Dispose() }
}
function Get-OrdinalStrings([object[]]$Values = @()) {
    $strings = [string[]]@($Values | ForEach-Object { [string]$_ } | Where-Object { $_ })
    [System.Array]::Sort($strings, [System.StringComparer]::Ordinal)
    return @($strings | Select-Object -Unique)
}
function Convert-HostIdentity([object]$Fragment) {
    $hostIdentity = [string]$Fragment.identity.host
    $job = [string]$Fragment.identity.job
    if ($job -ceq "validate-windows-powershell") { return "windows-powershell" }
    if ($hostIdentity.StartsWith("Windows-", [System.StringComparison]::Ordinal)) { return "windows-latest" }
    if ($hostIdentity.StartsWith("Linux-", [System.StringComparison]::Ordinal)) { return "ubuntu-latest" }
    if ($hostIdentity.StartsWith("macOS-", [System.StringComparison]::Ordinal)) { return "macos-latest" }
    if ($hostIdentity -ceq "fixture-host") { return "fixture-host" }
    throw "Evidence fragment contains an unknown host identity '$hostIdentity'."
}

if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or -not $RunId -or -not $RunAttempt) {
    throw "Repository, run ID, and run attempt must be valid and non-empty."
}
$candidate = Read-JsonFile $CandidateContractPath "Candidate contract"
$classification = Read-JsonFile $ClassificationPath "Classification"
$binding = Read-JsonFile $GuardBindingPath "Guard binding"
$fragmentsRootFull = [System.IO.Path]::GetFullPath($FragmentsRoot)
if (-not [System.IO.Directory]::Exists($fragmentsRootFull)) { throw "FragmentsRoot does not exist." }
if ([int]$candidate.schema_version -ne 1 -or [string]$candidate.repository -cne $Repository) { throw "Candidate contract is invalid." }
if ([int]$classification.schema_version -ne 2) { throw "Classifier schema/version is invalid." }
if ([string]$classification.base_ref -cne [string]$candidate.base.sha -or
    [string]$classification.head_ref -cne [string]$candidate.head.sha) {
    throw "Classifier base/head boundary does not match the exact candidate contract."
}
$classifierProperties = [ordered]@{}
foreach ($name in @(
    "conservative_fallback",
    "run_validation_self_protection",
    "validation_self_protection_reason",
    "control_plane",
    "self_protection_required",
    "self_protection_reason"
)) {
    $property = @($classification.PSObject.Properties | Where-Object { $_.Name -ceq $name })
    if ($property.Count -ne 1) { throw "Classifier is missing required authority field '$name'." }
    $classifierProperties[$name] = $property[0].Value
}
foreach ($name in @("conservative_fallback", "run_validation_self_protection", "control_plane", "self_protection_required")) {
    if ($classifierProperties[$name] -isnot [bool]) { throw "Classifier authority field '$name' must be Boolean." }
}
foreach ($name in @("validation_self_protection_reason", "self_protection_reason")) {
    if ($classifierProperties[$name] -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$classifierProperties[$name]) -or
        $knownSelfProtectionReasons -cnotcontains [string]$classifierProperties[$name]) {
        throw "Classifier authority field '$name' must be a known self-protection reason."
    }
}
if ([bool]$classifierProperties.self_protection_required -ne [bool]$classifierProperties.run_validation_self_protection -or
    [string]$classifierProperties.self_protection_reason -cne [string]$classifierProperties.validation_self_protection_reason) {
    throw "Classifier authority fields disagree with the compatibility self-protection contract."
}
if ([bool]$classifierProperties.control_plane -and -not [bool]$classifierProperties.self_protection_required) {
    throw "Classifier control-plane ownership must require self-protection."
}
if ([int]$binding.schema_version -ne 1) { throw "Guard binding schema/version is invalid." }

$fragmentFiles = @(Get-ChildItem -LiteralPath $fragmentsRootFull -Recurse -File -Filter "evidence-manifest.json" | Sort-Object FullName)
if ($fragmentFiles.Count -eq 0) { throw "Canonical evidence requires validation fragments." }
$fragments = New-Object 'System.Collections.Generic.List[object]'
foreach ($file in $fragmentFiles) {
    $fragment = Read-JsonFile $file.FullName "Evidence fragment"
    if ([int]$fragment.schema_version -ne 2 -or [string]$fragment.proof_kind -cne "validation-fragment") { throw "Evidence fragment schema is invalid." }
    if ([string]$fragment.repository -cne $Repository -or [string]$fragment.event_name -cne "pull_request" -or
        [string]$fragment.identity.commit_sha -cne [string]$candidate.candidate.sha -or
        [string]$fragment.identity.run_id -cne $RunId -or [string]$fragment.identity.run_attempt -cne $RunAttempt) {
        throw "Evidence fragment contains mixed repository, candidate, run, or attempt identity."
    }
    if ([string]$fragment.contracts.workflow -cne $WorkflowIdentity -or [string]$fragment.contracts.routing -cne $RoutingContractIdentity -or
        [string]$fragment.contracts.gate -cne $GateContractIdentity) { throw "Evidence fragment contract identity mismatch." }
    if ([string]$fragment.outcome -cne "success") { throw "Canonical evidence cannot include a failed fragment." }
    if ([string]$fragment.candidate.candidate.sha -cne [string]$candidate.candidate.sha -or
        [string]$fragment.candidate.candidate.tree -cne [string]$candidate.candidate.tree -or
        (@($fragment.candidate.candidate.ordered_parents) -join ",") -cne (@($candidate.candidate.ordered_parents) -join ",") -or
        [int]$fragment.candidate.pr_number -ne [int]$candidate.pr_number -or
        [string]$fragment.candidate.base.sha -cne [string]$candidate.base.sha -or
        [string]$fragment.candidate.head.sha -cne [string]$candidate.head.sha -or
        [string]$fragment.candidate.change.combined_digest -cne [string]$candidate.change.combined_digest) {
        throw "Evidence fragment candidate identity mismatch."
    }
    $fragments.Add($fragment)
}
foreach ($name in @("base_guard", "identity_guard", "final_gate")) {
    $entry = $binding.$name
    if ($null -eq $entry -or -not [string]$entry.run_id -or -not [string]$entry.job_id -or [string]$entry.conclusion -cne "success") {
        throw "Binding '$name' lacks an actual successful run/job identity."
    }
    if ([string]$entry.run_attempt -cne $RunAttempt) { throw "Binding '$name' uses a mixed run attempt." }
}
if ([string]$binding.final_gate.run_id -cne $RunId) { throw "Final gate belongs to another run." }
foreach ($name in @("base_guard", "identity_guard", "final_gate")) {
    if ([string]$binding.$name.head_sha -cne [string]$candidate.head.sha -or [int]$binding.$name.pr_number -ne [int]$candidate.pr_number) {
        throw "Binding '$name' does not match PR/head identity."
    }
}

$actualSuites = Get-OrdinalStrings @($fragments.ToArray() | ForEach-Object { @($_.executed.targeted_suite_names) })
$actualHosts = Get-OrdinalStrings @($fragments.ToArray() | ForEach-Object { Convert-HostIdentity $_ })
$requiredSuites = Get-OrdinalStrings @($classification.required_suites)
$requiredHosts = Get-OrdinalStrings @($classification.required_hosts)
if ([bool]$classification.requires_windows_powershell) { $requiredHosts = Get-OrdinalStrings @($requiredHosts + "windows-powershell") }
$missingSuites = @($requiredSuites | Where-Object { $actualSuites -cnotcontains $_ })
$missingHosts = @($requiredHosts | Where-Object { $actualHosts -cnotcontains $_ })
if ($missingSuites.Count -or $missingHosts.Count) { throw "Suite/host closure is incomplete: suites=$($missingSuites -join ','); hosts=$($missingHosts -join ',')." }
$selfProtectionFragments = @($fragments.ToArray() | Where-Object { [string]$_.identity.job -ceq "validation-self-protection" })
if ([bool]$classification.run_validation_self_protection -and $selfProtectionFragments.Count -ne 1) { throw "Self-protection closure is incomplete." }

$artifactDigests = @(Get-ChildItem -LiteralPath $fragmentsRootFull -Recurse -File | Sort-Object FullName | ForEach-Object {
    [ordered]@{
        path = $_.FullName.Substring($fragmentsRootFull.Length).TrimStart([char[]]@('\', '/')).Replace("\", "/")
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
$payload = [ordered]@{
    schema_version = 2; proof_kind = "canonical-candidate-evidence"; repository = $Repository; pr_number = [int]$candidate.pr_number
    base = $candidate.base; head = $candidate.head; candidate = $candidate.candidate; change = $candidate.change
    classifier = [ordered]@{
        schema_version = [int]$classification.schema_version; detected_tier = [int]$classification.detected_tier
        affected_modules = Get-OrdinalStrings @($classification.affected_modules)
        conservative_fallback = [bool]$classifierProperties.conservative_fallback; escalation_reason = [string]$classification.escalation_reason
        control_plane = [bool]$classifierProperties.control_plane
        self_protection_required = [bool]$classifierProperties.self_protection_required
        self_protection_reason = [string]$classifierProperties.self_protection_reason
    }
    required = [ordered]@{
        suites = $requiredSuites; hosts = $requiredHosts; windows_powershell = [bool]$classification.requires_windows_powershell
        self_protection = [bool]$classification.run_validation_self_protection
    }
    actual = [ordered]@{ suites = $actualSuites; hosts = $actualHosts; fragment_count = $fragments.Count }
    decisions = [ordered]@{
        windows_powershell = $(if ([bool]$classification.requires_windows_powershell) { "required-and-passed" } else { "not-required" })
        self_protection = $(if ([bool]$classification.run_validation_self_protection) { "required-and-passed" } else { "not-required" })
    }
    contracts = [ordered]@{ workflow = $WorkflowIdentity; routing = $RoutingContractIdentity; gate = $GateContractIdentity }
    run = [ordered]@{ id = $RunId; attempt = $RunAttempt }
    checks = [ordered]@{ base_guard = $binding.base_guard; identity_guard = $binding.identity_guard; final_gate = $binding.final_gate }
    artifact_digests = $artifactDigests
}
$generated = [DateTimeOffset]::UtcNow
$manifest = [ordered]@{
    schema_version = 2; proof_kind = "canonical-candidate-evidence"; generated_at_utc = $generated.ToString("o")
    freshness = [ordered]@{ status = "fresh"; expires_at_utc = $generated.AddHours($FreshnessHours).ToString("o"); retention_hours = $FreshnessHours }
}
foreach ($key in $payload.Keys | Where-Object { $_ -notin @("schema_version", "proof_kind") }) { $manifest[$key] = $payload[$key] }
$manifest.canonical_evidence_digest = Get-Sha256Text ($payload | ConvertTo-Json -Depth 20 -Compress)
$outputFull = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outputFull)) | Out-Null
$manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outputFull -Encoding UTF8
if ($Json) { $manifest | ConvertTo-Json -Depth 20 } else { Write-Output "Canonical candidate evidence finalized." }
