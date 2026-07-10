# Directory Index Reference

Use a directory index when a directory has many entries, its initial navigation cost is high, or lifecycle status needs a single maintained view. An index is a navigation aid, not a requirement for every directory.

## Choose the file name

- Use `README.md` when the directory description and usage guidance are the
  main content.
- Use `INDEX.md` when the entry list and lifecycle navigation are the main
  content.

## Suggested fields

| Entry | Summary | Status | Refs | Last reviewed |
| --- | --- | --- | --- | --- |
| [`example/`](example/) | What the entry contains and why it exists. | Active | Issue or pull request reference, plus maintained repository-relative links. | YYYY-MM-DD |

Adapt or omit fields to fit the directory. Do not apply the complete table
mechanically when a smaller index is clearer.

Record only current, public-safe facts that can be maintained over time. Do not record temporary branches, waiting for checks, next actions, local machine paths, private evidence, raw runtime logs, or other short-lived governance state.
