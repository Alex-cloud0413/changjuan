# Status-bar pixel quality research — 2026-11-07

Status: Photos result quality remains unresolved. This record covers source research and bounded local diagnostics; no App Store action is claimed.

## Decision

Keep the current pipeline while locating the first stage that changes the captured pixels. Keep-status-bar ON must preserve the actual time, battery, island and recording indicator. No background reconstruction or alternate-frame substitution is wanted. A framework replacement cannot recover detail already absent from its input.

## Source-reviewed candidates

- **Seamly.app**, reviewed at `ed371ad`: the closest architectural reference. ReplayKit frames become native BGRA images; selected keyframes are stored as [raw BGRA bytes](https://github.com/LiLiKazine/Seamly.app/blob/ed371adfc13151f95c95b6e3e8e3ff8790075d8d/Seamly/StitchKit/Sources/StitchKit/KeyframeIO.swift#L15-L45). Its [compositor](https://github.com/LiLiKazine/Seamly.app/blob/ed371adfc13151f95c95b6e3e8e3ff8790075d8d/Seamly/StitchKit/Sources/StitchKit/Compositor.swift#L121-L138) uses source dimensions and disables interpolation; [export](https://github.com/LiLiKazine/Seamly.app/blob/ed371adfc13151f95c95b6e3e8e3ff8790075d8d/Seamly/Seamly/Features/Export/Exporter.swift#L29-L38) uses PNG. However, the [reviewed tree](https://github.com/LiLiKazine/Seamly.app/tree/ed371adfc13151f95c95b6e3e8e3ff8790075d8d) contains no license file, and GitHub reports no declared license. Treat it as publicly readable source, not a permissively licensed dependency.
- **SnapFlow**, reviewed at `aa0ad27`: its [ScreenCaptureKit configuration](https://github.com/taoking/SnapFlow/blob/aa0ad272eba1434d3f1ba94648e9a6f35487e117/LongShot/Core/Capture/ScreenCaptureSession.swift#L26-L30) explicitly multiplies `contentRect` dimensions by `pointPixelScale`. It [stores PNG frames](https://github.com/taoking/SnapFlow/blob/aa0ad272eba1434d3f1ba94648e9a6f35487e117/LongShot/Core/Capture/FrameSampler.swift#L73-L85) and [copies native RGBA rows](https://github.com/taoking/SnapFlow/blob/aa0ad272eba1434d3f1ba94648e9a6f35487e117/LongShot/Core/Stitching/StitchRenderer.swift#L29-L56). Its [reviewed tree](https://github.com/taoking/SnapFlow/tree/aa0ad272eba1434d3f1ba94648e9a6f35487e117) likewise has no license file. Use it for comparison, not direct code adoption.
- **ScrollCap**, reviewed at `cf81b04`, has an actual [MIT license](https://github.com/EthanShen10086/ScrollCap/blob/cf81b0449c81de328dad7809ca22c110aca1db3a/LICENSE). However, its ReplayKit broadcast [writer encodes JPEG at quality 0.7](https://github.com/EthanShen10086/ScrollCap/blob/cf81b0449c81de328dad7809ca22c110aca1db3a/BroadcastExtension/SampleHandler.swift#L73-L89). That makes it an unsuitable sharpness upgrade over the existing capture path.

LiveKit's [Apache-2.0 license](https://github.com/livekit/client-sdk-swift/blob/df4194cdddc2f9cc065ae3144ac752740ceb7b22/LICENSE) and [iOS screen-sharing implementation](https://github.com/livekit/client-sdk-swift/blob/df4194cdddc2f9cc065ae3144ac752740ceb7b22/Docs/ios-screen-sharing.md) make it a useful streaming reference. It is not a still-image export or status-bar sharpness fix.

## What the measurements establish

The synthetic native rendering probe measured **zero MAE** for the PNG drawing path. Pristine PNG versus the current JPEG-0.9 capture plus JPEG-0.94 export simulation gave clock MAE **0.2455 on a 0–255 scale**, with approximately **99.2% Laplacian sharpness retention**. These are synthetic results, not evidence about the user's incoming capture buffer.

The original Photos JPEG, at **1206 × 6471**, showed a **4.44-pixel 10–90% edge-transition width** on a clock digit stem versus **1.37 pixels** on the black island wall. These values are edge widths, not MAE. They describe regional softness within one image; they do not identify where it originated.

Photos-original retrieval was verified. Content-free device logs confirmed Build 51 capture frames at **1206 × 2622**. Dimensions alone do not prove pixel fidelity, and no raw ScreenCaptureKit sample is available for comparison yet.

## Next bounded diagnostic

The temporary Build 52 diagnostic is implemented, but is not a proven quality fix. Trace one source frame through four stages: native capture image before JPEG; decoded persisted frame; compositor pixels before export; and final exported pixels. Stage one is a CGImage after the existing Core Image conversion and orientation handling, not the raw ScreenCaptureKit pixel buffer. If it is already soft, upstream capture versus conversion remains unresolved. Compare the same native clock, island and battery regions without resizing or changing the selected frame. Identify the first divergent stage before changing the pipeline. Keep private pixels and diagnostic linkage local.
