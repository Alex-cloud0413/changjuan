import AppIntents
import SwiftUI
import WidgetKit

struct LongScrollCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: CaptureSystem.controlKind,
            provider: Provider()
        ) { phase in
            ControlWidgetButton(action: ToggleLongScrollIntent()) {
                Label {
                    Text(controlTitle(for: phase))
                } icon: {
                    Image(.longJuanCaptureV2)
                        .symbolRenderingMode(.monochrome)
                }
            }
        }
        .displayName("长卷")
        .description("开始长截图，或在到达目标位置后立即完成。")
    }

    private func controlTitle(for phase: CaptureSurfacePhase) -> String {
        switch phase {
        case .capturing, .paused:
            return "完成长卷"
        case .choosing:
            return "等待选择"
        case .processing:
            return "正在生成"
        case .idle, .saved, .failed:
            return "开始长卷"
        }
    }

}

extension LongScrollCaptureControl {
    struct Provider: ControlValueProvider {
        var previewValue: CaptureSurfacePhase { .idle }

        func currentValue() async throws -> CaptureSurfacePhase {
            CaptureCommandStore.phase
        }
    }
}

/// Optional persistent alternative when people cannot discover the Dynamic
/// Island's long-press gesture. It never starts a new recording by accident.
struct LongScrollPageControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: CaptureSystem.pageControlKind,
            provider: LongScrollCaptureControl.Provider()
        ) { phase in
            ControlWidgetButton(action: NextLongScrollPageIntent()) {
                Label {
                    Text(phase == .paused ? "继续收卷" : "接下一页")
                } icon: {
                    Image(.longJuanCaptureV2)
                        .symbolRenderingMode(.monochrome)
                }
            }
            .disabled(phase != .capturing && phase != .paused)
        }
        .displayName("长卷 · 接下一页")
        .description("收卷时暂停采集，切换页面后再次轻点继续。不会跳回 App。")
    }
}
