# Commands Folder

Project memory language: English.

Use this folder for reusable high-frequency project workflows. It complements
`.agents/AGENTS.md`: the agent guide says when to look here, and this folder
records exact repeatable command flows.

Prefer documented commands from project docs, package scripts, Makefiles, task
runners, CI workflows, or existing files in this folder. Do not invent commands
when the project has not documented a way to run that workflow; inspect the
project surface first.

## Current Command Cards

- `test-workflow.md`: record project-specific test framework, commands, CI
  entry points, and evidence expectations. Use existing project commands; do
  not select a new test framework from this template alone.

Add one short Markdown file per reusable workflow when the details no longer
fit this README. Useful fields:
- Purpose and when to use it
- Prerequisites
- Commands
- Expected pass/fail evidence
- Safety notes for external side effects

Examples:
- setup/install workflow
- format/lint workflow
- test workflow
- build workflow
- release validation workflow
- review checklist
