function Assert-AgentEcosystemPowerShellRuntime {
    [CmdletBinding()]
    param(
        [Version]$Version = $PSVersionTable.PSVersion,
        [string]$Edition = [string]$PSVersionTable.PSEdition
    )

    if ($Edition -cne "Core") {
        throw "PowerShell Core edition is required."
    }
    if ($Version -lt [Version]"7.6") {
        throw "PowerShell 7.6 or later is required."
    }
}

function Resolve-AgentEcosystemPwshExecutable {
    [CmdletBinding()]
    param([scriptblock]$CommandLookup)

    if ($null -eq $CommandLookup) {
        $CommandLookup = {
            param([string]$Name)
            Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        }
    }

    $command = & $CommandLookup "pwsh"
    if ($null -eq $command) {
        return ""
    }
    return [string]$command.Source
}
