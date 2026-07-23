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
        "classifier", "required", "actual", "decisions", "contracts", "run", "checks", "artifact_digests"
    )) { $payload[$name] = $Evidence.$name }
    $Evidence.canonical_evidence_digest = Get-Sha256Text ($payload | ConvertTo-Json -Depth 20 -Compress)
    return
}
function New-Evidence([int]$Pr, [string]$Base, [string]$Head, [string]$Tree, [string[]]$Sequence, [string[]]$Digests, [string]$Combined) {
    $check = {
        param([string]$Run, [string]$Job)
        return [pscustomobject][ordered]@{
            run_id = $Run; run_attempt = "1"; job_id = $Job; check_name = $Job; conclusion = "success"
            head_sha = $Head; pr_number = $Pr
        }
    }
    $evidence = [pscustomobject][ordered]@{
        schema_version = 2; proof_kind = "canonical-candidate-evidence"; generated_at_utc = "2026-07-23T00:00:00Z"
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
        run = [pscustomobject][ordered]@{ id = "1001"; attempt = "1" }
        checks = [pscustomobject][ordered]@{
            base_guard = & $check "2001" "3001"
            identity_guard = & $check "2002" "3002"
            final_gate = & $check "1001" "3003"
        }
        artifact_digests = @([pscustomobject][ordered]@{ path = "fragment/evidence-manifest.json"; sha256 = New-Hex "1" 64 })
        canonical_evidence_digest = ""
    }
    Set-EvidenceDigest $evidence
    return $evidence
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
        "mixed-attempt" { $e.checks.base_guard.run_attempt = "2" }
        "workflow-identity" { $e.contracts.workflow = "wrong" }
        "routing-identity" { $e.contracts.routing = "wrong" }
        "gate-identity" { $e.contracts.gate = "wrong" }
        "base-guard-missing" { $e.checks.base_guard.job_id = "" }
        "base-guard-fail" { $e.checks.base_guard.conclusion = "failure" }
        "identity-guard-missing" { $e.checks.identity_guard.job_id = "" }
        "identity-guard-fail" { $e.checks.identity_guard.conclusion = "failure" }
        "final-gate-missing" { $e.checks.final_gate.job_id = "" }
        "final-gate-fail" { $e.checks.final_gate.conclusion = "failure" }
        "suite-closure" { $e.actual.suites = @() }
        "host-closure" { $e.actual.hosts = @() }
        "classifier-fallback" { $e.classifier.conservative_fallback = $true }
        "control-plane" { $e.change.paths = @("M`t.github/workflows/release-validation.yml") }
        "second-proof-missing" { $Fixture.proofs = @($Fixture.proofs | Select-Object -First 1) }
        default { throw "Unknown mutation '$Mutation'." }
    }
    foreach ($p in @($Fixture.proofs)) { Set-EvidenceDigest $p.evidence }
}

[System.IO.Directory]::CreateDirectory($scratch) | Out-Null
try {
    # NOTE: 显式数组类型保持 fixture 顺序，确保同一输入矩阵产生确定输出。
    $matrixText = [System.IO.File]::ReadAllText($casesPath)
    [object[]]$matrixRecords = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $matrixText
    if ($null -eq $matrixRecords -or $matrixRecords.Length -eq 0) {
        throw "Lineage fixture matrix is empty."
    }
    $results = New-Object 'System.Collections.Generic.List[object]'
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
    $summary = [ordered]@{ schema_version = 1; pass = $results.Count; fail = 0; cases = @($results.ToArray()) }
    if ($Json) { $summary | ConvertTo-Json -Depth 5 } else { Write-Output "lineage verifier fixtures: PASS=$($results.Count) FAIL=0" }
}
finally {
    if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
