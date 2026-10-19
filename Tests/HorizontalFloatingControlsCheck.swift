import Foundation
import UIKit

/// Synthetic tables only. No installed-app data, screenshots or personal content.
@main
struct HorizontalFloatingControlsCheck {
    static let files = FileManager.default
    static let screenWidth = 390, screenHeight = 844, tableTop = 142, tableBottom = 690
    static let offsets = [0, 17, 49, 88, 137, 194, 251, 318, 386, 459, 538, 610, 688, 760, 818, 880]
    static var checks = 0
    enum Controls { case separated, contentOnly, plainInk, squareCard, transient }
    struct Fixture { let frames: [URL]; let world: UIImage; let finalFrame: UIImage; let directory: URL; let scale: Int }

    static func require(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError(message) }
    }

    @MainActor static func main() throws {
        let root = files.temporaryDirectory.appendingPathComponent("LongShotFloatingControls-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["LONGSHOT_ALIGNMENT_TRACE"] == "1" {
            FrameStitcher.alignmentTrace = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) }
        }
        if CommandLine.arguments.contains("--content-only") {
            try validateContent(at: root.appendingPathComponent("content-only"))
            print("Horizontal moving blue-content negative passed: \(checks) checks; fixtures \(root.path)")
            return
        }
        if CommandLine.arguments.contains("--square-only") {
            try validateSquareCard(at: root.appendingPathComponent("square-card"))
            print("Horizontal square-card negative passed: \(checks) checks; fixtures \(root.path)")
            return
        }
        if CommandLine.arguments.contains("--transient-only") {
            try validateTransient(at: root.appendingPathComponent("transient"))
            print("Horizontal transient-control negative passed: \(checks) checks; fixtures \(root.path)")
            return
        }
        let fixture = try makeFixture(at: root.appendingPathComponent("separated"), controls: .separated)
        let originalBytes = try fixture.frames.map { try Data(contentsOf: $0) }
        try validateSeparated(fixture, name: "rightward")
        if !CommandLine.arguments.contains("--primary-only") {
            try validateSeparated(fixture, name: "leftward", order: Array(fixture.frames.indices.reversed()))
            try validateSeparated(fixture, name: "backtrack", order: [0, 1, 2, 3, 4, 5, 6, 5, 4, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
            try validateSeparated(fixture, name: "revisit", order: Array(fixture.frames.indices) + Array(fixture.frames.indices.reversed()) + Array(fixture.frames.indices))
            for url in fixture.frames {
                let data = try Data(contentsOf: url)
                try FramePreparationCache.store(FrameStitcher(options: CaptureOptions(axis: .horizontal))
                    .prepareFrame(at: url, encodedData: data), for: url)
            }
            let prepared = try output(fixture, name: "prepared", cached: true)
            let fallback = UIImage(contentsOfFile: fixture.directory.appendingPathComponent("rightward/Outputs/longshot-01.jpg").path)!
            require(prepared.jpegData(compressionQuality: 1) == fallback.jpegData(compressionQuality: 1),
                    "Prepared and fallback paths must keep exactly the same native pixels")
            try validateContent(at: root.appendingPathComponent("content-only"))
            try validatePlainInk(at: root.appendingPathComponent("plain-ink"))
            try validateSquareCard(at: root.appendingPathComponent("square-card"))
            try validateTransient(at: root.appendingPathComponent("transient"))
            let native = try makeFixture(at: root.appendingPathComponent("native-separated"), controls: .separated, scale: 3)
            try validateSeparated(native, name: "rightward")
            try validateSeparated(native, name: "leftward", order: Array(native.frames.indices.reversed()))
            try validateSeparated(native, name: "backtrack", order: [0, 1, 2, 3, 4, 5, 6, 5, 4, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
            try validateSeparated(native, name: "revisit", order: Array(native.frames.indices) + Array(native.frames.indices.reversed()) + Array(native.frames.indices))
        }
        require(try fixture.frames.map { try Data(contentsOf: $0) } == originalBytes,
                "Overlay repair must not change any source JPEG")
        print("Horizontal floating controls passed: \(checks) checks; separated full circles once, authentic body recovery, reverse/revisit, cache parity, blue-content negatives; fixtures \(root.path)")
    }

    static var format: UIGraphicsImageRendererFormat {
        let value = UIGraphicsImageRendererFormat()
        value.scale = 1; value.opaque = true; value.preferredRange = .standard
        return value
    }

    @MainActor static func makeFixture(at directory: URL, controls: Controls, scale: Int = 1) throws -> Fixture {
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let renderingFormat = format
        renderingFormat.scale = CGFloat(scale)
        let outputWidth = offsets.last! + screenWidth
        func text(_ value: String, _ x: Int, _ y: Int, _ size: CGFloat = 11, gray: CGFloat = 0.12) {
            value.draw(at: CGPoint(x: x, y: y), withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: size, weight: .regular),
                .foregroundColor: UIColor(white: gray, alpha: 1)])
        }
        let world = UIGraphicsImageRenderer(size: CGSize(width: outputWidth, height: screenHeight), format: renderingFormat).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: screenHeight))
            for column in 0..<18 {
                let x = 32 + column * 78
                UIColor(white: 0.82, alpha: 1).setFill()
                context.fill(CGRect(x: x, y: tableTop, width: 1, height: tableBottom - tableTop))
                text(String(UnicodeScalar(65 + column)!), x + 32, tableTop + 2, 12)
                UIColor.orange.setFill(); context.fill(CGRect(x: x, y: 160, width: 78, height: 22))
                text(column % 3 == 0 ? "READY" : column % 3 == 1 ? "NAME" : "", x + 6, 164)
                for row in 0..<24 {
                    let y = 184 + row * 21
                    UIColor(white: 0.89, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 78, height: 1))
                    if column % 3 == 0 { text("READY", x + 6, y + 3) }
                    if column % 3 == 1 { text(String(format: "%02d-%02d", column, row), x + 6, y + 3, 10) }
                }
            }
            if controls == .contentOnly {
                // Blue content follows world coordinates, not viewport coordinates.
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 134, y: 636, width: 28, height: 24))
                context.fill(CGRect(x: 541, y: 643, width: 22, height: 12))
                context.fill(CGRect(x: 938, y: 630, width: 31, height: 29))
                // A full-width coloured row is table data, not a floating pill.
                context.fill(CGRect(x: 32, y: 562, width: outputWidth - 32, height: 24))
                text("BLUE CONTENT ROW", 40, 567, 12, gray: 1)
            }
        }
        var frames: [URL] = []
        var final: UIImage!
        for (index, offset) in offsets.enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: screenWidth, height: screenHeight), format: renderingFormat).image { context in
                world.draw(at: CGPoint(x: -offset, y: 0))
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: screenWidth, height: tableTop))
                context.fill(CGRect(x: 0, y: tableBottom, width: screenWidth, height: screenHeight - tableBottom))
                text("09:41                  100%", 24, 22, 17)
                text("<   Table                       ...", 18, 77, 17)
                text("Sheet1", 15, 117, 14)
                UIColor(white: 0.97, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: tableTop, width: 31, height: tableBottom - tableTop))
                for row in 0..<24 { text("\(row + 1)", 6, 187 + row * 21, 9, gray: 0.5) }
                text("A1                          x", 30, 716, 15, gray: 0.5)
                text("Local table", 30, 777, 18, gray: 0.5)
                if controls != .contentOnly {
                    if controls == .separated {
                        drawCircle(context, x: 170)
                        drawKeyboard(context, x: 180)
                    } else if controls == .plainInk {
                        // Stable blue ink with no circular surround must not
                        // trigger an invented white-circle-sized removal mask.
                        drawKeyboard(context, x: 180)
                    } else if controls == .squareCard {
                        // Same size, ink, baseline and shadow as the positive,
                        // but straight edges/corners are not a white circle.
                        context.cgContext.saveGState()
                        context.cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 4,
                            color: UIColor(white: 0, alpha: 0.24).cgColor)
                        UIColor.white.setFill()
                        context.fill(CGRect(x: 170, y: 638, width: 38, height: 38))
                        context.cgContext.restoreGState()
                        UIColor(white: 0.88, alpha: 1).setStroke()
                        context.cgContext.setLineWidth(0.75)
                        context.cgContext.stroke(CGRect(x: 170, y: 638, width: 38, height: 38))
                        drawKeyboard(context, x: 180)
                    } else if index == 0 || index == offsets.count - 1 {
                        drawCircle(context, x: 170)
                        drawKeyboard(context, x: 180)
                    }
                    drawCircle(context, x: 245)
                    UIColor.systemBlue.setStroke(); context.cgContext.setLineWidth(2)
                    context.cgContext.stroke(CGRect(x: 258, y: 648, width: 10, height: 18))
                    context.cgContext.stroke(CGRect(x: 254, y: 650, width: 10, height: 14))
                    UIColor.systemBlue.setFill()
                    context.cgContext.addPath(UIBezierPath(roundedRect: CGRect(x: 286, y: 638, width: 101, height: 38), cornerRadius: 19).cgPath)
                    context.cgContext.fillPath()
                    text("TOOLS", 309, 649, 14, gray: 1)
                }
            }
            let url = directory.appendingPathComponent(String(format: "frame-%02d.jpg", index))
            try image.jpegData(compressionQuality: 0.94)!.write(to: url)
            frames.append(url); final = UIImage(contentsOfFile: url.path)!
        }
        try world.pngData()!.write(to: directory.appendingPathComponent("world.png"))
        return Fixture(frames: frames, world: world, finalFrame: final, directory: directory, scale: scale)
    }

    static func drawCircle(_ context: UIGraphicsImageRendererContext, x: CGFloat) {
        context.cgContext.saveGState()
        context.cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor(white: 0, alpha: 0.24).cgColor)
        UIColor.white.setFill(); context.cgContext.fillEllipse(in: CGRect(x: x, y: 638, width: 38, height: 38))
        context.cgContext.restoreGState()
        UIColor(white: 0.88, alpha: 1).setStroke()
        context.cgContext.setLineWidth(0.75)
        context.cgContext.strokeEllipse(in: CGRect(x: x, y: 638, width: 38, height: 38))
    }

    static func drawKeyboard(_ context: UIGraphicsImageRendererContext, x: CGFloat) {
        UIColor.systemBlue.setStroke(); context.cgContext.setLineWidth(2)
        context.cgContext.stroke(CGRect(x: x, y: 650, width: 18, height: 12))
        for row in 0..<2 { for column in 0..<4 {
            context.cgContext.stroke(CGRect(x: x + 3 + CGFloat(column) * 3.5, y: 653 + CGFloat(row) * 4, width: 1, height: 1))
        } }
    }

    @MainActor static func output(_ fixture: Fixture, name: String, order: [Int]? = nil, cached: Bool = false) throws -> UIImage {
        let inputs = (order ?? Array(fixture.frames.indices)).map { fixture.frames[$0] }
        let result = try FrameStitcher(usePreparedFrames: cached, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
            .stitch(frameURLs: inputs, sessionURL: fixture.directory.appendingPathComponent(name))
        require(result.outputURLs.count == 1, "One synthetic page must remain one output")
        let image = UIImage(contentsOfFile: result.outputURLs[0].path)!
        require(image.cgImage!.width == (offsets.last! + screenWidth) * fixture.scale && image.cgImage!.height == screenHeight * fixture.scale,
                "Overlay repair must not change the captured horizontal extent or height")
        return image
    }

    @MainActor static func validateSeparated(_ fixture: Fixture, name: String, order: [Int]? = nil) throws {
        let image = try output(fixture, name: name, order: order)
        let scale = fixture.scale
        func scaled(_ rect: CGRect) -> CGRect { rect.applying(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))) }
        let runs = blueRuns(image, top: 636 * scale, bottom: 680 * scale)
        require(runs.count == 3, "Each independent keyboard/phone/pill must remain exactly once, not repeated or fragmented; got \(runs); \(fixture.directory.path)/\(name)")
        require(runs.filter { $0.count > 60 * scale }.count == 1 && runs.filter { $0.count < 30 * scale }.count == 2,
                "Exactly two small glyph controls and one whole blue pill must remain")
        let originalRects = [CGRect(x: 164, y: 632, width: 50, height: 52), CGRect(x: 239, y: 632, width: 50, height: 52), CGRect(x: 283, y: 634, width: 107, height: 46)]
        let retained = originalRects.map { scaled($0.offsetBy(dx: CGFloat(offsets.last!), dy: 0)) }
        let repaired = meanError(image, fixture.world, rect: scaled(CGRect(x: 34, y: 628, width: CGFloat(offsets.last! + screenWidth - 34), height: 58)), excluding: retained)
        FileHandle.standardOutput.write(Data(("FLOATING \(name) runs=\(runs) repairMAE=\(repaired) fixture=\(fixture.directory.path)\n").utf8))
        require(repaired < 3, "All exposed table content, including shadows of separated circles, must recover from actual overlaps; MAE \(repaired)")
        for rect in originalRects {
            let error = meanError(image, fixture.finalFrame, rect: scaled(rect.offsetBy(dx: CGFloat(offsets.last!), dy: 0)), rhsOrigin: scaled(rect).origin)
            require(error < 3, "Each last-edge circle/pill including neutral surround and shadow must be preserved whole; rect=\(rect), MAE=\(error), fixture=\(fixture.directory.path)")
        }
        require(meanError(image, fixture.world, rect: scaled(CGRect(x: 34, y: 184, width: CGFloat(offsets.last! + screenWidth - 34), height: 432))) < 3,
                "Overlay repair must not change unrelated table pixels")
    }

    @MainActor static func validateContent(at directory: URL) throws {
        let fixture = try makeFixture(at: directory, controls: .contentOnly)
        let image = try output(fixture, name: "output")
        // The production path encodes capture JPEGs and the final JPEG at
        // quality .94. Compare saturation-sensitive RGB against the same two
        // lossy encodings, rather than an impossible lossless PNG oracle.
        let encodedWorld = UIImage(data: UIImage(data: fixture.world.jpegData(compressionQuality: 0.94)!)!
            .jpegData(compressionQuality: 0.94)!)!
        let rects = [CGRect(x: 130, y: 630, width: 38, height: 36), CGRect(x: 535, y: 637, width: 34, height: 24), CGRect(x: 932, y: 624, width: 43, height: 41), CGRect(x: 34, y: 560, width: image.size.width - 34, height: 28)]
        let errors = rects.map { meanError(image, encodedWorld, rect: $0) }
        FileHandle.standardOutput.write(Data(("FLOATING CONTENT matched-JPEG roiMAE=\(errors) fixture=\(fixture.directory.path)\n").utf8))
        for (rect, error) in zip(rects, errors) {
            require(error < 3,
                    "Moving blue content, ordinary badges and broad coloured rows must not be erased as floating UI; rect=\(rect), MAE=\(error), fixture=\(fixture.directory.path)")
            let expected = blueShape(fixture.world, rect: rect), actual = blueShape(image, rect: rect)
            require(Double(actual.count) >= Double(expected.count) * 0.95,
                    "At least 95% of each blue content region must remain, not be masked away")
            require(abs(actual.bounds.minX - expected.bounds.minX) <= 1
                    && abs(actual.bounds.maxX - expected.bounds.maxX) <= 1
                    && abs(actual.bounds.minY - expected.bounds.minY) <= 1
                    && abs(actual.bounds.maxY - expected.bounds.maxY) <= 1,
                    "Each moving blue-content shape must retain its table bounds within one JPEG chroma-edge pixel; expected=\(expected), actual=\(actual)")
        }
    }

    @MainActor static func validatePlainInk(at directory: URL) throws {
        let fixture = try makeFixture(at: directory, controls: .plainInk)
        let image = try output(fixture, name: "output")
        let runs = blueRuns(image, top: 636, bottom: 680)
        require(runs.filter { $0.count < 30 }.count > 2,
                "Stable blue ink without a circular surround must not be collapsed into a fabricated circle control")
    }

    @MainActor static func validateTransient(at directory: URL) throws {
        let fixture = try makeFixture(at: directory, controls: .transient)
        let image = try output(fixture, name: "output")
        let runs = blueRuns(image, top: 636, bottom: 680)
        FileHandle.standardOutput.write(Data(("FLOATING TRANSIENT runs=\(runs) fixture=\(fixture.directory.path)\n").utf8))
        require(runs.filter { $0.count < 30 }.count >= 3,
                "A control absent in middle frames is not proven persistent and must not be silently deleted")
        let first = UIImage(contentsOfFile: fixture.frames[0].path)!
        require(meanError(image, first, rect: CGRect(x: 164, y: 632, width: 50, height: 52)) < 3,
                "The first authentic transient control and shadow must remain intact, not be replaced by a guessed fixed-control mask")
    }

    @MainActor static func validateSquareCard(at directory: URL) throws {
        let fixture = try makeFixture(at: directory, controls: .squareCard)
        let image = try output(fixture, name: "output")
        let runs = blueRuns(image, top: 636, bottom: 680)
        FileHandle.standardOutput.write(Data(("FLOATING SQUARE runs=\(runs) fixture=\(fixture.directory.path)\n").utf8))
        require(runs.filter { $0.count < 30 }.count > 2,
                "A square white card with identical glyph, size, baseline and shadow is not a proven round floating control; runs=\(runs), fixture=\(fixture.directory.path)")
    }

    static func rgba(_ image: UIImage) -> [UInt8] {
        let cg = image.cgImage!, width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { memory in
            let context = CGContext(data: memory.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    static func blueRuns(_ image: UIImage, top: Int, bottom: Int) -> [Range<Int>] {
        let pixels = rgba(image), width = image.cgImage!.width
        var found: [Range<Int>] = [], start: Int?, last = 0
        for x in 0..<width {
            let count = (top..<bottom).filter { y in
                let i = (y * width + x) * 4
                return Int(pixels[i + 2]) - Int(pixels[i]) > 70 && pixels[i + 2] > 140
            }.count
            if count >= 2 {
                if let begin = start, x - last > 4 { found.append(begin..<(last + 1)); start = x }
                if start == nil { start = x }
                last = x
            }
        }
        if let start { found.append(start..<(last + 1)) }
        return found
    }

    static func blueShape(_ image: UIImage, rect: CGRect) -> (count: Int, bounds: CGRect) {
        let pixels = rgba(image), width = image.cgImage!.width
        var count = 0, left = Int(rect.maxX), right = Int(rect.minX), top = Int(rect.maxY), bottom = Int(rect.minY)
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
            let i = (y * width + x) * 4
            if Int(pixels[i + 2]) - Int(pixels[i]) > 70 && pixels[i + 2] > 140 {
                count += 1; left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
            }
        } }
        return (count, CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
    }

    static func meanError(_ lhs: UIImage, _ rhs: UIImage, rect: CGRect, rhsOrigin: CGPoint? = nil, excluding: [CGRect] = []) -> Double {
        let a = rgba(lhs), b = rgba(rhs), aw = lhs.cgImage!.width, bw = rhs.cgImage!.width
        let origin = rhsOrigin ?? rect.origin
        var difference = 0, count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
            if excluding.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) { continue }
            let ax = (y * aw + x) * 4
            let bx = ((y - Int(rect.minY) + Int(origin.y)) * bw + x - Int(rect.minX) + Int(origin.x)) * 4
            for channel in 0..<3 { difference += abs(Int(a[ax + channel]) - Int(b[bx + channel])); count += 1 }
        } }
        return Double(difference) / Double(max(1, count))
    }
}
