# release-shard-contract.ps1
# Defines and validates the exact check ownership for Full, PlatformNeutral, and RuntimePlatform.

function Get-ReleaseShardContract {
    param([string]$ContractPath = (Join-Path $PSScriptRoot "release-shard-contract.json"))

    $contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json
    if ([int]$contract.schema_version -ne 1) {
        throw "Unsupported release shard contract schema version."
    }

    $neutral = @($contract.shards.PlatformNeutral.checks | ForEach-Object { [string]$_ })
    $runtime = @($contract.shards.RuntimePlatform.checks | ForEach-Object { [string]$_ })
    if ($neutral.Count -eq 0 -or $runtime.Count -eq 0) {
        throw "Release shard contract must define non-empty PlatformNeutral and RuntimePlatform check lists."
    }
    if (@($neutral | Group-Object | Where-Object Count -ne 1).Count -gt 0 -or
        @($runtime | Group-Object | Where-Object Count -ne 1).Count -gt 0) {
        throw "Release shard contract contains duplicate check names within a shard."
    }
    $intersection = @($neutral | Where-Object { $runtime -ccontains $_ })
    if ($intersection.Count -gt 0) {
        throw ("Release shard contract assigns checks to multiple shards: {0}" -f ($intersection -join ", "))
    }
    foreach ($required in @($contract.required_runtime_checks)) {
        if ($runtime -cnotcontains [string]$required) {
            throw "Required runtime check '$required' is not owned by RuntimePlatform."
        }
    }
    return $contract
}

function Get-ExpectedReleaseCheckNames {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Full", "PlatformNeutral", "RuntimePlatform")]
        [string]$ValidationShard,
        [object]$Contract = (Get-ReleaseShardContract)
    )

    if ($ValidationShard -ceq "PlatformNeutral") {
        return @($Contract.shards.PlatformNeutral.checks | ForEach-Object { [string]$_ })
    }
    if ($ValidationShard -ceq "RuntimePlatform") {
        return @($Contract.shards.RuntimePlatform.checks | ForEach-Object { [string]$_ })
    }
    return @(
        @($Contract.shards.PlatformNeutral.checks) + @($Contract.shards.RuntimePlatform.checks) |
            ForEach-Object { [string]$_ }
    )
}

function Assert-ReleaseShardCoverage {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Full", "PlatformNeutral", "RuntimePlatform")]
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
        throw ("Release shard '$ValidationShard' coverage mismatch. duplicates=[{0}] missing=[{1}] unexpected=[{2}]" -f
            ($duplicates -join ", "), ($missing -join ", "), ($unexpected -join ", "))
    }

    return [ordered]@{
        contract_schema_version = [int]$contract.schema_version
        validation_shard = $ValidationShard
        expected_check_count = $expected.Count
        actual_check_count = $actual.Count
        platform_neutral_check_count = @($contract.shards.PlatformNeutral.checks).Count
        runtime_platform_check_count = @($contract.shards.RuntimePlatform.checks).Count
        shard_intersection_count = 0
        full_union_check_count = @($contract.shards.PlatformNeutral.checks).Count + @($contract.shards.RuntimePlatform.checks).Count
        status = "PASS"
    }
}
