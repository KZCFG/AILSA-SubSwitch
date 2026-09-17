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

## Binary candidate: 1.0.0 (2026091716)

- [x] Direct source build of application and widget on Apple Silicon.
- [x] Baseline CLT asserting harness: 271 passed, 0 failed across 36 classes.
      Settings regression after the About-tab addition: 18 passed, 0 failed.
      These are not Apple's XCTest runner; files importing Swift Testing are excluded.
- [x] Verify final ZIP checksum, app and widget signatures, resources and version.
- [x] Confirm no Sparkle framework, update-feed keys or updater dependency.
- [x] Install the exact 2026091716 archive and confirm Accounts and Settings → About
      render with the new A.S.S. icon. Navigation and usage layout were checked in
      2026091715; this candidate changes icon resources and build metadata only.
- [ ] Complete the remaining interactive checks in [TEST-CHECKLIST.md](TEST-CHECKLIST.md).
- [ ] Verify the menu bar icon's visibility on the target display, including any
      menu bar manager configuration. Reopening a window alone is not proof.
- [x] Confirm existing account profiles and preferences remain after local replacement.
- [ ] Attach the tested ZIP and checksum; publish accurate known limitations.

## Additional coverage still needed

- Native XCTest under full Xcode; do not advertise a passing native CI suite yet.
- Clean-machine first launch and widget installation.
- Intel hardware, other macOS versions, display arrangements and accessibility.
- Developer ID signing and notarization are deferred. The current ad-hoc package
  must not be described as notarized or as permanently fixing Keychain prompts.

The maintainer keeps raw logs and any private acceptance evidence outside the
public repository. See [release notes](RELEASE-READINESS-20260917.md) for the
current preparation status.
