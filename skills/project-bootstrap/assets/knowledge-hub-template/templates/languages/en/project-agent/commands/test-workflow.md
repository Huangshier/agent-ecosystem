# Test Workflow

Project memory language: English.

## Purpose

Record the project's own test entry points, framework, common commands, and
verification methods. When a spec's acceptance criteria require test evidence,
use this card to guide the agent to find and run the project's existing test
entry points.

## When To Use

- The agent needs to run the project's test suite to collect test evidence.
- A spec or task list acceptance field requires test evidence.
- The agent needs to understand the project's test framework, commands, or
  environment dependencies.

## Prerequisites

- The project has a test framework installed and configured. Do not invent
  a test framework for the project.
- The project's test commands are documented in `package.json`, `Makefile`,
  CI config, or project documentation.

## Usage

### 1. Record the project test entry points

Record in this file or in the project's
`.agents/context/tech/testing-conventions.md`:

| Field | Description |
|-------|-------------|
| Framework | The project's test framework (e.g., pytest, Jest, go test, cargo test) |
| Run all tests | Command to run the full test suite |
| Run a single test | Command to run a single test file or case |
| Coverage | How to get a coverage report (if available) |
| Environment | Environment variables, services, or fixtures required for testing |
| CI entry | Workflow or job name that runs tests in CI |

### 2. Run tests

Use the project's documented commands. Examples:

```bash
# Example: Python / pytest
pytest --tb=short

# Example: Node / npm
npm test

# Example: Go
go test ./...

# Example: Rust
cargo test
```

Replace with the commands the project actually uses.

### 3. Record test evidence

Record test results in the spec's Acceptance / Evidence section:

- What command was run
- Pass/fail status
- Failed test cases (if any)
- Coverage summary (if available)

## Expected Evidence

- Test commands produce a pass or fail exit code.
- On failure, show the actual error output; do not just state "tests failed".
- Coverage data (if available) comes from tool output; do not fabricate it.

## Safety Notes

- Test commands should run in a local or CI environment; do not run test
  suites against production.
- The project's test framework and commands are decided by the project itself;
  this card does not mandate any specific framework.
