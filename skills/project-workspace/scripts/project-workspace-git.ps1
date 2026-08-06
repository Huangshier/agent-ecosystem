# Internal read-only Git state and anchor responsibilities for project-workspace.
# This file is dot-sourced only by project-workspace.ps1.

# Invoke-GitProbe: run a read-only Git probe and preserve its exit state.
function Invoke-GitProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $hadOptionalLocks = Test-Path Env:GIT_OPTIONAL_LOCKS
    $previousOptionalLocks = $env:GIT_OPTIONAL_LOCKS
    try {
        # NOTE: Git status may refresh the index unless optional locks are disabled;
        # the check contract must not mutate the worktree while observing it.
        $env:GIT_OPTIONAL_LOCKS = "0"
        try {
            $output = @(& git -C $Root @Arguments 2>$null)
            $exitCode = [int]$LASTEXITCODE
        }
        catch {
            $output = @()
            $exitCode = 127
        }
        return [ordered]@{ exit_code = $exitCode; text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim() }
    }
    finally {
        if ($hadOptionalLocks) { $env:GIT_OPTIONAL_LOCKS = $previousOptionalLocks }
        else { Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue }
    }
}

# Invoke-GitText: read-only Git command helper with no path-bearing output.
function Invoke-GitText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $probe = Invoke-GitProbe -Root $Root -Arguments $Arguments
    if ([int]$probe.exit_code -ne 0) { return $null }
    return [string]$probe.text
}

# Get-GitState: collect branch/worktree facts without modifying the repository.
function Get-GitState {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $insideProbe = Invoke-GitProbe -Root $Root -Arguments @("rev-parse", "--is-inside-work-tree")
    if ([int]$insideProbe.exit_code -ne 0 -or [string]$insideProbe.text -cne "true") {
        Add-Finding -Findings $Findings -Code "git-unavailable" -Path "" -Message "Git repository metadata is unavailable; discovery remains filesystem-based." -Severity warning
        return [ordered]@{ state = "unavailable"; branch = ""; head = ""; dirty = $null; shallow = $null; detached = $null; anchors = @() }
    }
    $branchProbe = Invoke-GitProbe -Root $Root -Arguments @("symbolic-ref", "--quiet", "--short", "HEAD")
    $headProbe = Invoke-GitProbe -Root $Root -Arguments @("rev-parse", "HEAD")
    $shallowProbe = Invoke-GitProbe -Root $Root -Arguments @("rev-parse", "--is-shallow-repository")
    $statusProbe = Invoke-GitProbe -Root $Root -Arguments @("status", "--porcelain", "--untracked-files=all")
    if ([int]$headProbe.exit_code -ne 0 -or [int]$shallowProbe.exit_code -ne 0 -or [int]$statusProbe.exit_code -ne 0) {
        Add-Finding -Findings $Findings -Code "git-unavailable" -Path "" -Message "Git repository state could not be observed reliably; anchor checks degrade to unavailable." -Severity warning
        return [ordered]@{ state = "unavailable"; branch = ""; head = ""; dirty = $null; shallow = $null; detached = $null; anchors = @() }
    }
    $branch = if ([int]$branchProbe.exit_code -eq 0) { [string]$branchProbe.text } else { "" }
    $head = [string]$headProbe.text
    $shallowText = [string]$shallowProbe.text
    $statusText = [string]$statusProbe.text
    if (-not [string]::IsNullOrWhiteSpace($branch) -and -not (Test-PublicSafeText -Text ([string]$branch))) {
        Add-Finding -Findings $Findings -Code "unsafe-output" -Path "" -Field "git.branch" -Message "Current Git branch cannot be emitted as public-safe metadata."
        $branch = ""
    }
    $detached = [string]::IsNullOrWhiteSpace($branch)
    $dirty = -not [string]::IsNullOrWhiteSpace($statusText)
    $shallow = ($shallowText -ceq "true")
    if ($dirty) { Add-Finding -Findings $Findings -Code "git-dirty" -Path "" -Message "Git worktree has uncommitted changes." -Severity warning }
    if ($shallow) { Add-Finding -Findings $Findings -Code "git-shallow" -Path "" -Message "Git repository is shallow; commit reachability is limited." -Severity warning }
    if ($detached) { Add-Finding -Findings $Findings -Code "git-detached" -Path "" -Message "Git HEAD is detached; branch anchors cannot be matched." -Severity warning }
    return [ordered]@{ state = "available"; branch = [string]$branch; head = [string]$head; dirty = $dirty; shallow = $shallow; detached = $detached; anchors = @() }
}

# Test-GitAnchor: evaluate optional Work anchors against current read-only Git facts.
function Test-GitAnchor {
    param(
        [Parameter(Mandatory = $true)][object]$Asset,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object]$GitState,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Findings
    )

    $anchor = Get-PropertyValue $Asset "git"
    if ($null -eq $anchor) { return $null }
    $branch = [string](Get-PropertyValue $anchor "branch")
    $worktree = [string](Get-PropertyValue $anchor "worktree")
    $verified = [string](Get-PropertyValue $anchor "last_verified_commit")
    $branchState = "not_checked"
    if (-not [string]::IsNullOrWhiteSpace($branch)) {
        if ($GitState.state -cne "available" -or $GitState.detached) { $branchState = "unavailable" }
        elseif ([string]$GitState.branch -ceq $branch) { $branchState = "branch_match" }
        else {
            $branchState = "branch_mismatch"
            Add-Finding -Findings $Findings -Code "branch_mismatch" -Path ([string]$Asset.path) -Field "git.branch" -Message "Work item Git branch differs from the current branch." -Severity warning
        }
    }
    $worktreeState = "not_set"
    $worktreePresent = $null
    if (-not [string]::IsNullOrWhiteSpace($worktree)) {
        try {
            $worktreePath = Assert-ProjectPath -Root $Root -RelativePath $worktree -AllowMissing
            if (Test-Path -LiteralPath $worktreePath -PathType Container) {
                $worktreeState = "present"
                $worktreePresent = $true
            }
            elseif (Test-Path -LiteralPath $worktreePath) {
                $worktreeState = "wrong_type"
                $worktreePresent = $false
                Add-Finding -Findings $Findings -Code "git-worktree-type" -Path ([string]$Asset.path) -Field "git.worktree" -Message "Git worktree anchor target is not a directory." -Severity warning
            }
            else {
                $worktreeState = "missing"
                $worktreePresent = $false
                Add-Finding -Findings $Findings -Code "git-worktree-missing" -Path ([string]$Asset.path) -Field "git.worktree" -Message "Git worktree anchor target is not present under the project root." -Severity warning
            }
        }
        catch {
            $worktreeState = "invalid"
            $worktreePresent = $false
            Add-Finding -Findings $Findings -Code "git-worktree-invalid" -Path ([string]$Asset.path) -Field "git.worktree" -Message "Git worktree anchor is not a safe project-relative path." -Severity warning
        }
    }

    $commitPresence = "not_set"
    $commitState = "not_checked"
    if (-not [string]::IsNullOrWhiteSpace($verified)) {
        if ($GitState.state -cne "available") {
            $commitPresence = "unknown"
            $commitState = "git_unavailable"
        }
        elseif ($verified -notmatch '^[0-9a-fA-F]{7,64}$') {
            $commitPresence = "invalid"
            $commitState = "invalid_commit"
            Add-Finding -Findings $Findings -Code "git-anchor-invalid" -Path ([string]$Asset.path) -Field "git.last_verified_commit" -Message "Git anchor commit must be a hexadecimal commit id." -Severity warning
        }
        else {
            $objectProbe = Invoke-GitProbe -Root $Root -Arguments @("cat-file", "-e", ($verified + "^{commit}"))
            if ([int]$objectProbe.exit_code -eq 0) {
                $commitPresence = "existing"
                $reachProbe = Invoke-GitProbe -Root $Root -Arguments @("merge-base", "--is-ancestor", $verified, "HEAD")
                if ([int]$reachProbe.exit_code -eq 0) {
                    $commitState = "reachable"
                }
                elseif ([int]$reachProbe.exit_code -eq 1 -and [bool]$GitState.shallow) {
                    $commitState = "shallow_unknown"
                    Add-Finding -Findings $Findings -Code "git-anchor-shallow-unknown" -Path ([string]$Asset.path) -Field "git.last_verified_commit" -Message "Shallow Git history cannot reliably determine anchor reachability." -Severity warning
                }
                elseif ([int]$reachProbe.exit_code -eq 1) {
                    $commitState = "unreachable"
                    Add-Finding -Findings $Findings -Code "git-anchor-unreachable" -Path ([string]$Asset.path) -Field "git.last_verified_commit" -Message "Git anchor commit exists but is not reachable from current HEAD." -Severity warning
                }
                else {
                    $commitState = "git_unavailable"
                    Add-Finding -Findings $Findings -Code "git-anchor-unavailable" -Path ([string]$Asset.path) -Field "git.last_verified_commit" -Message "Git could not reliably evaluate anchor reachability." -Severity warning
                }
            }
            elseif ([bool]$GitState.shallow) {
                $commitPresence = "unknown"
                $commitState = "shallow_unknown"
                Add-Finding -Findings $Findings -Code "git-anchor-shallow-unknown" -Path ([string]$Asset.path) -Field "git.last_verified_commit" -Message "Shallow Git history cannot reliably determine whether the anchor commit exists or is reachable." -Severity warning
            }
            else {
                $commitPresence = "missing"
                $commitState = "missing"
                Add-Finding -Findings $Findings -Code "git-anchor-missing" -Path ([string]$Asset.path) -Field "git.last_verified_commit" -Message "Git anchor commit does not exist in the local repository." -Severity warning
            }
        }
    }
    $publicBranch = if ([string]::IsNullOrWhiteSpace($branch) -or -not (Test-PublicSafeText -Text $branch)) { "" } else { $branch }
    $publicWorktree = if ([string]::IsNullOrWhiteSpace($worktree) -or -not (Test-PublicSafeText -Text $worktree) -or -not (Test-SafeProjectRelativePath -Path $worktree)) { "" } else { $worktree }
    $publicVerified = if ($verified -match '^[0-9a-fA-F]{7,64}$') { $verified.ToLowerInvariant() } else { "" }
    return [ordered]@{
        branch = $publicBranch
        branch_state = $branchState
        worktree = $publicWorktree
        worktree_present = $worktreePresent
        worktree_state = $worktreeState
        last_verified_commit = $publicVerified
        commit_presence = $commitPresence
        commit_state = $commitState
    }
}
