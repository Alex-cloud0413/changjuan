import SwiftUI
import UIKit

@main
@MainActor
struct CaptureActivityVisualCheck {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        for (name, size) in [("island-standard", DynamicTypeSize.large), ("island-accessible", .accessibility2)] {
            let content = VStack(alignment: .leading, spacing: 16) {
                Text("正在收卷 / 切换页面中 · 实际操作行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                row(phase: .capturing)
                row(phase: .paused)
            }
            .padding(16)
            .frame(width: 390)
            .background(Color(white: 0.18))
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, size)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            guard let image = renderer.uiImage, let data = image.pngData() else {
                fatalError("SwiftUI render failed")
            }
            try data.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    private static func row(phase: CaptureSurfacePhase) -> some View {
        CaptureIslandRow(state: .init(phase: phase, frameCount: 32, pageCount: 0))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.black, in: RoundedRectangle(cornerRadius: 32))
    }
}
