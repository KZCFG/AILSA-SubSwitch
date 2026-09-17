# Third-party notices

This file ships inside the app bundle (`Contents/Resources/THIRD_PARTY_NOTICES.md`)
and records known third-party code and reference sources in AILSA SubSwitch. File-level status for every source
file is tracked separately in `docs/PROVENANCE.md`.

## Copool — original Swift contributions (MIT confirmation received)

AILSA SubSwitch is derived from Copool (<https://github.com/AlickH/Copool>,
upstream baseline `3cb6ede534bdbff86804e9beaed567a190dac2f3`). On 2026-09-17,
Alick confirmed in writing that his original Swift contributions to Copool
are licensed under MIT and may be modified and redistributed as part of
AILSA SubSwitch, with applicable copyright notices, license text and
attribution preserved. The maintainer retains the private correspondence;
private email addresses and screenshots are not distributed in this repository.

The public upstream LICENSE was also verified on 2026-09-17:
<https://github.com/AlickH/Copool/blob/main/LICENSE>. It preserves the
170-carry and Alick Huang / Copool contributor notices reproduced below.
The email confirmation covers only Alick's original contributions. Code from
170-carry/codex-tools and other third parties remains under its respective
license. See `docs/PROVENANCE.md` for the remaining provenance review.

The fork keeps the upstream account-store format and Keychain identifiers
(`CodexToolsSwift`, `~/.codex/auth.json` handling) so existing local data stays
readable; those identifiers originate upstream.

MIT License

Copyright (c) 2026 170-carry
Copyright (c) 2026 Alick Huang and Copool contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## CodexBar — UsageProgressBar visual structure (MIT)

The compact single-Canvas, 6pt flat progress-bar structure in
`Sources/Copool/UI/LiquidProgress.swift` is adapted from
[`UsageProgressBar.swift`](https://github.com/KZCFG/CodexBar/blob/86a47f80a71e74c59dd2d4dd14de397348d36546/Sources/CodexBar/UsageProgressBar.swift)
in CodexBar. This product replaces its provider tint with independently
implemented provider icon spatial fields and does not include CodexBar's pace
or marker logic.

The Cursor and Antigravity usage readers (`CursorUsageService.swift`,
`AntigravityUsageService.swift`, `AntiGravityAuthRepository.swift`) were written
with CodexBar's provider implementations as a behavioural reference (endpoints,
local file locations). The full MIT notice below is included conservatively for all such reuse. An
exhaustive line-level originality comparison has not been completed.

MIT License

Copyright (c) 2026 Peter Steinberger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Data read from other tools (no code included)

The app reads, but does not bundle code from, these local files written by
other programs. Their formats belong to their respective projects:

- OpenCodex usage ledger `~/.opencodex/usage.jsonl` and its verified pricing
  bindings JSON (read-only; used for the Codex quota dashboard).
- Codex CLI `~/.codex/auth.json` and `~/.codex/config.toml` (read and rewritten
  on account switch).
- Antigravity `~/.gemini` credentials and `Antigravity.app` bundle metadata
  (the OAuth client secret is read from the installed app at runtime and kept
  in memory only; it is not stored in this repository).
- Cursor `…/Cursor/User/globalStorage/state.vscdb` (`cursorAuth/*` rows) for
  account switching and the `WorkosCursorSessionToken` cookie for usage calls.

## Removed in this fork

The upstream local API proxy (`proxyd`, derived from codex-tools / Tauri,
Rust sources and prebuilt binaries), Cloudflare tunnel management, remote SSH
deployment, the OpenAI Codex Electron JavaScript snapshots at the repository
root, and the upstream screenshots were removed from this fork in September
2026 and are not part of the app or its build. Backups live outside the
repository for review only.

