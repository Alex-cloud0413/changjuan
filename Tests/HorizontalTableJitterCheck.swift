import Foundation
import UIKit

/// All content is synthetic. Frozen column headings do not move vertically;
/// the scrolling table body can move slightly across the horizontal axis.
@main
struct HorizontalTableJitterCheck {
    static let files = FileManager.default
    static var checks = 0
    static let screenWidth = 390, screenHeight = 844
    static let columnHeaderTop = 142, bodyTop = 168, bodyBottom = 690
    static let rowHeight = 22
    static let offsets = [0, 42, 83, 125, 168, 214, 267, 319, 372, 428, 486, 548, 611, 674, 742, 810]

    struct Fixture {
        let frames: [URL]
        let expected: UIImage
        let scale: Int
        let topTrim: Int
        let bottomTrim: Int
        let pixelWidth: Int
        var pixelHeight: Int { HorizontalTableJitterCheck.screenHeight * scale - topTrim - bottomTrim }
    }

    static func require(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError(message) }
    }

    @MainActor static func main() throws {
        let root = files.temporaryDirectory.appendingPathComponent("LongShotTableJitter-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["LONGSHOT_ALIGNMENT_TRACE"] == "1" {
            FrameStitcher.alignmentTrace = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) }
        }
        let jitter = [0, 0, 0, -3, 1, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4]
        let stationary = try makeFixture(at: root.appendingPathComponent("native-no-jitter"), scale: 3,
                                         jitters: [Int](repeating: 0, count: offsets.count))
        require(stationary.topTrim == 0 && stationary.bottomTrim == 0, "Zero cross-axis movement has no crop")
        try validate(stationary, output: root.appendingPathComponent("native-no-jitter-output"))
        if CommandLine.arguments.contains("--zero-jitter-only") {
            print("Horizontal table zero-jitter baseline passed: \(checks) checks; native dimensions retained; fixtures \(root.path)")
            return
        }
        let repeatedOpening = try makeFixture(at: root.appendingPathComponent("stationary-opening"), scale: 3,
            jitters: [0, 0, 0, 0, 0], scrollOffsets: [0, 0, 42, 42, 83])
        try validate(repeatedOpening, output: root.appendingPathComponent("stationary-opening-output"))
        let sameX = try makeFixture(at: root.appendingPathComponent("same-x-native-jitter"), scale: 3,
            jitters: [0, 0, -3, -3], scrollOffsets: [0, 42, 42, 83])
        require(sameX.topTrim == 9 && sameX.bottomTrim == 0,
                "A pure cross-axis movement between identical X offsets changes only the shared body interval")
        try validate(sameX, output: root.appendingPathComponent("same-x-native-output"))
        if CommandLine.arguments.contains("--same-x-jitter-only") {
            print("Horizontal table same-X-jitter passed: \(checks) checks; fixtures \(root.path)")
            return
        }
        let smallNativeJitter = [0, 0, 0, -1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]
        let small = try makeFixture(at: root.appendingPathComponent("small-native-jitter"), scale: 3,
            jitters: [Int](repeating: 0, count: offsets.count), nativePixelJitters: smallNativeJitter)
        require(small.topTrim == 1 && small.bottomTrim == 2, "Native one/two-pixel movement must preserve the frozen header divider")
        try validate(small, output: root.appendingPathComponent("small-native-output"))
        if CommandLine.arguments.contains("--small-jitter-only") {
            print("Horizontal table small-native-jitter passed: \(checks) checks; fixtures \(root.path)")
            return
        }
        let native = try makeFixture(at: root.appendingPathComponent("native-jitter"), scale: 3, jitters: jitter)
        require(native.topTrim == 9 && native.bottomTrim == 12, "Only the shared captured body is a valid expected image")
        let nativeOriginals = try native.frames.map { try Data(contentsOf: $0) }
        let nativeResult = try validate(native, output: root.appendingPathComponent("native-output"))
        try validate(native, output: root.appendingPathComponent("native-reverse-output"),
            frameOrder: Array(native.frames.indices.reversed()))
        let backtrack = [0, 1, 2, 3, 4, 5, 6, 5, 4, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
        try validate(native, output: root.appendingPathComponent("native-backtrack-output"), frameOrder: backtrack)
        for (url, data) in zip(native.frames, nativeOriginals) {
            try FramePreparationCache.store(FrameStitcher(options: CaptureOptions(axis: .horizontal))
                .prepareFrame(at: url, encodedData: data), for: url)
        }
        let prepared = try validate(native, output: root.appendingPathComponent("native-prepared-output"), prepared: true)
        require(prepared.preparedFrameCount == native.frames.count, "Every current prepared frame must be consumed")
        require(try Data(contentsOf: prepared.outputURLs[0]) == Data(contentsOf: nativeResult.outputURLs[0]),
                "Prepared and fallback paths must align frozen headings/body to exactly the same original pixels")
        require(try native.frames.map { try Data(contentsOf: $0) } == nativeOriginals,
                "Registration and rendering must never rewrite the original capture JPEGs")
        let frozen = try makeFixture(at: root.appendingPathComponent("frozen-columns-jitter"), scale: 3,
            jitters: jitter, frozenColumns: 188)
        try validate(frozen, output: root.appendingPathComponent("frozen-columns-jitter-forward"))
        try validate(frozen, output: root.appendingPathComponent("frozen-columns-jitter-reverse"),
            frameOrder: Array(frozen.frames.indices.reversed()))
        try validate(frozen, output: root.appendingPathComponent("frozen-columns-jitter-backtrack"), frameOrder: backtrack)
        let split = try FrameStitcher(options: CaptureOptions(axis: .horizontal, keepsStatusBar: true), testPageLimit: 1500)
            .stitch(frameURLs: frozen.frames, sessionURL: root.appendingPathComponent("frozen-columns-paginated"))
        require(split.outputURLs.count > 1, "Exercise pagination through a registered table body")
        var origin = 0
        for url in split.outputURLs {
            let page = UIImage(contentsOfFile: url.path)!
            let expected = UIImage(cgImage: frozen.expected.cgImage!.cropping(to: CGRect(x: origin, y: 0,
                width: page.cgImage!.width, height: frozen.pixelHeight))!)
            let left = origin == 0 ? 34 * frozen.scale : 0
            let rect = CGRect(x: left, y: 180 * frozen.scale, width: page.cgImage!.width - left, height: 400 * frozen.scale)
            require(meanError(page, expected, rect: rect) < 3, "Pagination must preserve global body coordinates without repeating frozen columns")
            origin += page.cgImage!.width
        }
        require(origin == frozen.pixelWidth, "Paginated coverage must equal the complete observed extent")
        // With a very wide fixed pane, fast swipes can leave cells permanently
        // behind the floating control even when the unoccluded top overlaps.
        let hidden = try makeFixture(at: root.appendingPathComponent("frozen-occluded-gap"), scale: 3,
            jitters: [0, 0, 0, 0], scrollOffsets: [0, 42, 83, 125], frozenColumns: 266)
        try validatePartial(hidden, output: root.appendingPathComponent("frozen-occluded-gap-output"))
        let hiddenJitter = try makeFixture(at: root.appendingPathComponent("frozen-occluded-jitter"), scale: 3,
            jitters: [0, 0, -1, 2], scrollOffsets: [0, 42, 83, 125], frozenColumns: 266)
        try validatePartial(hiddenJitter, output: root.appendingPathComponent("frozen-occluded-jitter-output"))
        let unproven = try makeFixture(at: root.appendingPathComponent("no-fixed-divider"), scale: 3,
            jitters: [0, 0, -3, -3], scrollOffsets: [0, 42, 42, 83], fixedHeaderDivider: false)
        let originals = try unproven.frames.map { try Data(contentsOf: $0) }
        do {
            _ = try FrameStitcher(options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
                .stitch(frameURLs: unproven.frames, sessionURL: root.appendingPathComponent("no-fixed-divider-output"))
            fatalError("A proven cross-axis grid shift without a proven frozen boundary must not generate a false column extent")
        } catch StitchError.unseenGap { checks += 1 }
        require(try unproven.frames.map { try Data(contentsOf: $0) } == originals,
                "An unsafe grid registration must preserve every original capture byte")
        let periodic = try makeFixture(at: root.appendingPathComponent("periodic-ambiguous"), scale: 3,
            jitters: [0, 0, 0], scrollOffsets: [0, 78, 156], identifiableColumns: false)
        try requireRejected(periodic, output: root.appendingPathComponent("periodic-ambiguous-output"),
            message: "A perfectly repeated table without unique column identities has no provable horizontal extent")
        let gap = try makeFixture(at: root.appendingPathComponent("nonoverlap"), scale: 3,
            jitters: [0, 0], scrollOffsets: [0, 430])
        try requireRejected(gap, output: root.appendingPathComponent("nonoverlap-output"),
            message: "Unique cells with no captured overlap must not be joined by a repeated-grid alias")
        print("Horizontal table jitter passed: \(checks) checks; frozen headings, aligned body rows, complete horizontal extent, shared visible pixels only; fixtures \(root.path)")
    }

    @MainActor static func makeFixture(at directory: URL, scale: Int, jitters: [Int], nativePixelJitters: [Int]? = nil,
                                       scrollOffsets: [Int] = offsets, fixedHeaderDivider: Bool = true,
                                       identifiableColumns: Bool = true, frozenColumns: Int = 0) throws -> Fixture {
        precondition(jitters.count == scrollOffsets.count && scrollOffsets.min() == 0)
        let pixelJitters = nativePixelJitters ?? jitters.map { $0 * scale }
        precondition(pixelJitters.count == scrollOffsets.count)
        let jitterPoints = pixelJitters.map { CGFloat($0) / CGFloat(scale) }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let width = scrollOffsets.max()! + screenWidth
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(scale); format.opaque = true; format.preferredRange = .standard
        func text(_ value: String, _ x: Int, _ y: Int, size: CGFloat = 11, gray: CGFloat = 0.12) {
            value.draw(at: CGPoint(x: x, y: y), withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: size, weight: .regular),
                .foregroundColor: UIColor(white: gray, alpha: 1)
            ])
        }
        let world = UIGraphicsImageRenderer(size: CGSize(width: width, height: screenHeight), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: screenHeight))
            UIColor(white: 0.97, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: columnHeaderTop, width: width, height: bodyTop - columnHeaderTop))
            for row in 0..<26 {
                let y = bodyTop + row * rowHeight
                UIColor(white: row % 2 == 0 ? 0.975 : 1, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: y, width: width, height: rowHeight))
                UIColor(white: 0.84, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: y, width: width, height: 1))
            }
            for column in 0..<16 {
                let x = 32 + column * 78
                UIColor(white: 0.82, alpha: 1).setFill()
                context.fill(CGRect(x: x, y: columnHeaderTop, width: 1, height: screenHeight - columnHeaderTop))
                text(identifiableColumns ? String(UnicodeScalar(65 + column)!) : "A", x + 33, columnHeaderTop + 6, size: 12)
                for row in 0..<26 {
                    text(String(format: "%02d-%02d", identifiableColumns ? column + 1 : 1, row + 1),
                        x + 13, bodyTop + row * rowHeight + 5)
                }
            }
        }
        var frames: [URL] = []
        for (index, offset) in scrollOffsets.enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: screenWidth, height: screenHeight), format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight))
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: columnHeaderTop, width: screenWidth, height: bodyTop - columnHeaderTop))
                world.draw(at: CGPoint(x: -offset, y: 0))
                if frozenColumns > 0 {
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: CGRect(x: 0, y: columnHeaderTop, width: frozenColumns, height: bodyTop - columnHeaderTop))
                    world.draw(at: .zero); context.cgContext.restoreGState()
                }
                context.cgContext.restoreGState()
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: bodyTop, width: screenWidth, height: bodyBottom - bodyTop))
                world.draw(at: CGPoint(x: CGFloat(-offset), y: jitterPoints[index]))
                if frozenColumns > 0 {
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: CGRect(x: 0, y: bodyTop, width: frozenColumns, height: bodyBottom - bodyTop))
                    world.draw(at: CGPoint(x: 0, y: jitterPoints[index])); context.cgContext.restoreGState()
                }
                // The row-number rail is frozen horizontally but follows the
                // body vertically, like the moving table grid.
                UIColor(white: 0.97, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: bodyTop, width: 31, height: bodyBottom - bodyTop))
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: jitterPoints[index])
                for row in 0..<26 { text("\(row + 1)", 7, bodyTop + row * rowHeight + 5, size: 9, gray: 0.5) }
                context.cgContext.restoreGState()
                context.cgContext.restoreGState()
                if fixedHeaderDivider {
                    // A one-native-pixel fixed separator has a peak exactly
                    // two pixels above the scroll-body boundary.
                    UIColor(white: 0.55, alpha: 1).setFill()
                    context.fill(CGRect(x: 0, y: CGFloat(bodyTop) - 2 / CGFloat(scale),
                        width: CGFloat(screenWidth), height: 1 / CGFloat(scale)))
                }
                text("09:41              100%", 24, 22, size: 17)
                text("‹    Table                       ···", 18, 77, size: 17)
                text("Sheet1", 15, 117, size: 14)
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: bodyBottom, width: screenWidth, height: screenHeight - bodyBottom))
                text("A1                        ×", 30, 716, size: 15, gray: 0.5)
                text("Local table", 30, 777, size: 18, gray: 0.5)
                UIColor.systemBlue.setFill(); context.fill(CGRect(x: 286, y: 638, width: 101, height: 38))
                text("TOOLS", 309, 649, size: 14, gray: 1)
            }
            let url = directory.appendingPathComponent(String(format: "frame-%02d.jpg", index))
            try image.jpegData(compressionQuality: 0.94)!.write(to: url)
            frames.append(url)
        }
        let topTrim = max(0, -(pixelJitters.min() ?? 0))
        let bottomTrim = max(0, pixelJitters.max() ?? 0)
        let outputHeight = CGFloat(screenHeight) - CGFloat(topTrim + bottomTrim) / CGFloat(scale)
        let expected = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width), height: outputHeight), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: outputHeight))
            context.cgContext.saveGState()
            context.cgContext.clip(to: CGRect(x: 0, y: columnHeaderTop, width: width, height: bodyTop - columnHeaderTop))
            world.draw(at: .zero)
            context.cgContext.restoreGState()
            if fixedHeaderDivider {
                UIColor(white: 0.55, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: CGFloat(bodyTop) - 2 / CGFloat(scale),
                    width: CGFloat(width), height: 1 / CGFloat(scale)))
            }
            context.cgContext.saveGState()
            context.cgContext.clip(to: CGRect(x: 0, y: CGFloat(bodyTop), width: CGFloat(width),
                height: CGFloat(bodyBottom - bodyTop) - CGFloat(topTrim + bottomTrim) / CGFloat(scale)))
            world.draw(at: CGPoint(x: 0, y: -CGFloat(topTrim) / CGFloat(scale)))
            context.cgContext.restoreGState()
        }
        try expected.pngData()!.write(to: directory.appendingPathComponent("expected-shared-body.png"))
        return Fixture(frames: frames, expected: expected, scale: scale, topTrim: topTrim, bottomTrim: bottomTrim,
                       pixelWidth: width * scale)
    }

    @MainActor @discardableResult
    static func validate(_ fixture: Fixture, output: URL, frameOrder: [Int]? = nil, prepared: Bool = false) throws -> StitchResult {
        let inputs = frameOrder.map { order in order.map { fixture.frames[$0] } } ?? fixture.frames
        let result = try FrameStitcher(usePreparedFrames: prepared, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
            .stitch(frameURLs: inputs, sessionURL: output)
        require(result.outputURLs.count == 1, "This fixture has exactly one horizontal page")
        require(!result.omittedOccludedBottomRows, "Recoverable content must never be qualified as partial")
        let image = UIImage(contentsOfFile: result.outputURLs[0].path)!
        require(image.cgImage!.width == fixture.pixelWidth,
                "Cross-axis registration must not omit or duplicate horizontal columns; expected \(fixture.pixelWidth), got \(image.cgImage!.width); output \(output.path)")
        require(image.cgImage!.height == fixture.pixelHeight,
                "Output must contain only the common captured body; expected \(fixture.pixelHeight), got \(image.cgImage!.height)")
        let scale = fixture.scale
        let header = CGRect(x: 34 * scale, y: columnHeaderTop * scale,
            width: fixture.pixelWidth - 34 * scale, height: (bodyTop - columnHeaderTop) * scale)
        require(meanError(image, fixture.expected, rect: header) < 3, "Frozen column headings must remain at their original vertical position")
        let body = CGRect(x: 34 * scale, y: (bodyTop + 10) * scale,
            width: fixture.pixelWidth - 34 * scale, height: (600 - bodyTop - 10) * scale - fixture.topTrim)
        let bodyError = meanError(image, fixture.expected, rect: body)
        require(bodyError < 3, "Body rows must align across every horizontal seam; MAE \(bodyError)")
        let rowErrors = (3...19).map { row in
            meanError(image, fixture.expected, rect: CGRect(x: 34 * scale,
                y: (bodyTop + row * rowHeight) * scale - fixture.topTrim,
                width: fixture.pixelWidth - 34 * scale, height: scale))
        }
        require(rowErrors.allSatisfy { $0 < 3 }, "Every known body grid line must remain straight; largest row MAE \(rowErrors.max()!)")
        let edgeRows = [(bodyTop + 1) * scale,
                        bodyBottom * scale - fixture.topTrim - fixture.bottomTrim - scale]
        require(edgeRows.allSatisfy { y in meanError(image, fixture.expected,
            rect: CGRect(x: 34 * scale, y: y, width: fixture.pixelWidth - 34 * scale, height: scale)) < 3 },
            "Body boundaries must be actual shared source pixels, without duplicated or invented edge rows")
        return result
    }

    @MainActor static func validatePartial(_ fixture: Fixture, output: URL) throws {
        let originals = try fixture.frames.map { try Data(contentsOf: $0) }
        let result = try FrameStitcher(usePreparedFrames: false, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
            .stitch(frameURLs: fixture.frames, sessionURL: output)
        require(result.omittedOccludedBottomRows, "Unobservable bottom cells require an explicit partial-output flag")
        let image = UIImage(contentsOfFile: result.outputURLs[0].path)!, scale = fixture.scale
        require(image.cgImage!.width == fixture.pixelWidth, "Bottom fallback cannot change column coverage")
        require(image.cgImage!.height < fixture.pixelHeight, "Unsupported button band must not be retained as repeated content")
        let bodyEnd = image.cgImage!.height - (screenHeight - bodyBottom) * scale
        let gridCoordinate = bodyEnd + fixture.topTrim - bodyTop * scale
        let remainder = gridCoordinate % (rowHeight * scale)
        require(min(remainder, rowHeight * scale - remainder) <= 4, "Fallback must end at a real complete row, even with Y drift")
        require(meanError(image, fixture.expected, rect: CGRect(x: 34 * scale, y: 180 * scale,
            width: fixture.pixelWidth - 34 * scale, height: bodyEnd - 180 * scale - 5)) < 3,
            "Every retained row above the occlusion must match the synthetic oracle")
        require(try fixture.frames.map { try Data(contentsOf: $0) } == originals, "Partial output never modifies original recordings")
    }

    @MainActor static func requireRejected(_ fixture: Fixture, output: URL, message: String) throws {
        let originals = try fixture.frames.map { try Data(contentsOf: $0) }
        do {
            _ = try FrameStitcher(usePreparedFrames: false, options: CaptureOptions(axis: .horizontal, keepsStatusBar: true))
                .stitch(frameURLs: fixture.frames, sessionURL: output)
            fatalError(message)
        } catch StitchError.unseenGap { checks += 1
        } catch StitchError.noUsableMovement { checks += 1 }
        require(try fixture.frames.map { try Data(contentsOf: $0) } == originals,
                "An uncertain/no-overlap result must preserve its original captures")
    }

    static func meanError(_ lhs: UIImage, _ rhs: UIImage, rect: CGRect) -> Double {
        func pixels(_ image: UIImage) -> [UInt8] {
            let cg = image.cgImage!, width = cg.width, height = cg.height
            var result = [UInt8](repeating: 0, count: width * height)
            result.withUnsafeMutableBytes { memory in
                let context = CGContext(data: memory.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
                context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return result
        }
        let a = pixels(lhs), b = pixels(rhs), aw = lhs.cgImage!.width, bw = rhs.cgImage!.width
        var difference = 0, count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
            difference += abs(Int(a[y * aw + x]) - Int(b[y * bw + x])); count += 1
        } }
        return Double(difference) / Double(count)
    }
}
