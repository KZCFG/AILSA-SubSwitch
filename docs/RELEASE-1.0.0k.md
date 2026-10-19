# AILSA SubSwitch 1.0.0(k)

Build **2026102001**. Control which model details appear in shared usage images.

- Add **Settings → Quota display → Usage sharing images → Hide models without
  a USD amount**. The option is off by default and is saved across launches.
- Apply it to Daily, Weekly and Monthly PNG exports. Hide only model rows whose
  USD amount is unavailable; models with an explicit **$0.00** stay visible.
- Preserve complete Token totals, reference-USD totals and trends. Images state
  when model details have been hidden, including periods with no priced models.

This is an export presentation preference. It does not change account cards,
usage dashboards, stored records, provider prices or switching behavior.

The macOS package is ad-hoc signed for Apple Silicon, requires macOS 14 or later,
and is not notarized. Existing account data and settings are retained.
