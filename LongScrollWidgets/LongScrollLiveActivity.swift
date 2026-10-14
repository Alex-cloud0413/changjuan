import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum ActivityPalette {
    static let paper = Color(red: 0.992, green: 0.988, blue: 0.976)
    static let ink = Color(red: 0.145, green: 0.145, blue: 0.13)
    static let recording = Color(red: 0.62, green: 0.24, blue: 0.18)
    static let success = Color(red: 0.27, green: 0.39, blue: 0.30)
}

struct LongScrollLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LongScrollActivityAttributes.self) { context in
            Group {
                if context.state.phase == .capturing || context.state.phase == .paused {
                    CaptureIslandRow(state: context.state)
                        .foregroundStyle(ActivityPalette.ink)
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: statusSymbol(for: context.state.phase))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(statusColor(for: context.state.phase))
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(statusTitle(for: context.state))
                                .font(.headline)
                                .foregroundStyle(ActivityPalette.ink)
                            Text(statusDetail(for: context.state))
                                .font(.caption)
                                .foregroundStyle(ActivityPalette.ink.opacity(0.68))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                }
            }
            .padding(.horizontal, 4)
            .activityBackgroundTint(ActivityPalette.paper)
            .activitySystemActionForegroundColor(ActivityPalette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                // A single action row replaces the title/counter row plus a
                // full-width second button row. iOS still owns expansion timing.
                DynamicIslandExpandedRegion(.center) {
                    CaptureIslandRow(state: context.state)
                }
            } compactLeading: {
                Image(systemName: statusSymbol(for: context.state.phase))
                    .foregroundStyle(statusColor(for: context.state.phase))
            } compactTrailing: {
                Text(shortStatus(for: context.state))
                    .font(.caption2.monospacedDigit())
                    .accessibilityLabel(context.state.language.text("长按灵动岛，显示接下一页、继续和完成按钮"))
            } minimal: {
                Image(systemName: statusSymbol(for: context.state.phase))
                    .foregroundStyle(statusColor(for: context.state.phase))
            }
            .widgetURL(URL(string: "longshot://capture"))
            .keylineTint(statusColor(for: context.state.phase))
        }
    }

    private func statusTitle(
        for state: LongScrollActivityAttributes.ContentState
    ) -> String {
        switch state.phase {
        case .idle:
            return state.language.text("长卷")
        case .choosing:
            return state.language.text("等待系统选择")
        case .capturing:
            return state.language.text("正在收卷")
        case .paused:
            return state.language.text("切换页面中")
        case .processing:
            return state.language.text("正在生成长图")
        case .saved:
            return state.language.text("已保存到照片")
        case .failed:
            return state.language.text("这一次没有成卷")
        }
    }

    private func statusDetail(
        for state: LongScrollActivityAttributes.ContentState
    ) -> String {
        switch state.phase {
        case .idle:
            return state.language.text("从控制中心打开")
        case .choosing:
            return state.language.text("请确认长卷录制")
        case .capturing:
            return state.language.text("到达目标位置后轻点完成")
        case .paused:
            return state.language.text("采集已暂停，切到新页面后轻点继续")
        case .processing:
            return state.language.text("可继续使用其他 App")
        case .saved:
            return state.pageCount > 1 ? state.language.format("已生成 %ld 张图片", state.pageCount) : state.language.text("长图已经可以使用")
        case .failed:
            return state.language.text("打开长卷查看原因")
        }
    }

    private func shortStatus(
        for state: LongScrollActivityAttributes.ContentState
    ) -> String {
        switch state.phase {
        case .capturing:
            return state.language.text("长按操作")
        case .paused:
            return state.language.text("长按继续")
        case .processing:
            return state.language.text("整理中")
        case .saved:
            return state.language.text("已保存")
        case .failed:
            return state.language.text("失败")
        case .idle:
            return state.language.text("就绪")
        case .choosing:
            return state.language.text("等待中")
        }
    }

    private func statusSymbol(for phase: CaptureSurfacePhase) -> String {
        switch phase {
        case .capturing:
            return "record.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .processing:
            return "ellipsis.circle"
        case .saved:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "rectangle.stack"
        case .choosing:
            return "rectangle.on.rectangle"
        }
    }

    private func statusColor(for phase: CaptureSurfacePhase) -> Color {
        switch phase {
        case .capturing, .paused, .failed:
            return ActivityPalette.recording
        case .saved:
            return ActivityPalette.success
        case .processing, .idle, .choosing:
            return ActivityPalette.ink
        }
    }
}

/// Shared with the local visual-check harness: this is the actual shipping
/// expanded content, not a screenshot mock of the system's Dynamic Island.
struct CaptureIslandRow: View {
    let state: LongScrollActivityAttributes.ContentState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    title
                    actions
                }
            } else {
                HStack(spacing: 8) {
                    title
                    Spacer(minLength: 0)
                    actions
                }
            }
            if state.phase == .capturing {
                Text(state.language.text("等面板收起再滚动 · 长按灵动岛接页"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if state.phase == .paused {
                Text(state.language.text("切换页面后点继续，再等面板收起滚动"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            Image(systemName: state.phase == .paused ? "pause.circle.fill" : "record.circle.fill")
                .foregroundStyle(ActivityPalette.recording)
                .accessibilityHidden(true)
            Text(state.language.text(state.phase == .paused ? "暂停" : "长卷"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var actions: some View {
        if state.phase == .capturing || state.phase == .paused {
            CaptureActivityActions(paused: state.phase == .paused, language: state.language)
        } else {
            Text(state.language.text(state.phase == .saved ? "已保存" : state.phase == .failed ? "失败" : "整理中"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CaptureActivityActions: View {
    let paused: Bool
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: NextLongScrollPageIntent()) {
                Text(language.text(paused ? "继续" : "接下一页"))
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.gray)
            .accessibilityLabel(language.text(paused ? "在新页面继续收卷" : "暂停收卷，接下一页"))

            Button(intent: FinishLongScrollIntent()) {
                Text(language.text("完成"))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(ActivityPalette.recording)
            .accessibilityLabel(language.text("完成长卷并保存到照片"))
        }
    }
}
