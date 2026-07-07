# Context Routing

Project memory language: English.

Use this folder as the long-term memory base.

- `tech/`: architecture, modules, build/deploy details, environment notes
- `business/`: product logic, state machines, domain rules
- `experience/`: pitfalls, incidents, fixes, and reusable playbooks

Optional context files (create only when the project benefits from them):
- `tech/terminology.md`: project-specific terms, abbreviations, and domain jargon — useful for domain-heavy, multi-team, or abbreviation-heavy projects; skip for small or well-documented projects.

Progressive disclosure rule: keep non-template context files discoverable with `## Summary` and `## Keywords` near the top. Agents should read README/index files first, then open only matching context entries.

## Optional Entry Index

Use an `Entry Index` table in category README files when a directory has more
than a few entries or when faster scanning would help. Keep the index
public-safe and human-maintained:

| File | Summary | Keywords |
| --- | --- | --- |
| `example.md` | One sentence describing when to open the entry. | keyword-a, keyword-b |

Optional columns such as `Maturity` or `Reviewed` are allowed only when they are
manually reviewed metadata. Do not add telemetry-derived fields, runtime usage
counts, `last_accessed`, or automatic decay state to context indexes.
