# release-governance-workflow-checks.ps1
# Contains validation checks for governance workflows:
# issue triage label sync and PR identity guard.
# Part of the release validator thin-entrypoint refactor.
# Authoritative check names: "issue triage label sync", "PR identity guard".

<#
.SYNOPSIS
    Invoke-ReleaseGovernanceWorkflowChecks
    Validates issue triage label sync and PR identity guard workflows, helpers, tests, and docs.
.PARAMETER RepositoryRoot
    Absolute path to the repository root.
#>
function Invoke-ReleaseGovernanceWorkflowChecks {
    param(
        [string]$RepositoryRoot
    )

    # Issue triage label sync / decision command checks
    try {
        $triageWorkflow = Get-FileText -RelativePath ".github/workflows/issue-triage-label-sync.yml"
        $decisionCommandWorkflow = Get-FileText -RelativePath ".github/workflows/issue-triage-decision-command.yml"
        $decisionCommandHelper = Get-FileText -RelativePath ".github/scripts/issue-triage-decision-command.js"
        $decisionCommandTest = Get-FileText -RelativePath "scripts/test-issue-triage-decision-command.ps1"
        $governance = Get-FileText -RelativePath "docs/agent-governance.md"
        $issueTemplate = Get-FileText -RelativePath ".github/ISSUE_TEMPLATE/agent-candidate.md"
        $triageExpectations = [ordered]@{
            ".github/workflows/issue-triage-label-sync.yml" = @(
                "issues:",
                "issues: write",
                "contents: read",
                "source:agent",
                "Human Triage Decision",
                "concurrency:",
                "Decision:",
                "legacy checklist",
                "agent-ecosystem-bot[bot]",
                "getCollaboratorPermissionLevel",
                "Actor is not trusted",
                "triage:accepted",
                "triage:rejected",
                "triage:deferred",
                "triage:needs-human",
                "review:needs-human",
                "core.setFailed"
            )
            ".github/workflows/issue-triage-decision-command.yml" = @(
                "issue_comment:",
                "issues: write",
                "contents: read",
                "source:agent",
                "pull_request == null",
                "concurrency:",
                "actions/checkout@v6",
                "actions/github-script@v8",
                "issue-triage-decision-command.js"
            )
            ".github/scripts/issue-triage-decision-command.js" = @(
                "parseDecisionCommand",
                "/decision accepted",
                "/accept",
                "TRUSTED_REPOSITORY_ROLES",
                '"admin", "maintain", "write"',
                "getCollaboratorPermissionLevel",
                "updateDecisionInBody",
                "buildNormalizedTriageSection",
                "DEFAULT_ALLOWED_VALUES_LINE",
                "formatActorLogin",
                "convergeTriageLabels",
                "review:needs-human",
                "Pull request comments are ignored"
            )
            "scripts/test-issue-triage-decision-command.ps1" = @(
                "/decision accepted",
                "/decision maybe",
                "countOccurrences",
                'assert(!updated.body.includes("@maintainer"))',
                "Allowed values: accepted, rejected, deferred, needs-human",
                'permission: "triage"',
                "pull_request",
                "triage:accepted",
                "triage:needs-human",
                "missingSection",
                "appended"
            )
            "docs/agent-governance.md" = @(
                "Issue Triage Label Sync",
                "Issue Triage Decision Commands",
                "mirrors the explicit",
                "does not make triage decisions",
                "source:agent",
                "trusted automation",
                "appends a normalized section",
                "maintainer-authorized",
                "Decision: needs-human",
                "/decision accepted",
                "admin",
                "maintain",
                "write",
                "review:needs-human"
            )
            ".github/ISSUE_TEMPLATE/agent-candidate.md" = @(
                "issue triage label sync workflow",
                "Decision: needs-human",
                "Allowed values: accepted, rejected, deferred, needs-human"
            )
        }

        $triageMissing = New-Object 'System.Collections.Generic.List[string]'
        foreach ($relativePath in $triageExpectations.Keys) {
            $text = switch ($relativePath) {
                ".github/workflows/issue-triage-label-sync.yml" { $triageWorkflow }
                ".github/workflows/issue-triage-decision-command.yml" { $decisionCommandWorkflow }
                ".github/scripts/issue-triage-decision-command.js" { $decisionCommandHelper }
                "scripts/test-issue-triage-decision-command.ps1" { $decisionCommandTest }
                "docs/agent-governance.md" { $governance }
                default { $issueTemplate }
            }
            foreach ($token in $triageExpectations[$relativePath]) {
                if (-not $text.Contains($token)) {
                    $triageMissing.Add("$relativePath missing token: $token")
                }
            }
        }

        $triageUnexpected = New-Object 'System.Collections.Generic.List[string]'
        $triageUnexpectedTokens = [ordered]@{
            ".github/workflows/issue-triage-label-sync.yml" = @(
                "- unlabeled"
            )
            ".github/ISSUE_TEMPLATE/agent-candidate.md" = @(
                "- [ ] Accepted",
                "- [ ] Rejected",
                "- [ ] Deferred",
                "- [ ] Needs human investigation",
                "Leave only one checked"
            )
        }
        foreach ($relativePath in $triageUnexpectedTokens.Keys) {
            $text = switch ($relativePath) {
                ".github/workflows/issue-triage-label-sync.yml" { $triageWorkflow }
                default { $issueTemplate }
            }
            foreach ($token in $triageUnexpectedTokens[$relativePath]) {
                if ($text.Contains($token)) {
                    $triageUnexpected.Add("$relativePath still contains legacy token: $token")
                }
            }
        }

        if ($triageMissing.Count -gt 0 -or $triageUnexpected.Count -gt 0) {
            $triageFindings = @($triageMissing.ToArray()) + @($triageUnexpected.ToArray())
            Add-Check "issue triage label sync" "FAIL" "Issue triage label sync workflow or docs are incomplete." $triageFindings
        }
        else {
            $decisionCommandTestScript = Join-PathParts $RepositoryRoot "scripts" "test-issue-triage-decision-command.ps1"
            $decisionCommandTestResult = & $decisionCommandTestScript -RepoRoot $RepositoryRoot -Json | ConvertFrom-Json
            if ($LASTEXITCODE -ne 0) {
                throw "Issue triage decision command tests exited with code $LASTEXITCODE."
            }
            Add-Check "issue triage label sync" "PASS" "Authorized agent candidate issue triage decisions are mirrored to labels by a scoped workflow." ([ordered]@{
                workflow = ".github/workflows/issue-triage-label-sync.yml"
                command_workflow = ".github/workflows/issue-triage-decision-command.yml"
                command_helper = ".github/scripts/issue-triage-decision-command.js"
                command_test = $decisionCommandTestResult
                docs = @("docs/agent-governance.md", ".github/ISSUE_TEMPLATE/agent-candidate.md")
            })
        }
    }
    catch {
        Add-Check "issue triage label sync" "FAIL" $_.Exception.Message
    }

    # PR identity guard checks
    try {
        $identityWorkflow = Get-FileText -RelativePath ".github/workflows/pr-identity-guard.yml"
        $identityHelper = Get-FileText -RelativePath ".github/scripts/pr-identity-guard.js"
        $identityTest = Get-FileText -RelativePath "scripts/test-pr-identity-guard.ps1"
        $governance = Get-FileText -RelativePath "docs/agent-governance.md"
        $identityExpectations = [ordered]@{
            ".github/workflows/pr-identity-guard.yml" = @(
                "pull_request:",
                "contents: read",
                "pull-requests: read",
                "verify agent PR commit identity",
                "actions/checkout@v6",
                "actions/github-script@v8",
                "pr-identity-guard.js"
            )
            ".github/scripts/pr-identity-guard.js" = @(
                "ACCEPTED_BOT_SIGNATURES",
                "agent-ecosystem-bot[bot]@users.noreply.github.com",
                "resolveAgentSignals",
                "source:agent",
                "codex|agent",
                "evaluatePullRequestIdentity",
                "evaluateCommitIdentity",
                "Actor Boundary",
                "listCommits"
            )
            "scripts/test-pr-identity-guard.ps1" = @(
                "source:agent",
                "codex/issue-145-pr-identity-guard",
                "Actor Boundary",
                "agent-ecosystem-bot[bot]@users.noreply.github.com",
                "committer is Local User"
            )
            "docs/agent-governance.md" = @(
                "Pull Request Identity Guard",
                "source:agent",
                "codex/",
                "agent/",
                "scans every commit",
                "commit author and committer",
                "Actor Boundary",
                "bot-backed public write flow"
            )
        }

        $identityMissing = New-Object 'System.Collections.Generic.List[string]'
        foreach ($relativePath in $identityExpectations.Keys) {
            $text = switch ($relativePath) {
                ".github/workflows/pr-identity-guard.yml" { $identityWorkflow }
                ".github/scripts/pr-identity-guard.js" { $identityHelper }
                "scripts/test-pr-identity-guard.ps1" { $identityTest }
                default { $governance }
            }
            foreach ($token in $identityExpectations[$relativePath]) {
                if (-not $text.Contains($token)) {
                    $identityMissing.Add("$relativePath missing token: $token")
                }
            }
        }

        if ($identityMissing.Count -gt 0) {
            Add-Check "PR identity guard" "FAIL" "PR identity guard workflow, helper, tests, or docs are incomplete." @($identityMissing.ToArray())
        }
        else {
            $identityTestScript = Join-PathParts $RepositoryRoot "scripts" "test-pr-identity-guard.ps1"
            $identityTestResult = & $identityTestScript -RepoRoot $RepositoryRoot -Json | ConvertFrom-Json
            if ($LASTEXITCODE -ne 0) {
                throw "PR identity guard tests exited with code $LASTEXITCODE."
            }
            Add-Check "PR identity guard" "PASS" "Hosted PR checks validate bot commit identity for explicitly agent-authored pull requests." ([ordered]@{
                workflow = ".github/workflows/pr-identity-guard.yml"
                helper = ".github/scripts/pr-identity-guard.js"
                focused_test = $identityTestResult
                docs = "docs/agent-governance.md"
            })
        }
    }
    catch {
        Add-Check "PR identity guard" "FAIL" $_.Exception.Message
    }
}
