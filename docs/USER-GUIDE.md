# User guide

## Install and update

Use a release archive from this repository. Version 1.0.0 targets Apple Silicon
and macOS 14+. Unzip it, move **AILSA SubSwitch.app** to **Applications**, then
launch it. The app lives in the menu bar; closing its panel does not quit it.

The first release is ad-hoc signed, not Developer ID signed or notarized. After
attempting to open a trusted download, macOS may offer **Open Anyway** in System
Settings → Privacy & Security. Review the source and release checksum before
approving. If macOS reports a damaged archive, redownload and verify it first.

Each package has a SHA-256 file. In the download directory:

```bash
shasum -a 256 -c AILSA-SubSwitch-1.0.0-arm64.zip.sha256
```

There is no OTA updater in 1.0.0. Quit ASS from Settings before replacing the
application with a newer download. Replacing the app does not erase its separate
account store. Keep only one installed copy to avoid launching an older build.

## Add and switch accounts

Open **Accounts** and choose **Codex**, **Antigravity**, or **Cursor**. The entire
provider segment is clickable. Use the provider's own sign-in flow, then import
its current session into ASS. Repeat for another account you own or are
permitted to use. Importing does not create a provider account or subscription.

The active account's switch action is disabled. On another card, click the switch
icon. Depending on the provider and settings, its app may close and relaunch;
finish sensitive work in that app first. A failed or unverified native switch
must not be interpreted as a successful login just because a profile was saved.

Antigravity and Cursor depend on their installed native applications and local
session formats. If authentication has expired, sign in through the provider
again and re-import or reauthenticate. ASS does not bypass authentication.

## Read quota

Cards display the quota windows available from each provider, with remaining or
used percentages and reset times. Missing data is not a full allowance. Codex
reset credits and expiration dates appear when the provider reports them.

Use Settings → Quota Display to choose which windows to show. This changes the
presentation only; it does not alter your plan or its limits.

Smart switching is a toggle for supported providers. Antigravity requires native
credential access that can operate quietly; authorization failures leave the
feature unavailable rather than repeatedly opening a password dialog. Cursor
currently uses manual switching.

## Explore usage

**Quota Management** separates providers and defaults to **Today**. Choose 7 or
30 days for a longer view. Open the expand button for a standalone window.

- Model rows scroll inside their own rounded panel. Click a row for details.
- Today uses points connected by lines. Change the sampling interval and use
  horizontal trackpad gestures to move across the time axis.
- Hovering a sample temporarily shows that sample's totals and model breakdown.
  Leaving the chart restores the selected period.
- Settings offers M or B token units. They only change formatting.
- Reopening the usage window refreshes data; cached content can remain visible
  during a refresh. Cursor's first usage request can take longer.

The Codex dashboard prefers OpenCodex records when available and keeps that
source separate from the local Codex-session fallback. It does not sum both
sources together. Supported external model routes can appear when records
identify their actual model/provider and usage.

Antigravity's supported source exposes quota rather than itemized token billing.
Its quota history begins with locally captured observations. Do not compare
that chart directly with a token chart from a different provider.

## Understand USD values

An **API reference estimate** values recorded tokens against an identified rate.
It is not a subscription invoice or credit balance. Missing token fields,
unknown models and uncertain service tiers can make an estimate unavailable or
partial. Related model names may be grouped for readability without applying one
price blindly to every record.

Cursor amounts come from its usage API when reported. Data Details identifies
price sources and their verification dates where available. See [Privacy](PRIVACY.md)
for the inputs read by each provider.

## Compact cards and display preferences

In **Settings → Quota Display**, select Codex, Antigravity or Cursor:

- **Quota windows** controls which limits are visible; it does not change usage or switching policy.
- **Compact rings** (Codex and Antigravity) selects the first and second ring. Set
  a provider default or choose an individual account. Selecting the other ring's
  quota swaps positions; choose Hidden to omit a ring. Restore automatic selection
  or use provider defaults to remove an override. Hidden quotas remain hidden;
  an unavailable selected quota shows a dash instead of another quota's value.
- **Progress skin** offers Official logo colors and AILSA SubSwitch default
  (black, white and gray). It applies to this provider's bars and rings and follows
  light/dark appearance. Existing installations retain official colors initially.

Compact Antigravity rings label both the model family and time window. A single
Codex ring leaves room for the reset-credit count and balance. Reset credits are
listed individually in expiry order. **Settings → General → Reset credit dates**,
below Progress display, chooses Time remaining or Expiry date. This is independent
of Used/Remaining percentages. Countdowns update every second; missing dates stay
unknown and expired dates are labeled as expired.

For a newly reset 5-hour or 1-week window, the countdown waits until the provider
reports usage in that window. Reading quota alone does not activate a usage
window. **Settings → General → Automatic quota checks** can check the current
Codex or Antigravity account after switching, or all accounts during configured
work hours while the app is running. Work hours use local time; matching start
and end times means all day. These checks do not send model requests or activate
the provider's countdown.

In **Settings → Switch behavior**, **Open OpenCodex dashboard** opens the local
dashboard at `http://127.0.0.1:10100/`; OpenCodex must be running. The separate
editor restart controls apply after switching a Codex account: enable the toggle
and choose which installed editor to restart so it loads the new sign-in. Save
your work first. Choosing None skips the editor restart.

## About AILSA SubSwitch

Choose **Settings → About** from the settings tabs. This opens a page inside
the panel. It shows
the app icon, name, version, build time and tagline, with links to GitHub,
feedback and third-party notices. Version 1.0.0 has no update controls.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No menu bar icon | Check macOS menu bar visibility and any menu-bar manager's hidden items; confirm only one ASS copy is running. |
| Empty account list | Import a session after signing in to the corresponding provider app. |
| Quota is stale or unavailable | Refresh, check provider authentication/network access, and inspect the displayed error. |
| No OpenCodex token history | The ledger must exist locally and contain supported usage records; ASS cannot reconstruct missing usage. |
| Repeated Gemini Keychain prompts | Approve only the expected app/item. Development signatures can invalidate prior grants. Stable signing is deferred; do not grant access to all apps. |
| Cursor switch fails | Let Cursor close normally; unsaved work or a still-running process can block replacement. |
| Widget is unavailable | Widget packaging exists, but clean-device provisioning is not yet a validated 1.0.0 feature. Use the menu panel. |

Include your ASS version/build (Settings → About), macOS version and reproduction
steps in bug reports. Do not upload credential files, native profile databases,
private account exports, or unredacted usage screenshots.

## Browse and arrange accounts

All three providers use vertical scrolling instead of account pages. With cards
collapsed, Antigravity and Cursor use up to three columns; Codex uses up to two
columns to leave room for balances and reset credits. The standard panel fits
three rows of compact Antigravity cards. Smaller displays show fewer rows and
keep the rest reachable by scrolling.

Press and hold a card for a moment, then drag it before or after another card.
The other cards move into place. Each provider remembers its own order, including
after relaunch; new accounts are appended. This order does not change the smart
switching policy. VoiceOver also offers Move earlier / Move later actions.
Use the small switch button to change accounts; the current account's button is disabled.

Antigravity's compact-ring choices are grouped by model: Gemini 5h and weekly,
then Claude 5h and weekly. Existing custom selections are preserved. The automatic
selection shows the shortest visible window from each family, Gemini first.

Reset credits use Arabic numbers (Reset 1, Reset 2, and so on), one per line.
Settings → General offers countdown or expiry-date display and **d / h / m / s**
or Chinese countdown units. Countdown labels update each second; this does not
poll provider APIs each second or imply that an expired quota has refreshed.
