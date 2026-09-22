# AILSA SubSwitch 1.0.0(a)

Build: **2026092201**. This revision updates model pricing and Antigravity
compatibility without changing the account or usage dashboard layouts.

## Grok 4.7

Recorded Grok 4.7 usage now appears in its own model family and receives an
official API reference estimate. The Grok Build `grok-4.7-build` identity maps
to the same reference family without being treated as an exact confirmed API
identity. Historical records through other supported routes remain readable.

The [xAI pricing table](https://docs.x.ai/developers/pricing) and
[Grok 4.7 model page](https://docs.x.ai/developers/models/grok-4.7) were checked
on September 22, 2026. Rates match Grok 4.6:

| Global API rate, USD per million tokens | Input | Cached input | Output |
| --- | ---: | ---: | ---: |
| Prompt below 200,000 tokens | 2.00 | 0.50 | 6.00 |
| Prompt at or above 200,000 tokens | 4.00 | 1.00 | 12.00 |

Long-context rates apply to all tokens in the request. Confirmed Priority/Fast
processing uses twice the standard rate. Selecting Fast locally does not prove
it was granted. These global reference estimates do not include the US regional
endpoint premium or server-side tool fees and are not subscription bills.
The new model carries its own audit date; older entries retain their dates.

## Antigravity compatibility

Antigravity 2.15.1 exposed a bug in the previous forward-compatibility check:
Go stores its OAuth strings as pointer/length pairs, so requiring a trailing
NUL incorrectly rejected valid native configuration.

The resolver now checks the arm64 initialization of the two OAuth configuration
fields, matches each known public client ID to its explicitly referenced secret,
and verifies Google's code signature for newer builds. It does not infer client
identity from string order or borrow nearby strings. Ambiguous bindings and
unrecognized layouts remain unavailable. OAuth client secrets stay in memory;
they are not added to the repository, account snapshots, or logs.

Expired or revoked account grants remain separate authentication failures and
are not repaired by this compatibility change.

Validation includes the CLT asserting test harness (328 passed, 0 failed),
synthetic packed-string/reversed-order/malformed-layout regressions, the installed
Antigravity 2.15.1 binary's consumer and GCP configuration resolution, and three
successful account refreshes through the production coordinator. The live checks
returned four quota pools per account using native or account-scoped remote
sources. The harness is not Apple's XCTest runtime.

## Distribution

The visible app version is `1.0.0(a)` and the monotonic build is `2026092201`.
The app and widget retain their bundle identifiers and existing local data.
Packages are ad-hoc signed and are not notarized. Source publication and the
binary draft are separate from the remaining stable-release acceptance checks.
