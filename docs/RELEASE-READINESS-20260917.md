# 1.0.0 preparation — September 17, 2026

Updated September 18 after the acceptance continuation. **Candidate installed;
stable release held.** Full observations and limitations are in
[ACCEPTANCE-RESULTS-20260918.md](ACCEPTANCE-RESULTS-20260918.md).

The public project is **AILSA SubSwitch**, maintained at
[KZCFG/AILSA-SubSwitch](https://github.com/KZCFG/AILSA-SubSwitch).
It is a derivative of Copool, with the upstream MIT notices preserved.

## This candidate

- Marketing version: **1.0.0**; build **2026091805**.
- Manual distribution; no OTA updater, feed, Sparkle framework or automatic download.
- Settings → About shows the application icon, product name, version, build time,
  “Weekly usage at a glance. Switch accounts in a click.” and “© 2026 KZCFG · MIT”.
- Duplicate main-page headings are removed; usage actions share the provider row.
- The app and project-page icon share updated A.S.S. lettering; all macOS icon
  sizes can be regenerated with `scripts/build_icon.sh`.
- Application identifier: `com.ailsa.subswitch`; widget: `com.ailsa.subswitch.widgets`.
- Existing account data paths and credential identifiers are retained.
- English homepage, installation guide, privacy policy, contribution guidance,
  roadmap and issue templates are included.

## Verified locally

- The app and widget compile on Apple Silicon with Command Line Tools.
- The asserting harness ran **299 tests: 299 passed, 0 failed**, across 38 test
  classes. This is a custom XCTest-compatible shim, not Apple's XCTest.
- Account cards scroll instead of paginating. Compact Antigravity/Cursor layouts
  use up to three columns; Codex uses two to preserve room for credit details.
- Historical 1803 evidence: a native synthetic 12-account harness exercised scrolling, long-press sorting,
  cross-row gap filling and persisted order after process restart. Run it with
  `bash scripts/render_docs.sh --account-smoke`; it never loads real credentials.
  This harness was not rerun during the September 18 continuation.
- Native display acceptance covered named compact rings, the Gemini-first grouped
  selection menu, retained custom selections, per-credit rows and ticking seconds.
- The build script signs and checks the bundles, and generates a ZIP, checksum
  and local source manifest. The default signing identity is ad-hoc.
- September 18 real UI checks covered compact warning visibility, expiry versus
  countdown, provider skins, usage ranges/sorts/details, provider error isolation,
  the separate quota window and preserved preferences after candidate replacement.
- Installed 1805 reconciles the current Antigravity marker with verified native
  readback. Failed OAuth refreshes retain old snapshot timestamps and explicit errors.

## Public project delivery

The independent source repository and English project page are public. The
README images were rendered from native components with synthetic data, and all
six homepage images loaded successfully on GitHub. Relative documentation links
were checked. A bounded scan of 207 outgoing files found no known private-key,
API-token, personal home-directory or personal account-address patterns. This is
not a guarantee of the absence of every possible secret. Private vulnerability
reporting is enabled.

The previous release record placed a 1.0.0 ZIP and SHA-256 in a GitHub Release
draft; its remote state was not revisited in this continuation. Candidate 1805
was built and installed locally and was not uploaded or published. This display iteration
adds provider-specific order, scrollable account collections, custom compact rings,
reset-credit date/countdown options, and official/monochrome progress skins.
The About entry and A.S.S. artwork from the previous candidate remain unchanged.

## Still to validate before calling the binary stable

Use [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) for current acceptance. Source
publication does not prove clean-machine installation, menu bar visibility in
every display setup, widget behavior or durable Keychain authorization. The
installed app and packaged candidate use build 2026091805; this local UI check
does not complete the broader acceptance checklist. The two live Antigravity
failures were diagnosed as HTTP 400 `invalid_grant` from Google OAuth, and require
user sign-in before successful refresh can be validated. Their cached quota is
not fresh validation. Native current-card mismatch was a separate defect, fixed
and checked in 1805.

On this macOS 26/Bartender setup, ControlCenter blocks the launched status item
unless the host application's menu-bar permission is enabled. The temporary
permission was restored afterward; general menu-bar visibility remains open.
Live A → B → A transactions, chart hover/trackpad gestures, accessibility and
clean-machine/widget coverage also remain unverified.

The older OTA experiment is deferred and is not shipped in this version.
Private author correspondence, earlier debugging notes, live account data and
build logs are kept outside the public source snapshot.
