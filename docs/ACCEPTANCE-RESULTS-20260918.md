# September 18 acceptance results

**1.0.0 (2026091805) is built and installed locally. It is not approved or
published as a stable binary.** Two saved Antigravity grants require user sign-in,
and menu-bar visibility and several real interaction checks remain open.

This continuation used the existing dirty checkout at `1e1ea32`. Earlier changes
were retained. Source publication, artwork and MIT notices were not repeated.
The work followed [the acceptance plan](ACCEPTANCE-PLAN-20260918.md).

## Environment and build identity

- M3 Max, Apple Silicon; macOS 26.0 (25A354); Command Line Tools.
- Built-in display: 2056 × 1329 points; two external displays: 2560 × 1440
  points each. The built-in and left external display were observed; the right
  external display was not successfully validated.
- Bartender 6.6.2 was running for the successful menu/panel observations.
- Initial installed candidate: 1803. UI work and the compact-warning fix were
  exercised in 1804; current-identity correction, affected card UI and persistence
  were rechecked in installed 1805. Do not treat every 1804 check as rerun on 1805.
- Candidate and installed bundle: 20 matching files. App and widget signatures
  are ad-hoc; no Developer ID signing or notarization is claimed.

| Artifact | SHA-256 |
| --- | --- |
| 1805 application executable | `8c8a19ba761d122ab33de747e19572b08608b61b30053acb72ac7e6cb84776c5` |
| 1805 ZIP | `0e3ee5cdb2128fb0523ea57df6b8dd42e1efda4ffdd3d0f2e8e428ee5bf23cbd` |

The build's source manifest was compared with the final compilation inputs.
The ZIP is a private acceptance candidate and was not uploaded in this task.

## Corrections and regression evidence

1. Compact cards previously hid stale/error status when quota rings were present.
   They now retain a warning and the original successful-update time. Four new
   cases cover stale snapshots, failed refreshes, missing snapshots and fresh data.
2. A saved Antigravity current marker differed from the verified native session.
   Refresh now reconciles only that marker after fresh, verified native evidence.
   It does not switch accounts, change credentials or rewrite quota timestamps.
   Pending transactions and concurrent selection/credential changes take priority;
   an unknown or ambiguous verified native identity clears the old marker.
   Seven new cases cover these boundaries. Installed 1805 and final native
   readback agree on exactly one current saved Antigravity account.
3. The diagnostic driver no longer excludes the application delegate required by
   the quota window. It builds the full production module and links a narrow CLI.
   The driver build and production refresh/readback paths were exercised.

The final CLT asserting harness passed **299 cases, 0 failures, 38 classes**.
This is the repository's XCTest-compatible shim, **not Apple's XCTest runner**;
Swift Testing files are excluded. Native XCTest under full Xcode remains open.

## Real application observations

“Passed” below applies only to the action and build stated. Screenshots and AX
readback were used together; a successful automation response alone was not proof.

| Check | Build | Result and boundary |
| --- | --- | --- |
| Source build, app/widget signatures, versions, resources, no updater | 1805 | Passed; installed files match the candidate |
| Current native Antigravity identity | 1805 | Passed after correction, including final app restart; no provider switch performed |
| Failed Antigravity refreshes | 1804–1805 | Two production refreshes returned errors and retained the old fetched-at times; no borrowing of another account's native quota |
| Recovery of those two accounts | — | Blocked: Google OAuth `/token` returned HTTP 400 `invalid_grant`; no successful reauthentication yet |
| Compact stale/error warnings | 1804, 1805 | Passed visually and through AX; old numbers remain explicitly stale |
| Named compact rings and per-account order | 1804, 1805 | Changed a real account to Claude/GPT 5h then Gemini weekly; other accounts retained provider defaults; survived install/restart |
| Compact Codex layout | 1804 | Passed: one ring, credit count/balance beside it, three individually numbered reset-credit rows |
| Expiry versus countdown | 1804 | Changed via Settings; all three credit rows showed absolute expiry while quota percentages stayed in remaining mode |
| Per-provider progress skins | 1804 | Changed Codex, Antigravity and Cursor separately; preview/defaults readback passed; actual Codex and Antigravity monochrome cards inspected |
| Restored preferences | 1805 | Five test keys exactly restored and rechecked after restart; settings JSON unchanged; saved profile IDs retained |
| Status-item open/close and Escape | 1804, 1805 | Passed for the available status item/panel; visibility is separately conditional below |
| Menu-bar visibility | 1804, 1805 | Open gate: macOS host permission determines visibility in this environment |
| Outside click | 1805 | Unverified: background native automation click did not establish normal physical-click dismissal; Escape did dismiss |
| Light/dark appearance | 1804 | Both inspected; built-in and left external menu surfaces observed; system appearance restored |
| Provider/navigation controls | 1804 | Actual edge click, account/usage/settings navigation and collapse/expand worked; current card switch disabled |
| About | 1804 | Icon/name/version/build time/tagline and © 2026 KZCFG · MIT inspected; link controls present, destinations not clicked; leaving About preserved panel |
| Usage automatic refresh and ranges | 1804 | Open initiated refresh; Today/7/30 changed displayed data; selected provider range survived provider navigation |
| Model sorting/details | 1804 | Token/USD sorts changed order appropriately; details opened/closed while parent remained open |
| Model-list reachability | 1804 | AX scroll reached last of 18 rows without moving the summary/headings/chart; physical wheel/trackpad behavior not established |
| Today chart | 1804 | Point-and-line rendering inspected; hover and two-finger horizontal pan not tested |
| Usage labels | 1804 | Unknown prices and reference estimates remained explicitly labeled; Antigravity described quota snapshots rather than token/USD consumption |
| Cursor isolation/recovery | 1804 | Initial timeout stayed within Cursor; production reader returned account/history; later UI retry recovered, other providers remained usable |
| Cursor incremental cache | — | Not instrumented; no claim that all history avoids rescanning on every open |
| Separate quota window | 1804 | Opened, refreshed and closed; status app remained running; new window used its own default range |

## Menu-bar finding

ControlCenter logged the ASS status item under the launch host's tracked
application and moved it to the blocked list. Both ASS switches were enabled in
System Settings, but enabling the host entry displayed as “ChatGPT” restored ASS
visibility with Bartender still running. Disabling it again hid the item; a later
Finder launch did not remove the block. AX can still expose/open a hidden item,
so AX presence is not evidence that a user can see and click it.

This is a diagnosed local condition, not a completed source fix or a general
menu-manager compatibility pass. The temporary host permission was returned to
its original off state. Bartender is running and system appearance is restored.

## Remaining acceptance gates

- User-assisted login for both invalid Antigravity grants, followed by successful
  identity-bound refresh and fresh timestamps.
- Controlled import, refresh, A → B → A switch and remove of test profiles for
  each provider, including native identity and restart-setting readback. No live
  provider switch, restart, removal or login was performed in this continuation.
- A reliable visible status item in the intended display/menu-manager setup, plus
  physical outside-click, wheel/trackpad scrolling, chart hover and horizontal pan.
- Remaining Settings-to-dashboard M/B units, interval and quota-window checks;
  keyboard navigation, VoiceOver, Reduce Motion and non-Chinese localization.
- Native XCTest, clean-machine first launch/widget installation, Intel and other
  macOS/display configurations. Ad-hoc signing does not establish durable Keychain
  authorization.

The earlier 12-account synthetic harness remains historical 1803 evidence for
scrolling/reordering. It was not rerun here and does not substitute for the live
transaction checks above.

## Evidence and cleanup

Raw evidence is outside the public repository in the private
`acceptance-20260918-continuation` artifact directory. It contains the initial
diff/hashes/settings backup, build/test logs, redacted OAuth/native readback,
installed-file comparison, private screenshots and preference-restoration report.
Public screenshots continue to use synthetic data; live account screenshots,
identities and logs are not added here.

The three provider skins, reset-credit time mode and ring-choice preference were
restored with a comparison against the tested values to avoid overwriting a newer
user change. The original menu-bar permission and system appearance were restored;
the temporary launch job was removed. The installed app remains candidate 1805.
No source push or release publication was performed.
