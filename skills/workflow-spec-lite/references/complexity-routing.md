# Complexity Routing

Use this routing guide when deciding whether work is `quick`, `standard`, or `deep`.

## Quick
Typical signals:
- one file or one isolated edit area
- no meaningful design branch
- one obvious validation command or check

Examples:
- fix a typo in a parser error
- adjust one config default
- patch one guard condition in one function

## Standard
Typical signals:
- multiple files are likely
- acceptance needs to be written down
- constraints or assumptions may be forgotten across sessions
- research is needed, but the work is still bounded

Examples:
- add a small feature across a module boundary
- adjust a protocol handler with compatibility constraints
- investigate and fix a recurring build or runtime issue with repo-specific behavior

## Deep
Typical signals:
- staged execution or phased delivery
- multiple modules or artifacts
- research, design, and implementation are all involved
- handoff or review needs an explicit checklist

Examples:
- implement a subsystem change with migration steps
- reverse engineer a feature, document findings, then build tooling around it
- refactor a workflow that touches code, docs, and validation strategy
