[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}
else {
    $RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
}

$helperPath = Join-Path $RepoRoot ".github/scripts/issue-triage-decision-command.js"
if (-not (Test-Path -LiteralPath $helperPath)) {
    throw "Decision command helper was not found: $helperPath"
}

$node = Get-Command node -ErrorAction SilentlyContinue
if ($null -eq $node) {
    throw "Node.js is required to run issue triage decision command tests."
}

$testScript = @'
const assert = require("assert");
const helper = require(process.argv[2]);

function makeIssue(overrides = {}) {
  return Object.assign({
    number: 123,
    state: "open",
    labels: [{ name: "source:agent" }, { name: "triage:needs-human" }],
    body: [
      "## Background",
      "",
      "Body text.",
      "",
      "## Human Triage Decision",
      "",
      "Decision: needs-human",
      "",
      "Allowed values: accepted, rejected, deferred, needs-human",
      "",
      "Decision notes:",
      "",
    ].join("\n"),
  }, overrides);
}

function makeCore() {
  return {
    infos: [],
    warnings: [],
    failures: [],
    info(message) { this.infos.push(String(message)); },
    warning(message) { this.warnings.push(String(message)); },
    setFailed(message) {
      this.failures.push(String(message));
      throw new Error(message);
    },
  };
}

function countOccurrences(text, pattern) {
  return (String(text).match(pattern) || []).length;
}

async function runScenario({ commentBody, issue, sender, permission }) {
  const calls = [];
  const github = {
    rest: {
      repos: {
        async getCollaboratorPermissionLevel() {
          if (permission === "404") {
            const error = new Error("not found");
            error.status = 404;
            throw error;
          }
          return { data: { permission, role_name: permission } };
        },
      },
      issues: {
        async update(args) {
          calls.push(["update", args]);
        },
        async removeLabel(args) {
          calls.push(["removeLabel", args]);
        },
        async addLabels(args) {
          calls.push(["addLabels", args]);
        },
      },
    },
  };
  const context = {
    repo: { owner: "Huangshier", repo: "agent-ecosystem" },
    payload: {
      issue,
      comment: { body: commentBody },
      sender: sender || { login: "maintainer", type: "User" },
    },
  };
  const core = makeCore();
  const result = await helper.run({ github, context, core });
  return { result, calls, core };
}

(async () => {
  assert.deepStrictEqual(helper.parseDecisionCommand("/decision accepted").decision, "accepted");
  assert.deepStrictEqual(helper.parseDecisionCommand("/decision rejected").decision, "rejected");
  assert.deepStrictEqual(helper.parseDecisionCommand("/decision deferred").decision, "deferred");
  assert.deepStrictEqual(helper.parseDecisionCommand("/decision needs-human").decision, "needs-human");
  assert.deepStrictEqual(helper.parseDecisionCommand("/accept").decision, "accepted");
  assert.strictEqual(helper.parseDecisionCommand("/decision maybe").valid, false);
  assert.strictEqual(helper.parseDecisionCommand("please accept this").matched, false);

  assert.strictEqual(helper.resolveActorAuthorityFromPermission({
    login: "maintainer",
    type: "User",
    permission: "write",
  }).trusted, true);
  assert.strictEqual(helper.resolveActorAuthorityFromPermission({
    login: "triager",
    type: "User",
    permission: "triage",
  }).trusted, false);
  assert.strictEqual(helper.resolveActorAuthorityFromPermission({
    login: "agent-ecosystem-bot[bot]",
    type: "Bot",
  }).trusted, true);

  const updated = helper.updateDecisionInBody({
    body: makeIssue().body,
    decision: "accepted",
    actorLogin: "maintainer",
    command: "/decision accepted",
    now: "2026-06-03T00:00:00.000Z",
  });
  assert.strictEqual(updated.changed, true);
  assert(updated.body.includes("Decision: accepted"));
  assert(updated.body.includes("Decision notes: Set to accepted by `maintainer` via `/decision accepted` on 2026-06-03T00:00:00.000Z."));
  assert(!updated.body.includes("@maintainer"));
  assert.strictEqual(countOccurrences(updated.body, /^Decision notes:/gim), 1);
  assert(updated.body.indexOf("Decision: accepted") < updated.body.indexOf("Allowed values: accepted, rejected, deferred, needs-human"));
  assert(updated.body.indexOf("Allowed values: accepted, rejected, deferred, needs-human") < updated.body.indexOf("Decision notes: Set to accepted"));
  // Missing section: now appends normalized section instead of failing
  const missingSection = helper.updateDecisionInBody({
    body: "## Background\n\nNo triage section.\n",
    decision: "accepted",
    actorLogin: "maintainer",
    command: "/decision accepted",
    now: "2026-06-03T00:00:00.000Z",
  });
  assert.strictEqual(missingSection.changed, true);
  assert.strictEqual(missingSection.appended, true);
  assert(missingSection.body.includes("## Human Triage Decision"));
  assert(missingSection.body.includes("Decision: accepted"));
  assert(missingSection.body.includes("Decision notes: Set to accepted by `maintainer`"));
  assert(missingSection.body.includes("Allowed values: accepted, rejected, deferred, needs-human"));
  // Original content is preserved
  assert(missingSection.body.includes("## Background"));

  // Missing section with empty body
  const emptyBody = helper.updateDecisionInBody({
    body: "",
    decision: "rejected",
    actorLogin: "agent-ecosystem-bot[bot]",
    command: "/decision rejected",
    now: "2026-06-03T00:00:00.000Z",
  });
  assert.strictEqual(emptyBody.changed, true);
  assert.strictEqual(emptyBody.appended, true);
  assert(emptyBody.body.includes("Decision: rejected"));
  assert.strictEqual(emptyBody.label, "triage:rejected");

  // Missing section: idempotent on re-run (second run finds section, updates in place)
  const secondRun = helper.updateDecisionInBody({
    body: missingSection.body,
    decision: "deferred",
    actorLogin: "admin",
    command: "/decision deferred",
    now: "2026-06-03T01:00:00.000Z",
  });
  assert.strictEqual(secondRun.changed, true);
  assert.strictEqual(secondRun.appended, undefined);
  assert(secondRun.body.includes("Decision: deferred"));
  assert(!secondRun.body.includes("Decision: accepted"));
  // Only one Decision notes line in the section
  assert.strictEqual(countOccurrences(secondRun.body, /^Decision notes:/gim), 1);

  const polluted = helper.updateDecisionInBody({
    body: [
      "## Background",
      "",
      "Body text.",
      "",
      "## Human Triage Decision",
      "",
      "Decision: accepted",
      "",
      "Decision notes: Set to accepted by @Huangshier via `/decision accepted` on 2026-06-03T10:26:32.379Z.",
      "",
      "",
      "Allowed values: accepted, rejected, deferred, needs-human",
      "",
      "Decision notes:",
      "",
    ].join("\n"),
    decision: "accepted",
    actorLogin: "Huangshier",
    command: "/decision accepted",
    now: "2026-06-03T10:30:00.000Z",
  });
  assert.strictEqual(polluted.changed, true);
  assert(!polluted.body.includes("@Huangshier"));
  assert.strictEqual(countOccurrences(polluted.body, /^Decision notes:/gim), 1);
  assert(polluted.body.indexOf("Decision: accepted") < polluted.body.indexOf("Allowed values: accepted, rejected, deferred, needs-human"));
  assert(polluted.body.indexOf("Allowed values: accepted, rejected, deferred, needs-human") < polluted.body.indexOf("Decision notes: Set to accepted"));

  const authorized = await runScenario({
    commentBody: "/decision accepted",
    issue: makeIssue(),
    permission: "write",
  });
  assert.strictEqual(authorized.result.action, "updated");
  assert.strictEqual(authorized.calls.filter((call) => call[0] === "update").length, 1);
  assert(!authorized.calls[0][1].body.includes("@maintainer"));
  assert.strictEqual(countOccurrences(authorized.calls[0][1].body, /^Decision notes:/gim), 1);
  assert.strictEqual(authorized.calls.filter((call) => call[0] === "removeLabel" && call[1].name === "triage:needs-human").length, 1);
  assert.strictEqual(authorized.calls.filter((call) => call[0] === "addLabels" && call[1].labels[0] === "triage:accepted").length, 1);

  const unauthorized = await runScenario({
    commentBody: "/decision accepted",
    issue: makeIssue(),
    permission: "triage",
  });
  assert.strictEqual(unauthorized.result.action, "ignored");
  assert.strictEqual(unauthorized.calls.length, 0);

  const invalid = await runScenario({
    commentBody: "/decision maybe",
    issue: makeIssue(),
    permission: "write",
  });
  assert.strictEqual(invalid.result.action, "ignored");
  assert.strictEqual(invalid.calls.length, 0);

  const unrelated = await runScenario({
    commentBody: "LGTM",
    issue: makeIssue(),
    permission: "write",
  });
  assert.strictEqual(unrelated.result.action, "ignored");
  assert.strictEqual(unrelated.calls.length, 0);

  const prComment = await runScenario({
    commentBody: "/decision accepted",
    issue: makeIssue({ pull_request: { url: "https://example.invalid/pr" } }),
    permission: "write",
  });
  assert.strictEqual(prComment.result.action, "ignored");
  assert.strictEqual(prComment.calls.length, 0);

  const nonAgent = await runScenario({
    commentBody: "/decision accepted",
    issue: makeIssue({ labels: [{ name: "triage:needs-human" }] }),
    permission: "write",
  });
  assert.strictEqual(nonAgent.result.action, "ignored");
  assert.strictEqual(nonAgent.calls.length, 0);

  // Missing section scenario: /decision accepted on source:agent issue without HTD section
  const missingSectionScenario = await runScenario({
    commentBody: "/decision accepted",
    issue: {
      number: 200,
      state: "open",
      labels: [{ name: "source:agent" }, { name: "triage:needs-human" }],
      body: "## Background\n\nAPI-created issue without triage section.\n",
    },
    permission: "write",
  });
  assert.strictEqual(missingSectionScenario.result.action, "updated");
  assert.strictEqual(missingSectionScenario.result.decision, "accepted");
  assert.strictEqual(missingSectionScenario.calls.filter((call) => call[0] === "update").length, 1);
  assert(missingSectionScenario.calls[0][1].body.includes("## Human Triage Decision"));
  assert(missingSectionScenario.calls[0][1].body.includes("Decision: accepted"));
  assert.strictEqual(missingSectionScenario.calls.filter((call) => call[0] === "removeLabel" && call[1].name === "triage:needs-human").length, 1);
  assert.strictEqual(missingSectionScenario.calls.filter((call) => call[0] === "addLabels" && call[1].labels[0] === "triage:accepted").length, 1);

  // Missing section scenario: bot command on issue without HTD section
  const botMissingSection = await runScenario({
    commentBody: "/decision accepted",
    issue: {
      number: 201,
      state: "open",
      labels: [{ name: "source:agent" }],
      body: "Bot-created issue.\n",
    },
    sender: { login: "agent-ecosystem-bot[bot]", type: "Bot" },
    permission: "write",
  });
  assert.strictEqual(botMissingSection.result.action, "updated");
  assert.strictEqual(botMissingSection.calls.filter((call) => call[0] === "update").length, 1);

  console.log(JSON.stringify({
    tests: 16,
    helper: process.argv[2],
    status: "PASS",
  }));
})().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
'@

$tempScript = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".js")
try {
    [System.IO.File]::WriteAllText($tempScript, $testScript, [System.Text.UTF8Encoding]::new($false))
    $output = & node $tempScript $helperPath
    if ($LASTEXITCODE -ne 0) {
        throw "Node decision command tests failed with exit code $LASTEXITCODE."
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
    Write-Output ("Issue triage decision command tests passed ({0} checks)." -f $result.tests)
}
