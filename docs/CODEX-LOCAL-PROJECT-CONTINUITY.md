# Codex account switching and local project continuity

Codex desktop 26.1103 scopes renderer navigation by a hash of the real user and account IDs. A newly selected account may therefore have an empty project sidebar while the previous account retains its local project snapshot. This does not establish deletion of the underlying project directories or chats.

AILSA SubSwitch preserves local project navigation when it performs an explicit Codex account change:

1. Request a normal quit of the Codex desktop bundle and wait for it to finish. Cancellation or timeout stops the switch; no force-kill is used.
2. Read the final state after exit, validate the account owner and known renderer schema, and save a private backup under `~/.codex/subswitch-project-backups/`.
3. Merge this computer's local project directory and supported local chat memberships into the target account's navigation snapshot. Existing target names, order, assignments and explicitly unassigned chats take priority. Keep core project ID mappings and reconcile only local assignments.
4. Write the selected account's unmodified identity and normal credentials, then honor the existing launch preference. The native application performs its own owner selection.

Cloud and remote projects, browser sessions, private renderer atoms, workspace selection, account IDs, user IDs and server authentication are not copied or forged. This does not make an account change invisible to the service. It adds no model request, telemetry suppression or identity spoofing. Same-account token renewal does not quit Codex or rewrite project state.

Unknown or conflicting formats fail before credentials change. State backups use private directory/file permissions. A failed credential write restores the exact previous project-state bytes when they have not subsequently changed. A failed switch restores SubSwitch's previous selected card. Changes made outside SubSwitch are outside this transaction.

Upstream review on 2026-11-08: [CodexBar 0.84.0](https://github.com/steipete/CodexBar/releases/tag/v0.84.0) fixes same-email saved-account replacement and other usage/history issues. The matching [project visibility issue #5003](https://github.com/steipete/CodexBar/issues/5003) remains open; it does not establish an upstream fix for this behavior.

Validation separates fixture account transitions and read-only live-state projection from an actual interactive native account switch. A production desktop switch is not run while the user's Codex work is active.

Only the account-switch projection invokes the desktop quit and project transaction. Background credential maintenance can renew the same identity, but rejects a different known identity rather than closing the desktop or switching it implicitly.
