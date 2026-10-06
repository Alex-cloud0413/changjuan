# Control Center icon refinement — local Build 29

## Design contract

- Preserve the three brand stroke centerlines; do not change the desktop App icon.
- Increase the Control Center mark's occupancy and stroke thickness, using filled
  vector paths in a native monochrome template symbol. Let iOS supply tint and
  the control background; add no custom glass, circle or color.
- Use the same symbol for the capture and next-page controls. Do not change
  capture, stitching, notification or navigation behavior.
- Apply the apple-design skill's native-symbol and proportional visual checks.
  Apple source: https://developer.apple.com/documentation/uikit/creating-custom-symbol-images-for-your-app

## Changes

- `LongJuanCaptureV3.symbolset` retains the three-stroke geometry. Regular-M
  increases the drawing scale from 0.16 to 0.24 and the base outline width from
  26 to 50 source units. Small/medium/large use 0.783 / 1 / 1.29 ratios; compatible
  Ultralight-S / Regular-S / Black-S paths provide small-scale weight sources.
- Both ControlWidget labels reference V3. V2 remains for comparison/history.
- The new asset name distinguishes the resource from cached V2 artwork.

## Verification on 2026-10-06

- Apple `actool` compiled baseline and V3 catalogs without symbol errors.
- `ControlIconVisualCheck.swift` loaded the compiled images as symbol images and
  passed all nine regular/semibold/bold × small/medium/large visibility,
  occupancy and clipping checks at 24 pt, 3× rendering.
- Medium regular ink bounds: before 46×60 px; after 72×94 px. The native-rendered
  comparison is a fixture, not a screenshot of the actual Control Center.
- Existing capture improvements regression suite passed, including reverse /
  revisit byte equality, segmented-page ordering and startup overlay recovery.
- Xcode 27 RC Release build succeeded; deep/strict signature verification passed.
- GYM iPhone updated in place from 1.1.0 (28) to 1.1.0 (29), read back using
  CoreDevice, and launched successfully. Existing app data was not cleared.
- Actual Control Center appearance on the physical phone awaits user inspection.

## Release boundary

This is a local test build. The project still specifies Build 28; the device
build used `CURRENT_PROJECT_VERSION=29` as a command-line override. No Git commit,
GitHub push, App Store upload or replacement of the submitted Build 28 occurred.

## Evidence and rerun

Evidence directory, relative to the workspace root:
`tmp/longshot-control-icon-20261006/`.
It includes compiled baseline/new asset catalogs, comparison PNG, pixel metrics,
build/regression logs and device install/version/launch JSON.

Compile `Tests/ControlIconVisualCheck.swift` with `swiftc -parse-as-library`, an
iOS simulator target and SDK. Run via `simctl spawn` with three absolute arguments:
the baseline resource bundle, the new resource bundle, and the output directory.
Each resource bundle contains `Assets.car` and its own minimal `Info.plist`.
