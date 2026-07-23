[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$resolver = Join-Path $PSScriptRoot "validation/resolve-pull-request-candidate.ps1"
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
    Invoke-Git $author add fixture.txt | Out-Null
    Invoke-Git $author commit -m "base" | Out-Null
    $base = [string](@(Invoke-Git $author rev-parse HEAD)[0]).Trim().ToLowerInvariant()
    Invoke-Git $author remote add origin $remote | Out-Null
    Invoke-Git $author push origin "HEAD:refs/heads/main" | Out-Null

    Invoke-Git $author checkout -b feature | Out-Null
    Add-Content -LiteralPath (Join-Path $author "fixture.txt") -Value "feature"
    Invoke-Git $author add fixture.txt | Out-Null
    Invoke-Git $author commit -m "feature one" | Out-Null
    Add-Content -LiteralPath (Join-Path $author "fixture.txt") -Value "feature two"
    Invoke-Git $author add fixture.txt | Out-Null
    Invoke-Git $author commit -m "feature two" | Out-Null
    $head = [string](@(Invoke-Git $author rev-parse HEAD)[0]).Trim().ToLowerInvariant()
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
