# Project Terminology

## Summary

Record project-specific terms, abbreviations, domain jargon, and easily
confused concepts. This file is optional; create it when a terminology table
helps agents and contributors avoid misinterpretation. Delete it if the project
has no domain-specific vocabulary worth formalizing.

## Keywords

terminology, glossary, domain terms, abbreviations, project vocabulary

## When To Create

A terminology file adds value when one or more of the following apply:

- The project operates in a domain-heavy field (embedded systems, finance,
  medical devices, protocol design, reverse engineering).
- Multiple teams or external contributors collaborate and use terms
  differently.
- The codebase contains many abbreviations, acronyms, or overloaded words
  whose meaning depends on context.
- Business terms and technical terms overlap and can be confused (e.g.,
  "session" in HTTP vs. a user's working session).

## When Not Needed

Skip this file when:

- The project is small and terminology is obvious from the code and docs.
- Terms are standard and well-documented in the framework or language docs.
- The work is short-lived or one-off with no long-term collaborators.

## Suggested Structure

Keep the table minimal. Add or remove columns to fit the project.

| Term | Definition | Context / Aliases | Notes |
|------|-----------|-------------------|-------|
| *(example)* Widget sync | Periodic reconciliation between the widget store and the external registry | Also called "widget refresh" in older docs | Runs every 5 min in production |
| *(example)* HAL | Hardware Abstraction Layer | Not to be confused with "HAL" (HTTP Accept-Language) in the API module | See `drivers/hal/` |

Fill in only the rows relevant to the project. Delete example rows once real
entries are added.

## Tips

- Keep definitions short — one or two sentences.
- Use the `Context / Aliases` column for cross-references, not long paragraphs.
- Add a `Notes` column entry when a term has a non-obvious history, deprecation
  status, or known pitfall.
- This file is discovered by agents via the `## Keywords` header. No special
  routing configuration is needed.
- Update or remove entries when terms change. Stale definitions are worse than
  no definitions.

## Notes

- This template is entirely optional. Do not create this file unless the
  project genuinely benefits from a terminology reference.
- Do not treat this file as a changelog or glossary maintenance tracker. It
  is a living reference, not a history log.
- Project-specific terms only. Do not add definitions for terms already
  documented in the programming language or framework docs.
