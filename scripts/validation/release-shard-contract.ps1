# release-shard-contract.ps1
# Defines the schema-2 product-runtime and repository-checkpoint authority profiles.

function Get-ReleaseShardContract {
    param([string]$ContractPath = (Join-Path $PSScriptRoot "release-shard-contract.json"))

    $contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json
    if ([int]$contract.schema_version -ne 2) { throw "Unsupported release shard contract schema version." }

    $knownShards = @("PlatformNeutral", "RuntimePlatform", "RepositoryCheckpointNeutral", "RepositoryCheckpointRuntime")
    $allContractChecks = @($knownShards | ForEach-Object { @($contract.shards.PSObject.Properties[$_].Value.checks) } | ForEach-Object { [string]$_ })
    foreach ($property in @($contract.merged_checks.PSObject.Properties)) {
        if ([string]::IsNullOrWhiteSpace([string]$property.Name) -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            throw "Merged release checks must define non-empty source and authority names."
        }
        if ($allContractChecks -cnotcontains [string]$property.Value) {
            throw "Merged release check '$($property.Name)' targets unknown authority '$($property.Value)'."
        }
        if ($allContractChecks -ccontains [string]$property.Name) {
            throw "Merged release check '$($property.Name)' must not remain independently routed."
        }
    }
    foreach ($shardName in $knownShards) {
        $shard = $contract.shards.PSObject.Properties[$shardName].Value
        $checks = @($shard.checks | ForEach-Object { [string]$_ })
        if ($checks.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$shard.authority) -or [string]::IsNullOrWhiteSpace([string]$shard.responsibility)) {
            throw "Release shard '$shardName' must define authority, responsibility, and checks."
        }
        if (@($checks | Group-Object | Where-Object Count -ne 1).Count -gt 0) { throw "Release shard '$shardName' contains duplicate check names." }
    }
    foreach ($profileName in @("Full", "RepositoryCheckpoint")) {
        $profileShards = @($contract.profiles.PSObject.Properties[$profileName].Value | ForEach-Object { [string]$_ })
        if ($profileShards.Count -ne 2 -or @($profileShards | Where-Object { $knownShards -cnotcontains $_ }).Count -gt 0) {
            throw "Release profile '$profileName' must reference exactly two known shards."
        }
        $profileChecks = @($profileShards | ForEach-Object { @($contract.shards.PSObject.Properties[$_].Value.checks) })
        if (@($profileChecks | Group-Object | Where-Object Count -ne 1).Count -gt 0) { throw "Release profile '$profileName' assigns a check to multiple shards." }
    }
    $runtime = @($contract.shards.RuntimePlatform.checks | ForEach-Object { [string]$_ })
    foreach ($required in @($contract.required_runtime_checks)) {
        if ($runtime -cnotcontains [string]$required) { throw "Required runtime check '$required' is not owned by RuntimePlatform." }
    }
    return $contract
}

function Get-ExpectedReleaseCheckNames {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Full", "PlatformNeutral", "RuntimePlatform", "RepositoryCheckpoint", "RepositoryCheckpointNeutral", "RepositoryCheckpointRuntime")]
        [string]$ValidationShard,
        [object]$Contract = (Get-ReleaseShardContract)
    )

    $profileProperty = $Contract.profiles.PSObject.Properties[$ValidationShard]
    $shardNames = if ($null -ne $profileProperty) { @($profileProperty.Value) } else { @($ValidationShard) }
    return @($shardNames | ForEach-Object { @($Contract.shards.PSObject.Properties[[string]$_].Value.checks) } | ForEach-Object { [string]$_ })
}

function Assert-ReleaseShardCoverage {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Full", "PlatformNeutral", "RuntimePlatform", "RepositoryCheckpoint", "RepositoryCheckpointNeutral", "RepositoryCheckpointRuntime")]
        [string]$ValidationShard,
        [Parameter(Mandatory = $true)][object[]]$Checks
    )

    $contract = Get-ReleaseShardContract
    $expected = @(Get-ExpectedReleaseCheckNames -ValidationShard $ValidationShard -Contract $contract)
    $actual = @($Checks | ForEach-Object { [string]$_.name })
    $duplicates = @($actual | Group-Object | Where-Object Count -ne 1 | ForEach-Object Name)
    $missing = @($expected | Where-Object { $actual -cnotcontains $_ })
    $unexpected = @($actual | Where-Object { $expected -cnotcontains $_ })
    if ($duplicates.Count -gt 0 -or $missing.Count -gt 0 -or $unexpected.Count -gt 0) {
        throw ("Release shard '$ValidationShard' coverage mismatch. duplicates=[{0}] missing=[{1}] unexpected=[{2}]" -f ($duplicates -join ", "), ($missing -join ", "), ($unexpected -join ", "))
    }

    return [ordered]@{
        contract_schema_version = [int]$contract.schema_version
        validation_shard = $ValidationShard
        authority = $(if ($null -ne $contract.shards.PSObject.Properties[$ValidationShard]) { [string]$contract.shards.PSObject.Properties[$ValidationShard].Value.authority } else { [string]$ValidationShard })
        expected_check_count = $expected.Count
        actual_check_count = $actual.Count
        product_platform_neutral_check_count = @($contract.shards.PlatformNeutral.checks).Count
        product_runtime_platform_check_count = @($contract.shards.RuntimePlatform.checks).Count
        product_runtime_full_check_count = @(Get-ExpectedReleaseCheckNames -ValidationShard Full -Contract $contract).Count
        repository_checkpoint_check_count = @(Get-ExpectedReleaseCheckNames -ValidationShard RepositoryCheckpoint -Contract $contract).Count
        status = "PASS"
    }
}
