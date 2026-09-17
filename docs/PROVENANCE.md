# Source provenance

AILSA SubSwitch is derived from [Copool](https://github.com/AlickH/Copool), using
baseline commit `3cb6ede534bdbff86804e9beaed567a190dac2f3`. The independent repository
starts with a reviewed current-source snapshot; it does not erase that derivation
or claim the upstream architecture as original ASS work.

## Reuse and notices

- Copool and its upstream [codex-tools](https://github.com/170-carry/codex-tools)
  are covered by the MIT notices preserved in the root LICENSE. Copool's public
  LICENSE was verified on September 17, 2026. The author also confirmed MIT for
  his original Swift contributions; private correspondence is not published.
- `LiquidProgress.swift` adapts CodexBar's progress-bar structure.
- The Cursor and Antigravity readers used CodexBar as an implementation reference.
  The full CodexBar MIT notice is included conservatively for all such reuse;
  an exhaustive line-by-line originality comparison has not been performed.
- OpenCodex is an optional external data source. Its server/runtime code is not
  part of the application or this source snapshot.
- The app icon is a project-specific, AI-assisted illustration. Provider names
  and marks remain the property of their respective owners.

See [bundled third-party notices](../Sources/Copool/Resources/THIRD_PARTY_NOTICES.md).
The removed proxy binaries/Rust sources, copied Electron JavaScript snapshots,
private artifacts and upstream screenshots are not in this public snapshot.

## File inventory

[provenance.csv](provenance.csv) compares outgoing files to the recorded upstream
baseline: identical, modified or absent from that baseline. “Local” means absent
from the baseline; it is **not an independent proof of original authorship**.
Images are listed by byte size rather than lines of text.

Regenerate from an upstream-aware development checkout:

```bash
python3 scripts/generate_provenance.py --upstream /path/to/Copool
```

The selected upstream checkout must contain the baseline commit. The clean public
repository intentionally does not contain the developer's private working history.
