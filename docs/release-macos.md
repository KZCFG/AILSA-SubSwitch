# Build and release

Version 1.0.0 uses manual GitHub distribution. It does not bundle Sparkle, contact
an update feed or require an Apple developer membership to build. The default
signature is ad-hoc; there is no claim of notarization or durable Keychain trust.

## Canonical build

Requirements: Apple Silicon, macOS 14+, recent Xcode Command Line Tools and Python 3.

```bash
bash scripts/build_app.sh
# Or choose a new output directory:
bash scripts/build_app.sh --output /tmp/ass-1.0.0
```

The script compiles source, assembles the app and widget, copies required assets,
resolves Info.plist, signs inner to outer, validates signatures, and writes a ZIP,
checksum and source manifest. It never copies an installed app or downloads an
updater dependency. Build time is embedded in `ASSBuildDate`; `SOURCE_DATE_EPOCH`
can override it for reproducible metadata.

Options: `--skip-zip`, `--no-sign`, `--output NEW_DIRECTORY`.
`release_macos.sh` is an alias for this manual packaging flow and never publishes.
A maintainer with a certificate may supply `CODESIGN_IDENTITY`; notarization is
not performed by this script. Do not describe such output as notarized without
separately completing and verifying Apple's process.

## Version and identity

Edit `VERSION`, then run `bash scripts/sync_version.sh`.

- Change the numeric marketing version for a larger feature release.
- For small updates to the same release, advance the lowercase suffix in parentheses:
  `1.0.0(a)`, `1.0.0(b)`, `1.0.0(c)`, and so on. Start the suffix sequence again when
  the numeric version changes. Letters denote maintenance revisions, not alpha
  or beta release status.
- Keep `CFBundleShortVersionString` numeric (`1.0.0` for this release);
  `ASSBuildLabel` supplies the full visible version (`1.0.0(b)`).
- Advance the internal `YYYYMMDDNN` build number for every packaged revision.
  The current build is `2026092301`; build numbers must increase monotonically.
- Use the same visible version in the app and GitHub release title. Use the
  portable tag `v1.0.0-b`; archive names omit parentheses so GitHub preserves the
  checksum filename: `AILSA-SubSwitch-1.0.0b-2026092301-arm64.zip`.

The application identifier
is `com.ailsa.subswitch`; the widget is `com.ailsa.subswitch.widgets`.

The existing `CodexToolsSwift` data directory, provider credential identifiers,
legacy widget group and `copool` URL scheme remain for compatibility. No account
database is renamed or deleted by replacing the application.

## Publish

Follow [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md). Review the exact source tree
and artifacts, create a version tag, and attach the ZIP plus checksum to a GitHub
release. The repository homepage must accurately state whether the package is
published, signed and notarized. Do not attach private build logs or account data.

Write GitHub release titles and notes in English, including control names and
date examples. Document the user-visible changes, fixes, and validation for each
revision.

Future stable signing and OTA work is deferred in [ROADMAP.md](ROADMAP.md).
