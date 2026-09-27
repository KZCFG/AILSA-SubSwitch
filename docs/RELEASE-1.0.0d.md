# AILSA SubSwitch 1.0.0(d)

Build: **2026092801**. Grok Build Fast now contributes its equivalent API
reference amount to the Grok 4.7 usage group, including previously recorded usage.

## Fixed

- Recognize the resolved `grok-4.7-build-fast` route as a user-selected Grok 4.7
  reference mapping. Its Token usage and equivalent API amount appear together
  under Grok 4.7 in Today, 7-day and 30-day views.
- Recalculate existing local history when it is read. No sign-in, ledger edit
  or record deletion is needed. Other model totals remain unchanged.
- Retain Grok 4.7's cached-input discount and long-context threshold: prompts
  below 200,000 tokens use $2 input / $0.50 cached input / $6 output per million
  tokens; prompts at or above 200,000 use $4 / $1 / $12 for the entire request.
  Rates were checked against the [official pricing page](https://docs.x.ai/developers/pricing).
- A route name containing Fast does not prove Priority processing. Priority
  rates still require an explicitly confirmed grant. Reference mappings do not
  enter the separate vendor-confirmed pricing catalog.

## Validation

- Regression coverage includes the Fast alias, cache discounts, the exact
  long-context boundary, confirmed versus unconfirmed Priority, missing model
  identity, request deduplication and unchanged unrelated model records.
- Historical replay verifies that Token totals remain identical and only the
  newly supported route gains reference pricing. No private usage records or
  personal screenshots are included in this release.
- The full CLT asserting harness passes 339 tests across 45 classes. This is
  not Apple's XCTest runtime.
- The Apple Silicon package is ad-hoc signed and not notarized. See the
  [release checklist](RELEASE-CHECKLIST.md) for validation scope.

Equivalent API amounts are reference estimates, not subscription invoices or
actual charges. Records without usable usage or pricing stay unavailable.
