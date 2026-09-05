[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",
    [string]$ScratchRoot = "",
    [string]$BootstrapScript = "",
    [string]$HubDir = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

# Get-TreeFingerprint: 计算目录的文件和空目录指纹；参数 Root 为待检查目录。
function Get-TreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return "MISSING"
    }

    $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([char[]]"\/")
    $records = New-Object 'System.Collections.Generic.List[string]'
    Get-ChildItem -LiteralPath $rootFull -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($rootFull.Length).TrimStart([char[]]"\/") -replace "\\", "/"
        if ($_.PSIsContainer) {
            $records.Add("D:$relative") | Out-Null
        } else {
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $records.Add("F:$relative`:$hash") | Out-Null
        }
    }
    return ($records.ToArray() -join "`n")
}

# Get-TreeFileHashMap: 返回目录下全部文件的相对路径到 SHA256 的映射；参数 Root 为目标目录。
function Get-TreeFileHashMap {
    param([Parameter(Mandatory = $true)][string]$Root)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Root)) {
        return $map
    }
    $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([char[]]"\/")
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force | ForEach-Object {
        $relative = $_.FullName.Substring($rootFull.Length).TrimStart([char[]]"\/") -replace "\\", "/"
        $map[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $map
}

# Get-LegacyTemplateRelativePaths: 枚举指定语言 legacy 模板树映射到项目内的相对路径；参数 HubDir、LanguageCode。
function Get-LegacyTemplateRelativePaths {
    param(
        [Parameter(Mandatory = $true)][string]$HubDir,
        [Parameter(Mandatory = $true)][string]$LanguageCode
    )

    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($templatePair in @(@{ dir = "project-root"; prefix = "" }, @{ dir = "project-agent"; prefix = ".agents/" })) {
        $templateDir = Join-Path $HubDir ("templates/languages/{0}/{1}" -f $LanguageCode, $templatePair.dir)
        Get-ChildItem -LiteralPath $templateDir -Recurse -File | ForEach-Object {
            $templateRelative = $_.FullName.Substring($templateDir.Length).TrimStart([char[]]"\/") -replace "\\", "/"
            if ($templatePair.prefix) {
                $templateRelative = "{0}{1}" -f $templatePair.prefix, $templateRelative
            }
            $paths.Add($templateRelative)
        }
    }
    return $paths.ToArray()
}

# Assert-ExistingFilesUnchanged: 断言运行前存在的所有文件在运行后仍存在且哈希不变；参数 BeforeMap、AfterMap、Name 为前后文件哈希映射和用例名。
function Assert-ExistingFilesUnchanged {
    param(
        [Parameter(Mandatory = $true)]$BeforeMap,
        [Parameter(Mandatory = $true)]$AfterMap,
        [Parameter(Mandatory = $true)][string]$Name
    )

    foreach ($existingFile in $BeforeMap.Keys) {
        if (-not $AfterMap.ContainsKey($existingFile)) {
            throw "$Name deleted an existing file: $existingFile"
        }
        if ($AfterMap[$existingFile] -cne $BeforeMap[$existingFile]) {
            throw "$Name modified an existing file: $existingFile"
        }
    }
}

# Assert-ExplicitLegacyAddedFiles: 断言显式 legacy bootstrap 的新增文件集合恰为
# 模板树与 lock 中运行前不存在的文件；参数 BeforeMap、AfterMap、HubDir 为运行前
# 后文件哈希映射和 hub 根，返回实际新增文件数。
function Assert-ExplicitLegacyAddedFiles {
    param(
        [Parameter(Mandatory = $true)]$BeforeMap,
        [Parameter(Mandatory = $true)]$AfterMap,
        [Parameter(Mandatory = $true)][string]$HubDir
    )

    $expectedAdded = New-Object 'System.Collections.Generic.List[string]'
    foreach ($templateRelative in (Get-LegacyTemplateRelativePaths -HubDir $HubDir -LanguageCode "en")) {
        if (-not $BeforeMap.ContainsKey($templateRelative)) {
            $expectedAdded.Add($templateRelative)
        }
    }
    if (-not $BeforeMap.ContainsKey(".agents/hub.lock.json")) {
        $expectedAdded.Add(".agents/hub.lock.json")
    }

    $actualAdded = @($AfterMap.Keys | Where-Object { -not $BeforeMap.ContainsKey($_) } | Sort-Object)
    $expectedSorted = @($expectedAdded.ToArray() | Sort-Object)
    if ($actualAdded.Count -ne $expectedSorted.Count) {
        $unexpectedAdded = @($actualAdded | Where-Object { $expectedSorted -cnotcontains $_ })
        $missingAdded = @($expectedSorted | Where-Object { $actualAdded -cnotcontains $_ })
        throw ("Explicit legacy bootstrap added an unexpected file set. Unexpected: {0}; missing: {1}" -f ($unexpectedAdded -join ', '), ($missingAdded -join ', '))
    }
    for ($addedIndex = 0; $addedIndex -lt $expectedSorted.Count; $addedIndex++) {
        if ($expectedSorted[$addedIndex] -cne $actualAdded[$addedIndex]) {
            throw ("Explicit legacy bootstrap added-file mismatch: expected '{0}', got '{1}'." -f $expectedSorted[$addedIndex], $actualAdded[$addedIndex])
        }
    }
    return $actualAdded.Count
}

# Assert-ExpectedFailure: 执行预期失败的命令并校验错误文本；参数 Name、Command、ExpectedToken 描述用例。
function Assert-ExpectedFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command,
        [Parameter(Mandatory = $true)][string]$ExpectedToken
    )

    try {
        & $Command | Out-Null
    } catch {
        $message = $_.Exception.Message
        if ($message -notlike ("*{0}*" -f $ExpectedToken)) {
            throw "Fixture '$Name' expected error containing '$ExpectedToken', got: $message"
        }
        return [ordered]@{ name = $Name; error = $message }
    }

    throw "Fixture '$Name' expected bootstrap to fail."
}

# Assert-Unchanged: 校验失败命令没有改变目录；参数 Root、Before、Name 为目录、旧指纹和用例名。
function Assert-Unchanged {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Before,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $after = Get-TreeFingerprint -Root $Root
    if ($after -ne $Before) {
        throw "Fixture '$Name' changed the target tree on an error path."
    }
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("project-bootstrap-safety-{0}" -f [guid]::NewGuid().ToString("N"))
}
if ([string]::IsNullOrWhiteSpace($BootstrapScript)) {
    $BootstrapScript = Join-Path $RepositoryRoot "skills/project-bootstrap/scripts/bootstrap_project.ps1"
}
if ([string]::IsNullOrWhiteSpace($HubDir)) {
    $HubDir = Join-Path $RepositoryRoot "knowledge-hub"
}
if (-not (Test-Path -LiteralPath $BootstrapScript -PathType Leaf)) {
    throw "Bootstrap script not found: $BootstrapScript"
}
if (-not (Test-Path -LiteralPath $HubDir -PathType Container)) {
    throw "Knowledge hub not found: $HubDir"
}

New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null
$scratchFull = (Resolve-Path -LiteralPath $ScratchRoot).Path
$results = New-Object 'System.Collections.Generic.List[object]'

# NOTE: minimal example 是 fresh/default adoption surface，只做精确路径与明确文档
# term 检查，避免把 compatibility fixture 或历史文档纳入通用字符串扫描。
$minimalExampleRoot = Join-Path $RepositoryRoot "examples/minimal-project"
$minimalRequiredPaths = @(
    "AGENTS.md",
    "README.md",
    ".agents/.gitignore",
    ".agents/README.md",
    ".agents/work",
    ".agents/context",
    ".agents/procedures",
    ".agents/skills",
    "docs/specs/example-work/spec.md",
    "docs/specs/example-work/tasks.md"
)
$minimalRetiredPaths = @(
    ".agents/AGENTS.md",
    ".agents/process.txt",
    ".agents/plan.md",
    ".agents/notes.md",
    ".agents/commands",
    "CLAUDE.md",
    ".claude"
)
$minimalMissingPaths = @($minimalRequiredPaths | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $minimalExampleRoot $_))
})
$minimalPresentRetiredPaths = @($minimalRetiredPaths | Where-Object {
    Test-Path -LiteralPath (Join-Path $minimalExampleRoot $_)
})
if ($minimalMissingPaths.Count -gt 0 -or $minimalPresentRetiredPaths.Count -gt 0) {
    throw "Minimal C3.3 example layout drifted. Missing: $($minimalMissingPaths -join ', '); retired: $($minimalPresentRetiredPaths -join ', ')."
}
$results.Add([ordered]@{ name = "minimal-example-c3-3-layout"; status = "PASS" }) | Out-Null

$minimalGuidanceFiles = @(
    "AGENTS.md",
    "README.md",
    "docs/specs/example-work/spec.md",
    "docs/specs/example-work/tasks.md"
)
$minimalGuidanceText = ($minimalGuidanceFiles | ForEach-Object {
    [IO.File]::ReadAllText((Join-Path $minimalExampleRoot $_), [Text.UTF8Encoding]::new($false, $true))
}) -join "`n"
$minimalRetiredGuidanceTokens = @(
    ".agents/AGENTS.md",
    ".agents/process.txt",
    ".agents/plan.md",
    ".agents/notes.md",
    ".agents/commands",
    "project-context-gate",
    "workflow-spec-lite",
    "memory-governance",
    "CLAUDE.md",
    ".claude/"
)
$minimalPresentRetiredTokens = @($minimalRetiredGuidanceTokens | Where-Object {
    $minimalGuidanceText.Contains($_, [StringComparison]::Ordinal)
})
$minimalRequiredGuidanceTokens = @(
    "project-bootstrap",
    "project-workspace check",
    "project-workspace",
    "docs/specs/<slug>/"
)
$minimalMissingGuidanceTokens = @($minimalRequiredGuidanceTokens | Where-Object {
    -not $minimalGuidanceText.Contains($_, [StringComparison]::Ordinal)
})
if ($minimalPresentRetiredTokens.Count -gt 0 -or $minimalMissingGuidanceTokens.Count -gt 0) {
    throw "Minimal C3.3 example guidance drifted. Missing active terms: $($minimalMissingGuidanceTokens -join ', '); retired terms: $($minimalPresentRetiredTokens -join ', ')."
}
$results.Add([ordered]@{ name = "minimal-example-active-guidance"; status = "PASS" }) | Out-Null

$repositoryStyleHub = Join-Path $scratchFull "repository-style-hub"
$repositoryStyleProject = Join-Path $scratchFull "repository-style-project"
New-Item -ItemType Directory -Path (Join-Path $repositoryStyleHub "skills") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $repositoryStyleHub "knowledge-hub/templates/languages") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $repositoryStyleHub "README.md") -Value "fixture" -Encoding ASCII
New-Item -ItemType Directory -Path $repositoryStyleProject | Out-Null
Set-Content -LiteralPath (Join-Path $repositoryStyleProject "sentinel.txt") -Value "project fixture" -Encoding ASCII
$repositoryStyleHubBefore = Get-TreeFingerprint -Root $repositoryStyleHub
$repositoryStyleProjectBefore = Get-TreeFingerprint -Root $repositoryStyleProject
$repositoryStyleFailure = Assert-ExpectedFailure -Name "repository-style-explicit-hub" -ExpectedToken "directly contains templates/languages" -Command {
    & $BootstrapScript -ProjectDir $repositoryStyleProject -HubDir $repositoryStyleHub -SkipMemoryUpgradeAnalysis
}
if ($repositoryStyleFailure.error -notlike "*knowledge-hub subdirectory*") {
    throw "Fixture 'repository-style-explicit-hub' expected a knowledge-hub subdirectory hint."
}
Assert-Unchanged -Root $repositoryStyleHub -Before $repositoryStyleHubBefore -Name "repository-style-explicit-hub-hub"
Assert-Unchanged -Root $repositoryStyleProject -Before $repositoryStyleProjectBefore -Name "repository-style-explicit-hub-project"
$results.Add([ordered]@{ name = "repository-style-explicit-hub"; status = "PASS"; error = $repositoryStyleFailure.error }) | Out-Null

$ordinaryNonHub = Join-Path $scratchFull "ordinary-non-hub"
$ordinaryNonHubProject = Join-Path $scratchFull "ordinary-non-hub-project"
New-Item -ItemType Directory -Path $ordinaryNonHub | Out-Null
Set-Content -LiteralPath (Join-Path $ordinaryNonHub "sentinel.txt") -Value "hub fixture" -Encoding ASCII
New-Item -ItemType Directory -Path $ordinaryNonHubProject | Out-Null
Set-Content -LiteralPath (Join-Path $ordinaryNonHubProject "sentinel.txt") -Value "project fixture" -Encoding ASCII
$ordinaryNonHubBefore = Get-TreeFingerprint -Root $ordinaryNonHub
$ordinaryNonHubProjectBefore = Get-TreeFingerprint -Root $ordinaryNonHubProject
$ordinaryNonHubFailure = Assert-ExpectedFailure -Name "ordinary-explicit-non-hub" -ExpectedToken "directly contains templates/languages" -Command {
    & $BootstrapScript -ProjectDir $ordinaryNonHubProject -HubDir $ordinaryNonHub -SkipMemoryUpgradeAnalysis
}
if ($ordinaryNonHubFailure.error -like "*knowledge-hub subdirectory*") {
    throw "Fixture 'ordinary-explicit-non-hub' received an inapplicable knowledge-hub subdirectory hint."
}
Assert-Unchanged -Root $ordinaryNonHub -Before $ordinaryNonHubBefore -Name "ordinary-explicit-non-hub-hub"
Assert-Unchanged -Root $ordinaryNonHubProject -Before $ordinaryNonHubProjectBefore -Name "ordinary-explicit-non-hub-project"
$results.Add([ordered]@{ name = "ordinary-explicit-non-hub"; status = "PASS"; error = $ordinaryNonHubFailure.error }) | Out-Null

$explicitNewHub = Join-Path $scratchFull "explicit-new-hub"
$explicitNewProject = Join-Path $scratchFull "explicit-new-project"
New-Item -ItemType Directory -Path $explicitNewProject | Out-Null
& $BootstrapScript -ProjectDir $explicitNewProject -HubDir $explicitNewHub -SkipMemoryUpgradeAnalysis | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $explicitNewHub "templates/languages") -PathType Container)) {
    throw "Explicit new hub directory was not initialized."
}
if ($LASTEXITCODE -ne 0) {
    throw "Successful explicit new hub initialization leaked LASTEXITCODE=$LASTEXITCODE."
}
$results.Add([ordered]@{ name = "explicit-new-hub"; status = "PASS" }) | Out-Null

$explicitEmptyHub = Join-Path $scratchFull "explicit-empty-hub"
$explicitEmptyProject = Join-Path $scratchFull "explicit-empty-project"
New-Item -ItemType Directory -Path $explicitEmptyHub | Out-Null
New-Item -ItemType Directory -Path $explicitEmptyProject | Out-Null
& $BootstrapScript -ProjectDir $explicitEmptyProject -HubDir $explicitEmptyHub -SkipMemoryUpgradeAnalysis | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $explicitEmptyHub "templates/languages") -PathType Container)) {
    throw "Explicit empty hub directory was not initialized."
}
$results.Add([ordered]@{ name = "explicit-empty-hub"; status = "PASS" }) | Out-Null

$defaultHubProfile = Join-Path $scratchFull "default-hub-profile"
$defaultHubProject = Join-Path $scratchFull "default-hub-project"
New-Item -ItemType Directory -Path $defaultHubProfile | Out-Null
New-Item -ItemType Directory -Path $defaultHubProject | Out-Null
$previousUserProfile = $env:USERPROFILE
try {
    $env:USERPROFILE = $defaultHubProfile
    & $BootstrapScript -ProjectDir $defaultHubProject -SkipMemoryUpgradeAnalysis | Out-Null
} finally {
    $env:USERPROFILE = $previousUserProfile
}
$expectedDefaultHub = Join-Path $defaultHubProfile ".agents/knowledge-hub/templates/languages"
if (-not (Test-Path -LiteralPath $expectedDefaultHub -PathType Container)) {
    throw "Missing default runtime hub was not initialized."
}
$results.Add([ordered]@{ name = "missing-default-hub"; status = "PASS" }) | Out-Null

$inheritProject = Join-Path $scratchFull "existing-zh-cn"
New-Item -ItemType Directory -Path $inheritProject | Out-Null
& $BootstrapScript -ProjectDir $inheritProject -HubDir $HubDir -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis | Out-Null
$missingScaffold = Join-Path $inheritProject ".agents/context"
Remove-Item -LiteralPath $missingScaffold -Recurse -Force
$inheritOutput = @(& $BootstrapScript -ProjectDir $inheritProject -HubDir $HubDir -AnalyzeMemoryUpgrade)
$inheritLock = Get-Content -LiteralPath (Join-Path $inheritProject ".agents/hub.lock.json") -Raw | ConvertFrom-Json
if ([string]$inheritLock.project_language -ne "zh-CN") {
    throw "Omitted -ProjectLanguage did not inherit zh-CN from hub.lock.json."
}
$inheritWorkspaceModel = [string]$inheritLock.workspace_model
if ($inheritWorkspaceModel -ne "c3.3" -or [string]$inheritLock.workspace_state -ne "active") {
    throw "Fresh project bootstrap did not produce the active C3.3 workspace contract."
}
$expectedZhWorkspace = Join-Path $inheritProject ".agents/context"
if (-not (Test-Path -LiteralPath $expectedZhWorkspace -PathType Container)) {
    throw "Inherited bootstrap did not restore the C3.3 workspace context root."
}
$resolvedIndex = [array]::FindIndex([string[]]$inheritOutput, [Predicate[string]]{ param($line) $line -match '^Resolved project dir: ' })
$completeIndex = [array]::FindIndex([string[]]$inheritOutput, [Predicate[string]]{ param($line) $line -eq 'Project bootstrap complete.' })
if ($resolvedIndex -lt 0 -or $completeIndex -lt 0 -or $resolvedIndex -ge $completeIndex) {
    throw "Resolved project dir was not visible before bootstrap completion output."
}
$results.Add([ordered]@{ name = "inherit-lock-language"; status = "PASS"; project_language = "zh-CN" }) | Out-Null
$results.Add([ordered]@{ name = "valid-explicit-hub"; status = "PASS" }) | Out-Null

$unknownProject = Join-Path $scratchFull "unknown-parameter"
New-Item -ItemType Directory -Path $unknownProject | Out-Null
$unknownBefore = Get-TreeFingerprint -Root $unknownProject
$unknownFailure = Assert-ExpectedFailure -Name "unknown-parameter" -ExpectedToken "UnknownFixtureParameter" -Command {
    & $BootstrapScript -ProjectDir $unknownProject -HubDir $HubDir -UnknownFixtureParameter "value" -SkipMemoryUpgradeAnalysis
}
Assert-Unchanged -Root $unknownProject -Before $unknownBefore -Name "unknown-parameter"
$results.Add([ordered]@{ name = "unknown-parameter"; status = "PASS"; error = $unknownFailure.error }) | Out-Null

$projectRootMistake = Join-Path $scratchFull "project-root-mistake"
New-Item -ItemType Directory -Path $projectRootMistake | Out-Null
$projectRootBefore = Get-TreeFingerprint -Root $projectRootMistake
$projectRootFailure = Assert-ExpectedFailure -Name "project-root-mistake" -ExpectedToken "Use -ProjectDir" -Command {
    & $BootstrapScript -ProjectRoot $projectRootMistake -HubDir $HubDir -AnalyzeMemoryUpgrade
}
Assert-Unchanged -Root $projectRootMistake -Before $projectRootBefore -Name "project-root-mistake"
$results.Add([ordered]@{ name = "project-root-mistake"; status = "PASS"; error = $projectRootFailure.error }) | Out-Null

$conflictOmittedProject = Join-Path $scratchFull "language-conflict-omitted"
New-Item -ItemType Directory -Path $conflictOmittedProject | Out-Null
& $BootstrapScript -ProjectDir $conflictOmittedProject -HubDir $HubDir -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis | Out-Null
$conflictOmittedGuide = Join-Path $conflictOmittedProject ".agents/AGENTS.md"
Set-Content -LiteralPath $conflictOmittedGuide -Value "Project memory language: English." -Encoding ASCII
$conflictOmittedBefore = Get-TreeFingerprint -Root $conflictOmittedProject
$conflictOmittedFailure = Assert-ExpectedFailure -Name "language-conflict-omitted" -ExpectedToken "Project language conflict" -Command {
    & $BootstrapScript -ProjectDir $conflictOmittedProject -HubDir $HubDir -AnalyzeMemoryUpgrade
}
Assert-Unchanged -Root $conflictOmittedProject -Before $conflictOmittedBefore -Name "language-conflict-omitted"
$results.Add([ordered]@{ name = "language-conflict-omitted"; status = "PASS"; error = $conflictOmittedFailure.error }) | Out-Null

$conflictExplicitProject = Join-Path $scratchFull "language-conflict-explicit"
New-Item -ItemType Directory -Path $conflictExplicitProject | Out-Null
& $BootstrapScript -ProjectDir $conflictExplicitProject -HubDir $HubDir -ProjectLanguage "zh-CN" -SkipMemoryUpgradeAnalysis | Out-Null
$conflictExplicitGuide = Join-Path $conflictExplicitProject ".agents/AGENTS.md"
Set-Content -LiteralPath $conflictExplicitGuide -Value "Project memory language: English." -Encoding ASCII
$conflictExplicitBefore = Get-TreeFingerprint -Root $conflictExplicitProject
$conflictExplicitFailure = Assert-ExpectedFailure -Name "language-conflict-explicit" -ExpectedToken "Project language conflict" -Command {
    & $BootstrapScript -ProjectDir $conflictExplicitProject -HubDir $HubDir -ProjectLanguage "zh-CN" -AnalyzeMemoryUpgrade
}
Assert-Unchanged -Root $conflictExplicitProject -Before $conflictExplicitBefore -Name "language-conflict-explicit"
$results.Add([ordered]@{ name = "language-conflict-explicit"; status = "PASS"; error = $conflictExplicitFailure.error }) | Out-Null

# NOTE: Issue #369 —— workspace 身份歧义只限定为"既有 memory 且
# .agents/hub.lock.json 文件缺失"，默认 fail closed；-LegacyWorkspace 只表达
# 调用方的 legacy 意图，适用条件在任何写入或迁移委托前校验；既有 lock 文件
# （含无 workspace_model 的旧格式）保持原行为，不走歧义分支。
$identityHubBefore = Get-TreeFingerprint -Root $HubDir

$identityNoLockProject = Join-Path $scratchFull "workspace-identity-no-lock"
New-Item -ItemType Directory -Path $identityNoLockProject | Out-Null
Set-Content -LiteralPath (Join-Path $identityNoLockProject "AGENTS.md") -Value "# fixture legacy memory" -Encoding ASCII
$identityNoLockBefore = Get-TreeFingerprint -Root $identityNoLockProject
$identityNoLockFailure = Assert-ExpectedFailure -Name "workspace-identity-missing-no-lock" -ExpectedToken "Ambiguous workspace identity" -Command {
    & $BootstrapScript -ProjectDir $identityNoLockProject -HubDir $HubDir -SkipMemoryUpgradeAnalysis
}
Assert-Unchanged -Root $identityNoLockProject -Before $identityNoLockBefore -Name "workspace-identity-missing-no-lock-project"
Assert-Unchanged -Root $HubDir -Before $identityHubBefore -Name "workspace-identity-missing-no-lock-hub"
$results.Add([ordered]@{ name = "workspace-identity-missing-no-lock"; status = "PASS"; error = $identityNoLockFailure.error }) | Out-Null

$identityNoLockAnalyzeProject = Join-Path $scratchFull "workspace-identity-no-lock-analyze"
New-Item -ItemType Directory -Path $identityNoLockAnalyzeProject | Out-Null
Set-Content -LiteralPath (Join-Path $identityNoLockAnalyzeProject "AGENTS.md") -Value "# fixture legacy memory" -Encoding ASCII
$identityNoLockAnalyzeBefore = Get-TreeFingerprint -Root $identityNoLockAnalyzeProject
$identityNoLockAnalyzeFailure = Assert-ExpectedFailure -Name "workspace-identity-missing-analyze-wrapper" -ExpectedToken "Ambiguous workspace identity" -Command {
    & $BootstrapScript -ProjectDir $identityNoLockAnalyzeProject -HubDir $HubDir -AnalyzeMemoryUpgrade
}
Assert-Unchanged -Root $identityNoLockAnalyzeProject -Before $identityNoLockAnalyzeBefore -Name "workspace-identity-missing-analyze-wrapper-project"
Assert-Unchanged -Root $HubDir -Before $identityHubBefore -Name "workspace-identity-missing-analyze-wrapper-hub"
$results.Add([ordered]@{ name = "workspace-identity-missing-analyze-wrapper"; status = "PASS"; error = $identityNoLockAnalyzeFailure.error }) | Out-Null

$identityLegacyProject = Join-Path $scratchFull "workspace-identity-legacy-selected"
New-Item -ItemType Directory -Path $identityLegacyProject | Out-Null
Set-Content -LiteralPath (Join-Path $identityLegacyProject "AGENTS.md") -Value "# fixture legacy memory" -Encoding ASCII
$identityLegacyBeforeMap = Get-TreeFileHashMap -Root $identityLegacyProject
& $BootstrapScript -ProjectDir $identityLegacyProject -HubDir $HubDir -LegacyWorkspace -SkipMemoryUpgradeAnalysis | Out-Null
$identityLegacyAfterMap = Get-TreeFileHashMap -Root $identityLegacyProject
Assert-ExistingFilesUnchanged -BeforeMap $identityLegacyBeforeMap -AfterMap $identityLegacyAfterMap -Name "Explicit legacy bootstrap"
$identityLegacyAddedCount = Assert-ExplicitLegacyAddedFiles -BeforeMap $identityLegacyBeforeMap -AfterMap $identityLegacyAfterMap -HubDir $HubDir
$identityLegacyLock = Get-Content -LiteralPath (Join-Path $identityLegacyProject ".agents/hub.lock.json") -Raw | ConvertFrom-Json
if ([string]$identityLegacyLock.workspace_model -ne "legacy" -or [string]$identityLegacyLock.workspace_state -ne "not-enabled") {
    throw "Explicit -LegacyWorkspace did not persist the declared legacy workspace identity."
}
foreach ($legacySurface in @(".agents/process.txt", ".agents/AGENTS.md", "CLAUDE.md", ".claude/settings.json")) {
    if (-not (Test-Path -LiteralPath (Join-Path $identityLegacyProject $legacySurface))) {
        throw "Explicit legacy bootstrap did not create the declared legacy scaffold surface: $legacySurface"
    }
}
foreach ($c33Surface in @(".agents/work", ".agents/skills")) {
    if (Test-Path -LiteralPath (Join-Path $identityLegacyProject $c33Surface)) {
        throw "Explicit legacy bootstrap must not create the C3.3 workspace surface: $c33Surface"
    }
}
Assert-Unchanged -Root $HubDir -Before $identityHubBefore -Name "workspace-identity-legacy-selected-hub"
$results.Add([ordered]@{ name = "workspace-identity-legacy-selected"; status = "PASS"; added_file_count = $identityLegacyAddedCount }) | Out-Null

# NOTE: 既有 lock（无 workspace_model 的旧格式）保持原行为：不带参数仍按既有
# 选择执行；-LegacyWorkspace 因 lock 文件存在而不适用，在任何写入前拒绝。
$identityOldLockProject = Join-Path $scratchFull "workspace-identity-old-lock"
New-Item -ItemType Directory -Path (Join-Path $identityOldLockProject ".agents") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $identityOldLockProject "AGENTS.md") -Value "# fixture legacy memory" -Encoding ASCII
$identityOldLockMemoryHash = (Get-FileHash -LiteralPath (Join-Path $identityOldLockProject "AGENTS.md") -Algorithm SHA256).Hash
$identityOldLockData = [ordered]@{
    schema_version = 1
    installed_at_utc = "2026-01-01T00:00:00.0000000Z"
    installer = "project-bootstrap"
    project_dir = $identityOldLockProject
    project_language = "en"
}
$identityOldLockData | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $identityOldLockProject ".agents/hub.lock.json") -Encoding ASCII
$identityOldLockBefore = Get-TreeFingerprint -Root $identityOldLockProject
$identityOldLockMisuseFailure = Assert-ExpectedFailure -Name "legacy-workspace-existing-lock-misuse" -ExpectedToken "applies only when existing project memory is present" -Command {
    & $BootstrapScript -ProjectDir $identityOldLockProject -HubDir $HubDir -LegacyWorkspace -SkipMemoryUpgradeAnalysis
}
Assert-Unchanged -Root $identityOldLockProject -Before $identityOldLockBefore -Name "legacy-workspace-existing-lock-misuse-project"
Assert-Unchanged -Root $HubDir -Before $identityHubBefore -Name "legacy-workspace-existing-lock-misuse-hub"
$results.Add([ordered]@{ name = "legacy-workspace-existing-lock-misuse"; status = "PASS"; error = $identityOldLockMisuseFailure.error }) | Out-Null

& $BootstrapScript -ProjectDir $identityOldLockProject -HubDir $HubDir -SkipMemoryUpgradeAnalysis | Out-Null
$identityOldLockPlain = Get-Content -LiteralPath (Join-Path $identityOldLockProject ".agents/hub.lock.json") -Raw | ConvertFrom-Json
if ([string]$identityOldLockPlain.workspace_model -ne "legacy") {
    throw "Plain bootstrap on an existing lock without workspace_model must keep the original legacy selection behavior."
}
if ((Get-FileHash -LiteralPath (Join-Path $identityOldLockProject "AGENTS.md") -Algorithm SHA256).Hash -ne $identityOldLockMemoryHash) {
    throw "Plain bootstrap on an existing old-format lock modified existing project memory."
}
$results.Add([ordered]@{ name = "existing-lock-plain-original-behavior"; status = "PASS" }) | Out-Null

# NOTE: 真实故障 fixture —— 正式 bootstrap 建立完整 C3.3 后仅移除 lock，
# 两个独立且初始状态相同的副本分别验证默认拒绝与显式 legacy 选择（首次
# legacy 接入）；不能用旧格式 lock 替代该场景。
$identityC33BaseProject = Join-Path $scratchFull "workspace-identity-c33-base"
New-Item -ItemType Directory -Path $identityC33BaseProject | Out-Null
& $BootstrapScript -ProjectDir $identityC33BaseProject -HubDir $HubDir -ProjectLanguage "en" -SkipMemoryUpgradeAnalysis | Out-Null
$identityC33BaseLock = Get-Content -LiteralPath (Join-Path $identityC33BaseProject ".agents/hub.lock.json") -Raw | ConvertFrom-Json
if ([string]$identityC33BaseLock.workspace_model -cne "c3.3") {
    throw "C3.3 lock-removed fixture base was not established by a real bootstrap."
}
$identityC33BaseFingerprint = Get-TreeFingerprint -Root $identityC33BaseProject

$identityC33RejectProject = Join-Path $scratchFull "workspace-identity-c33-lock-removed-reject"
$identityC33LegacySelectedProject = Join-Path $scratchFull "workspace-identity-c33-lock-removed-legacy"
Copy-Item -LiteralPath $identityC33BaseProject -Destination $identityC33RejectProject -Recurse
Copy-Item -LiteralPath $identityC33BaseProject -Destination $identityC33LegacySelectedProject -Recurse
foreach ($copiedProject in @($identityC33RejectProject, $identityC33LegacySelectedProject)) {
    if ((Get-TreeFingerprint -Root $copiedProject) -cne $identityC33BaseFingerprint) {
        throw "Lock-removed fixture copies did not start from an identical C3.3 state: $copiedProject"
    }
}
foreach ($copiedProject in @($identityC33RejectProject, $identityC33LegacySelectedProject)) {
    Remove-Item -LiteralPath (Join-Path $copiedProject ".agents/hub.lock.json") -Force
}

$identityC33RejectBefore = Get-TreeFingerprint -Root $identityC33RejectProject
$identityC33RejectFailure = Assert-ExpectedFailure -Name "workspace-identity-c33-lock-removed-reject" -ExpectedToken "Ambiguous workspace identity" -Command {
    & $BootstrapScript -ProjectDir $identityC33RejectProject -HubDir $HubDir -SkipMemoryUpgradeAnalysis
}
Assert-Unchanged -Root $identityC33RejectProject -Before $identityC33RejectBefore -Name "workspace-identity-c33-lock-removed-reject-project"
Assert-Unchanged -Root $HubDir -Before $identityHubBefore -Name "workspace-identity-c33-lock-removed-reject-hub"
$results.Add([ordered]@{ name = "workspace-identity-c33-lock-removed-reject"; status = "PASS"; error = $identityC33RejectFailure.error }) | Out-Null

$identityC33BeforeMap = Get-TreeFileHashMap -Root $identityC33LegacySelectedProject
& $BootstrapScript -ProjectDir $identityC33LegacySelectedProject -HubDir $HubDir -LegacyWorkspace -SkipMemoryUpgradeAnalysis | Out-Null
$identityC33AfterMap = Get-TreeFileHashMap -Root $identityC33LegacySelectedProject
Assert-ExistingFilesUnchanged -BeforeMap $identityC33BeforeMap -AfterMap $identityC33AfterMap -Name "Explicit legacy bootstrap on a lock-less C3.3 project"
$identityC33AddedCount = Assert-ExplicitLegacyAddedFiles -BeforeMap $identityC33BeforeMap -AfterMap $identityC33AfterMap -HubDir $HubDir
$identityC33LegacyLock = Get-Content -LiteralPath (Join-Path $identityC33LegacySelectedProject ".agents/hub.lock.json") -Raw | ConvertFrom-Json
if ([string]$identityC33LegacyLock.workspace_model -cne "legacy" -or [string]$identityC33LegacyLock.workspace_state -cne "not-enabled") {
    throw "Explicit legacy bootstrap on a lock-less C3.3 project did not record the legacy workspace identity."
}
Assert-Unchanged -Root $HubDir -Before $identityHubBefore -Name "workspace-identity-c33-lock-removed-legacy-hub"
$results.Add([ordered]@{ name = "workspace-identity-c33-lock-removed-legacy-selected"; status = "PASS"; added_file_count = $identityC33AddedCount }) | Out-Null

$identityEmptyMisuseProject = Join-Path $scratchFull "workspace-identity-empty-misuse"
New-Item -ItemType Directory -Path $identityEmptyMisuseProject | Out-Null
$identityEmptyMisuseBefore = Get-TreeFingerprint -Root $identityEmptyMisuseProject
$identityEmptyMisuseFailure = Assert-ExpectedFailure -Name "legacy-workspace-empty-misuse" -ExpectedToken "applies only when existing project memory is present" -Command {
    & $BootstrapScript -ProjectDir $identityEmptyMisuseProject -HubDir $HubDir -LegacyWorkspace -SkipMemoryUpgradeAnalysis
}
Assert-Unchanged -Root $identityEmptyMisuseProject -Before $identityEmptyMisuseBefore -Name "legacy-workspace-empty-misuse-project"
Assert-Unchanged -Root $HubDir -Before $identityHubBefore -Name "legacy-workspace-empty-misuse-hub"
$results.Add([ordered]@{ name = "legacy-workspace-empty-misuse"; status = "PASS"; error = $identityEmptyMisuseFailure.error }) | Out-Null

$identityLegacyDeclaredBefore = Get-TreeFingerprint -Root $identityLegacyProject
$identityLegacyMisuseFailure = Assert-ExpectedFailure -Name "legacy-workspace-declared-legacy-misuse" -ExpectedToken "applies only when existing project memory is present" -Command {
    & $BootstrapScript -ProjectDir $identityLegacyProject -HubDir $HubDir -LegacyWorkspace -SkipMemoryUpgradeAnalysis
}
Assert-Unchanged -Root $identityLegacyProject -Before $identityLegacyDeclaredBefore -Name "legacy-workspace-declared-legacy-misuse-project"
$results.Add([ordered]@{ name = "legacy-workspace-declared-legacy-misuse"; status = "PASS"; error = $identityLegacyMisuseFailure.error }) | Out-Null

$identityC33MisuseBefore = Get-TreeFingerprint -Root $inheritProject
$identityC33MisuseFailure = Assert-ExpectedFailure -Name "legacy-workspace-declared-c33-misuse" -ExpectedToken "applies only when existing project memory is present" -Command {
    & $BootstrapScript -ProjectDir $inheritProject -HubDir $HubDir -LegacyWorkspace -SkipMemoryUpgradeAnalysis
}
Assert-Unchanged -Root $inheritProject -Before $identityC33MisuseBefore -Name "legacy-workspace-declared-c33-misuse-project"
$results.Add([ordered]@{ name = "legacy-workspace-declared-c33-misuse"; status = "PASS"; error = $identityC33MisuseFailure.error }) | Out-Null

$identityLegacyRefreshMemoryHash = (Get-FileHash -LiteralPath (Join-Path $identityLegacyProject "AGENTS.md") -Algorithm SHA256).Hash
& $BootstrapScript -ProjectDir $identityLegacyProject -HubDir $HubDir -SkipMemoryUpgradeAnalysis | Out-Null
$identityLegacyRefreshLock = Get-Content -LiteralPath (Join-Path $identityLegacyProject ".agents/hub.lock.json") -Raw | ConvertFrom-Json
if ([string]$identityLegacyRefreshLock.workspace_model -ne "legacy") {
    throw "Plain bootstrap on a declared legacy lock must keep the legacy workspace."
}
if ((Get-FileHash -LiteralPath (Join-Path $identityLegacyProject "AGENTS.md") -Algorithm SHA256).Hash -ne $identityLegacyRefreshMemoryHash) {
    throw "Plain legacy refresh modified existing project memory."
}
$results.Add([ordered]@{ name = "legacy-lock-plain-refresh"; status = "PASS" }) | Out-Null

$identityComboProject = Join-Path $scratchFull "workspace-identity-language-migration-combo"
New-Item -ItemType Directory -Path $identityComboProject | Out-Null
Set-Content -LiteralPath (Join-Path $identityComboProject "AGENTS.md") -Value "# fixture legacy memory" -Encoding ASCII
$identityComboBefore = Get-TreeFingerprint -Root $identityComboProject
& $BootstrapScript -ProjectDir $identityComboProject -HubDir $HubDir -LegacyWorkspace -AnalyzeLanguageMigration -SourceLanguage en -TargetLanguage zh-CN | Out-Null
if ((Get-TreeFingerprint -Root $identityComboProject) -ne $identityComboBefore) {
    throw "Language migration analysis combined with -LegacyWorkspace must not write project files."
}
$results.Add([ordered]@{ name = "workspace-identity-language-migration-combo"; status = "PASS" }) | Out-Null

# NOTE: 不适用输入上的显式 -LegacyWorkspace 组合必须在迁移委托前拒绝；
# Apply 分支用不存在的 proposal 直接证明拒绝发生在委托之前，不依赖 Analyze 的只读性。
$identityComboAnalyzeProject = Join-Path $scratchFull "workspace-identity-combo-analyze-misuse"
New-Item -ItemType Directory -Path $identityComboAnalyzeProject | Out-Null
$identityComboAnalyzeBefore = Get-TreeFingerprint -Root $identityComboAnalyzeProject
$identityComboAnalyzeFailure = Assert-ExpectedFailure -Name "legacy-workspace-combo-analyze-misuse" -ExpectedToken "applies only when existing project memory is present" -Command {
    & $BootstrapScript -ProjectDir $identityComboAnalyzeProject -HubDir $HubDir -LegacyWorkspace -AnalyzeLanguageMigration -SourceLanguage en -TargetLanguage zh-CN
}
Assert-Unchanged -Root $identityComboAnalyzeProject -Before $identityComboAnalyzeBefore -Name "legacy-workspace-combo-analyze-misuse-project"
Assert-Unchanged -Root $HubDir -Before $identityHubBefore -Name "legacy-workspace-combo-analyze-misuse-hub"
$results.Add([ordered]@{ name = "legacy-workspace-combo-analyze-misuse"; status = "PASS"; error = $identityComboAnalyzeFailure.error }) | Out-Null

$identityComboApplyProject = Join-Path $scratchFull "workspace-identity-combo-apply-misuse"
New-Item -ItemType Directory -Path $identityComboApplyProject | Out-Null
$identityComboApplyBefore = Get-TreeFingerprint -Root $identityComboApplyProject
$identityComboApplyFailure = Assert-ExpectedFailure -Name "legacy-workspace-combo-apply-misuse" -ExpectedToken "applies only when existing project memory is present" -Command {
    & $BootstrapScript -ProjectDir $identityComboApplyProject -HubDir $HubDir -LegacyWorkspace -ApplyLanguageMigration -MigrationPlan (Join-Path $scratchFull "nonexistent-migration-plan.json")
}
Assert-Unchanged -Root $identityComboApplyProject -Before $identityComboApplyBefore -Name "legacy-workspace-combo-apply-misuse-project"
Assert-Unchanged -Root $HubDir -Before $identityHubBefore -Name "legacy-workspace-combo-apply-misuse-hub"
$results.Add([ordered]@{ name = "legacy-workspace-combo-apply-misuse"; status = "PASS"; error = $identityComboApplyFailure.error }) | Out-Null

$missingProject = Join-Path $scratchFull "missing-target"
$missingFailure = Assert-ExpectedFailure -Name "missing-target" -ExpectedToken "does not exist" -Command {
    & $BootstrapScript -ProjectDir $missingProject -HubDir $HubDir -SkipMemoryUpgradeAnalysis
}
if (Test-Path -LiteralPath $missingProject) {
    throw "Missing target error path created the target directory."
}
$results.Add([ordered]@{ name = "missing-target"; status = "PASS"; error = $missingFailure.error }) | Out-Null

$fileTarget = Join-Path $scratchFull "file-target.txt"
Set-Content -LiteralPath $fileTarget -Value "fixture" -Encoding ASCII
$fileHashBefore = (Get-FileHash -LiteralPath $fileTarget -Algorithm SHA256).Hash
$fileFailure = Assert-ExpectedFailure -Name "file-target" -ExpectedToken "does not exist" -Command {
    & $BootstrapScript -ProjectDir $fileTarget -HubDir $HubDir -SkipMemoryUpgradeAnalysis
}
if ((Get-FileHash -LiteralPath $fileTarget -Algorithm SHA256).Hash -ne $fileHashBefore) {
    throw "File target error path modified the target file."
}
$results.Add([ordered]@{ name = "file-target"; status = "PASS"; error = $fileFailure.error }) | Out-Null

$report = [ordered]@{
    status = "PASS"
    fixture_count = $results.Count
    scratch_root = $scratchFull
    fixtures = @($results.ToArray())
}
$global:LASTEXITCODE = 0
if ($Json.IsPresent) {
    $report | ConvertTo-Json -Depth 6
} else {
    Write-Output ("Project bootstrap safety fixtures: PASS ({0})" -f $results.Count)
    foreach ($result in $results) {
        Write-Output ("  - {0}: {1}" -f $result.name, $result.status)
    }
}
