"use strict";

const ACCEPTED_BOT_LOGINS = new Set([
  "agent-ecosystem-bot",
  "agent-ecosystem-bot[bot]",
  "app/agent-ecosystem-bot",
]);

const ACCEPTED_BOT_SIGNATURES = [
  {
    name: "agent-ecosystem-bot[bot]",
    email: "agent-ecosystem-bot[bot]@users.noreply.github.com",
  },
];

const AUTOMATION_BRANCH_PATTERN = /^(codex|agent)\//i;
const AGENT_BODY_PATTERN = /\b(agent[- ]authored|agent[- ]assisted|agent flow|automation identity|source:agent)\b/i;
const ACTOR_BOUNDARY_HEADING_PATTERN = /^##\s*Actor Boundary(?:\s+Exception(?:s)?)?\s*$/im;

// normalizeText: value 为任意输入；返回用于比较的去空白字符串。
function normalizeText(value) {
  return String(value || "").trim();
}

// getLabelNames: pr 为 pull_request 对象；返回 PR 标签名称列表。
function getLabelNames(pr) {
  const labels = Array.isArray(pr && pr.labels) ? pr.labels : [];
  return labels.map((label) => normalizeText(label && (label.name || label))).filter(Boolean);
}

// hasLabel: pr 为 pull_request 对象，labelName 为待查标签；判断标签是否存在。
function hasLabel(pr, labelName) {
  const expected = normalizeText(labelName).toLowerCase();
  return getLabelNames(pr).some((label) => label.toLowerCase() === expected);
}

// getAuthorLogin: pr 为 pull_request 对象；返回兼容 REST / GraphQL 形态的作者 login。
function getAuthorLogin(pr) {
  return normalizeText(
    pr &&
      ((pr.user && pr.user.login) ||
        (pr.author && pr.author.login) ||
        (pr.author && pr.author.name))
  );
}

// getHeadRef: pr 为 pull_request 对象；返回 head branch 名称。
function getHeadRef(pr) {
  return normalizeText(pr && ((pr.head && pr.head.ref) || pr.headRefName));
}

// resolveAgentSignals: pr 为 pull_request 对象；返回使 guard 生效的自动化信号。
function resolveAgentSignals(pr) {
  const signals = [];
  const authorLogin = getAuthorLogin(pr);
  const headRef = getHeadRef(pr);
  const body = normalizeText(pr && pr.body);

  if (ACCEPTED_BOT_LOGINS.has(authorLogin)) {
    signals.push(`PR author is ${authorLogin}`);
  }
  if (hasLabel(pr, "source:agent")) {
    signals.push("PR has source:agent label");
  }
  if (AUTOMATION_BRANCH_PATTERN.test(headRef)) {
    signals.push(`head branch matches automation pattern: ${headRef}`);
  }
  if (AGENT_BODY_PATTERN.test(body)) {
    signals.push("PR body declares an agent or automation flow");
  }

  return signals;
}

// getActorBoundarySection: body 为 PR body；返回显式 Actor Boundary 章节正文。
function getActorBoundarySection(body) {
  const text = normalizeText(body);
  const match = ACTOR_BOUNDARY_HEADING_PATTERN.exec(text);
  if (!match) {
    return "";
  }

  const afterHeading = text.slice(match.index + match[0].length);
  const nextHeading = afterHeading.search(/^##\s+/m);
  const section = nextHeading >= 0 ? afterHeading.slice(0, nextHeading) : afterHeading;
  return normalizeText(section);
}

// hasReviewableActorBoundary: body 为 PR body；判断是否有可审查的显式例外说明。
function hasReviewableActorBoundary(body) {
  const section = getActorBoundarySection(body);
  return section.length > 0 && !/^none\.?$/i.test(section);
}

// isAcceptedBotSignature: signature 为 commit author / committer 元数据；判断是否为允许的 bot 身份。
function isAcceptedBotSignature(signature) {
  const name = normalizeText(signature && signature.name);
  const email = normalizeText(signature && signature.email).toLowerCase();

  return ACCEPTED_BOT_SIGNATURES.some(
    (accepted) => name === accepted.name && email === accepted.email.toLowerCase()
  );
}

// describeSignature: signature 为 commit author / committer 元数据；返回安全的展示文本。
function describeSignature(signature) {
  const name = normalizeText(signature && signature.name) || "<missing name>";
  const email = normalizeText(signature && signature.email) || "<missing email>";
  return `${name} <${email}>`;
}

// getCommitSha: commit 为 GitHub commits API 条目；返回短 SHA。
function getCommitSha(commit) {
  return normalizeText(commit && commit.sha).slice(0, 12) || "<unknown>";
}

// evaluateCommitIdentity: commit 为 GitHub commits API 条目；返回该 commit 的身份违规列表。
function evaluateCommitIdentity(commit) {
  const violations = [];
  const author = commit && commit.commit && commit.commit.author;
  const committer = commit && commit.commit && commit.commit.committer;
  const sha = getCommitSha(commit);

  if (!isAcceptedBotSignature(author)) {
    violations.push(`${sha} author is ${describeSignature(author)}`);
  }
  if (!isAcceptedBotSignature(committer)) {
    violations.push(`${sha} committer is ${describeSignature(committer)}`);
  }

  return violations;
}

// evaluatePullRequestIdentity: pr 为 pull_request 对象，commits 为 PR commit 列表；返回 guard 判定结果。
function evaluatePullRequestIdentity(pr, commits) {
  const signals = resolveAgentSignals(pr);
  if (signals.length === 0) {
    return {
      ok: true,
      action: "skipped",
      message: "PR has no explicit agent-authored signals; commit identity guard skipped.",
      signals,
      violations: [],
    };
  }

  const violations = [];
  for (const commit of Array.isArray(commits) ? commits : []) {
    violations.push(...evaluateCommitIdentity(commit));
  }

  if (violations.length === 0) {
    return {
      ok: true,
      action: "passed",
      message: "Agent-authored PR commits all use the accepted bot author and committer identity.",
      signals,
      violations,
    };
  }

  if (hasReviewableActorBoundary(pr && pr.body)) {
    return {
      ok: true,
      action: "actor-boundary-exception",
      message: "Commit identity mismatch is covered by an explicit Actor Boundary section in the PR body.",
      signals,
      violations,
    };
  }

  return {
    ok: false,
    action: "failed",
    message:
      "Agent-authored PR contains commits whose author or committer is not the accepted bot identity. " +
      "Amend the commits with agent-ecosystem-bot[bot] author and committer metadata, then update the branch through the bot flow; " +
      "or document a reviewable Actor Boundary exception in the PR body.",
    signals,
    violations,
  };
}

// listPullRequestCommits: github/context/pr 为 GitHub API 输入；读取 PR 内所有 commits。
async function listPullRequestCommits({ github, context, pr }) {
  return github.paginate(github.rest.pulls.listCommits, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    pull_number: pr.number,
    per_page: 100,
  });
}

// run: github/context/core 为 actions/github-script 注入对象；执行 hosted PR identity guard。
async function run({ github, context, core }) {
  const pr = context && context.payload && context.payload.pull_request;
  if (!pr) {
    core.info("No pull_request payload found; PR identity guard skipped.");
    return { ok: true, action: "skipped", signals: [], violations: [] };
  }

  const commits = await listPullRequestCommits({ github, context, pr });
  const result = evaluatePullRequestIdentity(pr, commits);

  for (const signal of result.signals) {
    core.info(`Agent signal: ${signal}`);
  }
  for (const violation of result.violations) {
    core.warning(`Commit identity mismatch: ${violation}`);
  }

  if (!result.ok) {
    core.setFailed(result.message);
    return result;
  }

  if (result.action === "actor-boundary-exception") {
    core.warning(result.message);
  } else {
    core.info(result.message);
  }

  return result;
}

module.exports = {
  ACCEPTED_BOT_LOGINS,
  ACCEPTED_BOT_SIGNATURES,
  evaluateCommitIdentity,
  evaluatePullRequestIdentity,
  getActorBoundarySection,
  hasReviewableActorBoundary,
  isAcceptedBotSignature,
  resolveAgentSignals,
  run,
};
