# App Review Notes — Long Scroll 1.1.1 (Build 35)

Long Scroll creates a single long image from content that the user explicitly scrolls through on their iPhone.

## How to test

1. Open a scrollable app or page and stop at the desired starting position.
2. Open Control Center and tap “长卷”. The current app remains visible after Control Center closes.
3. In Apple’s system-owned panel, select “Share Entire Screen”. Keep the starting position still until the sharing panel and expanded Dynamic Island collapse, then scroll slowly with overlapping content. Scroll downward, upward, or back and forth within the same page; output is ordered by the page's vertical layout.
4. At the desired endpoint, touch and hold the Dynamic Island to expand it, then tap “完成”; alternatively tap the main Control Center control again.
5. Grant add-only Photos permission if requested. The stitched image is saved to Photos. When Long Scroll is in the foreground, a tappable floating thumbnail appears in the app; when another app is visible, Long Scroll requests a system completion notification with a preview action. Banner visibility remains subject to iOS notification and Focus settings.

The Control Center control can be added from Control Center’s edit mode by searching for “长卷” (or “Long Scroll” in English). The large central capture symbol on the home screen is an alternative entry point and requires switching to the target app after system confirmation. It retains an accessibility label but no visible start caption.

## Cross-page capture (new in 1.1.0)

1. While capturing page A, touch and hold the Dynamic Island and tap “接下一页”. Capture is paused.
2. Switch to page B while paused, tap “继续” in the expanded Dynamic Island, wait for the system panels to collapse, and scroll page B.
3. Finish as above. Page segments are stitched in capture order with a separator, rather than inferred as one continuously scrolling page.

An optional second Control Center control, “长卷 · 接下一页”, performs the same pause/resume action without opening the app. It is disabled outside an active capture session. No automatic cross-page switch is inferred.

Rapid jumps, dynamic content and frames without enough shared content may fail alignment. Starting overlays cannot reveal content that was never captured unobstructed; the UI asks users to wait at their starting position. The app does not suppress Apple's recording indicators or permission panel.

## Privacy and recording behavior

- Recording begins only after an explicit user action and Apple’s system-owned confirmation.
- iOS displays its recording indicator while capture is active. Long Scroll also displays a Live Activity with a visible finish control.
- ScreenCaptureKit delivers screen sample buffers to the app only for the user-requested capture session. This build does not contain ReplayKit broadcast extensions.
- Audio and camera sample buffers are ignored. The app does not save or transmit audio.
- Screen frames and generated images remain in the app group container on the device and are never uploaded.
- The app has no account system, analytics, advertising SDK, tracking, or server communication.
- The result is written to Photos only after add-only Photos authorization.

## Implementation note

Build 35 supports iOS 27 and later and uses ScreenCaptureKit's `SCContentSharingPicker` and `SCStream` with the screen-capture background mode. Control Center commands use LiveActivityIntent to execute in the app process without requesting foreground presentation. Explicit system permission is always required.

Version 1.1.1 simplifies the home screen to a single screen at ordinary text sizes. Tap “查看使用方法” to reopen the three-step guide. Larger accessibility text may scroll rather than truncate. The permanent saved-result card and repeated instructions have been removed, but the transient saved thumbnail, notification preview, failure recovery, capture and page-transition actions remain. Control Center symbols are unchanged from the publicly available 1.1.0 (Build 29).

Build 35 replaces the pending Build 31. It removes the idle home slogan and start caption and adds explicit language buttons: 中文 at the bottom left and English at the bottom right. The guide, status text, Live Activity and local notifications follow the selected app language; system permission UI follows iOS. The privacy policy remains easily accessible inside the app: tap “查看使用方法” / “How to use”, then “隐私政策” / “Privacy policy” at the bottom of any guide page. The privacy policy URL in App Store Connect is unchanged. Store screenshots are updated to match this UI.

To reduce post-capture waiting, Build 35 computes derived frame analysis on a bounded background queue during recording. Original JPEGs remain the rendering source, with unchanged resolution and compression settings. Unavailable or invalid derived data is recomputed at finish; no original frame is dropped to keep up with preprocessing. All analysis and timing diagnostics stay on device.

Store screenshots show the current native UI. The control-center and sharing-panel illustrations are part of the app's actual guide. The result preview uses developer-authored offline sample content passed through the production stitcher, with no real user data.

When the user taps Finish, the app seals frame intake, stops the stream, commits the local capture and stitches it under a finite background task. No fixed recording-end wait or destructive tail-frame trim is used.

## Reviewer contact

Use the confirmed App Review contact stored in App Store Connect. No login, special account, or external hardware is required.
