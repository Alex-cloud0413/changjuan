import SwiftUI
import UIKit

/// Screenshot-only entry point copied into a disposable project. Not part of
/// the shipping Xcode target. No recording, Photos writes or network requests.
@main
struct StoreScreenshotApp: App {
    @StateObject private var model = AppModel.shared
    private let mode: String
    private let outputs: [URL]

    init() {
        UserDefaults.standard.set(true, forKey: "longshot.hasCompletedUsageGuide.v1")
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--reset-language") {
            AppLanguage.defaults.removeObject(forKey: AppLanguage.preferenceKey)
        } else if let index = args.firstIndex(of: "--language"), args.indices.contains(index + 1),
           let language = AppLanguage(rawValue: args[index + 1]) {
            AppLanguage.defaults.set(language.rawValue, forKey: AppLanguage.preferenceKey)
        }
        mode = args.contains("--guide") ? "guide" : args.contains("--result") ? "result" : "home"
        if mode == "result" {
            do { outputs = try StoreExample.makeResult() }
            catch { fatalError("Production stitcher rejected store fixture: \(error)") }
        } else { outputs = [] }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if mode == "guide" {
                    UsageGuideView(isFirstRun: false, onDismiss: {})
                } else if mode == "result" {
                    LongImagePreview(urls: outputs)
                } else {
                    ContentView(model: model)
                }
            }
            .preferredColorScheme(.light)
            .environment(\.appLanguage, AppLanguage.current)
            .environment(\.locale, AppLanguage.current.locale)
        }
    }
}

private enum StoreExample {
    static func makeResult() throws -> [URL] {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StoreFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let width: CGFloat = 440
        let pageHeight: CGFloat = 3400
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let paragraphs = [
            ("01", "沿着河岸，慢慢走", "把周末留给一条熟悉的路。\n不赶时间，也不必安排得很满。", "RIVERSIDE"),
            ("02", "路过一家小书店", "挑一本想读很久的书，坐在窗边。\n光落在纸上，是下午最安静的片刻。", "BOOKSHOP"),
            ("03", "留一份简单的午餐", "一碗热汤，一份刚出炉的面包。\n好好吃饭，也是今天的安排。", "LUNCH"),
            ("04", "抬头看看天空", "街道、树影和云，都值得停一下。\n把看到的细节，记在这一页。", "AFTERNOON"),
            ("05", "换一条路回家", "顺着落日的方向，再散步一会儿。\n熟悉的城市，也会有新的角落。", "SUNSET"),
            ("06", "把这一天收起来", "不需要特别的目的地。\n这一份慢慢完成的记录，就很好。", "WEEKEND")
        ]
        let page = UIGraphicsImageRenderer(size: CGSize(width: width, height: pageHeight), format: format).image { context in
            UIColor(red: 0.97, green: 0.965, blue: 0.95, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: pageHeight))
            text("周末散步笔记", x: 28, y: 22, size: 34, weight: .semibold)
            text("一页记录 · 示例内容", x: 29, y: 77, size: 15, color: .secondaryLabel)
            for (index, item) in paragraphs.enumerated() {
                let y = CGFloat(index) * 515 + 133
                UIColor.white.setFill()
                UIBezierPath(roundedRect: CGRect(x: 20, y: y, width: 400, height: 475), cornerRadius: 20).fill()
                text(item.0, x: 39, y: y + 23, size: 14, color: .secondaryLabel)
                text(item.1, x: 39, y: y + 52, size: 24, weight: .semibold)
                text(item.2, x: 39, y: y + 94, size: 16, color: .secondaryLabel)
                let scene = CGRect(x: 39, y: y + 169, width: 362, height: 250)
                UIColor(red: 0.83 - Double(index) * 0.022, green: 0.88 - Double(index) * 0.031, blue: 0.86 - Double(index) * 0.029, alpha: 1).setFill()
                UIBezierPath(roundedRect: scene, cornerRadius: 13).fill()
                let cg = context.cgContext
                cg.saveGState()
                UIBezierPath(roundedRect: scene, cornerRadius: 13).addClip()
                UIColor(red: 0.96, green: 0.91, blue: 0.77, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: 289 - CGFloat(index) * 17, y: y + 192, width: 59, height: 59)).fill()
                UIColor(red: 0.34, green: 0.47, blue: 0.42, alpha: 1).setFill()
                let hills = UIBezierPath()
                hills.move(to: CGPoint(x: 39, y: y + 343))
                hills.addCurve(to: CGPoint(x: 401, y: y + 307), controlPoint1: CGPoint(x: 145, y: y + 208 + CGFloat(index) * 14), controlPoint2: CGPoint(x: 245, y: y + 396))
                hills.addLine(to: CGPoint(x: 401, y: y + 419))
                hills.addLine(to: CGPoint(x: 39, y: y + 419))
                hills.close(); hills.fill()
                UIColor.white.withAlphaComponent(0.42).setFill()
                context.fill(CGRect(x: 39, y: y + 370 + CGFloat(index) * 4, width: 362, height: 2))
                cg.restoreGState()
                text(item.3, x: 41, y: y + 439, size: 12, color: .secondaryLabel)
            }
            text("今天，就走到这里。", x: 28, y: 3274, size: 23, weight: .medium)
        }
        var frames: [URL] = []
        for (index, offset) in stride(from: 0, through: 2520, by: 360).enumerated() {
            let frame = UIGraphicsImageRenderer(size: CGSize(width: width, height: 956), format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: 956))
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: 80, width: width, height: 790))
                page.draw(at: CGPoint(x: 0, y: 80 - CGFloat(offset)))
                context.cgContext.restoreGState()
                text("散步笔记", x: 26, y: 34, size: 18, weight: .semibold)
                text("仅用于展示 · 无真实个人信息", x: 28, y: 899, size: 13, color: .secondaryLabel)
            }
            let url = directory.appendingPathComponent(String(format: "frame-%03d.jpg", index))
            try frame.jpegData(compressionQuality: 0.96)!.write(to: url)
            frames.append(url)
        }
        let result = try FrameStitcher().stitch(frameURLs: frames, sessionURL: directory)
        print("Store fixture: accepted=\(result.acceptedFrameCount), skipped=\(result.skippedFrameCount), outputs=\(result.outputURLs)")
        return result.outputURLs
    }

    private static func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat,
                             weight: UIFont.Weight = .regular, color: UIColor = .label) {
        (value as NSString).draw(in: CGRect(x: x, y: y, width: 440 - x - 25, height: 110),
                                withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
}
