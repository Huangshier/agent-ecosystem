# release-eval-runner-generator.ps1
# 确定性 eval runner output artifact 生成器。
# 读取 evals.json + expected.json，验证 fixture 结构，将断言展开为
# assertion_details，产出符合 runner-output-schema.json 的 runner output artifact。
# 不调用 eval runner、不调用 LLM、不访问网络。属于 release validator 生态。

<#
.SYNOPSIS
    New-EvalRunnerOutputArtifact
    从 evals.json 和 expected.json 计算确定性 runner output artifact。
    产出数据符合 runner-output-schema.json v1 契约。
.PARAMETER EvalsJsonPath
    evals.json 的绝对路径。
.PARAMETER ExpectedJsonPath
    expected.json 的绝对路径。
#>
function New-EvalRunnerOutputArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$EvalsJsonPath,
        [Parameter(Mandatory = $true)][string]$ExpectedJsonPath
    )

    if (-not [System.IO.File]::Exists($EvalsJsonPath)) {
        throw ("evals.json not found: " + $EvalsJsonPath)
    }
    $evalsContent = [System.IO.File]::ReadAllText($EvalsJsonPath) | ConvertFrom-Json

    if (-not [System.IO.File]::Exists($ExpectedJsonPath)) {
        throw ("expected.json not found: " + $ExpectedJsonPath)
    }
    $expectedContent = [System.IO.File]::ReadAllText($ExpectedJsonPath) | ConvertFrom-Json

    foreach ($field in @("skill", "version", "evals")) {
        if ($null -eq $evalsContent.$field) {
            throw ("evals.json is missing required top-level field: " + $field)
        }
    }

    $skillName = [string]$evalsContent.skill
    $version = [int]$evalsContent.version
    $evalCases = @($evalsContent.evals)

    if ($evalCases.Count -lt 1) {
        throw "evals.json must contain at least one eval case."
    }

    foreach ($field in @("expected_eval_count", "expected_assertion_count", "expected_eval_ids", "schema_validation")) {
        if ($null -eq $expectedContent.$field) {
            throw ("expected.json is missing required field: " + $field)
        }
    }
    if ($null -eq $expectedContent.schema_validation.allowed_assertion_types) {
        throw "expected.json is missing schema_validation.allowed_assertion_types."
    }

    $allowedTypes = @($expectedContent.schema_validation.allowed_assertion_types | ForEach-Object { [string]$_ })

    $evalResults = New-Object 'System.Collections.Generic.List[object]'
    $totalAssertions = 0
    $totalPassed = 0
    $totalFailed = 0
    $evalsPassed = 0
    $evalsFailed = 0

    foreach ($evalCase in $evalCases) {
        foreach ($field in @("id", "input", "assertions")) {
            if ($null -eq $evalCase.$field) {
                throw ("Eval case is missing required field: " + $field)
            }
        }

        $evalId = [string]$evalCase.id
        $caseAssertions = @($evalCase.assertions)
        $assertionCount = $caseAssertions.Count

        if ($assertionCount -lt 1) {
            throw ("Eval case '" + $evalId + "' has no assertions.")
        }

        $assertionDetails = New-Object 'System.Collections.Generic.List[object]'
        foreach ($assertion in $caseAssertions) {
            if ($null -eq $assertion.type -or $null -eq $assertion.expected) {
                throw ("Assertion in eval case '" + $evalId + "' is missing 'type' or 'expected'.")
            }
            $assertionType = [string]$assertion.type
            if ($assertionType -notin $allowedTypes) {
                throw ("Assertion type '" + $assertionType + "' in eval case '" + $evalId + "' is not in the allowed enum.")
            }

            $assertionDetails.Add([ordered]@{
                type = $assertionType
                expected = [string]$assertion.expected
                actual = [string]$assertion.expected
                passed = $true
            })
        }

        $evalResults.Add([ordered]@{
            eval_id = $evalId
            status = "PASS"
            assertions_total = $assertionCount
            assertions_passed = $assertionCount
            assertions_failed = 0
            assertion_details = @($assertionDetails.ToArray())
        })

        $totalAssertions += $assertionCount
        $totalPassed += $assertionCount
        $evalsPassed++
    }

    $expectedIds = @($expectedContent.expected_eval_ids | ForEach-Object { [string]$_ })
    $actualIds = @($evalCases | ForEach-Object { [string]$_.id })
    $sortedActual = @($actualIds | Sort-Object)
    $sortedExpected = @($expectedIds | Sort-Object)
    if ($sortedActual.Count -ne $sortedExpected.Count) {
        throw ("Eval count mismatch: expected " + $sortedExpected.Count + ", got " + $sortedActual.Count + ".")
    }
    for ($i = 0; $i -lt $sortedActual.Count; $i++) {
        if ($sortedActual[$i] -ne $sortedExpected[$i]) {
            throw ("Eval ID mismatch at index " + $i + ": expected '" + $sortedExpected[$i] + "', got '" + $sortedActual[$i] + "'.")
        }
    }
    if ($evalCases.Count -ne [int]$expectedContent.expected_eval_count) {
        throw ("Eval count mismatch: expected " + $expectedContent.expected_eval_count + ", got " + $evalCases.Count + ".")
    }
    if ($totalAssertions -ne [int]$expectedContent.expected_assertion_count) {
        throw ("Assertion count mismatch: expected " + $expectedContent.expected_assertion_count + ", got " + $totalAssertions + ".")
    }

    $generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    return [ordered]@{
        schema_version = 1
        contract_version = "1.0.0"
        description = ("Deterministic runner output artifact for " + $skillName + " eval suite. Generated from evals.json and expected.json. No eval runner or LLM is invoked.")
        runner_metadata = [ordered]@{
            name = "eval-runner-static-fixture"
            version = "0.0.0"
            mode = "static"
            skill = $skillName
            skill_version = "fixture"
        }
        execution_metadata = [ordered]@{
            started_at = $generatedAt
            finished_at = $generatedAt
            duration_ms = 0
        }
        eval_results = @($evalResults.ToArray())
        failure_reason_shape = [ordered]@{
            description = "When an assertion fails, the finding includes these fields."
            example = [ordered]@{
                eval_id = "<eval-case-id>"
                assertion_type = "<assertion-type>"
                expected = "<expected-value>"
                actual = "<actual-value>"
            }
        }
        comparison_metadata = [ordered]@{
            comparison_mode = "none"
            paired_run_id = ""
            baseline_pass_rate = 0.0
            current_pass_rate = 1.0
            delta = 0.0
        }
        summary = [ordered]@{
            eval_count = $evalCases.Count
            evals_passed = $evalsPassed
            evals_failed = $evalsFailed
            assertions_total = $totalAssertions
            assertions_passed = $totalPassed
            assertions_failed = $totalFailed
            status = "PASS"
        }
    }
}

<#
.SYNOPSIS
    Compare-RunnerOutputFields
    按字段比较生成的和已提交的 runner output 对象。
    所有字段匹配返回 $true，首次不匹配时抛出异常。
    使用结构化字段比较（而非 JSON 字符串比较）以避免跨 PowerShell
    版本的属性顺序差异。
.PARAMETER Generated
    由 New-EvalRunnerOutputArtifact 生成的 runner output 对象。
.PARAMETER Committed
    从 runner-output-example.json 解析的已提交对象。
#>
function Compare-RunnerOutputFields {
    param(
        [Parameter(Mandatory = $true)]$Generated,
        [Parameter(Mandatory = $true)]$Committed
    )

    foreach ($field in @("schema_version", "contract_version")) {
        $gv = [string]$Generated.$field
        $cv = [string]$Committed.$field
        if ($gv -ne $cv) {
            throw ("Runner output regeneration mismatch on field '" + $field + "': generated='" + $gv + "', committed='" + $cv + "'.")
        }
    }

    foreach ($field in @("name", "version", "mode", "skill", "skill_version")) {
        $gv = [string]$Generated.runner_metadata.$field
        $cv = [string]$Committed.runner_metadata.$field
        if ($gv -ne $cv) {
            throw ("Runner output regeneration mismatch on runner_metadata." + $field + ": generated='" + $gv + "', committed='" + $cv + "'.")
        }
    }

    if ([int]$Generated.execution_metadata.duration_ms -ne [int]$Committed.execution_metadata.duration_ms) {
        throw "Runner output regeneration mismatch on execution_metadata.duration_ms."
    }

    $genResults = @($Generated.eval_results)
    $comResults = @($Committed.eval_results)
    $genCount = $genResults.Count
    $comCount = $comResults.Count
    if ($genCount -ne $comCount) {
        throw ("Runner output regeneration mismatch: eval_results count differs (generated=" + $genCount + ", committed=" + $comCount + ").")
    }
    $comById = @{}
    foreach ($r in $comResults) { $comById[[string]$r.eval_id] = $r }
    foreach ($gen in $genResults) {
        $evalId = [string]$gen.eval_id
        $com = $comById[$evalId]
        if ($null -eq $com) {
            throw ("Runner output regeneration mismatch: eval_id '" + $evalId + "' present in generated but missing from committed.")
        }
        foreach ($f in @("status", "assertions_total", "assertions_passed", "assertions_failed")) {
            $gv2 = [string]$gen.$f
            $cv2 = [string]$com.$f
            if ($gv2 -ne $cv2) {
                throw ("Runner output regeneration mismatch on eval '" + $evalId + "' field '" + $f + "': generated='" + $gv2 + "', committed='" + $cv2 + "'.")
            }
        }

        $genDetails = @($gen.assertion_details)
        $comDetails = @($com.assertion_details)
        $gdc = $genDetails.Count
        $cdc = $comDetails.Count
        if ($gdc -ne $cdc) {
            throw ("Runner output regeneration mismatch on eval '" + $evalId + "' assertion_details count: generated=" + $gdc + ", committed=" + $cdc + ".")
        }
        for ($di = 0; $di -lt $genDetails.Count; $di++) {
            foreach ($f in @("type", "expected", "actual", "passed")) {
                $gdv = [string]$genDetails[$di].$f
                $cdv = [string]$comDetails[$di].$f
                if ($gdv -ne $cdv) {
                    throw ("Runner output regeneration mismatch on eval '" + $evalId + "' assertion_detail[" + $di + "]." + $f + ": generated='" + $gdv + "', committed='" + $cdv + "'.")
                }
            }
        }
    }

    $genExample = $Generated.failure_reason_shape.example
    $comExample = $Committed.failure_reason_shape.example
    foreach ($f in @("eval_id", "assertion_type", "expected", "actual")) {
        if ([string]$genExample.$f -ne [string]$comExample.$f) {
            throw ("Runner output regeneration mismatch on failure_reason_shape.example." + $f + ".")
        }
    }

    foreach ($f in @("comparison_mode", "paired_run_id")) {
        $gv3 = [string]$Generated.comparison_metadata.$f
        $cv3 = [string]$Committed.comparison_metadata.$f
        if ($gv3 -ne $cv3) {
            throw ("Runner output regeneration mismatch on comparison_metadata." + $f + ": generated='" + $gv3 + "', committed='" + $cv3 + "'.")
        }
    }
    # 浮点字段用 double 比较：PS 5.1 ConvertFrom-Json 反序列化为 decimal，
    # 而内存中 ordered hash 为 double，字符串化后 "0" vs "0.0" 会误判不匹配。
    foreach ($f in @("baseline_pass_rate", "current_pass_rate", "delta")) {
        $gv3n = [double]$Generated.comparison_metadata.$f
        $cv3n = [double]$Committed.comparison_metadata.$f
        if ($gv3n -ne $cv3n) {
            throw ("Runner output regeneration mismatch on comparison_metadata." + $f + ": generated=" + $gv3n + ", committed=" + $cv3n + ".")
        }
    }

    # 数值字段用数值比较，避免 PS 5.1 decimal/int 与 PS 7 double/int 之间类型差异
    foreach ($f in @("eval_count", "evals_passed", "evals_failed", "assertions_total", "assertions_passed", "assertions_failed")) {
        $gv4n = [int]$Generated.summary.$f
        $cv4n = [int]$Committed.summary.$f
        if ($gv4n -ne $cv4n) {
            throw ("Runner output regeneration mismatch on summary field '" + $f + "': generated=" + $gv4n + ", committed=" + $cv4n + ".")
        }
    }
    $gs = [string]$Generated.summary.status
    $cs = [string]$Committed.summary.status
    if ($gs -ne $cs) {
        throw ("Runner output regeneration mismatch on summary field 'status': generated='" + $gs + "', committed='" + $cs + "'.")
    }

    return $true
}

<#
.SYNOPSIS
    Test-EvalRunnerOutputRegeneration
    从 evals.json 和 expected.json 重新生成 runner output artifact，
    并与已提交的 runner-output-example.json 比较，验证确定性再生能力。
.PARAMETER EvalsJsonPath
    evals.json 的绝对路径。
.PARAMETER ExpectedJsonPath
    expected.json 的绝对路径。
.PARAMETER CommittedExamplePath
    已提交 runner-output-example.json 的绝对路径。
#>
function Test-EvalRunnerOutputRegeneration {
    param(
        [Parameter(Mandatory = $true)][string]$EvalsJsonPath,
        [Parameter(Mandatory = $true)][string]$ExpectedJsonPath,
        [Parameter(Mandatory = $true)][string]$CommittedExamplePath
    )

    $generated = New-EvalRunnerOutputArtifact -EvalsJsonPath $EvalsJsonPath -ExpectedJsonPath $ExpectedJsonPath

    if (-not [System.IO.File]::Exists($CommittedExamplePath)) {
        throw ("Committed runner-output-example.json not found: " + $CommittedExamplePath)
    }
    $committed = [System.IO.File]::ReadAllText($CommittedExamplePath) | ConvertFrom-Json

    [void](Compare-RunnerOutputFields -Generated $generated -Committed $committed)

    return [ordered]@{
        generated_eval_count = @($generated.eval_results).Count
        generated_assertion_count = [int]$generated.summary.assertions_total
        generated_status = [string]$generated.summary.status
        match = $true
    }
}

<#
.SYNOPSIS
    直接调用入口。
    以 -File -EvalsJsonPath / -ExpectedJsonPath 参数调用时，
    生成 runner output artifact 并以 JSON 输出到 stdout。
    以 dot-source 方式加载（InvocationName 为 '.'）时，不执行任何操作。
#>
$isDirectInvocation = $MyInvocation.InvocationName -ne '.'
if ($isDirectInvocation) {
    $evalsPath = ""
    $expectedPath = ""
    for ($ai = 0; $ai -lt $args.Count; $ai++) {
        if ($args[$ai] -eq '-EvalsJsonPath' -and ($ai + 1) -lt $args.Count) {
            $evalsPath = [string]$args[$ai + 1]; $ai++
        }
        elseif ($args[$ai] -eq '-ExpectedJsonPath' -and ($ai + 1) -lt $args.Count) {
            $expectedPath = [string]$args[$ai + 1]; $ai++
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($evalsPath) -and -not [string]::IsNullOrWhiteSpace($expectedPath)) {
        if (-not [System.IO.Path]::IsPathRooted($evalsPath)) {
            $evalsPath = [System.IO.Path]::GetFullPath((Join-Path $PWD $evalsPath))
        }
        if (-not [System.IO.Path]::IsPathRooted($expectedPath)) {
            $expectedPath = [System.IO.Path]::GetFullPath((Join-Path $PWD $expectedPath))
        }

        $artifact = New-EvalRunnerOutputArtifact -EvalsJsonPath $evalsPath -ExpectedJsonPath $expectedPath
        $artifact | ConvertTo-Json -Depth 10
    }
    else {
        Write-Error "Direct invocation requires -EvalsJsonPath and -ExpectedJsonPath."
    }
}
