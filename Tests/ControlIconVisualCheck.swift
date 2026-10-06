import UIKit

/// Draws compiled symbols, not a replacement or mockup of the system panel.
@main
@MainActor
struct ControlIconVisualCheck {
    struct Metrics: Codable {
        let symbol: String
        let weight: String
        let scale: String
        let width: Int
        let height: Int
        let inkPixels: Int
    }

    static func main() throws {
        let before = Bundle(path: CommandLine.arguments[1])!
        let after = Bundle(path: CommandLine.arguments[2])!
        let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        var metrics: [Metrics] = []
        let weights: [(String, UIImage.SymbolWeight)] = [("regular", .regular), ("semibold", .semibold), ("bold", .bold)]
        let scales: [(String, UIImage.SymbolScale)] = [("small", .small), ("medium", .medium), ("large", .large)]
        for (weightName, weight) in weights {
            for (scaleName, scale) in scales {
                let config = UIImage.SymbolConfiguration(pointSize: 24, weight: weight, scale: scale)
                let old = image("LongJuanCaptureV2", bundle: before, config: config)
                let new = image("LongJuanCaptureV3", bundle: after, config: config)
                let oldMetrics = measure(old, name: "before", weight: weightName, scale: scaleName)
                let newMetrics = measure(new, name: "after", weight: weightName, scale: scaleName)
                precondition(newMetrics.inkPixels > oldMetrics.inkPixels, "The new symbol must have greater visual weight")
                precondition(newMetrics.height > oldMetrics.height, "The new symbol must occupy more vertical space")
                precondition(newMetrics.height <= 144, "The largest symbol must fit within a 48 pt envelope")
                metrics += [oldMetrics, newMetrics]
            }
        }
        let medium = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular, scale: .medium)
        let symbols: [(String, UIImage)] = [
            ("修改前", image("LongJuanCaptureV2", bundle: before, config: medium)),
            ("修改后", image("LongJuanCaptureV3", bundle: after, config: medium)),
            ("系统录屏", UIImage(systemName: "record.circle", withConfiguration: medium)!),
            ("系统扫码", UIImage(systemName: "qrcode.viewfinder", withConfiguration: medium)!)
        ]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 164), format: format)
        let comparison = renderer.image { context in
            UIColor(white: 0.08, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 480, height: 164))
            drawText("编译后的原生符号对照 · 非真机控制中心", at: CGPoint(x: 16, y: 12), size: 12, color: .lightGray)
            for (index, item) in symbols.enumerated() {
                let center = CGPoint(x: CGFloat(index) * 116 + 66, y: 88)
                UIColor(white: 0.25, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)).fill()
                let icon = item.1.withTintColor(.white, renderingMode: .alwaysOriginal)
                icon.draw(at: CGPoint(x: center.x - icon.size.width / 2, y: center.y - icon.size.height / 2))
                drawText(item.0, at: CGPoint(x: center.x - 25, y: 132), size: 12, color: .white)
            }
        }
        try comparison.pngData()!.write(to: output.appendingPathComponent("compiled-symbol-comparison.png"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metrics).write(to: output.appendingPathComponent("symbol-metrics.json"))
        print("PASS: compiled symbol visibility, occupancy and weight for 9 configurations")
    }

    static func image(_ name: String, bundle: Bundle, config: UIImage.SymbolConfiguration) -> UIImage {
        guard let image = UIImage(named: name, in: bundle, with: config), image.isSymbolImage else {
            fatalError("Missing compiled template symbol: \(name)")
        }
        return image
    }

    static func measure(_ image: UIImage, name: String, weight: String, scale: String) -> Metrics {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let canvas = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { _ in
            image.withTintColor(.white, renderingMode: .alwaysOriginal).draw(at: CGPoint(x: 32 - image.size.width / 2, y: 32 - image.size.height / 2))
        }.cgImage!
        let width = canvas.width
        let height = canvas.height
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        data.initialize(repeating: 0, count: width * height * 4)
        defer { data.deallocate() }
        let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(canvas, in: CGRect(x: 0, y: 0, width: width, height: height))
        var x0 = width, y0 = height, x1 = -1, y1 = -1, ink = 0
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] >= 32 {
                x0 = min(x0, x); y0 = min(y0, y)
                x1 = max(x1, x); y1 = max(y1, y)
                ink += 1
            }
        }
        precondition(ink > 0 && x0 > 0 && y0 > 0 && x1 < width - 1 && y1 < height - 1, "Symbol must be visible and unclipped")
        return Metrics(symbol: name, weight: weight, scale: scale, width: x1 - x0 + 1, height: y1 - y0 + 1, inkPixels: ink)
    }

    static func drawText(_ text: String, at point: CGPoint, size: CGFloat, color: UIColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: color])
    }
}
