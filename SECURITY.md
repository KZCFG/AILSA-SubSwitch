# Security policy

AILSA SubSwitch handles local authentication state. Credential exposure,
incorrect-account switching and unsafe file replacement are security-relevant.
The current release line is 1.0.x; fixes will be prepared for the latest version.

## Report privately

Use [GitHub private vulnerability reporting](https://github.com/KZCFG/AILSA-SubSwitch/security/advisories/new)
(**Security → Advisories → Report a vulnerability**), enabled for this repository.
If that entry is unavailable, open an issue containing only “Private security
contact requested”—no exploit details, credentials, logs or affected account
identifiers—and wait for a private channel.

Include the affected version, a minimal synthetic reproduction, expected and
actual behavior, and the potential impact. Do not test against other people's
accounts, publish tokens, or send real credential files. We cannot promise a
response time or bounty.

## Important boundaries

- 1.0.0 is ad-hoc signed and not Apple-notarized. It has no OTA updater.
- Local account/profile files can contain secrets. File permissions are not a
  substitute for protecting your macOS account and backups.
- Provider sign-in formats and endpoints may change. A successful import is
  not proof that a subsequent native switch has succeeded.
- Repeated Keychain prompts across development signatures remain a known issue;
  weakening Keychain access controls is not an accepted fix.
