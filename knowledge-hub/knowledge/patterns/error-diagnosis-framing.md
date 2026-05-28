# Error Diagnosis Framing

Maturity: draft
Scope: cross-project
Source: manual
Last reviewed: 2026-05-29

## Summary

Present errors to users with structured context that enables actionable
diagnosis: state what failed, what was expected, what changed, and what to try
next. Avoid raw log dumps, unexplained stack traces, and vague summaries.

## Use When

- An agent encounters an error during implementation, build, test, or
  deployment and needs to communicate it to the user.
- The error message from a tool or build system is ambiguous or overly verbose.
- The user needs to decide whether to fix, retry, skip, or escalate.
- Multiple errors occur and need prioritization.

## Do Not Use When

- The error is trivially self-explanatory (e.g., file not found with a clear
  path).
- The agent can fix the error autonomously without user input.
- The error is from a known, documented failure mode with a standard fix.

## Steps

1. **Capture the error**: record the exact error text, exit code, and the
   command or action that produced it.
2. **Identify the surface**: name the file, module, tool, or system that
   generated the error.
3. **State the expected behavior**: what should have happened if the error did
   not occur.
4. **Check for known patterns**: match the error against project-local
   experience entries, knowledge hub patterns, or tool documentation before
   reporting.
5. **Frame the diagnosis**: present the error in this structure:
   - **What failed**: one-line summary of the failing action.
   - **Error**: the key error message or code (trimmed to the actionable part).
   - **Context**: what was being done when the error occurred.
   - **Likely cause**: if identifiable, state the most probable root cause.
   - **Next steps**: what the user can try (fix, retry, skip, escalate).
6. **Prioritize multiple errors**: if several errors occurred, group by severity
   (blockers first) and identify whether they share a common root cause.

## Validation

- The error report names the failing surface, the error, and at least one
  actionable next step.
- The user can understand the error without reading the full log.
- Known errors link to the relevant experience entry or documentation.
- The agent does not fabricate error messages, stack traces, or tool output.
