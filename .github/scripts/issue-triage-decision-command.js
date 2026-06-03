"use strict";

const DECISION_LABELS = new Map([
  ["accepted", "triage:accepted"],
  ["rejected", "triage:rejected"],
  ["deferred", "triage:deferred"],
  ["needs-human", "triage:needs-human"],
]);

const SUPPORTED_COMMANDS = [
  "/decision accepted",
  "/decision rejected",
  "/decision deferred",
  "/decision needs-human",
  "/accept",
];

const TRIAGE_LABELS = [...DECISION_LABELS.values()];
const TRUSTED_BOTS = new Set(["agent-ecosystem-bot[bot]"]);
const TRUSTED_REPOSITORY_ROLES = new Set(["admin", "maintain", "write"]);

function normalizeCommentBody(body) {
  return String(body || "").trim();
}

function parseDecisionCommand(body) {
  const command = normalizeCommentBody(body);
  const lower = command.toLowerCase();

  if (lower === "/accept") {
    return { matched: true, valid: true, decision: "accepted", command };
  }

  const match = lower.match(/^\/decision\s+(accepted|rejected|deferred|needs-human)$/);
  if (match) {
    return { matched: true, valid: true, decision: match[1], command };
  }

  if (lower.startsWith("/decision") || lower === "/reject" || lower === "/defer" || lower === "/needs-human") {
    return { matched: true, valid: false, reason: "Unsupported or invalid decision command.", command };
  }

  return { matched: false, valid: false, reason: "No decision command found.", command };
}

function issueHasLabel(issue, labelName) {
  const labels = Array.isArray(issue && issue.labels) ? issue.labels : [];
  return labels.some((label) => String(label.name || label).toLowerCase() === labelName.toLowerCase());
}

function shouldProcessIssue(issue) {
  if (!issue) {
    return { ok: false, reason: "Missing issue payload." };
  }
  if (issue.pull_request) {
    return { ok: false, reason: "Pull request comments are ignored." };
  }
  if (String(issue.state || "").toLowerCase() !== "open") {
    return { ok: false, reason: "Closed issues are ignored." };
  }
  if (!issueHasLabel(issue, "source:agent")) {
    return { ok: false, reason: "Issue is not labeled source:agent." };
  }
  return { ok: true };
}

function resolveActorAuthorityFromPermission(actor) {
  const login = String((actor && actor.login) || "");
  const type = String((actor && actor.type) || "");
  const permission = String((actor && actor.permission) || "").toLowerCase();
  const role = String((actor && actor.role) || "").toLowerCase();

  if (TRUSTED_BOTS.has(login)) {
    return { trusted: true, reason: `trusted automation ${login}` };
  }
  if (!login) {
    return { trusted: false, reason: "missing event sender" };
  }
  if (type === "Bot") {
    return { trusted: false, reason: `untrusted bot ${login}` };
  }
  if (TRUSTED_REPOSITORY_ROLES.has(permission) || TRUSTED_REPOSITORY_ROLES.has(role)) {
    return { trusted: true, reason: `${login} has repository role ${role || permission}` };
  }
  return { trusted: false, reason: `${login} has repository role ${role || permission || "unknown"}` };
}

async function getActorAuthority({ github, context }) {
  const sender = (context.payload && context.payload.sender) || {};
  const login = sender.login || "";
  const type = sender.type || "";

  if (TRUSTED_BOTS.has(login) || !login || type === "Bot") {
    return resolveActorAuthorityFromPermission({ login, type });
  }

  try {
    const response = await github.rest.repos.getCollaboratorPermissionLevel({
      owner: context.repo.owner,
      repo: context.repo.repo,
      username: login,
    });
    return resolveActorAuthorityFromPermission({
      login,
      type,
      permission: response.data && response.data.permission,
      role: response.data && response.data.role_name,
    });
  } catch (error) {
    if (error.status === 404) {
      return { trusted: false, reason: `${login} is not a repository collaborator` };
    }
    throw error;
  }
}

function getHumanTriageSection(body) {
  const text = String(body || "");
  const match = text.match(/(^##\s*Human Triage Decision\s*)([\s\S]*?)(?=^##\s+|\s*$)/im);
  if (!match) {
    return null;
  }
  return {
    start: match.index,
    end: match.index + match[0].length,
    heading: match[1],
    section: match[2],
    full: match[0],
  };
}

function updateDecisionInBody({ body, decision, actorLogin, command, now }) {
  if (!DECISION_LABELS.has(decision)) {
    return { changed: false, reason: `Unsupported decision: ${decision}` };
  }

  const sectionInfo = getHumanTriageSection(body);
  if (!sectionInfo) {
    return { changed: false, reason: "Human Triage Decision section was not found." };
  }

  const decisionMatches = [...sectionInfo.section.matchAll(/^\s*Decision:\s*([^\r\n]*)\s*$/gim)];
  if (decisionMatches.length !== 1) {
    return { changed: false, reason: "Expected exactly one Decision: field in Human Triage Decision section." };
  }

  const timestamp = now || new Date().toISOString();
  const safeActor = actorLogin ? `@${actorLogin}` : "an authorized actor";
  const note = `Decision notes: Set to ${decision} by ${safeActor} via \`${command}\` on ${timestamp}.`;

  let section = sectionInfo.section.replace(/^\s*Decision:\s*[^\r\n]*\s*$/im, `Decision: ${decision}`);
  if (/^\s*Decision notes:.*$/im.test(section)) {
    section = section.replace(/^\s*Decision notes:.*$/im, note);
  } else {
    section = `${section.trimEnd()}\n\n${note}\n`;
  }

  const updatedSection = `${sectionInfo.heading}${section}`;
  const updatedBody = `${body.slice(0, sectionInfo.start)}${updatedSection}${body.slice(sectionInfo.end)}`;
  return { changed: updatedBody !== body, body: updatedBody, decision, label: DECISION_LABELS.get(decision) };
}

async function convergeTriageLabels({ github, context, issue, decision }) {
  const desired = DECISION_LABELS.get(decision);
  if (!desired) {
    return { changed: false, reason: `Unsupported decision: ${decision}` };
  }

  const currentLabels = (issue.labels || []).map((label) => String(label.name || label));
  const removed = [];
  for (const label of [...TRIAGE_LABELS, "review:needs-human"]) {
    if (label === desired || !currentLabels.includes(label)) {
      continue;
    }
    try {
      await github.rest.issues.removeLabel({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number: issue.number,
        name: label,
      });
      removed.push(label);
    } catch (error) {
      if (error.status !== 404) {
        throw error;
      }
    }
  }

  let added = false;
  if (!currentLabels.includes(desired)) {
    await github.rest.issues.addLabels({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: issue.number,
      labels: [desired],
    });
    added = true;
  }

  return { changed: removed.length > 0 || added, desired, removed, added };
}

async function run({ github, context, core }) {
  const issue = context.payload.issue;
  const comment = context.payload.comment || {};

  const issueScope = shouldProcessIssue(issue);
  if (!issueScope.ok) {
    core.info(issueScope.reason);
    return { action: "ignored", reason: issueScope.reason };
  }

  const parsed = parseDecisionCommand(comment.body || "");
  if (!parsed.matched) {
    core.info(parsed.reason);
    return { action: "ignored", reason: parsed.reason };
  }
  if (!parsed.valid) {
    core.warning(parsed.reason);
    return { action: "ignored", reason: parsed.reason };
  }

  const authority = await getActorAuthority({ github, context });
  if (!authority.trusted) {
    core.warning(`Actor is not trusted for decision command (${authority.reason}); leaving issue unchanged.`);
    return { action: "ignored", reason: authority.reason };
  }
  core.info(`Actor authorized for decision command: ${authority.reason}.`);

  const updated = updateDecisionInBody({
    body: issue.body || "",
    decision: parsed.decision,
    actorLogin: (context.payload.sender && context.payload.sender.login) || "",
    command: parsed.command,
  });
  if (!updated.changed) {
    core.warning(updated.reason);
    return { action: "ignored", reason: updated.reason };
  }

  await github.rest.issues.update({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: issue.number,
    body: updated.body,
  });
  core.info(`Updated issue body decision to ${parsed.decision}.`);

  const labelResult = await convergeTriageLabels({ github, context, issue, decision: parsed.decision });
  core.info(`Converged labels to ${labelResult.desired}.`);

  return { action: "updated", decision: parsed.decision, label: labelResult.desired };
}

module.exports = {
  DECISION_LABELS,
  SUPPORTED_COMMANDS,
  TRIAGE_LABELS,
  parseDecisionCommand,
  shouldProcessIssue,
  resolveActorAuthorityFromPermission,
  updateDecisionInBody,
  convergeTriageLabels,
  run,
};
