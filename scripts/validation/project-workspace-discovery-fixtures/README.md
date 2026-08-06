# Project workspace discovery fixtures

These fixtures exercise the dormant C3.3 Slice B surface through a temporary
project copy. The verifier owns the temporary files so the checked-in fixture
remains a small canonical Markdown source set.

The matrix covers deterministic Catalog build/reuse, missing/empty/corrupt and
stale cache recovery, deletion and rename, evidence-backed Glossary expansion,
fail-closed Glossary inputs, Git anchor degradation, Work revision hashing, and
strictly read-only `check` behavior. The same PowerShell 7.6 verifier is used by
the Windows, Ubuntu, and macOS `workspace-assets` hosted jobs.
