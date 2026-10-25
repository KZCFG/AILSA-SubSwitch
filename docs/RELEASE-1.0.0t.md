## What changed

- Combine GLM 5.3 requested-model estimates with resolved GLM 5.3 usage in one model row, in both the usage dashboard and exported share images.
- Keep the original per-request amounts, Token totals, unresolved-route metadata and high-estimate counts. The amount can still show an approximation marker; details explain which records were estimated.
- Match the exact GLM 5.3 identity for supported providers. GLM 5.3 Flash and other requested-model estimates keep their existing grouping. No pricing tables, quota requests or account settings change.

- Remove unidentified model rows from dashboards and share-image details. Keep their original records, reported Token totals and trends; an export with reported usage can still be generated when no named model details are available.

## Validation

- Ten focused accounting/grouping checks pass in each edition using the CLT asserting XCTest-compatible harness, not Apple XCTest. Coverage includes merged dashboard/report rows, unchanged Token/USD totals, estimate counts, exact identities unrelated models, and hidden unidentified rows with preserved totals.
- Package checks verify source hashes, versions, app/widget signatures, archive checksums and exclusion of private implementation and credentials from the public edition.
- Distribution remains an ad-hoc signed Apple Silicon package. Native save-dialog interaction, native XCTest, clean-machine installation, Developer ID signing and notarization are not claimed.
