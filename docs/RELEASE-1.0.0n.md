## What's new

- Added explicit unified management for Antigravity account synchronization, manual selection and quota-based rotation.
- Takeover backs up and disables recognized legacy sync daemons; an external writer blocks managed operations instead of competing with them.
- Replaced direct account-file updates with the original OpenCodex locked store transaction, using identity checks, discovered project IDs and credential-generation comparisons. No proxy plugin or installation patch is required.
- Follow verified desktop identity changes once. Quota refreshes and pool rotation no longer pin the pool back to an unchanged desktop account.
- Admit saved accounts from Settings. New entries start paused; existing account IDs, custom labels, paused states and separate provider pools are retained.
- Added local maintenance commands with credential-free status output. Stopping management pauses managed automation and does not silently restore legacy scripts.

## Validation

- All 437 public regression checks passed with the CLT asserting XCTest-compatible harness; this is not Apple XCTest.
- Ten unified-management checks cover takeover failures, writer exclusion, identity transitions, preserved selection, credential generation and explicit admission. The existing 16 activation/pool checks are included in the regression run.
- Five worker transaction tests passed, including concurrent credential refresh, account metadata preservation, paused admission and provider verification requirements.
- Original OpenCodex 2.88.0 exposes the required locked-store capability without a plugin or installation patch.
