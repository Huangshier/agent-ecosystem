# Release Notes

- [Future release-note template](template.md)
- [v0.7.0](v0.7.0.md)
- [v0.6.0](v0.6.0.md)
- [v0.5.2](v0.5.2.md)
- [v0.5.1](v0.5.1.md)
- [v0.5.0](v0.5.0.md)
- [v0.4.6](v0.4.6.md)
- [v0.4.5](v0.4.5.md)
- [v0.4.4](v0.4.4.md)
- [v0.4.3](v0.4.3.md)
- [v0.4.2](v0.4.2.md)
- [v0.4.1](v0.4.1.md)
- [v0.4.0](v0.4.0.md)
- [v0.3.1](v0.3.1.md)
- [v0.3.0](v0.3.0.md)
- [v0.2.0](v0.2.0.md)
- [v0.1.0](v0.1.0.md)

## Release body and maintainer record contract

Future release notes start from `template.md` and have two deliberately
separate audiences:

- The content between `RELEASE_BODY_START` and `RELEASE_BODY_END` is the only
  copyable GitHub Release body. It is user-facing and covers audience, upgrade
  actions, main changes, compatibility, known limitations, rollback, and the
  public boundary. It may say that validation succeeded, but it must not include
  exact result counts or internal evidence.
- `Internal Release Record`, after `RELEASE_BODY_END`, is the maintainer record.
  It owns issue and pull-request mapping, exact PASS/FAIL/WARN/DEFERRED counts,
  hosted run and platform-matrix evidence, artifact and manifest details, tag
  target, release status, authorization, and other governance facts.

The validator applies the strict contract to the future template and every new
release-note file. The tracked published notes through `v0.6.0` form an exact
legacy allowlist: they remain immutable historical records and are not
retroactively judged by the new body-content rules. This compatibility set is
intentionally closed; a new or backdated note cannot opt out by choosing an old
version number, omitting markers, or omitting contract metadata.
