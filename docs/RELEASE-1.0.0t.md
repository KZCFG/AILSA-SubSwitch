## What changed

- Combine GLM 5.3 requested-model estimates with resolved GLM 5.3 usage in one model row, in both the usage dashboard and exported share images.
- Keep the original per-request amounts, Token totals, unresolved-route metadata and high-estimate counts. The amount can still show an approximation marker; details explain which records were estimated.
- Match the exact GLM 5.3 identity for supported providers. GLM 5.3 Flash and other requested-model estimates keep their existing grouping. No pricing tables, quota requests or account settings change.

## Validation

- Eight focused accounting/grouping checks pass in each edition using the CLT asserting XCTest-compatible harness, not Apple XCTest. Coverage includes merged dashboard/report rows, unchanged Token/USD totals, estimate counts, exact identities and unrelated models.
- Package checks verify source hashes, versions, app/widget signatures, archive checksums and exclusion of private implementation and credentials from the public edition.
- Distribution remains an ad-hoc signed Apple Silicon package. Native save-dialog interaction, native XCTest, clean-machine installation, Developer ID signing and notarization are not claimed.
