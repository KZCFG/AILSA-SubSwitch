# 1.0.0(y) — HY4, Kimi K3.1 Pro and CodeBuddy reference pricing

This update closes the unpriced model rows found in a real seven-day usage audit.

- **HY4:** combine hy4std and hy4free into one HY4 display row, preserving original route identities, request deduplication and Token counts. Apply Tencent's published USD reference and its 50% promotion through December 31, 2026 (Beijing time); restore list price automatically afterward.
- **HY3:** recognize its exact CodeBuddy CN route and price input, cache hits and output with Tencent's official USD reference.
- **Kimi K3.1 Pro / HighSpeed:** add official global USD prices. HighSpeed doubles ordinary input and output rates; the cache-hit rate stays $0.20 per million for both. Keep the two variants separately labeled.
- **GLM 5.3 / Flash / FlashX:** map the exact gateway IDs to their published Z.AI rates. Correct FlashX's display family so it does not fall through into GLM 5.3.
- Reprice existing saved usage on load. Do not rewrite source ledgers, fill missing Token counters, infer invoices, or modify provider configuration.

A Free route can have an API-equivalent reference value without implying that the user paid that amount. Existing share-image privacy and model filtering continue to apply.

## Official references

- [Tencent model pricing](https://www.tencentcloud.com/document/product/1300/78937)
- [Kimi global API pricing](https://platform.kimi.ai/docs/pricing/chat)
- [Z.AI model pricing](https://docs.z.ai/guides/overview/pricing)

## Validation

Both editions are checked with the same fixed seven-day route sample, source-identity and Token preservation, rate fixtures, HY4 promotion boundaries, HighSpeed cache behavior, grouping, and the full command-line regression suites. Public artifacts exclude private ATC implementation and configuration.
