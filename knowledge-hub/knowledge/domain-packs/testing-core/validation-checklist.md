# Testing Validation Checklist

Maturity: draft
Scope: cross-project
Source: issue #210
Last reviewed: 2026-07-06

## Summary

Generic public-safe boundaries for recording testing and verification evidence.
Use this checklist to keep project-owned test commands separate from reusable
testing guidance.

## Checklist

- Identify the project's own test workflow before recommending commands.
- Record which command, fixture, manual check, or CI signal provided evidence.
- State skipped checks and the reason before claiming implementation complete.
- Keep coverage targets and framework choices owned by the target project.
- Treat LLM review as advisory, not as deterministic pass/fail evidence.
- Keep non-public harnesses, local paths, and project-only logs out of public
  knowledge entries.

## Boundary

This entry is public knowledge. It deliberately avoids test execution,
framework mandates, coverage thresholds, downstream release gates, and
environment-specific assumptions.
