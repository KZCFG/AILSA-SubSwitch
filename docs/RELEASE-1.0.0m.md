## What's new

- Added an opt-in Antigravity 5-hour quota activation setting, separate from read-only quota checks.
- Choose the current account or all saved accounts during local work hours, including overnight schedules.
- Fully reset, unused quota pools receive one short request after a staggered 1–5 minute delay. This uses real quota; it is not a guarantee against provider risk controls.
- Durable claims prevent repeated requests after failures, restarts or sleep. No automatic model fallback is used.
- Countdown evidence is recorded only after provider-confirmed generation; weekly reset times remain provider-reported.
- Optional local OpenCodex pool controls use original management APIs, with per-account ranges, stable cycle thresholds and conservative 30-second checks while SubSwitch runs. No proxy patches are required.
- Existing settings migrate with request activation disabled.

## Validation

Local application and routing regression results are recorded separately from live provider acceptance.
