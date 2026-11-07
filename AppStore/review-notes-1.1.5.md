# App Review notes — 1.1.5 (62)

Long Scroll is an on-device long-screenshot utility for iOS 27 and later. It requires no app account or external hardware. Build 62 uses the capture and feedback behavior verified in Build 61 and updates the privacy manifest for optional support email.

## Capture

1. In a full-screen scrollable app, stop at the starting position and select “长卷” / “Long Scroll” in Control Center.
2. Select “Share Entire Screen” in Apple’s panel. Wait for the panel and expanded Dynamic Island to collapse, then scroll slowly with overlapping content.
3. Touch and hold the Dynamic Island and tap “完成” / “Finish”, or tap the main Control Center control again. Allow add-only Photos access if asked. The result is saved to Photos and can be opened in the app’s preview.

In Settings, “保留状态栏” / “Keep status bar” applies to new captures. In portrait, the app can choose a clearer original frame from the same scroll position. When the preference is off, the app crops a verified status bar boundary. Changes in the captured pixel dimensions or orientation produce separate native-size images.

## Feedback and privacy

Open Settings → “问题反馈” / “Feedback”. The same entry is available from a failed capture and from the long-image preview. Enter a test description, preview the diagnostics, and choose a mail app. “附带诊断信息” / “Include diagnostics” is off by default. An optional diagnostic summary can accompany the user’s description as JSON in the draft or as a JSON attachment. A mail account is only needed to actually send the email. The review can stop at the draft.

The feedback payload contains app and OS versions and selected technical capture events and durations. The app does not attach recordings, screenshots, recognized text, or Photos content. The user reviews the draft and taps Send in their mail client. The developer receives the confirmed content and sender details in the support inbox for customer support and troubleshooting. There is no background upload or tracking.

The in-app privacy policy is available from Home → “查看使用方法” / “How to use” → “隐私政策” / “Privacy policy”.
