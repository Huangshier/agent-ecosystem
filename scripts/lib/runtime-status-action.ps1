function Get-RecommendedNextAction {
    param([Parameter(Mandatory = $true)][object]$Payload)

    try {
        function Get-ActionProperty {
            param([Parameter(Mandatory = $true)][object]$InputObject, [Parameter(Mandatory = $true)][string]$Name)
            if ($InputObject -is [string] -or $InputObject -is [System.Array]) { throw "invalid payload shape" }
            $property = $InputObject.PSObject.Properties[$Name]
            if ($null -eq $property) { throw "missing payload property" }
            return $property.Value
        }

        function Get-ActionStatus {
            param([Parameter(Mandatory = $true)][object]$InputObject, [Parameter(Mandatory = $true)][string]$Name)
            $value = Get-ActionProperty -InputObject $InputObject -Name $Name
            if ($value -isnot [string]) { throw "invalid status type" }
            return [string]$value
        }

        $runtime = Get-ActionProperty -InputObject $Payload -Name "runtime"
        switch (Get-ActionStatus -InputObject $runtime -Name "manifest_status") {
            { $_ -in @("missing", "legacy", "unsupported", "invalid") } { return "reinstall-runtime" }
            "current" { }
            default { return "inspect-manually" }
        }

        $managedFiles = Get-ActionProperty -InputObject $runtime -Name "managed_files"
        switch (Get-ActionStatus -InputObject $managedFiles -Name "status") {
            "conflict" { return "review-managed-conflicts" }
            "missing" { return "reinstall-runtime" }
            { $_ -in @("modified", "unknown") } { return "inspect-manually" }
            "current" { }
            default { return "inspect-manually" }
        }

        $bridge = Get-ActionProperty -InputObject $Payload -Name "bridge"
        switch (Get-ActionStatus -InputObject $bridge -Name "status") {
            { $_ -in @("conflict", "broken", "stale") } { return "repair-bridge" }
            "unknown" { return "inspect-manually" }
            { $_ -in @("current", "not-configured") } { }
            default { return "inspect-manually" }
        }

        $project = Get-ActionProperty -InputObject $Payload -Name "project"
        switch (Get-ActionStatus -InputObject $project -Name "status") {
            "migration-required" { return "run-memory-migration-analysis" }
            "optional-refresh" { return "refresh-project-templates" }
            "unknown" {
                if ((Get-ActionStatus -InputObject $project -Name "reason") -cne "not-requested") { return "inspect-manually" }
            }
            "current" { }
            default { return "inspect-manually" }
        }

        return "none"
    }
    catch {
        return "inspect-manually"
    }
}
