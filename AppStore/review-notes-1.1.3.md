# App Review notes — 1.1.3 (46)

Long Scroll 1.1.3 (46) is an on-device long-screenshot utility for iOS 27+. No login is required. This update improves frozen-column table alignment and handles irrecoverable bottom overlays explicitly.

HOW TO TEST
1. In a scrollable app, stop at the desired starting position.
2. In Control Center, tap “长卷” / “Long Scroll”. Add this control in edit mode by searching either name. The current app remains visible.
3. Select “Share Entire Screen” in Apple's panel. Keep still until the system panel and expanded Dynamic Island collapse, then scroll slowly with overlapping content.
4. Touch and hold the Dynamic Island and tap “完成” / “Finish”, or tap the main Control Center control again. There is no fixed end countdown.
5. Allow add-only Photos access if asked. Results are saved to Photos; an in-app thumbnail or local notification opens the preview. Banners depend on iOS notification and Focus settings.
Starting with the home icon requires switching to the target app after consent.

HORIZONTAL TABLES AND PARTIAL RESULTS
Home → gear → “拼接方向” / “Scroll direction” → “横向” / “Horizontal”. Capture a wide table by slowly dragging left/right with overlap. Output follows content order, including backtracking. One recording uses one axis; do not rotate the device or mix vertical/horizontal scrolling. This preference applies to new recordings only. Wide previews support panning and zooming.
Frozen columns, repeated columns and small cross-axis jitter are matched separately from static bars and floating controls. Covered content is recovered only from actual unobstructed recorded pixels; no content is generated.
If a persistent floating overlay makes only bottom table rows unrecoverable, the app may end at a verified complete visible row boundary. The thumbnail, preview and completion notification explicitly warn “底部遮挡行未收录” (bottom obscured rows not included). The preview explains that original frames are retained until manual cleanup. Missing middle content, uncertain alignment or absence of a safe row boundary still fails rather than silently omitting content.

EXISTING FEATURES
Vertical capture supports upward, downward and back-and-forth scrolling. For cross-page capture, expand the Dynamic Island and tap “接下一页” / “Next page” to pause, switch pages, then tap “继续” / “Continue”. Wait for panels to collapse before scrolling. The optional Control Center “Long Scroll · Next page” control also pauses/resumes. Pages are joined in capture order with separators; page transitions are not guessed.
Settings → “保留顶部状态栏” / “Keep status bar” defaults off. When on, actual captured pixels are kept once and may include the recording indicator. No system consent or indicator is bypassed.

STORAGE AND PRIVACY
Complete results saved successfully to Photos have raw frames and analysis caches removed automatically. Ordinary saved previews use a 7-day, 10-session, 100 MB budget, excluding active previews and notification delivery. Failed/unsaved recordings and partial results with omitted bottom rows retain their original frames until manual cleanup. This budget is not a hard cap on all app data.
Settings → “清理所有缓存” / “Clear all caches” requires confirmation and warns that raw input recovery is lost. It retains Photos assets, generated previews and preferences; it is disabled during capture/processing.
Processing stays on device. Original JPEGs remain the rendering source; missing analysis is recomputed. No account, ads, tracking, backend or remote push. ScreenCaptureKit uses explicit system sharing consent and the screen-capture background mode. Audio/camera buffers are ignored; no ReplayKit extension.
Privacy policy: Home → “查看使用方法” / “How to use” → footer. Chinese/English controls are at home bottom. Rapid jumps, animations and insufficient overlap may prevent alignment. Store screenshots contain no private user captures. Review contacts are unchanged.
