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

Edit `VERSION`, then run `bash scripts/sync_version.sh`. Marketing version is
1.0.0; `ASSBuildLabel` supplies the visible revision `1.0.0(a)`, while the numeric
bundle build remains `2026092201` (date plus revision). Build numbers remain
monotonically increasing. Archive names include the visible revision and build
number. The application identifier
is `com.ailsa.subswitch`; the widget is `com.ailsa.subswitch.widgets`.

The existing `CodexToolsSwift` data directory, provider credential identifiers,
legacy widget group and `copool` URL scheme remain for compatibility. No account
database is renamed or deleted by replacing the application.

## Publish

Follow [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md). Review the exact source tree
and artifacts, create a version tag, and attach the ZIP plus checksum to a GitHub
release. The repository homepage must accurately state whether the package is
published, signed and notarized. Do not attach private build logs or account data.

Future stable signing and OTA work is deferred in [ROADMAP.md](ROADMAP.md).
