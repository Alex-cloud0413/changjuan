# Portrait status-bar crop regression — 2026-11-06

## Report and cause

The user reported that vertical capture with Keep status bar OFF still included a malformed compact Dynamic Island. GitHub main was read back as `db9c28b05e7bf8ff7581b5a098e94ba3fa46db7e`; its capture coordinator always stores `topCropRatio: 0`. The Duo change removed the own-window safe-area inference to protect target-app content, but supplied no replacement crop path. The existing `CaptureOverlayDetector` intentionally excludes normal compact islands. Thus OFF still appended the entire opening status strip. This is a code regression, not evidence that the preference failed to persist.

## Fix and preservation

- For zero recorded crop ratios, only vertical/OFF output prefixes run the new captured-pixel detector. The actual selected prefix JPEG supplies the proof: a spatially bounded clock and one complete rounded compact capsule with contrasting surround. Its full lower edge plus a small antialiasing pad must fit before the matched-content boundary; no clamp through the island is allowed.
- Unknown/dark/landscape layouts keep the full frame. Positive legacy crop ratios, Keep ON and horizontal behavior retain their existing semantics. No own-window safe area, device-model list, fixed output-height percentage or generated pixels is introduced.
- Detection happens once per selected explicit-page/geometry-group prefix after frame selection. Matching samples, preparation caches, source JPEGs, native width, page order, pagination and existing activity/system-sheet occlusion handling are unchanged.
- Settings explain the positive-proof behavior in Chinese and English.

## Evidence

- Real macOS Vision passed 12 synthetic assertions: native compact/tall/smaller captures, complete lower-edge check, clock position, missing clock/pill, rectangular header, dark and landscape negatives.
- An additional four checks read the user-authorized 1206×6051 result locally in place. Detected lower boundary: **177 native pixels**, below the complete island and above the app title. Source bytes were unchanged. The private image is not copied, emitted, bundled or committed. A stitched-result detector check is not raw-capture or physical-device acceptance.
- Focused native UIKit integration passed **31 assertions**: OFF/ON actual output height and retained title pixels, original top pixels when ON, legacy ratio, unknown preservation, reverse equality with varying capsule positions, prepared/unprepared byte equality, static explicit pages, independently sized geometry outputs and source-JPEG byte equality.
- A fresh-context independent reviewer found no actionable issue in bounds, Vision coordinate conversion, preference/axis gates, selected-frame origin, page/geometry paths or test oracles. The focused status suite does not directly exercise horizontal output; the full existing horizontal suites remain included.
- Full unified regression passed **29/29 gates** (`Build/regression-QIutSi/report.json`). Both standard unsigned Release builds and bundled bilingual resources passed; app/widget minimum iOS 27.0 remains synchronized. Source/config/test fingerprint: `bb4f9819108963c1ade9cc92db98e4eece1816965a1cd64fa51fa9dc5408e277`. The detector and both new tests are included in that coherent run.
- The fixed 90-frame / 3-page capture output stays byte-identical to the pinned Build 35 baseline. All existing performance budgets passed: simulator algorithm total median 1.2734 → 1.2810 seconds; sample p95 1.3083 → 1.3352 seconds. This fixed benchmark uses its recorded positive crop policy and does not measure real capture/Photos latency or per-page Vision cost.

## Environment and delivery

Xcode 27.2 (27B52), macOS 27.2 SDK, dedicated iOS 27.2 simulator for native executables; deployment target remains iOS 27.0. The earlier dedicated Duo runtime did not complete startup, so it is not counted as current runtime evidence. No physical device, real cross-app capture, Photos save or notification display was tested in this fix. No App Store release is claimed. Private inputs, simulator identifiers, test executables and logs stay outside tracked files.

The patch retains version identifiers 1.1.4 (47) for review; it has not been archived/uploaded as a new App Store build. A future distribution build needs its own version/build identifiers and platform validation.
