# AILSA SubSwitch 1.0.0(e)

Build: **2026092803**. Export shareable usage images and include GPT-6 Sol
and GPT-6 Luna in equivalent API cost totals.

## Usage images

- Use **Export usage image** in the top-right toolbar of Codex or Cursor usage.
  Choose Daily, Weekly (7 days), or Monthly (30 days), plus an ending date.
- The native save dialog lets you choose a folder and filename. After saving,
  Finder reveals the PNG. Suggested filenames include the provider, period
  and date range.
- Images use the app's black-and-white layout, with summary cards, model
  breakdowns and a full-height chart. Daily charts show 30-minute totals;
  weekly and monthly charts show daily totals.
- Exported charts honor the saved Token/USD preference and M/B token unit.
  Current periods are labeled with their cutoff time; older dates retain
  their own minute-level history.
- Images contain usage aggregates only, without accounts, credentials,
  request IDs, conversation text or local paths. The Antigravity interface
  and public promotional images are unchanged.

## GPT-6 pricing

Official model pages were checked on September 28, 2026:

| Model | Input / 1M | Cached input / 1M | Output / 1M |
| --- | ---: | ---: | ---: |
| [GPT-6 Sol](https://developers.openai.com/api/docs/models/gpt-6-sol) | $2.00 | $0.20 | $10.00 |
| [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna) | $0.10 | $0.01 | $0.50 |

- Above 272,000 input tokens, the full request uses twice the input/cache
  rates and 1.5 times the output rate. Exactly 272,000 stays at short-context rates.
- Existing usage is recalculated when read. Token counts and other model
  prices are unchanged. Confirmed Fast pricing remains a separate pricing
  basis and requires actual vendor confirmation.
- Model-specific catalog additions keep older audit dates intact. Unpriced
  or inconsistent records remain unavailable instead of receiving invented costs.
- Includes the Grok Build Fast mapping introduced in 1.0.0(d).

## Validation and distribution

- The full CLT asserting harness passes 348 tests across 47 classes, including
  cache discounts, long-context boundaries, date ranges, daylight-saving time,
  historical minute loading, family grouping and unknown prices. This is not
  Apple's XCTest runtime.
- Native offscreen PNG checks cover all three report periods, Chinese and
  English layouts, and both Token and USD charts. Historical replay verifies
  unchanged Token totals and changes limited to the newly priced models.
- The Apple Silicon package is ad-hoc signed and not notarized. See the
  [release checklist](RELEASE-CHECKLIST.md).

Equivalent API amounts are reference estimates, not subscription invoices or
actual charges. Exported amounts sum the records that can be priced.
