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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("longshot.hasCompletedUsageGuide.v1") private var hasCompletedUsageGuide = false
    @AppStorage(AppLanguage.preferenceKey, store: AppLanguage.defaults) private var languageCode = AppLanguage.initialLanguage.rawValue
    @State private var showingDeleteConfirmation = false
    @State private var showingFailureDetails = false
    @State private var showingFullPreview = false
    @State private var showingUsageGuide = false
    @State private var usageGuideIsInitial = false
    @State private var showingSettings = false
    @AppStorage(CaptureOptions.axisKey) private var captureAxis = CaptureAxis.vertical.rawValue

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? AppLanguage.initialLanguage }

    var body: some View {
        NavigationStack {
            ZStack {
                paperBackground
                GeometryReader { geometry in
                    let region = homeRegion(in: geometry)
                    ScrollView(showsIndicators: false) {
                        homeContent(compact: region.height < 650)
                            .frame(minHeight: region.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: region.width, height: region.height)
                    .position(x: region.midX, y: region.midY)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                CaptureSettingsView(model: model)
            }
            .fullScreenCover(isPresented: fullPreviewBinding) {
                LongImagePreview(urls: model.outputURLs, omittedOccludedBottomRows: model.omittedOccludedBottomRows,
                                 outputsSeparatedByGeometry: model.outputsSeparatedByGeometry)
            }
            .fullScreenCover(isPresented: $showingUsageGuide, onDismiss: completeUsageGuidePresentation) {
                UsageGuideView(isFirstRun: usageGuideIsInitial) {
                    hasCompletedUsageGuide = true
                    showingUsageGuide = false
                }
            }
            .alert(language.text("这一次没有成卷"), isPresented: $showingFailureDetails) {
                Button(language.text("重新整理")) { Task { await model.retryProcessing() } }
                Button(language.text("清理后重录"), role: .destructive) {
                    showingDeleteConfirmation = true
                }
                Button(language.text("关闭"), role: .cancel) {}
            } message: {
                Text(failureMessage)
            }
            .confirmationDialog(language.text("清理这一次的本地记录？"), isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button(language.text("清理本地记录"), role: .destructive) { model.discardCurrentSession() }
                Button(language.text("取消"), role: .cancel) {}
            } message: {
                Text(language.text("已经保存到系统照片中的图片不会被删除。"))
            }
            .alert(language.text("预览已不可用"), isPresented: $model.isSavedPreviewUnavailable) {
                Button(language.text("关闭"), role: .cancel) {}
            } message: {
                Text(language.text("本地预览可能已自动清理，请到系统「照片」中查看已保存的长图。若已在照片中删除，长卷无法恢复。"))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.isSavedThumbnailPresented,
                   !fullPreviewBinding.wrappedValue,
                   !showingUsageGuide,
                   let image = model.previewImage {
                    savedThumbnail(image)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1), value: model.isSavedThumbnailPresented)
        }
        .tint(ScrollPalette.ink)
        .environment(\.appLanguage, language)
        .environment(\.locale, language.locale)
        .onAppear {
#if LONGSHOT_UI_CHECKS
            // Opt-in simulator snapshot route; excluded from ordinary builds.
            if ProcessInfo.processInfo.arguments.contains("--snapshot-settings") {
                showingSettings = true
                return
            }
#endif
            guard !hasCompletedUsageGuide, !showingUsageGuide else { return }
            usageGuideIsInitial = true
            showingUsageGuide = true
        }
    }

    /// Keep controls on one usable side of a fold/camera, using the regions
    /// reported for this view, never a device name or an orientation guess.
    private func homeRegion(in geometry: GeometryProxy) -> CGRect {
        var region = CGRect(origin: .zero, size: geometry.size)
        if #available(iOS 27.1, *) {
            let reserved = geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                + geometry.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed)
            for item in reserved where item.isActive {
                let blocked = item.frame.inset(by: UIEdgeInsets(top: -item.margins.top, left: -item.margins.leading,
                    bottom: -item.margins.bottom, right: -item.margins.trailing)).intersection(region)
                guard !blocked.isNull, !blocked.isEmpty else { continue }
                let candidates = [
                    CGRect(x: region.minX, y: region.minY, width: max(0, blocked.minX - region.minX), height: region.height),
                    CGRect(x: blocked.maxX, y: region.minY, width: max(0, region.maxX - blocked.maxX), height: region.height),
                    CGRect(x: region.minX, y: region.minY, width: region.width, height: max(0, blocked.minY - region.minY)),
                    CGRect(x: region.minX, y: blocked.maxY, width: region.width, height: max(0, region.maxY - blocked.maxY))
                ]
                if let best = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }), !best.isEmpty {
                    region = best
                }
            }
        }
        return region
    }

    private func homeContent(compact: Bool) -> some View {
        VStack(spacing: 0) {
            brandHeader
            Spacer(minLength: compact ? 12 : 24)
            VStack(spacing: compact ? 24 : 34) {
                VStack(spacing: 12) {
                    captureAction
                    if let hint = visibleCaptureHint {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(captureHintColor)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    contextualAction
                    if captureAxis == CaptureAxis.horizontal.rawValue, !model.isBusy {
                        Text(language.text("横向 · 左右滚动"))
                            .font(.footnote)
                            .foregroundStyle(ScrollPalette.secondaryInk)
                    }
                }

                Button {
                    usageGuideIsInitial = false
                    showingUsageGuide = true
                } label: {
                    Text(language.text("查看使用方法"))
                        .font(.callout)
                        .foregroundStyle(ScrollPalette.secondaryInk)
                        .frame(minWidth: 144, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(language.text("打开三步使用引导，查看控制中心设置和截图方法"))
                .accessibilityIdentifier("home.usageGuide")
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: compact ? 16 : 32)
            languageControls
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 24)
        .padding(.top, compact ? 12 : 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("home.singleScreen")
    }

    private var languageControls: some View {
        HStack(spacing: 16) {
            languageButton(.chinese, title: "中文")
            Spacer(minLength: 0)
            languageButton(.english, title: "English")
        }
        .accessibilityIdentifier("home.languageControls")
    }

    private func languageButton(_ option: AppLanguage, title: String) -> some View {
        Button {
            guard language != option else { return }
            languageCode = option.rawValue
            model.refreshLanguagePresentation()
        } label: {
            Text(verbatim: title)
                .font(.callout.weight(language == option ? .semibold : .regular))
                .foregroundStyle(language == option ? ScrollPalette.ink : ScrollPalette.secondaryInk)
                .frame(minWidth: 72, minHeight: 44, alignment: option == .chinese ? .leading : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text(option == .chinese ? "使用中文" : "使用英文"))
        .accessibilityAddTraits(language == option ? .isSelected : [])
        .accessibilityIdentifier(option == .chinese ? "home.language.zh" : "home.language.en")
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

    /// Newly saved images still offer transient feedback. Historical results
    /// no longer occupy the home screen; closing this never deletes Photos.
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
                        Text(language.text("已保存到照片"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ScrollPalette.ink)
                        Text(language.text(model.omittedOccludedBottomRows ? "底部遮挡行未收录，轻点查看" : "轻点预览长图"))
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
            .accessibilityLabel(language.text(model.omittedOccludedBottomRows
                ? "底部遮挡行未收录，轻点查看" : "已保存到照片，轻点预览刚刚生成的长图"))

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
            .accessibilityLabel(language.text("关闭缩略图提示"))
            .accessibilityHint(language.text("已保存的长图不会被删除"))
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
            HStack(alignment: .center, spacing: 12) {
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
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.regular))
                        .foregroundStyle(ScrollPalette.secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("设置"))
                .accessibilityIdentifier("home.settings")
            }

            Rectangle()
                .fill(hairline)
                .frame(height: 1)
        }
    }

    private var brandName: some View {
        Text(language.text("长卷"))
            .font(.title2.weight(.semibold))
            .fontDesign(.serif)
            .foregroundStyle(ScrollPalette.ink)
    }

    private var brandCaption: some View {
        Text(verbatim: language == .chinese ? "LONG SCROLL" : "CHANGJUAN")
            .font(.caption2.weight(.medium))
            .fontDesign(.rounded)
            .tracking(2.2)
            .foregroundStyle(ScrollPalette.secondaryInk)
    }

    private var captureAction: some View {
        Button {
            if case .capturing = model.phase {
                Task { await model.stopCapture() }
            } else {
                model.beginCapture()
            }
        } label: {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(captureButtonColor)
                        .frame(width: 88, height: 88)

                    captureButtonSymbol
                }

                if let title = visibleCaptureActionTitle {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ScrollPalette.ink)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(model.phase == .choosingSource || model.phase == .processing)
        .accessibilityLabel(captureActionTitle)
        .accessibilityHint(captureActionHint)
        .accessibilityIdentifier("home.capture")
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
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 42, height: 48)
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
            return language.text("正在打开系统面板")
        case .capturing:
            return language.text("结束并生成")
        case .processing:
            return language.text("正在生成")
        case .idle, .ready, .failed:
            return language.text("开始收卷")
        }
    }

    /// Idle capture stays icon-only; active states retain visible feedback.
    /// VoiceOver always receives the action title via accessibilityLabel.
    private var visibleCaptureActionTitle: String? {
        switch model.phase {
        case .idle, .ready, .failed:
            return nil
        case .choosingSource, .capturing, .processing:
            return captureActionTitle
        }
    }

    private var captureActionHint: String {
        switch model.phase {
        case .choosingSource:
            return language.text("请在 Apple 面板中确认共享整个屏幕")
        case .capturing:
            return language.text("长按灵动岛，可接下一页、继续或完成；也可使用控制中心的长卷控制")
        case .processing:
            return language.text("正在识别重叠内容并保存到照片")
        case .idle, .ready, .failed:
            return language.text("也可以从控制中心或操作按钮打开")
        }
    }

    @ViewBuilder
    private var contextualAction: some View {
        switch model.phase {
        case .capturing:
#if LONGSHOT_SCREEN_CAPTURE_KIT
            Button(language.text(model.isPageTransitionPaused ? "继续收卷" : "接下一页")) {
                Task { await model.togglePageTransition() }
            }
            .font(.callout)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("home.pageTransition")
#endif
        case .failed:
            Button(language.text("查看失败详情")) { showingFailureDetails = true }
                .font(.callout)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.failureDetails")
        case .idle, .choosingSource, .processing, .ready:
            EmptyView()
        }
    }

    private var visibleCaptureHint: String? {
        switch model.phase {
        case .choosingSource: return language.text("请确认共享整个屏幕")
        case .capturing:
            return language.text(model.isPageTransitionPaused ? "采集已暂停，切换页面后继续" : "回到目标页面继续滚动")
        case .processing: return language.text("完成后自动保存到照片")
        case .failed: return language.text("这一次没有成卷")
        case .idle, .ready: return nil
        }
    }

    private var captureHintColor: Color {
        if case .failed = model.phase { return ScrollPalette.warning }
        return ScrollPalette.secondaryInk
    }

    private var failureMessage: String {
        if case .failed(let message) = model.phase { return language.text(message) }
        return ""
    }

    private var hairline: Color {
        ScrollPalette.ink.opacity(colorSchemeContrast == .increased ? 0.25 : 0.12)
    }

    private func completeUsageGuidePresentation() {
        if usageGuideIsInitial {
            hasCompletedUsageGuide = true
        }
        usageGuideIsInitial = false
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLanguage.chinese
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
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


private struct LongImagePreview: View {
    let urls: [URL]
    let omittedOccludedBottomRows: Bool
    var outputsSeparatedByGeometry = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var selectedPage = 0
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if urls.isEmpty {
                    ContentUnavailableView(language.text("没有可预览的长图"), systemImage: "photo")
                } else {
                    TabView(selection: $selectedPage) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            if let image = UIImage(contentsOfFile: url.path) {
                                ZoomableLongImage(image: image, imageID: url)
                                    .tag(index)
                            } else {
                                ContentUnavailableView(language.text("无法读取这张长图"), systemImage: "photo.badge.exclamationmark")
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
            .safeAreaInset(edge: .top) {
                if outputsSeparatedByGeometry {
                    Text(language.text("屏幕尺寸或方向变化的内容已分开保存"))
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial)
                }
                if omittedOccludedBottomRows {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(language.text("底部遮挡行未收录"), systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                        Text(language.text("悬浮按钮遮住的底部内容无法完整恢复，已保留上方完整可见的行。原始画面保留至手动清理缓存。"))
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label(language.text("完成"), systemImage: "checkmark")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label(language.text("分享"), systemImage: "square.and.arrow.up")
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
        urls.count > 1 ? language.format("长图 %ld / %ld", selectedPage + 1, urls.count) : language.text("长图预览")
    }
}

private struct ZoomableLongImage: UIViewRepresentable {
    let image: UIImage
    var imageID: URL? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = ResizingScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.contentInsetAdjustmentBehavior = .automatic
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .systemBackground
        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        scrollView.onResize = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let coordinator, let scrollView else { return }
            coordinator.layoutImage(in: scrollView, image: coordinator.imageView.image ?? image,
                                    imageID: coordinator.previousImageID)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.layoutImage(in: scrollView, image: image, imageID: imageID)
    }

    class ResizingScrollView: UIScrollView {
        var onResize: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onResize?()
        }
        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            onResize?()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        private var previousSize = CGSize.zero
        private var previousSystemInsets = UIEdgeInsets.zero
        private var previousImage: UIImage?
        private(set) var previousImageID: URL?
        private var readingAnchor = CGPoint.zero
        private var isLayingOut = false

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        private func systemInsets(in scrollView: UIScrollView) -> UIEdgeInsets {
            let adjusted = scrollView.adjustedContentInset, own = scrollView.contentInset
            return UIEdgeInsets(top: adjusted.top - own.top, left: adjusted.left - own.left,
                                bottom: adjusted.bottom - own.bottom, right: adjusted.right - own.right)
        }

        private func viewport(size: CGSize, insets: UIEdgeInsets) -> CGRect {
            CGRect(x: insets.left, y: insets.top,
                width: max(0, size.width - insets.left - insets.right),
                height: max(0, size.height - insets.top - insets.bottom))
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let visible = viewport(size: scrollView.bounds.size, insets: systemInsets(in: scrollView))
            let horizontal = max((visible.width - scrollView.contentSize.width) / 2, 0)
            let vertical = max((visible.height - scrollView.contentSize.height) / 2, 0)
            let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
            if scrollView.contentInset != inset { scrollView.contentInset = inset }
            rememberReadingPosition(in: scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { rememberReadingPosition(in: scrollView) }

        func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
            guard let image = imageView.image else { return }
            layoutImage(in: scrollView, image: image, imageID: previousImageID)
        }

        private func rememberReadingPosition(in scrollView: UIScrollView) {
            guard !isLayingOut, previousImage != nil, previousSize == scrollView.bounds.size,
                  previousSystemInsets == systemInsets(in: scrollView) else { return }
            readingAnchor = anchor(in: scrollView)
        }

        private func anchor(in scrollView: UIScrollView) -> CGPoint {
            let visible = viewport(size: scrollView.bounds.size, insets: systemInsets(in: scrollView))
            let point = imageView.convert(CGPoint(x: scrollView.contentOffset.x + visible.midX,
                y: scrollView.contentOffset.y + visible.midY), from: scrollView)
            return CGPoint(x: point.x / max(1, imageView.bounds.width), y: point.y / max(1, imageView.bounds.height))
        }

        func layoutImage(in scrollView: UIScrollView, image: UIImage, imageID: URL? = nil) {
            let size = scrollView.bounds.size
            let system = systemInsets(in: scrollView)
            let visible = viewport(size: size, insets: system)
            let sameImage = previousImage === image || (imageID != nil && previousImageID == imageID)
            guard !isLayingOut, visible.width > 0, visible.height > 0,
                  image.size.width > 0, image.size.height > 0,
                  size != previousSize || system != previousSystemInsets || !sameImage else { return }
            isLayingOut = true
            defer { isLayingOut = false }
            let restoring = sameImage && previousSize != .zero
            let oldZoom = restoring ? scrollView.zoomScale : 1
            let savedAnchor = readingAnchor
            scrollView.setZoomScale(1, animated: false)
            imageView.image = image
            let wide = image.size.width > image.size.height
            let fit = wide ? min(1, visible.height / image.size.height) : visible.width / image.size.width
            let base = CGSize(width: image.size.width * fit, height: image.size.height * fit)
            imageView.frame = CGRect(origin: .zero, size: base)
            scrollView.contentSize = base
            scrollView.alwaysBounceVertical = !wide
            scrollView.alwaysBounceHorizontal = wide
            scrollView.setZoomScale(oldZoom, animated: false)
            scrollViewDidZoom(scrollView)
            let point = imageView.convert(CGPoint(x: savedAnchor.x * base.width, y: savedAnchor.y * base.height), to: scrollView)
            let inset = scrollView.adjustedContentInset
            let desired = restoring ? CGPoint(x: point.x - visible.midX, y: point.y - visible.midY)
                : CGPoint(x: -inset.left, y: -inset.top)
            scrollView.contentOffset = CGPoint(
                x: min(max(-inset.left, desired.x), max(-inset.left, scrollView.contentSize.width - size.width + inset.right)),
                y: min(max(-inset.top, desired.y), max(-inset.top, scrollView.contentSize.height - size.height + inset.bottom)))
            previousSize = size
            previousSystemInsets = system
            previousImage = image
            previousImageID = imageID
            readingAnchor = anchor(in: scrollView)
        }
    }
}

struct CaptureSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(CaptureOptions.axisKey) private var axis = CaptureAxis.vertical.rawValue
    @AppStorage(CaptureOptions.statusBarKey) private var keepsStatusBar = false
    @State private var confirmingCleanup = false
    @State private var cleanupMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            directionPicker.pickerStyle(.inline)
                        } else {
                            directionPicker.pickerStyle(.segmented)
                        }
                    }
                    .accessibilityIdentifier("settings.axis")
                    .disabled(model.isBusy)
                } header: {
                    if !dynamicTypeSize.isAccessibilitySize { Text(language.text("拼接方向")) }
                } footer: {
                    Text(language.text("横向适合左右拖动的表格。一次录制只使用一种方向；更改仅影响新录制。"))
                }
                Section {
                    Toggle(language.text("保留状态栏"), isOn: $keepsStatusBar)
                        .accessibilityIdentifier("settings.statusBar")
                        .disabled(model.isBusy)
                } footer: {
                    Text(language.text("保留实际录制到的时间、信号和电量，也可能包含录制指示。无法确认状态栏边界时保留完整画面，避免裁掉正文。"))
                }
                Section {
                    Button(role: .destructive) { confirmingCleanup = true } label: {
                        HStack {
                            Text(language.text("清理所有缓存"))
                            Spacer()
                            if model.isClearingCaches { ProgressView() }
                        }
                    }
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("settings.clearCache")
                    if let cleanupMessage {
                        Text(cleanupMessage).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.cleanupResult")
                    }
                } header: {
                    Text(language.text("存储"))
                } footer: {
                    Text(language.text("仅清理原始画面和分析缓存，保留系统照片与已生成的本地预览。"))
                }
                if model.isBusy {
                    Section {
                        Text(language.text("请等待当前录制、整理或清理完成后再修改设置。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScrollPalette.paper)
            .navigationTitle(language.text("设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Label(language.text("完成"), systemImage: "checkmark")
                    }
                }
            }
            .alert(language.text("清理所有缓存？"), isPresented: $confirmingCleanup) {
                Button(language.text("清理缓存"), role: .destructive) {
                    Task {
                        guard let report = await model.clearAllRawCaches() else { return }
                        if report.failures > 0 {
                            cleanupMessage = language.text("部分缓存未能清理，请稍后重试。")
                        } else if report.reclaimedBytes == 0 {
                            cleanupMessage = language.text("没有可清理的缓存。")
                        } else {
                            let size = ByteCountFormatter.string(fromByteCount: report.reclaimedBytes, countStyle: .file)
                            cleanupMessage = language.format("已清理 %@，照片和预览未删除。", size)
                        }
                    }
                }
                Button(language.text("取消"), role: .cancel) {}
            } message: {
                Text(language.text("这会删除所有原始画面和分析缓存，尚未保存的记录将无法重新整理。系统照片和已生成的本地预览不会被删除。此操作无法撤销。"))
            }
        }
        .tint(ScrollPalette.ink)
#if LONGSHOT_UI_CHECKS
        .onAppear {
            confirmingCleanup = ProcessInfo.processInfo.arguments.contains("--snapshot-cleanup-confirmation")
        }
#endif
    }

    private var directionPicker: some View {
        Picker(language.text("拼接方向"), selection: $axis) {
            Text(language.text("纵向")).tag(CaptureAxis.vertical.rawValue)
            Text(language.text("横向")).tag(CaptureAxis.horizontal.rawValue)
        }
    }
}
