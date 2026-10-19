import Foundation

/// App-owned preference, shared with controls. Never changes AppleLanguages,
/// system permission settings, stored captures or Apple's sharing panels.
enum AppLanguage: String, CaseIterable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    static let preferenceKey = "longshot.interfaceLanguage.v1"

    static var defaults: UserDefaults {
        let configured = Bundle.main.object(forInfoDictionaryKey: "LongShotAppGroupIdentifier") as? String
        let group = configured.flatMap { !$0.isEmpty && !$0.contains("$(") ? $0 : nil }
            ?? "group.com.gaoyiming.longshot.private"
        return UserDefaults(suiteName: group) ?? .standard
    }

    static var current: AppLanguage { read(from: defaults) }

    static func initialLanguage(isExistingInstallation: Bool, preferredLanguages: [String]) -> AppLanguage {
        if isExistingInstallation { return .chinese }
        return preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
    }

    static var initialLanguage: AppLanguage {
        initialLanguage(
            isExistingInstallation: UserDefaults.standard.object(forKey: "longshot.hasCompletedUsageGuide.v1") != nil,
            preferredLanguages: Locale.preferredLanguages
        )
    }

    static func prepareIfNeeded() {
        guard defaults.string(forKey: preferenceKey) == nil else { return }
        defaults.set(initialLanguage.rawValue, forKey: preferenceKey)
    }

    static func read(from defaults: UserDefaults, fallback: AppLanguage = initialLanguage) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? fallback
    }

    var locale: Locale { Locale(identifier: rawValue) }

    func text(_ source: String) -> String {
        guard self == .english else { return source }
        if let translated = Self.englishText[source] { return translated }
        // Preserve old manifest evidence; translate failures only for display.
        if source.hasPrefix("无法读取画面：") {
            return "Unable to read frame: " + source.dropFirst("无法读取画面：".count)
        }
        if source.hasPrefix("录制记录损坏：") {
            return "Capture record is damaged: " + source.dropFirst("录制记录损坏：".count)
        }
        if source.hasPrefix("无法访问本地共享空间（") {
            return "Unable to access local shared storage. Reopen Long Scroll and try again."
        }
        if source.hasPrefix("第 "), source.contains(" 页没有采集到可连续拼接的内容。"),
           let number = source.split(separator: " ").dropFirst().first, Int(number) != nil {
            return "Page \(number) has no continuous content to stitch. Tap Resume after switching pages, then scroll slowly. Original frames are still on this device."
        }
        return source // Keep unfamiliar OS errors rather than hide details.
    }

    func format(_ source: String, _ arguments: CVarArg...) -> String {
        String(format: text(source), locale: locale, arguments: arguments)
    }

    static let englishText: [String: String] = [
        "长卷": "Long Scroll",
        "查看使用方法": "How to use",
        "使用中文": "Use Chinese",
        "使用英文": "Use English",
        "已选择": "Selected",
        "打开三步使用引导，查看控制中心设置和截图方法": "Open the three-step guide for Control Center setup and capture instructions",
        "这一次没有成卷": "Couldn't create this scroll",
        "重新整理": "Try stitching again",
        "清理后重录": "Clear and record again",
        "关闭": "Close",
        "清理这一次的本地记录？": "Clear this capture's local records?",
        "清理本地记录": "Clear local records",
        "取消": "Cancel",
        "已经保存到系统照片中的图片不会被删除。": "Images already saved to Photos will not be deleted.",
        "已保存到照片": "Saved to Photos",
        "轻点预览长图": "Tap to preview",
        "已保存到照片，轻点预览刚刚生成的长图": "Saved to Photos. Tap to preview your new long image",
        "关闭缩略图提示": "Dismiss thumbnail",
        "已保存的长图不会被删除": "The saved image will not be deleted",
        "正在打开系统面板": "Opening system picker",
        "结束并生成": "Finish capture",
        "正在生成": "Creating image",
        "开始收卷": "Start capture",
        "请在 Apple 面板中确认共享整个屏幕": "Confirm Share Entire Screen in Apple's picker",
        "长按灵动岛，可接下一页、继续或完成；也可使用控制中心的长卷控制": "Touch and hold the Dynamic Island to add a page, resume or finish. You can also use the Long Scroll controls in Control Center",
        "正在识别重叠内容并保存到照片": "Matching overlapping content and saving to Photos",
        "也可以从控制中心或操作按钮打开": "You can also start from Control Center or the Action button",
        "继续收卷": "Resume capture",
        "接下一页": "Next page",
        "查看失败详情": "View error details",
        "请确认共享整个屏幕": "Confirm Share Entire Screen",
        "采集已暂停，切换页面后继续": "Capture paused. Switch pages, then resume",
        "回到目标页面继续滚动": "Return to your content and keep scrolling",
        "完成后自动保存到照片": "The image will be saved to Photos",
        "没有可预览的长图": "No image to preview",
        "无法读取这张长图": "Unable to load this image",
        "完成": "Done",
        "分享": "Share",
        "长图 %ld / %ld": "Image %ld / %ld",
        "长图预览": "Image preview",
        "跳过": "Skip",
        "第 1 步 · 只需设置一次": "STEP 1 · SET UP ONCE",
        "把长卷放进控制中心": "Add Long Scroll to Control Center",
        "以后无论正在看微信、淘宝还是网页，都能从控制中心快速唤起长卷。": "Start a long capture from Control Center while viewing a chat, a product page or a website.",
        "从屏幕右上角向下轻扫，打开控制中心。": "Swipe down from the top-right corner to open Control Center.",
        "长按空白处或轻点左上角「＋」进入编辑，再轻点「添加控制」。": "Touch and hold an empty area, or tap + at the top left. Then tap Add a Control.",
        "搜索「长卷」或「Long Scroll」，轻点三笔标志把它加入控制中心。": "Search for Long Scroll or “长卷”. Tap the three-stroke symbol to add the control. Its name follows your iPhone's system language.",
        "控制中心设置示意图，显示长卷三笔标志和添加控制按钮": "Control Center setup illustration showing the Long Scroll symbol and Add a Control",
        "第 2 步 · 确认一次录制": "STEP 2 · CONFIRM CAPTURE",
        "轻点长卷，确认开始": "Tap Long Scroll to begin",
        "在当前界面确认 Apple 的整个屏幕共享，然后继续滚动。": "Confirm Apple's entire-screen sharing, then scroll in your current app.",
        "先打开要截取的内容，停在想要的起点。": "Open the content you want to capture and stay at your starting point.",
        "打开控制中心，轻点「长卷」。": "Open Control Center and tap the “长卷” (Long Scroll) control.",
        "控制中心收起后，当前 App 保持不变；轻点 Apple 面板中的「Share Entire Screen（共享整个屏幕）」。": "Your app stays in place when Control Center closes. Select Share Entire Screen in Apple's picker; its labels follow your iPhone's system language.",
        "先等灵动岛面板与系统共享提示收起，再沿设置中的拼接方向缓慢滚动；等待时停在原处。": "Stay at the starting point until the Dynamic Island and sharing notice collapse. Then scroll slowly in the direction selected in Settings.",
        "Apple 录制确认面板示意图，突出显示共享整个屏幕": "Apple capture confirmation illustration highlighting Share Entire Screen",
        "第 3 步 · 到哪里停在哪里": "STEP 3 · FINISH WHERE YOU WANT",
        "滚动内容，轻点完成": "Scroll, then tap Done",
        "不用等待固定倒计时；确认完成后，长卷会立即整理并保存到照片。": "No fixed countdown. Once you finish, Long Scroll starts stitching and saves the result to Photos.",
        "纵向模式可上下往返，横向模式可左右往返。请保持同一方向轴，长卷会按内容顺序去重拼接。": "Scroll up and down in Vertical mode, or left and right in Horizontal mode. Stay on one axis; Long Scroll removes duplicates and follows the content's order.",
        "长按顶部灵动岛即可重新展开操作。要切换页面，先点「接下一页」暂停，切换后长按灵动岛再点「继续」。": "Touch and hold the Dynamic Island to reveal the actions. Tap Next page to pause, switch to another page, then expand it again and tap Resume.",
        "也可添加「长卷 · 接下一页」（Long Scroll · Next page）控制，直接暂停或继续，不用返回长卷。": "You can also add Long Scroll · Next page (长卷 · 接下一页) to Control Center. It pauses and resumes capture without opening the app.",
        "到达想要的终点，长按灵动岛后点「完成」，或再次点控制中心里的「长卷」。": "At your endpoint, expand the Dynamic Island and tap Done, or tap the main Long Scroll control in Control Center again.",
        "保存后，长卷内会浮出缩略图，轻点查看完整长图；在其他 App 中的提醒需要允许通知。": "After saving, tap the thumbnail in Long Scroll to preview the full image. Allow notifications to see completion alerts while using other apps.",
        "滚动与完成示意图，显示灵动岛中的完成按钮": "Scrolling illustration showing Done in the Dynamic Island",
        "第 %ld 步，共 %ld 步": "Step %ld of %ld",
        "我会用了": "Got it",
        "下一步": "Next",
        "通知提醒设置": "Notification settings",
        "在其他 App 中显示完成提示，需要允许长卷通知和横幅": "Allow Long Scroll notifications and banners to receive completion alerts in other apps",
        "隐私政策": "Privacy policy",
        "打开长卷的隐私政策网页": "Open the Long Scroll privacy policy webpage",
        "截取滚动内容": "Capture scrolling content",
        "添加控制": "Add a Control",
        "开始屏幕录制": "Start screen capture",
        "仅在设备上整理画面": "Processed only on this device",
        "长卷已保存为 %ld 张长图": "Long Scroll saved %ld images",
        "长卷已保存": "Long Scroll saved",
        "长卷已保存（部分内容）": "Long Scroll saved (partial)",
        "底部遮挡行未收录，轻点查看": "Obscured bottom rows were omitted. Tap to review.",
        "底部遮挡行未收录": "Obscured bottom rows were omitted",
        "悬浮按钮遮住的底部内容无法完整恢复，已保留上方完整可见的行。原始画面保留至手动清理缓存。": "The bottom content hidden by floating controls could not be fully recovered. Complete visible rows above it are included. Original frames are kept until you clear capture caches.",
        "轻点预览刚刚生成的长图": "Tap to preview your new long image",
        "长按灵动岛，显示接下一页、继续和完成按钮": "Touch and hold the Dynamic Island for Next page, Resume and Done",
        "等待系统选择": "Waiting for permission",
        "正在收卷": "Capturing",
        "切换页面中": "Switching pages",
        "正在生成长图": "Creating your image",
        "从控制中心打开": "Start from Control Center",
        "请确认长卷录制": "Confirm capture in Apple's picker",
        "到达目标位置后轻点完成": "Tap Done at your endpoint",
        "采集已暂停，切到新页面后轻点继续": "Capture paused. Switch pages, then tap Resume",
        "可继续使用其他 App": "You can keep using other apps",
        "已生成 %ld 张图片": "%ld images created",
        "长图已经可以使用": "Your image is ready",
        "打开长卷查看原因": "Open Long Scroll for details",
        "长按操作": "Hold",
        "长按继续": "Hold",
        "整理中": "Working",
        "已保存": "Saved",
        "失败": "Failed",
        "就绪": "Ready",
        "等待中": "Waiting",
        "等面板收起再滚动 · 长按灵动岛接页": "Wait for panels to collapse before scrolling. Hold the Dynamic Island to add a page.",
        "切换页面后点继续，再等面板收起滚动": "Switch pages, tap Resume, then wait for panels to collapse before scrolling.",
        "暂停": "Paused",
        "继续": "Resume",
        "在新页面继续收卷": "Resume capture on the new page",
        "暂停收卷，接下一页": "Pause capture to add another page",
        "完成长卷并保存到照片": "Finish capture and save to Photos",
        "完成长卷": "Finish capture",
        "等待选择": "Waiting for permission",
        "开始长卷": "Start capture",
        "没有采集到足够的画面，请重新录制。": "Not enough frames were captured. Please record again.",
        "录制过程中屏幕方向或尺寸发生了变化，请保持同一屏幕方向后重试。": "The screen's orientation or size changed during capture. Keep the same orientation and try again.",
        "没有识别到连续滚动内容。请沿设置中的拼接方向缓慢滚动，保持相邻画面有重叠。": "No continuous scrolling content was found. Scroll slowly in the direction selected in Settings, with overlap between frames.",
        "长图生成失败，请重试。": "The image couldn't be created. Please try again.",
        "有一段内容缺少重叠画面，无法完整拼接。请放慢滚动速度后重试；原始画面已保留。": "Some content is missing overlapping frames, so it can't be stitched completely. Scroll more slowly and try again. Original frames are still on this device.",
        "这台设备当前不允许屏幕捕获，请检查系统的屏幕录制限制。": "Screen capture is not allowed on this device. Check the system's screen recording restrictions.",
        "你取消了屏幕捕获。": "You cancelled screen capture.",
        "你取消了屏幕捕获授权。": "You cancelled screen capture permission.",
        "系统屏幕选择等待超时，请重新从控制中心开始。": "The screen-sharing picker timed out. Start again from Control Center.",
        "屏幕捕获权限尚未配置完成，请重新安装此版本后再试。": "Screen capture permission isn't configured. Reinstall this version and try again.",
        "可用存储空间不足，无法继续生成长图。": "There isn't enough free storage to create the image.",
        "系统没有允许长卷在后台继续捕获，请重新安装此版本后再试。": "The system didn't allow Long Scroll to continue capturing in the background. Reinstall this version and try again.",
        "没有捕获到可用画面。请选择整个屏幕，并在提示后切到目标 App。": "No usable frames were captured. Select the entire screen, then return to your content.",
        "屏幕捕获需要在 iPhone 真机上使用。": "Screen capture requires a physical iPhone.",
        "上一次系统录制没有正常结束。请先停止顶部录制标记，再重新开始；本地画面已保留。": "The previous capture didn't finish normally. Stop it using the recording indicator, then start again. Local frames have been kept.",
        "屏幕捕获没有正常完成。": "Screen capture didn't finish normally.",
        "没有获得保存到照片的权限。请在系统设置中允许“长卷”添加照片。": "Photos permission wasn't granted. Allow Long Scroll to add photos in Settings.",
        "图片已经生成，但保存到照片时失败。": "The image was created, but saving it to Photos failed.",
        "预览已不可用": "Preview unavailable",
        "设置": "Settings",
        "拼接方向": "Scroll direction",
        "纵向": "Vertical",
        "横向": "Horizontal",
        "横向 · 左右滚动": "Horizontal · Scroll left or right",
        "横向适合左右拖动的表格。一次录制只使用一种方向；更改仅影响新录制。": "Choose Horizontal for wide tables. Use one direction per recording. Changes apply to new recordings only.",
        "保留顶部状态栏": "Keep status bar",
        "保留实际录制到的时间、信号和电量，也可能包含录制指示。默认关闭。": "Keep the captured time, signal and battery. Recording indicators may also appear. Off by default.",
        "清理所有缓存": "Clear all capture caches",
        "存储": "Storage",
        "仅清理原始画面和分析缓存，保留系统照片与已生成的本地预览。": "Remove raw frames and analysis caches only. Saved photos and generated previews stay on your device.",
        "请等待当前录制、整理或清理完成后再修改设置。": "Wait for capture, processing or cleanup to finish before changing settings.",
        "清理所有缓存？": "Clear all capture caches?",
        "清理缓存": "Clear Cache",
        "部分缓存未能清理，请稍后重试。": "Some caches couldn't be cleared. Try again later.",
        "没有可清理的缓存。": "No capture caches to clear.",
        "已清理 %@，照片和预览未删除。": "Cleared %@. Photos and previews were kept.",
        "这会删除所有原始画面和分析缓存，尚未保存的记录将无法重新整理。系统照片和已生成的本地预览不会被删除。此操作无法撤销。": "This deletes all raw frames and analysis caches. Unsaved recordings can no longer be reprocessed. Photos and generated previews are kept. This cannot be undone.",
        "本地预览可能已自动清理，请到系统「照片」中查看已保存的长图。若已在照片中删除，长卷无法恢复。": "The local preview may have been cleared automatically. Look for the saved image in Photos. Long Scroll cannot recover images deleted from Photos."
    ]
}
