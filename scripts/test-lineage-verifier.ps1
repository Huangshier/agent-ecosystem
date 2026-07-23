[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$verifier = Join-Path $PSScriptRoot "validation/lineage-verifier.ps1"
$casesPath = Join-Path $PSScriptRoot "validation/lineage-verifier-fixtures/cases.json"
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-lineage-fixtures-" + [Guid]::NewGuid().ToString("N"))

function New-Hex([string]$Character, [int]$Length = 40) { return ($Character * $Length) }
function Get-Sha256Text([string]$Text) {
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant() }
    finally { $hash.Dispose() }
}
function Set-EvidenceDigest([object]$Evidence) {
    $payload = [ordered]@{}
    foreach ($name in @(
        "schema_version", "proof_kind", "repository", "pr_number", "base", "head", "candidate", "change",
        "classifier", "required", "actual", "decisions", "contracts", "generation", "checks", "artifact_digests"
    )) { $payload[$name] = $Evidence.$name }
    $Evidence.canonical_evidence_digest = Get-Sha256Text ($payload | ConvertTo-Json -Depth 20 -Compress)
    return
}
function New-Evidence([int]$Pr, [string]$Base, [string]$Head, [string]$Tree, [string[]]$Sequence, [string[]]$Digests, [string]$Combined) {
    $evidence = [pscustomobject][ordered]@{
        schema_version = 3; proof_kind = "canonical-candidate-evidence"; generated_at_utc = "2026-07-23T00:00:00Z"
        freshness = [pscustomobject][ordered]@{ status = "fresh"; expires_at_utc = "2099-01-01T00:00:00Z"; retention_hours = 72 }
        repository = "Huangshier/agent-ecosystem"; pr_number = $Pr
        base = [pscustomobject][ordered]@{ ref = "main"; sha = $Base }
        head = [pscustomobject][ordered]@{
            ref = "feature"; sha = $Head; merge_base = $Base; commit_sequence = $Sequence; ordered_change_digests = $Digests
        }
        candidate = [pscustomobject][ordered]@{
            sha = New-Hex "c"; tree = $Tree; ordered_parents = @($Base, $Head); source = "refs/pull/$Pr/merge"
        }
        change = [pscustomobject][ordered]@{ combined_digest = $Combined; paths = @("M`tREADME.md") }
        classifier = [pscustomobject][ordered]@{
            schema_version = 2; detected_tier = 2; affected_modules = @("docs"); conservative_fallback = $false; escalation_reason = ""
            control_plane = $false; self_protection_required = $false; self_protection_reason = "not-tier-3"
        }
        required = [pscustomobject][ordered]@{
            suites = @("documentation-contract"); hosts = @("ubuntu-latest"); windows_powershell = $false; self_protection = $false
        }
        actual = [pscustomobject][ordered]@{ suites = @("documentation-contract"); hosts = @("ubuntu-latest"); fragment_count = 1 }
        decisions = [pscustomobject][ordered]@{ windows_powershell = "not-required"; self_protection = "not-required" }
        contracts = [pscustomobject][ordered]@{
            workflow = ".github/workflows/release-validation.yml"
            routing = "scripts/validation/change-risk-rules.json"
            gate = "scripts/validation/required-validation-gate.ps1"
        }
        generation = [pscustomobject][ordered]@{
            repository = "Huangshier/agent-ecosystem"; pr_number = $Pr; run_id = "1001"; run_attempt = "1"
        }
        checks = [pscustomobject][ordered]@{
            final_gate = [pscustomobject][ordered]@{
                schema_version = 1; proof_kind = "final-validation-gate"; repository = "Huangshier/agent-ecosystem"
                pr_number = $Pr; head_sha = $Head; run_id = "1001"; run_attempt = "1"
                job = "validation-gate"; check_name = "validation gate"; conclusion = "success"
            }
        }
        artifact_digests = @([pscustomobject][ordered]@{ path = "fragment/evidence-manifest.json"; sha256 = New-Hex "1" 64 })
        canonical_evidence_digest = ""
    }
    Set-EvidenceDigest $evidence
    return $evidence
}
function Set-ClassifierControlPlane([object]$Evidence) {
    $Evidence.classifier.control_plane = $true
    $Evidence.classifier.self_protection_required = $true
    $Evidence.classifier.self_protection_reason = "self-protection-control-surface"
    $Evidence.required.self_protection = $true
    $Evidence.required.hosts = @("ubuntu-latest", "windows-latest")
    $Evidence.actual.hosts = @("ubuntu-latest", "windows-latest")
    $Evidence.decisions.self_protection = "required-and-passed"
}
function New-Proof([int]$Pr, [object]$Evidence) {
    return [pscustomobject][ordered]@{
        pr_number = $Pr; pr_base_sha = [string]$Evidence.base.sha; pr_head_sha = [string]$Evidence.head.sha; evidence = $Evidence
    }
}
function New-LineageFixtureInput([string]$Template) {
    $base = New-Hex "a"; $head = New-Hex "b"; $tree = New-Hex "d"; $landed1 = New-Hex "e"; $landed2 = New-Hex "f"
    if ($Template -ceq "merge") {
        $e = New-Evidence 1 $base $head $tree @($head) @("patch-1") "combined-1"
        return [pscustomobject][ordered]@{
            schema_version = 1; repository = "Huangshier/agent-ecosystem"; before = $base; sha = $landed1; forced = $false; range_complete = $true
            commits = @([pscustomobject][ordered]@{
                sha = $landed1; tree = $tree; parents = @($base, $head); associated_prs = @(1)
                combined_change_digest = "combined-1"; ordered_change_digest = ""
            })
            proofs = @((New-Proof -Pr 1 -Evidence $e))
        }
    }
    if ($Template -ceq "single") {
        $e = New-Evidence 1 $base $head $tree @($head) @("patch-1") "combined-1"
        return [pscustomobject][ordered]@{
            schema_version = 1; repository = "Huangshier/agent-ecosystem"; before = $base; sha = $landed1; forced = $false; range_complete = $true
            commits = @([pscustomobject][ordered]@{
                sha = $landed1; tree = $tree; parents = @($base); associated_prs = @(1)
                combined_change_digest = "combined-1"; ordered_change_digest = "patch-1"
            })
            proofs = @((New-Proof -Pr 1 -Evidence $e))
        }
    }
    if ($Template -ceq "collapsed") {
        $head2 = New-Hex "c"
        $e = New-Evidence 1 $base $head2 $tree @($head, $head2) @("patch-1", "patch-2") "combined-12"
        return [pscustomobject][ordered]@{
            schema_version = 1; repository = "Huangshier/agent-ecosystem"; before = $base; sha = $landed1; forced = $false; range_complete = $true
            commits = @([pscustomobject][ordered]@{
                sha = $landed1; tree = $tree; parents = @($base); associated_prs = @(1)
                combined_change_digest = "combined-12"; ordered_change_digest = "collapsed"
            })
            proofs = @((New-Proof -Pr 1 -Evidence $e))
        }
    }
    if ($Template -ceq "replayed") {
        $head2 = New-Hex "c"
        $e = New-Evidence 1 $base $head2 $tree @($head, $head2) @("patch-1", "patch-2") "combined-12"
        return [pscustomobject][ordered]@{
            schema_version = 1; repository = "Huangshier/agent-ecosystem"; before = $base; sha = $landed2; forced = $false; range_complete = $true
            commits = @(
                [pscustomobject][ordered]@{
                    sha = $landed1; tree = New-Hex "9"; parents = @($base); associated_prs = @(1)
                    combined_change_digest = "partial"; ordered_change_digest = "patch-1"
                },
                [pscustomobject][ordered]@{
                    sha = $landed2; tree = $tree; parents = @($landed1); associated_prs = @(1)
                    combined_change_digest = "partial-2"; ordered_change_digest = "patch-2"
                }
            )
            proofs = @((New-Proof -Pr 1 -Evidence $e))
        }
    }
    if ($Template -ceq "multi-pr") {
        $tree2 = New-Hex "8"; $final = New-Hex "9"; $head2 = New-Hex "c"
        $e1 = New-Evidence 1 $base $head $tree @($head) @("patch-1") "combined-1"
        $e2 = New-Evidence 2 $landed1 $head2 $tree2 @($head2) @("patch-2") "combined-2"
        return [pscustomobject][ordered]@{
            schema_version = 1; repository = "Huangshier/agent-ecosystem"; before = $base; sha = $final; forced = $false; range_complete = $true
            commits = @(
                [pscustomobject][ordered]@{
                    sha = $landed1; tree = $tree; parents = @($base, $head); associated_prs = @(1)
                    combined_change_digest = "combined-1"; ordered_change_digest = ""
                },
                [pscustomobject][ordered]@{
                    sha = $final; tree = $tree2; parents = @($landed1); associated_prs = @(2)
                    combined_change_digest = "combined-2"; ordered_change_digest = "patch-2"
                }
            )
            proofs = @(
                (New-Proof -Pr 1 -Evidence $e1),
                (New-Proof -Pr 2 -Evidence $e2)
            )
        }
    }
    throw "Unknown fixture template '$Template'."
}
function Apply-Mutation([object]$Fixture, [string]$Mutation) {
    $proof = if (@($Fixture.proofs).Count) { @($Fixture.proofs)[0] } else { $null }
    $e = if ($proof) { $proof.evidence } else { $null }
    if ($Mutation -notin @("missing-association", "ambiguous-association", "forced", "zero-before", "range-incomplete", "omit-landed-commit", "extra-landed-commit") -and $null -eq $e) {
        throw "Fixture mutation '$Mutation' is missing evidence. proofs=$($Fixture.proofs | ConvertTo-Json -Depth 4 -Compress)"
    }
    switch ($Mutation) {
        "none" {}
        "candidate-sha-differs" { $e.candidate.sha = New-Hex "7" }
        "missing-association" { @($Fixture.commits)[0].associated_prs = @() }
        "ambiguous-association" { @($Fixture.commits)[0].associated_prs = @(1, 2) }
        "forced" { $Fixture.forced = $true }
        "zero-before" { $Fixture.before = New-Hex "0" }
        "range-incomplete" { $Fixture.range_complete = $false }
        "omit-landed-commit" { $Fixture.commits = @($Fixture.commits | Select-Object -First 1) }
        "extra-landed-commit" {
            $last = @($Fixture.commits)[-1]; $extra = [pscustomobject][ordered]@{
                sha = New-Hex "7"; tree = [string]$last.tree; parents = @([string]$last.sha); associated_prs = @($last.associated_prs)
                combined_change_digest = "extra"; ordered_change_digest = "extra"
            }
            $Fixture.commits = @($Fixture.commits) + $extra; $Fixture.sha = [string]$extra.sha
        }
        "base-drift" { $proof.pr_base_sha = New-Hex "7" }
        "head-drift" { $proof.pr_head_sha = New-Hex "7" }
        "tree-mismatch" { @($Fixture.commits)[-1].tree = New-Hex "7" }
        "parent-mismatch" {
            $firstCommit = @($Fixture.commits)[0]
            $firstCommit.parents = @(@($firstCommit.parents)[0], (New-Hex "7"))
        }
        "reorder-digests" { @($Fixture.commits)[0].ordered_change_digest = "patch-2"; @($Fixture.commits)[1].ordered_change_digest = "patch-1" }
        "extra-digest" { @($Fixture.commits)[-1].ordered_change_digest = "patch-extra" }
        "missing-artifact" { $e.artifact_digests = @() }
        "expired" { $e.freshness.expires_at_utc = "2020-01-01T00:00:00Z" }
        "mixed-attempt" { $e.checks.final_gate.run_attempt = "2" }
        "workflow-identity" { $e.contracts.workflow = "wrong" }
        "routing-identity" { $e.contracts.routing = "wrong" }
        "gate-identity" { $e.contracts.gate = "wrong" }
        "generation-repository-mismatch" { $e.generation.repository = "wrong/repository" }
        "generation-pr-mismatch" { $e.generation.pr_number = 999 }
        "generation-run-mismatch" { $e.generation.run_id = "9999" }
        "generation-attempt-mismatch" { $e.generation.run_attempt = "2" }
        "final-gate-missing" { $e.checks.final_gate.job = "" }
        "final-gate-fail" { $e.checks.final_gate.conclusion = "failure" }
        "suite-closure" { $e.actual.suites = @() }
        "host-closure" { $e.actual.hosts = @() }
        "classifier-fallback" { $e.classifier.conservative_fallback = $true }
        "control-plane" {
            # NOTE: 状态机 fixture 仅提供 classifier 已判定的 authority，不让 lineage 再按路径推导。
            $e.change.paths = @("M`t.github/workflows/release-validation.yml")
            Set-ClassifierControlPlane $e
        }
        "second-proof-missing" { $Fixture.proofs = @($Fixture.proofs | Select-Object -First 1) }
        default { throw "Unknown mutation '$Mutation'." }
    }
    foreach ($p in @($Fixture.proofs)) { Set-EvidenceDigest $p.evidence }
}
function Invoke-GenerationResolutionFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][object[]]$Runs,
        [Parameter(Mandatory = $true)][object[]]$Artifacts,
        [Parameter(Mandatory = $true)][string]$ExpectedDecision,
        [string]$ExpectedReason = ""
    )
    $fixtureInput = New-LineageFixtureInput "single"
    $fixtureInput | Add-Member -NotePropertyName generation_fixture -NotePropertyValue ([pscustomobject][ordered]@{
        pr_number = 1
        base_sha = New-Hex "a"
        head_sha = New-Hex "b"
        merged_at = "2026-07-24T00:00:00Z"
        runs = $Runs
        artifacts = $Artifacts
    })
    $inputPath = Join-Path $scratch "$Name-input.json"
    $outputPath = Join-Path $scratch "$Name-observation.json"
    $fixtureInput | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $inputPath -Encoding UTF8
    & $verifier -InputPath $inputPath -OutputPath $outputPath | Out-Null
    $observation = Get-Content -Raw $outputPath | ConvertFrom-Json
    if ([string]$observation.decision -cne $ExpectedDecision) {
        throw "Generation fixture '$Name' expected '$ExpectedDecision', got '$($observation.decision)'."
    }
    if ($ExpectedReason -and @($observation.fallback_reasons) -notcontains $ExpectedReason) {
        throw "Generation fixture '$Name' did not record '$ExpectedReason'."
    }
    return [ordered]@{ name = $Name; decision = [string]$observation.decision; status = "PASS" }
}
function New-ReleaseRun(
    [string]$Id,
    [string]$CreatedAt,
    [string]$Head,
    [string]$Attempt,
    [string]$Conclusion = "success"
) {
    return [pscustomobject][ordered]@{
        id = $Id
        created_at = $CreatedAt
        event = "pull_request"
        head_sha = $Head
        run_attempt = $Attempt
        status = "completed"
        conclusion = $Conclusion
        display_title = "Release validation #1 synchronize $Head"
        pull_requests = @([pscustomobject]@{ number = 1 })
    }
}
function New-GenerationArtifact([object]$Evidence, [string]$RunId, [string]$Attempt, [string]$Head) {
    return [pscustomobject][ordered]@{
        name = "canonical-candidate-evidence-pr-1-$Head-run-$RunId-attempt-$Attempt"
        expired = $false
        workflow_run = [pscustomobject][ordered]@{ id = $RunId; head_sha = $Head }
        evidence = $Evidence
    }
}
function Invoke-ClassifierAuthorityFixture {
    param(
        [string]$Name,
        [scriptblock]$Mutation,
        [string]$ExpectedReason,
        [switch]$SkipDigestRefresh
    )

    $fixtureInput = New-LineageFixtureInput "single"
    & $Mutation $fixtureInput
    if (-not $SkipDigestRefresh.IsPresent) {
        foreach ($proof in @($fixtureInput.proofs)) { Set-EvidenceDigest $proof.evidence }
    }
    $inputPath = Join-Path $scratch "$Name-input.json"
    $outputPath = Join-Path $scratch "$Name-observation.json"
    $fixtureInput | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $inputPath -Encoding UTF8
    & $verifier -InputPath $inputPath -OutputPath $outputPath | Out-Null
    $observation = Get-Content -Raw $outputPath | ConvertFrom-Json
    if ([string]$observation.decision -cne "full-fallback") {
        throw "Classifier authority fixture '$Name' must fail closed."
    }
    if ($ExpectedReason -and @($observation.fallback_reasons) -cnotcontains $ExpectedReason) {
        throw "Classifier authority fixture '$Name' did not record '$ExpectedReason'."
    }
    return [ordered]@{ name = $Name; decision = [string]$observation.decision; status = "PASS" }
}

[System.IO.Directory]::CreateDirectory($scratch) | Out-Null
try {
    # NOTE: 40-case JSON matrix 只覆盖 lineage 判定状态机；真实 Git 输入与 digest parity
    # 由 test-exact-candidate-contract.ps1 的双宿主 bare-remote fixture 覆盖。
    $matrixText = [System.IO.File]::ReadAllText($casesPath)
    [object[]]$matrixRecords = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $matrixText
    if ($null -eq $matrixRecords -or $matrixRecords.Length -eq 0) {
        throw "Lineage fixture matrix is empty."
    }
    $results = New-Object 'System.Collections.Generic.List[object]'
    $authorityResults = New-Object 'System.Collections.Generic.List[object]'
    $generationResults = New-Object 'System.Collections.Generic.List[object]'
    $singleCommitSemantics = @{}
    for ($fixtureIndex = 0; $fixtureIndex -lt $matrixRecords.Length; $fixtureIndex++) {
        $fixtureRecord = $matrixRecords[$fixtureIndex]
        $fixtureInput = New-LineageFixtureInput ([string]$fixtureRecord.template)
        Apply-Mutation $fixtureInput ([string]$fixtureRecord.mutation) | Out-Null
        $inputPath = Join-Path $scratch "$($fixtureRecord.name)-input.json"
        $outputPath = Join-Path $scratch "$($fixtureRecord.name)-observation.json"
        $fixtureInput | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $inputPath -Encoding UTF8
        & $verifier -InputPath $inputPath -OutputPath $outputPath | Out-Null
        $observation = Get-Content -Raw $outputPath | ConvertFrom-Json
        if ([string]$observation.decision -cne [string]$fixtureRecord.decision) {
            throw "Fixture '$($fixtureRecord.name)' expected '$($fixtureRecord.decision)', got '$($observation.decision)': $(@($observation.fallback_reasons) -join ', ')."
        }
        if ([string]$fixtureRecord.decision -ceq "proven" -and [string]$fixtureRecord.proof_class -cne "multiple") {
            if (@($observation.groups).Count -ne 1 -or [string]@($observation.groups)[0].proof_class -cne [string]$fixtureRecord.proof_class) {
                throw "Fixture '$($fixtureRecord.name)' proof class mismatch."
            }
        }
        if ([string]$fixtureRecord.name -in @("single-commit-squash", "single-commit-rebase")) {
            $group = @($observation.groups)[0]
            if ([string]$group.actual_merge_method -cne "not-observable" -or
                (@($group.compatible_merge_methods) -join ",") -cne "squash,rebase") {
                throw "Single-commit linearized proof must preserve squash/rebase equivalence."
            }
            $singleCommitSemantics[[string]$fixtureRecord.name] = [ordered]@{
                decision = [string]$observation.decision
                proof_class = [string]$group.proof_class
                actual_merge_method = [string]$group.actual_merge_method
                compatible_merge_methods = @($group.compatible_merge_methods)
            }
        }
        $results.Add([ordered]@{ name = [string]$fixtureRecord.name; decision = [string]$observation.decision; status = "PASS" }) | Out-Null
    }
    $squashSemantics = $singleCommitSemantics["single-commit-squash"] | ConvertTo-Json -Depth 5 -Compress
    $rebaseSemantics = $singleCommitSemantics["single-commit-rebase"] | ConvertTo-Json -Depth 5 -Compress
    if ($squashSemantics -cne $rebaseSemantics) {
        throw "Single-commit squash and rebase fixtures must produce identical observable proof semantics."
    }
    $generationHead = New-Hex "b"
    $generationBase = New-Hex "a"
    $generationTree = New-Hex "d"
    $oldRun = New-ReleaseRun -Id "1001" -CreatedAt "2026-07-23T10:00:00Z" -Head $generationHead -Attempt "2"
    $latestRun = New-ReleaseRun -Id "1002" -CreatedAt "2026-07-23T11:00:00Z" -Head $generationHead -Attempt "1"
    $latestEvidence = New-Evidence 1 $generationBase $generationHead $generationTree @($generationHead) @("patch-1") "combined-1"
    $latestEvidence.generation.run_id = "1002"
    $latestEvidence.checks.final_gate.run_id = "1002"
    Set-EvidenceDigest $latestEvidence
    $oldEvidence = New-Evidence 1 $generationBase $generationHead $generationTree @($generationHead) @("patch-1") "combined-1"
    $generationResults.Add((Invoke-GenerationResolutionFixture -Name "latest-run-same-head-fresh-generation" `
        -Runs @($oldRun, $latestRun) `
        -Artifacts @(
            (New-GenerationArtifact -Evidence $oldEvidence -RunId "1001" -Attempt "2" -Head $generationHead),
            (New-GenerationArtifact -Evidence $latestEvidence -RunId "1002" -Attempt "1" -Head $generationHead)
        ) -ExpectedDecision "proven")) | Out-Null

    $rerunAllRun = New-ReleaseRun -Id "2001" -CreatedAt "2026-07-23T12:00:00Z" -Head $generationHead -Attempt "2"
    $rerunAllEvidence = New-Evidence 1 $generationBase $generationHead $generationTree @($generationHead) @("patch-1") "combined-1"
    $rerunAllEvidence.generation.run_id = "2001"
    $rerunAllEvidence.generation.run_attempt = "2"
    $rerunAllEvidence.checks.final_gate.run_id = "2001"
    $rerunAllEvidence.checks.final_gate.run_attempt = "2"
    Set-EvidenceDigest $rerunAllEvidence
    $generationResults.Add((Invoke-GenerationResolutionFixture -Name "rerun-all-latest-attempt-complete" `
        -Runs @($rerunAllRun) `
        -Artifacts @((New-GenerationArtifact -Evidence $rerunAllEvidence -RunId "2001" -Attempt "2" -Head $generationHead)) `
        -ExpectedDecision "proven")) | Out-Null

    $rerunFailedRun = New-ReleaseRun -Id "3001" -CreatedAt "2026-07-23T13:00:00Z" -Head $generationHead -Attempt "2"
    $rerunFailedEvidence = New-Evidence 1 $generationBase $generationHead $generationTree @($generationHead) @("patch-1") "combined-1"
    $rerunFailedEvidence.generation.run_id = "3001"
    $rerunFailedEvidence.checks.final_gate.run_id = "3001"
    Set-EvidenceDigest $rerunFailedEvidence
    $generationResults.Add((Invoke-GenerationResolutionFixture -Name "rerun-failed-no-current-canonical" `
        -Runs @($rerunFailedRun) `
        -Artifacts @((New-GenerationArtifact -Evidence $rerunFailedEvidence -RunId "3001" -Attempt "1" -Head $generationHead)) `
        -ExpectedDecision "full-fallback" -ExpectedReason "missing-latest-generation-evidence")) | Out-Null

    $mixedEvidence = New-Evidence 1 $generationBase $generationHead $generationTree @($generationHead) @("patch-1") "combined-1"
    $mixedEvidence.generation.run_id = "4001"
    $mixedEvidence.checks.final_gate.run_id = "4001"
    Set-EvidenceDigest $mixedEvidence
    $mixedRun = New-ReleaseRun -Id "4001" -CreatedAt "2026-07-23T14:00:00Z" -Head $generationHead -Attempt "2"
    $generationResults.Add((Invoke-GenerationResolutionFixture -Name "mixed-generation-rejected" `
        -Runs @($mixedRun) `
        -Artifacts @((New-GenerationArtifact -Evidence $mixedEvidence -RunId "4001" -Attempt "2" -Head $generationHead)) `
        -ExpectedDecision "full-fallback" -ExpectedReason "candidate-evidence-run-mismatch")) | Out-Null

    $newerFailedRun = New-ReleaseRun -Id "5002" -CreatedAt "2026-07-23T16:00:00Z" -Head $generationHead -Attempt "1" -Conclusion "failure"
    $olderSuccessfulRun = New-ReleaseRun -Id "5001" -CreatedAt "2026-07-23T15:00:00Z" -Head $generationHead -Attempt "3"
    $olderSuccessfulEvidence = New-Evidence 1 $generationBase $generationHead $generationTree @($generationHead) @("patch-1") "combined-1"
    $olderSuccessfulEvidence.generation.run_id = "5001"
    $olderSuccessfulEvidence.generation.run_attempt = "3"
    $olderSuccessfulEvidence.checks.final_gate.run_id = "5001"
    $olderSuccessfulEvidence.checks.final_gate.run_attempt = "3"
    Set-EvidenceDigest $olderSuccessfulEvidence
    $generationResults.Add((Invoke-GenerationResolutionFixture -Name "stale-success-generation-not-used" `
        -Runs @($olderSuccessfulRun, $newerFailedRun) `
        -Artifacts @((New-GenerationArtifact -Evidence $olderSuccessfulEvidence -RunId "5001" -Attempt "3" -Head $generationHead)) `
        -ExpectedDecision "full-fallback" -ExpectedReason "latest-generation-not-successful")) | Out-Null

    foreach ($path in @(
        "scripts/test-exact-candidate-contract.ps1",
        "scripts/test-lineage-verifier.ps1",
        "scripts/validation/lineage-verifier-fixtures/cases.json"
    )) {
        $pathForFixture = $path
        $authorityResults.Add((Invoke-ClassifierAuthorityFixture -Name ("classifier-control-plane-{0}" -f ($pathForFixture -replace '[^A-Za-z0-9]+', '-').Trim('-')) -ExpectedReason "classifier-control-plane" -Mutation {
            param($fixture)
            $evidence = @($fixture.proofs)[0].evidence
            $evidence.change.paths = @("M`t$pathForFixture")
            Set-ClassifierControlPlane $evidence
        })) | Out-Null
    }
    $authorityResults.Add((Invoke-ClassifierAuthorityFixture -Name "classifier-authority-missing" -ExpectedReason "evidence-contract-invalid" -Mutation {
        param($fixture)
        @($fixture.proofs)[0].evidence.classifier.PSObject.Properties.Remove("control_plane")
    })) | Out-Null
    $authorityResults.Add((Invoke-ClassifierAuthorityFixture -Name "classifier-authority-unknown" -ExpectedReason "evidence-contract-invalid" -Mutation {
        param($fixture)
        @($fixture.proofs)[0].evidence.classifier.control_plane = "unknown"
    })) | Out-Null
    $authorityResults.Add((Invoke-ClassifierAuthorityFixture -Name "classifier-authority-unknown-reason" -ExpectedReason "evidence-contract-invalid" -Mutation {
        param($fixture)
        @($fixture.proofs)[0].evidence.classifier.self_protection_reason = "future-self-protection-reason"
    })) | Out-Null
    $authorityResults.Add((Invoke-ClassifierAuthorityFixture -Name "classifier-authority-inconsistent" -ExpectedReason "classifier-authority-inconsistent" -Mutation {
        param($fixture)
        $evidence = @($fixture.proofs)[0].evidence
        $evidence.classifier.self_protection_required = $true
        $evidence.classifier.self_protection_reason = "self-protection-control-surface"
    })) | Out-Null
    $authorityResults.Add((Invoke-ClassifierAuthorityFixture -Name "classifier-field-digest-tamper" -ExpectedReason "evidence-digest-mismatch" -SkipDigestRefresh -Mutation {
        param($fixture)
        @($fixture.proofs)[0].evidence.classifier.control_plane = $true
    })) | Out-Null
    $verifierSource = [System.IO.File]::ReadAllText($verifier)
    $forbiddenPathDerivedFallback = '"control-plane-' + 'change"'
    if ($verifierSource.Contains($forbiddenPathDerivedFallback) -or $verifierSource.Contains("change.paths |")) {
        throw "Lineage verifier retains a path-derived control-plane authority."
    }
    $summary = [ordered]@{
        schema_version = 1
        pass = $results.Count + $authorityResults.Count + $generationResults.Count
        fail = 0
        cases = @($results.ToArray())
        state_machine_matrix = [ordered]@{ pass = $results.Count; cases = $matrixRecords.Length; status = "PASS" }
        classifier_authority = @($authorityResults.ToArray())
        generation_resolution = @($generationResults.ToArray())
    }
    if ($Json) { $summary | ConvertTo-Json -Depth 5 } else { Write-Output "lineage verifier fixtures: PASS=$($results.Count) FAIL=0" }
}
finally {
    if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
