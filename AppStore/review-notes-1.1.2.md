# App Review notes — 1.1.2 (42)

Long Scroll 1.1.2 (Build 42) creates long images from content explicitly captured and scrolled by the user. Requires iOS 27 or later. No login or extra hardware is needed.

HOW TO TEST
1. In a scrollable app, stop at the desired starting position.
2. Open Control Center and tap “长卷” / “Long Scroll”. Add the control from Control Center edit mode by searching either name. The current app remains visible.
3. Select “Share Entire Screen” in Apple's system panel. Keep still until the sharing panel and expanded Dynamic Island collapse, then scroll slowly with overlapping content. Vertical upward, downward and back-and-forth scrolling are supported; output follows the page layout.
4. Touch and hold the Dynamic Island, then tap “完成” / “Finish”; alternatively tap the main Control Center control again. There is no fixed recording-end wait.
5. Grant add-only Photos permission if requested. Results are saved to Photos. An in-app thumbnail or local completion notification opens the preview. Notification banners depend on iOS notification and Focus settings.
The central home icon is an alternative start control. Starting inside the app requires switching to the target app after permission.

NEW SETTINGS AND HORIZONTAL CAPTURE
Home → top-right gear → “拼接方向” / “Scroll direction” → “横向” / “Horizontal”. Then capture a wide table by slowly dragging it left/right, with overlap. Results follow the content's left-to-right order, including backtracking. Each recording uses one chosen axis; do not rotate the device or mix horizontal and vertical movement during a recording. The setting applies to new recordings only. Wide previews support panning and zooming.
“保留顶部状态栏” / “Keep status bar” defaults off. When enabled, actual captured status-bar pixels are retained once; they may include the recording indicator. System consent and recording indicators are not bypassed.

Horizontal alignment handles repeated table columns and small vertical drag jitter. Identified persistent floating control groups are retained once; covered table pixels are recovered only from actual unobstructed overlapping frames. No content is generated or inferred for areas never captured unobstructed.

CROSS-PAGE CAPTURE
Expand the Dynamic Island and tap “接下一页” / “Next page” to pause, switch pages while paused, then tap “继续” / “Continue”. Wait for panels to collapse and scroll. Pages are joined in capture order with a separator. Optional Control Center control “长卷 · 接下一页” / “Long Scroll · Next page” provides the same pause/resume action. Transitions are not inferred automatically.

STORAGE AND PRIVACY
After a confirmed successful Photos save, original frames and analysis caches are automatically removed. Saved local previews are maintained under a 7-day, 10-session, 100 MB budget; active previews and notification delivery are protected. Failed/unsaved input is not automatically pruned. Settings → “清理所有缓存” / “Clear all caches” requires confirmation and warns that raw input recovery is lost. It retains Photos assets, generated previews and preferences, and is disabled during recording or processing.
All processing stays on device. Frame analysis during recording reduces work at finish; original JPEGs remain the rendering source. Missing/invalid analysis is recomputed. No account, ads, tracking, analytics, backend or remote push. ScreenCaptureKit uses explicit system sharing consent and screen-capture background mode. Audio/camera buffers are ignored; no ReplayKit extensions.
Privacy policy: home → “查看使用方法” / “How to use” → footer “隐私政策” / “Privacy policy”. Chinese/English selection is at the bottom of home. Rapid jumps, animations and insufficient overlap may affect alignment. Content never captured unobstructed cannot be recovered.

Screenshots show native UI. Result examples use developer-authored sample content, not user data. Review contact details are unchanged.
