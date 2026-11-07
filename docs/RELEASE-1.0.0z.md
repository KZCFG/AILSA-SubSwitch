# 1.0.0(z) — Account reset date display

Choose how quota reset times appear on account cards in **Settings → General → Quota reset display**:

- **Countdown** keeps the existing live remaining-time display and remains the default.
- **Date and time** shows the provider-reported reset date, year and time in this Mac's time zone, formatted in the selected interface language.

The preference applies immediately to the shared account-card reset labels for Codex, Antigravity and Cursor, and persists across launches. Reset-credit expiry display remains independently configurable.

Waiting-for-first-request, missing-time and imminent-reset states retain their existing behavior. This preference changes presentation only; it does not modify reset epochs, activate windows, refresh quotas or change account-switching decisions.

## Validation

Both editions pass the full command-line regression suites, including default preference behavior, local time zones, year boundaries, live countdown versus fixed dates, missing reset times and preference isolation. Native offscreen previews verify both modes and an in-place preference change without accessing saved accounts.
