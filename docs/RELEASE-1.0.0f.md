# AILSA SubSwitch 1.0.0(f)

Build: **2026093001**. Add DeepSeek V4.1 Flash Token and equivalent API usage
accounting for the ATC local route.

## DeepSeek V4.1 Flash

- Recognize `atc-deepseek/DeepSeek-v4.1-Flash-EXL3` and show it as
  **DeepSeek V4.1 Flash** in model breakdowns and usage exports.
- Keep actual input/output Token counts from reported usage. Cache hits remain
  part of input and reasoning remains part of output; neither is added twice.
- Calculate the equivalent API amount from the official `deepseek-flash` price
  table, which currently serves DeepSeek V4.1 Flash. The exact local provider/model
  mapping does not establish a vendor charge or a quality equivalence for EXL3.
- Recalculate existing history when it is read. There is no need to sign in again
  or rewrite the original usage ledger. Other model prices are unchanged.

## Official USD reference

The [DeepSeek price table](https://api-docs.deepseek.com/quick_start/pricing) was
checked on September 30, 2026. Prices below are per **1 million tokens**:

| Period | Input, cache miss | Input, cache hit | Output |
| --- | ---: | ---: | ---: |
| Peak | $0.30 | $0.006 | $1.20 |
| Off-peak | $0.15 | $0.003 | $0.60 |

- Each record uses its own request timestamp. Peak hours are **01:00–04:00**
  and **06:00–10:00 UTC**, Monday–Friday, excluding Chinese public holidays.
  Window end times are exclusive. All other hours use off-peak rates.
- Fix the existing Flash reference calculation to honor Chinese holidays.
  The [official 2026 holiday schedule](https://www.gov.cn/gongbao/2025/issue_12406/202511/content_7048922.html)
  is included. Weekends stay off-peak even when designated as make-up workdays.
- No holiday calendar is invented for an unverified year. A potentially peak
  record in such a year remains unpriced; known off-peak hours still work.
- Missing cache details retain a partial estimate. Missing/estimated usage,
  aborted requests, unknown identities and inconsistent token fields do not
  receive invented costs. The confirmed-tier catalog remains unchanged.

## Validation and distribution

The full CLT asserting harness passes **360 tests across 48 classes** on M1,
including request-time boundaries, holiday rates, cache accounting and identity
checks. This is not Apple's XCTest runtime. The Apple Silicon package is
ad-hoc signed and not notarized; see the [release checklist](RELEASE-CHECKLIST.md).

Equivalent API amounts are reference estimates, not actual DeepSeek invoices,
subscription charges, or the operating cost of local hardware.
