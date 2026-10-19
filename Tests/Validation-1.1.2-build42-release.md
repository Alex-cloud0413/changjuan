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
