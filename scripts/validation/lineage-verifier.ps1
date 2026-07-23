[CmdletBinding(DefaultParameterSetName = "Fixture")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Fixture")][string]$InputPath,
    [Parameter(Mandatory = $true, ParameterSetName = "Live")][string]$Repository,
    [Parameter(Mandatory = $true, ParameterSetName = "Live")][string]$Before,
    [Parameter(Mandatory = $true, ParameterSetName = "Live")][string]$Sha,
    [Parameter(Mandatory = $true, ParameterSetName = "Live")][string]$GitHubToken,
    [Parameter(ParameterSetName = "Live")][switch]$Forced,
    [Parameter(Mandatory = $true, ParameterSetName = "Live")][string]$ScratchRoot,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$RunId = "fixture-run",
    [string]$RunAttempt = "1",
    [string]$EvaluatorIdentity = "scripts/validation/lineage-verifier.ps1",
    [string]$WorkflowIdentity = ".github/workflows/release-validation.yml",
    [string]$RoutingContractIdentity = "scripts/validation/change-risk-rules.json",
    [string]$GateContractIdentity = "scripts/validation/required-validation-gate.ps1",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "git-stable-patch-id.ps1")

function Read-JsonFile([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($full)) { throw "Lineage input does not exist." }
    try { return [System.IO.File]::ReadAllText($full) | ConvertFrom-Json }
    catch { throw "Lineage input is not valid JSON." }
}
function Get-Sha256Text([string]$Text) {
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant() }
    finally { $hash.Dispose() }
}
function Test-Sha([string]$Value) { return $Value -match '^[0-9a-f]{40}$' }
function Add-Fallback([System.Collections.Generic.List[string]]$Reasons, [string]$Reason) {
    if ([string]::IsNullOrWhiteSpace($Reason)) { return }
    if (-not $Reasons.Contains($Reason)) { $Reasons.Add($Reason) | Out-Null }
}
function Get-CanonicalDigestPayload([object]$Evidence) {
    $payload = [ordered]@{}
    foreach ($name in @(
        "schema_version", "proof_kind", "repository", "pr_number", "base", "head", "candidate", "change",
        "classifier", "required", "actual", "decisions", "contracts", "generation", "checks", "artifact_digests"
    )) {
        if ($Evidence.PSObject.Properties.Name -notcontains $name) { throw "Canonical evidence is missing '$name'." }
        $payload[$name] = $Evidence.$name
    }
    return $payload
}
function Get-RequiredClassifierBoolean([object]$Classifier, [string]$Name) {
    $properties = @($Classifier.PSObject.Properties | Where-Object { $_.Name -ceq $Name })
    if ($properties.Count -ne 1 -or $properties[0].Value -isnot [bool]) {
        throw "Classifier authority field '$Name' must be an actual Boolean."
    }
    return [bool]$properties[0].Value
}
function Get-RequiredClassifierString([object]$Classifier, [string]$Name) {
    $properties = @($Classifier.PSObject.Properties | Where-Object { $_.Name -ceq $Name })
    if ($properties.Count -ne 1 -or $properties[0].Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string]$properties[0].Value)) {
        throw "Classifier authority field '$Name' must be a non-blank string."
    }
    return [string]$properties[0].Value
}
function Test-Evidence([object]$Evidence, [System.Collections.Generic.List[string]]$Reasons, [int]$PrNumber) {
    try {
        if ([int]$Evidence.schema_version -ne 3 -or [string]$Evidence.proof_kind -cne "canonical-candidate-evidence") {
            Add-Fallback $Reasons "evidence-schema-invalid"; return $false
        }
        if ([int]$Evidence.pr_number -ne $PrNumber) { Add-Fallback $Reasons "evidence-pr-mismatch"; return $false }
        if ([string]$Evidence.generation.repository -cne [string]$Evidence.repository -or
            [int]$Evidence.generation.pr_number -ne $PrNumber -or -not [string]$Evidence.generation.run_id -or
            -not [string]$Evidence.generation.run_attempt) {
            Add-Fallback $Reasons "generation-identity-invalid"; return $false
        }
        if ([string]$Evidence.freshness.status -cne "fresh" -or [DateTimeOffset]::Parse([string]$Evidence.freshness.expires_at_utc) -le [DateTimeOffset]::UtcNow) {
            Add-Fallback $Reasons "evidence-expired"; return $false
        }
        $payload = Get-CanonicalDigestPayload $Evidence
        $expectedDigest = Get-Sha256Text ($payload | ConvertTo-Json -Depth 20 -Compress)
        if ([string]$Evidence.canonical_evidence_digest -cne $expectedDigest) { Add-Fallback $Reasons "evidence-digest-mismatch"; return $false }
        if (@($Evidence.artifact_digests).Count -eq 0 -or @($Evidence.artifact_digests | Where-Object { [string]$_.sha256 -notmatch '^[0-9a-f]{64}$' }).Count) {
            Add-Fallback $Reasons "artifact-closure-incomplete"; return $false
        }
        if ([string]$Evidence.contracts.workflow -cne $WorkflowIdentity -or [string]$Evidence.contracts.routing -cne $RoutingContractIdentity -or
            [string]$Evidence.contracts.gate -cne $GateContractIdentity) { Add-Fallback $Reasons "contract-identity-mismatch"; return $false }
        $finalGate = $Evidence.checks.final_gate
        if ($null -eq $finalGate -or [string]$finalGate.repository -cne [string]$Evidence.repository -or
            [int]$finalGate.pr_number -ne $PrNumber -or [string]$finalGate.head_sha -cne [string]$Evidence.head.sha -or
            [string]$finalGate.run_id -cne [string]$Evidence.generation.run_id -or
            [string]$finalGate.run_attempt -cne [string]$Evidence.generation.run_attempt -or
            [string]$finalGate.job -cne "validation-gate" -or [string]$finalGate.check_name -cne "validation gate" -or
            [string]$finalGate.conclusion -cne "success") {
            Add-Fallback $Reasons "final-gate-identity-invalid"; return $false
        }
        $missingSuites = @($Evidence.required.suites | Where-Object { @($Evidence.actual.suites) -cnotcontains [string]$_ })
        $missingHosts = @($Evidence.required.hosts | Where-Object { @($Evidence.actual.hosts) -cnotcontains [string]$_ })
        if ($missingSuites.Count -or $missingHosts.Count) { Add-Fallback $Reasons "suite-host-closure-incomplete"; return $false }
        $controlPlane = Get-RequiredClassifierBoolean $Evidence.classifier "control_plane"
        $selfProtectionRequired = Get-RequiredClassifierBoolean $Evidence.classifier "self_protection_required"
        $conservativeFallback = Get-RequiredClassifierBoolean $Evidence.classifier "conservative_fallback"
        $selfProtectionReason = Get-RequiredClassifierString $Evidence.classifier "self_protection_reason"
        if (@(
            "full-coverage-unproven",
            "unknown-or-ambiguous-input",
            "self-protection-control-surface",
            "not-tier-3",
            "no-control-plane-change"
        ) -cnotcontains $selfProtectionReason) {
            throw "Classifier authority self-protection reason is unknown."
        }
        if ($selfProtectionRequired -ne [bool]$Evidence.required.self_protection) {
            Add-Fallback $Reasons "classifier-authority-inconsistent"; return $false
        }
        $expectedSelfProtectionDecision = if ($selfProtectionRequired) { "required-and-passed" } else { "not-required" }
        if ([string]$Evidence.decisions.self_protection -cne $expectedSelfProtectionDecision) {
            Add-Fallback $Reasons "classifier-authority-inconsistent"; return $false
        }
        if ($controlPlane -and -not $selfProtectionRequired) {
            Add-Fallback $Reasons "classifier-authority-inconsistent"; return $false
        }
        if ($controlPlane) { Add-Fallback $Reasons "classifier-control-plane"; return $false }
        if ($selfProtectionRequired) { Add-Fallback $Reasons "classifier-self-protection-required"; return $false }
        if ($conservativeFallback) { Add-Fallback $Reasons "classifier-fallback"; return $false }
        return $true
    }
    catch {
        Add-Fallback $Reasons "evidence-contract-invalid"
        return $false
    }
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $output = @(& git @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join "`n")" }
    return @($output)
}
function Get-NormalizedDiff([string]$From, [string]$To) {
    return (@(Invoke-Git diff --no-ext-diff --binary --full-index --no-renames $From $To | ForEach-Object { [string]$_ }) -join "`n") + "`n"
}
function Invoke-GitHubRest([string]$Uri) {
    $headers = @{
        Authorization = "Bearer $GitHubToken"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "agent-ecosystem-lineage-shadow"
    }
    return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers
}
function Select-LatestReleaseRun(
    [object[]]$Runs,
    [int]$PrNumber,
    [string]$HeadSha,
    [DateTimeOffset]$MergedAt,
    [System.Collections.Generic.List[string]]$Reasons
) {
    $escapedHead = [regex]::Escape($HeadSha)
    $escapedPr = [regex]::Escape([string]$PrNumber)
    $titlePattern = "^Release validation #$escapedPr [a-z_]+ $escapedHead$"
    $eligible = @($Runs | Where-Object {
        $run = $_
        $createdAt = [DateTimeOffset]::MinValue
        $createdValid = [DateTimeOffset]::TryParse([string]$run.created_at, [ref]$createdAt)
        $associatedPrs = @($run.pull_requests | ForEach-Object { [int]$_.number })
        $associationValid = $associatedPrs.Count -eq 0 -or $associatedPrs -contains $PrNumber
        $createdValid -and $createdAt -le $MergedAt -and [string]$run.event -ceq "pull_request" -and
            [string]$run.head_sha -ceq $HeadSha -and $associationValid -and
            [string]$run.display_title -cmatch $titlePattern
    } | Sort-Object @{ Expression = { [DateTimeOffset]::Parse([string]$_.created_at) }; Descending = $true },
        @{ Expression = { [long]$_.id }; Descending = $true })
    if ($eligible.Count -eq 0) {
        Add-Fallback $Reasons "missing-release-generation"
        return $null
    }
    $latest = $eligible[0]
    if ([string]$latest.status -cne "completed" -or [string]$latest.conclusion -cne "success" -or
        -not [string]$latest.run_attempt) {
        Add-Fallback $Reasons "latest-generation-not-successful"
        return $null
    }
    return $latest
}
function Select-ExactCanonicalArtifact(
    [object[]]$Artifacts,
    [string]$ExpectedName,
    [string]$RunId,
    [string]$HeadSha,
    [string]$NotAfterUtc = "",
    [System.Collections.Generic.List[string]]$Reasons
) {
    $eligible = @($Artifacts | Where-Object {
        $artifactCreatedAt = [DateTimeOffset]::MinValue
        $timeValid = [string]::IsNullOrWhiteSpace($NotAfterUtc) -or
            ([DateTimeOffset]::TryParse([string]$_.created_at, [ref]$artifactCreatedAt) -and
                $artifactCreatedAt -le [DateTimeOffset]::Parse($NotAfterUtc))
        [string]$_.name -ceq $ExpectedName -and -not [bool]$_.expired -and
            $timeValid -and
            ($null -eq $_.workflow_run -or
                ([string]$_.workflow_run.id -ceq $RunId -and [string]$_.workflow_run.head_sha -ceq $HeadSha))
    })
    if ($eligible.Count -ne 1) {
        Add-Fallback $Reasons $(if ($eligible.Count -eq 0) { "missing-latest-generation-evidence" } else { "ambiguous-latest-generation-evidence" })
        return $null
    }
    return $eligible[0]
}
function Resolve-FixtureGeneration([object]$LineageInput) {
    if ($LineageInput.PSObject.Properties.Name -notcontains "generation_fixture") { return $LineageInput }
    $fixture = $LineageInput.generation_fixture
    $fixtureReasons = New-Object 'System.Collections.Generic.List[string]'
    $LineageInput.proofs = @()
    $latest = Select-LatestReleaseRun -Runs @($fixture.runs) -PrNumber ([int]$fixture.pr_number) `
        -HeadSha ([string]$fixture.head_sha) -MergedAt ([DateTimeOffset]::Parse([string]$fixture.merged_at)) -Reasons $fixtureReasons
    if ($null -ne $latest) {
        $artifactName = "canonical-candidate-evidence-pr-$([int]$fixture.pr_number)-$([string]$fixture.head_sha)-run-$([string]$latest.id)-attempt-$([string]$latest.run_attempt)"
        $artifact = Select-ExactCanonicalArtifact -Artifacts @($fixture.artifacts) -ExpectedName $artifactName `
            -RunId ([string]$latest.id) -HeadSha ([string]$fixture.head_sha) -Reasons $fixtureReasons
        if ($null -ne $artifact -and $artifact.PSObject.Properties.Name -contains "evidence") {
            if ([string]$artifact.evidence.generation.run_id -cne [string]$latest.id -or
                [string]$artifact.evidence.generation.run_attempt -cne [string]$latest.run_attempt) {
                Add-Fallback $fixtureReasons "candidate-evidence-run-mismatch"
            }
            else {
                $LineageInput.proofs = @([pscustomobject][ordered]@{
                    pr_number = [int]$fixture.pr_number
                    pr_base_sha = [string]$fixture.base_sha
                    pr_head_sha = [string]$fixture.head_sha
                    evidence = $artifact.evidence
                })
            }
        }
        elseif ($null -ne $artifact) {
            Add-Fallback $fixtureReasons "candidate-evidence-artifact-invalid"
        }
    }
    $combinedReasons = @(@($LineageInput.preflight_fallback_reasons) + @($fixtureReasons.ToArray()))
    if ($LineageInput.PSObject.Properties.Name -contains "preflight_fallback_reasons") {
        $LineageInput.preflight_fallback_reasons = $combinedReasons
    }
    else {
        $LineageInput | Add-Member -NotePropertyName preflight_fallback_reasons -NotePropertyValue $combinedReasons
    }
    return $LineageInput
}
function Get-LiveInput {
    if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw "Repository must use owner/name form." }
    $beforeNormalized = $Before.ToLowerInvariant()
    $shaNormalized = $Sha.ToLowerInvariant()
    if (-not (Test-Sha $shaNormalized)) { throw "Live lineage Sha is invalid." }
    $fallback = New-Object 'System.Collections.Generic.List[string]'
    $commits = New-Object 'System.Collections.Generic.List[object]'
    $proofs = New-Object 'System.Collections.Generic.List[object]'
    $rangeComplete = $true
    if (-not (Test-Sha $beforeNormalized) -or $beforeNormalized -eq ("0" * 40)) {
        $rangeComplete = $false
    }
    else {
        & git cat-file -e "$beforeNormalized^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) { $rangeComplete = $false }
        if ($rangeComplete) {
            & git merge-base --is-ancestor $beforeNormalized $shaNormalized 2>$null
            if ($LASTEXITCODE -ne 0) { $rangeComplete = $false }
        }
    }
    if ($rangeComplete) {
        $range = @(Invoke-Git rev-list --reverse --first-parent "$beforeNormalized..$shaNormalized" | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
        foreach ($commitSha in $range) {
            $parentsLine = [string](@(Invoke-Git show -s --format=%P $commitSha)[0])
            $parents = @($parentsLine.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.ToLowerInvariant() })
            $tree = [string](@(Invoke-Git rev-parse "$commitSha^{tree}")[0]).Trim().ToLowerInvariant()
            $associations = @()
            try {
                $associationResult = Invoke-GitHubRest "https://api.github.com/repos/$Repository/commits/$commitSha/pulls?per_page=100"
                $associations = @($associationResult | ForEach-Object { [int]$_.number })
            }
            catch {
                $fallback.Add("pr-association-unavailable")
            }
            $commits.Add([ordered]@{
                sha = $commitSha
                tree = $tree
                parents = $parents
                associated_prs = $associations
                combined_change_digest = $(if ($parents.Count) { Get-Sha256Text (Get-NormalizedDiff $parents[0] $commitSha) } else { "" })
                ordered_change_digest = $(if ($parents.Count -eq 1) { Get-GitStablePatchId -Parent $parents[0] -Commit $commitSha } else { "" })
            })
        }
    }
    $prNumbers = @($commits.ToArray() | ForEach-Object { @($_.associated_prs) } | Sort-Object -Unique)
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetFullPath($ScratchRoot)) | Out-Null
    foreach ($prNumber in $prNumbers) {
        try {
            $pr = Invoke-GitHubRest "https://api.github.com/repos/$Repository/pulls/$prNumber"
            if (-not [bool]$pr.merged -or -not [string]$pr.merged_at) { $fallback.Add("associated-pr-not-merged"); continue }
            $headSha = ([string]$pr.head.sha).ToLowerInvariant()
            $workflowId = [Uri]::EscapeDataString("release-validation.yml")
            $runsResult = Invoke-GitHubRest "https://api.github.com/repos/$Repository/actions/workflows/$workflowId/runs?event=pull_request&head_sha=$headSha&per_page=100"
            $latest = Select-LatestReleaseRun -Runs @($runsResult.workflow_runs) -PrNumber $prNumber -HeadSha $headSha `
                -MergedAt ([DateTimeOffset]::Parse([string]$pr.merged_at)) -Reasons $fallback
            if ($null -eq $latest) { continue }
            $artifactName = "canonical-candidate-evidence-pr-$prNumber-$headSha-run-$([string]$latest.id)-attempt-$([string]$latest.run_attempt)"
            $encodedName = [Uri]::EscapeDataString($artifactName)
            $artifactResult = Invoke-GitHubRest "https://api.github.com/repos/$Repository/actions/runs/$([string]$latest.id)/artifacts?name=$encodedName&per_page=100"
            $artifact = Select-ExactCanonicalArtifact -Artifacts @($artifactResult.artifacts) -ExpectedName $artifactName `
                -RunId ([string]$latest.id) -HeadSha $headSha -NotAfterUtc ([string]$pr.merged_at) -Reasons $fallback
            if ($null -eq $artifact) { continue }
            $zipPath = Join-Path $ScratchRoot "evidence-$prNumber.zip"
            $extractPath = Join-Path $ScratchRoot "evidence-$prNumber"
            $headers = @{
                Authorization = "Bearer $GitHubToken"; Accept = "application/vnd.github+json"
                "X-GitHub-Api-Version" = "2022-11-28"; "User-Agent" = "agent-ecosystem-lineage-shadow"
            }
            Invoke-WebRequest -Uri "https://api.github.com/repos/$Repository/actions/artifacts/$($artifact.id)/zip" -Headers $headers -OutFile $zipPath
            if (Test-Path $extractPath) { [System.IO.Directory]::Delete($extractPath, $true) }
            Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath
            $manifestFiles = @(Get-ChildItem -LiteralPath $extractPath -Recurse -File -Filter "evidence-manifest.json")
            if ($manifestFiles.Count -ne 1) { $fallback.Add("candidate-evidence-artifact-invalid"); continue }
            $evidence = Read-JsonFile $manifestFiles[0].FullName
            if ([string]$evidence.generation.run_id -cne [string]$latest.id -or
                [string]$evidence.generation.run_attempt -cne [string]$latest.run_attempt -or
                [string]$evidence.head.sha -cne $headSha) {
                $fallback.Add("candidate-evidence-run-mismatch"); continue
            }
            $proofs.Add([ordered]@{
                pr_number = [int]$prNumber
                pr_base_sha = [string]$pr.base.sha
                pr_head_sha = [string]$pr.head.sha
                evidence = $evidence
            })
        }
        catch {
            $fallback.Add("candidate-evidence-unavailable")
        }
    }
    return [pscustomobject][ordered]@{
        schema_version = 1; repository = $Repository; before = $beforeNormalized; sha = $shaNormalized
        forced = [bool]$Forced; range_complete = $rangeComplete; preflight_fallback_reasons = @($fallback.ToArray())
        commits = @($commits.ToArray()); proofs = @($proofs.ToArray())
    }
}

$input = if ($PSCmdlet.ParameterSetName -ceq "Live") { Get-LiveInput } else { Resolve-FixtureGeneration (Read-JsonFile $InputPath) }
$reasons = New-Object 'System.Collections.Generic.List[string]'
$groupsOutput = New-Object 'System.Collections.Generic.List[object]'
if ([int]$input.schema_version -ne 1) { throw "Unsupported lineage input schema." }
foreach ($reason in @($input.preflight_fallback_reasons)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$reason)) { Add-Fallback $reasons ([string]$reason) }
}
$before = ([string]$input.before).ToLowerInvariant()
$sha = ([string]$input.sha).ToLowerInvariant()
if (-not (Test-Sha $sha)) { throw "Lineage input sha is invalid." }
if ([bool]$input.forced) { Add-Fallback $reasons "force-push" }
if (-not (Test-Sha $before) -or $before -eq ("0" * 40)) { Add-Fallback $reasons "before-unreachable" }
if (-not [bool]$input.range_complete) { Add-Fallback $reasons "first-parent-range-incomplete" }
$commits = @($input.commits)
if ($commits.Count -eq 0) { Add-Fallback $reasons "empty-first-parent-range" }

$expectedParent = $before
foreach ($commit in $commits) {
    if (-not (Test-Sha ([string]$commit.sha).ToLowerInvariant()) -or @($commit.parents).Count -lt 1 -or [string]$commit.parents[0] -cne $expectedParent) {
        Add-Fallback $reasons "first-parent-range-incomplete"
        break
    }
    $expectedParent = ([string]$commit.sha).ToLowerInvariant()
}
if ($commits.Count -and $expectedParent -cne $sha) { Add-Fallback $reasons "range-tip-mismatch" }

$proofMap = @{}
foreach ($proof in @($input.proofs)) {
    $key = [string][int]$proof.pr_number
    if ($proofMap.ContainsKey($key)) { Add-Fallback $reasons "duplicate-pr-evidence" } else { $proofMap[$key] = $proof }
}

$index = 0
while ($index -lt $commits.Count -and $reasons.Count -eq 0) {
    $commit = $commits[$index]
    $associations = @($commit.associated_prs | ForEach-Object { [int]$_ } | Select-Object -Unique)
    if ($associations.Count -ne 1) { Add-Fallback $reasons $(if ($associations.Count -eq 0) { "missing-pr-association" } else { "ambiguous-pr-association" }); break }
    $prNumber = [int]$associations[0]
    $group = New-Object 'System.Collections.Generic.List[object]'
    $group.Add($commit)
    $index++
    if (@($commit.parents).Count -eq 1) {
        while ($index -lt $commits.Count) {
            $nextAssociations = @($commits[$index].associated_prs | ForEach-Object { [int]$_ } | Select-Object -Unique)
            if ($nextAssociations.Count -ne 1 -or [int]$nextAssociations[0] -ne $prNumber -or @($commits[$index].parents).Count -ne 1) { break }
            $group.Add($commits[$index]); $index++
        }
    }
    $key = [string]$prNumber
    if (-not $proofMap.ContainsKey($key)) { Add-Fallback $reasons "missing-candidate-evidence"; break }
    $proofRecord = $proofMap[$key]
    $evidence = $proofRecord.evidence
    if ([string]$proofRecord.pr_base_sha -and [string]$evidence.base.sha -cne [string]$proofRecord.pr_base_sha) { Add-Fallback $reasons "base-drift"; break }
    if ([string]$proofRecord.pr_head_sha -and [string]$evidence.head.sha -cne [string]$proofRecord.pr_head_sha) { Add-Fallback $reasons "head-drift"; break }
    if (-not (Test-Evidence $evidence $reasons $prNumber)) { break }
    $groupItems = @($group.ToArray())
    $first = $groupItems[0]
    $last = $groupItems[$groupItems.Count - 1]
    if ([string]$evidence.base.sha -cne [string]$first.parents[0] -or [string]$evidence.candidate.tree -cne [string]$last.tree) {
        Add-Fallback $reasons "tree-or-parent-mismatch"; break
    }
    $proofClass = ""
    $compatible = @()
    $actualMethod = "not-observable"
    if ($groupItems.Count -eq 1 -and @($first.parents).Count -eq 2) {
        if ((@($first.parents) -join ",") -cne (@($evidence.candidate.ordered_parents) -join ",")) { Add-Fallback $reasons "ordered-parent-mismatch"; break }
        $proofClass = "merge-commit"; $compatible = @("merge")
    }
    elseif (@($groupItems | Where-Object { @($_.parents).Count -ne 1 }).Count -gt 0) {
        Add-Fallback $reasons "unsafe-landing-structure"; break
    }
    elseif (@($evidence.head.commit_sequence).Count -eq 1 -and $groupItems.Count -eq 1) {
        if ([string]$first.ordered_change_digest -cne [string]$evidence.head.ordered_change_digests[0] -or
            [string]$first.combined_change_digest -cne [string]$evidence.change.combined_digest) {
            Add-Fallback $reasons "change-digest-mismatch"; break
        }
        $proofClass = "single-commit-linearized"; $compatible = @("squash", "rebase")
    }
    elseif ($groupItems.Count -eq 1 -and @($evidence.head.commit_sequence).Count -gt 1) {
        if ([string]$first.combined_change_digest -cne [string]$evidence.change.combined_digest) { Add-Fallback $reasons "change-digest-mismatch"; break }
        $proofClass = "linear-collapsed"; $compatible = @("squash")
    }
    elseif ($groupItems.Count -eq @($evidence.head.commit_sequence).Count -and $groupItems.Count -gt 1) {
        $actualDigests = @($groupItems | ForEach-Object { [string]$_.ordered_change_digest })
        if (($actualDigests -join ",") -cne (@($evidence.head.ordered_change_digests) -join ",")) { Add-Fallback $reasons "ordered-replay-mismatch"; break }
        $proofClass = "linear-replayed"; $compatible = @("rebase")
    }
    else {
        Add-Fallback $reasons "ambiguous-proof-class"; break
    }
    $groupsOutput.Add([ordered]@{
        pr_number = $prNumber
        commits = @($groupItems | ForEach-Object { [string]$_.sha })
        proof_class = $proofClass
        actual_merge_method = $actualMethod
        compatible_merge_methods = $compatible
        candidate_evidence_digest = [string]$evidence.canonical_evidence_digest
        final_gate_identity = $evidence.checks.final_gate
    })
}

$decision = if ($reasons.Count -eq 0) { "proven" } else { "full-fallback" }
if ($decision -ceq "proven") { $reportedGroups = @($groupsOutput.ToArray()) } else { $reportedGroups = @() }
$observation = [ordered]@{
    schema_version = 1
    repository = [string]$input.repository
    before = $before
    sha = $sha
    first_parent_range = @($commits | ForEach-Object { [string]$_.sha })
    commits = @($commits | ForEach-Object {
        [ordered]@{ sha = [string]$_.sha; associated_prs = @($_.associated_prs); parents = @($_.parents); tree = [string]$_.tree }
    })
    groups = $reportedGroups
    decision = $decision
    fallback_reasons = @($reasons.ToArray())
    evaluator_identity = $EvaluatorIdentity
    run_id = $RunId
    run_attempt = $RunAttempt
}
$outputFull = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outputFull)) | Out-Null
$observation | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outputFull -Encoding UTF8
if ($Json) { $observation | ConvertTo-Json -Depth 20 } else { Write-Output "Lineage shadow decision: $decision" }
