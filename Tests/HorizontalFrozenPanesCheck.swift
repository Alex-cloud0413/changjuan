import Foundation
import UIKit

/// Synthetic pixel-oracle tests. Never reads an installed app or user recording.
@main
struct HorizontalFrozenPanesCheck {
    static var checks = 0
    static let files = FileManager.default
    static func require(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError(message) }
    }
    @MainActor static func main() throws {
        let root = files.temporaryDirectory.appendingPathComponent("LongShotFrozenPanes-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["LONGSHOT_ALIGNMENT_TRACE"] == "1" {
            FrameStitcher.alignmentTrace = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) }
        }
        let widths = CommandLine.arguments.contains("--quick") ? [188] : [0, 32, 97, 110, 173, 188, 257, 266]
        for scale in (CommandLine.arguments.contains("--quick") ? [1] : [1, 3]) {
            for frozen in widths {
                let directory = root.appendingPathComponent("freeze-\(frozen)-\(scale)x")
                try files.createDirectory(at: directory, withIntermediateDirectories: true)
                // A merged/sparse sheet can lack a regular horizontal grid;
                // whole-column motion then changes only the unique labels.
                let offsets = frozen == 97 ? [0, 0, 78, 156, 234, 312] : [0, 0, 23, 51, 83, 117, 152, 190, 231, 275, 320]
                let outputWidth = 390 + offsets.last!
                let format = UIGraphicsImageRendererFormat()
                format.scale = CGFloat(scale); format.opaque = true; format.preferredRange = .standard
                func text(_ s: String, _ x: Int, _ y: Int, size: CGFloat = 11) {
                    s.draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: size, weight: .regular), .foregroundColor: UIColor.black])
                }
                let world = UIGraphicsImageRenderer(size: CGSize(width: outputWidth, height: 844), format: format).image { ctx in
                    UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: outputWidth, height: 844))
                    for row in 0..<24 where frozen != 97 {
                        let y = 168 + row * 22
                        UIColor(white: 0.83, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: y, width: outputWidth, height: 1))
                    }
                    for column in 0..<10 {
                        let x = 32 + column * 78
                        UIColor(white: 0.8, alpha: 1).setFill(); ctx.fill(CGRect(x: x, y: 142, width: 1, height: 548))
                        text(String(UnicodeScalar(65 + column)!), x + 33, 148, size: 12)
                        for row in 0..<24 {
                            if [110, 257].contains(frozen) && column % 3 == 2 { continue }
                            let value = frozen == 97 || ([110, 257].contains(frozen) && column % 3 == 0) ? "READY" : String(format: "%02d-%02d", column, row)
                            text(value, x + 13, 173 + row * 22)
                        }
                    }
                }
                var urls: [URL] = []
                for (index, offset) in offsets.enumerated() {
                    let shot = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844), format: format).image { ctx in
                        UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
                        ctx.cgContext.saveGState()
                        ctx.cgContext.clip(to: CGRect(x: frozen, y: 142, width: 390 - frozen, height: 548))
                        world.draw(at: CGPoint(x: -offset, y: 0)); ctx.cgContext.restoreGState()
                        ctx.cgContext.saveGState(); ctx.cgContext.clip(to: CGRect(x: 0, y: 142, width: frozen, height: 548))
                        world.draw(at: .zero); ctx.cgContext.restoreGState()
                        if frozen > 0 && ![97, 173, 257].contains(frozen) {
                            UIColor(white: 0.6, alpha: 1).setFill(); ctx.fill(CGRect(x: frozen - 1, y: 142, width: 1, height: 548))
                        }
                        UIColor(white: 0.55, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 166, width: 390, height: 1))
                        text("09:41              100%", 24, 22, size: 17)
                        text("Local synthetic table", 18, 77, size: 17)
                        text("Sheet1", 15, 117, size: 14)
                        text("Footer", 18, 750, size: 17)
                    }
                    let url = directory.appendingPathComponent("\(index).jpg")
                    try shot.jpegData(compressionQuality: 0.94)!.write(to: url); urls.append(url)
                }
                let before = try urls.map { try Data(contentsOf: $0) }
                let orders = CommandLine.arguments.contains("--quick") ? [Array(urls.indices)] : [
                    Array(urls.indices), Array(urls.indices.reversed()), [0, 1, 2, 3, 4, 3, 2, 3, 4] + Array(5..<urls.count)
                ]
                for (index, order) in orders.enumerated() {
                    let result = try FrameStitcher(usePreparedFrames: false, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
                        .stitch(frameURLs: order.map { urls[$0] }, sessionURL: directory.appendingPathComponent("output-\(index)"))
                    let output = UIImage(contentsOfFile: result.outputURLs[0].path)!
                    require(output.cgImage!.width == outputWidth * scale, "Wrong extent freeze=\(frozen), scale=\(scale): \(output.size)")
                    require(output.cgImage!.height == 844 * scale, "Unexpected vertical crop")
                    let rect = CGRect(x: (frozen + 2) * scale, y: 180 * scale, width: (outputWidth - 2 - frozen) * scale, height: 430 * scale)
                    let error = mae(output, world, rect: rect)
                    require(error < 3, "Missing/duplicate cells freeze=\(frozen) order=\(index), MAE=\(error), \(result.outputURLs[0].path)")
                    if frozen > 2 {
                        let fixedError = mae(output, UIImage(contentsOfFile: urls[0].path)!, rect: CGRect(x: 0, y: 180 * scale, width: (frozen - 1) * scale, height: 430 * scale))
                        require(fixedError < 2, "Frozen columns must appear once at their original width")
                    }
                }
                if frozen == 188 && scale == 3 {
                    for (url, data) in zip(urls, before) {
                        try FramePreparationCache.store(FrameStitcher(options: CaptureOptions(axis: .horizontal))
                            .prepareFrame(at: url, encodedData: data), for: url)
                    }
                    let cached = try FrameStitcher(usePreparedFrames: true, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
                        .stitch(frameURLs: urls, sessionURL: directory.appendingPathComponent("cached"))
                    require(cached.preparedFrameCount == urls.count, "Frozen-pane session must consume all prepared frames")
                    require(try Data(contentsOf: cached.outputURLs[0]) == Data(contentsOf: directory.appendingPathComponent("output-0/Outputs/longshot-01.jpg")),
                        "Frozen-pane cached and uncached output must be byte-identical")
                }
                require(try urls.map { try Data(contentsOf: $0) } == before, "Source captures must remain byte-identical")
            }
        }
        try validateWideColumns(at: root)
        for mode in 1...3 { try validateWideColumns(at: root, occlusion: mode) }
        print("Horizontal frozen panes passed: \(checks) checks; fixtures \(root.path)")
    }
    @MainActor static func validateWideColumns(at root: URL, occlusion: Int = 0) throws {
        let frozen = 188, offsets = [0, 0, 92, 190, 305, 420, 538, 650], outputWidth = 1040
        for scale in [1, 3] {
            let directory = root.appendingPathComponent("wide-columns-\(scale)x-occlusion\(occlusion)")
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            let format = UIGraphicsImageRendererFormat()
            format.scale = CGFloat(scale); format.opaque = true; format.preferredRange = .standard
            func text(_ s: String, _ x: Int, _ y: Int, size: CGFloat = 11) {
                s.draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: size, weight: .regular), .foregroundColor: UIColor.black])
            }
            let world = UIGraphicsImageRenderer(size: CGSize(width: outputWidth, height: 844), format: format).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: outputWidth, height: 844))
                for row in 0..<24 {
                    if occlusion == 3 && (470...638).contains(168 + row * 22) { continue }
                    UIColor(white: 0.83, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 168 + row * 22, width: outputWidth, height: 1))
                }
                for column in 0..<7 {
                    let x = 32 + column * 160
                    UIColor(white: 0.8, alpha: 1).setFill(); ctx.fill(CGRect(x: x, y: 142, width: 1, height: 548))
                    text(String(UnicodeScalar(65 + column)!), x + 76, 148, size: 12)
                    for row in 0..<24 {
                        text(String(format: "%02d-%02d / %02d-%02d", column, row, row * 3, column * 7), x + 8, 173 + row * 22)
                    }
                }
            }
            var urls: [URL] = []
            for (index, offset) in offsets.enumerated() {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844), format: format).image { ctx in
                    UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
                    ctx.cgContext.saveGState(); ctx.cgContext.clip(to: CGRect(x: frozen, y: 142, width: 390 - frozen, height: 548))
                    world.draw(at: CGPoint(x: -offset, y: 0)); ctx.cgContext.restoreGState()
                    ctx.cgContext.saveGState(); ctx.cgContext.clip(to: CGRect(x: 0, y: 142, width: frozen, height: 548))
                    world.draw(at: .zero); ctx.cgContext.restoreGState()
                    UIColor(white: 0.6, alpha: 1).setFill(); ctx.fill(CGRect(x: frozen - 1, y: 142, width: 1, height: 548))
                    UIColor(white: 0.55, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 166, width: 390, height: 1))
                    // A stable coloured selected cell in the frozen layer must
                    // remain table content, never become a floating-UI mask.
                    UIColor.systemBlue.setStroke(); ctx.cgContext.setLineWidth(3)
                    ctx.cgContext.stroke(CGRect(x: 40, y: 170, width: 65, height: 24))
                    // A fixed control crosses the frozen boundary. Retain it
                    // whole once at that boundary, recover its moving copies.
                    UIColor.systemBlue.setFill()
                    if occlusion == 0 {
                        ctx.fill(CGRect(x: 170, y: 638, width: 42, height: 38))
                    } else {
                        let y = occlusion == 2 ? 400 : 638
                        ctx.fill(CGRect(x: 170, y: y, width: 67, height: 38))
                        ctx.fill(CGRect(x: 245, y: y, width: 137, height: 38))
                    }
                    text("09:41              100%", 24, 22, size: 17)
                    text("Local synthetic table", 18, 77, size: 17)
                    text("Sheet1", 15, 117, size: 14); text("Footer", 18, 750, size: 17)
                }
                let url = directory.appendingPathComponent("\(index).jpg")
                try image.jpegData(compressionQuality: 0.94)!.write(to: url); urls.append(url)
            }
            for (index, order) in [Array(urls.indices), Array(urls.indices.reversed()), [0, 1, 2, 3, 2, 1, 2, 3, 4, 5, 6, 7]].enumerated() {
                if occlusion >= 2 {
                    do {
                        _ = try FrameStitcher(usePreparedFrames: false, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
                            .stitch(frameURLs: order.map { urls[$0] }, sessionURL: directory.appendingPathComponent("rejected-\(index)"))
                        fatalError("Central occlusion or missing row boundary must not silently crop")
                    } catch StitchError.unseenGap { checks += 1 }
                    continue
                }
                let result = try FrameStitcher(usePreparedFrames: false, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
                    .stitch(frameURLs: order.map { urls[$0] }, sessionURL: directory.appendingPathComponent("output-\(index)"))
                let image = UIImage(contentsOfFile: result.outputURLs[0].path)!
                require(result.omittedOccludedBottomRows == (occlusion == 1), "Only proven bottom occlusion qualifies the output")
                if occlusion == 1 {
                    require(image.cgImage!.width == outputWidth * scale, "Partial fallback must not alter column extent")
                    require(image.cgImage!.height < 844 * scale && image.cgImage!.height > 700 * scale,
                        "Only bottom rows are omitted")
                    require(mae(image, world, rect: CGRect(x: 190 * scale, y: 180 * scale, width: 848 * scale, height: 420 * scale)) < 3,
                        "Unobscured cells stay pixel-complete after partial fallback")
                    let removed = 844 * scale - image.cgImage!.height
                    require(mae(image, UIImage(contentsOfFile: urls[0].path)!, rect: CGRect(x: 10 * scale, y: 180 * scale, width: 172 * scale, height: 420 * scale)) < 3,
                        "Frozen columns remain intact above the omitted rows")
                    let source = UIImage(contentsOfFile: urls[0].path)!.cgImage!
                    let footer = UIImage(cgImage: source.cropping(to: CGRect(x: 0, y: removed, width: 390 * scale, height: 844 * scale - removed))!)
                    require(mae(image, footer, rect: CGRect(x: 0, y: 730 * scale - removed, width: 390 * scale, height: 80 * scale)) < 3,
                        "Fixed footer is preserved once at the new bottom")
                    if index == 0 {
                        for url in urls {
                            let data = try Data(contentsOf: url)
                            try FramePreparationCache.store(FrameStitcher(options: CaptureOptions(axis: .horizontal)).prepareFrame(at: url, encodedData: data), for: url)
                        }
                        let cached = try FrameStitcher(usePreparedFrames: true, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
                            .stitch(frameURLs: urls, sessionURL: directory.appendingPathComponent("cached-partial"))
                        require(cached.omittedOccludedBottomRows && cached.preparedFrameCount == urls.count, "Prepared partial session retains qualification")
                        require(try Data(contentsOf: cached.outputURLs[0]) == Data(contentsOf: result.outputURLs[0]), "Partial output cached/uncached byte parity")
                    }
                    continue
                }
                require(image.cgImage!.width == outputWidth * scale && image.cgImage!.height == 844 * scale,
                    "Disappearing column labels must not truncate the captured extent: scale=\(scale) order=\(index) actual=\(image.size) output=\(result.outputURLs[0].path)")
                require(mae(image, world, rect: CGRect(x: 190 * scale, y: 180 * scale, width: 848 * scale, height: 430 * scale)) < 3,
                    "Wide-column body must match its complete pixel oracle without omitted/duplicated columns")
                require(mae(image, UIImage(contentsOfFile: urls[0].path)!, rect: CGRect(x: 35 * scale, y: 168 * scale, width: 148 * scale, height: 450 * scale)) < 3,
                    "Frozen content including its blue selection must survive at original coordinates")
                require(mae(image, UIImage(contentsOfFile: urls[0].path)!, rect: CGRect(x: 165 * scale, y: 630 * scale, width: 52 * scale, height: 52 * scale)) < 3,
                    "The boundary-crossing control must stay whole at the original frozen edge")
                require(mae(image, world, rect: CGRect(x: 220 * scale, y: 628 * scale, width: 818 * scale, height: 56 * scale)) < 3,
                    "Every moving copy of a frozen-boundary control must be recovered from real pixels")
            }
        }
    }
    static func mae(_ a: UIImage, _ b: UIImage, rect: CGRect) -> Double {
        func pixels(_ image: UIImage) -> [UInt8] {
            let crop = image.cgImage!.cropping(to: rect)!
            var data = [UInt8](repeating: 0, count: crop.width * crop.height)
            data.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
                context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            }
            return data
        }
        let aa = pixels(a), bb = pixels(b)
        return Double(zip(aa, bb).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(aa.count)
    }
}
