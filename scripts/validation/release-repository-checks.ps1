# release-repository-checks.ps1
# Extracted from scripts/validate-release.ps1 Invoke-ReleaseValidationRepositoryChecks (Phase 2).
# Runs repository structure, documentation boundary, helper ownership, skill metadata, and hub init checks.
# Depends on: release-test-helper.ps1 (Add-Check, Test-RequiredPath, Get-GitFiles, Get-FileText,
#             Get-LineMatches, Get-MissingRequiredText), path-guard.ps1 (Join-PathParts, Assert-PathInsideRoot).
# Scope: script-level $repoRoot, $scratchRootFull, $script:evidence, $checks.

# Invoke-ReleaseRepositoryChecks: No parameters; runs public structure, root agents boundary, spec state boundary,
# legacy template references, upgrade path, command boundaries, path guard helper, helper ownership, release
# validation helper, and skill metadata checks in the original order.
function Invoke-ReleaseRepositoryChecks {

$requiredFiles = @(
    "README.md",
    "README.en.md",
    "README.zh-CN.md",
    "LICENSE",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "scripts/benchmark-context-gate.ps1",
    "scripts/install.ps1",
    "scripts/lib/path-guard.ps1",
    "scripts/prune-validation-scratch.ps1",
    "scripts/test-pr-identity-guard.ps1",
    "scripts/uninstall.ps1",
    "scripts/validation/release-test-helper.ps1",
    "scripts/validation/workflow-spec-lite-fixture-helper.ps1",
    "scripts/validation/workflow-spec-lite-fixtures/complete-spec.md",
    "scripts/validation/workflow-spec-lite-fixtures/loop-contract-spec.md",
    "scripts/validation/workflow-spec-lite-fixtures/chinese-section-spec.md",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/README.md",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/compact-active-phase/.agents/process.txt",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/compact-active-phase/.agents/plan.md",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/compact-active-phase/.agents/notes.md",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/compact-active-phase/.agents/context/README.md",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/compact-active-phase/expected.json",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/process-history-backlog/.agents/process.txt",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/process-history-backlog/.agents/plan.md",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/process-history-backlog/.agents/notes.md",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/process-history-backlog/.agents/context/README.md",
    "scripts/validation/memory-diagnose-structural-fixtures/completed-list-growth/process-history-backlog/expected.json",
    "scripts/validation/memory-upgrade-stable-notes-fixtures/README.md",
    "scripts/validation/memory-upgrade-stable-notes-fixtures/positive-stable-section/notes.md",
    "scripts/validation/memory-upgrade-stable-notes-fixtures/positive-stable-section/expected.json",
    "scripts/validation/memory-upgrade-stable-notes-fixtures/negative-volatile-only/notes.md",
    "scripts/validation/memory-upgrade-stable-notes-fixtures/negative-volatile-only/expected.json",
    "scripts/validate-release.ps1",
    "docs/architecture.md",
    "docs/existing-project-upgrade.md",
    "docs/how-to-adapt.md",
    "docs/language-policy.md",
    "docs/powershell-helper-ownership.md",
    "docs/release-process.md",
    "docs/release-readiness.md",
    "docs/roadmap/memory-diagnose-structural-diagnostics.md",
    "docs/shell-strategy.md",
    "docs/template-path-reference-audit.md",
    "docs/releases/README.md",
    "docs/releases/v0.1.0.md",
    "docs/releases/v0.2.0.md",
    "docs/releases/v0.3.0.md",
    "docs/releases/v0.3.1.md",
    "docs/releases/v0.4.0.md",
    "docs/releases/v0.4.1.md",
    "docs/releases/v0.4.2.md",
    "docs/releases/v0.4.3.md",
    "docs/releases/v0.4.4.md",
    "docs/releases/v0.4.5.md",
    "docs/releases/v0.4.6.md",
    "knowledge-hub/knowledge-catalog.md",
    "knowledge-hub/knowledge/standards/bilingual-public-private-routing.md",
    "skills/workflow-spec-lite/scripts/validate_spec.ps1",
    "skills/project-bootstrap/scripts/audit_memory_language.ps1",
    "examples/minimal-project/README.md",
    "examples/minimal-project/.agents/AGENTS.md",
    "examples/minimal-project/docs/specs/example-work/spec.md",
    "examples/minimal-project/docs/specs/example-work/tasks.md",
    ".github/workflows/pr-identity-guard.yml",
    ".github/scripts/pr-identity-guard.js"
)
$missingFiles = @($requiredFiles | Where-Object { -not (Test-RequiredPath -RelativePath $_) })

$requiredDirs = @(
    "skills/project-bootstrap",
    "skills/project-context-gate",
    "skills/workflow-spec-lite",
    "skills/memory-governance",
    "knowledge-hub/templates",
    "knowledge-hub/templates/languages/en/project-root",
    "knowledge-hub/templates/languages/en/project-agent",
    "knowledge-hub/templates/languages/zh-CN/project-root",
    "knowledge-hub/templates/languages/zh-CN/project-agent",
    "knowledge-hub/scripts",
    "knowledge-hub/knowledge/experience",
    "knowledge-hub/knowledge/patterns",
    "knowledge-hub/knowledge/standards",
    "knowledge-hub/knowledge/domain-packs",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-root",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/en/project-agent",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-root",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/languages/zh-CN/project-agent"
)
$missingDirs = @($requiredDirs | Where-Object { -not (Test-RequiredPath -RelativePath $_ -Directory) })
$forbiddenDirs = @(
    "knowledge-hub/templates/project-root",
    "knowledge-hub/templates/project-agent",
    "knowledge-hub/templates/project-memory",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/project-root",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/project-agent",
    "skills/project-bootstrap/assets/knowledge-hub-template/templates/project-memory",
    "skills/project-bootstrap/templates/project-memory"
)
$presentForbiddenDirs = @($forbiddenDirs | Where-Object { Test-RequiredPath -RelativePath $_ -Directory })

if ($missingFiles.Count -eq 0 -and $missingDirs.Count -eq 0 -and $presentForbiddenDirs.Count -eq 0) {
    Add-Check "public structure" "PASS" "Required release files, skills, docs, knowledge hub paths, and language-scoped template paths exist; legacy template entry paths are absent."
}
else {
    Add-Check "public structure" "FAIL" "Required public paths are missing or forbidden legacy paths are present." ([ordered]@{ files = $missingFiles; directories = $missingDirs; forbidden_directories = $presentForbiddenDirs })
}

try {
    $trackedRootAgentFiles = @(& git -C $repoRoot ls-files -- ".agents")
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files .agents failed."
    }

    $allAgentPathFiles = @(Get-GitFiles | Where-Object { $_ -match '(^|/)\.agents/' })
    $allowedAgentPathFiles = @($allAgentPathFiles | Where-Object { $_ -notmatch '^\.agents/' })
    $gitignoreText = Get-FileText -RelativePath ".gitignore"
    $hasRootAgentsIgnore = $gitignoreText -match '(?m)^/\.agents/\s*$'

    $script:evidence.memory_boundary = [ordered]@{
        tracked_root_agents = @($trackedRootAgentFiles)
        allowed_non_root_agents_count = $allowedAgentPathFiles.Count
        has_root_anchored_ignore = [bool]$hasRootAgentsIgnore
    }

    if ($trackedRootAgentFiles.Count -gt 0 -or -not $hasRootAgentsIgnore) {
        Add-Check "root agents runtime boundary" "FAIL" "Root .agents runtime memory must be ignored and untracked." $evidence.memory_boundary
    }
    else {
        Add-Check "root agents runtime boundary" "PASS" "Root .agents runtime memory is untracked while non-root template, example, fixture, and generated .agents paths remain allowed." $evidence.memory_boundary
    }
}
catch {
    Add-Check "root agents runtime boundary" "FAIL" $_.Exception.Message
}

try {
    $specVolatileRules = @(
        [ordered]@{ name = "current_branch"; pattern = '(?i)\bCurrent Branch\b' },
        [ordered]@{ name = "origin_main"; pattern = '(?i)\borigin/main\b' },
        [ordered]@{ name = "hosted_checks_pending"; pattern = '(?i)\bhosted\b.*\bchecks?\b.*\bpending\b' },
        [ordered]@{ name = "next_actions"; pattern = '(?i)\bNext Actions\b' },
        [ordered]@{ name = "force_push"; pattern = '(?i)\bforce-?push(?:ing)?\b' },
        [ordered]@{ name = "merge_this_pr"; pattern = '(?i)\bmerge\s+this\s+PR\b' },
        [ordered]@{ name = "publish_branch"; pattern = '(?i)\bpublish\s+branch\b' }
    )
    $specStateAllowlist = @{
        "docs/specs/accepted-stabilization-guardrails/spec.md" = @("origin_main", "force_push", "current_branch")
        "docs/specs/accepted-stabilization-guardrails/tasks.md" = @("origin_main")
        "docs/specs/bootstrap-auto-upgrade/spec.md" = @("force_push")
        "docs/specs/file-based-memory-templates/tasks.md" = @("origin_main")
        "docs/specs/hub-maintenance-hardening/spec.md" = @("force_push")
        "docs/specs/project-memory-template-authority/tasks.md" = @("origin_main")
        "docs/specs/v0-3-0-public-maintenance/spec.md" = @("origin_main", "force_push")
        "docs/specs/v0-3-1-stabilization/spec.md" = @("force_push")
        "docs/specs/v0-4-3-release-record-reconciliation/spec.md" = @("origin_main")
    }

    function Test-SpecStateLineAllowed {
        param(
            [Parameter(Mandatory = $true)][string]$LineText,
            [Parameter(Mandatory = $true)][string]$RuleName
        )

        if ($LineText -match '(?i)\bStop rule\b|Historical note|retrospective|incident|Prevention rule') {
            return $true
        }
        if ($RuleName -eq "force_push" -and $LineText -match '(?i)\bdo not\b|blocked|stop|recovery|retarget|requirement') {
            return $true
        }
        if ($RuleName -eq "origin_main" -and $LineText -match '(?i)\bfinal\b|\bvalidation\b|\bevidence\b|\bcompleted\b|\bmerged\b|\bclosed\b|\bpublished\b|\btag\b') {
            return $true
        }
        return $false
    }

    $specFiles = @(Get-GitFiles | Where-Object {
        $_ -match '^docs/specs/.+/(spec|tasks)\.md$' -and $_ -notmatch '^docs/specs/_templates/'
    })
    $allowedSpecMatches = New-Object 'System.Collections.Generic.List[object]'
    $unexpectedSpecMatches = New-Object 'System.Collections.Generic.List[object]'

    foreach ($file in $specFiles) {
        foreach ($rule in $specVolatileRules) {
            foreach ($match in @(Get-LineMatches -RelativePath $file -Pattern $rule.pattern)) {
                $isAllowed = $false
                if ($specStateAllowlist.ContainsKey($file) -and $rule.name -in @($specStateAllowlist[$file])) {
                    $isAllowed = $true
                }
                elseif (Test-SpecStateLineAllowed -LineText ([string]$match.text) -RuleName ([string]$rule.name)) {
                    $isAllowed = $true
                }

                $entry = [ordered]@{
                    rule = [string]$rule.name
                    path = [string]$match.path
                    line = [int]$match.line
                    text = [string]$match.text
                    allowed = [bool]$isAllowed
                }

                if ($isAllowed) {
                    $allowedSpecMatches.Add([object]$entry)
                }
                else {
                    $unexpectedSpecMatches.Add([object]$entry)
                }
            }
        }
    }

    $script:evidence.spec_state_boundary = [ordered]@{
        scanned_files = $specFiles.Count
        allowed_matches = @($allowedSpecMatches.ToArray())
        unexpected_matches = @($unexpectedSpecMatches.ToArray())
        allowlist_files = @($specStateAllowlist.Keys)
    }

    if ($unexpectedSpecMatches.Count -gt 0) {
        Add-Check "spec state boundary" "FAIL" "Public specs contain volatile active-state language outside the historical evidence allowlist." @($unexpectedSpecMatches.ToArray())
    }
    else {
        Add-Check "spec state boundary" "PASS" "Public specs keep volatile active-state patterns out of long-lived records or confine them to historical evidence, stop-rule, and retrospective allowlists." $evidence.spec_state_boundary
    }
}
catch {
    Add-Check "spec state boundary" "FAIL" $_.Exception.Message
}

try {
    $legacyReferencePattern = 'templates/project-root|templates/project-agent|templates/project-memory|project-bootstrap/templates/project-memory'
    $allowedLegacyReferenceFiles = @(
        "CHANGELOG.md",
        "docs/release-readiness.md",
        "docs/releases/v0.4.1.md",
        "docs/releases/v0.4.2.md",
        "docs/template-path-reference-audit.md",
        "scripts/validation/release-repository-checks.ps1",
        "scripts/validation/release-documentation-checks.ps1",
        "scripts/validation/release-project-template-checks.ps1",
        "scripts/validate-release.ps1",
        "skills/project-bootstrap/scripts/init_hub.ps1"
    )
    $legacyMatches = New-Object 'System.Collections.Generic.List[object]'
    $unexpectedLegacyMatches = New-Object 'System.Collections.Generic.List[object]'

    foreach ($file in @(Get-GitFiles)) {
        foreach ($match in @(Get-LineMatches -RelativePath $file -Pattern $legacyReferencePattern)) {
            $legacyMatches.Add([object]$match)
            $isAllowed = $false

            if ($file -in $allowedLegacyReferenceFiles) {
                $isAllowed = $true
            }
            elseif ($file -like "docs/specs/*") {
                $fileText = Get-FileText -RelativePath $file
                $isAllowed = ($fileText -match "Historical note:" -and $fileText -match "(legacy|superseded|removed|negative validation)")
            }

            if (-not $isAllowed) {
                $unexpectedLegacyMatches.Add([object]$match)
            }
        }
    }

    $script:evidence.legacy_template_references = [ordered]@{
        total_matches = $legacyMatches.Count
        unexpected_matches = @($unexpectedLegacyMatches.ToArray())
        allowed_files = @($allowedLegacyReferenceFiles)
    }

    if ($unexpectedLegacyMatches.Count -gt 0) {
        Add-Check "legacy template path references" "FAIL" "Legacy template path references appeared outside allowed validator, remediation, or marked historical records." @($unexpectedLegacyMatches.ToArray())
    }
    else {
        Add-Check "legacy template path references" "PASS" ("Legacy template path references are limited to validator/remediation logic or marked historical records ({0} matches)." -f $legacyMatches.Count) $evidence.legacy_template_references
    }
}
catch {
    Add-Check "legacy template path references" "FAIL" $_.Exception.Message
}

try {
    $upgradeGuide = Get-FileText -RelativePath "docs/existing-project-upgrade.md"
    $adaptGuide = Get-FileText -RelativePath "docs/how-to-adapt.md"
    $bootstrapReadme = Get-FileText -RelativePath "skills/project-bootstrap/README.md"
    $upgradeTokens = @(
        "language-scoped project-memory templates",
        "templates/languages/<language>/project-root|project-agent",
        "project-specific memory",
        ".agents/context/experience",
        ".agents/context/patterns",
        ".agents/context/standards",
        "analyze -> plan -> backup -> apply -> validate",
        "memory_upgrade.ps1",
        "-Mode Analyze",
        "-AnalyzeMemoryUpgrade",
        "missing scaffold files",
        "memory-only and no-edit",
        "Do not recreate legacy template directories",
        "ApplyMemoryUpgrade",
        "Validate"
    )
    $missingUpgradeTokens = @(Get-MissingRequiredText -Text $upgradeGuide -RequiredText $upgradeTokens)
    $missingLinks = @()
    if ($adaptGuide -notlike "*existing project upgrade path*") {
        $missingLinks += "docs/how-to-adapt.md missing existing project upgrade path link."
    }
    if ($bootstrapReadme -notlike "*docs/existing-project-upgrade.md*") {
        $missingLinks += "skills/project-bootstrap/README.md missing existing project upgrade guide link."
    }

    if ($missingUpgradeTokens.Count -gt 0 -or $missingLinks.Count -gt 0) {
        Add-Check "existing project upgrade path" "FAIL" "Existing project upgrade guidance is incomplete." ([ordered]@{
            missing_tokens = @($missingUpgradeTokens)
            missing_links = @($missingLinks)
        })
    }
    else {
        Add-Check "existing project upgrade path" "PASS" "Existing project upgrade guidance covers language-scoped templates, memory preservation, conservative flow, old path handling, and validation."
    }
}
catch {
    Add-Check "existing project upgrade path" "FAIL" $_.Exception.Message
}

try {
    $boundaryDocPath = "docs/project-bootstrap-command-boundaries.md"
    $boundaryDoc = Get-FileText -RelativePath $boundaryDocPath
    $upgradeGuide = Get-FileText -RelativePath "docs/existing-project-upgrade.md"
    $bootstrapReadme = Get-FileText -RelativePath "skills/project-bootstrap/README.md"
    $boundaryTokens = @(
        "scaffold creation",
        "safe refresh",
        "explicit force reset",
        "legacy memory upgrade wrappers",
        "conservative project-memory language migration wrappers",
        "future old-release upgrade orchestration",
        "memory_upgrade.ps1",
        "language_migration.ps1",
        "audit_memory_language.ps1",
        "check_hub_lock.ps1",
        "Dedicated upgrade orchestration helper",
        "Release-to-release upgrade rehearsals should live in a dedicated helper or command card",
        "Standalone Runtime Packaging",
        "copy-mode and link-mode",
        "#96 covers staged modularization",
        "#97 covers shared PowerShell path helpers",
        "#118 covers old-release upgrade validation"
    )
    $missingBoundaryTokens = @(Get-MissingRequiredText -Text $boundaryDoc -RequiredText $boundaryTokens)
    $missingBoundaryLinks = @()
    if ($upgradeGuide -notlike "*project-bootstrap-command-boundaries.md*") {
        $missingBoundaryLinks += "docs/existing-project-upgrade.md missing command boundary design note link."
    }
    if ($bootstrapReadme -notlike "*docs/project-bootstrap-command-boundaries.md*") {
        $missingBoundaryLinks += "skills/project-bootstrap/README.md missing command boundary design note link."
    }

    $script:evidence.bootstrap_command_boundary = [ordered]@{
        design_note = $boundaryDocPath
        missing_tokens = @($missingBoundaryTokens)
        missing_links = @($missingBoundaryLinks)
    }

    if ($missingBoundaryTokens.Count -gt 0 -or $missingBoundaryLinks.Count -gt 0) {
        Add-Check "project-bootstrap command boundaries" "FAIL" "Project-bootstrap command boundary documentation is incomplete." $evidence.bootstrap_command_boundary
    }
    else {
        Add-Check "project-bootstrap command boundaries" "PASS" "Project-bootstrap command ownership, compatibility aliases, future upgrade orchestration, and standalone packaging boundaries are documented." $evidence.bootstrap_command_boundary
    }
}
catch {
    Add-Check "project-bootstrap command boundaries" "FAIL" $_.Exception.Message
}

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

try {
    $pathGuardHelper = Get-FileText -RelativePath "scripts/lib/path-guard.ps1"
    $pathGuardConsumers = @("scripts/benchmark-context-gate.ps1", "scripts/install.ps1", "scripts/prune-validation-scratch.ps1", "scripts/uninstall.ps1", "scripts/validate-release.ps1")
    $missingDotSource = New-Object 'System.Collections.Generic.List[string]'
    $localDefinitions = New-Object 'System.Collections.Generic.List[string]'

    foreach ($functionName in @("Join-PathParts", "Assert-PathInsideRoot", "Assert-NotLiveRuntime")) {
        if ($pathGuardHelper -notmatch ("(?m)^function\s+{0}\s*\{{" -f [regex]::Escape($functionName))) {
            $localDefinitions.Add("scripts/lib/path-guard.ps1 missing $functionName")
        }
    }

    foreach ($consumer in $pathGuardConsumers) {
        $consumerText = Get-FileText -RelativePath $consumer
        if ($consumerText -notmatch 'lib/path-guard\.ps1') {
            $missingDotSource.Add("$consumer does not dot-source scripts/lib/path-guard.ps1")
        }
        foreach ($functionName in @("Join-PathParts", "Assert-PathInsideRoot", "Assert-NotLiveRuntime")) {
            if ($consumerText -match ("(?m)^function\s+{0}\s*\{{" -f [regex]::Escape($functionName))) {
                $localDefinitions.Add("$consumer still defines $functionName locally")
            }
        }
    }

    if ($missingDotSource.Count -eq 0 -and $localDefinitions.Count -eq 0) {
        Add-Check "shared path guard helper" "PASS" "Installer and release validator use the shared PowerShell path guard helper." ([ordered]@{
            helper = "scripts/lib/path-guard.ps1"
            consumers = @($pathGuardConsumers)
        })
    }
    else {
        Add-Check "shared path guard helper" "FAIL" "Shared path guard helper wiring is incomplete." ([ordered]@{
            missing_dot_source = @($missingDotSource.ToArray())
            local_definitions = @($localDefinitions.ToArray())
        })
    }
}
catch {
    Add-Check "shared path guard helper" "FAIL" $_.Exception.Message
}

try {
    $helperOwnershipDoc = Get-FileText -RelativePath "docs/powershell-helper-ownership.md"
    $allowedJoinPathPartsDefinitions = @(
        "knowledge-hub/scripts/promote_experience.ps1",
        "knowledge-hub/scripts/rebuild_experience_index.ps1",
        "knowledge-hub/scripts/search_experience.ps1",
        "scripts/lib/path-guard.ps1",
        "skills/project-bootstrap/scripts/audit_memory_language.ps1",
        "skills/project-bootstrap/scripts/bootstrap_project.ps1",
        "skills/project-bootstrap/scripts/check_hub_lock.ps1",
        "skills/project-bootstrap/scripts/init_hub.ps1",
        "skills/project-bootstrap/scripts/language_migration.ps1",
        "skills/project-bootstrap/scripts/promote_experience.ps1",
        "skills/project-bootstrap/scripts/rebuild_experience_index.ps1",
        "skills/project-bootstrap/scripts/set_project_language.ps1",
        "skills/project-context-gate/scripts/context_gate.ps1"
    )
    $definitionPattern = "(?m)^function\s+Join-PathParts\s*\{"
    $actualDefinitions = New-Object 'System.Collections.Generic.List[string]'

    foreach ($relativePath in @(Get-GitFiles | Where-Object {
                ($_ -like "scripts/*.ps1" -or $_ -like "scripts/**/*.ps1" -or
                    $_ -like "skills/*.ps1" -or $_ -like "skills/**/*.ps1" -or
                    $_ -like "knowledge-hub/*.ps1" -or $_ -like "knowledge-hub/**/*.ps1")
            })) {
        $text = Get-FileText -RelativePath $relativePath
        if ($text -match $definitionPattern) {
            $actualDefinitions.Add(($relativePath -replace "\\", "/"))
        }
    }

    $actual = @($actualDefinitions.ToArray() | Sort-Object -Unique)
    $allowed = @($allowedJoinPathPartsDefinitions | Sort-Object -Unique)
    $unexpectedDefinitions = @($actual | Where-Object { $_ -notin $allowed })
    $missingDefinitions = @($allowed | Where-Object { $_ -notin $actual })
    $docMarkers = @(
        "Repository maintenance scripts",
        "Installed skill runtime scripts",
        "Knowledge hub installed runtime scripts",
        "Intentional Duplication",
        "Compatibility Copies",
        "scripts/lib/path-guard.ps1"
    )
    $missingDocMarkers = @(Get-MissingRequiredText -Text $helperOwnershipDoc -RequiredText $docMarkers)

    if ($unexpectedDefinitions.Count -eq 0 -and $missingDefinitions.Count -eq 0 -and $missingDocMarkers.Count -eq 0) {
        Add-Check "PowerShell helper ownership allowlist" "PASS" "Join-PathParts definitions match the documented helper ownership model." ([ordered]@{
            ownership_doc = "docs/powershell-helper-ownership.md"
            allowed_definitions = @($allowed)
        })
    }
    else {
        Add-Check "PowerShell helper ownership allowlist" "FAIL" "Join-PathParts helper ownership guard found drift." ([ordered]@{
            unexpected_definitions = @($unexpectedDefinitions)
            missing_definitions = @($missingDefinitions)
            missing_doc_markers = @($missingDocMarkers)
        })
    }
}
catch {
    Add-Check "PowerShell helper ownership allowlist" "FAIL" $_.Exception.Message
}

try {
    $releaseHelper = Get-FileText -RelativePath "scripts/validation/release-test-helper.ps1"
    $validatorText = Get-FileText -RelativePath "scripts/validate-release.ps1"
    $helperFunctions = @(
        "ConvertTo-DisplayPath",
        "Add-Check",
        "Test-RequiredPath",
        "Get-GitFiles",
        "Get-FileText",
        "Get-LineMatches",
        "Get-MissingRequiredText",
        "Get-ValidationFilesByExtension",
        "Test-BytesHaveUtf8Bom",
        "Test-BytesHaveNonAscii",
        "Get-PowerShellParseError",
        "Get-CurrentPowerShellPath",
        "Get-PowerShellFileArguments",
        "Invoke-IsolatedPowerShellScript",
        "Test-ExactArray"
    )
    $helperErrors = New-Object 'System.Collections.Generic.List[string]'

    if ($validatorText -notmatch 'validation/release-test-helper\.ps1') {
        $helperErrors.Add("scripts/validate-release.ps1 does not dot-source scripts/validation/release-test-helper.ps1")
    }
    foreach ($functionName in $helperFunctions) {
        if ($releaseHelper -notmatch ("(?m)^function\s+{0}\s*\{{" -f [regex]::Escape($functionName))) {
            $helperErrors.Add("scripts/validation/release-test-helper.ps1 missing $functionName")
        }
        if ($validatorText -match ("(?m)^function\s+{0}\s*\{{" -f [regex]::Escape($functionName))) {
            $helperErrors.Add("scripts/validate-release.ps1 still defines $functionName locally")
        }
    }

    if ($helperErrors.Count -eq 0) {
        Add-Check "release validation helper" "PASS" "Release validator uses the shared validation helper for common test utilities." ([ordered]@{
            helper = "scripts/validation/release-test-helper.ps1"
            functions = @($helperFunctions)
        })
    }
    else {
        Add-Check "release validation helper" "FAIL" "Release validation helper wiring is incomplete." @($helperErrors.ToArray())
    }
}
catch {
    Add-Check "release validation helper" "FAIL" $_.Exception.Message
}

$skillNames = @("project-bootstrap", "project-context-gate", "workflow-spec-lite", "memory-governance")
$metadataErrors = New-Object 'System.Collections.Generic.List[string]'
foreach ($skillName in $skillNames) {
    $skillPath = "skills/$skillName/SKILL.md"
    $content = Get-FileText -RelativePath $skillPath
    foreach ($line in @("category: kernel", "stability: stable", "scope: cross-project")) {
        $pattern = "(?m)^\s*{0}\s*$" -f [regex]::Escape($line)
        if ($content -notmatch $pattern) {
            $metadataErrors.Add("$skillPath missing $line")
        }
    }
    # Slice 2: verify metadata map exists with matching category / stability / scope
    if ($content -notmatch '(?m)^\s*metadata:\s*$') {
        $metadataErrors.Add("$skillPath missing metadata map")
    }
    else {
        $frontmatterMatch = [regex]::Match($content, '(?s)^---\s*\n(.*?)\n---', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($frontmatterMatch.Success) {
            $frontmatter = $frontmatterMatch.Groups[1].Value
            if ($frontmatter -match '(?s)metadata:\s*\n((?:\s+.*\n?)*)') {
                $metadataBlock = $Matches[1]
                foreach ($metaField in @("category: kernel", "stability: stable", "scope: cross-project")) {
                    $metaPattern = "(?m)^\s*{0}\s*$" -f [regex]::Escape($metaField)
                    if ($metadataBlock -notmatch $metaPattern) {
                        $metadataErrors.Add("$skillPath metadata map missing $metaField")
                    }
                }
            }
            else {
                $metadataErrors.Add("$skillPath metadata map is empty or malformed")
            }
        }
    }
}
if ($metadataErrors.Count -eq 0) {
    Add-Check "skill metadata" "PASS" "All Workflow Kernel skills include category, stability, scope metadata, and a consistent metadata map."
}
else {
    Add-Check "skill metadata" "FAIL" "Skill metadata mismatch." @($metadataErrors.ToArray())
}

# Slice 3: verify compatibility field exists with stable tokens
$compatErrors = New-Object 'System.Collections.Generic.List[string]'
foreach ($skillName in $skillNames) {
    $skillPath = "skills/$skillName/SKILL.md"
    $content = Get-FileText -RelativePath $skillPath
    if ($content -notmatch '(?m)^\s*compatibility:\s*\S') {
        $compatErrors.Add("$skillPath missing compatibility field")
    }
    else {
        foreach ($token in @("PowerShell 7+", "metadata", "aliases")) {
            if ($content -notmatch [regex]::Escape($token)) {
                $compatErrors.Add("$skillPath compatibility field missing token: $token")
            }
        }
    }
}
if ($compatErrors.Count -eq 0) {
    Add-Check "skill compatibility" "PASS" "All Workflow Kernel skills declare compatibility with stable tokens for PowerShell requirement, metadata layer, and alias support."
}
else {
    Add-Check "skill compatibility" "FAIL" "Skill compatibility field is missing or incomplete." @($compatErrors.ToArray())
}

}
