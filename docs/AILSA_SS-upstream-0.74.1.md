# CodexBar 0.74.1 integration

Reviewed on 2026-10-13 against the [upstream release](https://github.com/steipete/CodexBar/releases/tag/v0.74.1).

| Upstream change | AILSA SubSwitch 1.0.0(i) |
| --- | --- |
| Cached-input reuse and cache sample coverage | Usage details show a token-weighted reuse rate over samples with an explicit valid cache breakdown, plus the sample count. Missing metadata is distinct from reported zero. Current period and hover aggregates use the same mergeable statistics. |
| Lower retained Codex reader memory | The native-session fallback now reads JSONL in fixed-size chunks with a bounded line buffer. It retains usage metadata only. The existing compact incremental primary ledger stays exclusive; sources are not summed. |
| Selected macOS SDK preserved in app and helpers | App and widget compilation and link metadata use the selected SDK; the packager validates their `LC_BUILD_VERSION` records. macOS 14 remains the minimum. |
| Settings/popup launch reliability | The public edition receives AILSA SubSwitch's verified menu-bar anchor placement guard and truthful repair result. |

The saved-conversation-title Cost menu, xAI invoice/credit panel and provider-specific menu hover option belong to upstream surfaces that this release does not expose. They are not advertised as implemented. No conversation content or credential database is imported. These changes are independent implementations of the documented behavior; no upstream source files are vendored.
