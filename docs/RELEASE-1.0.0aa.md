# AILSA SubSwitch 1.0.0(aa)

## Fixed

- Preserve local Codex projects and supported local chat memberships when switching saved accounts, keeping target-account edits and existing project IDs.
- Quit Codex normally before changing credentials. Cancel the switch if quitting is rejected or the project-state format cannot be preserved safely.
- Keep private local backups and restore the previous selected card after a failed switch. Avoid restarting Codex during same-account token renewal.

## Scope

Local project navigation only. Cloud/remote projects and account identities remain separate. No detection-evasion mechanism or additional model request is introduced. This addresses a behavior still reported in CodexBar issue #5003; the same-email account fix in 0.84.0 is a different issue.

## Validation

Regression tests cover account round trips, target edits, cloud/remote exclusions, authentication failure rollback, cancelled quits, application restart races and unknown migration formats. A read-only projection checks the installed desktop's current project state. An interactive native account switch is not claimed while active user work is running.

The final regression run passed 547 public checks and 641 private checks, including 17 new project-continuity checks, using the CLT asserting XCTest-compatible harness. Read-only live-state projection retained all 10 current local projects for both other saved Codex accounts. No live desktop account change or model request was performed for validation.

Only the account-switch projection invokes the desktop quit and project transaction. Background credential maintenance can renew the same identity, but rejects a different known identity rather than closing the desktop or switching it implicitly.
