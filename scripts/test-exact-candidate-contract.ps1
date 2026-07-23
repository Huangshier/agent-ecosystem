[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$resolver = Join-Path $PSScriptRoot "validation/resolve-pull-request-candidate.ps1"
$stablePatchIdHelper = Join-Path $PSScriptRoot "validation/git-stable-patch-id.ps1"
. $stablePatchIdHelper
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-candidate-fixture-" + [Guid]::NewGuid().ToString("N"))
$results = New-Object 'System.Collections.Generic.List[object]'

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )
    # NOTE: Windows PowerShell 将原生 stderr 包装成 ErrorRecord；Git 的正常进度输出不能因此变成终止错误。
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $output = @(& git -C $WorkingDirectory @Arguments 2>&1) }
    finally { $ErrorActionPreference = $previousPreference }
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join "`n")" }
    return @($output)
}
function Assert-Fails([scriptblock]$Action, [string]$Name) {
    try { & $Action; throw "Fixture '$Name' unexpectedly succeeded." }
    catch {
        if ($_.Exception.Message -ceq "Fixture '$Name' unexpectedly succeeded.") { throw }
        $results.Add([ordered]@{ name = $Name; status = "PASS" }) | Out-Null
    }
}
function Get-Sha256Text([string]$Text) {
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hash.Dispose()
    }
}
function Get-CombinedChangeDigest([string]$WorkingDirectory, [string]$Parent, [string]$Commit) {
    $diff = (@(Invoke-Git $WorkingDirectory diff --no-ext-diff --binary --full-index --no-renames $Parent $Commit | ForEach-Object { [string]$_ }) -join "`n") + "`n"
    return Get-Sha256Text $diff
}
function Get-FirstParent([string]$WorkingDirectory, [string]$Commit) {
    $parentsLine = [string](@(Invoke-Git $WorkingDirectory show -s --format=%P $Commit)[0])
    $parents = @($parentsLine.Trim().Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries))
    if ($parents.Count -ne 1) { throw "Fixture commit '$Commit' must have exactly one parent." }
    return [string]$parents[0]
}
function Get-NativeStablePatchId([string]$WorkingDirectory, [string]$Parent, [string]$Commit) {
    Assert-GitCommitSha -Value $Parent -Label "Fixture parent"
    Assert-GitCommitSha -Value $Commit -Label "Fixture commit"
    $pipeline = "git diff --no-ext-diff --binary --full-index --no-renames $($Parent.ToLowerInvariant()) $($Commit.ToLowerInvariant()) | git patch-id --stable"
    Push-Location $WorkingDirectory
    try {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            if ($env:OS -ceq "Windows_NT") {
                $lines = @(& cmd.exe /d /s /c $pipeline 2>&1)
            }
            else {
                $lines = @(& /bin/sh -c $pipeline 2>&1)
            }
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }
    }
    finally {
        Pop-Location
    }
    $output = (@($lines | ForEach-Object { [string]$_ }) -join "`n").Trim()
    $records = @($output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($exitCode -ne 0 -or $records.Count -ne 1) { throw "Native stable patch-id fixture failed." }
    $parts = $records[0].Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -lt 1 -or $parts[0] -notmatch '^[0-9a-fA-F]{40}$') { throw "Native stable patch-id fixture returned malformed output." }
    return $parts[0].ToLowerInvariant()
}

[System.IO.Directory]::CreateDirectory($scratch) | Out-Null
try {
    $remote = Join-Path $scratch "remote.git"
    $author = Join-Path $scratch "author"
    $consumer = Join-Path $scratch "consumer"
    Invoke-Git $scratch init --bare $remote | Out-Null
    Invoke-Git $scratch init -b main $author | Out-Null
    Invoke-Git $author config user.name "Candidate Fixture" | Out-Null
    Invoke-Git $author config user.email "candidate-fixture@example.invalid" | Out-Null
    Set-Content -LiteralPath (Join-Path $author "fixture.txt") -Value "base" -Encoding UTF8
    [System.IO.File]::WriteAllText(
        (Join-Path $author ".gitattributes"),
        "high-byte.txt diff`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    Invoke-Git $author add fixture.txt .gitattributes | Out-Null
    Invoke-Git $author commit -m "base" | Out-Null
    $base = [string](@(Invoke-Git $author rev-parse HEAD)[0]).Trim().ToLowerInvariant()
    Invoke-Git $author remote add origin $remote | Out-Null
    Invoke-Git $author push origin "HEAD:refs/heads/main" | Out-Null

    Invoke-Git $author checkout -b feature | Out-Null
    Add-Content -LiteralPath (Join-Path $author "fixture.txt") -Value "feature"
    Invoke-Git $author add fixture.txt | Out-Null
    Invoke-Git $author commit -m "feature one" | Out-Null
    $featureOne = [string](@(Invoke-Git $author rev-parse HEAD)[0]).Trim().ToLowerInvariant()
    Add-Content -LiteralPath (Join-Path $author "fixture.txt") -Value "feature two"
    # NOTE: 无 NUL 的高位字节仍是 Git text diff；该输入会暴露 PowerShell 文本管道的编码漂移。
    [System.IO.File]::WriteAllBytes((Join-Path $author "high-byte.txt"), [byte[]](0x80, 0x81, 0x82, 0x0A, 0xFE, 0xFF, 0x0A))
    Invoke-Git $author add fixture.txt high-byte.txt | Out-Null
    Invoke-Git $author commit -m "feature two" | Out-Null
    $head = [string](@(Invoke-Git $author rev-parse HEAD)[0]).Trim().ToLowerInvariant()
    $featureSequence = @($featureOne, $head)
    $highByteNumstat = @((Invoke-Git $author diff --numstat $base $head -- high-byte.txt) | ForEach-Object { [string]$_ })
    if ($highByteNumstat.Count -ne 1 -or $highByteNumstat[0] -notmatch '^\d+\s+\d+\s+high-byte\.txt$') {
        throw "High-byte fixture must remain a text diff."
    }
    Invoke-Git $author push origin "HEAD:refs/pull/1/head" | Out-Null
    Invoke-Git $author checkout main | Out-Null
    Invoke-Git $author merge --no-ff feature -m "synthetic candidate" | Out-Null
    $candidate = [string](@(Invoke-Git $author rev-parse HEAD)[0]).Trim().ToLowerInvariant()
    Invoke-Git $author push origin "HEAD:refs/pull/1/merge" | Out-Null

    Invoke-Git $scratch clone $remote $consumer | Out-Null
    $output = Join-Path $scratch "candidate-contract.json"
    Push-Location $consumer
    try {
        & $resolver -Repository "fixture/repository" -PullRequestNumber 1 -BaseRef main -BaseSha $base `
            -HeadRef feature -HeadSha $head -ExpectedCandidateSha $candidate -OutputPath $output | Out-Null
    }
    finally { Pop-Location }
    $contract = Get-Content -Raw $output | ConvertFrom-Json
    if ([string]$contract.candidate.sha -cne $candidate -or
        (@($contract.candidate.ordered_parents) -join ",") -cne "$base,$head" -or
        [string]$contract.candidate.source -cne "refs/pull/1/merge" -or
        @($contract.head.commit_sequence).Count -ne 2 -or @($contract.head.ordered_change_digests).Count -ne 2) {
        throw "Exact candidate fixture did not bind candidate/base/head identity."
    }
    $results.Add([ordered]@{ name = "exact-candidate"; status = "PASS" }) | Out-Null

    Invoke-Git $author checkout -B squash-landing $base | Out-Null
    Invoke-Git $author merge --squash feature | Out-Null
    Invoke-Git $author commit -m "squash landing" | Out-Null
    $squash = [string](@(Invoke-Git $author rev-parse HEAD)[0]).Trim().ToLowerInvariant()

    Invoke-Git $author checkout -B rebased feature | Out-Null
    $hadCommitterDate = Test-Path Env:GIT_COMMITTER_DATE
    $previousCommitterDate = $env:GIT_COMMITTER_DATE
    try {
        $env:GIT_COMMITTER_DATE = "2030-01-01T00:00:00+00:00"
        Invoke-Git $author rebase --force-rebase $base | Out-Null
    }
    finally {
        if ($hadCommitterDate) { $env:GIT_COMMITTER_DATE = $previousCommitterDate }
        else { Remove-Item Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue }
    }
    $rebaseHead = [string](@(Invoke-Git $author rev-parse HEAD)[0]).Trim().ToLowerInvariant()
    $rebaseSequence = @(Invoke-Git $author rev-list --reverse --topo-order $rebaseHead --not $base | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    if ($rebaseSequence.Count -ne 2 -or ($rebaseSequence -join ",") -ceq ($featureSequence -join ",")) {
        throw "Fixture rebase did not create a distinct two-commit replay."
    }
    Push-Location $author
    try {
        $rebaseDigests = @(
            foreach ($commit in $rebaseSequence) {
                Get-GitStablePatchId -Parent (Get-FirstParent $author $commit) -Commit $commit
            }
        )
    }
    finally {
        Pop-Location
    }
    $nativeFeatureDigests = @(
        foreach ($commit in $featureSequence) {
            Get-NativeStablePatchId -WorkingDirectory $author -Parent (Get-FirstParent $author $commit) -Commit $commit
        }
    )
    $nativeRebaseDigests = @(
        foreach ($commit in $rebaseSequence) {
            Get-NativeStablePatchId -WorkingDirectory $author -Parent (Get-FirstParent $author $commit) -Commit $commit
        }
    )
    $squashCombinedDigest = Get-CombinedChangeDigest -WorkingDirectory $author -Parent $base -Commit $squash
    if (
        (@($contract.head.ordered_change_digests) -join ",") -cne ($nativeFeatureDigests -join ",") -or
        (@($contract.head.ordered_change_digests) -join ",") -cne ($rebaseDigests -join ",") -or
        ($rebaseDigests -join ",") -cne ($nativeRebaseDigests -join ",") -or
        [string]$contract.change.combined_digest -cne $squashCombinedDigest
    ) {
        throw "Real Git candidate, rebase, and squash digest parity failed."
    }
    $results.Add([ordered]@{
        name = "real-git-digest-parity"; status = "PASS"
        candidate_ordered_change_digests = @($contract.head.ordered_change_digests)
        rebase_landed_ordered_change_digests = $rebaseDigests
        candidate_combined_digest = [string]$contract.change.combined_digest
        squash_combined_digest = $squashCombinedDigest
    }) | Out-Null

    Assert-Fails {
        Push-Location $consumer
        try {
            & $resolver -Repository "fixture/repository" -PullRequestNumber 2 -BaseRef main -BaseSha $base `
                -HeadRef feature -HeadSha $head -OutputPath (Join-Path $scratch "missing.json")
        }
        finally { Pop-Location }
    } "missing-merge-ref"
    Assert-Fails {
        Push-Location $consumer
        try {
            & $resolver -Repository "fixture/repository" -PullRequestNumber 1 -BaseRef main -BaseSha ("0" * 40) `
                -HeadRef feature -HeadSha $head -OutputPath (Join-Path $scratch "base-drift.json")
        }
        finally { Pop-Location }
    } "base-drift"
    Assert-Fails {
        Push-Location $consumer
        try {
            & $resolver -Repository "fixture/repository" -PullRequestNumber 1 -BaseRef main -BaseSha $base `
                -HeadRef feature -HeadSha $head -ExpectedCandidateTree ("0" * 40) -OutputPath (Join-Path $scratch "tree-drift.json")
        }
        finally { Pop-Location }
    } "candidate-tree-drift"

    $summary = [ordered]@{ schema_version = 1; pass = $results.Count; fail = 0; cases = @($results.ToArray()) }
    if ($Json) { $summary | ConvertTo-Json -Depth 5 } else { Write-Output "exact candidate contract fixtures: PASS=$($results.Count) FAIL=0" }
}
finally {
    if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
