# Release checklist

Record evidence for the exact version and build being shipped. An unchecked item
means unverified, not passed. Source publication and a stable binary release are
separate steps.

## Public source

- [x] English README, user guide, privacy policy, contribution guide and issue templates.
- [x] Preserve Copool, codex-tools and CodexBar MIT attribution and license text.
- [x] Set version 1.0.0; exclude updater code and dependencies.
- [x] Check all relative documentation links and preview images.
- [x] Review outgoing files for credentials, personal accounts, logs and build artifacts.
- [x] Publish a clean source snapshot to KZCFG/AILSA-SubSwitch; verify remote readback.
- [x] Enable private vulnerability reporting.

## Current release: 1.0.0(b) (2026092301)

The maintainer authorized publishing the (b) revision on September 23, 2026.
The final package uses the public version `1.0.0(b)` and includes the Codex
historical hover and 30-day grouping fixes described in the release notes.

- Application test evidence: **330 passed, 0 failed across 44 classes** in the
  full CLT asserting harness. This is not Apple's XCTest runtime.
- Antigravity 2.15.1: both native OAuth profiles resolved without a version-table
  entry; all three saved accounts refreshed successfully. A subsequent read-only
  check confirmed current native quota retrieval and no stored account errors.
  The expired-grant observations below describe the September 18 candidate.
- Codex 7-day hover now drives the range title, KPI cards, model rows and USD
  amount from the hovered date. Codex 30-day charts support daily or four-period
  weekly aggregation; hover labels use dates or month-week labels accordingly.
- Earlier Today / provider visual acceptance remains applicable; no new
  clean-machine coverage is claimed.
- Final packaging checks cover version metadata, source manifest, archive checksum,
  app/widget signatures, bundled resources, and absence of local account files.
- Distribution uses an ad-hoc-signed Apple Silicon ZIP with a checksum. Developer
  ID signing, notarization, native XCTest, clean-machine/widget installation and
  other display/menu-bar-manager configurations remain outside validated coverage.

Small releases use `1.0.0(a)`, `1.0.0(b)`, `1.0.0(c)`, and so on. Larger feature releases
change the numeric version; every package retains an increasing date-based build.
See [version policy](release-macos.md#version-and-identity) and the
[1.0.0(b) release notes](RELEASE-1.0.0b.md).

## Historical release: 1.0.0(a) (2026092202)

The previous public release and its acceptance record remain available at
[1.0.0(a) release notes](RELEASE-1.0.0a.md).

## Historical candidate: 1.0.0 (2026091805)

The checklist below is retained as the September 18 evidence record. Unchecked
items were not verified on that build and are not retroactively marked as passed.

- [x] Direct source build of application and widget on Apple Silicon.
- [x] CLT asserting harness: 299 passed, 0 failed across 38 classes.
      This is not Apple's XCTest runner; files importing Swift Testing are excluded.
- [x] Verify archive checksum, app/widget signatures, resources and version.
- [x] Confirm no Sparkle framework, update-feed keys or updater dependency.
- [x] Historical evidence from 1803, not rerun on 1805: synthetic 12-account
      interaction harness with nine compact Antigravity cards,
      vertical scrolling, long-press horizontal and cross-row reordering, order
      retained after restarting the harness, and compact Codex two-column layout.
- [x] Inspect installed account grids, family-grouped ring choices, preserved ring
      selections, numerical reset-credit rows and second-precision countdowns.
- [x] Preserve current-account disabled switch controls in compact cards.
- [x] Retain old timestamps and show stale/error warnings after failed live
      Antigravity refreshes; verify compact warning layout in 1804 and 1805.
- [x] Correct the current Antigravity marker from verified native identity without
      switching the provider; verify the installed 1805 app against native readback.
- [x] Verify actual expiry/countdown independence and per-provider skin settings
      in 1804, persisted custom ring order after installing/restarting 1805, and
      restoration of all five temporary display preferences afterward.
- [ ] Complete the remaining interactive checks in [TEST-CHECKLIST.md](TEST-CHECKLIST.md).
- [ ] Reauthenticate and recheck two saved Antigravity accounts. Production OAuth
      refresh returned HTTP 400 `invalid_grant` for both; neither recovered yet.
- [ ] Verify menu bar visibility across display and menu bar manager configurations.
      Local visibility depends on a macOS host menu-bar permission; the temporary
      setting was restored. This is an open gate, not a source-code fix.
- [x] Confirm existing profiles and display preferences survive app replacement.
- [ ] Publish the stable binary only after the remaining release checks pass.

## Additional coverage still needed

- Native XCTest under full Xcode; do not advertise a passing native CI suite yet.
- Clean-machine first launch and widget installation.
- Intel hardware, other macOS versions, display arrangements and accessibility.
- Developer ID signing and notarization are deferred. The current ad-hoc package
  must not be described as notarized or as permanently fixing Keychain prompts.

The maintainer keeps raw logs and any private acceptance evidence outside the
public repository. See [release notes](RELEASE-READINESS-20260917.md) and the
[September 18 evidence matrix](ACCEPTANCE-RESULTS-20260918.md) for exact build,
environment, checks and remaining gates. No stable binary was published in this
continuation.
