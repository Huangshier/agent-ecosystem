# release-hub-initialization-checks.ps1
# Host-specific init_hub filesystem and Git behavior retained in RuntimePlatform.

function Invoke-ReleaseHubInitializationChecks {
    try {
        $initHubScript = Join-PathParts $repoRoot "skills" "project-bootstrap" "scripts" "init_hub.ps1"
        $defaultHub = Join-PathParts $scratchRootFull "init-hub-default"
        $explicitGitHub = Join-PathParts $scratchRootFull "init-hub-explicit-git"
        Assert-PathInsideRoot -Path $defaultHub -Root $scratchRootFull
        Assert-PathInsideRoot -Path $explicitGitHub -Root $scratchRootFull

        & $initHubScript -HubDir $defaultHub | Out-Host
        if (Test-Path -LiteralPath (Join-PathParts $defaultHub ".git")) {
            throw "init_hub.ps1 created .git without -InitializeGit or -CommitInitial."
        }

        & $initHubScript -HubDir $explicitGitHub -InitializeGit | Out-Host
        if (-not (Test-Path -LiteralPath (Join-PathParts $explicitGitHub ".git"))) {
            throw "init_hub.ps1 -InitializeGit did not create .git."
        }

        Add-Check "hub initialization git mode" "PASS" "init_hub.ps1 leaves default hubs as ordinary directories and initializes Git only when requested." ([ordered]@{
            default_hub = $defaultHub
            explicit_git_hub = $explicitGitHub
        })
    }
    catch {
        Add-Check "hub initialization git mode" "FAIL" $_.Exception.Message
    }
}
