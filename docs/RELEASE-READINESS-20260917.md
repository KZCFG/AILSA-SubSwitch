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

## Still to validate before calling the binary stable

Use [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) for current acceptance. Source
publication does not prove clean-machine installation, menu bar visibility in
every display setup, widget behavior or durable Keychain authorization. The
installed development build and packaged candidate are distinct until a tested
replacement is performed.

The older OTA experiment is deferred and is not shipped in this version.
Private author correspondence, earlier debugging notes, live account data and
build logs are kept outside the public source snapshot.
