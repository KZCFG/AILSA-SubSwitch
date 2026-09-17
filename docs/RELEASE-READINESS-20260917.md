# 1.0.0 preparation — September 17, 2026

The public project is **AILSA SubSwitch**, maintained at
[KZCFG/AILSA-SubSwitch](https://github.com/KZCFG/AILSA-SubSwitch).
It is a derivative of Copool, with the upstream MIT notices preserved.

## This candidate

- Marketing version: **1.0.0**; build **2026091715**.
- Manual distribution; no OTA updater, feed, Sparkle framework or automatic download.
- Settings → About shows the application icon, product name, version, build time,
  “Quota at a glance. Switch accounts in a click.” and “© 2026 KZCFG · MIT”.
- Duplicate main-page headings are removed; usage actions share the provider row.
- Application identifier: `com.ailsa.subswitch`; widget: `com.ailsa.subswitch.widgets`.
- Existing account data paths and credential identifiers are retained.
- English homepage, installation guide, privacy policy, contribution guidance,
  roadmap and issue templates are included.

## Verified locally

- Source application and widget compile on Apple Silicon with Command Line Tools.
- The baseline portable asserting harness ran **271 tests: 271 passed, 0 failed**,
  across 36 test classes. Settings regression after the About-tab change: **18
  passed, 0 failed**. This is a custom XCTest-compatible shim, not Apple's XCTest.
- The build script signs and checks the bundles, and generates a ZIP, checksum
  and local source manifest. The default signing identity is ad-hoc.

## Public project delivery

The independent source repository and English project page are public. The
README images were rendered from native components with synthetic data, and all
six homepage images loaded successfully on GitHub. Relative documentation links
were checked. A bounded scan of 207 outgoing files found no known private-key,
API-token, personal home-directory or personal account-address patterns. This is
not a guarantee of the absence of every possible secret. Private vulnerability
reporting is enabled.

The 1.0.0 ZIP and SHA-256 are staged in a GitHub Release draft. Package signatures,
version/build fields and the absence of updater keys/frameworks were verified.
After the English account-card labels changed, all 11 account-card regression
tests passed again. The exact 2026091715 ZIP was installed locally; Accounts,
Quota Management and Settings → About were inspected in the native app. The
footer, single About entry and removal of duplicate headings were confirmed.

## Still to validate before calling the binary stable

Use [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) for current acceptance. Source
publication does not prove clean-machine installation, menu bar visibility in
every display setup, widget behavior or durable Keychain authorization. The installed app and packaged candidate now both use build 2026091715; this
local UI check does not complete the broader acceptance checklist.

The older OTA experiment is deferred and is not shipped in this version.
Private author correspondence, earlier debugging notes, live account data and
build logs are kept outside the public source snapshot.
