# 1.0.0(x) — DeepSeek Harness usage accounting

DeepSeek Harness desktop usage now joins the combined Token and API-equivalent USD dashboard, including daily charts and custom-range share images.

- Read native v4 JSONL and Zstandard sessions through the installed Harness Node runtime. No additional global runtime installation is needed for the supported desktop layout.
- Normalize Harness's disjoint ordinary-input, cache-read and cache-write counters once; output and reasoning are not added twice.
- Keep the newest durable sample within an attempt, retain separately billed retries, and prefer existing OpenCodex records when the same response identity is present. Similar Token counts alone do not establish duplicates.
- Price DeepSeek Flash (DeepSeek-V4.1-Flash-1017) and V4 Pro at each request's published USD rates, including actual peak/off-peak periods, cache hits, weekends and the supported 2026 holiday calendar.
- Recover complete checksummed frames while a log is being appended; leave unfinished frames for the next refresh. Unknown or invalid usage is not fabricated.
- Keep all reading local: no Harness agent startup, credential import, online quota polling or model requests. Conversation text is not returned by the usage helper or included in exports.

Amounts are API-equivalent references, not subscription invoices. Separate Search/Fetch charges are not inferred from Token counters. Custom/private deployment profiles are excluded from this public edition.

[Official DeepSeek pricing](https://api-docs.deepseek.com/quick_start/pricing)
