# AILSA SubSwitch 1.0.0(b)

Build: **2026092301**. This maintenance revision makes historical Codex usage
interactive without changing the Accounts, Antigravity, or Cursor layouts.

## Codex historical hover

- Hovering a 7-day bar or line point now selects that date as the active usage
  context. The range control changes from `7 天` to the hovered date.
- The Token total, equivalent API consumption amount, and model breakdown above
  the chart are recalculated from the hovered date. Moving away restores the
  complete 7-day range.
- Hovering works identically with the bar and line chart styles.

## 30-day grouping

- Codex 30-day usage now has an explicit **按天 / 按周** control.
- Daily mode keeps one point per day. Weekly mode combines the full 30-day
  window into four periods, retaining all records while keeping the chart at a
  readable density.
- Hover labels follow the selected mode: a date in daily mode and a localized
  month-week label such as `9月第4周` in weekly mode. The Token, equivalent API
  amount, and model rows follow the same period.

## Validation

- The source and app build compile with the Command Line Tools packaging path.
- The targeted quota-management time-range test passes after the change.
- The full asserting harness passes **330 tests across 44 classes**, using the
  Command Line Tools XCTest-compatible shim; it is not Apple's XCTest runtime.
  The result is recorded in [the release checklist](RELEASE-CHECKLIST.md).
- The package is Apple Silicon, ad-hoc signed, and not notarized. It contains no
  local account files or credentials. Existing provider-specific validation from
  [1.0.0(a)](RELEASE-1.0.0a.md) remains unchanged.

## Version policy

Small maintenance updates use lowercase parenthesized revisions:
`1.0.0(a)`, `1.0.0(b)`, `1.0.0(c)`, and so on. Larger feature releases change
the numeric version. The internal build number remains date plus revision.
