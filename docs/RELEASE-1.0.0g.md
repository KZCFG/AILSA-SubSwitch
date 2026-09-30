# AILSA SubSwitch 1.0.0(g)

Build: **2026100101**. Add GPT-6.1 Sol usage and equivalent API cost accounting.

## GPT-6.1 Sol usage

- Recognize the exact `openai/gpt-6.1-sol` route and display **GPT-6.1 Sol**
  separately from GPT-6 Sol. Preserve reported input/output tokens and cache
  details without counting cached or reasoning tokens twice.
- Include its equivalent API amounts in model breakdowns, Today/7-day/30-day
  charts and Daily/Weekly/Monthly usage images.
- Recalculate existing records when read. No re-login, ledger rewrite or
  account reimport is required. Other model prices and audit dates are unchanged.
- Reject out-of-range numeric Token fields safely instead of crashing while
  loading a malformed record.

## Official USD reference

The [GPT-6.1 Sol model page](https://developers.openai.com/api/docs/models/gpt-6.1-sol)
and [API price table](https://developers.openai.com/api/docs/pricing) were checked
on October 1, 2026. Prices below are per **1 million tokens**:

| Context / mode | Input | Cached input | Output |
| --- | ---: | ---: | ---: |
| Standard, up to 272K input | $2.00 | $0.10 | $10.00 |
| Standard, over 272K input | $4.00 | $0.20 | $15.00 |
| Fast, up to 272K input | $4.00 | $0.20 | $20.00 |
| Fast, over 272K input | $8.00 | $0.40 | $30.00 |

- Exactly 272,000 input tokens uses short-context rates. Above that threshold,
  the full request uses twice the input/cache rates and 1.5 times the output rate.
- Fast is twice the applicable Standard rates. Apply it only with consistent
  vendor-confirmed Fast/priority evidence; a requested mode or bridge echo alone
  does not prove a grant. Unknown tiers keep a Standard reference estimate.
- Official cache-write pricing is $2.50/M for short Standard requests. The v1
  ledger does not establish cache-write overlap semantics, so nonzero cache-write
  records remain unpriced rather than receiving invented charges. Regional,
  Batch and Flex adjustments are not inferred from requested settings.
- Strict confirmed-tier bindings remain separate from reference estimates and
  require exact provider/model/context/tier evidence.

## Validation and distribution

The M1 command-line test runner passed **370 tests across 49 classes**. A
historical replay of **61,380 unique records** preserved all Token totals and
all previously priced model amounts. The newly recognized GPT-6.1 Sol records
also matched an independent price calculation.

The Apple Silicon package is ad-hoc signed and not notarized. Native XCTest and
a clean-machine installation have not been run; see the
[release checklist](RELEASE-CHECKLIST.md).

Equivalent API amounts are reference estimates, not subscription invoices or
actual charges.
