import SwiftUI
import UIKit

struct UsageGuideView: View {
    let isFirstRun: Bool
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.appLanguage) private var language
    @State private var selectedStep = 0

    private let stepCount = 3

    var body: some View {
        ZStack {
            guideBackground

            VStack(spacing: 0) {
                guideHeader

                TabView(selection: $selectedStep) {
                    addControlStep.tag(0)
                    startCaptureStep.tag(1)
                    finishCaptureStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                guideFooter
            }
        }
        .tint(ScrollPalette.ink)
        .preferredColorScheme(.light)
    }

    private var guideBackground: some View {
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

    private var guideHeader: some View {
        HStack {
            HStack(spacing: 9) {
                CaptureMark()
                    .stroke(
                        ScrollPalette.ink,
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 25, height: 29)

                Text(language.text("长卷"))
                    .font(.headline)
                    .fontDesign(.serif)
            }

            Spacer()

            Button(language.text(isFirstRun ? "跳过" : "关闭"), action: onDismiss)
                .font(.subheadline.weight(.medium))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
        .foregroundStyle(ScrollPalette.ink)
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var addControlStep: some View {
        guidePage(
            eyebrow: "第 1 步 · 只需设置一次",
            title: "把长卷放进控制中心",
            summary: "以后无论正在看微信、淘宝还是网页，都能从控制中心快速唤起长卷。",
            illustration: AnyView(ControlCenterSetupIllustration()),
            instructions: [
                "从屏幕右上角向下轻扫，打开控制中心。",
                "长按空白处或轻点左上角「＋」进入编辑，再轻点「添加控制」。",
                "搜索「长卷」或「Long Scroll」，轻点三笔标志把它加入控制中心。"
            ],
            accessibilityLabel: "控制中心设置示意图，显示长卷三笔标志和添加控制按钮"
        )
    }

    private var startCaptureStep: some View {
        guidePage(
            eyebrow: "第 2 步 · 确认一次录制",
            title: "轻点长卷，确认开始",
            summary: "在当前界面确认 Apple 的整个屏幕共享，然后继续滚动。",
            illustration: AnyView(StartCaptureIllustration()),
            instructions: [
                "先打开要截取的内容，停在想要的起点。",
                "打开控制中心，轻点「长卷」。",
                "控制中心收起后，当前 App 保持不变；轻点 Apple 面板中的「Share Entire Screen（共享整个屏幕）」。",
                "先等灵动岛面板与系统共享提示收起，再沿设置中的拼接方向缓慢滚动；等待时停在原处。"
            ],
            accessibilityLabel: "Apple 录制确认面板示意图，突出显示共享整个屏幕"
        )
    }

    private var finishCaptureStep: some View {
        guidePage(
            eyebrow: "第 3 步 · 到哪里停在哪里",
            title: "滚动内容，轻点完成",
            summary: "不用等待固定倒计时；确认完成后，长卷会立即整理并保存到照片。",
            illustration: AnyView(FinishCaptureIllustration()),
            instructions: [
                "纵向模式可上下往返，横向模式可左右往返。请保持同一方向轴，长卷会按内容顺序去重拼接。",
                "长按顶部灵动岛即可重新展开操作。要切换页面，先点「接下一页」暂停，切换后长按灵动岛再点「继续」。",
                "也可添加「长卷 · 接下一页」（Long Scroll · Next page）控制，直接暂停或继续，不用返回长卷。",
                "到达想要的终点，长按灵动岛后点「完成」，或再次点控制中心里的「长卷」。",
                "保存后，长卷内会浮出缩略图，轻点查看完整长图；在其他 App 中的提醒需要允许通知。"
            ],
            accessibilityLabel: "滚动与完成示意图，显示灵动岛中的完成按钮"
        )
    }

    private func guidePage(
        eyebrow: String,
        title: String,
        summary: String,
        illustration: AnyView,
        instructions: [String],
        accessibilityLabel: String
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                VStack(spacing: 9) {
                    Text(language.text(eyebrow))
                        .font(.caption.weight(.semibold))
                        .fontDesign(.rounded)
                        .tracking(0.8)
                        .foregroundStyle(ScrollPalette.secondaryInk)

                    Text(language.text(title))
                        .font(.largeTitle.weight(.semibold))
                        .fontDesign(.serif)
                        .foregroundStyle(ScrollPalette.ink)
                        .multilineTextAlignment(.center)

                    Text(language.text(summary))
                        .font(.body)
                        .foregroundStyle(ScrollPalette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                illustration
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(language.text(accessibilityLabel))

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                        GuideInstructionRow(number: index + 1, text: language.text(instruction))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    Color.white.opacity(reduceTransparency ? 1 : 0.72),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(ScrollPalette.ink.opacity(0.12), lineWidth: 1)
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var guideFooter: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedStep ? ScrollPalette.ink : ScrollPalette.ink.opacity(0.16))
                        .frame(width: index == selectedStep ? 22 : 7, height: 7)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1),
                            value: selectedStep
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language.format("第 %ld 步，共 %ld 步", selectedStep + 1, stepCount))

            Button {
                if selectedStep == stepCount - 1 {
                    onDismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1)) {
                        selectedStep += 1
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(language.text(selectedStep == stepCount - 1 ? "我会用了" : "下一步"))
                    Image(systemName: selectedStep == stepCount - 1 ? "checkmark" : "arrow.right")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 15))
            .controlSize(.large)
            .tint(ScrollPalette.ink)

            HStack(spacing: 22) {
                if selectedStep == stepCount - 1 {
                    Button {
                        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        Text(language.text("通知提醒设置"))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(language.text("在其他 App 中显示完成提示，需要允许长卷通知和横幅"))
                }

                Link(destination: URL(string: "https://changjuan-install-a7f4c2d9.wen-s-0413.chatgpt.site/privacy")!) {
                    Text(language.text("隐私政策"))
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("usageGuide.privacyPolicy")
                .accessibilityHint(language.text("打开长卷的隐私政策网页"))
            }
            .font(.footnote)
            .foregroundStyle(ScrollPalette.secondaryInk)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(reduceTransparency ? 1 : 0.76))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ScrollPalette.ink.opacity(0.1))
                .frame(height: 1)
        }
    }
}

private struct GuideInstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(number))
                .font(.caption.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(ScrollPalette.ink, in: Circle())

            Text(text)
                .font(.body)
                .foregroundStyle(ScrollPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ControlCenterSetupIllustration: View {
    @Environment(\.appLanguage) private var language
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.82))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(ScrollPalette.ink.opacity(0.12), lineWidth: 1)
                }

            VStack(spacing: 14) {
                HStack(spacing: 11) {
                    controlPlaceholder(systemName: "airplane", wide: false)
                    controlPlaceholder(systemName: "wifi", wide: false)
                    controlPlaceholder(systemName: "sun.max.fill", wide: true)
                }

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(ScrollPalette.ink)
                            .frame(width: 58, height: 58)
                        CaptureMark()
                            .stroke(
                                Color.white,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: 31, height: 35)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("长卷"))
                            .font(.headline)
                            .fontDesign(.serif)
                        Text(language.text("截取滚动内容"))
                            .font(.caption)
                            .foregroundStyle(ScrollPalette.secondaryInk)
                    }

                    Spacer()

                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ScrollPalette.ink)
                }
                .padding(13)
                .background(ScrollPalette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Label(language.text("添加控制"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(ScrollPalette.ink.opacity(0.08), in: Capsule())
            }
            .padding(20)

            Image(systemName: "arrow.down")
                .font(.headline.weight(.semibold))
                .foregroundStyle(ScrollPalette.ink)
                .padding(10)
                .background(.white, in: Circle())
                .shadow(color: ScrollPalette.ink.opacity(0.1), radius: 8, y: 4)
                .offset(x: 9, y: -10)
        }
        .foregroundStyle(ScrollPalette.ink)
        .frame(height: 235)
    }

    private func controlPlaceholder(systemName: String, wide: Bool) -> some View {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .fill(ScrollPalette.ink.opacity(0.08))
            .frame(maxWidth: wide ? .infinity : 58, minHeight: 58, maxHeight: 58)
            .overlay {
                Image(systemName: systemName)
                    .foregroundStyle(ScrollPalette.secondaryInk)
            }
    }
}

private struct StartCaptureIllustration: View {
    @Environment(\.appLanguage) private var language
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(alignment: .top) {
                    VStack(spacing: 11) {
                        HStack {
                            Circle().frame(width: 28, height: 28)
                            RoundedRectangle(cornerRadius: 4).frame(width: 84, height: 9)
                            Spacer()
                            Image(systemName: "magnifyingglass")
                        }
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(ScrollPalette.ink.opacity(index.isMultiple(of: 2) ? 0.07 : 0.11))
                                .frame(height: 24)
                        }
                    }
                    .foregroundStyle(ScrollPalette.ink.opacity(0.17))
                    .padding(20)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(ScrollPalette.ink.opacity(0.12), lineWidth: 1)
                }

            VStack(spacing: 12) {
                Capsule()
                    .fill(ScrollPalette.ink.opacity(0.14))
                    .frame(width: 38, height: 5)

                Text(language.text("开始屏幕录制"))
                    .font(.headline)
                    .foregroundStyle(ScrollPalette.ink)

                HStack(spacing: 12) {
                    Image(systemName: "rectangle.inset.filled")
                        .font(.title3)
                        .frame(width: 38, height: 38)
                        .background(ScrollPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share Entire Screen")
                            .font(.subheadline.weight(.semibold))
                        Text(language.text("仅在设备上整理画面"))
                            .font(.caption)
                            .foregroundStyle(ScrollPalette.secondaryInk)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                }
                .foregroundStyle(ScrollPalette.ink)
                .padding(13)
                .background(ScrollPalette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: ScrollPalette.ink.opacity(0.1), radius: 18, y: 8)
            .padding(13)
        }
        .frame(height: 235)
    }
}

private struct FinishCaptureIllustration: View {
    @Environment(\.appLanguage) private var language
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.82))
                .overlay {
                    VStack(spacing: 10) {
                        ForEach(0..<7, id: \.self) { index in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(ScrollPalette.ink.opacity(index.isMultiple(of: 2) ? 0.12 : 0.07))
                                    .frame(width: 58, height: 20)
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(ScrollPalette.ink.opacity(0.08))
                                    .frame(height: 9)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 61)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(ScrollPalette.ink.opacity(0.12), lineWidth: 1)
                }

            HStack(spacing: 8) {
                Circle()
                    .fill(ScrollPalette.recording)
                    .frame(width: 8, height: 8)
                Text(language.text("完成"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(.black, in: Capsule())
            .padding(.top, 12)

            VStack {
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ScrollPalette.ink)
                    .padding(11)
                    .background(.white, in: Circle())
                    .shadow(color: ScrollPalette.ink.opacity(0.1), radius: 8, y: 4)
                    .padding(.bottom, 12)
            }
        }
        .frame(height: 235)
    }
}
