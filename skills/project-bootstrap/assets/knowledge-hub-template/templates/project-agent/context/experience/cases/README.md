# Troubleshooting Cases

Structured case files for complex or recurring issues.

## When to Use
- Issue required significant root cause analysis
- Fix involved non-obvious steps or workarounds
- Issue is likely to recur in this or similar projects

## Format
Use `case_template.md` for new cases. Each case file should have:
- **Keywords** for index search matching
- **Symptoms** with exact error text
- **Root Cause** with code/config references
- **Prevention Rule** that can be checked automatically

## vs incidents.md
- `incidents.md`: Quick lightweight entries for minor issues
- `cases/*.md`: Structured files for complex/representative issues worth indexing

## Searching
When troubleshooting, scan filenames and Keywords sections in this directory for matches against error text or module names.
