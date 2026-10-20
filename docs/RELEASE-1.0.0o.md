## What changed

- Record completed account-pool decisions separately from credential-sync time, including exact remainder, the chosen threshold, eligible candidates and the reason a switch was deferred.
- Show two-decimal quota headroom and clear decision status in Settings; record manual selection and threshold-range changes distinctly from automatic rotation.
- Isolate credential-sync errors from quota rotation between independently healthy provider accounts. Unknown or stale quota, cancellation, external controllers and operator changes still block selection.
- Confirm automatic selection through the original provider's readback before reporting success. Existing requests remain on their original account; requests are never replayed by account-pool management.
- Add read-only `--pool-control diagnose` history. The bounded, protected journal excludes emails, credentials, prompts and raw error messages.

## Validation

- 446 public regression checks passed with the CLT asserting XCTest-compatible harness; this is not Apple XCTest.
- New cases cover fractional quota thresholds, sync-failure isolation, cancellation, unknown quota, provider readback, operator-action records, journal bounds, permissions and corruption preservation.

This follow-up improves control isolation and future diagnosis. It does not establish the cause of a past incident whose per-check decision records were never retained.
