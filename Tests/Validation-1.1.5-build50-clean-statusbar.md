# Clean status-bar export — 1.1.5 (50) device-test candidate

> **Superseded and withdrawn at the user's request.** [Build 51](Validation-1.1.5-build51-raw-statusbar.md) removes all background repair and special opening selection. Keep status bar ON now preserves the captured status bar, including islands and recording controls. The evidence below records the historical Build 50 experiment only.

## Requested behavior

The user accepted Build49 portrait OFF cropping, then reported malformed/recording islands with ON. An in-place1.1.3 (46) pre-Duo source comparison also retained sharp recording controls. Its source fingerprint matched the historical release; sampling/vertical rendering were unchanged, so a broad rollback was not an evidenced fix. The user explicitly clarified the desired output: keep captured time/battery and remove the whole island plus detached recording circle.

This changes exported pixels, rather than hiding system recording UI during capture. A strict, clock-verified native mask preserves the detected components' contours and enclosed recording rings, fills only those regions using nearby observed texture, and blends seams locally. Two additional native pixels cover JPEG/downsampling edge residue; the repair extent is separate from the existing OFF crop boundary. Measured clock bounds and the right-hand network/battery region remain protected. Donors stay below and horizontally inside the repaired span, and no clock/battery glyphs are synthesized.

**The obscured photo background is an approximation, not recovery of the original hidden pixels.** The setting description states this. Unproved/expanded/blurred layouts retain their original pixels if no supported observation is available; removal is not unconditional. The repair code does not rewrite captured JPEGs or matching/cache inputs. Existing normal storage cleanup policy still applies independently.

If an opening cannot be repaired, vertical ON can use a later supported observation only at the exact same positioned coverage with byte-identical lower body and exposed sides. The complete opening coverage is replaced, including an expanded island's tail; no later scroll position is substituted. Work is bounded to eight candidate observations. Otherwise the original opening is retained. A repaired native header is prepared once and carried through pagination, including page breaks inside the prefix. Horizontal cleanup uses original native coordinates and existing header clips.

## Verification

The final coherent full run passed **31/31** gates, `Build/regression-qdU0Mh/report.json`, with fixed performance budgets, byte-identical pinned 90-frame/3-page baseline results, unsigned device/simulator Release builds and an unchanged before/after source/config/test fingerprint (109 files): `f22f7d5bd87a9e77c7e447d4e288aea269a6cdb6263c80a89ded2ea685996017`. Xcode 27.2 (27B52), iOS 27.2 simulator. The earlier run was invalidated by a test/source change and is not the final acceptance evidence.

Focused final run: 84 native assertions with the latest local image (77 synthetic/contract assertions without it), plus 268 UIKit integration assertions. Checks cover full native mask coverage at 1005/1206 widths and fractional positions; flat/gradient reconstruction, exact unmasked RGBA/alpha preservation before JPEG output, determinism and invalid-context rejection; real Vision; OFF/ON; native clock/battery/title/body fidelity; whole capsule/circle removal; reverse/cache/legacy ratios; explicit/static/geometry pages; one-pixel body-change and changed-position rejection; and a status prefix split across output pages. All original fixture JPEGs remain byte-identical.

Three local result images were read in place. The two photo boundaries are 158 pixels and the neutral result 177; in-memory JPEG 0.9 agrees. A fallback OCR crop uses the existing allowed left-clock bounds and the proved capsule's vertical extent, retaining exact time syntax/uniqueness/native coordinate checks. The latest actual photo's native repair extends to 160 pixels, leaving its158-pixel OFF crop unchanged. A private top-only preview confirmed no black edge/recording symbol remained and preserved time/battery. No private image, preview or device receipt is committed.

Independent reviews checked mask bounds, donor/Poisson access, protected regions, exact-coverage selection, and page-slice coordinates; no remaining actionable finding. Simulator/native algorithm checks and a top-strip preview do not replace user end-to-end capture acceptance.

## Installation and acceptance

The final standard Release archive and release-testing (Ad Hoc) export succeeded. Both exported arm64 bundles are 1.1.5 (50), minimum iOS 27.0 / SDK 27.2, Apple Distribution signed, strict deep signatures valid, `get-task-allow=false`, with original identifiers/App Group and target-phone provisioning. Bilingual resources and absence of snapshot/benchmark/export-frame/test-hook entry points passed. The archived runtime-source fingerprint was rechecked before installation as well as the full regression fingerprint.

The phone was updated **in place from 1.1.3 (46) to 1.1.5 (50)**; installation succeeded and a separate installed-app query read back exactly 1.1.5 / 50. No uninstall, manual cache clear or preference reset was issued. iOS initially denied automatic launch because the phone was locked. After the user unlocked it, a fresh query again confirmed 1.1.5 (50), and normal no-argument launch succeeded. This confirms process launch, not the user-page capture result. The historical comparison and build49 recovery packages remain available locally.

User end-to-end acceptance remains pending: record the same photographic page again with Keep status bar ON and inspect actual time/battery, absence of the island/circle, and the approximate background repair; compare OFF and first body content. No App Store submission was performed for this candidate.
