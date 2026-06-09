param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$helperPath = Join-Path $RepoRoot ".github/scripts/pr-identity-guard.js"
if (-not (Test-Path -LiteralPath $helperPath)) {
    throw "PR identity guard helper not found: $helperPath"
}

$testScript = @'
const assert = require("assert");
const guard = require(process.argv[2]);

function signature(name, email) {
  return { name, email };
}

function commit(sha, author, committer) {
  return {
    sha,
    commit: {
      author,
      committer,
    },
  };
}

function pr(overrides = {}) {
  return {
    number: 1,
    user: { login: "Huangshier" },
    labels: [],
    head: { ref: "human/topic" },
    body: "",
    ...overrides,
  };
}

const bot = signature("agent-ecosystem-bot[bot]", "agent-ecosystem-bot[bot]@users.noreply.github.com");
const human = signature("Huangshier", "1012928902@qq.com");
const local = signature("Local User", "local@example.invalid");

const humanOnly = guard.evaluatePullRequestIdentity(pr(), [commit("a1", human, human)]);
assert.strictEqual(humanOnly.ok, true);
assert.strictEqual(humanOnly.action, "skipped");

const botAuthored = guard.evaluatePullRequestIdentity(
  pr({ user: { login: "agent-ecosystem-bot[bot]" } }),
  [commit("b1", bot, bot)]
);
assert.strictEqual(botAuthored.ok, true);
assert.strictEqual(botAuthored.action, "passed");

const sourceAgentMismatch = guard.evaluatePullRequestIdentity(
  pr({ labels: [{ name: "source:agent" }] }),
  [commit("c1", human, human)]
);
assert.strictEqual(sourceAgentMismatch.ok, false);
assert(sourceAgentMismatch.violations.some((item) => item.includes("author is Huangshier")));
assert(sourceAgentMismatch.violations.some((item) => item.includes("committer is Huangshier")));

const multiCommitMismatch = guard.evaluatePullRequestIdentity(
  pr({ head: { ref: "codex/issue-145-pr-identity-guard" } }),
  [commit("d1", bot, bot), commit("d2", bot, local)]
);
assert.strictEqual(multiCommitMismatch.ok, false);
assert.strictEqual(multiCommitMismatch.violations.length, 1);
assert(multiCommitMismatch.violations[0].includes("committer is Local User"));

const bodySignalMismatch = guard.evaluatePullRequestIdentity(
  pr({ body: "Prepared by an agent-assisted flow." }),
  [commit("e1", human, human)]
);
assert.strictEqual(bodySignalMismatch.ok, false);

const boundaryException = guard.evaluatePullRequestIdentity(
  pr({
    labels: [{ name: "source:agent" }],
    body: "## Actor Boundary\n\nMaintainer-authored workflow permission repair after bot push was blocked.",
  }),
  [commit("f1", human, human)]
);
assert.strictEqual(boundaryException.ok, true);
assert.strictEqual(boundaryException.action, "actor-boundary-exception");

const emptyBoundary = guard.evaluatePullRequestIdentity(
  pr({ labels: [{ name: "source:agent" }], body: "## Actor Boundary\n\nNone." }),
  [commit("g1", human, human)]
);
assert.strictEqual(emptyBoundary.ok, false);

assert.strictEqual(guard.isAcceptedBotSignature(bot), true);
assert.strictEqual(guard.isAcceptedBotSignature(human), false);

console.log(JSON.stringify({ tests: 8, helper: process.argv[2], status: "PASS" }));
'@

$tempScript = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".js")
try {
    [System.IO.File]::WriteAllText($tempScript, $testScript, [System.Text.UTF8Encoding]::new($false))
    $output = & node $tempScript $helperPath
    if ($LASTEXITCODE -ne 0) {
        throw "Node PR identity guard tests failed with exit code $LASTEXITCODE."
    }
}
finally {
    Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
}

if ($Json.IsPresent) {
    $output
}
else {
    $result = $output | ConvertFrom-Json
    Write-Output ("PR identity guard tests passed ({0} checks)." -f $result.tests)
}
