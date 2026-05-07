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
  and memory diagnosis in both recommended copy and link installs
- installer no-`-Force` conflict behavior and forced reinstall behavior
- `hub.lock` drift checking against a temporary git-backed hub
- public experience index search
- experience promotion, index rebuild, and search closure against a temporary
  hub copy
- PowerShell parser checks and JSON parsing
- public sensitive-pattern audit
- duplicate helper script hashes

## CI Gate

The repository also runs `.github/workflows/release-validation.yml` on pushes to
`main`, pull requests, and manual dispatch. The workflow executes the same
validator on:

- `windows-latest`
- `ubuntu-latest`
- `macos-latest`

Each job uploads the validator scratch directory as evidence. Treat CI failures
as release blockers unless the maintainer explicitly records a platform-specific
deferral for a pre-release calibration run.

Deferred checks are allowed only when the capability does not exist yet. The
current known deferred item is automatic first-session language writing; the
templates are validated, but the behavior is not script-driven yet.

## Publishing Steps

1. Start from a clean local review branch or a clearly understood local diff.
2. Run the release validation gate with a temporary scratch directory.
3. Review `validation-result.json` and any public diff.
4. Open or update a pull request when using CI for release review.
5. Confirm the release validation workflow passes on Windows, Ubuntu, and macOS.
6. Record only public-safe release status in this repository.
7. Push, tag, and publish release notes only after maintainer approval.

Do not publish if the validator reports a failed check. Fix the public tree or
record the release-blocking decision in private migration state, then rerun the
gate.

## Public Records

Public release records should describe the validation surface and final status.
Do not include local machine paths, private repository mappings, raw sensitive
audit findings, or private overlay details.
