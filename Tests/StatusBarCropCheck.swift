import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// Real CoreGraphics/Vision fixtures. Private --fixture inputs are read in place.
@main
struct StatusBarCropCheck {
    private static var checks = 0

    static func main() throws {
#if canImport(UIKit)
        if CommandLine.arguments.contains("--integration") {
            if CommandLine.arguments.contains("--moving-status-probe") {
                try checkMovingStatusProbe()
                return
            }
            try checkStitcherIntegration()
            return
        }
#endif
        try checkNativeDetector()
        if let flag = CommandLine.arguments.firstIndex(of: "--fixture") {
            require(flag + 1 < CommandLine.arguments.count, "--fixture needs a local image path")
            try checkPrivateFixture(URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
        }
        print("Status bar native checks passed (\(checks) assertions): real Vision, compact/tall captures and conservative negatives.")
    }

    private static func require(_ value: Bool, _ message: String, line: UInt = #line) {
        checks += 1
        if !value { fatalError("\(message) (line \(line))") }
    }

    private enum Shape { case capsule, rectangle, absent }

    /// All coordinates are native pixels measured from the top-left.
    private static func makeHeader(width: Int = 1206, height: Int = 2622,
                                   clockTop: CGFloat? = 72, capsuleTop: CGFloat = 42,
                                   shape: Shape = .capsule,
                                   dark: Bool = false, scale: CGFloat = 1) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CheckError.image }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(gray: dark ? 0 : 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if shape != .absent {
            let rect = CGRect(x: CGFloat(width) / 2 - 176 * scale, y: capsuleTop,
                              width: 352 * scale, height: 108 * scale)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            if shape == .capsule {
                context.addPath(CGPath(roundedRect: rect, cornerWidth: 54 * scale,
                                       cornerHeight: 54 * scale, transform: nil))
                context.fillPath()
            } else {
                context.fill(rect)
            }
        }
        if let clockTop {
            drawText("09:41", at: CGPoint(x: 78 * scale, y: clockTop), size: 52 * scale,
                     color: CGColor(gray: dark ? 1 : 0, alpha: 1), in: context)
        }
        drawText("Weixin", at: CGPoint(x: CGFloat(width) / 2 - 75 * scale, y: 209 * scale),
                 size: 42 * scale, color: CGColor(gray: dark ? 1 : 0, alpha: 1), in: context)
        guard let image = context.makeImage() else { throw CheckError.image }
        return image
    }

    private static func drawText(_ value: String, at point: CGPoint, size: CGFloat,
                                 color: CGColor, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: point.x, y: point.y + CTFontGetAscent(font))
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes)), context)
        context.restoreGState()
    }

    private static func checkNativeDetector() throws {
        let positive = try makeHeader()
        // Native OCR failure is a failure, never a successful negative test.
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = .accurate
        probe.recognitionLanguages = ["en-US"]
        probe.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: positive).perform([probe])
        let text = (probe.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        require(text.contains("09:41") || text.contains("9:41"), "Native Vision must recognize the fixture clock: \(text)")
        let bottom = CaptureStatusBarDetector.bottom(in: positive, maximumBottom: 196)
        require(bottom != nil && bottom! >= 150 && bottom! <= 170,
                "Complete compact capsule is removed with only a small pixel pad: \(String(describing: bottom))")
        require(CaptureStatusBarDetector.bottom(in: positive, maximumBottom: 130) == nil,
                "An incomplete lower edge must never be clamped through the capsule")
        let tall = try makeHeader(height: 6051)
        let tallBottom = CaptureStatusBarDetector.bottom(in: tall, maximumBottom: floor(6051 * 0.075))
        require(tallBottom != nil && abs(tallBottom! - bottom!) <= 4,
                "A long result uses the captured status pixels, not a height percentage")
        let small = try makeHeader(width: 1005, height: 2185, clockTop: 60, capsuleTop: 35, scale: 5.0 / 6.0)
        let smallBottom = CaptureStatusBarDetector.bottom(in: small, maximumBottom: floor(2185 * 0.075))
        require(smallBottom != nil && smallBottom! >= 125 && smallBottom! <= 145,
                "Pixel evidence follows native width for a smaller portrait capture")
        let negatives: [(String, CGImage)] = [
            ("low clock", try makeHeader(clockTop: 510)),
            ("bottom clock", try makeHeader(clockTop: 2440)),
            ("pill without clock", try makeHeader(clockTop: nil)),
            ("clock without pill", try makeHeader(shape: .absent)),
            ("rectangular app banner", try makeHeader(shape: .rectangle)),
            ("full dark screenshot", try makeHeader(dark: true)),
            ("landscape content", try makeHeader(width: 2622, height: 1206))
        ]
        for (name, image) in negatives {
            require(CaptureStatusBarDetector.bottom(in: image, maximumBottom: floor(CGFloat(image.height) * 0.075)) == nil,
                    "Unproven status bar must preserve the source: \(name)")
        }
    }

    private static func checkPrivateFixture(_ url: URL) throws {
        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CheckError.image }
        require(image.width == 1206 && image.height == 6051,
                "Expected the authorized 1206×6051 private result, got \(image.width)×\(image.height)")
        let bottom = CaptureStatusBarDetector.bottom(in: image, maximumBottom: floor(CGFloat(image.height) * 0.075))
        require(bottom != nil && bottom! >= 160 && bottom! <= 200,
                "Authorized result must remove the complete island before the Weixin title: \(String(describing: bottom))")
        require(try Data(contentsOf: url) == original, "Private image bytes remain unchanged")
        print("Private fixture inspected in place: 1206×6051; detected bottom=\(bottom!); no image copied or emitted.")
    }

#if canImport(UIKit)
    private static func checkStitcherIntegration() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("LongShotStatusBar-\(UUID())", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["LONGSHOT_ALIGNMENT_TRACE"] == "1" {
            FrameStitcher.alignmentTrace = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
        }
        let frames = try makeScrollFrames(in: root.appendingPathComponent("island"), status: true)
        let noStatus = try makeScrollFrames(in: root.appendingPathComponent("no-status"), status: false)
        let small = try makeScrollFrames(in: root.appendingPathComponent("small"), status: true,
                                         width: 1005, height: 2185, count: 1)
        let originals = try (frames + noStatus + small).map { ($0, try Data(contentsOf: $0)) }
        func stitch(_ input: [URL], _ name: String, keep: Bool = false, cached: Bool = false,
                    ratio: Double = 0, boundaries: [Int] = [],
                    geometry: [CaptureGeometrySegment] = []) throws -> StitchResult {
            do {
                return try FrameStitcher(usePreparedFrames: cached, options: CaptureOptions(keepsStatusBar: keep))
                    .stitch(frameURLs: input, sessionURL: root.appendingPathComponent(name),
                            topCropRatio: ratio, segmentStarts: boundaries, geometrySegments: geometry)
            } catch {
                print("Status-bar integration fixture failed at \(name); generated fixture root: \(root.path)")
                throw error
            }
        }
        let source = try readImage(frames[0])
        let detected = CaptureStatusBarDetector.bottom(in: source, maximumBottom: floor(CGFloat(source.height) * 0.075))
        require(detected != nil, "JPEG source status bar must be recognized by native Vision")
        let cut = Int(detected!)
        let off = try stitch(frames, "off")
        let on = try stitch(frames, "on", keep: true)
        require(off.outputURLs.count == 1 && on.outputURLs.count == 1, "One complete output per scrolling page")
        let cropped = try readImage(off.outputURLs[0]), kept = try readImage(on.outputURLs[0])
        require(cropped.width == source.width && kept.width == source.width, "Native width stays unchanged")
        require(kept.height - cropped.height == cut, "OFF removes precisely the detected prefix; ON preserves it")
        require(kept.height == source.height + 5 * 137, "Every newly observed native body row is retained")
        require(pixelError(source, rect: CGRect(x: 0, y: cut, width: source.width, height: 120),
                           cropped, rect: CGRect(x: 0, y: 0, width: source.width, height: 120)) < 5,
                "Retained navigation/title pixels follow the exact source crop")
        require(pixelError(source, rect: CGRect(x: 0, y: 0, width: source.width, height: 190),
                           kept, rect: CGRect(x: 0, y: 0, width: source.width, height: 190)) < 5,
                "ON keeps the authentic original status bar")
        let legacy = try stitch(frames, "legacy-positive", ratio: 0.075)
        require(try kept.height - readImage(legacy.outputURLs[0]).height == Int(floor(CGFloat(source.height) * 0.075)),
                "Previously recorded positive crop ratios keep their old meaning")
        let unknownOff = try stitch(noStatus, "unknown-off")
        let unknownOn = try stitch(noStatus, "unknown-on", keep: true)
        require(try Data(contentsOf: unknownOff.outputURLs[0]) == Data(contentsOf: unknownOn.outputURLs[0]),
                "Absent captured status evidence preserves all header pixels")
        let reverse = try stitch(Array(frames.reversed()), "reverse")
        require(try Data(contentsOf: off.outputURLs[0]) == Data(contentsOf: reverse.outputURLs[0]),
                "Reverse recording detects the actual selected upper source")
        for (url, data) in originals {
            try FramePreparationCache.store(FrameStitcher().prepareFrame(at: url, encodedData: data), for: url)
        }
        let cached = try stitch(frames, "cached", cached: true)
        require(cached.preparedFrameCount == frames.count, "Existing prepared payloads are reused")
        require(try Data(contentsOf: off.outputURLs[0]) == Data(contentsOf: cached.outputURLs[0]),
                "Prepared and original analysis paths produce byte-identical JPEG outputs")
        let pages = frames + [frames[0]]
        let pageOff = try stitch(pages, "page-off", boundaries: [0, frames.count])
        let pageOn = try stitch(pages, "page-on", keep: true, boundaries: [0, frames.count])
        require(try readImage(pageOn.outputURLs[0]).height - readImage(pageOff.outputURLs[0]).height == 2 * cut,
                "Each explicit page removes its own status bar, including a static page")
        let geometry = [
            CaptureGeometrySegment(startFrame: 0, pixelWidth: 1206, pixelHeight: 2622, videoOrientation: 1),
            CaptureGeometrySegment(startFrame: frames.count, pixelWidth: 1005, pixelHeight: 2185, videoOrientation: 1)
        ]
        let geoOff = try stitch(frames + small, "geometry-off", boundaries: [0, frames.count], geometry: geometry)
        let geoOn = try stitch(frames + small, "geometry-on", keep: true, boundaries: [0, frames.count], geometry: geometry)
        require(geoOff.outputsSeparatedByGeometry && geoOff.outputURLs.count == 2,
                "Different captured geometry remains independent native-size outputs")
        for index in 0..<2 {
            let raw = try readImage(index == 0 ? frames[0] : small[0])
            let detected = CaptureStatusBarDetector.bottom(in: raw, maximumBottom: floor(CGFloat(raw.height) * 0.075))
            require(detected != nil, "Each geometry proves its own captured status band")
            let a = try readImage(geoOn.outputURLs[index]), b = try readImage(geoOff.outputURLs[index])
            require(a.width == raw.width && b.width == raw.width && a.height - b.height == Int(detected!),
                    "Geometry page \(index) crops only its own proved status pixels")
        }
        try checkHorizontalIntegration(in: root.appendingPathComponent("horizontal"))
        for (url, data) in originals {
            require(try Data(contentsOf: url) == data, "Every original JPEG remains byte-for-byte unchanged")
        }
        print("Status-bar UIKit integration passed (\(checks) assertions): OFF/ON, title pixels, unknown source, legacy ratio, reverse, cache, explicit/static pages and geometry groups. Generated fixtures: \(root.path)")
    }

    private static func checkMovingStatusProbe() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LongShotMovingStatus-\(UUID())")
        let frames = try makeScrollFrames(in: root.appendingPathComponent("frames"), status: true,
                                         count: 3, axis: .horizontal, headerMovement: 2)
        FrameStitcher.alignmentTrace = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
        for ratio in [0.0, 0.075] {
            do {
                let result = try FrameStitcher(usePreparedFrames: false, options: CaptureOptions(axis: .horizontal))
                    .stitch(frameURLs: frames, sessionURL: root.appendingPathComponent("ratio-\(ratio)"), topCropRatio: ratio)
                let image = try readImage(result.outputURLs[0])
                FileHandle.standardError.write(Data("MOVING STATUS ratio=\(ratio) success \(image.width)x\(image.height)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("MOVING STATUS ratio=\(ratio) failure \(error)\n".utf8))
            }
        }
        FileHandle.standardError.write(Data("Moving-status synthetic probe fixtures: \(root.path)\n".utf8))
    }

    private static func checkHorizontalIntegration(in root: URL) throws {
        let frames = try makeScrollFrames(in: root.appendingPathComponent("captured"), status: true, count: 3, axis: .horizontal)
        let unknown = try makeScrollFrames(in: root.appendingPathComponent("unknown"), status: false, count: 3, axis: .horizontal)
        let small = try makeScrollFrames(in: root.appendingPathComponent("small"), status: true,
                                        width: 1005, height: 2185, count: 1, axis: .horizontal)
        let shifted = try makeScrollFrames(in: root.appendingPathComponent("shifted-status"), status: true,
                                          count: 1, axis: .horizontal, headerOffset: 12)
        let animated = try makeScrollFrames(in: root.appendingPathComponent("animated-status"), status: true,
                                           count: 3, axis: .horizontal, headerMovement: 2)
        let early = try makeScrollFrames(in: root.appendingPathComponent("early-moving-row"), status: true,
                                        count: 3, axis: .horizontal, headerMovement: 2, earlyMovingRow: true)
        let originals = try (frames + unknown + small + shifted + animated + early).map { ($0, try Data(contentsOf: $0)) }
        func stitch(_ input: [URL], _ name: String, keep: Bool = false, cached: Bool = false,
                    ratio: Double = 0, starts: [Int] = [], geometry: [CaptureGeometrySegment] = []) throws -> StitchResult {
            do {
                return try FrameStitcher(usePreparedFrames: cached, options: CaptureOptions(axis: .horizontal, keepsStatusBar: keep))
                    .stitch(frameURLs: input, sessionURL: root.appendingPathComponent(name), topCropRatio: ratio,
                            segmentStarts: starts, geometrySegments: geometry)
            } catch {
                FileHandle.standardError.write(Data("Horizontal status fixture failed at \(name): \(error); root \(root.path)\n".utf8))
                throw error
            }
        }
        let source = try readImage(frames[0])
        let cut = Int(CaptureStatusBarDetector.bottom(in: source, maximumBottom: floor(CGFloat(source.height) * 0.075))!)
        let off = try stitch(frames, "off"), on = try stitch(frames, "on", keep: true)
        let cropped = try readImage(off.outputURLs[0]), kept = try readImage(on.outputURLs[0])
        require(cropped.width == source.width + 2 * 137 && kept.width == cropped.width,
                "Horizontal OFF/ON retain every native scrolling column")
        require(kept.height == source.height && kept.height - cropped.height == cut,
                "Horizontal OFF removes exactly the proved native status band")
        require(pixelError(source, rect: CGRect(x: 0, y: cut, width: source.width, height: 120),
                           cropped, rect: CGRect(x: 0, y: 0, width: source.width, height: 120)) < 5,
                "Horizontal OFF preserves navigation/title pixels below the band")
        require(pixelError(source, rect: CGRect(x: 0, y: 0, width: source.width, height: cut),
                           kept, rect: CGRect(x: 0, y: 0, width: source.width, height: cut)) < 5,
                "Horizontal ON preserves one authentic captured status bar")
        require(pixelError(kept, rect: CGRect(x: source.width + 20, y: 0, width: 100, height: cut),
                           kept, rect: CGRect(x: source.width + 140, y: 0, width: 100, height: cut)) < 1,
                "Horizontal ON leaves the extra wide status region uniform")
        let legacy = try stitch(frames, "legacy", ratio: 0.075)
        require(try readImage(legacy.outputURLs[0]).height == source.height - Int(floor(CGFloat(source.height) * 0.075)),
                "Horizontal legacy crop ratios retain their original meaning")
        let animatedOff = try stitch(animated, "animated-off"), animatedOn = try stitch(animated, "animated-on", keep: true)
        require(try readImage(animatedOff.outputURLs[0]).width == source.width + 2 * 137
                && readImage(animatedOn.outputURLs[0]).height - readImage(animatedOff.outputURLs[0]).height == cut,
                "Moving compact status indicators cannot become a false column-identity layer")
        let animatedReverse = try stitch(Array(animated.reversed()), "animated-reverse")
        require(try Data(contentsOf: animatedReverse.outputURLs[0]) == Data(contentsOf: animatedOff.outputURLs[0]),
                "Animated-status horizontal reverse preserves the same native output")
        let reverse = try stitch(Array(frames.reversed()), "reverse")
        require(try Data(contentsOf: reverse.outputURLs[0]) == Data(contentsOf: off.outputURLs[0]),
                "Horizontal reverse capture uses the selected original prefix")
        for (url, data) in originals {
            try FramePreparationCache.store(FrameStitcher(options: CaptureOptions(axis: .horizontal))
                .prepareFrame(at: url, encodedData: data), for: url)
        }
        let cached = try stitch(frames, "cached", cached: true)
        require(try cached.preparedFrameCount == frames.count && Data(contentsOf: cached.outputURLs[0]) == Data(contentsOf: off.outputURLs[0]),
                "Horizontal crop preserves cached/uncached output equivalence")
        let earlyOff = try stitch(early, "early-row-off"), earlyOn = try stitch(early, "early-row-on", keep: true)
        let earlyImage = try readImage(earlyOn.outputURLs[0])
        let observedBottoms = try early.map { url -> CGFloat in
            let image = try readImage(url)
            return CaptureStatusBarDetector.capsuleBottom(in: image, maximumBottom: 196)!
        }
        require(observedBottoms.max()! < 166 && 174 < 196,
                "Moving test rows lie strictly below every observed capsule and above the old percentage bound")
        require(earlyImage.width == source.width + 2 * 137, "Early moving rows retain the full observed horizontal extent")
        for (index, url) in early.enumerated() {
            let raw = try readImage(url)
            require(pixelError(raw, rect: CGRect(x: index == 0 ? 20 : source.width - 120, y: 166, width: 100, height: 8),
                               earlyImage, rect: CGRect(x: index == 0 ? 20 : source.width - 120 + index * 137, y: 166, width: 100, height: 8)) < 5,
                    "Moving row pixels directly below the proved status extent stay aligned to their native source")
        }
        require(try readImage(earlyOff.outputURLs[0]).height == earlyImage.height - cut,
                "Early moving body rows cannot increase the exact output status crop")
        let animatedCached = try stitch(animated, "animated-cached", cached: true)
        require(try animatedCached.preparedFrameCount == animated.count
                && Data(contentsOf: animatedCached.outputURLs[0]) == Data(contentsOf: animatedOff.outputURLs[0]),
                "Animated status analysis retains cache equivalence")
        let unknownOff = try stitch(unknown, "unknown-off"), unknownOn = try stitch(unknown, "unknown-on", keep: true)
        require(try Data(contentsOf: unknownOff.outputURLs[0]) == Data(contentsOf: unknownOn.outputURLs[0]),
                "Unproved horizontal status areas preserve every native row")
        let explicit = try stitch(frames + [frames[0]], "explicit-static", starts: [frames.count])
        require(try readImage(explicit.outputURLs[0]).height == cropped.height,
                "Horizontal explicit/static pages use their own captured evidence")
        let shiftedImage = try readImage(shifted[0])
        let shiftedBottom = CaptureStatusBarDetector.bottom(in: shiftedImage, maximumBottom: floor(CGFloat(shiftedImage.height) * 0.075))
        require(shiftedBottom != nil && shiftedBottom! > CGFloat(cut),
                "Mixed positive pages prove two distinct status extents independently")
        let variedOff = try stitch(frames + shifted, "different-status-extents", starts: [frames.count])
        let variedOn = try stitch(frames + shifted, "different-status-extents-on", keep: true, starts: [frames.count])
        require(try readImage(variedOff.outputURLs[0]).height == source.height
                && Data(contentsOf: variedOff.outputURLs[0]) == Data(contentsOf: variedOn.outputURLs[0]),
                "Different proved status extents preserve whole bars instead of bisecting a capsule")
        let mixed = try stitch(frames + [unknown[0]], "mixed-evidence", starts: [frames.count])
        require(try readImage(mixed.outputURLs[0]).height == source.height,
                "Unknown explicit-page headers prevent a shared destructive crop")
        let records = [CaptureGeometrySegment(startFrame: 0, pixelWidth: source.width, pixelHeight: source.height, videoOrientation: 1),
            CaptureGeometrySegment(startFrame: frames.count, pixelWidth: 1005, pixelHeight: 2185, videoOrientation: 1)]
        let geoOff = try stitch(frames + small, "geometry-off", starts: [frames.count], geometry: records)
        let geoOn = try stitch(frames + small, "geometry-on", keep: true, starts: [frames.count], geometry: records)
        require(geoOff.outputsSeparatedByGeometry && geoOff.outputURLs.count == 2, "Horizontal native geometries remain separate outputs")
        for index in 0..<2 {
            let raw = try readImage(index == 0 ? frames[0] : small[0])
            let nativeCut = Int(CaptureStatusBarDetector.bottom(in: raw, maximumBottom: floor(CGFloat(raw.height) * 0.075))!)
            require(try readImage(geoOn.outputURLs[index]).height - readImage(geoOff.outputURLs[index]).height == nativeCut,
                    "Each horizontal geometry independently proves its crop")
        }
        for (url, data) in originals {
            require(try Data(contentsOf: url) == data, "Horizontal source JPEGs remain byte-identical")
        }
    }

    private static func makeScrollFrames(in directory: URL, status: Bool, width: Int = 1206,
                                         height: Int = 2622, count: Int = 6, axis: CaptureAxis = .vertical, headerOffset: Int = 0, headerMovement: Int = 0, earlyMovingRow: Bool = false) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let top = floor(CGFloat(height) * 0.075), bottom = CGFloat(height) - ceil(CGFloat(height) * 0.19)
        let scale = CGFloat(width) / 1206
        var random: UInt64 = 0x35a179c4
        let worldWidth = width + (axis == .horizontal ? count * 137 : 0)
        let worldHeight = height + (axis == .vertical ? count * 137 : 0)
        let world = UIGraphicsImageRenderer(size: CGSize(width: worldWidth, height: worldHeight), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: worldWidth, height: worldHeight))
            for y in stride(from: 0, to: worldHeight, by: axis == .horizontal ? 87 : 11) {
                for x in stride(from: 0, to: worldWidth, by: axis == .horizontal ? 93 : 24) {
                    random = random &* 6364136223846793005 &+ 1442695040888963407
                    let shade = CGFloat(40 + ((random >> 32) % 180)) / 255
                    UIColor(red: shade, green: min(1, shade * 0.86), blue: min(1, shade * 1.1), alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y,
                        width: axis == .horizontal ? 20 + Int((random >> 16) % 60) : 24,
                        height: axis == .horizontal ? 20 + Int((random >> 24) % 50) : 11))
                }
            }
        }
        return try (0..<count).map { index in
            // Different temporal headers expose accidentally detecting frame zero
            // instead of the source selected for the beginning of a reverse capture.
            let temporalOffset = headerOffset + index * (axis == .vertical ? 2 : headerMovement)
            let header = try makeHeader(width: width, height: height,
                clockTop: status ? CGFloat(72 + temporalOffset) * scale : nil,
                capsuleTop: CGFloat(42 + temporalOffset) * scale,
                shape: status ? .capsule : .absent, scale: scale)
            let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
                UIImage(cgImage: header).draw(at: .zero)
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: top, width: CGFloat(width), height: bottom - top))
                world.draw(at: CGPoint(x: axis == .horizontal ? -CGFloat(index * 137) : 0,
                                       y: top - (axis == .vertical ? CGFloat(index * 137) : 0)))
                context.cgContext.restoreGState()
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: top, width: CGFloat(width), height: 86 * scale))
                "Weixin".draw(at: CGPoint(x: CGFloat(width) / 2 - 75 * scale, y: 209 * scale),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 42 * scale), .foregroundColor: UIColor.black])
                if earlyMovingRow {
                    for x in stride(from: 0, to: worldWidth, by: 41) {
                        let value = (x / 41 * 73 + 37) % 200
                        UIColor(white: CGFloat(value) / 255, alpha: 1).setFill()
                        context.fill(CGRect(x: x - index * 137, y: 166, width: 41, height: 8))
                    }
                }
                // A distinct native navigation band must survive directly below the status crop.
                UIColor(red: 0.05, green: 0.55, blue: 0.93, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 178 * scale, width: CGFloat(width), height: 12 * scale))
            }
            let url = CaptureStorage.frameURL(index: index, sessionURL: directory)
            guard let data = image.jpegData(compressionQuality: 0.94) else { throw CheckError.image }
            try data.write(to: url)
            return url
        }
    }

    private static func readImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CheckError.image }
        return image
    }

    private static func pixelError(_ first: CGImage, rect a: CGRect, _ second: CGImage, rect b: CGRect) -> Double {
        func pixels(_ image: CGImage, _ rect: CGRect) -> [UInt8] {
            guard let crop = image.cropping(to: rect) else { return [] }
            let width = 128, height = 64
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.interpolationQuality = .medium
                context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return bytes
        }
        let left = pixels(first, a), right = pixels(second, b)
        guard left.count == right.count, !left.isEmpty else { return .infinity }
        return zip(left, right).map { Double(abs(Int($0) - Int($1))) }.reduce(0, +) / Double(left.count)
    }
#endif
}

private enum CheckError: Error { case image }
