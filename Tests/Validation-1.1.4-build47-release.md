# 1.1.4 (47) release validation

## Scope and authorization

On 2026-10-23, the user explicitly stated that no physical iPhone Duo is available, authorized all feasible nonhardware tests, then a GitHub push and App Store review submission. This authorization overrides physical-device acceptance as a submission condition for this release; no hardware result is marked passed. Automated reports retain `physicalDeviceStatus=not_run` and `releaseReady=false` because they cannot grant publication authority.

Fresh App Store Connect read-back confirmed 1.1.3 (46) as available for distribution. This update uses 1.1.4 (47), built with Xcode 27.1 (27A9275), minimum iOS 27.0 for app and widget. The implementation is described in the [Duo candidate record](Validation-iphone-duo-20261023.md).

## Verification

The final source/config/test SHA-256 is `ec1cb3de8504d31cbecfffcf00b792b1f8c0f8b9555589f49233126a5c5ad6d6` (103 files). The working source and explicit 26-file allowlist copied to a fresh public-release clone match. The archive was built from that clean clone.

Signed Release archive and Apple Distribution export succeeded. Both exported targets are arm64, version 1.1.4 (47), minimum iOS 27.0, SDK 27.1, `get-task-allow=false`; strict deep signature verification, bilingual resources and absence of snapshot/benchmark/export-frames debug hooks passed. No app was installed on a physical device.

The first versioned unified run (`Build/regression-tKxx5P`) stopped at the existing 180-second native horizontal-jitter timeout, with no assertion failure reported. Concurrent simulator startup was consuming substantial CPU; the failure remains recorded. The prior candidate passed this gate in 56.103 seconds. This is not replaced with a relaxed threshold or treated as a pass; the full suite is rerun after QA devices shut down.

The stable-load full rerun passed **28/28 gates** (`Build/regression-DNqUzA/report.json`), using the same source fingerprint. Horizontal jitter passed in 47.344 seconds under the original 180-second timeout. Both unsigned Release builds, bundled Chinese/English resources and app/widget version/minimum-system consistency passed. The fixed 90-frame / 3-page output remains byte-identical to the pinned Build 35 baseline. All performance-stage budgets passed; algorithm total median was 1.6070 → 1.5841 seconds and sample p95 1.8294 → 1.5997 seconds across five warm measured pairs. These are simulator algorithm timings, not completion-to-Photos latency. Hardware fields remain explicitly not run.

Build outputs, device identifiers, UI hierarchies, signing material, receipts and screenshots stay in local ignored directories.

## Duo simulator UI

Native Device Hub pose controls produced actual rendered inner/outer UI, superseding the earlier candidate tool limitation. Open inner English home used a 951 × 669 landscape window; Partially Open confined controls to a roughly 435.7 × 669 region away from the fold. Rotating the partial pose produced a 669 × 951 window with controls in the bottom available region. Closed outer landscape was verified at 678 × 466 with maximum English accessibility type. Inner language switching, Settings → Done, Chinese guide scrolling at maximum type, and retained labels passed.

The final 1.1.4 (47) package was installed in place on the dedicated Duo simulator; product and installed metadata both read 1.1.4 / 47. Inner Chinese home → settings → Done returned correctly at 951 × 669. Independent screenshot review found no actionable clipping, overlap or unreadable controls in these states. This is static visual review plus the named interactions, not VoiceOver speech or hardware validation.

Arbitrary extremely narrow/short live app windows could not be established through supported Device Hub Resize mode; they are not marked passed. Controlled native preview tests cover small viewports and asymmetric system insets separately. Full guide paging, English guide maximum type and settings in the partial pose were not individually exercised. These are limits of this sampled UI pass, not reported successes.

All official interaction sessions ended; both dedicated QA simulators were restored to standard large type and shut down. Other simulators and physical devices were not altered. Detailed local evidence: `Build/duo-release-qa/validation-notes.md` and screenshots 01–12; none is published in GitHub.

## Limits

No physical Duo was used. Real cross-app ScreenCaptureKit capture through system consent, physical folding metadata, actual Dynamic Island/notification presentation, large-capture peak memory and completion-to-Photos latency are not claimed verified. Geometry handling uses native production-method tests with controlled metadata and pixel fixtures; actual simulator UI validates resizing and reserved regions.

Captured size/orientation changes produce separate native-size outputs. Target-app full-screen capture is required; visible Long Scroll in a partial window fails explicitly and retains originals. Unknown status-bar boundaries preserve full frames; automatic side-status-bar removal is not implemented. Store description, update notes and review instructions disclose these behaviors. Existing privacy settings, screenshots, price, regions and ratings are retained.

## Platform state

- Source commit `b856fa64eaebb895f84dde72fbced4bc5621ce4d` was pushed to the independent public repository `Alex-cloud0413/changjuan` main. `git ls-remote` and a second fresh clone confirmed it. All 26 allowlisted files matched byte-for-byte and all 103 source/config/test files matched the regression fingerprint.
- Xcode confirmed upload success at 2026-10-23 02:42 GMT+8 and reported the package processing. Both targets remain 1.1.4 (47). Upload success is not review submission.
- Version 1.1.4 was created and Chinese description, promotion, update notes and English review instructions were saved, refreshed and read back equal to the local source. Existing store screenshots were inherited. Automatic release after approval, immediate updates and retention of existing ratings were visually confirmed.
- Apple processing completed: TestFlight read back version 1.1.4, Build 47 as ready to submit. Build 47 was selected for 1.1.4, saved and read back, then added to the review submission.
- Formal submission completed on **2026-10-23 at 02:47 GMT+8**. The confirmation said one item submitted; the separate App Review detail page read back **Waiting for Review / 等待审核**, with exactly **1.1.4 (47)**. The screenshot and accessibility receipt remain in local ignored `Build/duo-release-qa/`.
- Approval and public availability of 1.1.4 remain pending. Version 1.1.3 (46) is the latest version freshly observed as available for distribution; 1.1.4 is configured for automatic release after approval. Submission is not publication. Internal platform identifiers and detailed receipts remain local.
