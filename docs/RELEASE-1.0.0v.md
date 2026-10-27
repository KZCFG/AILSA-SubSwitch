# 1.0.0(v)

This release adds explicit weekly-usage activation to account cards and fills API-equivalent pricing gaps for Claude pool routes and GPT-6.1 Terra.

- **Weekly usage controls.** Codex and Antigravity account cards show whether weekly usage is active. Clicking an inactive control sends one short request using that account. The control shows progress, preserves a durable success receipt, and becomes inactive again after the provider's weekly reset. Unknown, stale, or failed reads do not count as activation. Requests consume real quota; reset times remain provider-controlled. Generation failures are not retried automatically.
- **Claude pool pricing.** Antigravity Pool Opus, Sonnet, and Haiku records use the matching Anthropic standard API reference, including supported Thinking names and cached-input rates. Thinking tokens remain part of output and are not added twice. These amounts are API equivalents, not subscription charges.
- **GPT-6.1 Terra.** Added standard input, cached-input, and output reference pricing, the >272K long-context threshold, and confirmed Fast-mode pricing. Cache-write rates and source provenance are included; records whose cache-write duration is unavailable are not silently treated as ordinary input.

Official sources checked on October 27, 2026:

- [Anthropic API pricing](https://claude.com/pricing)
- [GPT-6.1 Terra model pricing](https://developers.openai.com/api/docs/models/gpt-6.1-terra)

The public edition contains no private ATC, Hub, account-pool credentials, or developer configuration.
