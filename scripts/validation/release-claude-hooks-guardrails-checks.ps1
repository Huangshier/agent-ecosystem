# release-claude-hooks-guardrails-checks.ps1
# Validates the public Claude Code hooks guardrails contract, template surface,
# bundled snapshot, and deterministic fixture matrix.
# Depends on: release-test-helper.ps1, path-guard.ps1.

function Invoke-ReleaseClaudeHooksGuardrailsChecks {

try {
    $contractPath = "docs/claude-code-hooks-guardrails.md"
    $contractText = Get-FileText -RelativePath $contractPath
    $requiredContractTokens = @(
        "template reliability",
        "not a security sandbox",
        "write authorization profile",
        "public/private boundary",
        "needs-human",
        "public contributor",
        "raw artifacts",
        "not be promoted into the generic project-bootstrap template as a universal bot requirement"
    )
    $missingContractTokens = @(Get-MissingRequiredText -Text $contractText -RequiredText $requiredContractTokens)

    $script:evidence.claude_hooks_guardrails_contract = [ordered]@{
        path = $contractPath
        missing_tokens = @($missingContractTokens)
    }

    if ($missingContractTokens.Count -gt 0) {
        Add-Check "Claude hooks guardrails contract" "FAIL" "The public guardrails contract is missing required boundary tokens." $evidence.claude_hooks_guardrails_contract
    }
    else {
        Add-Check "Claude hooks guardrails contract" "PASS" "The public guardrails contract defines template reliability goals, non-goals, write profiles, contributor path, stop point, and raw artifact boundaries." $evidence.claude_hooks_guardrails_contract
    }
}
catch {
    Add-Check "Claude hooks guardrails contract" "FAIL" $_.Exception.Message
}

try {
    $authorityRoot = "knowledge-hub/templates/languages"
    $snapshotRoot = "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages"
    $languages = @("en", "zh-CN")
    $requiredRelativePaths = @(
        "project-root/CLAUDE.md",
        "project-root/.claude/settings.json",
        "project-root/.claude/guardrails/README.md",
        "project-root/.claude/guardrails/profile.json",
        "project-root/.claude/hooks/README.md",
        "project-root/.claude/hooks/guardrail.ps1"
    )
    $requiredProfileChecks = @(
        "entry-loading",
        "project-context-loading",
        "project-language-awareness",
        "agents-file-awareness",
        "hub-lock-awareness",
        "public-private-boundary",
        "write-authorization-profile",
        "wrong-write-path",
        "dangerous-memory-refresh-confirmation",
        "stop-point-needs-human",
        "raw-artifact-quarantine",
        "public-contributor-no-bot-required"
    )

    $templateFailures = New-Object 'System.Collections.Generic.List[string]'
    foreach ($language in $languages) {
        foreach ($relativePath in $requiredRelativePaths) {
            $authorityPath = "$authorityRoot/$language/$relativePath"
            $snapshotPath = "$snapshotRoot/$language/$relativePath"
            if (-not (Test-RequiredPath -RelativePath $authorityPath)) {
                $templateFailures.Add("missing authority template: $authorityPath")
            }
            if (-not (Test-RequiredPath -RelativePath $snapshotPath)) {
                $templateFailures.Add("missing bundled snapshot: $snapshotPath")
            }
            if ((Test-RequiredPath -RelativePath $authorityPath) -and (Test-RequiredPath -RelativePath $snapshotPath)) {
                $authorityHash = (Get-FileHash -LiteralPath (Join-PathParts $repoRoot $authorityPath) -Algorithm SHA256).Hash
                $snapshotHash = (Get-FileHash -LiteralPath (Join-PathParts $repoRoot $snapshotPath) -Algorithm SHA256).Hash
                if ($authorityHash -ne $snapshotHash) {
                    $templateFailures.Add("authority and bundled snapshot differ: $language/$relativePath")
                }
            }
        }

        foreach ($root in @($authorityRoot, $snapshotRoot)) {
            $claudePath = "$root/$language/project-root/CLAUDE.md"
            if (Test-RequiredPath -RelativePath $claudePath) {
                $claudeText = Get-FileText -RelativePath $claudePath
                if (-not $claudeText.Contains("@.claude/guardrails/README.md")) {
                    $templateFailures.Add("$claudePath missing guardrails import")
                }
            }

            $settingsPath = "$root/$language/project-root/.claude/settings.json"
            if (Test-RequiredPath -RelativePath $settingsPath) {
                $settings = Get-FileText -RelativePath $settingsPath | ConvertFrom-Json
                foreach ($eventName in @("SessionStart", "PreToolUse", "Stop")) {
                    $groups = @($settings.hooks.$eventName)
                    if ($groups.Count -eq 0) {
                        $templateFailures.Add("$settingsPath missing $eventName registration")
                        continue
                    }
                    $handlers = @($groups | ForEach-Object { @($_.hooks) } | ForEach-Object { $_ })
                    $runnerHandlers = @($handlers | Where-Object {
                        [string]$_.command -eq "pwsh" -and
                        (@($_.args) -contains '${CLAUDE_PROJECT_DIR}/.claude/hooks/guardrail.ps1')
                    })
                    if ($runnerHandlers.Count -eq 0) {
                        $templateFailures.Add("$settingsPath $eventName does not invoke the public guardrail runner")
                    }
                }
                $preToolMatchers = @($settings.hooks.PreToolUse | ForEach-Object { [string]$_.matcher }) -join "|"
                foreach ($requiredTool in @("Bash", "PowerShell", "Monitor")) {
                    if ($preToolMatchers -notmatch ("(^|\|){0}(\||$)" -f [regex]::Escape($requiredTool))) {
                        $templateFailures.Add("$settingsPath PreToolUse matcher missing command tool: $requiredTool")
                    }
                }
            }

            $runnerPath = "$root/$language/project-root/.claude/hooks/guardrail.ps1"
            if (Test-RequiredPath -RelativePath $runnerPath) {
                $runnerText = Get-FileText -RelativePath $runnerPath
                foreach ($token in @("SessionStart", "PreToolUse", "Stop", "stop_hook_active", "default_profile", "public-contributor", "needs-human")) {
                    if (-not $runnerText.Contains($token)) {
                        $templateFailures.Add("$runnerPath missing runtime token: $token")
                    }
                }
                foreach ($persistenceToken in @("Add-Content", "Out-File", "WriteAllText", "AppendAllText")) {
                    if ($runnerText.Contains($persistenceToken)) {
                        $templateFailures.Add("$runnerPath must not persist raw hook input: $persistenceToken")
                    }
                }
            }

            $profilePath = "$root/$language/project-root/.claude/guardrails/profile.json"
            if (Test-RequiredPath -RelativePath $profilePath) {
                $profile = Get-FileText -RelativePath $profilePath | ConvertFrom-Json
                if ([int]$profile.schema_version -ne 1) {
                    $templateFailures.Add("$profilePath schema_version must be 1")
                }
                if ([string]$profile.guardrail_type -ne "template-reliability") {
                    $templateFailures.Add("$profilePath guardrail_type must be template-reliability")
                }
                if ([string]$profile.default_profile -ne "local-only") {
                    $templateFailures.Add("$profilePath default_profile must be local-only")
                }
                $checks = @($profile.required_checks | ForEach-Object { [string]$_ })
                foreach ($requiredCheck in $requiredProfileChecks) {
                    if ($requiredCheck -notin $checks) {
                        $templateFailures.Add("$profilePath missing required check: $requiredCheck")
                    }
                }
                $publicContributor = $profile.write_authorization_profiles.'public-contributor'
                if ($null -eq $publicContributor) {
                    $templateFailures.Add("$profilePath missing public-contributor profile")
                }
                elseif ([bool]$publicContributor.requires_bot) {
                    $templateFailures.Add("$profilePath public-contributor profile must not require a bot")
                }
                $projectMaintenance = $profile.write_authorization_profiles.'project-maintenance'
                if ($null -eq $projectMaintenance) {
                    $templateFailures.Add("$profilePath missing project-maintenance profile")
                }
                elseif ([bool]$projectMaintenance.requires_bot) {
                    $templateFailures.Add("$profilePath generic project-maintenance profile must not require a bot by default")
                }
            }
        }
    }

    $script:evidence.claude_hooks_guardrails_templates = [ordered]@{
        languages = @($languages)
        required_relative_paths = @($requiredRelativePaths)
        failures = @($templateFailures.ToArray())
    }

    if ($templateFailures.Count -gt 0) {
        Add-Check "Claude hooks guardrails templates" "FAIL" "Guardrails templates or bundled snapshots are incomplete or unsafe." $evidence.claude_hooks_guardrails_templates
    }
    else {
        Add-Check "Claude hooks guardrails templates" "PASS" "English and Simplified Chinese templates include lifecycle settings, executable runner, guardrails imports, no default bot requirement, and matching bundled snapshots." $evidence.claude_hooks_guardrails_templates
    }
}
catch {
    Add-Check "Claude hooks guardrails templates" "FAIL" $_.Exception.Message
}

try {
    $fixturePath = "scripts/validation/claude-hooks-guardrails-fixtures/cases.json"
    $fixture = Get-FileText -RelativePath $fixturePath | ConvertFrom-Json
    $requiredCases = @(
        "entry-loading",
        "project-context-loading",
        "project-language-agents-lock-awareness",
        "public-private-boundary",
        "write-authorization-profile",
        "wrong-write-path",
        "dangerous-memory-refresh-confirmation",
        "stop-point-needs-human",
        "raw-artifact-quarantine",
        "public-contributor-path-must-not-require-bot"
    )
    $caseFailures = New-Object 'System.Collections.Generic.List[string]'
    if ([int]$fixture.schema_version -ne 1) {
        $caseFailures.Add("fixture schema_version must be 1")
    }
    if ([string]$fixture.source -ne "public-deterministic-fixtures") {
        $caseFailures.Add("fixture source must be public-deterministic-fixtures")
    }
    $cases = @($fixture.cases)
    $caseNames = @($cases | ForEach-Object { [string]$_.name })
    foreach ($requiredCase in $requiredCases) {
        if ($requiredCase -notin $caseNames) {
            $caseFailures.Add("missing fixture case: $requiredCase")
        }
    }
    foreach ($case in $cases) {
        if (-not [bool]$case.public_safe) {
            $caseFailures.Add("fixture case is not public_safe: $($case.name)")
        }
        if ([string]$case.name -eq "wrong-write-path" -and [string]$case.expected_outcome -ne "stop") {
            $caseFailures.Add("wrong-write-path must stop")
        }
        if ([string]$case.name -eq "raw-artifact-quarantine" -and [string]$case.expected_outcome -ne "quarantine") {
            $caseFailures.Add("raw-artifact-quarantine must quarantine")
        }
        if ([string]$case.name -eq "public-contributor-path-must-not-require-bot" -and [bool]$case.requires_bot) {
            $caseFailures.Add("public contributor fixture must not require a bot")
        }
    }

    $script:evidence.claude_hooks_guardrails_fixtures = [ordered]@{
        path = $fixturePath
        required_cases = @($requiredCases)
        case_count = $cases.Count
        failures = @($caseFailures.ToArray())
    }

    if ($caseFailures.Count -gt 0) {
        Add-Check "Claude hooks guardrails fixtures" "FAIL" "The deterministic guardrails fixture matrix is incomplete or violates the public boundary." $evidence.claude_hooks_guardrails_fixtures
    }
    else {
        Add-Check "Claude hooks guardrails fixtures" "PASS" "The deterministic guardrails fixture matrix covers entry loading, project context, language and lock awareness, public/private boundary, write profiles, wrong write path, dangerous memory refresh, stop point, raw quarantine, and public contributor no-bot paths." $evidence.claude_hooks_guardrails_fixtures
    }
}
catch {
    Add-Check "Claude hooks guardrails fixtures" "FAIL" $_.Exception.Message
}

try {
    $runtimeValidatorPath = Join-PathParts $repoRoot "scripts" "validation" "test-claude-hooks-runtime.ps1"
    $runtimeResult = Invoke-IsolatedPowerShellScript -ScriptPath $runtimeValidatorPath -Arguments @(
        "-RepositoryRoot", $repoRoot,
        "-Json"
    )
    if ($runtimeResult.exit_code -ne 0) {
        throw "Targeted runtime validator exited with code $($runtimeResult.exit_code)."
    }
    $runtimeEvidence = ($runtimeResult.output -join "`n") | ConvertFrom-Json
    $script:evidence.claude_hooks_runtime_fixtures = $runtimeEvidence
    if ([string]$runtimeEvidence.status -ne "PASS" -or [int]$runtimeEvidence.failed -ne 0) {
        Add-Check "Claude hooks runtime fixtures" "FAIL" "One or more executable stdin/stdout fixtures failed." $runtimeEvidence
    }
    else {
        Add-Check "Claude hooks runtime fixtures" "PASS" "Executable SessionStart, PreToolUse, and Stop stdin/stdout fixtures passed, including boundary, authorization, dangerous refresh, no-bot contributor, quarantine, and stop-loop behavior." $runtimeEvidence
    }
}
catch {
    Add-Check "Claude hooks runtime fixtures" "FAIL" $_.Exception.Message
}

}
