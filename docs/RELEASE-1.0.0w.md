# 1.0.0(w) — Complete model reference pricing

This update closes pricing gaps found in a real 30-day usage audit. It covers native Antigravity usage as well as supported routes recorded by OpenCodex.

- **Claude Sonnet 5.5 and Opus 5.5:** recognized effort suffixes such as `medium`, `high`, and `thinking` use their documented base-model API rates. Confirmed Opus Fast requests use the published multiplier.
- **Grok 4.5:** supported records with a separately reported reasoning counter larger than output now receive a labeled USD upper-bound estimate. The original input, output, reasoning, total Tokens, and route identity remain intact.
- **Composer 2.5 Fast:** adds Cursor's published input, cache-read, and output API reference rates. An xAI account alias uses this explicitly labeled equivalent reference, not a claimed xAI billing rate.
- **Native cache writes:** price records whose native input is known to include cache reads and writes. Missing Claude cache retention uses the highest published write rate and is marked as an estimate.
- Unknown model identities and other invalid counters remain visible for diagnosis instead of receiving an invented price. Share-image privacy and filtering continue to apply.

These are API-equivalent reference amounts, not subscription invoices. Existing saved records are repriced when the updated app reads them; no source ledgers or Token counters are rewritten.

## Official pricing references

- [Anthropic API pricing](https://claude.com/pricing)
- [xAI Grok 4.5](https://docs.x.ai/developers/pricing)
- [Cursor models and pricing](https://cursor.com/docs/models-and-pricing#cursor-models)

## Validation

Both editions pass their command-line regression suites, including exact-rate fixtures, effort variants, cache accounting, overflow guards, and unchanged Token/deduplication checks. The local 30-day audit is re-run against the updated accounting pipeline before release.
