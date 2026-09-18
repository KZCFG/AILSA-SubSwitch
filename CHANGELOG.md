# Changelog

## 1.0.0 candidate 2026091820 — require request evidence for countdowns

- Stop starting 5-hour and 1-week countdowns from read-only quota refreshes or
  legacy markers. Only explicit model-request evidence can authorize a marker.

## 1.0.0 candidate 2026091819 — correct drag offset compensation

- Keep frozen geometry for target detection while compensating the lifted card
  against its current grid slot, avoiding a jump when neighboring cards move.

## 1.0.0 candidate 2026091818 — stable account-card dragging

- Keep the lifted account card anchored to its frozen drag origin while the
  neighboring grid settles, preventing layout feedback from making it shake or
  disappear near another module.

## 1.0.0 candidate 2026091817 — remove duplicate dashboard button

- Keep the OpenCodex dashboard entry in Switch settings and remove the duplicate
  button from About.

## 1.0.0 candidate 2026091816 — clearer dashboard link

- Use an external-open icon for the local OpenCodex dashboard link in About.

## 1.0.0 candidate 2026091815 — semantic icon colors

- Set the limit panel to deep crimson and the reset panel to deep blue, with a
  full reset bar and glossy red/blue arrow highlights.

## 1.0.0 candidate 2026091814 — settings guidance and darker icon palette

- Add persistent help for automatic quota checks and explain when the selected
  editor restarts after a Codex account switch.
- Link OpenCodex to its local dashboard instead of its GitHub project.
- Stop treating a read-only quota refresh as a first model request. Clear legacy
  countdown activation markers when the provider reports no usage; label the
  existing feature as automatic checks until model-request activation exists.
- Use a charcoal icon background with deep blue limit and crimson reset panels
  and matching switch arrows.

## 1.0.0 candidate 2026091812 — OpenCodeX account sync and quota-aware switching

- Add an opt-in Settings toggle that synchronizes a verified AntiGravity switch
  to OpenCodeX's `google-antigravity` account set.
- Preserve OpenCodeX's multi-account store, activate the matching account and
  keep the current OpenCode account when 5-hour / 1-week quota data is missing,
  stale or exhausted.
- Include reset timing in automatic account ranking and require a complete
  two-window snapshot before background switching.
- Keep account-card quota status on one line, strengthen reset-credit and
  Credits labels, and add spaces around Chinese countdown units.
- Keep compact-card quota warnings on one line as well, scaling the text before
  truncation when the card is narrow.
- Use the full product name in the new account-sync explanation and public
  project copy.
- Recover the OpenCodeX account email from a verified ID token when the saved
  AntiGravity credential does not include a top-level email field.
- Refresh the GitHub project description, provider roadmap and product wording.

## 1.0.0 candidate 2026091807 — guided AntiGravity login and menu-bar recovery

- Add a visible AntiGravity account-add progress card with a spinner and
  stages for Google sign-in, macOS authorization and account import.
- After Google sign-in, explain that the login window can close and that the
  following macOS password prompt completes the automatic import. An info
  dialog explains the Keychain authorization and confirms that SubSwitch never
  reads or stores the computer password.
- Add Settings → General → “Force icon display” to recreate the menu-bar
  status item when menu-bar organizers such as Bartender hide it.
- Normalize General settings row typography and keep the brighter deletion
  confirmation surface.
- Stabilize account-card drag targets and hit testing so cards do not oscillate
  or lose the drag when approaching a neighboring card.

## 1.0.0 candidate — account display and arrangement

- Scroll all account collections; fit compact Antigravity/Cursor cards in up to three columns and Codex in two.
- Long-press and drag cards to reorder, with animated gap filling and per-provider persistence.
- Show second-precision countdowns with abbreviated or Chinese time units.
- Group Antigravity ring choices by model family, Gemini before Claude.
- Label compact quota rings by family and window; configure ring order per provider or account.
- Show reset credits and balance beside a single Codex ring, with individually numbered expiry rows.
- Choose reset-credit countdowns or absolute expiry dates independently of quota percentages.
- Add official logo and monochrome AILSA SubSwitch progress skins per provider.
- Keep stale-snapshot and refresh-error warnings visible on compact account cards,
  including the last successful update time.
- Repair the production Antigravity diagnostic driver build after the separate
  quota-window integration.
- Reconcile the current Antigravity card after a verified external native sign-in;
  preserve pending switches and newer credentials, and never switch the provider
  or refresh old quota timestamps merely to update the current marker.


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
