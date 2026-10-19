import Foundation
import UIKit

/// Real image decoding, matching, rendering and cache I/O against isolated fixtures.
@main
struct CaptureOptionsCheck {
    static let files = FileManager.default
    static var checks = 0
    static func require(_ value: Bool, _ message: String, line: UInt = #line) {
        checks += 1
        if !value { fatalError("\(message) at \(line)") }
    }
    @MainActor static func main() throws {
        let root = files.temporaryDirectory.appendingPathComponent("LongShotOptions-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "LongShotOptions-\(UUID())")!
        require(CaptureOptions.load(from: defaults) == CaptureOptions(), "Old installs keep vertical/crop defaults")
        defaults.set("unknown", forKey: CaptureOptions.axisKey)
        require(CaptureOptions.load(from: defaults).axis == .vertical, "Unknown preference fails safe")
        defaults.set("horizontal", forKey: CaptureOptions.axisKey)
        defaults.set(true, forKey: CaptureOptions.statusBarKey)
        require(CaptureOptions.load(from: defaults) == CaptureOptions(axis: .horizontal, keepsStatusBar: true), "Preferences round trip")
        let options = CaptureOptions(axis: .horizontal)
        if ProcessInfo.processInfo.environment["LONGSHOT_ALIGNMENT_TRACE"] == "1" {
            FrameStitcher.alignmentTrace = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        var seed: UInt64 = 0x123456789
        let canvas = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 844), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 844))
            for row in 0..<14 {
                for col in 0..<20 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let value = Int((seed >> 32) % 100000)
                    UIColor(white: row % 2 == 0 ? 0.96 : 1, alpha: 1).setFill()
                    context.fill(CGRect(x: col * 80, y: 64 + row * 50, width: 80, height: 50))
                    UIColor(white: 0.78, alpha: 1).setStroke()
                    UIBezierPath(rect: CGRect(x: col * 80, y: 64 + row * 50, width: 80, height: 50)).stroke()
                    "\(value)".draw(at: CGPoint(x: col * 80 + 8, y: 78 + row * 50), withAttributes: [
                        .font: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium), .foregroundColor: UIColor.black])
                }
            }
        }
        try canvas.pngData()!.write(to: root.appendingPathComponent("table-world.png"))
        var frames: [URL] = []
        for (index, offset) in stride(from: 0, through: 927, by: 103).enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844), format: format).image { context in
                canvas.draw(at: CGPoint(x: -offset, y: 0))
                UIColor(white: 0.92, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 390, height: 63))
                "09:41                      100%".draw(at: CGPoint(x: 22, y: 18), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: UIColor.black])
            }
            let url = root.appendingPathComponent("table-\(index).jpg")
            try image.jpegData(compressionQuality: 0.94)!.write(to: url)
            frames.append(url)
        }
        let originals = try frames.map { try Data(contentsOf: $0) }
        func stitch(_ inputs: [URL], _ name: String, keep: Bool = false, cached: Bool = true, boundaries: [Int] = []) throws -> StitchResult {
            do {
                return try FrameStitcher(usePreparedFrames: cached, options: CaptureOptions(axis: .horizontal, keepsStatusBar: keep))
                    .stitch(frameURLs: inputs, sessionURL: root.appendingPathComponent(name), segmentStarts: boundaries)
            } catch {
                FileHandle.standardError.write(Data(("Capture options fixture \(name) rejected after \(checks) assertions; \(root.path)\n").utf8))
                throw error
            }
        }
        let forward = try stitch(frames, "forward", cached: false)
        let output = UIImage(contentsOfFile: forward.outputURLs[0].path)!
        require(output.size == CGSize(width: 1317, height: 781), "All 927 new columns plus 390 initial columns, cropped 63 status rows: \(output.size)")
        require(forward.acceptedFrameCount == frames.count, "No table frame silently lost")
        let reverse = try stitch(Array(frames.reversed()), "reverse")
        let revisit = try stitch(frames + Array(frames.reversed()) + frames, "revisit")
        require(try Data(contentsOf: forward.outputURLs[0]) == Data(contentsOf: reverse.outputURLs[0]), "Reverse produces same left-to-right columns")
        require(try Data(contentsOf: forward.outputURLs[0]) == Data(contentsOf: revisit.outputURLs[0]), "Revisited columns never duplicated")
        // Dense cell contents compared against the unscrolled world, not just output dimensions.
        let reference = UIGraphicsImageRenderer(size: output.size, format: format).image { _ in canvas.draw(at: CGPoint(x: 0, y: -63)) }
        let error = meanError(output, reference, top: 20, bottom: 680)
        require(error < 3, "Pixel alignment across all seams, JPEG MAE=\(error)")
        let kept = try stitch(frames, "kept", keep: true)
        let keptImage = UIImage(contentsOfFile: kept.outputURLs[0].path)!
        require(keptImage.size == CGSize(width: 1317, height: 844), "Keep status bar restores original height")
        require(meanError(keptImage, UIImage(contentsOfFile: frames[0].path)!, top: 0, bottom: 55, width: 390) < 3,
                "One authentic initial status bar, not redrawn")
        for (url, data) in zip(frames, originals) {
            try FramePreparationCache.store(FrameStitcher(options: options).prepareFrame(at: url, encodedData: data), for: url)
            require(FramePreparationCache.load(for: url, axis: .horizontal) != nil, "Horizontal cache readable")
            require(FramePreparationCache.load(for: url) == nil, "Axis mismatch rejects cache")
        }
        let cached = try stitch(frames, "cached")
        require(cached.preparedFrameCount == frames.count, "All horizontal prepared frames reused")
        require(try Data(contentsOf: cached.outputURLs[0]) == Data(contentsOf: forward.outputURLs[0]), "Prepared path byte identical")
        let pages = try stitch(frames + Array(frames.reversed()), "two-pages", boundaries: [0, frames.count])
        require(UIImage(contentsOfFile: pages.outputURLs[0].path)!.size.width == 1317 * 2 + 15, "Explicit horizontal pages ordered with separator")
        for (url, data) in zip(frames, originals) { require(try Data(contentsOf: url) == data, "Raw source bytes untouched") }
        do {
            _ = try stitch([frames[0], frames[0], frames[0]], "stationary")
            fatalError("Stationary table must not pretend to be wide")
        } catch StitchError.noUsableMovement { checks += 1 }
        var frozen: [URL] = []
        for (index, frame) in frames.enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844), format: format).image { context in
                UIImage(contentsOfFile: frame.path)!.draw(at: .zero)
                UIColor(white: 0.94, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 63, width: 390, height: 82))
                context.fill(CGRect(x: 0, y: 790, width: 390, height: 54))
                context.fill(CGRect(x: 0, y: 145, width: 58, height: 645))
                "Monthly table".draw(at: CGPoint(x: 24, y: 90), withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.black])
                "Sheet 1".draw(at: CGPoint(x: 24, y: 806), withAttributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.black])
                for row in 2..<14 {
                    "\(row)".draw(at: CGPoint(x: 16, y: 78 + row * 50), withAttributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.black])
                }
            }
            let url = root.appendingPathComponent("frozen-\(index).jpg")
            try image.jpegData(compressionQuality: 0.94)!.write(to: url)
            frozen.append(url)
        }
        let frozenResult = try stitch(frozen, "frozen-column-toolbar")
        let frozenImage = UIImage(contentsOfFile: frozenResult.outputURLs[0].path)!
        require(frozenImage.size == output.size, "Frozen column does not change motion geometry")
        let frozenReference = UIGraphicsImageRenderer(size: output.size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: output.size))
            context.cgContext.saveGState()
            context.cgContext.clip(to: CGRect(x: 0, y: 82, width: output.size.width, height: 645))
            canvas.draw(at: CGPoint(x: 0, y: -63))
            context.cgContext.restoreGState()
            context.cgContext.clip(to: [CGRect(x: 0, y: 0, width: 390, height: 82),
                CGRect(x: 0, y: 727, width: 390, height: 54), CGRect(x: 0, y: 82, width: 58, height: 645)])
            UIImage(contentsOfFile: frozen[0].path)!.draw(at: CGPoint(x: 0, y: -63))
        }
        require(meanError(frozenImage, frozenReference, top: 0, bottom: 781) < 3,
                "Fixed toolbar/footer and frozen column retained once; moving cells intact")
        let frozenReverse = try stitch(Array(frozen.reversed()), "frozen-reverse")
        require(try Data(contentsOf: frozenResult.outputURLs[0]) == Data(contentsOf: frozenReverse.outputURLs[0]), "Fixed chrome output deterministic in reverse")
        var fullSize: [URL] = []
        for (index, frame) in frames.prefix(6).enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1170, height: 2532), format: format).image { _ in
                UIImage(contentsOfFile: frame.path)!.draw(in: CGRect(x: 0, y: 0, width: 1170, height: 2532))
            }
            let url = root.appendingPathComponent("full-size-\(index).jpg")
            let data = image.jpegData(compressionQuality: 0.94)!
            try data.write(to: url)
            try FramePreparationCache.store(FrameStitcher(options: options).prepareFrame(at: url, encodedData: data), for: url)
            fullSize.append(url)
        }
        let full = try stitch(fullSize, "full-size")
        require(UIImage(contentsOfFile: full.outputURLs[0].path)!.size == CGSize(width: 2715, height: 2343), "Full-resolution table columns preserved")
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let coordinator = ZoomableLongImage(image: output).makeCoordinator()
        coordinator.layoutImage(in: scroll, image: output)
        require(scroll.contentSize.width > 390 && abs(scroll.contentSize.height - 700) < 0.01,
                "Wide preview fits height and exposes horizontal scroll, not tiny fit-width")
        let portrait = UIImage(contentsOfFile: frames[0].path)!
        coordinator.layoutImage(in: scroll, image: portrait)
        require(scroll.contentSize == CGSize(width: 390, height: 844), "Existing vertical preview still fits width")
        print(String(format: "Horizontal 1170x2532, 6 prepared frames: %.4fs", full.timings.total))
        print("Capture options passed: \(checks) checks; horizontal table MAE \(error); fixtures \(root.path)")
    }

    static func meanError(_ left: UIImage, _ right: UIImage, top: Int, bottom: Int, width: Int? = nil) -> Double {
        func bytes(_ image: UIImage) -> [UInt8] {
            let w = image.cgImage!.width, h = image.cgImage!.height
            var pixels = [UInt8](repeating: 0, count: w * h)
            pixels.withUnsafeMutableBytes { memory in
                let ctx = CGContext(data: memory.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
                ctx.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            return pixels
        }
        let a = bytes(left), b = bytes(right)
        let aw = left.cgImage!.width, bw = right.cgImage!.width, w = width ?? min(aw, bw)
        var sum = 0
        for y in top..<bottom { for x in 0..<w { sum += abs(Int(a[y * aw + x]) - Int(b[y * bw + x])) } }
        return Double(sum) / Double((bottom - top) * w)
    }
}
