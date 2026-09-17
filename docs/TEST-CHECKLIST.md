# Interactive acceptance

Record the exact build, macOS version, display configuration and observed result.
Run offline checks first; compilation alone is not interaction acceptance.

## Offline checks

```bash
bash scripts/sync_version.sh --check
bash scripts/run_tests.sh --isolate
bash scripts/build_app.sh --output /tmp/ass-candidate
```

The repository test runner uses an asserting shim on Command Line Tools. It
does not replace Apple's XCTest or run files importing Swift Testing. Keep this
distinction in every test report. Do not label failures environmental without
investigating them.

## Menu bar and windows

- Launch: one visible status item; Accounts opens first. No unwanted main window.
- Click status item to open/close; Escape and outside click dismiss only the panel.
- Confirm light/dark appearance, VoiceOver label and visibility with a menu bar manager.
- Small display: cards and controls remain reachable; the bounded model list
  scrolls independently of its headings, summary and chart.
- Expand Quota Management: separate window opens; closing it preserves the status item.
- About: Settings → About opens the inline page; no top-right information shortcut.
  Check the icon, name, 1.0.0, build time, tagline and GitHub/feedback/license links.
  Confirm the footer reads “© 2026 KZCFG · MIT”.
  Navigating away must preserve the panel; no updater controls are present.
- The Accounts, Quota Management and Settings pages do not repeat the selected
  main-tab title. Provider navigation, refresh and expand controls remain usable.

## Account safety

- Entire provider segments are clickable; highlights animate unless Reduce Motion is on.
- Current account has a disabled switch control. Smart switch is a persistent toggle.
- Import, refresh, switch A → B → A and remove a test profile for each provider.
  Verify the native identity after switching, not merely the selected card.
- Respect restart-after-switch settings; do not interrupt unsaved provider work.
- Wrong-account quota must not be displayed as the selected account's quota.
- Expired or denied credentials yield a recoverable error. Background refresh must
  not repeatedly prompt for a macOS password. Interactive Keychain access may need approval.
- Replacing ASS preserves saved profiles, quota preferences and native provider data.

## Usage dashboard

- Open window: automatic refresh; one provider's failure stays within that provider.
- Today / 7 / 30 and provider segments respond across the whole button, with animation.
- Token and USD sort correctly; the model list reaches every row without moving headings.
- Model details open/close without closing the parent panel; navigation retains context.
- Today uses points joined by lines. Horizontal two-finger movement pans time.
- Hover updates tokens, reference cost and model breakdown for the selected interval;
  leaving the plot restores the selected range totals.
- M/B units, interval and quota-window visibility match Settings.
- Unknown pricing stays unknown. Reference estimates are labeled separately from bills.
- Cursor refresh uses the selected account and does not rescan all history on each open.
- Antigravity history describes quota snapshots, not fabricated token or dollar consumption.

## Privacy and additional coverage

Use synthetic accounts for public screenshots; never publish credentials or full
session logs. Verify widget installation on a clean machine, localization,
keyboard navigation, VoiceOver and Reduce Motion separately and record untested
platforms explicitly.
