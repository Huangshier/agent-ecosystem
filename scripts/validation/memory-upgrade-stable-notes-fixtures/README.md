# Memory Upgrade Stable Notes Fixtures

These fixtures cover deterministic stable-section preservation for
`memory_upgrade.ps1 -Mode Apply`.

- `positive-stable-section` contains compact synthetic facts under explicit
  stable notes sections plus volatile session-state bullets. Apply should keep
  only the expected stable facts.
- `negative-volatile-only` contains only volatile notes. Apply should keep the
  existing minimal upgrade marker and preserve no stable facts.

The fixtures intentionally do not require semantic classification, NLP, or
stable-fact extraction from arbitrary prose.
