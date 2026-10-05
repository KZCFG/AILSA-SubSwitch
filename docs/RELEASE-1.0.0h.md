# AILSA SubSwitch 1.0.0(h)

Build: **2026100502**. Reliable automatic account and usage refresh.

## Account freshness

- Reopening the menu refreshes visible Codex and Antigravity subscriptions,
  even while the background worker is checking the active account. Cards
  already being refreshed reuse that in-flight request.
- Returning to Accounts or selecting Codex / Antigravity refreshes the
  relevant subscriptions without requiring the refresh button.
- Cursor rechecks the current native sign-in and quota on every presentation,
  including when an earlier account snapshot is already available.
- Claim the refresh before the initial store load, preventing simultaneous
  presentation callbacks from requesting each subscription twice.
- Keep the previous quota visible during a read; on failure, retain its last
  successful update time and show the provider error.

## Usage Management

- Opening Usage Management or changing its provider reads fresh usage.
- Selecting Today, 7 days or 30 days refreshes the selected provider immediately,
  including reselecting the current range. Hover context resets to the range.
- Automatic Cursor refreshes reuse older cached history and fetch the recent
  tail. The explicit refresh button still reloads the complete history.
- Concurrent refreshes for the same provider coalesce. A failed read retains
  the previous snapshot and timestamp rather than implying fresh data.
- Codex reads recorded local usage; Antigravity shows available quota snapshots.
  A refresh does not invent missing provider records or activate a quota window.

## Validation and distribution

The M1 command-line test runner passed **381 tests across 50 classes**, with
zero failures. A separate local variant passed **421 tests across 56 classes**.

Regression coverage includes reopening with a recent cache, inactive accounts
while an active refresh is running, simultaneous initial presentations,
provider selection, repeated range selection, Cursor quota refreshes and
failure recovery without changing the last successful update time.

This public build excludes the maintainer's private OpenCode usage import,
local ATC variant features, Hub service and machine configuration. Existing
usage accounting, chart layout and pricing are unchanged.

The Apple Silicon package is ad-hoc signed and is not notarized. The portable
asserting test runner is not Apple's XCTest runtime. Clean-machine installation
and other users' live-provider environments are outside this validation scope.
