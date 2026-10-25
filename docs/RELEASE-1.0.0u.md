## What changed

- Read recorded Token usage from local Antigravity App and CLI conversation databases, using the bounded metadata decoder adapted from CodexBar v0.81.0. No Antigravity CLI process, login or model request is started for usage statistics.
- Combine native Antigravity and OpenCodex usage in the existing usage dashboard, date-range charts and share images. Matching Gemini model versions share one model row; each request keeps its independently calculated API-equivalent amount. Other recorded models retain their own identities.
- Count cache reads and reasoning output once, recover dates from verified generation/step metadata, and deduplicate stable response identities. Do not infer missing dates from file timestamps or deduplicate unrelated requests merely because their counts look alike.
- Show incomplete local coverage explicitly. Unidentified model rows remain available in the app for auditing and are omitted from share-image details, while confirmed Token totals remain included.

- Refine share images: hide zero-Token and displayed-zero-dollar model rows, choose descending Token or USD model order, and render Grok 4.7 in the same neutral style as other models without a Fast badge. Totals and trends still include all confirmed usage.

## Validation

- Focused synthetic SQLite/protobuf tests cover Token semantics, timestamp recovery, active WAL updates, source overlap, date ranges, malformed/bounded reads and model grouping. The broader CLT asserting test harness is run for both editions; it is not Apple XCTest.
- A network-denied local probe and independent metadata readback verify the native reader without sending model requests. Package checks verify source hashes, versions, app/widget signatures, archive checksums and public/private separation.
- Distribution remains an ad-hoc signed Apple Silicon package. Native save-dialog interaction, clean-machine installation, Developer ID signing and notarization are not claimed.
