function Get-MigrationNonAuthorityPaths {
    param([Parameter(Mandatory = $true)][string]$Root)

    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    try {
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $lockPath = Join-Path $rootFull ".agents/hub.lock.json"
        if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return ,$paths }
        $lock = [IO.File]::ReadAllText($lockPath, [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        if ([string]$lock.workspace_model -cne "c3.3" -or $null -eq $lock.migration_non_authority -or
            [int]$lock.migration_non_authority.schema_version -ne 1) { return ,$paths }
        $entries = $lock.migration_non_authority.entries
        if ($entries -isnot [Collections.IList] -or $entries -is [string]) { return ,$paths }
        $validated = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($entry in @($entries)) {
            $propertyNames = @($entry.PSObject.Properties.Name | Sort-Object)
            $expectedPropertyNames = @("evidence_kind", "evidence_sha256", "path", "sha256") | Sort-Object
            if (($propertyNames -join "`n") -cne ($expectedPropertyNames -join "`n")) { return ,$paths }
            $relative = [string]$entry.path
            $sha256 = [string]$entry.sha256
            $evidenceKind = [string]$entry.evidence_kind
            $evidenceSha256 = [string]$entry.evidence_sha256
            if ($relative -cnotmatch '^\.agents/context/[^/\\\x00-\x1f]+(?:/[^/\\\x00-\x1f]+)*\.md$' -or
                $relative -match '(^|/)\.\.?(/|$)' -or $sha256 -cnotmatch '^[a-f0-9]{64}$' -or
                $evidenceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
                $evidenceKind -cnotin @("deterministic-template", "reviewed-disposition") -or
                ($evidenceKind -ceq "deterministic-template" -and $evidenceSha256 -cne $sha256) -or
                -not $validated.Add($relative)) { return ,$paths }
            $full = [IO.Path]::GetFullPath((Join-Path $rootFull $relative))
            $prefix = $rootFull + [IO.Path]::DirectorySeparatorChar
            if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-Path -LiteralPath $full -PathType Leaf)) { return ,$paths }
            $current = $rootFull
            foreach ($part in @($relative -split '/')) {
                $current = Join-Path $current $part
                $item = Get-Item -LiteralPath $current -Force
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return ,$paths }
            }
            $actual = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($full))).ToLowerInvariant()
            if ($actual -cne $sha256) { return ,$paths }
        }
        foreach ($relative in $validated) { [void]$paths.Add($relative) }
    }
    catch {
        # NOTE: Malformed or stale migration metadata never grants a non-authority exemption.
        return ,[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    }
    return ,$paths
}
