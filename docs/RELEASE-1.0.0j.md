# AILSA SubSwitch 1.0.0(j)

Build **2026101801**. Faster native Codex history reading and more accurate
Antigravity subscription labels, adapted from relevant CodexBar 0.77.0 changes.

- Skip unrelated conversation bodies before decoding native Codex usage records.
  Bounded byte scanning reduces reader overhead while preserving cumulative
  token totals, cache coverage, Unicode metadata and incomplete-file handling.
- Prefer explicit Antigravity paid-tier metadata. Show `PAID` when the paid tier
  is known but its specific plan is not. Suppress a conflicting `FREE` label
  beside measured five-hour quotas without guessing Pro or Ultra.
- Keep measured reset times in widgets and preserve the existing first-request
  evidence rule. Unknown or disabled quota buckets do not invent capacity.

The M1 Command Line Tools asserting compatibility harness passed **404 tests
across 54 classes**, with zero failures. Coverage includes the native/OAuth plan
paths, stored-plan fallback, identity mismatch, disabled/unmeasured windows,
widget reset projection, byte-search boundaries and cumulative usage parsing.
This harness is not Apple's XCTest runtime; Swift Testing suites are not run by it.

A 23 MB synthetic reader/parser benchmark completed in about **24 ms**, compared
with **157 ms** before the change at the median of three paired runs. All runs
returned the same record count and fixture token total. This is not a claim
about overall app responsiveness or production CPU usage.

Account credentials, provider pricing and automatic-switching rules are
unchanged. The app remains ad-hoc signed for Apple Silicon, requires macOS 14
or later, and is not notarized. Live provider behavior depends on the metadata
returned by the provider; injected-response tests do not replace a fresh
provider-side acceptance test.

See the [upstream applicability review](AILSA_SS-upstream-0.77.0.md) for the
changes adopted, already covered, or outside ASS's current provider support.
