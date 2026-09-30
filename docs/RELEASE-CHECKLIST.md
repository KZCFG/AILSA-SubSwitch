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

## Current release: 1.0.0(g) (2026100101)

This revision adds GPT-6.1 Sol usage reference pricing.

- M1 CLT validation: **370 tests passed, 0 failed, across 49 classes**, using
  the asserting XCTest compatibility runner. The separate local build passed
  **393 tests, 0 failed, across 53 classes**.
- Official prices were checked on October 1, 2026. Coverage includes cache
  discounts, the 272,000-token boundary, vendor-confirmed Fast outcomes,
  unknown identities, invalid usage and unchanged older model prices.
- Historical replay of **61,380 unique records** preserved all Token totals
  and all previously priced public model amounts. Only GPT-6.1 Sol gained newly
  calculated amounts, matching an independent calculation. Package validation
  covers source manifests, ZIP checksums and matching app/widget versions.
- Distribution is ad-hoc signed for Apple Silicon. Native XCTest, clean-machine
  installation, Developer ID signing and notarization remain unverified.

See [1.0.0(g) release notes](RELEASE-1.0.0g.md).

## Historical release: 1.0.0(f) (2026093001)

This revision adds official API-equivalent pricing for ATC's local DeepSeek V4.1
Flash model, without changing native usage records or confirmed vendor charges.

- **360 passed, 0 failed across 48 classes** in the full CLT asserting harness
  on M1. This is not Apple's XCTest runtime.
- The official Flash price table and the 2026 State Council holiday calendar
  were checked on September 30, 2026. Request-time UTC boundaries, weekends,
  holidays, cache discounts, identity checks and missing usage are covered.
- Private Hub files and local credentials are excluded from the public source
  and package. The public and locally installed builds are validated separately.
- Distribution remains ad-hoc signed for Apple Silicon. Native XCTest,
  clean-machine installation, Developer ID signing and notarization remain unverified.

See [1.0.0(f) release notes](RELEASE-1.0.0f.md).

## Historical release: 1.0.0(e) (2026092803)

This revision adds native usage-image export and GPT-6 Sol / Luna pricing.

- **348 passed, 0 failed across 47 classes** in the full CLT asserting harness.
  This is not Apple's XCTest runtime. New coverage includes official rates,
  threshold boundaries, rolling periods, DST and historical minute loading.
- Native offscreen reports cover Daily, Weekly and Monthly, Token and USD,
  Chinese and English. Export images include aggregates only; no private
  usage data or personal images enter the repository or release package.
- Historical replay confirms unchanged Token totals and existing model prices.
  The new pricing records keep their own audit date and confirmation rules.
- Packaging checks cover app/widget versions, clean source manifest, ZIP
  checksum, ad-hoc signatures and exclusion of local credentials/configuration.
- Native save-dialog interaction on other machines, native XCTest, clean-machine
  installation, Developer ID signing and notarization remain unverified.

See [1.0.0(e) release notes](RELEASE-1.0.0e.md).

## Historical release: 1.0.0(d) (2026092801)

This revision adds the Grok Build Fast reference mapping and no other features.

- **339 passed, 0 failed across 45 classes** in the full CLT asserting harness.
  Coverage includes cache discounts, the 200,000-token threshold, explicit
  Priority grants, unknown identity, deduplication and unaffected model records.
  This is not Apple's XCTest runtime.
- A frozen historical ledger was replayed through the production reader before
  and after the change. All Token counts and unrelated model amounts match;
  only Grok Build Fast receives the missing reference amount.
- The confirmed-tier catalog is unchanged. Unknown pricing stays unavailable.
- Packaging checks verify matching app/widget versions, clean source manifest,
  ZIP checksum, ad-hoc signatures and exclusion of private configuration/data.
- Distribution remains ad-hoc signed for Apple Silicon and is not notarized.
  Native XCTest, clean-machine installation and live-provider acceptance are
  outside this revision's validation scope.

See [1.0.0(d) release notes](RELEASE-1.0.0d.md) for user-visible changes.

## Historical release: 1.0.0(c) (2026092302)

This revision adds the saved chart-metric preference in Settings → Usage Display.
Token and reference-USD charts use the same aggregates as their summary cards;
Antigravity retains its percentage-based presentation.

- **334 passed, 0 failed across 45 classes** in the full CLT asserting harness,
  including interval boundaries, unpriced and zero-priced records, monetary
  overflow and daily/weekly aggregation. This is not Apple's XCTest runtime.
- Native offscreen rendering with synthetic data covers 14 chart states: both
  metrics for Today, and bar/line charts for 7 days, 30 days by day and 30 days
  by week. Live preference changes reach the existing views; an isolated
  preferences store retains the selected mode.
- The Settings → Usage Display control fits the existing panel at 544 × 670 pt.
  The General settings layout and public promotional images are unchanged.
- All 11 localization catalogs pass property-list validation.
- Packaging checks verify the version, clean source manifest, ZIP checksum,
  app/widget signatures, runtime resources and absence of local account files.
- Distribution remains ad-hoc signed for Apple Silicon and is not notarized.
  These synthetic checks do not claim live-provider or clean-machine acceptance.

See [1.0.0(c) release notes](RELEASE-1.0.0c.md) for user-visible changes.

## Historical release: 1.0.0(b) (2026092301)

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
