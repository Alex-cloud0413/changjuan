# Photographic status-bar follow-up — 1.1.5 (49), 2026-11-06

## Problem and change

The user reported that Build 48 still retained the Dynamic Island with portrait Keep status bar OFF on a photographic header. Accurate native Vision successfully read the white clock; the missed crop came from dark photo pixels joining the capsule at the neutral-background threshold and from an absolute bright-surround requirement. Build 48's neutral-header checks did not cover this scene.

The neutral-background detector remains available. A separate photographic path requires strict black capsule geometry, a bounded rounded outline, local exterior contrast, a recording ring with a dark center, and the existing accurate native clock proof. It includes a proved lower detached recording circle in the crop boundary. Nearby recording-marked components are collected before shape verification: an uncertain circle joined to photographic darkness rejects the crop rather than disappearing from consideration. Unknown evidence preserves the source pixels.

Only the displayed/output status band is cropped. Captured native JPEGs, matching input and cache data stay intact. No fixed screen percentage, fabricated pixels or model-specific device dimensions were added. Main app and widget build numbers advance together to 49; minimum iOS remains 27.0.

## Validation

The final source passed a fresh coherent **31/31** regression run, `Build/regression-GEDlme/report.json`, including fixed performance budgets, byte-identical pinned 90-frame / 3-page baseline results, and unsigned device/simulator Release builds. Source/config/test SHA-256 (109 files): `1fc0dd8032fc81ed3f9fcc621a00b10708a79930f1ac3cd7a65d79d53c32d88f`. Xcode 27.2 (27B52), iOS 27.2 simulator; this does not establish physical Duo behavior. Focused native tests pass 52 assertions with each private image fixture. Both locally supplied result images were read in place: the photographic 1206×7273 result proves a 158-pixel boundary, and the prior 1206×6051 neutral result proves 177 pixels. In-memory JPEG0.9 encoding/decoding gives the same respective boundaries. No user image is saved, emitted or committed by these checks.

Synthetic fixtures cover textured/dim photo backgrounds, white clocks, detached lower recording circles, multiple native widths and tall captures; negatives include no clock/ring, unbounded dark content, plain black shapes and a recording circle joined to an uncertain photographic spur. The complete run passes 45 synthetic native Vision assertions and 86 UIKit integration assertions. UIKit checks cover OFF/ON, patterned split recording headers, exact native title/body pixels, reverse/cache/explicit/static pages and geometry groups. Independent review reproduced the uncertain-circle clipping before the final guard and confirmed `nil` after it; no further actionable finding remained in the changed detector.

## Installation and acceptance

The final standard Release archive and release-testing (Ad Hoc) export succeeded. Both exported arm64 bundles are 1.1.5 (49), minimum iOS 27.0, SDK 27.2, Apple Distribution signed, with strict deep signatures valid, `get-task-allow=false`, unchanged application identifiers/App Group and profiles containing the target phone. Chinese/English resources and absence of snapshot/benchmark/export-frame/test-hook entry points passed.

The connected iPhone was updated **in place from 1.1.5 (48) to 1.1.5 (49)**. Installation succeeded, a separate installed-app query read back exactly 1.1.5 / 49, and normal launch succeeded without arguments. No uninstall, manual cache-clear or preference-reset command was issued. Existing user recordings/photos were not inspected or exported.

The user can now repeat a new portrait capture of the reported photographic page with Keep status bar OFF and compare ON. That real end-to-end capture acceptance remains pending; installation/version read-back and launch do not establish it. No new App Store submission is part of this test-build follow-up. Private images, device identifiers, provisioning/signing material, packages and device receipts remain outside public Git.
