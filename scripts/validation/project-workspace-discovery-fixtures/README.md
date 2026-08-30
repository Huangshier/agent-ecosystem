# Project workspace discovery fixtures

These fixtures exercise the C3.3 Slice B surface through a temporary
project copy. The verifier owns the temporary files so the checked-in fixture
remains a small canonical Markdown source set.

The matrix covers the minimal C3.3 layout, deterministic Catalog build/reuse,
parseable but contract-invalid Catalog shapes, warning-only missing/stale cache
state, deletion and rename, canonical schema and reference failures, exact
ordinal ordering and Glossary/candidate deduplication, fail-closed Glossary
inputs, complete Git anchor presence/reachability degradation, Work revision
hashing, and strictly read-only `check` behavior. It separately proves that
canonical sources are read-only and that `discover` writes only
`.agents/.cache/catalog.json`. The same PowerShell 7.6 verifier is used by the
Windows, Ubuntu, and macOS `workspace-assets` hosted jobs.
