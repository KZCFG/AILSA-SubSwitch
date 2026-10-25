## What changed

- Replace the Year preset in **Export usage image** with **Custom**. Select a start and end date, inclusive in the local time zone, for a weekend, a project or a longer period.
- Add an optional **Share title** for all periods, up to 80 characters. For example, export a Friday–Sunday report titled “A wonderful weekend”. Leave it blank for the default Daily, Weekly, Monthly or period heading. The actual date range remains visible below the title.
- Load the complete selected history, including ranges longer than 365 days, without changing the normal 30-day dashboards or Cursor’s refresh cache. Single days use half-hour buckets; longer trends group days automatically while preserving exact interval totals.
- Keep native folder/filename selection and Finder reveal after saving. The suggested filename safely includes a custom title and the actual dates.
- Preserve offline-only Claude statistics, available-history limits, unpriced-model filtering and separate API-equivalent amounts. No missing usage is reconstructed.

## Model recognition and reference estimates

- Add Gemini 4 Argon Token/reference-USD recognition, including output thinking tokens as an existing subset, implicit cache discounts and the December 1, 2026 price change. Official Standard prices per million tokens are $2 input / $0.10 cached input / $10 output through November 30, then $4 / $0.20 / $20. Vendor-confirmed Priority uses the published 1.8× rates. [Google pricing](https://ai.google.dev/gemini-api/docs/pricing#gemini-4-argon).
- Recognize official GLM 5.3 and GLM 5.3 Flash identities case-insensitively and show readable model names. GLM 5.3 uses $1.40 input / $0.26 cached input / $4.40 output per million tokens; Flash retains $0.15 / $0.03 / $0.50. [Z.AI pricing](https://docs.z.ai/guides/overview/pricing).
- For reported Token usage with a known requested model but missing resolved identity, add a separately labeled requested-model estimate at the highest known published context/priority rates, without cache discounts. Keep the original unresolved identity and confirmed-price fields unchanged. Existing valid per-request prices are preserved.
- Mark high estimates in the dashboard and share images, and show diagnostic counts and missing-price reasons in details. Missing Token counts, unknown automatic routes, unsupported prices and conflicting data stay unpriced. This is an upper estimate within known published Token rates, not a maximum possible bill including unknown tools, regions or unverified charges.

## Validation

- 473 public regression checks passed with the CLT asserting XCTest-compatible harness; the private edition passed 550 checks. This is not Apple XCTest.
- Coverage includes inclusive weekend boundaries, DST, invalid and future ranges, single-day custom intraday buckets, 800-day history, safe filenames, title defaults and exact Token/USD aggregation. Additional checks cover Argon promotion/Priority boundaries, GLM identities, highest-rate assumptions, invalid usage and unchanged confirmed-price fields.
- Native offscreen rendering under a deny-network process sandbox verifies Chinese/English report controls, a custom weekend heading, Token/USD images and an 80-character title. This does not claim interaction with the native save dialog.
- App/widget signatures, version metadata, source hashes, archive checksums and public credential/private-code exclusion are verified before distribution. Existing unrelated Keychain/concurrency compiler warnings remain.
- Distribution uses an ad-hoc signed Apple Silicon package. Native XCTest, clean-machine installation, Developer ID signing and notarization are not claimed.
