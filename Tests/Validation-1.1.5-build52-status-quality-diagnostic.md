# Status-bar quality attribution — 1.1.5 (52)

Status: diagnostic device-test candidate. The user's original Photos JPEG still has a soft clock/battery region. This build does not claim to fix that symptom, and is not an App Store submission candidate.

## Behavior and boundary

The production capture, frame selection, native renderer, JPEG quality and Photos file-URL save path are unchanged from Build 51. Keep-status-bar ON preserves the recorded island/recording indicators. OFF retains its validated captured-pixel crop. No cleanup, sharpening, substituted status bar or replacement library is introduced. App and widget versions advance together to 1.1.5 (52).

The temporary device package enables `LONGSHOT_STATUS_QUALITY_DIAGNOSTICS` in addition to the existing `LONGSHOT_SCREEN_CAPTURE_KIT` condition. Standard builds do not enable the diagnostic condition; its image collection code and calls are excluded at compile time. `LONGSHOT_CAPTURE_CHECKS` and developer launch commands remain excluded from the installed package.

## Private diagnostic samples

The diagnostic traces the first eight committed capture frames and at most two vertical outputs. Pending native strips/data are capped at 32 MiB, PNG storage at 64 MiB, and decoded full images at 16 million pixels; exceeding a limit skips diagnostics without changing the capture. The directory is excluded from backup. PNG work runs on a serial utility queue outside the capture state lock. Bounded native top strips are kept separately in the main app's Documents/LongShotStatusQuality directory, not in Photos or public Git. Starting a capture replaces only the previous owned diagnostic session; manual cache cleanup clears this diagnostic directory too. Normal recordings and saved results are not deleted by the diagnostic.

Four stages are compared only when the recorded source piece starts at source y=0 and destination y=0 with matching native width: capture image before JPEG; decoded persisted frame; compositor canvas before JPEG; decoded final output. The first stage is after the existing Core Image conversion/orientation, not an independent raw CVPixelBuffer dump. If it is already soft, incoming capture versus conversion still needs separation. Missing source samples, later pages and cropped pieces must be labelled unsupported rather than compared with an unrelated frame.

## Verification

Native synthetic diagnostics passed 8/8 groups, including PNG pixel identity, unchanged inputs, SHA/session/index/destination pairing, 8/2 limits, raw-cache cleanup after export, oversized JPEG headers, directory ownership and failure isolation. The diagnostic-enabled production pipeline passed all five native groups plus exact committed-JPEG hash and cleanup-preservation assertions. An independent final review found no further actionable issue. The four standard runtime files match Build 51 after excluding private diagnostic blocks and blank lines.

Release archive and Ad Hoc export succeeded with diagnostic conditions explicitly enabled. Both arm64 bundles are 1.1.5 (52), minimum iOS 27.0 / SDK 27.2, Apple Distribution signed, strict signatures valid, target phone provisioned, original identifiers/App Group, no developer test hooks. Chinese/English built resources passed. Runtime source fingerprint (59 paths): `dab31ae47422d66d6cc6481f5d7937cb62eee8612037056fb907c2c5f6dc0457`.

Final coherent unified run: **33/33** gates passed, including the two new diagnostic checks, fixed performance budgets, byte-identical pinned 90-frame/3-page baseline, and unsigned standard device/simulator builds. Standard Release binary checks confirm the image diagnostic and developer launch hooks are absent. Report: `Build/regression-mpHxR5/report.json`. Source/config/test SHA-256: `f2efbefa343d84cb40c07b99ff0adab0800f8be3b381d4275f8ee1b1aa55fd67`. The earlier simulated process-exit timeout did not count as a pass; the focused check and final unified run both exited successfully.

The signed diagnostic package was installed in place from 1.1.5 (51) to **1.1.5 (52)**. A separate app inventory query confirmed 52; normal no-argument launch and independent process lookup succeeded. No uninstall, cache clear, preference reset or automatic recording was issued. A new user capture is needed to obtain paired on-device status-bar samples.

Private image samples, device identifiers, provisioning material, native probe outputs and installation receipts stay outside public Git. Public research and test sources are recoverable from the feature branch. User capture acceptance and physical iPhone Duo coverage remain unverified; PR #2 remains a draft.
