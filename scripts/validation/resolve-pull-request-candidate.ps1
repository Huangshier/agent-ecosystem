[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][int]$PullRequestNumber,
    [Parameter(Mandatory = $true)][string]$BaseRef,
    [Parameter(Mandatory = $true)][string]$BaseSha,
    [Parameter(Mandatory = $true)][string]$HeadRef,
    [Parameter(Mandatory = $true)][string]$HeadSha,
    [string]$Remote = "origin",
    [string]$ExpectedCandidateSha = "",
    [string]$ExpectedCandidateTree = "",
    [string[]]$ExpectedCandidateParents = @(),
    [string]$OutputPath = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Assert-CommitSha([string]$Value, [string]$Label) {
    if ($Value -notmatch '^[0-9a-fA-F]{40}$') { throw "$Label must be a 40-character Git commit ID." }
}
function Assert-RefName([string]$Value, [string]$Label) {
    if ($Value -notmatch '^[A-Za-z0-9._/-]+$' -or $Value.Contains("..") -or $Value.StartsWith("-") -or $Value.EndsWith("/")) {
        throw "$Label contains an unsafe Git ref name."
    }
}
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    # NOTE: Windows PowerShell 将 Git 的正常 stderr 进度包装成 ErrorRecord；以退出码作为唯一成败依据。
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $output = @(& git @Arguments 2>&1) }
    finally { $ErrorActionPreference = $previousPreference }
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join "`n")" }
    return @($output)
}
function Get-Commit([string]$Ref) {
    return [string](@(Invoke-Git rev-parse --verify "$Ref^{commit}")[0]).Trim().ToLowerInvariant()
}
function Get-Tree([string]$Commit) {
    return [string](@(Invoke-Git rev-parse --verify "$Commit^{tree}")[0]).Trim().ToLowerInvariant()
}
function Get-Parents([string]$Commit) {
    $line = [string](@(Invoke-Git show -s --format=%P $Commit)[0])
    if ([string]::IsNullOrWhiteSpace($line)) { return @() }
    return @($line.Trim().Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.ToLowerInvariant() })
}
function Get-Sha256Text([string]$Text) {
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant()
    }
    finally { $hash.Dispose() }
}
function Get-NormalizedDiff([string]$From, [string]$To) {
    return (@(Invoke-Git diff --no-ext-diff --binary --full-index --no-renames $From $To | ForEach-Object { [string]$_ }) -join "`n") + "`n"
}
function Get-StablePatchId([string]$Commit) {
    $parents = @(Get-Parents -Commit $Commit)
    if ($parents.Count -ne 1) { throw "Replayed proof requires a linear head sequence; '$Commit' has $($parents.Count) parents." }
    # NOTE: 直接传递 Git stdout 原始字节，避免 Windows PowerShell 文本管道改变 patch 输入编码。
    $diffStart = New-Object System.Diagnostics.ProcessStartInfo
    $diffStart.FileName = "git"
    $diffStart.Arguments = "diff --no-ext-diff --binary --full-index --no-renames $($parents[0]) $Commit"
    $diffStart.WorkingDirectory = (Get-Location).ProviderPath
    $diffStart.UseShellExecute = $false
    $diffStart.CreateNoWindow = $true
    $diffStart.RedirectStandardOutput = $true
    $diffStart.RedirectStandardError = $true
    $diffProcess = New-Object System.Diagnostics.Process
    $diffProcess.StartInfo = $diffStart
    [void]$diffProcess.Start()
    $diffBytes = New-Object System.IO.MemoryStream
    $diffProcess.StandardOutput.BaseStream.CopyTo($diffBytes)
    $diffError = $diffProcess.StandardError.ReadToEnd()
    $diffProcess.WaitForExit()
    if ($diffProcess.ExitCode -ne 0) { throw "git diff failed for '$Commit': $diffError" }

    $patchStart = New-Object System.Diagnostics.ProcessStartInfo
    $patchStart.FileName = "git"
    $patchStart.Arguments = "patch-id --stable"
    $patchStart.WorkingDirectory = (Get-Location).ProviderPath
    $patchStart.UseShellExecute = $false
    $patchStart.CreateNoWindow = $true
    $patchStart.RedirectStandardInput = $true
    $patchStart.RedirectStandardOutput = $true
    $patchStart.RedirectStandardError = $true
    $patchProcess = New-Object System.Diagnostics.Process
    $patchProcess.StartInfo = $patchStart
    [void]$patchProcess.Start()
    $diffBytes.Position = 0
    $diffBytes.CopyTo($patchProcess.StandardInput.BaseStream)
    $patchProcess.StandardInput.Close()
    $patchOutput = $patchProcess.StandardOutput.ReadToEnd().Trim()
    $patchError = $patchProcess.StandardError.ReadToEnd()
    $patchProcess.WaitForExit()
    $patchExitCode = $patchProcess.ExitCode
    $diffBytes.Dispose()
    $diffProcess.Dispose()
    $patchProcess.Dispose()
    if ($patchExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($patchOutput)) {
        throw "git patch-id --stable failed for '$Commit': $patchError"
    }
    $parts = $patchOutput.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -lt 1 -or $parts[0] -notmatch '^[0-9a-fA-F]{40}$') { throw "git patch-id returned malformed output." }
    return $parts[0].ToLowerInvariant()
}

Assert-CommitSha $BaseSha "BaseSha"
Assert-CommitSha $HeadSha "HeadSha"
Assert-RefName $BaseRef "BaseRef"
Assert-RefName $HeadRef "HeadRef"
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw "Repository must use owner/name form." }
if ($PullRequestNumber -lt 1) { throw "PullRequestNumber must be positive." }
if ($ExpectedCandidateSha) { Assert-CommitSha $ExpectedCandidateSha "ExpectedCandidateSha" }
if ($ExpectedCandidateTree) { Assert-CommitSha $ExpectedCandidateTree "ExpectedCandidateTree" }
foreach ($parent in @($ExpectedCandidateParents)) { Assert-CommitSha ([string]$parent) "ExpectedCandidateParents" }

$baseShaNormalized = $BaseSha.ToLowerInvariant()
$headShaNormalized = $HeadSha.ToLowerInvariant()
$mergeSource = "refs/pull/$PullRequestNumber/merge"
$headSource = "refs/pull/$PullRequestNumber/head"
$baseSource = "refs/heads/$BaseRef"
$namespace = "refs/candidate-verification/$([Guid]::NewGuid().ToString('N'))"
$refs = [ordered]@{
    initial_merge = "$namespace/initial-merge"; initial_base = "$namespace/initial-base"; initial_head = "$namespace/initial-head"
    final_merge = "$namespace/final-merge"; final_base = "$namespace/final-base"; final_head = "$namespace/final-head"
}
try {
    Invoke-Git fetch --no-tags --force $Remote "+${mergeSource}:$($refs.initial_merge)" "+${baseSource}:$($refs.initial_base)" "+${headSource}:$($refs.initial_head)" | Out-Null
    $candidateSha = Get-Commit $refs.initial_merge
    $candidateTree = Get-Tree $candidateSha
    $candidateParents = @(Get-Parents $candidateSha)
    $resolvedBase = Get-Commit $refs.initial_base
    $resolvedHead = Get-Commit $refs.initial_head
    if ($resolvedBase -cne $baseShaNormalized) { throw "Base drift detected." }
    if ($resolvedHead -cne $headShaNormalized) { throw "Head drift detected." }
    if ($candidateParents.Count -ne 2 -or $candidateParents[0] -cne $baseShaNormalized -or $candidateParents[1] -cne $headShaNormalized) {
        throw "Exact merge candidate ordered parents do not match event base/head."
    }
    Invoke-Git fetch --no-tags --force $Remote "+${mergeSource}:$($refs.final_merge)" "+${baseSource}:$($refs.final_base)" "+${headSource}:$($refs.final_head)" | Out-Null
    if ((Get-Commit $refs.final_merge) -cne $candidateSha -or (Get-Commit $refs.final_base) -cne $resolvedBase -or (Get-Commit $refs.final_head) -cne $resolvedHead) {
        throw "Candidate, base, or head ref changed during resolution."
    }
    if ($ExpectedCandidateSha -and $candidateSha -cne $ExpectedCandidateSha.ToLowerInvariant()) { throw "Candidate SHA changed after classification." }
    if ($ExpectedCandidateTree -and $candidateTree -cne $ExpectedCandidateTree.ToLowerInvariant()) { throw "Candidate tree changed after classification." }
    if (@($ExpectedCandidateParents).Count -gt 0) {
        $expectedParents = @($ExpectedCandidateParents | ForEach-Object { ([string]$_).ToLowerInvariant() })
        if (($candidateParents -join ",") -cne ($expectedParents -join ",")) { throw "Candidate ordered parents changed after classification." }
    }
    $mergeBase = [string](@(Invoke-Git merge-base $baseShaNormalized $headShaNormalized)[0]).Trim().ToLowerInvariant()
    Assert-CommitSha $mergeBase "head merge base"
    $headSequence = @(Invoke-Git rev-list --reverse --topo-order $headShaNormalized --not $baseShaNormalized | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    if ($headSequence.Count -eq 0) { throw "PR head has no commits outside the exact base." }
    $orderedChangeDigests = @($headSequence | ForEach-Object { Get-StablePatchId $_ })
    $contract = [ordered]@{
        schema_version = 1
        repository = $Repository
        pr_number = $PullRequestNumber
        base = [ordered]@{ ref = $BaseRef; sha = $baseShaNormalized }
        head = [ordered]@{
            ref = $HeadRef; sha = $headShaNormalized; merge_base = $mergeBase
            commit_sequence = $headSequence; ordered_change_digests = $orderedChangeDigests
        }
        candidate = [ordered]@{
            sha = $candidateSha; tree = $candidateTree; ordered_parents = $candidateParents; source = $mergeSource
        }
        change = [ordered]@{
            combined_digest = Get-Sha256Text (Get-NormalizedDiff $baseShaNormalized $headShaNormalized)
            paths = @(Invoke-Git diff --name-status --no-renames $baseShaNormalized $headShaNormalized | ForEach-Object { [string]$_ })
        }
    }
    if ($OutputPath) {
        $outputFull = [System.IO.Path]::GetFullPath($OutputPath)
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outputFull)) | Out-Null
        $contract | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputFull -Encoding UTF8
    }
    if ($Json) { $contract | ConvertTo-Json -Depth 12 } else { Write-Output "Exact pull request candidate verified." }
}
finally {
    foreach ($ref in $refs.Values) { & git update-ref -d $ref 2>$null }
}
