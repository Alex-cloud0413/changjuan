import SwiftUI
import UIKit

enum ScrollPalette {
    static let paper = Color(red: 0.992, green: 0.988, blue: 0.976)
    static let ink = Color(red: 0.145, green: 0.145, blue: 0.13)
    static let secondaryInk = Color(red: 0.42, green: 0.41, blue: 0.38)
    static let recording = Color(red: 0.62, green: 0.24, blue: 0.18)
    static let success = Color(red: 0.27, green: 0.39, blue: 0.30)
    static let warning = Color(red: 0.62, green: 0.42, blue: 0.18)
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @AppStorage("longshot.hasCompletedUsageGuide.v1") private var hasCompletedUsageGuide = false

    @State private var showingShareSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingFullPreview = false
    @State private var showingUsageGuide = false
    @State private var usageGuideIsInitial = false

    var body: some View {
        NavigationStack {
            ZStack {
                paperBackground

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 26) {
                        brandHeader
                        introduction
                        systemEntryCard
                        captureAction
                        statusCard
                        instructions
                        privacyNote
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingShareSheet) {
                ActivityView(items: model.outputURLs)
            }
            .fullScreenCover(isPresented: fullPreviewBinding) {
                LongImagePreview(urls: model.outputURLs)
            }
            .fullScreenCover(
                isPresented: $showingUsageGuide,
                onDismiss: completeUsageGuidePresentation
            ) {
                UsageGuideView(isFirstRun: usageGuideIsInitial) {
                    hasCompletedUsageGuide = true
                    showingUsageGuide = false
                }
            }
            .confirmationDialog(
                "清理这一次的本地记录？",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("清理本地记录", role: .destructive) {
                    model.discardCurrentSession()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("已经保存到系统照片中的图片不会被删除。")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.isSavedThumbnailPresented,
                   !fullPreviewBinding.wrappedValue,
                   !showingUsageGuide,
                   !showingShareSheet,
                   let image = model.previewImage {
                    savedThumbnail(image)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1),
                value: model.isSavedThumbnailPresented
            )
        }
        .tint(ScrollPalette.ink)
        .onAppear {
            guard !hasCompletedUsageGuide, !showingUsageGuide else { return }
            usageGuideIsInitial = true
            showingUsageGuide = true
        }
    }

    private var fullPreviewBinding: Binding<Bool> {
        Binding(
            get: { showingFullPreview || model.isSavedPreviewRequested },
            set: { isPresented in
                showingFullPreview = isPresented
                if !isPresented {
                    model.dismissSavedPreview()
                }
            }
        )
    }

    /// Completion feedback stays above the scrolling page and does not depend
    /// on notification permission. Closing it never deletes the saved image.
    private func savedThumbnail(_ image: UIImage) -> some View {
        HStack(spacing: 0) {
            Button {
                model.openSavedThumbnail()
            } label: {
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 76, alignment: .top)
                        .clipped()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(hairline, lineWidth: 1)
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("已保存到照片")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ScrollPalette.ink)
                        Text("轻点预览长图")
                            .font(.footnote)
                            .foregroundStyle(ScrollPalette.secondaryInk)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .padding(.leading, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel("已保存到照片，轻点预览刚刚生成的长图")

            Button {
                model.dismissSavedThumbnail()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ScrollPalette.secondaryInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭缩略图提示")
            .accessibilityHint("已保存的长图不会被删除")
        }
        .frame(maxWidth: 380)
        .background {
            if reduceTransparency || colorSchemeContrast == .increased {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.regularMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(hairline, lineWidth: 1)
        }
        .shadow(color: ScrollPalette.ink.opacity(0.12), radius: 18, y: 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paperBackground: some View {
        ScrollPalette.paper
            .overlay {
                Image("PaperTexture")
                    .resizable()
                    .scaledToFill()
                    .opacity(reduceTransparency ? 0.24 : 0.52)
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    private var brandHeader: some View {
        VStack(spacing: 13) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    brandName
                    Spacer()
                    brandCaption
                }

                VStack(alignment: .leading, spacing: 4) {
                    brandName
                    brandCaption
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle()
                .fill(hairline)
                .frame(height: 1)
        }
    }

    private var brandName: some View {
        Text("长卷")
            .font(.title2.weight(.semibold))
            .fontDesign(.serif)
            .foregroundStyle(ScrollPalette.ink)
    }

    private var brandCaption: some View {
        Text("LONG SCROLL")
            .font(.caption2.weight(.medium))
            .fontDesign(.rounded)
            .tracking(2.2)
            .foregroundStyle(ScrollPalette.secondaryInk)
    }

    private var introduction: some View {
        VStack(spacing: 12) {
            CaptureMark()
                .stroke(
                    ScrollPalette.ink,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 72, height: 82)
                .accessibilityHidden(true)

            Text("把滚动，收成一卷")
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(ScrollPalette.ink)
                .multilineTextAlignment(.center)

            Text("确认一次录制，在想停的位置完成。")
                .font(.body)
                .foregroundStyle(ScrollPalette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var systemEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("先设置一次，之后快速开始", systemImage: "switch.2")
                .font(.headline)
                .foregroundStyle(ScrollPalette.ink)

            Text("在控制中心的编辑页添加「长卷」，也可以把它设为操作按钮。在需要截图的界面轻点控制，确认 Apple 的「Share Entire Screen（共享整个屏幕）」后，等顶部面板收起再滚动。长按灵动岛可重新展开「接下一页／继续」和「完成」，不用返回 App；也可添加「长卷 · 接下一页」控制。")
                .font(.footnote)
                .foregroundStyle(ScrollPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                usageGuideIsInitial = false
                showingUsageGuide = true
            } label: {
                Label("重新查看使用方法", systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(ScrollPalette.ink)
            .padding(.top, 2)

            Button {
                guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Label("完成预览提醒设置", systemImage: "bell")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .accessibilityHint("在其他 App 中显示完成提示，需要允许长卷通知和横幅")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperPanel()
    }

    private var captureAction: some View {
        Button {
            if case .capturing = model.phase {
                Task { await model.stopCapture() }
            } else {
                model.beginCapture()
            }
        } label: {
            VStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(captureButtonColor)
                        .frame(width: 76, height: 76)
                        .shadow(
                            color: ScrollPalette.ink.opacity(reduceTransparency ? 0.06 : 0.14),
                            radius: 18,
                            y: 9
                        )

                    captureButtonSymbol
                }

                Text(captureActionTitle)
                    .font(.headline)
                    .foregroundStyle(ScrollPalette.ink)

                Text(captureActionHint)
                    .font(.footnote)
                    .foregroundStyle(ScrollPalette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(model.phase == .choosingSource || model.phase == .processing)
        .accessibilityLabel(captureActionTitle)
        .accessibilityHint(captureActionHint)
    }

    @ViewBuilder
    private var captureButtonSymbol: some View {
        switch model.phase {
        case .choosingSource, .processing:
            ProgressView()
                .tint(.white)
                .controlSize(.large)
        case .capturing:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.white)
                .frame(width: 23, height: 23)
        case .idle, .ready, .failed:
            CaptureMark()
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 38, height: 43)
        }
    }

    private var captureButtonColor: Color {
        if case .capturing = model.phase {
            return ScrollPalette.recording
        }
        return ScrollPalette.ink
    }

    private var captureActionTitle: String {
        switch model.phase {
        case .choosingSource:
            return "正在打开系统面板"
        case .capturing:
            return "结束并生成"
        case .processing:
            return "正在生成"
        case .idle, .ready, .failed:
            return "开始收卷"
        }
    }

    private var captureActionHint: String {
        switch model.phase {
        case .choosingSource:
            return "请在 Apple 面板中确认共享整个屏幕"
        case .capturing:
            return "长按灵动岛，可接下一页、继续或完成；也可使用控制中心的长卷控制"
        case .processing:
            return "正在识别重叠内容并保存到照片"
        case .idle, .ready, .failed:
            return "也可以从控制中心或操作按钮打开"
        }
    }

    private var statusCard: some View {
        Group {
            statusContent
                .id(phaseIdentity)
                .transition(phaseTransition)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperPanel()
        .animation(phaseAnimation, value: phaseIdentity)
    }

    @ViewBuilder
    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            switch model.phase {
            case .idle:
                statusHeading("准备好了", systemImage: "circle", color: ScrollPalette.success)
                supportingText("确认共享后先等顶部面板收起再滚动。长按灵动岛，可随时展开接下一页和完成按钮。")

            case .choosingSource:
                statusHeading("等待你的选择", systemImage: "rectangle.on.rectangle", color: ScrollPalette.ink)
                supportingText("保持在当前 App，确认共享整个屏幕后先停在原处，等顶部面板收起再滚动。")
#if !LONGSHOT_SCREEN_CAPTURE_KIT
                Button("取消本次开始") { model.cancelCaptureChoice() }
                    .buttonStyle(.bordered)
#endif

            case .capturing(let frameCount):
                statusHeading(model.isPageTransitionPaused ? "切换页面中" : "正在收卷", systemImage: model.isPageTransitionPaused ? "pause.circle" : "record.circle", color: ScrollPalette.recording)
                supportingText(model.isPageTransitionPaused
                    ? "采集已暂停。切到新页面后，在灵动岛轻点「继续」；切换动画不会进入长图。"
                    : frameCount == 0
                    ? "系统录制已连接。请在要截取的页面开始滚动；若从长卷内启动，再切回目标 App。"
                    : "已收到 " + String(frameCount) + " 个画面。可上下滚动；切换页面前，先在灵动岛点「接下一页」。")
#if LONGSHOT_SCREEN_CAPTURE_KIT
                Button(model.isPageTransitionPaused ? "在新页面继续" : "暂停并接下一页") {
                    Task { await model.togglePageTransition() }
                }
                .buttonStyle(.bordered)
#endif
                Button {
                    Task { await model.stopCapture() }
                } label: {
                    Label("现在结束并生成", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(ScrollPalette.recording)

            case .processing:
                HStack(spacing: 13) {
                    ProgressView()
                        .tint(ScrollPalette.ink)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("正在整理长卷")
                            .font(.headline)
                            .foregroundStyle(ScrollPalette.ink)
                        supportingText("正在识别重叠内容并保存到照片。")
                    }
                }

            case .ready(let pageCount, let accepted, let skipped):
                statusHeading("已经保存到照片", systemImage: "checkmark.circle", color: ScrollPalette.success)
                if let image = model.previewImage {
                    Button {
                        model.dismissSavedThumbnail()
                        showingFullPreview = true
                    } label: {
                        ZStack(alignment: .bottom) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 280)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(reduceTransparency ? 1 : 0.78))

                            Label("查看完整长图", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(ScrollPalette.ink.opacity(0.88), in: Capsule())
                                .padding(12)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(hairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .accessibilityLabel("查看完整长图")
                }

                Text(resultSummary(pageCount: pageCount, accepted: accepted, skipped: skipped))
                    .font(.footnote)
                    .foregroundStyle(ScrollPalette.secondaryInk)

                resultActions

            case .failed(let message):
                statusHeading("这一次没有成卷", systemImage: "exclamationmark.triangle", color: ScrollPalette.warning)
                supportingText(message)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { failureActions }
                    VStack(alignment: .leading, spacing: 10) { failureActions }
                }
            }
        }
    }

    @ViewBuilder
    private var resultActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                shareButton
                deleteButton
            }

            VStack(alignment: .leading, spacing: 10) {
                shareButton
                deleteButton
            }
        }
    }

    private var shareButton: some View {
        Button {
            showingShareSheet = true
        } label: {
            Label("分享", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.borderedProminent)
        .tint(ScrollPalette.ink)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label("清理记录", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .tint(ScrollPalette.secondaryInk)
    }

    @ViewBuilder
    private var failureActions: some View {
        Button("重新整理") {
            Task { await model.retryProcessing() }
        }
        .buttonStyle(.borderedProminent)
        .tint(ScrollPalette.ink)

        Button("清理后重录", role: .destructive) {
            showingDeleteConfirmation = true
        }
        .buttonStyle(.bordered)
        .tint(ScrollPalette.secondaryInk)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("三步成卷")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(ScrollPalette.ink)

            instructionRow(number: "01", text: "首次在控制中心添加「长卷」，也可以把它设为操作按钮。")
            instructionDivider
            instructionRow(number: "02", text: "在目标 App 里确认共享后，先等顶部面板收起，再缓慢向上或向下滚动。")
            instructionDivider
            instructionRow(number: "03", text: "长按灵动岛，选择「接下一页／继续」或「完成」；也可用控制中心里的长卷控制。")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperPanel()
    }

    private var instructionDivider: some View {
        Rectangle()
            .fill(hairline)
            .frame(height: 1)
            .padding(.leading, 41)
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(
                "所有画面只留在这台 iPhone。分享前仍建议检查姓名、头像等隐私信息。",
                systemImage: "lock"
            )

            HStack(spacing: 18) {
                Link("隐私政策", destination: URL(string: "https://changjuan-install-a7f4c2d9.wen-s-0413.chatgpt.site/privacy")!)
                Link("使用帮助", destination: URL(string: "https://changjuan-install-a7f4c2d9.wen-s-0413.chatgpt.site/support")!)
            }
            .fontWeight(.medium)
        }
        .font(.footnote)
        .foregroundStyle(ScrollPalette.secondaryInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var hairline: Color {
        ScrollPalette.ink.opacity(colorSchemeContrast == .increased ? 0.25 : 0.12)
    }

    private var phaseIdentity: Int {
        switch model.phase {
        case .idle: return 0
        case .choosingSource: return 1
        case .capturing: return 2
        case .processing: return 3
        case .ready: return 4
        case .failed: return 5
        }
    }

    private var phaseAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1)
    }

    private var phaseTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .scale(scale: 0.985))
    }

    private func statusHeading(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(color)
    }

    private func supportingText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(ScrollPalette.secondaryInk)
            .multilineTextAlignment(.leading)
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number)
                .font(.footnote.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(ScrollPalette.secondaryInk)
                .frame(width: 28, alignment: .leading)

            Text(text)
                .font(.body)
                .foregroundStyle(ScrollPalette.ink)
                .multilineTextAlignment(.leading)
                .layoutPriority(1)
        }
    }

    private func resultSummary(pageCount: Int, accepted: Int, skipped: Int) -> String {
        let pageText = pageCount == 1 ? "1 张长图" : "\(pageCount) 张连续长图"
        return "生成 \(pageText)，采用 \(accepted) 个有效画面，自动略过 \(skipped) 个重复或模糊画面。"
    }

    private func completeUsageGuidePresentation() {
        if usageGuideIsInitial {
            hasCompletedUsageGuide = true
        }
        usageGuideIsInitial = false
    }
}

struct CaptureMark: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let width = rect.width
        let height = rect.height

        var path = Path()
        path.move(to: CGPoint(x: x + width * 0.18, y: y + height * 0.40))
        path.addLine(to: CGPoint(x: x + width * 0.18, y: y + height * 0.18))
        path.addLine(to: CGPoint(x: x + width * 0.56, y: y + height * 0.18))

        path.move(to: CGPoint(x: x + width * 0.57, y: y + height * 0.58))
        path.addLine(to: CGPoint(x: x + width * 0.82, y: y + height * 0.58))
        path.addLine(to: CGPoint(x: x + width * 0.82, y: y + height * 0.39))

        path.move(to: CGPoint(x: x + width * 0.50, y: y + height * 0.68))
        path.addLine(to: CGPoint(x: x + width * 0.50, y: y + height * 0.84))
        return path
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct PaperPanelModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .padding(19)
            .background(
                Color.white.opacity(reduceTransparency ? 1 : 0.72),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        ScrollPalette.ink.opacity(colorSchemeContrast == .increased ? 0.25 : 0.12),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: ScrollPalette.ink.opacity(reduceTransparency ? 0 : 0.035),
                radius: 16,
                y: 7
            )
    }
}

private extension View {
    func paperPanel() -> some View {
        modifier(PaperPanelModifier())
    }
}

private struct LongImagePreview: View {
    let urls: [URL]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPage = 0
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if urls.isEmpty {
                    ContentUnavailableView("没有可预览的长图", systemImage: "photo")
                } else {
                    TabView(selection: $selectedPage) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            if let image = UIImage(contentsOfFile: url.path) {
                                ZoomableLongImage(image: image)
                                    .tag(index)
                            } else {
                                ContentUnavailableView("无法读取这张长图", systemImage: "photo.badge.exclamationmark")
                                    .tag(index)
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .navigationTitle(previewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .disabled(urls.isEmpty)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ActivityView(items: urls)
            }
        }
    }

    private var previewTitle: String {
        urls.count > 1 ? "长图 \(selectedPage + 1) / \(urls.count)" : "长图预览"
    }
}

private struct ZoomableLongImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .systemBackground

        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.image = image
        scrollView.addSubview(imageView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView.image = image
        context.coordinator.layoutImage(in: scrollView, image: image)
        DispatchQueue.main.async {
            context.coordinator.layoutImage(in: scrollView, image: image)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let horizontalInset = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let verticalInset = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }

        func layoutImage(in scrollView: UIScrollView, image: UIImage) {
            guard scrollView.bounds.width > 0, image.size.width > 0 else { return }
            let fittedHeight = scrollView.bounds.width * image.size.height / image.size.width
            imageView.frame = CGRect(x: 0, y: 0, width: scrollView.bounds.width, height: fittedHeight)
            scrollView.contentSize = imageView.frame.size
        }
    }
}
