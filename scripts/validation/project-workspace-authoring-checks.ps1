# Focused Slice D verifier for canonical authoring and Procedure -> Skill promotion.
# It uses isolated scratch projects and never mutates the repository under test.

[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { [IO.Path]::GetFullPath($RepositoryRoot) }
$dispatcher = Join-Path $repoRoot "skills/project-workspace/scripts/project-workspace.ps1"
$parser = Join-Path $repoRoot "skills/project-workspace/scripts/read-project-assets.ps1"
$scratchParent = if ([string]::IsNullOrWhiteSpace($ScratchRoot)) { [IO.Path]::GetTempPath() } else { [IO.Path]::GetFullPath($ScratchRoot) }
$runRoot = Join-Path $scratchParent ("project-workspace-authoring-{0}" -f ([Guid]::NewGuid().ToString("N")))
$cases = New-Object 'System.Collections.Generic.List[object]'

function Add-Case {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    [void]$cases.Add([ordered]@{ name = $Name; status = $(if ($Passed) { "PASS" } else { "FAIL" }); detail = $Detail })
}

function Get-TreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath $Root -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)) {
            $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            [void]$lines.Add(("{0}|{1}" -f $relative, $hash))
        }
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($lines.ToArray() -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Invoke-WorkspaceJson {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$OperationParameters)
    $text = @(& $dispatcher @OperationParameters 2>$null) -join "`n"
    if ([string]::IsNullOrWhiteSpace($text)) { throw "workspace operation returned no structured result" }
    try { return ($text | ConvertFrom-Json -Depth 100 -DateKind String -ErrorAction Stop) }
    catch { throw "workspace operation returned malformed JSON" }
}

function Invoke-WorkspaceFileJson {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments)

    $processArguments = @("-NoProfile", "-NonInteractive", "-File", $dispatcher) + @($Arguments) + @("-Json")
    $output = @(& pwsh @processArguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = [int]$LASTEXITCODE
    $text = $output -join "`n"
    if ([string]::IsNullOrWhiteSpace($text)) { throw "pwsh -File workspace operation returned no structured result" }
    try { $payload = $text | ConvertFrom-Json -Depth 100 -DateKind String -ErrorAction Stop }
    catch { throw "pwsh -File workspace operation returned malformed JSON" }
    return [ordered]@{ exit_code = $exitCode; payload = $payload; text = $text }
}

function Invoke-ParserJson {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$AssetPath = ""
    )
    if ([string]::IsNullOrWhiteSpace($AssetPath)) {
        $text = @(& $parser -ProjectRoot $Root -IncludeMetadata -NoExit -Json 2>$null) -join "`n"
    }
    else {
        $text = @(& $parser -ProjectRoot $Root -AssetPath $AssetPath -IncludeMetadata -NoExit -Json 2>$null) -join "`n"
    }
    if ([string]::IsNullOrWhiteSpace($text)) { throw "parser returned no structured result" }
    try { return ($text | ConvertFrom-Json -Depth 100 -DateKind String -ErrorAction Stop) }
    catch { throw "parser returned malformed JSON" }
}

function Test-StandardSkillFrontMatter {
    param([Parameter(Mandatory = $true)][string]$Text)

    $lines = @($Text -split "`n")
    if ($lines.Count -lt 3 -or $lines[0] -cne "---") { return $false }
    $closing = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ([string]$lines[$index] -ceq "---") { $closing = $index; break }
    }
    if ($closing -lt 0) { return $false }
    $allowed = @("name", "description", "compatibility", "metadata", "allowed-tools", "license")
    $keys = @($lines[1..($closing - 1)] | Where-Object { $_ -match '^(?<key>[a-z][a-z0-9-]*):' } | ForEach-Object { [string]$matches.key })
    return ($keys.Count -eq @($keys | Sort-Object -Unique).Count -and
        @($keys | Where-Object { $allowed -notcontains $_ }).Count -eq 0 -and
        $keys -contains "name" -and $keys -contains "description")
}

function Test-RelativeOutput {
    param([AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -notmatch '^(?:[A-Za-z]:|[\\/])' -and $Value -notmatch '(^|[\\/])\.\.?(?:[\\/]|$)')
}

function Test-PublicCandidate {
    param([AllowEmptyString()][string]$Value)
    if (-not (Test-RelativeOutput -Value ".agents/skills/slice-d/SKILL.md")) { return $false }
    return ($Value -notmatch '(?i)(?:[A-Za-z]:[\\/]|\\\\|/(?:users|home|private|var|tmp)/|(?:ghp_|github_pat_|bearer\s+[a-z0-9._-]{12,}|AKIA[0-9A-Z]{16}))')
}

try {
    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    foreach ($relativeDirectory in @(".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $runRoot $relativeDirectory) | Out-Null
    }
    [IO.File]::WriteAllText((Join-Path $runRoot "AGENTS.md"), "# Fixture project instructions`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $runRoot ".agents/README.md"), "# Fixture C3.3 workspace`n", [Text.UTF8Encoding]::new($false))

    $contextParameters = [ordered]@{
        Operation = "create-context"; ProjectRoot = $runRoot; Id = "slice-d-context"; Title = "Slice D context";
        Summary = "A stable public-safe fact."; Keywords = @("slice-d", "context"); Evidence = @("verified fixture evidence"); Json = $true
    }
    $procedureParameters = [ordered]@{
        Operation = "create-procedure"; ProjectRoot = $runRoot; Id = "slice-d-procedure"; Title = "Slice D procedure";
        Kind = "command"; Summary = "A bounded internal procedure."; Triggers = @("run fixture"); SideEffects = @("writes fixture output");
        Preconditions = @("fixture is ready"); Steps = @("inspect the fixture"); Validation = @("parser passes");
        StopBoundaries = @("stop on validation failure"); Authorization = @("explicit approval remains required"); Json = $true
    }
    $specParameters = [ordered]@{
        Operation = "create-spec"; ProjectRoot = $runRoot; Id = "slice-d-spec"; Title = "Slice D spec";
        Summary = "A stable bounded design."; Goals = @("implement the bounded behavior"); NonGoals = @("automatic execution");
        Tradeoffs = @("small public surface"); Acceptance = @("focused verifier passes"); RelatedWork = @(); Supersedes = @(); Json = $true
    }

    $context = Invoke-WorkspaceJson -OperationParameters $contextParameters
    $procedure = Invoke-WorkspaceJson -OperationParameters $procedureParameters
    $spec = Invoke-WorkspaceJson -OperationParameters $specParameters
    $createdValid = ($context.status -ceq "PASS" -and $procedure.status -ceq "PASS" -and $spec.status -ceq "PASS" -and
        [string]$context.path -ceq ".agents/context/slice-d-context.md" -and
        [string]$procedure.path -ceq ".agents/procedures/slice-d-procedure.md" -and
        [string]$spec.path -ceq "docs/specs/slice-d-spec/spec.md")
    Add-Case -Name "create-valid-context-procedure-spec" -Passed $createdValid -Detail "Context, Procedure, and Spec creation returned canonical repository-relative paths."

    $parserTokens = $null
    $parseErrors = $null
    $dispatcherAst = [Management.Automation.Language.Parser]::ParseFile($dispatcher, [ref]$parserTokens, [ref]$parseErrors)
    $publicListParameters = @($dispatcherAst.ParamBlock.Parameters | Where-Object { $_.StaticType -eq [string[]] } | ForEach-Object { $_.Name.VariablePath.UserPath } | Sort-Object)
    $listAssignment = $dispatcherAst.Find({
            param($node)
            $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$script:ProjectWorkspaceListParameters'
        }, $true)
    $normalizedListParameters = if ($null -eq $listAssignment) { @() } else {
        @($listAssignment.Right.FindAll({ param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value } | Sort-Object)
    }
    $listCoverage = (@($parseErrors).Count -eq 0 -and $publicListParameters.Count -eq 20 -and
        $publicListParameters.Count -eq $normalizedListParameters.Count -and
        @((Compare-Object -ReferenceObject $publicListParameters -DifferenceObject $normalizedListParameters -CaseSensitive)).Count -eq 0)
    Add-Case -Name "all-public-list-parameters-normalized" -Passed $listCoverage -Detail "All 20 public string-array parameters, including StopBoundaries, are registered with the shared list-input normalizer."

    $skillText = [IO.File]::ReadAllText((Join-Path $repoRoot "skills/project-workspace/SKILL.md"), [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $walkthroughText = [IO.File]::ReadAllText((Join-Path $repoRoot "docs/walkthroughs/minimal-project-adoption.md"), [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $skillSpecLine = @($skillText -split "`n" | Where-Object { $_ -match 'project-workspace\.ps1 -Operation create-spec' })[0]
    $walkthroughSpecLine = @($walkthroughText -split "`n" | Where-Object { $_ -match 'project-workspace\.ps1 -Operation create-spec' })[0]
    $documentedExamples = ($skillText.Contains('-Type ''json:["work","spec"]'' -Status ''json:["active","draft"]''', [StringComparison]::Ordinal) -and
        $skillText.Contains('`StopBoundaries`', [StringComparison]::Ordinal) -and
        $skillSpecLine.Contains("-Goals <goal>", [StringComparison]::Ordinal) -and
        -not $skillSpecLine.Contains("-RelatedWork", [StringComparison]::Ordinal) -and
        -not $skillSpecLine.Contains("-Supersedes", [StringComparison]::Ordinal) -and
        $walkthroughSpecLine.Contains("-Goals <goal>", [StringComparison]::Ordinal) -and
        $walkthroughSpecLine.Contains("-Acceptance <criterion>", [StringComparison]::Ordinal) -and
        -not $walkthroughSpecLine.Contains("-RelatedWork", [StringComparison]::Ordinal) -and
        -not $walkthroughSpecLine.Contains("-Supersedes", [StringComparison]::Ordinal))
    Add-Case -Name "public-list-examples-match-contract" -Passed $documentedExamples -Detail "The Skill and minimal walkthrough publish the JSON-array filter form and an executable unassociated create-spec command."

    $cliRoot = Join-Path $runRoot "cli-subprocess"
    foreach ($relativeDirectory in @(".agents/work", ".agents/context", ".agents/procedures", ".agents/skills", "docs/specs")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $cliRoot $relativeDirectory) | Out-Null
    }
    [IO.File]::WriteAllText((Join-Path $cliRoot "AGENTS.md"), "# CLI fixture project instructions`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $cliRoot ".agents/README.md"), "# CLI fixture C3.3 workspace`n", [Text.UTF8Encoding]::new($false))

    $cliSpecOmitted = Invoke-WorkspaceFileJson -Arguments @(
        "-Operation", "create-spec", "-ProjectRoot", $cliRoot, "-Id", "cli-spec-omitted",
        "-Title", "CLI spec omitted relations", "-Summary", "Created through a fresh pwsh process.",
        "-Status", "draft", "-Goals", "prove the public entrypoint", "-NonGoals", "change schema semantics",
        "-Tradeoffs", "one explicit list encoding", "-Acceptance", "the child process succeeds"
    )
    $cliSpecOmittedText = [IO.File]::ReadAllText((Join-Path $cliRoot "docs/specs/cli-spec-omitted/spec.md"), [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $omittedRelations = ($cliSpecOmitted.exit_code -eq 0 -and $cliSpecOmitted.payload.status -ceq "PASS" -and
        $cliSpecOmittedText -match '(?m)^related_work: \[\]$' -and $cliSpecOmittedText -match '(?m)^supersedes: \[\]$')
    Add-Case -Name "file-create-spec-omits-empty-relations" -Passed $omittedRelations -Detail "A fresh pwsh -File process created a valid unassociated Spec while omitting RelatedWork and Supersedes."

    $cliSpecEmpty = Invoke-WorkspaceFileJson -Arguments @(
        "-Operation", "create-spec", "-ProjectRoot", $cliRoot, "-Id", "cli-spec-empty",
        "-Title", "CLI spec explicit empty relations", "-Summary", "Created through a fresh pwsh process.",
        "-Goals", "prove explicit empty lists", "-NonGoals", "change relation semantics",
        "-Tradeoffs", "one explicit list encoding", "-Acceptance", "the child process succeeds",
        "-RelatedWork", "json:[]", "-Supersedes", "json:[]"
    )
    $cliSpecEmptyText = [IO.File]::ReadAllText((Join-Path $cliRoot "docs/specs/cli-spec-empty/spec.md"), [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $explicitEmptyRelations = ($cliSpecEmpty.exit_code -eq 0 -and $cliSpecEmpty.payload.status -ceq "PASS" -and
        $cliSpecEmptyText -match '(?m)^related_work: \[\]$' -and $cliSpecEmptyText -match '(?m)^supersedes: \[\]$')
    Add-Case -Name "file-create-spec-explicit-empty-relations" -Passed $explicitEmptyRelations -Detail "Explicit JSON empty arrays remained bound empty lists through pwsh -File."

    $cliWork = Invoke-WorkspaceFileJson -Arguments @(
        "-Operation", "create-work", "-ProjectRoot", $cliRoot, "-Id", "cli-list-work",
        "-Title", "CLI list work", "-Summary", "Created through a child process.", "-Next", "checkpoint the work",
        "-ContinuityReason", "unfinished", "-Status", "active", "-Updated", "2026-08-30T00:00:00Z"
    )
    $verifiedJson = "json:" + (ConvertTo-Json -InputObject ([string[]]@("Parser output, exact", "Second verified fact")) -Compress)
    $cliCheckpoint = Invoke-WorkspaceFileJson -Arguments @(
        "-Operation", "checkpoint", "-ProjectRoot", $cliRoot, "-Id", "cli-list-work",
        "-BaseRevision", [string]$cliWork.payload.revision, "-Verified", $verifiedJson, "-Updated", "2026-08-30T00:01:00Z"
    )
    $cliWorkText = [IO.File]::ReadAllText((Join-Path $cliRoot ".agents/work/cli-list-work.md"), [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $verifiedPreserved = ($cliWork.exit_code -eq 0 -and $cliWork.payload.status -ceq "PASS" -and
        $cliCheckpoint.exit_code -eq 0 -and $cliCheckpoint.payload.status -ceq "PASS" -and
        $cliWorkText.Contains("- Parser output, exact`n- Second verified fact", [StringComparison]::Ordinal))
    Add-Case -Name "file-checkpoint-multi-verified-preserves-comma" -Passed $verifiedPreserved -Detail "A JSON string array crossed pwsh -File as two Verified values and preserved the natural-language comma exactly."

    $cliSingleContext = Invoke-WorkspaceFileJson -Arguments @(
        "-Operation", "create-context", "-ProjectRoot", $cliRoot, "-Id", "cli-single-context",
        "-Title", "CLI single context", "-Summary", "Proves ordinary single-value compatibility.",
        "-Keywords", "compatibility", "-Evidence", "[Source], exact"
    )
    $cliSingleContextText = [IO.File]::ReadAllText((Join-Path $cliRoot ".agents/context/cli-single-context.md"), [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    $singleNaturalValue = ($cliSingleContext.exit_code -eq 0 -and $cliSingleContext.payload.status -ceq "PASS" -and
        $cliSingleContextText.Contains('- "[Source], exact"', [StringComparison]::Ordinal))
    Add-Case -Name "file-single-natural-value-compatible" -Passed $singleNaturalValue -Detail "An ordinary single Evidence value beginning with a bracket and containing a comma remained one unchanged value."

    $beforeMalformedList = Get-TreeFingerprint -Root $cliRoot
    $malformedList = Invoke-WorkspaceFileJson -Arguments @(
        "-Operation", "create-context", "-ProjectRoot", $cliRoot, "-Id", "malformed-list",
        "-Title", "Malformed list", "-Summary", "Must fail before authoring.", "-Keywords", 'json:["valid",', "-Evidence", "unchanged"
    )
    $afterMalformedList = Get-TreeFingerprint -Root $cliRoot
    $malformedListClosed = ($malformedList.exit_code -ne 0 -and $malformedList.payload.status -ceq "FAIL" -and
        @($malformedList.payload.findings | Where-Object { [string]$_.code -ceq "invalid-list-input" -and [string]$_.field -ceq "Keywords" }).Count -eq 1 -and
        $beforeMalformedList -ceq $afterMalformedList -and -not (Test-Path -LiteralPath (Join-Path $cliRoot ".agents/context/malformed-list.md")))
    Add-Case -Name "file-malformed-list-fails-closed" -Passed $malformedListClosed -Detail "Malformed structured authoring input returned the stable list-input error before any project write."

    $catalogPath = Join-Path $runRoot ".agents/.cache/catalog.json"
    $createNoCatalog = (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf))
    Add-Case -Name "create-does-not-write-catalog" -Passed $createNoCatalog -Detail "Authoring writes canonical assets only; Catalog remains absent until discover."

    $beforeInvalid = Get-TreeFingerprint -Root $runRoot
    $invalidKind = Invoke-WorkspaceJson -OperationParameters ([ordered]@{
        Operation = "create-procedure"; ProjectRoot = $runRoot; Id = "invalid-kind"; Title = "Invalid kind"; Kind = "scheduler";
        Summary = "Must fail closed."; Json = $true
    })
    $invalidPublic = Invoke-WorkspaceJson -OperationParameters ([ordered]@{
        Operation = "create-context"; ProjectRoot = $runRoot; Id = "invalid-public"; Title = "Invalid output"; Summary = [IO.Path]::GetFullPath("invalid-public-value");
        Keywords = @("invalid"); Evidence = @("should fail"); Json = $true
    })
    $afterInvalid = Get-TreeFingerprint -Root $runRoot
    $invalidClosed = ($invalidKind.status -ceq "FAIL" -and $invalidPublic.status -ceq "FAIL" -and $beforeInvalid -ceq $afterInvalid -and
        -not (Test-Path -LiteralPath (Join-Path $runRoot ".agents/procedures/invalid-kind.md")) -and
        -not (Test-Path -LiteralPath (Join-Path $runRoot ".agents/context/invalid-public.md")))
    Add-Case -Name "invalid-input-fails-closed" -Passed $invalidClosed -Detail "Invalid kind and unsafe output input failed without changing project files."

    $parsedBeforeDiscover = Invoke-ParserJson -Root $runRoot
    $parserReadsCreated = ([string]$parsedBeforeDiscover.status -ceq "PASS" -and [int]$parsedBeforeDiscover.asset_count -eq 3)
    Add-Case -Name "parser-reads-created-assets" -Passed $parserReadsCreated -Detail "Existing parser reads the three newly created canonical assets."

    $discovered = Invoke-WorkspaceJson -OperationParameters ([ordered]@{ Operation = "discover"; ProjectRoot = $runRoot; Query = "Slice D"; Json = $true })
    $discoverReadsCreated = ([string]$discovered.status -ceq "PASS" -and [int]$discovered.result_count -ge 3 -and (Test-Path -LiteralPath $catalogPath -PathType Leaf))
    Add-Case -Name "discover-observes-after-create" -Passed $discoverReadsCreated -Detail "Discover observes canonical creates and is the first operation that writes Catalog."

    $catalogBeforeCheck = (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash
    $checked = Invoke-WorkspaceJson -OperationParameters ([ordered]@{ Operation = "check"; ProjectRoot = $runRoot; Json = $true })
    $checkReadOnly = ([string]$checked.status -ceq "PASS" -and [bool]$checked.read_only -and (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash -ceq $catalogBeforeCheck)
    Add-Case -Name "check-is-read-only" -Passed $checkReadOnly -Detail "Check validates the workspace without changing Catalog or canonical assets."

    $beforeAnalyze = Get-TreeFingerprint -Root $runRoot
    $analysis = Invoke-WorkspaceJson -OperationParameters ([ordered]@{ Operation = "promote-skill"; ProjectRoot = $runRoot; Id = "slice-d-procedure"; Analyze = $true; Json = $true })
    $afterAnalyze = Get-TreeFingerprint -Root $runRoot
    $frontMatterAllowed = Test-StandardSkillFrontMatter -Text ([string]$analysis.candidate)
    $frozenAnalyzeConditions = @(
        "The Procedure has been used repeatedly and is stable.",
        "The Procedure inputs, outputs, and stop conditions are stable.",
        "The Procedure clearly benefits from Agent-native discovery.",
        "The Skill description is not prone to accidental triggering.",
        "The authorization and side_effects boundaries are clear.",
        "The caller has reviewed the generated Skill candidate and understands that Apply deletes the original Procedure."
    )
    $analyzeConditionValues = @($analysis.manual_conditions | ForEach-Object { [string]$_ })
    $analyzeConditionsComplete = ($frozenAnalyzeConditions.Count -eq $analyzeConditionValues.Count)
    foreach ($condition in $frozenAnalyzeConditions) {
        if (-not ($analyzeConditionValues -ccontains $condition)) {
            $analyzeConditionsComplete = $false
            break
        }
    }
    $analyzeReadOnly = ([string]$analysis.status -ceq "PASS" -and [bool]$analysis.read_only -and
        [string]$analysis.candidate_path -ceq ".agents/skills/slice-d-procedure/SKILL.md" -and
        $beforeAnalyze -ceq $afterAnalyze -and
        -not (Test-Path -LiteralPath (Join-Path $runRoot ".agents/skills/slice-d-procedure/SKILL.md")) -and
        $frontMatterAllowed -and
        [string]$analysis.candidate_hash -match '^sha256:[0-9a-f]{64}$' -and
        [string]$analysis.evidence -match '^sha256:[0-9a-f]{64}$' -and
        [string]$analysis.candidate -match 'description:.*Use when.*run fixture' -and
        (Test-PublicCandidate -Value ([string]$analysis.candidate)) -and
        [string]$analysis.candidate -match "## Preconditions" -and
        [string]$analysis.candidate -match "## Steps" -and
        [string]$analysis.candidate -match "## Validation" -and
        [string]$analysis.candidate -match "## Stop Boundaries" -and
        [string]$analysis.candidate -match "## Authorization" -and
        [string]$analysis.candidate -match "writes fixture output")
    Add-Case -Name "promote-analyze-is-read-only" -Passed $analyzeReadOnly -Detail "Analyze emits a deterministic standard Agent Skill candidate and bound evidence without project writes."
    Add-Case -Name "analyze-returns-frozen-manual-conditions" -Passed $analyzeConditionsComplete -Detail "Analyze returns the complete frozen human-review condition list without automatic evaluation."

    $procedurePath = Join-Path $runRoot ".agents/procedures/slice-d-procedure.md"
    $skillPath = Join-Path $runRoot ".agents/skills/slice-d-procedure/SKILL.md"
    $beforeDirectApply = Get-TreeFingerprint -Root $runRoot
    $directApply = Invoke-WorkspaceJson -OperationParameters ([ordered]@{ Operation = "promote-skill"; ProjectRoot = $runRoot; Id = "slice-d-procedure"; Apply = $true; ConfirmPromotion = $true; Json = $true })
    $afterDirectApply = Get-TreeFingerprint -Root $runRoot
    $directApplyClosed = ([string]$directApply.status -ceq "FAIL" -and
        @($directApply.findings | Where-Object { [string]$_.code -ceq "analyze-evidence-required" }).Count -eq 1 -and
        $beforeDirectApply -ceq $afterDirectApply -and
        (Test-Path -LiteralPath $procedurePath -PathType Leaf) -and
        -not (Test-Path -LiteralPath $skillPath -PathType Leaf))
    Add-Case -Name "apply-requires-analyze-evidence" -Passed $directApplyClosed -Detail "Direct Apply without Analyze evidence fails closed without changing the Procedure or creating a Skill."

    $beforeUnconfirmedApply = Get-TreeFingerprint -Root $runRoot
    $unconfirmedApply = Invoke-WorkspaceJson -OperationParameters ([ordered]@{ Operation = "promote-skill"; ProjectRoot = $runRoot; Id = "slice-d-procedure"; Apply = $true; AnalyzeEvidence = [string]$analysis.evidence; Json = $true })
    $afterUnconfirmedApply = Get-TreeFingerprint -Root $runRoot
    $confirmationClosed = ([string]$unconfirmedApply.status -ceq "FAIL" -and
        @($unconfirmedApply.findings | Where-Object { [string]$_.code -ceq "confirmation-required" }).Count -eq 1 -and
        $beforeUnconfirmedApply -ceq $afterUnconfirmedApply -and
        (Test-Path -LiteralPath $procedurePath -PathType Leaf) -and
        -not (Test-Path -LiteralPath $skillPath -PathType Leaf))
    Add-Case -Name "apply-requires-explicit-confirmation" -Passed $confirmationClosed -Detail "Analyze evidence alone is insufficient; Apply requires explicit confirmation of the human promotion conditions."

    $originalProcedureText = [IO.File]::ReadAllText($procedurePath, [Text.UTF8Encoding]::new($false, $true))
    [IO.File]::WriteAllText($procedurePath, ($originalProcedureText + "`n# changed after Analyze`n"), [Text.UTF8Encoding]::new($false))
    $staleApply = Invoke-WorkspaceJson -OperationParameters ([ordered]@{ Operation = "promote-skill"; ProjectRoot = $runRoot; Id = "slice-d-procedure"; Apply = $true; AnalyzeEvidence = [string]$analysis.evidence; ConfirmPromotion = $true; Json = $true })
    $staleClosed = ([string]$staleApply.status -ceq "FAIL" -and
        @($staleApply.findings | Where-Object { [string]$_.code -ceq "stale-analyze-evidence" }).Count -eq 1 -and
        (Test-Path -LiteralPath $procedurePath -PathType Leaf) -and
        -not (Test-Path -LiteralPath $skillPath -PathType Leaf))
    [IO.File]::WriteAllText($procedurePath, $originalProcedureText, [Text.UTF8Encoding]::new($false))
    Add-Case -Name "stale-analyze-evidence-fails-closed" -Passed $staleClosed -Detail "Procedure changes after Analyze invalidate the evidence and leave the source Procedure intact."

    $applied = Invoke-WorkspaceJson -OperationParameters ([ordered]@{ Operation = "promote-skill"; ProjectRoot = $runRoot; Id = "slice-d-procedure"; Apply = $true; AnalyzeEvidence = [string]$analysis.evidence; ConfirmPromotion = $true; Json = $true })
    $applyAuthority = ([string]$applied.status -ceq "PASS" -and [bool]$applied.skill_created -and [bool]$applied.procedure_deleted -and [bool]$applied.no_dual_authority -and
        (Test-Path -LiteralPath $skillPath -PathType Leaf) -and -not (Test-Path -LiteralPath $procedurePath -PathType Leaf))
    Add-Case -Name "promote-apply-removes-procedure" -Passed $applyAuthority -Detail "Valid Analyze evidence plus explicit confirmation creates the standard Skill and removes the original Procedure without dual authority."

    $parsedAfterApply = Invoke-ParserJson -Root $runRoot
    $skillAssetCount = @($parsedAfterApply.assets | Where-Object { [string]$_.type -ceq "skill" }).Count
    $skillPathParser = Invoke-ParserJson -Root $runRoot -AssetPath ".agents/skills/slice-d-procedure/SKILL.md"
    $skillNotCanonical = ([string]$parsedAfterApply.status -ceq "PASS" -and [int]$parsedAfterApply.asset_count -eq 2 -and $skillAssetCount -eq 0 -and
        [string]$skillPathParser.status -ceq "FAIL" -and
        @($skillPathParser.findings | Where-Object { [string]$_.code -ceq "unsafe-path" }).Count -ge 1)
    Add-Case -Name "skill-is-derived-not-canonical" -Passed $skillNotCanonical -Detail "The canonical parser exposes only Work, Context, Procedure, and Spec; a promoted Skill is discovered through the derived reader."

    $discoverAfterApply = Invoke-WorkspaceJson -OperationParameters ([ordered]@{ Operation = "discover"; ProjectRoot = $runRoot; Query = "slice-d-procedure"; Type = @("skill"); Json = $true })
    $checkAfterApply = Invoke-WorkspaceJson -OperationParameters ([ordered]@{ Operation = "check"; ProjectRoot = $runRoot; Json = $true })
    $discoverCheckSkill = ([string]$discoverAfterApply.status -ceq "PASS" -and [int]$discoverAfterApply.result_count -eq 1 -and
        [string]$discoverAfterApply.results[0].type -ceq "skill" -and [string]$checkAfterApply.status -ceq "PASS" -and [bool]$checkAfterApply.read_only)
    Add-Case -Name "discover-and-check-see-single-skill" -Passed $discoverCheckSkill -Detail "After Catalog invalidation, discover and read-only check see one promoted Skill authority."

    $failures = @($cases | Where-Object status -eq "FAIL")
    $summary = [ordered]@{
        schema_version = 1
        status = $(if ($failures.Count -eq 0) { "PASS" } else { "FAIL" })
        scenario_count = $cases.Count
        pass = @($cases | Where-Object status -eq "PASS").Count
        fail = $failures.Count
        canonical_paths = $createdValid
        invalid_input_fail_closed = $invalidClosed
        catalog_written_only_by_discover = $createNoCatalog -and $discoverReadsCreated
        check_read_only = $checkReadOnly
        analyze_read_only = $analyzeReadOnly
        analyze_frozen_manual_conditions = $analyzeConditionsComplete
        frontmatter_allowed_fields = $frontMatterAllowed
        apply_requires_analyze_evidence = $directApplyClosed
        apply_requires_confirmation = $confirmationClosed
        stale_analyze_evidence_closed = $staleClosed
        apply_no_dual_authority = $applyAuthority
        canonical_skill_not_authority = $skillNotCanonical
        authorization_side_effects_preserved = ([string]$analysis.candidate -match "explicit approval remains required" -and [string]$analysis.candidate -match "writes fixture output")
        public_safe = (Test-PublicCandidate -Value ([string]$analysis.candidate))
        parser_discover_reads_new_assets = $parserReadsCreated -and $skillNotCanonical -and $discoverCheckSkill
        cases = @($cases.ToArray())
    }
}
catch {
    Add-Case -Name "verifier-runtime" -Passed $false -Detail "Focused verifier failed closed before completing its contract."
    $failures = @($cases | Where-Object status -eq "FAIL")
    $summary = [ordered]@{
        schema_version = 1
        status = "FAIL"
        scenario_count = $cases.Count
        pass = @($cases | Where-Object status -eq "PASS").Count
        fail = $failures.Count
        cases = @($cases.ToArray())
    }
}
finally {
    if (Test-Path -LiteralPath $runRoot) { [IO.Directory]::Delete($runRoot, $true) }
}

if ($Json.IsPresent) {
    $summary | ConvertTo-Json -Depth 20
}
else {
    Write-Output ("project-workspace Slice D authoring: PASS={0} FAIL={1}" -f $summary.pass, $summary.fail)
    foreach ($case in @($summary.cases)) { Write-Output ("[{0}] {1}" -f $case.status, $case.name) }
}

if ([string]$summary.status -ne "PASS") { exit 1 }
exit 0
