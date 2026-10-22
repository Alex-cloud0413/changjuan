# App Review notes — 1.1.4 (47)

Long Scroll 1.1.4 (47) is an on-device long-screenshot utility for iOS 27+. No login is required. Built with Xcode 27.1; minimum iOS remains 27.0.

HOW TO TEST
1. In a full-screen scrollable app, stop at the desired starting position.
2. In Control Center, tap “长卷” / “Long Scroll”. Add this control by searching either name.
3. Select “Share Entire Screen” in Apple's panel. Wait for the system panel and expanded Dynamic Island to collapse, then scroll slowly with overlapping content.
4. Touch and hold the Dynamic Island and tap “完成” / “Finish”, or tap the main Control Center control again. There is no fixed end countdown.
5. Allow add-only Photos access if asked. Results save to Photos; an in-app thumbnail or local notification opens the zoomable preview. Banners depend on notification and Focus settings.
Starting with the home icon requires switching to the target app after consent.

DUO AND GEOMETRY CHANGES
Home, settings and preview adapt to available window space and reserved regions on iOS 27.1. Opening/folding or rotation may change captured pixel dimensions or orientation. These changes create separate native-size outputs; notification and preview explain that they were saved separately. The app does not stretch incompatible frames into one image or claim continuity across reflowed content. Prefer stable device pose/layout for a continuous long image. Capture requires the target app to be full screen. If Long Scroll itself is visibly side by side, capture fails explicitly and retains original frames.
“保留顶部状态栏” / “Keep status bar” remains available. When a reliable target status-bar boundary is unavailable, new recordings preserve the full frame regardless of this preference. Automatic side-status-bar removal is not implemented. No system consent or recording indicator is bypassed.

SCROLLING AND PARTIAL OUTPUTS
Home → gear → “拼接方向” / “Scroll direction” chooses vertical or horizontal for new recordings. Slowly scroll along that axis with overlap; backtracking is supported. Do not mix scrolling axes.
For cross-page capture, expand the Dynamic Island and tap “接下一页” / “Next page” to pause, switch pages, then tap “继续” / “Continue”. The optional Control Center next-page control also pauses/resumes. Wait for panels to collapse. Equal-size pages join in capture order with separators.
Frozen columns and small cross-axis jitter are handled. If only bottom rows remain covered by a floating control, output may stop at a verified complete visible row with an explicit “底部遮挡行未收录” warning. Missing middle content or uncertain alignment still fails. No pixels are generated.

STORAGE AND PRIVACY
Complete results saved to Photos automatically remove raw frames and analysis caches. Ordinary saved previews use a 7-day, 10-session, 100 MB budget. Failed/unsaved recordings and partial outputs with omitted bottom rows retain originals until confirmed manual cleanup. This budget is not a hard cap on all data. Cache cleanup preserves Photos assets, generated previews and preferences.
Processing stays on device: no account, ads, tracking, backend or remote push. ScreenCaptureKit uses explicit system sharing consent and screen-capture background mode; audio/camera buffers are ignored. Privacy policy: Home → “查看使用方法” / “How to use” → footer. Chinese/English switch is at the home bottom. Existing store screenshots contain no private user captures. No physical Duo was available; automated/native and Duo simulator checks were used. Review contact is unchanged.
