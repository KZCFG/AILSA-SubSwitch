# Privacy and local data

AILSA SubSwitch does not run a hosted account service, add telemetry, or upload
your account library to a project server. It does contact provider services for
authentication and quota, and uses local app interfaces where available. This is
not an offline-only application.

## Local storage

| Location or source | Purpose | Sensitivity |
| --- | --- | --- |
| `~/Library/Application Support/CodexToolsSwift/` | Saved accounts, settings, Cursor profiles/recovery state and local quota history | Can contain credentials and account identifiers |
| `~/.codex/auth.json` | Current Codex authentication; updated when switching | Credentials |
| `~/.codex/config.toml` | Codex configuration and endpoint selection | May contain private configuration |
| `~/.codex/sessions/`, `~/.codex/archived_sessions/` | Read token-usage metadata for the local fallback | Source files can also contain conversations; do not share whole files |
| `~/.opencodex/usage.jsonl` | Read OpenCodex model/provider usage | Usage and routing metadata |
| `~/Library/Caches/CodexBar/model-pricing/models-dev-v1.json` | Optional local pricing-cache fallback | Public rate metadata |
| Antigravity native state, `~/.gemini/`, relevant Keychain items | Import, verify and switch Google sessions | Credentials |
| `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` | Read/write the supported `cursorAuth/*` entries during switching | Credentials and other app state |
| Legacy widget shared container | Account quota snapshot for the optional widget | Account identifiers and quota |

The `CodexToolsSwift` directory name is retained for compatibility with Copool;
renaming the application does not migrate or delete it. Some credentials are
stored in local profile files, not exclusively in Keychain. Cursor profile and
recovery files are written with owner-only permissions. Treat backups of this
directory as sensitive.

## Claude local usage

The Claude usage tab is offline-only. It reads the Desktop Code session index
under `~/Library/Application Support/Claude/claude-code-sessions/` and matching
usage metadata under `~/.claude/projects/`. Source logs may contain conversations;
only model, timestamp, request identity and numeric usage projections are retained.
Do not share complete source logs. Ordinary Claude Chat usage is not included.

This feature does not read Claude cookies, authentication files or Keychain
items, contact a Claude quota or usage endpoint, or send model requests. Opening,
refreshing and exporting this tab re-read local metadata only. Official public
API rates ship with the application; no pricing request runs during normal use.

## Network behavior

The integrations use provider authentication and usage endpoints (including
OpenAI/ChatGPT, Google's OAuth and Cloud Code services, and Cursor), and native
Antigravity loopback RPC where supported. Codex configuration can select a custom
endpoint; such configuration remains under the user's control. ASS does not
bundle the OpenCodex relay or forward model prompts as an inference service.

The installed Antigravity application's OAuth configuration may be read at
runtime. The project does not distribute a maintainer's personal credentials.
There is no updater, update feed or background update download in version 1.0.0.

## Switching and authorization

Switching changes the local provider session and may restart that provider's app.
The operating system can request Keychain approval. ASS does not collect your
macOS login password. Background refresh should not turn a denied credential
request into repeated interactive prompts.

The first release has no Developer ID certificate. Rebuilding or replacing an
ad-hoc signed app can require a fresh Keychain grant. We do not claim that this
release permanently eliminates those prompts.

## Sharing a report

Prefer a minimal synthetic example. Remove emails, account/workspace names,
file paths, session IDs, request IDs, cookies, bearer tokens and API keys.
Diagnostic logging is opt-in; review even redacted logs before sharing. Never
attach `accounts.json`, `cursor-profiles.json`, `auth.json`, an entire Cursor
profile database, or a full Codex session log to a public issue.

For a suspected credential exposure, follow [SECURITY.md](../SECURITY.md).

## Native Antigravity usage metadata

The local Token reader uses read-only SQLite access to Antigravity App/CLI
conversation databases under `~/.gemini/antigravity/` and
`~/.gemini/antigravity-cli/conversations/`. A tokscale local sessions cache is an
optional fallback only when no native databases are present. Generation blobs
may also contain conversation content; the bounded decoder projects only model,
usage counters, timestamp and request/step identity. Conversation content is not
retained in usage aggregates, exported or uploaded. Do not share source databases.

This reader does not launch the Antigravity CLI, refresh OAuth, query quota or
send inference requests. Stable response identities are hashed for cross-source
deduplication. File caches are in memory and invalidated when main/WAL evidence
changes. Unverifiable or conflicting evidence stays excluded with partial coverage.

### DeepSeek Harness local usage

The desktop integration reads v4 session artifacts under `~/.dsh/sessions`. A bundled metadata-only script runs in the installed Harness Node runtime to decode JSONL / Zstandard logs and return model identities, timestamps, response identifiers and numeric Token counters. It does not load Harness plugins, account files or credentials, start an agent, send model requests, or poll online quota. Conversation text is not returned by the helper, retained by the usage reader, or included in share images. Incomplete writes are retried on refresh and unsupported records remain explicitly unavailable. USD values are published API-equivalent reference estimates rather than subscription invoices.
