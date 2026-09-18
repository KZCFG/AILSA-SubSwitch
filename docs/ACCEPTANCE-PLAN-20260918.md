# 1.0.0 acceptance continuation — September 18, 2026

## Baseline and scope

Continue in the existing writable checkout, preserving every pre-existing dirty
change. Initial HEAD: `1e1ea32`; source and installed app report **1.0.0,
2026091803**. Confirm source provenance and installed hashes before attributing
new results to a build. Do not repeat source publication, logo work or MIT notices.

Historical evidence: 288 passing CLT asserting-harness cases and the synthetic
12-account interaction harness. These are neither Apple XCTest nor acceptance
of the installed application's live account transactions.

## Ordered plan and to-do list

- [x] Inspect the dirty tree, version, existing release/readiness/test checklists.
- [x] Record a private baseline: source hashes/diff, installed bundle metadata and
      hashes, macOS/displays, running app and menu bar manager.
- [x] Recheck both saved Antigravity accounts using the production refresh path;
      record identity binding, source, fetched-at time and error state without
      exposing credentials. Diagnose errors before changing behavior.
- [x] Confirm a failed/mismatched/unverified refresh cannot turn cached quota into
      fresh quota. Add focused regression coverage if a defect is found.
- [ ] Exercise the installed menu bar panel and available display/Bartender
      configuration: visibility, open/close, Escape, outside click, navigation,
      independent windows and repeated interactions.
      Partial: open/close, Escape, navigation and separate windows passed;
      visibility is conditional on a local macOS menu-bar setting. Outside click
      remains unverified with background automation.
- [x] Exercise the five requested display behaviors in the real app: named
      compact rings and persisted order; one Codex ring with credits/balance;
      individual reset-credit rows; independent expiry/countdown preference;
      per-provider official/AILSA progress colors.
- [ ] Exercise quota dashboard navigation, sorting, model details, scrolling,
      hover/pan, refresh isolation and accurate unknown/reference labels.
      Partial: navigation, sorting, details, AX list scrolling, isolation and
      labels passed. Physical gestures and hover remain unverified.
- [ ] Complete account transaction coverage with controlled test profiles and
      native identity readback; never interrupt unsaved provider work.
- [x] Record accessibility, display, clean-machine/widget and platform coverage
      explicitly, including checks that require another environment/user input.
- [x] If fixes are needed, run focused tests, the CLT suite and a fresh source
      build; verify bundle/version/resources/signatures and install only the
      concrete candidate needed for acceptance. Repeat affected UI checks.
- [x] Reconcile TEST-CHECKLIST, RELEASE-CHECKLIST and readiness notes with exact
      evidence, and restore temporary display/system preferences.
- [ ] Recover the two invalid Antigravity grants with user-assisted sign-in and
      complete the remaining live transaction/display checks before publication.

Current result: **2026091805 built and installed; not released as stable**.
See [the evidence matrix](ACCEPTANCE-RESULTS-20260918.md).

## Delivery self-check standard

For each check record: build identity, environment, action, observed result,
evidence location and status (`passed`, `failed`, `blocked`, `not run`, or
`historical`). A source review proves implementation only; an asserting harness
proves its assertions only; a signed archive proves packaging only; installation
proves placement only; actual clicks and readback prove the exercised behavior.

Fresh quota requires a new successful fetch plus verified account identity and
source. Preserve the old timestamp and an explicit stale/error state on failure.
Never replace unknown data with fabricated percentages, balances or consumption.

Keep raw screenshots, logs, account mappings and backups outside the public
repository. Public acceptance notes use aggregate or synthetic data. Before
delivery review the diff for accidental deletions, secrets and unsupported claims;
check version consistency and distinguish source, package, installation,
interaction acceptance and publication. Unchecked gates remain unchecked.

## Procedure

1. Capture the baseline and reversible settings before interaction.
2. Run read-only/refresh checks, then UI actions with before/after observations.
3. Diagnose any failure; apply the smallest justified correction in this tree.
4. Verify the correction at the appropriate level and restore test-only settings.
5. Update the evidence matrix and release decision. Missing evidence is not a pass.
