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
