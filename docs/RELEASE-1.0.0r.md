## What changed

- Add a Claude usage tab that reads local Claude Desktop Code-session logs only. No Claude account login, quota endpoint, cookies, Keychain access, credential extraction or model requests are added.
- Deduplicate streamed assistant frames by request and message identity, and retain incremental file offsets across refreshes. Native cache reads, 5-minute/1-hour cache writes and output/reasoning subsets are accounted for separately.
- Calculate API-equivalent USD using bundled official Claude rates verified on October 23, 2026, including supported Fast, US-region and Haiku long-context modifiers. Unknown models or incomplete pricing metadata remain unpriced. These values are not subscription charges.
- Export usage images for 60 days, 90 days and a rolling year (365 days), alongside existing daily, 7-day and 30-day reports. Annual trends group by week while retaining exact full-range totals; other multi-day trends use daily totals.
- Load the requested history range instead of truncating exports to the dashboard's 30 days. Cursor exports preserve its normal dashboard cache. Reports include only available records and do not reconstruct missing history.
- Include the previously prepared pool diagnostics: separate Pool Active badges, bounded stale quota handling and detailed rotation decisions.

## Validation

- 463 public regression checks passed with the CLT asserting XCTest-compatible harness; this is not Apple XCTest. The private edition also passed 534 checks.
- A process-level deny-network sandbox verified local Claude metering and 60-day, 90-day and annual PNG export against an independent calculation.
- Coverage includes native cache lifetimes, reasoning subsets, exact model matching, pricing modifiers, streamed-frame deduplication, incremental append/replacement, unknown-price handling and full-range export boundaries.
- macOS app and widget signatures, version metadata and source manifests are verified for the release packages. Existing unrelated compiler warnings remain in native Keychain/concurrency code.
