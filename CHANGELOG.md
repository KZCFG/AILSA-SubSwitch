# Changelog

## 1.0.0 — release preparation

The first AILSA SubSwitch release builds on Copool's Swift application foundation.

### Added

- Account management for Codex / ChatGPT, Antigravity and Cursor.
- Provider-specific quota families, reset times and available Codex reset credits.
- Today / 7-day / 30-day usage views, model details and a standalone usage window.
- OpenCodex ledger support with token metering and explicitly labeled USD estimates.
- Intraday point-and-line charts, hover breakdowns and horizontal trackpad navigation.
- Settings for token units, quota visibility and provider relaunch behavior.
- A native About window with version, build time and product tagline.
- Menu bar artwork, compact account cards and consistent segmented controls.

### Changed

- Removed the upstream proxy, tunnel and remote-deployment interface.
- Separated the application identity from Copool while preserving compatible
  local account/settings data paths and upstream notices.
- Replaced model-list pagination with a bounded scrolling list.
- App termination waits for active account-switch transactions to finish.

### Distribution

Manual GitHub downloads, Apple Silicon, macOS 14+. No OTA updater, no App Store
submission, no Developer ID signature or notarization in this release.

### Known limitations

Clean-device widget behavior and Intel packaging need validation. Provider
changes can require integration updates. Stable-signature Keychain grants are
not guaranteed by ad-hoc builds. See [the user guide](docs/USER-GUIDE.md).
