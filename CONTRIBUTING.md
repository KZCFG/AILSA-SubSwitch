# Contributing

Thank you for helping improve AILSA SubSwitch. Useful contributions include
provider-format fixtures, reproducible bug reports, accessibility checks,
translations, pricing provenance and macOS UI testing.

## Before changing code

Open an issue describing the problem and intended behavior for substantial
changes. Keep fixes focused. Preserve upstream attribution and do not introduce
credentials, private usage data or unlicensed copied code.

The app uses SwiftUI and AppKit. The source tree uses the AILSA_SS module name:

- `Sources/AILSA_SS/Features/`: accounts, quota dashboard, settings and About.
- `Sources/AILSA_SS/Behavior/`: account selection and switching coordination.
- `Sources/AILSA_SS/Infrastructure/`: local storage and provider integrations.
- `Sources/AILSA_SS/Domain/`: data models, quota/usage and localization helpers.
- `Sources/AILSA_SSWidgets/`: widget extension; clean-device validation remains open.
- `Tests/AILSA_SSTests/`: tests and synthetic fixtures.

## Build and verify

Use macOS 14+ on Apple Silicon with recent Xcode Command Line Tools and Python 3.
The direct build script is the tested packaging path and has no OTA dependency.

```bash
bash scripts/sync_version.sh --check
bash scripts/build_app.sh --output /tmp/ass-contribution-build
bash scripts/run_tests.sh --isolate
```

Output paths must be new. Version values come from `VERSION`.

`run_tests.sh` compiles and executes XCTest-style tests with an asserting local
shim. This lets contributors use Command Line Tools without full Xcode. It does
not claim Apple's XCTest behavior, skip accounting for Swift Testing files, or
substitute for native interaction testing. Tests importing `Testing` are not run
by this shim; report that gap explicitly. Focus a run with `--only ClassName`.

Xcode and SwiftPM project definitions are included, but this repository's public
build evidence is based on the direct script. Validate those alternative paths
before claiming compatibility with a particular Xcode version.

Before submitting, use [the interaction checklist](docs/TEST-CHECKLIST.md).
Account switching tests must use your own accounts and must not interrupt
someone else's active IDE session.

## Pull requests

Explain the user-visible change, why it is needed, the data/permissions it
uses, and exactly what you tested. Include a screenshot for UI changes using
synthetic data. State any checks you could not run. Keep unknown quota, prices
and identity unknown instead of substituting plausible values.

Use synthetic tokens and `example.invalid` addresses in tests. Do not include
local build products, Keychain exports, provider databases or private logs.
AI-assisted contributions are welcome; contributors remain responsible for
reviewing the result, licensing and tests.

## Community

Be specific, patient and respectful. Critique code and behavior, not people.
Harassment and sharing someone else's private data are not acceptable. Security
reports belong in the private process described in [SECURITY.md](SECURITY.md).
