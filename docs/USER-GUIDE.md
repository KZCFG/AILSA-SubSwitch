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
shasum -a 256 -c AILSA-SubSwitch-1.0.0l-2026102003-arm64.zip.sha256
```

There is no OTA updater in 1.0.0. Quit ASS from Settings before replacing the
application with a newer download. Replacing the app does not erase its separate
account store. Keep only one installed copy to avoid launching an older build.

This update is **1.0.0(l)**. DeepSeek V4.1 Flash, Hy3 and Step 5 Preview
now have official USD reference amounts, including WorkBuddy usage. Existing
history is recalculated when read, and the same amounts reach exported images.
DeepSeek retains request-time peak/off-peak pricing; Step 5 Preview uses the
vendor's $0.10 per million cached-input tokens. A free WorkBuddy route still has
an equivalent API reference value. See [the pricing table](RELEASE-1.0.0l.md).

Revision **1.0.0(g)**: **GPT-6.1 Sol** now contributes reported Token
usage and equivalent API amounts to model breakdowns, Today/7-day/30-day charts
and image exports. Historical records are recalculated when read, with no need
to sign in again. Standard pricing is $2.00 input, $0.10 cached input and $10.00
output per million tokens. Full-request long-context and vendor-confirmed Fast
prices are supported. These are API reference estimates, not subscription bills.
See the [pricing details](RELEASE-1.0.0g.md).
Small updates use letter revisions such as
**1.0.0(a)**, **1.0.0(b)**, and **1.0.0(c)**.
Larger feature releases change the numeric version. The date-based build number
identifies the exact package.

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

## Read usage

Cards display the usage windows available from each provider, with remaining or
used percentages and reset times. Missing data is not a full allowance. Codex
reset credits and expiration dates appear when the provider reports them.

Use Settings → Usage Display to choose which windows to show. This changes the
presentation only; it does not alter your plan or its limits.

Smart switching is a toggle for supported providers. Antigravity requires native
credential access that can operate quietly; authorization failures leave the
feature unavailable rather than repeatedly opening a password dialog. Cursor
currently uses manual switching.

## Automatic refresh

Opening the menu refreshes visible Codex and Antigravity subscriptions.
Returning to Accounts or selecting a provider also requests fresh data.
Cursor rechecks the current native account on each presentation. In-flight
reads are reused; older quota stays visible until a fresh result arrives.

Usage Management refreshes on entry, provider changes and Today / 7-day /
30-day selections. Its top-right time is the last successful scan, so failed
requests retain the previous time and show an error. Cursor automatically
refreshes recent history; its refresh button reloads the complete history.

## Explore usage

**Usage Management** separates providers and defaults to **Today**. Choose 7 or
30 days for a longer view. Open the expand button for a standalone window.

- Model rows scroll inside their own rounded panel. Click a row for details.
- Today uses points connected by lines. Change the sampling interval and use
  horizontal trackpad gestures to move across the time axis.
- Hovering a sample temporarily shows that sample's totals and model breakdown.
  Leaving the chart restores the selected period.
- **Settings → Usage Display → Usage chart display** selects **Token usage** or
  **Equivalent API consumption (USD)** for Today, 7-day and 30-day charts,
  including daily and weekly grouping. The saved choice updates open usage
  windows immediately and is independent of model-list sorting.
- Settings also offers M or B token units. They only change Token formatting.
- USD charts use the same amounts as the summary cards. Unpriced records stay
  unavailable; Antigravity continues to show quota percentages.
- Reopening the usage window refreshes data; cached content can remain visible
  during a refresh. Cursor's first usage request can take longer.

The Codex dashboard prefers OpenCodex records when available and keeps that
source separate from the local Codex-session fallback. It does not sum both
sources together. Supported external model routes can appear when records
identify their actual model/provider and usage.

Antigravity's supported source exposes usage percentages rather than itemized token billing.
Its usage history begins with locally captured observations. Do not compare
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

In **Settings → Usage Display**, select Codex, Antigravity or Cursor:

- **Usage windows** controls which limits are visible; it does not change usage or switching policy.
- **Compact rings** (Codex and Antigravity) selects the first and second ring. Set
  a provider default or choose an individual account. Selecting the other ring's
  usage window swaps positions; choose Hidden to omit a ring. Restore automatic selection
  or use provider defaults to remove an override. Hidden usage windows remain hidden;
  an unavailable selected usage window shows a dash instead of another usage window's value.
- **Progress skin** offers Official logo colors and AILSA SubSwitch default
  (black, white and gray). It applies to this provider's bars and rings and follows
  light/dark appearance. Existing installations retain official colors initially.

Compact Antigravity rings label both the model family and time window. A single
Codex ring leaves room for the reset-credit count and balance. Reset credits are
listed individually in expiry order. **Settings → General → Reset credit dates**,
below Progress display, chooses Time remaining or Expiry date. This is independent
of Used/Remaining percentages. Countdowns update every second; missing dates stay
unknown and expired dates are labeled as expired.

For a newly reset 5-hour or 1-week window, the countdown waits for explicit
evidence that a model request was observed in that window. Reading usage alone
does not activate a usage window, and legacy unverified markers are cleared.
**Settings → General → Automatic usage checks** can check the current
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
| Usage is stale or unavailable | Refresh, check provider authentication/network access, and inspect the displayed error. |
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
poll provider APIs each second or imply that an expired usage snapshot has refreshed.

## Export a usage image

In Codex or Cursor usage, click **Export usage image** in the top-right toolbar.
Choose Daily for one date, Weekly for the 7 days ending on that date, or Monthly
for the 30 days ending on that date. These are rolling windows, not calendar
weeks or months. Select **Generate and save**, then choose a folder and filename
in the native save dialog. Finder reveals the saved PNG.

Reports use the saved chart metric and Token unit from Settings. Daily charts
show 30-minute intervals; longer reports show daily totals. Current periods
include a cutoff time. Historical availability depends on locally retained
records; an empty period cannot be exported.

The image contains aggregates and model names, with no accounts, credentials,
request IDs, conversation contents or local paths. API amounts are reference
estimates, never an actual bill; unpriced or inconsistent records are excluded
from the monetary sum. Antigravity remains a separate quota-snapshot interface.

### Hide unpriced models in sharing images

In **Settings → Quota display → Usage sharing images**, enable **Hide models
without a USD amount** to omit those model rows from Daily, Weekly and Monthly
PNGs. This preference is off by default and is saved across launches. A model
with an explicit $0.00 amount stays visible. Token totals and charts still
include all usage, and the image notes when model details have been hidden.
This does not change the usage dashboard, stored records or pricing.


### Optional five-hour quota activation

Read-only quota checks do not send model requests. Settings → Account pool has a separate setting that can activate unused Antigravity five-hour pools during local work hours. It is disabled by default, including for existing users. After fresh quota confirms a fully reset pool with no request evidence, the application schedules one very short request with a 1–5 minute delay. Requests consume real quota; random timing or prompt variants do not guarantee avoidance of provider risk controls. No model fallback is used. Weekly resets stay provider-reported.

The application must remain running. Claims are saved before dispatch, so failed or ambiguous requests are not automatically retried, including after restart. Each account and model-family pool is attempted at most once every five hours. Unknown/stale quota, an unverified portable credential, or a native-session-only account is skipped. Requests never switch the official app sign-in or execute tools. Work hours support crossing midnight; equal start and end times mean all day.

### Unified Antigravity pool management

In Settings → Account pool, take over unified management before changing pool membership or enabling range-based rotation. Takeover verifies the original OpenCodex runtime, backs up recognized legacy sync scripts and launch-agent files, and disables those services. It does not modify the proxy installation, merge provider namespaces or rewrite the official IDE login markers. If a known external writer returns, managed mutations and activation pause.

SubSwitch synchronizes changed portable consumer grants for existing pool members using verified Google identity and the credential's discovered project. A short-lived worker calls the original OpenCodex locked store transaction. Credential-generation comparisons prevent stale scans from overwriting a newer proxy refresh; unrelated providers, IDs, labels, paused flags and active choice are retained. Expired or incompatible grants must first be refreshed normally in SubSwitch. New saved accounts require explicit admission from Settings and are initially paused. Legacy exclusions are not interpreted as a global rule that merges or deletes another provider pool.

The desktop-follow preference responds to verified SubSwitch or IDE identity changes, not file modification times or quota updates. Enabling management establishes a baseline without changing the currently selected pool account. Proactive quota rotation uses stable per-account ranges and fresh measurements as before. Original proactive rotation is suspended while SubSwitch owns management; stopping management restores its previous preference if it is still owned. Reactive rate-limit handling remains in the original proxy. The app must stay running. Stopping management also pauses activation for that managed installation; the legacy daemon is not automatically restarted.

For local maintenance, run the application's executable with `--pool-control status` or `--pool-control verify`. Status prints counts and control flags without tokens or email addresses. `takeover`, `check` and `stop` mutate control state and should only be used with the user's authorization. `check` performs synchronization and permitted pool selection, not a model activation request.

### Account-pool decision diagnostics

Settings → Account pool shows the last completed rotation decision separately from credential-sync time. The current model-family remainder is displayed to two decimals; it is the smaller remaining allowance across five-hour and weekly windows. Threshold decisions retain full precision. For example, 3.0685% is above a 3% threshold even if an account card rounds it to 3%.

A local bounded journal keeps the last 512 decisions and explicit selection/range changes. It contains numeric control metadata and account IDs, not credentials, email addresses or request contents. Run the application executable with `--pool-control diagnose` for read-only diagnostic history. Credential-sync failures are reported separately and do not block rotation between already healthy provider accounts with fresh verified quota. A successful selection is confirmed through provider readback. Existing requests continue on their original account until completion or cancellation; automatic account selection does not replay them.


### Pool selection badges and quota freshness

Antigravity cards distinguish the native desktop **Current** account from the blue **Pool Active** account used by the OpenCodex routing pool. These identities can differ, and the same card can carry both badges. Pool metadata is checked while the account page is visible; a failed metadata lookup clears the pool badge instead of presenting a cached selection as current.

Identity-confirmed quota is fresh for 300 seconds. A last confirmed reading up to 900 seconds old remains visible and is marked stale. A recent failed quota refresh also marks that reading stale. Stale active-account data can trigger departure at its existing threshold, but stale accounts cannot be chosen as replacement targets. Unknown, future-dated, expired-window or older readings cannot provide headroom. The limiting 5h/1w window, data age and precise decision reason are included in the protected local diagnostic journal.


## Claude local usage and longer reports

Choose **Usage → Claude** for local Claude Desktop **Code-mode** usage. Token
counts come from locally recorded assistant usage, with streamed repeats
deduplicated. API-equivalent USD includes supported cache lifetimes and pricing
modifiers; it is not a Claude subscription bill. This feature never queries
Claude online quota and does not require a login, API key or Keychain access.
Ordinary Chat sessions and activity missing from local logs are not included.

The share dialog supports **Daily**, **7 days**, **30 days**, **60 days**,
**90 days** and **Year (365 days)**, ending on your selected date. Annual
trends group by week; all other multi-day reports use days. Totals always cover
the entire selected interval. Only available records are included; selecting a
year does not recreate deleted or never-recorded history.
