# 1.0.0 preparation — September 17, 2026

The public project is **AILSA SubSwitch**, maintained at
[KZCFG/AILSA-SubSwitch](https://github.com/KZCFG/AILSA-SubSwitch).
It is a derivative of Copool, with the upstream MIT notices preserved.

## This candidate

- Marketing version: **1.0.0**; build **2026091713**.
- Manual distribution; no OTA updater, feed, Sparkle framework or automatic download.
- About view shows the application icon, product name, version, build time and
  “Quota at a glance. Switch accounts in a click.”
- Application identifier: `com.ailsa.subswitch`; widget: `com.ailsa.subswitch.widgets`.
- Existing account data paths and credential identifiers are retained.
- English homepage, installation guide, privacy policy, contribution guidance,
  roadmap and issue templates are included.

## Verified locally

- Source application and widget compile on Apple Silicon with Command Line Tools.
- The portable asserting harness ran **271 tests: 271 passed, 0 failed**, across
  36 test classes. It is a custom XCTest-compatible shim, not Apple's XCTest.
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
tests passed again.

## Still to validate before calling the binary stable

Use [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) for current acceptance. Source
publication does not prove clean-machine installation, menu bar visibility in
every display setup, widget behavior or durable Keychain authorization. The
installed development build and packaged candidate are distinct until a tested
replacement is performed.

The older OTA experiment is deferred and is not shipped in this version.
Private author correspondence, earlier debugging notes, live account data and
build logs are kept outside the public source snapshot.
