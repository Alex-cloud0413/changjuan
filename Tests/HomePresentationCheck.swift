import Foundation

@main
struct HomePresentationCheck {
    static func main() {
        for language in AppLanguage.allCases {
            for geometry in [false, true] {
                for omitted in [false, true] {
                    let result = HomePresentation(model: .init(outputsSeparatedByGeometry: geometry,
                        omittedOccludedBottomRows: omitted), language: language).savedThumbnailDescription
                    precondition(result.contains(language.text("屏幕尺寸或方向变化的内容已分开保存")) == geometry)
                    precondition(result.contains(language.text("底部遮挡行未收录")) == omitted)
                    precondition(result.hasSuffix(language.text("轻点预览长图")), "Every result remains actionable")
                    precondition(result.split(separator: "\n").count == 1 + (geometry ? 1 : 0) + (omitted ? 1 : 0),
                        "Geometry separation and omitted rows are independent qualifications")
                }
            }
            let expectedTitles = ["长卷", "等待系统选择", "正在收卷", "切换页面中", "正在生成长图", "已保存到照片", "这一次没有成卷"]
            for (phase, title) in zip(CaptureSurfacePhase.allCases, expectedTitles) {
                let state = LongScrollActivityAttributes.ContentState(phase: phase, language: language)
                let presentation = ActivityPresentation()
                precondition(presentation.statusTitle(for: state) == language.text(title))
                let hint = presentation.actionHint(for: state)
                precondition(hint.isEmpty == (phase != .capturing && phase != .paused),
                    "Processing/terminal states must not advertise unavailable capture actions")
                if !hint.isEmpty {
                    precondition(hint == language.text("长按灵动岛，显示接下一页、继续和完成按钮"))
                }
            }
        }
        print("Home result presentation passed: 8 flag/language combinations; compact/minimal activity labels and action availability in 14 phase/language combinations")
    }
}
