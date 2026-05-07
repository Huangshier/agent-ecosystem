# Release Process

This process keeps public releases repeatable while keeping private migration
state, sensitive audit details, and local runtime paths out of the public
repository.

## Release Gate

Run the release validation gate before any push, tag, or published release:

```powershell
.\scripts\validate-release.ps1 -ScratchRoot <scratch-root>
```

Use a scratch directory outside the live runtime. The validator refuses to use
the current user's `$HOME\.agents` runtime path. It writes an
`install-manifest.json` for each temporary install and a final
`validation-result.json` under the scratch directory.

The validator checks:

- public repository structure and release documentation entrypoints
- Workflow Kernel skill metadata
- installer profile matrix for `minimal`, `recommended`, `full`, and `dev`
- copy mode and default link/junction mode installs
- runtime smoke coverage for bootstrap, context gate, workflow spec creation,
  and memory diagnosis
- public experience index search
- PowerShell parser checks and JSON parsing
- public sensitive-pattern audit
- duplicate helper script hashes

Deferred checks are allowed only when the capability does not exist yet. The
current known deferred item is automatic first-session language writing; the
templates are validated, but the behavior is not script-driven yet.

## Publishing Steps

1. Start from a clean local review branch or a clearly understood local diff.
2. Run the release validation gate with a temporary scratch directory.
3. Review `validation-result.json` and any public diff.
4. Record only public-safe release status in this repository.
5. Push, tag, and publish release notes only after maintainer approval.

Do not publish if the validator reports a failed check. Fix the public tree or
record the release-blocking decision in private migration state, then rerun the
gate.

## Public Records

Public release records should describe the validation surface and final status.
Do not include local machine paths, private repository mappings, raw sensitive
audit findings, or private overlay details.
