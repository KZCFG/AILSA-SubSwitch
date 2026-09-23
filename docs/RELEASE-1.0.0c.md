# AILSA SubSwitch 1.0.0(c)

Build: **2026092302**. Choose whether usage charts show Token usage or
equivalent API consumption in USD from Settings.

## Choose a chart metric

- Open **Settings → Usage Display → Usage chart display** and select **Token usage**
  or **Equivalent API consumption (USD)**. Token usage remains the default.
- The preference is saved between launches and updates open usage windows
  immediately. The selector stays in Settings to keep the usage dashboard clean.
- The choice applies to Today, 7-day and 30-day charts, including daily and weekly
  grouping, bar charts, line charts, axis labels and hover values.
- Model-list sorting is now independent of the chart metric. Changing a table's
  sort order no longer silently changes the historical chart's unit.

## Consistent amounts and missing data

- Today's USD chart sums the same minute buckets used by its hover summaries.
  Historical USD charts use the same daily or weekly totals as the summary cards.
- USD values keep their existing pricing basis. API-equivalent amounts are not
  subscription invoices, and separate pricing bases are never added together.
- Records without a price remain unavailable instead of becoming zero-dollar
  usage. Known zero amounts and intervals without requests remain distinguishable.
- Antigravity keeps its quota-percentage charts because its source does not
  report per-request tokens or prices.

## Validation and distribution

- The full CLT asserting harness passes **334 tests across 45 classes**, including
  interval boundaries, unpriced data, monetary overflow and daily/weekly totals.
  This harness is not Apple's XCTest runtime.
- Native offscreen rendering checks cover both metrics for Today, 7-day and
  30-day charts, both historical chart styles, weekly grouping and Settings.
  The checks use synthetic records and isolated preferences.
- The Apple Silicon package is ad-hoc signed and not notarized. Native XCTest,
  clean-machine installation and other hardware configurations remain outside
  this revision's validation scope. See the [release checklist](RELEASE-CHECKLIST.md).
