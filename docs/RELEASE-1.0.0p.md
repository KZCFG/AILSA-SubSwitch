## What changed

- Show a blue **Pool Active** badge on the Antigravity account actually selected by OpenCodex's routing pool. The native app's **Current** badge remains independent; an account may show both.
- Accept identity-confirmed quota readings for five minutes. Keep the last confirmed reading for up to fifteen minutes with a visible stale warning, including after a transient refresh failure. Stale readings may justify leaving the active account; replacement accounts still require fresh headroom.
- Identify whether the five-hour or weekly quota window is limiting the account. Exclude expired windows and reject future-dated or over-fifteen-minute-old readings.
- Explain skipped rotation decisions with exact remaining quota, threshold, delta, data age and limiting window. Keep the bounded diagnostic journal compatible with existing entries.
- Include the previous diagnostic improvements: separate credential-sync failures from healthy-account rotation, record manual actions distinctly, and verify selection through the original provider's readback.

## Validation

- 452 public regression checks passed with the CLT asserting XCTest-compatible harness; this is not Apple XCTest.
- Coverage includes 300/900-second boundaries, stale-current versus stale-candidate behavior, expired reset windows, precise comparisons, routing-pool identity and backward-compatible journal decoding.
- Native `swift test` could not start because the installed Command Line Tools are missing `SWBBuildService.framework`. Existing compiler warnings remain in unrelated native Keychain/concurrency code.

Selection affects subsequent requests. It does not replay or migrate an in-flight request, or establish the cause of a past incident without contemporaneous decision records.
