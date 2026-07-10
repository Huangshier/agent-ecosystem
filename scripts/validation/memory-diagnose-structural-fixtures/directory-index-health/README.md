# Directory Index Health

This fixture family validates the opt-in directory index health diagnostics in
`skills/memory-governance/scripts/memory_diagnose.ps1`.

The release check builds an isolated project tree from `expected.json` and
covers:

- nine direct files without `README.md` or `INDEX.md`;
- the default threshold boundary;
- suppression by `README.md` and `INDEX.md`;
- direct-file counting without descendant accumulation;
- symbolic-link or junction traversal exclusion;
- unchanged fixture-tree content before and after diagnosis;
- unchanged finding codes when `-DirectoryIndexRoots` is omitted.

The positive finding contract is `directory_missing_index` with `warning`
severity. Its message includes the direct-file count, and its recommendation
suggests adding `README.md` or `INDEX.md`.
