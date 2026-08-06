# Project workspace fixture

`new-project/` is a self-contained public project root containing one valid
asset at each canonical root. Copy it to any temporary directory before a
read-only parser check; it does not rely on Git, a remote, a user profile, or
the repository that contains this fixture.

`cases.json` is a deterministic mutation manifest. Each case names the
canonical asset, a mutation or input-path variant, and the expected outcome.
Mutations are descriptions for a verifier to apply to a temporary copy; the
checked-in `new-project/` tree remains unchanged. The procedure body includes a
literal command marker solely to prove that readers inspect frontmatter without
executing Markdown body text.
