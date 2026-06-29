# release-eval-benchmark-generator.ps1
# 为 eval iteration fixture 生成确定性 benchmark 产出物
#
# 功能说明：
#   读取 evals.json 和 expected.json，验证 fixture 结构，构建包含
#   pass_rate、comparison_metadata、source_refs、iteration_index 的
#   确定性 benchmark artifact，与已提交的 benchmark.json 结构一致。
#   不调用 eval runner、LLM 或外部服务。
#
# 使用方法（独立调用）：
#   pwsh -NoProfile -File scripts/validation/release-eval-benchmark-generator.ps1 `
#     -EvalsJsonPath <path-to-evals.json> `
#     -ExpectedJsonPath <path-to-expected.json>
#
# 返回：JSON benchmark artifact 写入 stdout。

<#
.SYNOPSIS
    New-EvalBenchmarkArtifact
    从 evals.json 和 expected.json 生成确定性 benchmark artifact。
.PARAMETER EvalsJsonPath
    evals.json fixture 文件路径。
.PARAMETER ExpectedJsonPath
    expected.json fixture 文件路径。
.OUTPUTS
    Hashtable。benchmark artifact 对象。
#>
function New-EvalBenchmarkArtifact {
    param(
        [string]$EvalsJsonPath,
        [string]$ExpectedJsonPath
    )

    if (-not (Test-Path -LiteralPath $EvalsJsonPath)) {
        throw "Evals JSON not found: $EvalsJsonPath"
    }
    if (-not (Test-Path -LiteralPath $ExpectedJsonPath)) {
        throw "Expected JSON not found: $ExpectedJsonPath"
    }

    $evals = Get-Content -LiteralPath $EvalsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected = Get-Content -LiteralPath $ExpectedJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # 验证必需字段
    if (-not $evals.PSObject.Properties["skill"]) { throw "evals.json missing 'skill'." }
    if (-not $evals.PSObject.Properties["version"]) { throw "evals.json missing 'version'." }
    if (-not $evals.PSObject.Properties["evals"]) { throw "evals.json missing 'evals'." }
    if (-not $expected.PSObject.Properties["fixture"]) { throw "expected.json missing 'fixture'." }
    if (-not $expected.PSObject.Properties["expected_eval_count"]) { throw "expected.json missing 'expected_eval_count'." }
    if (-not $expected.PSObject.Properties["expected_assertion_count"]) { throw "expected.json missing 'expected_assertion_count'." }
    if (-not $expected.PSObject.Properties["expected_eval_ids"]) { throw "expected.json missing 'expected_eval_ids'." }

    # 实现字段一致性校验
    $skillName = [string]$evals.skill
    $evalCases = @($evals.evals)
    $evalCount = $evalCases.Count
    $expectedEvalCount = [int]$expected.expected_eval_count
    if ($evalCount -ne $expectedEvalCount) {
        throw "Eval count mismatch: evals.json has $evalCount, expected.json expects $expectedEvalCount."
    }
    $expectedEvalIds = @([string[]]$expected.expected_eval_ids)
    $actualEvalIds = @($evals.evals | ForEach-Object { [string]$_.id })
    $missing = $expectedEvalIds | Where-Object { $_ -notin $actualEvalIds }
    if ($missing) {
        throw "Eval IDs missing from evals.json: $($missing -join ', ')."
    }
    $extra = $actualEvalIds | Where-Object { $_ -notin $expectedEvalIds }
    if ($extra) {
        throw "Eval IDs in evals.json not in expected.json: $($extra -join ', ')."
    }

    # 断言计数
    $totalAssertions = 0
    foreach ($evalCase in $evalCases) {
        $totalAssertions += @($evalCase.assertions).Count
    }
    $expectedAssertions = [int]$expected.expected_assertion_count
    if ($totalAssertions -ne $expectedAssertions) {
        throw "Assertion count mismatch: evals.json has $totalAssertions, expected.json expects $expectedAssertions."
    }

    # 在静态确定性模式下所有 eval 均为 PASS
    $evalsPassed = $evalCount
    $evalsFailed = 0
    $assertionsPassed = $totalAssertions
    $assertionsFailed = 0
    $status = "PASS"

    $fixtureName = [string]$expected.fixture

    [ordered]@{
        skill = $skillName
        version = [int]$evals.version
        fixture = $fixtureName
        iteration_type = "static"
        description = "Deterministic static benchmark artifact for eval iteration-001 of $skillName. Records baseline pass rate, comparison metadata, delta placeholder, iteration index, and source references. No eval runner or LLM is invoked."
        iteration_index = 1
        benchmark_identity = [ordered]@{
            name = "${fixtureName}-iteration-001"
            iteration = 1
            description = "Static baseline benchmark for $skillName eval pilot. Records identity, pass rate, source refs, and comparison metadata before any live eval iteration."
        }
        source_refs = [ordered]@{
            evals_path = "${fixtureName}/evals.json"
            report_path = "${fixtureName}/report.json"
            baseline_path = "${fixtureName}/baseline.json"
            runner_output_path = "${fixtureName}/runner-output-example.json"
            runner_output_schema_path = "${fixtureName}/runner-output-schema.json"
        }
        pass_rate = [ordered]@{
            description = "Overall pass rate from the report artifact for this iteration."
            rate = 1.0
            eval_count = $evalCount
            evals_passed = $evalsPassed
            evals_failed = $evalsFailed
            assertions_total = $totalAssertions
            assertions_passed = $assertionsPassed
            assertions_failed = $assertionsFailed
            status = $status
        }
        comparison_metadata = [ordered]@{
            comparison_mode = "baseline"
            description = "Static baseline recording for future with-skill / without-skill comparison. All comparison fields are placeholder values representing pre-live-eval state."
            baseline_pass_rate = 1.0
            comparison_pass_rate = 0.0
            delta = 0.0
            delta_placeholder = "Used in static baseline mode. Populated by a live eval runner during comparison."
            iteration_count = 0
            paired_benchmark_id = ""
        }
        eval_ids = @([string[]]$actualEvalIds)
    }
}

<#
.SYNOPSIS
    Compare-BenchmarkFields
    逐字段比较生成的 benchmark object 与已提交的 benchmark.json。
.PARAMETER Generated
    由 New-EvalBenchmarkArtifact 生成的 benchmark。
.PARAMETER Committed
    已提交的 benchmark.json 解析后的对象。
.OUTPUTS
    Hashtable。包含 match、differences、generated_* 统计。
#>
function Compare-BenchmarkFields {
    param(
        [object]$Generated,
        [object]$Committed
    )

    $diffs = New-Object 'System.Collections.Generic.List[string]'

    # 顶层标量
    if ([string]$Generated.skill -ne [string]$Committed.skill) {
        $diffs.Add("skill: generated '$($Generated.skill)' vs committed '$($Committed.skill)'")
    }
    if ([int]$Generated.version -ne [int]$Committed.version) {
        $diffs.Add("version: generated $($Generated.version) vs committed $($Committed.version)")
    }
    if ([string]$Generated.fixture -ne [string]$Committed.fixture) {
        $diffs.Add("fixture: generated '$($Generated.fixture)' vs committed '$($Committed.fixture)'")
    }
    if ([string]$Generated.iteration_type -ne [string]$Committed.iteration_type) {
        $diffs.Add("iteration_type: generated '$($Generated.iteration_type)' vs committed '$($Committed.iteration_type)'")
    }
    if ([int]$Generated.iteration_index -ne [int]$Committed.iteration_index) {
        $diffs.Add("iteration_index: generated $($Generated.iteration_index) vs committed $($Committed.iteration_index)")
    }

    # benchmark_identity
    if ([string]$Generated.benchmark_identity.name -ne [string]$Committed.benchmark_identity.name) {
        $diffs.Add("benchmark_identity.name: generated '$($Generated.benchmark_identity.name)' vs committed '$($Committed.benchmark_identity.name)'")
    }
    if ([int]$Generated.benchmark_identity.iteration -ne [int]$Committed.benchmark_identity.iteration) {
        $diffs.Add("benchmark_identity.iteration: generated $($Generated.benchmark_identity.iteration) vs committed $($Committed.benchmark_identity.iteration)")
    }

    # source_refs
    foreach ($key in @("evals_path", "report_path", "baseline_path", "runner_output_path", "runner_output_schema_path")) {
        if ([string]$Generated.source_refs.$key -ne [string]$Committed.source_refs.$key) {
            $diffs.Add("source_refs.${key}: generated '$($Generated.source_refs.$key)' vs committed '$($Committed.source_refs.$key)'")
        }
    }

    # pass_rate
    $genRate = [double]$Generated.pass_rate.rate
    $comRate = [double]$Committed.pass_rate.rate
    if ([Math]::Abs($genRate - $comRate) -gt 1e-9) {
        $diffs.Add("pass_rate.rate: generated $genRate vs committed $comRate")
    }
    if ([int]$Generated.pass_rate.eval_count -ne [int]$Committed.pass_rate.eval_count) {
        $diffs.Add("pass_rate.eval_count: generated $($Generated.pass_rate.eval_count) vs committed $($Committed.pass_rate.eval_count)")
    }
    if ([int]$Generated.pass_rate.evals_passed -ne [int]$Committed.pass_rate.evals_passed) {
        $diffs.Add("pass_rate.evals_passed: generated $($Generated.pass_rate.evals_passed) vs committed $($Committed.pass_rate.evals_passed)")
    }
    if ([int]$Generated.pass_rate.assertions_total -ne [int]$Committed.pass_rate.assertions_total) {
        $diffs.Add("pass_rate.assertions_total: generated $($Generated.pass_rate.assertions_total) vs committed $($Committed.pass_rate.assertions_total)")
    }
    if ([int]$Generated.pass_rate.assertions_passed -ne [int]$Committed.pass_rate.assertions_passed) {
        $diffs.Add("pass_rate.assertions_passed: generated $($Generated.pass_rate.assertions_passed) vs committed $($Committed.pass_rate.assertions_passed)")
    }
    if ([string]$Generated.pass_rate.status -ne [string]$Committed.pass_rate.status) {
        $diffs.Add("pass_rate.status: generated '$($Generated.pass_rate.status)' vs committed '$($Committed.pass_rate.status)'")
    }

    # comparison_metadata
    foreach ($key in @("comparison_mode", "paired_benchmark_id")) {
        if ([string]$Generated.comparison_metadata.$key -ne [string]$Committed.comparison_metadata.$key) {
            $diffs.Add("comparison_metadata.${key}: generated '$($Generated.comparison_metadata.$key)' vs committed '$($Committed.comparison_metadata.$key)'")
        }
    }
    $genBpr = [double]$Generated.comparison_metadata.baseline_pass_rate
    $comBpr = [double]$Committed.comparison_metadata.baseline_pass_rate
    if ([Math]::Abs($genBpr - $comBpr) -gt 1e-9) {
        $diffs.Add("comparison_metadata.baseline_pass_rate: generated $genBpr vs committed $comBpr")
    }
    $genDelta = [double]$Generated.comparison_metadata.delta
    $comDelta = [double]$Committed.comparison_metadata.delta
    if ([Math]::Abs($genDelta - $comDelta) -gt 1e-9) {
        $diffs.Add("comparison_metadata.delta: generated $genDelta vs committed $comDelta")
    }
    if ([int]$Generated.comparison_metadata.iteration_count -ne [int]$Committed.comparison_metadata.iteration_count) {
        $diffs.Add("comparison_metadata.iteration_count: generated $($Generated.comparison_metadata.iteration_count) vs committed $($Committed.comparison_metadata.iteration_count)")
    }

    # eval_ids
    $genIds = [string[]]$Generated.eval_ids
    $comIds = [string[]]$Committed.eval_ids
    if ($genIds.Count -ne $comIds.Count) {
        $diffs.Add("eval_ids count: generated $($genIds.Count) vs committed $($comIds.Count)")
    }
    else {
        for ($i = 0; $i -lt $genIds.Count; $i++) {
            if ($genIds[$i] -ne $comIds[$i]) {
                $diffs.Add("eval_ids[$i]: generated '$($genIds[$i])' vs committed '$($comIds[$i])'")
            }
        }
    }

    [ordered]@{
        match = ($diffs.Count -eq 0)
        differences = @($diffs)
        generated_skill = [string]$Generated.skill
        generated_fixture = [string]$Generated.fixture
        generated_eval_count = [int]$Generated.pass_rate.eval_count
        generated_assertion_count = [int]$Generated.pass_rate.assertions_total
        generated_pass_rate = [double]$Generated.pass_rate.rate
        generated_status = [string]$Generated.pass_rate.status
    }
}

<#
.SYNOPSIS
    Test-EvalBenchmarkRegeneration
    编排 benchmark regeneration 和 comparison 流程。
.PARAMETER EvalsJsonPath
    evals.json fixture 文件路径。
.PARAMETER ExpectedJsonPath
    expected.json fixture 文件路径。
.PARAMETER CommittedBenchmarkPath
    已提交的 benchmark.json 路径。
.OUTPUTS
    Hashtable。regeneration evidence。
#>
function Test-EvalBenchmarkRegeneration {
    param(
        [string]$EvalsJsonPath,
        [string]$ExpectedJsonPath,
        [string]$CommittedBenchmarkPath
    )

    if (-not (Test-Path -LiteralPath $CommittedBenchmarkPath)) {
        throw "Committed benchmark not found: $CommittedBenchmarkPath"
    }

    $committedBenchmark = Get-Content -LiteralPath $CommittedBenchmarkPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $generated = New-EvalBenchmarkArtifact -EvalsJsonPath $EvalsJsonPath -ExpectedJsonPath $ExpectedJsonPath
    $comparison = Compare-BenchmarkFields -Generated $generated -Committed $committedBenchmark

    [ordered]@{
        generator_path = "scripts/validation/release-eval-benchmark-generator.ps1"
        benchmark_path = "scripts/validation/eval-iteration-fixtures/workflow-spec-lite/iterations/iteration-001/benchmark.json"
        generated_eval_count = $comparison.generated_eval_count
        generated_assertion_count = $comparison.generated_assertion_count
        generated_pass_rate = $comparison.generated_pass_rate
        generated_status = $comparison.generated_status
        match = [bool]$comparison.match
        differences = @($comparison.differences)
    }
}

# 直接调用入口
if ($MyInvocation.InvocationName -eq "-File" -or $MyInvocation.InvocationName -like "*.ps1") {
    if (-not $args -or $args.Count -lt 2) {
        Write-Error "Usage: pwsh -File release-eval-benchmark-generator.ps1 -EvalsJsonPath <path> -ExpectedJsonPath <path>"
        exit 1
    }
    $eIdx = [array]::IndexOf($args, '-EvalsJsonPath')
    $xIdx = [array]::IndexOf($args, '-ExpectedJsonPath')
    if ($eIdx -lt 0 -or $xIdx -lt 0) {
        Write-Error "Missing required parameters"
        exit 1
    }
    $ePath = $args[$eIdx + 1]
    $xPath = $args[$xIdx + 1]
    if (-not (Test-Path -LiteralPath $ePath)) { throw "Evals JSON not found: $ePath" }
    if (-not (Test-Path -LiteralPath $xPath)) { throw "Expected JSON not found: $xPath" }

    $benchmark = New-EvalBenchmarkArtifact -EvalsJsonPath $ePath -ExpectedJsonPath $xPath
    $benchmark | ConvertTo-Json -Depth 10
}
