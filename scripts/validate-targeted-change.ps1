[CmdletBinding()]
param(
    [string]$BaseRef = "HEAD~1",
    [string]$HeadRef = "HEAD",
    [string[]]$ChangedPath = @(),
    [ValidateSet("quick", "targeted")]
    [string]$Mode = "quick",
    [string]$ScratchRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptDir
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-ecosystem-change-validation-{0}" -f ([Guid]::NewGuid().ToString("N")))
}
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

$classification = if (@($ChangedPath).Count -gt 0) {
    (& (Join-Path $scriptDir "validate-change.ps1") -ChangedPath $ChangedPath -Json | Out-String) | ConvertFrom-Json
} else {
    (& (Join-Path $scriptDir "validate-change.ps1") -BaseRef $BaseRef -HeadRef $HeadRef -Json | Out-String) | ConvertFrom-Json
}
if ([int]$classification.detected_tier -eq 3) { throw "Targeted validation cannot replace required Tier 3 full release validation." }

$checks = New-Object 'System.Collections.Generic.List[object]'
function Add-Result([string]$Name, [string]$Status, [string]$Detail) {
    $checks.Add([ordered]@{ name = $Name; status = $Status; detail = $Detail })
}

if (@($ChangedPath).Count -gt 0) { & git -C $repoRoot diff --check } else { & git -C $repoRoot diff --check "$BaseRef...$HeadRef" }
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }
Add-Result "diff-check" "PASS" "No whitespace errors in the selected diff."

foreach ($path in @($classification.changed_paths)) {
    $fullPath = Join-Path $repoRoot ([string]$path).Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
    $extension = [IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    if ($extension -eq ".ps1" -or $extension -eq ".psm1") {
        $astLexemes = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$astLexemes, [ref]$errors)
        if (@($errors).Count -gt 0) { throw "PowerShell parse failed for $path`: $($errors[0].Message)" }
    } elseif ($extension -eq ".json") {
        Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json | Out-Null
    }
    if ($extension -in @(".md", ".txt", ".json", ".yml", ".yaml", ".ps1", ".psm1", ".js")) {
        $text = Get-Content -LiteralPath $fullPath -Raw
        $privateOverlayToken = "agent-ecosystem" + "-private"
        $hiddenDirectory = ".sec" + "rets"
        $keyMarker = "PRIVATE" + " KEY"
        $unsafePattern = '(?i)(' + [regex]::Escape($privateOverlayToken) + '|[A-Z]:\\Projects\\|' + [regex]::Escape($hiddenDirectory) + '[/\\]|BEGIN (RSA |EC |OPENSSH )?' + $keyMarker + ')'
        if ($text -match $unsafePattern) {
            throw "Public-safe scan rejected $path."
        }
    }
}
Add-Result "changed-file-parse" "PASS" "Changed PowerShell and JSON files parse; public-safe text scan passed."

if ([int]$classification.detected_tier -ge 1) {
    foreach ($scriptPath in @(Get-ChildItem -LiteralPath $scriptDir -Recurse -File | Where-Object { $_.Extension -in @(".ps1", ".psm1") })) {
        $astLexemes = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($scriptPath.FullName, [ref]$astLexemes, [ref]$parseErrors)
        if (@($parseErrors).Count -gt 0) { throw "Quick repository PowerShell parse failed for $($scriptPath.FullName): $($parseErrors[0].Message)" }
    }
    $knowledgeRoot = Join-Path $repoRoot "knowledge-hub/knowledge"
    foreach ($jsonPath in @(Get-ChildItem -LiteralPath $knowledgeRoot -Recurse -File -Filter *.json)) {
        Get-Content -LiteralPath $jsonPath.FullName -Raw | ConvertFrom-Json | Out-Null
    }
    Add-Result "quick-repository-checks" "PASS" "Repository PowerShell and knowledge JSON parse checks passed."
}

if ($Mode -eq "targeted") {
    $modules = @($classification.affected_modules)
    if ($modules -contains "hooks") {
        & (Join-Path $scriptDir "validation/test-claude-hooks-runtime.ps1") -RepositoryRoot $repoRoot -ScratchRoot (Join-Path $ScratchRoot "hooks") -Json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Hooks runtime fixtures failed." }
        Add-Result "hooks-runtime" "PASS" "Executable hooks runtime fixtures passed."
    }
    if ($modules -contains "repository") {
        & (Join-Path $scriptDir "test-pr-identity-guard.ps1") -RepoRoot $repoRoot -Json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "PR identity guard fixtures failed." }
        & (Join-Path $scriptDir "test-issue-triage-decision-command.ps1") -RepoRoot $repoRoot -Json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Issue decision fixtures failed." }
        Add-Result "repository-guards" "PASS" "Repository guard fixtures passed."
    }
    if ($modules -contains "installer" -or $modules -contains "runtime") {
        $runtimeRoot = Join-Path $ScratchRoot "runtime"
        & (Join-Path $scriptDir "install.ps1") -Profile minimal -TargetDir $runtimeRoot | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $runtimeRoot "install-manifest.json"))) { throw "Minimal copy-first install smoke failed." }
        & (Join-Path $scriptDir "uninstall.ps1") -TargetDir $runtimeRoot -Json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Manifest uninstall smoke failed." }
        Add-Result "installer-runtime-smoke" "PASS" "Minimal copy-first install and manifest uninstall completed in scratch space."
    }
    if ($modules -contains "skills") {
        foreach ($path in @($classification.changed_paths | Where-Object { $_ -match '^skills/[^/]+/SKILL\.md$' })) {
            $text = Get-Content -LiteralPath (Join-Path $repoRoot $path) -Raw
            if ($text -notmatch '(?s)^---\s+.*?name:\s*\S+.*?description:\s*.+?\s+---') { throw "Skill metadata frontmatter is incomplete: $path" }
        }
        Add-Result "skill-metadata" "PASS" "Changed skill entrypoints contain required metadata."
    }
    if ($modules -contains "bootstrap" -or $modules -contains "templates") {
        & (Join-Path $scriptDir "validation/project-bootstrap-safety-fixture.ps1") `
            -RepositoryRoot $repoRoot `
            -ScratchRoot (Join-Path $ScratchRoot "bootstrap") `
            -Json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Project bootstrap safety fixtures failed." }
        Add-Result "bootstrap-safety" "PASS" "Project bootstrap proposal, backup, and write-boundary fixtures passed."
    }
    Add-Result "targeted-module-matrix" "PASS" ("Targeted checks completed for modules: {0}" -f ($modules -join ", "))
}

$result = [ordered]@{
    schema_version = 1
    mode = $Mode
    classification = $classification
    checks = @($checks.ToArray())
    summary = [ordered]@{ pass = @($checks | Where-Object status -eq "PASS").Count; fail = 0 }
}
$resultPath = Join-Path $ScratchRoot "targeted-validation-result.json"
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
if ($Json.IsPresent) { $result | ConvertTo-Json -Depth 10 } else { Write-Output ("Targeted validation PASS ({0} checks)." -f $result.summary.pass) }
