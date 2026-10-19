# AILSA SubSwitch 1.0.0(l)

Build **2026102003**. Reference API prices for DeepSeek V4.1 Flash, Hy3 and
Step 5 Preview now appear in usage dashboards, historical views and exported
Daily, Weekly and Monthly usage images, including the WorkBuddy routes.

USD per million tokens, checked against official documentation on October 20, 2026:

| Model | Uncached input | Cached input | Output |
| --- | ---: | ---: | ---: |
| DeepSeek V4.1 Flash, off-peak | $0.15 | $0.003 | $0.60 |
| DeepSeek V4.1 Flash, peak | $0.30 | $0.006 | $1.20 |
| Hy3 | $0.132 | $0.033 | $0.528 |
| Step 5 Preview | $1.00 | $0.10 | $2.70 |

- Recognize WorkBuddy's `deepseek-v4.1-flash` model ID and calculate each
  request from its original timestamp. DeepSeek peak hours remain 01:00–04:00
  and 06:00–10:00 UTC on weekdays, excluding Chinese public holidays.
- Use StepFun's own $0.10 cached-input rate rather than the $0.05 reseller rate.
  Cache-hit input is a subset of input; reasoning is already part of output.
- Recalculate historical reference amounts when records are read, without
  changing raw Token counts, stored routing identities or duplicate handling.
- Show consistent Hy3 and Step 5 Preview names. Priced rows remain visible
  when the optional unpriced-model filter is enabled for sharing images.

These are equivalent API reference amounts, not WorkBuddy subscription charges
or invoices. A free WorkBuddy multiplier does not set the reference API rate to
zero. Unreported usage, invalid token breakdowns and unknown model identities
remain unpriced. Existing account and usage layouts are unchanged.

Sources: [DeepSeek](https://api-docs.deepseek.com/quick_start/pricing/),
[Tencent Cloud](https://www.tencentcloud.com/document/product/1300/78937),
[StepFun](https://platform.stepfun.ai/docs/en/guides/pricing/details).

The app is ad-hoc signed for Apple Silicon, requires macOS 14 or later, and is
not notarized. Existing accounts and saved preferences are retained.
