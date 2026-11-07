# Duo regression follow-up — 1.1.5 (48), 2026-11-06

## Authorization and scope

The user asked for another audit of regressions caused by the Duo adaptation, fixes for evidenced problems, and in-place installation on the connected iPhone for their own real capture acceptance. This is a local test build; no App Store upload or approval is claimed. The source starts from the reviewed portrait status-bar patch `b07834c` on PR #2, based on public main `db9c28b`.

## Findings and changes

- Zero-ratio captures: portrait OFF crop uses actual selected prefix clock/capsule evidence; horizontal rendering and earlier table-layer analysis also need native status evidence. Unknown layouts preserve pixels. A shared horizontal crop cannot cut through a taller capsule on another explicit page. Matching must not reclassify real moving headings as fixed chrome merely because a fixed percentage extends below the status band.
- Cold background system intent: an inactive application with no visible scene must not inherit permanent host-foreground exclusion. A real foregroundInactive scene remains excluded. Actual scene geometry replaces transient UIWindow geometry for detecting unsupported partial-window capture; unknown/transitional geometry does not cause a false split-screen error.
- Pause/resume: explicit page boundaries commit with the next successfully persisted JPEG; resuming then immediately finishing no longer leaves a dangling empty page. Geometry and manual boundaries remain deduplicated.
- Orientation: metadata values normalize to the same CGImagePropertyOrientation transform used for pixels; geometry records validate the full active range, native dimensions and supported orientation domain.
- Output failure safety: render complete uniform/geometry output sets into staging and publish with a single directory rename/swap. Render or publication failure keeps previous result files and unrelated sidecars intact. Original JPEGs are never exchanged or deleted by publication.
- Feedback: saved thumbnails carry both geometry-separation and omitted-row warnings when applicable; compact/minimal activity accessibility describes the actual phase, and only capturing/paused phases advertise their actions.
- Existing preview bounds/inset/zoom/reading-anchor behavior was checked; no new defect was demonstrated. Ordinary home layout was retained rather than changed to satisfy an invalid hosting harness.

## Validation

The coherent full run passed **31/31 gates**, `Build/regression-itrCl6/report.json`. Source/config/test SHA-256 (109 files): `95bfc75b956490b8492ac0658bd9abb9922f6b738aefd4ff72d255ac8fce8fc9`. Main app and Widgets are 1.1.5 (48), minimum iOS 27.0; both unsigned Release targets build. All fixed performance budgets passed and the 90-frame / 3-page baseline output remains byte-identical. Simulator algorithm timing is not phone finish-to-Photos latency.

Focused evidence includes 5 native capture regression groups, 12 original pipeline groups, 3 numeric diagnostic groups; real Vision detector 12 synthetic assertions (plus four local user-image checks with boundary177px); UIKit status-bar integration70 assertions including animated status and native moving pixels immediately below it; geometry metadata negatives and actual forced directory-publication failures; 8 result-flag/language and14 LiveActivity-phase/language combinations; actual UIKit preview bounds/asymmetric-inset/zoom/identity checks. An independent code review found no remaining actionable issue after the horizontal analysis bound was corrected to exact observed pixels.

Only isolated synthetic inputs are used by automatic tests; the previously authorized user image stays local and is not committed. The physical-device acceptance field remains not run; installing the test package does not assert correct user-page captures.

Xcode 27.2 (27B52), iOS 27.2 simulator; minimum iOS remains 27.0. Physical installation target was freshly read as iPhone 17 on iOS 27.2, running Long Scroll 1.1.4 (47), with the same bundle identifier. Device identifiers, private receipts, signing material, profiles, app packages, raw captures and images are excluded from public Git.

## Installation and acceptance

Standard Release archive and release-testing (Ad Hoc) export succeeded. Both exported arm64 bundles are Apple Distribution signed, 1.1.5 (48), minimum iOS 27.0, SDK27.2, `get-task-allow=false`, with unchanged application identifiers and App Group. Both profiles contain the target phone. Strict deep signatures, bilingual resources and absence of snapshot/benchmark/export-frame/test-hook entry points passed.

The connected iPhone was updated **in place** from 1.1.4 (47) to **1.1.5 (48)**. The installer returned success, a separate installed-app query read back exactly1.1.5 /48, and normal app launch succeeded without arguments. No uninstall, manual cache-cleanup or preference-reset command was issued. Existing production capture data was not exported or inspected. The previously installed package did not expose its data container through the device tool, so a byte-level before/after data comparison is not claimed.

Installation/version read-back and app launch are separate from the user's end-to-end capture acceptance, which remains pending. Suggested real checks: portrait Keep status bar OFF/ON including the app title; horizontal tables and first heading row; cold Control Center start; Next page pause/resume then immediate Finish; complete/partial notifications and the corresponding preview. No App Store submission was performed for this test build.
