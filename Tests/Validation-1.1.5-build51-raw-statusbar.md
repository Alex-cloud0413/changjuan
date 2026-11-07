# Original status-bar export — 1.1.5 (51) device-test candidate

## Final requested behavior

The user withdrew the Build50 cleanup approach: Keep status bar ON must preserve exactly what was captured at the top, including the Dynamic Island, recording circle, time and battery. OFF retains the verified captured-pixel crop behavior. The UI and README now state that distinction directly.

All background-repair/mask/inpainting code, cached repaired prefixes and special settled-opening selection have been removed. Vertical rendering, generic frame selection, pagination, horizontal native-header rendering, capture and geometry behavior are restored to the validated Build49 implementation. ON performs no status-overlay erasure or background reconstruction. Normal existing JPEG output encoding still applies, so this is native-image preservation rather than a claim of lossless JPEG bytes.

The only stitcher difference from Build49 is the already tested strict clock OCR fallback: retry the existing allowed clock range at the proved capsule's vertical bounds, preserving full time syntax, uniqueness and native coordinate checks. It supports OFF detection on photographic backgrounds. It does not alter vertical ON pixels. The earlier Duo geometry/background-entry/boundary/atomic-publication fixes remain intact. Both app and widget advance to 1.1.5 (51), minimum iOS 27.0.

## Verification

Source review confirms no remaining cleaner/inpainter/repair-mask/patched-prefix/special-opening-selector symbols. Render, pagination and selection functions match Build49. Focused native Vision checks passed 52 assertions with an in-place local photographic fixture; its 158-pixel OFF boundary agrees after in-memory JPEG 0.9 encoding. Native UIKit integration passed 179 assertions, including separate original full-top/clock/island/recording-circle/battery ROIs, raw expanded animation despite a later compact frame, fractional/scaled photo headers, reverse/cache/legacy paths, horizontal export and explicit/static/geometry pages. Original fixture JPEGs remain byte-identical.

Standard Release archive and Ad Hoc export succeeded. Both arm64 bundles are 1.1.5 (51), minimum iOS 27.0 / SDK 27.2, Apple Distribution signed with strict deep signatures valid, original identifiers/App Group, target-phone provisioning and no developer hooks. Binary checks also confirm the removed repair/selector classes are absent. Bilingual resources and capture-setting integration contracts passed. The final coherent full run passed **31/31** gates, `Build/regression-Sn9Xgx/report.json`, including fixed performance budgets, byte-identical pinned 90-frame/3-page baseline outputs, unsigned device/simulator Release builds and an unchanged before/after source/config/test fingerprint (109 files): `638ba082336d5a20cdbc089d6e7e9a8fb965d0e2f9e02b4439ecfeb85114aca3`. Xcode 27.2 (27B52), iOS 27.2 simulator.

Private user images, previews, packages, device identifiers and receipts remain outside public Git. Build50's historical record is marked withdrawn. No App Store submission is performed for this device-test candidate; user end-to-end capture acceptance remains pending.

## Installation and acceptance

The final standard Release/Ad Hoc package was installed **in place from 1.1.5 (50) to 1.1.5 (51)**. A separate installed-app query confirmed 1.1.5 / 51. Normal no-argument launch succeeded; its executable belongs to the newly installed app, and an independent process query confirmed it remained running. No uninstall, manual cache clear or preference reset was issued.

User end-to-end acceptance remains pending: make a new capture with Keep status bar ON and confirm the actual recorded island/recording controls/time/battery remain as captured; compare OFF cropping. Previous Photos results are not rewritten by installation. No physical Duo acceptance or App Store submission is claimed.
