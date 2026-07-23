"use strict";

const fs = require("fs");

function requireExactSingle(items, label) {
  if (items.length !== 1) {
    throw new Error(`${label} must resolve to exactly one item; found ${items.length}.`);
  }
  return items[0];
}

async function waitForRun({ github, owner, repo, runId, timeoutMs = 600000 }) {
  const deadline = Date.now() + timeoutMs;
  while (true) {
    const response = await github.rest.actions.getWorkflowRun({ owner, repo, run_id: runId });
    if (response.data.status === "completed") return response.data;
    if (Date.now() >= deadline) throw new Error(`Timed out waiting for exact workflow run ${runId}.`);
    await new Promise((resolve) => setTimeout(resolve, 5000));
  }
}

async function waitForExactGuardRun({
  github, owner, repo, workflowPath, expectedTitle, headSha, prNumber, runAttempt, timeoutMs = 600000,
}) {
  const deadline = Date.now() + timeoutMs;
  while (true) {
    const listed = await github.rest.actions.listWorkflowRuns({
      owner, repo, workflow_id: workflowPath, event: "pull_request", head_sha: headSha, per_page: 100,
    });
    const matches = listed.data.workflow_runs.filter(
      (run) =>
        run.event === "pull_request" &&
        run.head_sha === headSha &&
        run.display_title === expectedTitle &&
        Number(run.run_attempt) === Number(runAttempt) &&
        Array.isArray(run.pull_requests) &&
        run.pull_requests.some((pr) => Number(pr.number) === Number(prNumber)),
    );
    if (matches.length > 1) {
      throw new Error(`Guard workflow ${workflowPath} must resolve to one run; found ${matches.length}.`);
    }
    if (matches.length === 1) return matches[0];
    if (Date.now() >= deadline) {
      throw new Error(`Timed out resolving exact guard workflow ${workflowPath}.`);
    }
    await new Promise((resolve) => setTimeout(resolve, 5000));
  }
}

async function resolveGuard({ github, owner, repo, workflowPath, expectedTitle, headSha, prNumber, runAttempt }) {
  const selected = await waitForExactGuardRun({
    github, owner, repo, workflowPath, expectedTitle, headSha, prNumber, runAttempt,
  });
  const completed = await waitForRun({ github, owner, repo, runId: selected.id });
  if (completed.conclusion !== "success") throw new Error(`Guard run ${completed.id} concluded ${completed.conclusion}.`);
  const jobs = await github.rest.actions.listJobsForWorkflowRun({
    owner, repo, run_id: completed.id, filter: "latest", per_page: 100,
  });
  const job = requireExactSingle(jobs.data.jobs, `Guard workflow ${workflowPath} jobs`);
  if (job.status !== "completed" || job.conclusion !== "success") throw new Error(`Guard job ${job.id} is not a completed success.`);
  return {
    workflow_id: String(completed.workflow_id), workflow_path: workflowPath,
    run_id: String(completed.id), run_attempt: String(completed.run_attempt),
    job_id: String(job.id), check_name: job.name, conclusion: job.conclusion, html_url: job.html_url,
    head_sha: completed.head_sha, pr_number: Number(prNumber), event: completed.event, display_title: completed.display_title,
  };
}

async function resolveFinalGate({ github, owner, repo, runId, runAttempt, headSha, prNumber }) {
  const current = await github.rest.actions.getWorkflowRun({ owner, repo, run_id: runId });
  if (
    current.data.event !== "pull_request" ||
    current.data.head_sha !== headSha ||
    Number(current.data.run_attempt) !== Number(runAttempt) ||
    !current.data.pull_requests.some((pr) => Number(pr.number) === Number(prNumber))
  ) throw new Error("Current Release validation run identity does not match the PR/head.");
  const jobs = await github.rest.actions.listJobsForWorkflowRun({
    owner, repo, run_id: runId, filter: "latest", per_page: 100,
  });
  const gate = requireExactSingle(jobs.data.jobs.filter((job) => job.name === "validation gate"), "Final validation gate job");
  if (gate.status !== "completed" || gate.conclusion !== "success") throw new Error(`Final gate ${gate.id} is not a completed success.`);
  return {
    workflow_id: String(current.data.workflow_id), workflow_path: ".github/workflows/release-validation.yml",
    run_id: String(current.data.id), run_attempt: String(current.data.run_attempt),
    job_id: String(gate.id), check_name: gate.name, conclusion: gate.conclusion, html_url: gate.html_url,
    head_sha: current.data.head_sha, pr_number: Number(prNumber), event: current.data.event, display_title: current.data.display_title,
  };
}

async function run({ github, context, core, outputPath }) {
  const pr = context.payload.pull_request;
  if (!pr) throw new Error("Validation check binding requires a pull_request event.");
  const owner = context.repo.owner;
  const repo = context.repo.repo;
  const runAttempt = process.env.GITHUB_RUN_ATTEMPT;
  const headSha = pr.head.sha.toLowerCase();
  const prNumber = Number(pr.number);
  const action = context.payload.action;
  const baseGuard = await resolveGuard({
    github, owner, repo, workflowPath: ".github/workflows/pr-base-guard.yml",
    expectedTitle: `PR base guard #${prNumber} ${action} ${headSha}`, headSha, prNumber, runAttempt,
  });
  const identityGuard = await resolveGuard({
    github, owner, repo, workflowPath: ".github/workflows/pr-identity-guard.yml",
    expectedTitle: `PR identity guard #${prNumber} ${action} ${headSha}`, headSha, prNumber, runAttempt,
  });
  const finalGate = await resolveFinalGate({
    github, owner, repo, runId: Number(process.env.GITHUB_RUN_ID), runAttempt, headSha, prNumber,
  });
  const binding = { schema_version: 1, base_guard: baseGuard, identity_guard: identityGuard, final_gate: finalGate };
  fs.writeFileSync(outputPath, `${JSON.stringify(binding, null, 2)}\n`, "utf8");
  core.info(`Resolved exact bindings: base=${baseGuard.run_id}/${baseGuard.job_id}, identity=${identityGuard.run_id}/${identityGuard.job_id}, gate=${finalGate.run_id}/${finalGate.job_id}.`);
  return binding;
}

module.exports = { requireExactSingle, waitForExactGuardRun, resolveGuard, resolveFinalGate, run };
