# CodexBar 0.77.0 integration review

Reviewed against [CodexBar 0.77.0](https://github.com/steipete/CodexBar/releases/tag/v0.77.0),
published October 16, 2026 (UTC). AILSA SubSwitch is a separate application;
provider support and data contracts determine which upstream changes apply.

## Adapted in 1.0.0(j)

### Native Codex history scanning

CodexBar [#4552](https://github.com/steipete/CodexBar/pull/4552) replaces expensive
byte-marker searching in large message bodies. ASS now uses bounded raw-byte
search for JSONL newlines and usage markers, and skips unrelated conversation
rows before JSON decoding. Unicode-escaped metadata still takes the JSON parser
path. The existing 1 MiB line limit, chunk boundaries, incomplete-tail handling,
cumulative token deltas, cache coverage and ledger-primary selection remain.

A synthetic, optimized M1 benchmark scanned 23,244,000 bytes with 1,200 token
records. Three paired runs took 150–158 ms before and 24–25 ms after this change
(about 6.5 times faster at the median); each returned exactly 132,000 fixture
tokens. This measures the reader/parser workload, not end-to-end UI latency or
real-world background CPU. No conversation content was used in the benchmark.

### Antigravity subscription labels

CodexBar [#4571](https://github.com/steipete/CodexBar/pull/4571), fixing
[#4565](https://github.com/steipete/CodexBar/issues/4565), addresses paid accounts
reported as Free by generic tier metadata. ASS now prefers explicit `paidTier`
metadata in both native and OAuth responses. An unidentified but explicit paid
tier displays `PAID`; measured five-hour quotas suppress a conflicting `FREE`
label without guessing Pro or Ultra. Identity-mismatched, disabled and unknown
quota buckets do not provide that evidence. Account cards and widgets also
suppress a stale stored Free label when the same verified snapshot contradicts it.

## Already covered or not applicable

| CodexBar change | ASS assessment |
| --- | --- |
| Antigravity widget reset times (#4529) | Already passed through from measured quota buckets. Regression coverage verifies the absolute reset and preserves ASS's first-request evidence rule. |
| Bounded Codex database titles (#4550) | ASS uses a short session identifier, not a prompt or database fallback title. No full prompt is retained as a title. |
| Claude sleep inhibitors (#4544) and Dock window rescans (#4516/#4524) | The affected polling/window-scanning paths are absent. No equivalent service was added. |
| Claude desktop sessions, per-account costs, tcr pools, forecasts and Platform links | ASS has no Claude account provider. Supporting a new provider requires its own authentication, storage and switching design. |
| Gemini App, Future AGI, Munito, OpenCode Go and Qwen Cloud | These sources are not implemented in ASS. OpenCodex ledger support is a separate format from OpenCode Go history. |
| HTTP usage server and SSH cache fallback (#4430/#4554) | Public ASS has no usage CLI/server. Adding a listener is outside this compatibility update. |
| Spend menu items, plugin gauges, forecasts and six-day workweeks | ASS already exposes reference costs in Usage Management, but does not implement these forecast/plugin concepts. No quota or pricing semantics were changed. |
| Settings history navigation and projected-exhaustion menu selection | ASS has different settings and account-selection flows. Its existing navigation and explicit quota choices are preserved. |
| Plan-renewal wording and Claude Cloud widget credit metadata | The corresponding renewal/Claude Cloud fields are not part of ASS's data model. |
| Browser-cookie rejection/import permissions | ASS uses native credentials and provider-specific authentication, not the affected CodexBar browser-session store. |
| Homebrew refresh recovery | ASS has no Homebrew updater. |
| Inactive-display menu rendering and confetti | The affected rendering paths are absent. |
| Test-home isolation and detached CLI fixture cleanup | ASS uses injected fixture paths for these tests, has no CodexBar cost cache or detached CLI fixture helper. No runtime home or credentials are changed. |
| Indonesian Keychain text | ASS's current translations do not include Indonesian. |

The CodexBar MIT attribution is retained in the bundled third-party notices.
