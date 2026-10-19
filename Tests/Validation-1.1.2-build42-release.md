# 1.1.2 (42) release validation

Validated on 2026-10-19 with Xcode 27 RC. Minimum supported system: iOS 27.0.

## Scope

Horizontal table alignment now tolerates repeated columns, small vertical drag jitter and backtracking. Fixed floating control groups are preserved once, using authentic overlapping pixels to restore content that was captured unobstructed. Source images, output resolution and JPEG quality are unchanged. Capture startup recovery and bounded local numeric diagnostics are also included.

## Evidence

- All 26 automated regression gates passed, including capture entry, picker lifecycle, overlay handling, explicit finish, tail frames, reverse/revisit, cross-page assembly, cache parity and cleanup, notifications, localization, horizontal tables and jitter, Release builds and control symbols.
- The focused floating-control suite passed 100 assertions at 1× and 3× resolution. It verifies complete controls and shadows, original image preservation, genuine body-pixel recovery, cache parity, and negative cases for blue table content, plain glyphs, square cards and transient controls.
- Original-size vertical, 90-frame / 3-page comparison preserved byte-identical outputs against the accepted baseline. No measured phase exceeded the existing performance-regression budget.
- Matched horizontal comparison used 16 synthetic 1170×2532 frames, warm prepared analysis, equal 3810×2532 output dimensions and five alternating pairs after warm-up. Median algorithm total was 0.8465 seconds before and 0.8379 seconds after; assembly was 0.2533 and 0.2552 seconds. No material regression was observed on this fixture. These simulator measurements are not physical-device finish-to-Photos latency.
- Standard signed Release app and widget both report 1.1.2 (42), iOS 27.0. Strict signature and bilingual resources checks passed. Developer snapshot, benchmark and frame-export launch hooks are absent from the package.
- Build 42 was installed in place on the connected iPhone and the installed version was read back. The user accepted the result and authorized GitHub and App Store submission on 2026-10-19.

Device recordings, screenshots, device identifiers, detailed diagnostics, signing material and install packages remain outside the repository. App Store submission and public availability are recorded separately after platform read-back.

## Release read-back — 2026-10-19

- Source commit `25f51263a0d1b60db8cd4bf9276c5792acc4d965` was pushed to the independent `Alex-cloud0413/changjuan` repository. GitHub `main` was read back with `git ls-remote`; no app source was pushed to the workspace repository.
- The clean release checkout matched the 26-gate report source fingerprint: `056a64969de032fe736740143f6b1cb9b6c67be4badd1de064928981d2ff9451`.
- Xcode archive and App Store upload completed successfully. Apple processing finished; Build 42 was bound to version 1.1.2 and saved with updated release notes and review instructions.
- App Store Connect confirmed one submitted item, **1.1.2 (42), Waiting for Review**, at 22:29 GMT+8. Automatic release on approval, immediate availability of the update and retention of existing ratings remain selected.
- The existing public version was still 1.1.1. Review submission is not approval or public availability. Existing store screenshots were retained; no private user screenshots were uploaded.
