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
        checkInpainterContract()
        try checkNativeRepairMaskCoverage()
        try checkNativeDetector()
        if let flag = CommandLine.arguments.firstIndex(of: "--fixture") {
            require(flag + 1 < CommandLine.arguments.count, "--fixture needs a local image path")
            try checkPrivateFixture(URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
        }
        print("Status bar native checks passed (\(checks) assertions): bounded native inpainting contracts, real Vision, compact/split recording indicators, patterned/tall captures and conservative negatives.")
    }

    private static func require(_ value: Bool, _ message: String, line: UInt = #line) {
        checks += 1
        if !value { fatalError("\(message) (line \(line))") }
    }

    private enum Shape { case capsule, recordingCapsule, splitRecording, spurredRecordingBubble, rectangle, circle, absent }
    private enum HeaderBackground { case plain, textured, photographic, unboundedShadow }

    /// All coordinates are native pixels measured from the top-left.
    private static func makeHeader(width: Int = 1206, height: Int = 2622,
                                   clockTop: CGFloat? = 72, capsuleTop: CGFloat = 42,
                                   shape: Shape = .capsule,
                                   dark: Bool = false, scale: CGFloat = 1,
                                   background: HeaderBackground = .plain) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CheckError.image }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(gray: dark ? 0 : 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if background != .plain {
            try drawPatternedHeader(in: context, width: width, height: height, scale: scale, background: background)
        }
        if shape != .absent {
            let rect = CGRect(x: CGFloat(width) / 2 - 176 * scale, y: capsuleTop,
                              width: 352 * scale, height: 108 * scale)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            if shape == .circle {
                context.fillEllipse(in: CGRect(x: CGFloat(width) / 2 - 54 * scale,
                    y: capsuleTop, width: 108 * scale, height: 108 * scale))
            } else if shape != .rectangle {
                context.addPath(CGPath(roundedRect: rect, cornerWidth: 54 * scale,
                                       cornerHeight: 54 * scale, transform: nil))
                context.fillPath()
            } else {
                context.fill(rect)
            }
            if shape == .recordingCapsule || shape == .splitRecording || shape == .spurredRecordingBubble {
                let ring = CGRect(x: rect.maxX - 74 * scale, y: capsuleTop + 34 * scale,
                    width: 40 * scale, height: 40 * scale)
                context.setFillColor(CGColor(red: 0.98, green: 0.13, blue: 0.19, alpha: 1))
                context.fillEllipse(in: ring)
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fillEllipse(in: ring.insetBy(dx: 11 * scale, dy: 11 * scale))
            }
            if shape == .splitRecording || shape == .spurredRecordingBubble {
                // A separate recording bubble can extend below the main island.
                // Its complete native lower edge is 164 px at 1206 px width.
                let bubble = CGRect(x: rect.maxX + 24 * scale, y: capsuleTop + 14 * scale,
                    width: 108 * scale, height: 108 * scale)
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fillEllipse(in: bubble)
                let ring = bubble.insetBy(dx: 33 * scale, dy: 33 * scale)
                context.setFillColor(CGColor(red: 0.98, green: 0.13, blue: 0.19, alpha: 1))
                context.fillEllipse(in: ring)
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fillEllipse(in: ring.insetBy(dx: 10 * scale, dy: 10 * scale))
                context.setFillColor(CGColor(red: 0.98, green: 0.13, blue: 0.19, alpha: 1))
                context.fillEllipse(in: ring.insetBy(dx: 16 * scale, dy: 16 * scale))
                if shape == .spurredRecordingBubble {
                    // This near-black photographic feature joins the red-marked
                    // bubble and reaches the inspection edge. Main-only cropping
                    // would leave uncertain status pixels in the retained result.
                    context.setFillColor(CGColor(gray: 0.015, alpha: 1))
                    context.fill(CGRect(x: CGFloat(width) / 2 + 237 * scale,
                        y: capsuleTop + 108 * scale, width: 45 * scale, height: 68 * scale))
                }
            }
        }
        if let clockTop {
            let statusColor = CGColor(gray: dark || background != .plain ? 1 : 0, alpha: 1)
            drawText("09:41", at: CGPoint(x: 78 * scale, y: clockTop), size: 52 * scale,
                     color: statusColor, in: context)
            // Real status-side pixels make a clock/battery-preservation check
            // meaningful; neither glyph provides recording-island evidence.
            context.setFillColor(statusColor)
            for index in 0..<4 {
                context.fill(CGRect(x: CGFloat(1004 + index * 12) * scale,
                    y: CGFloat(106 - index * 7) * scale, width: 8 * scale,
                    height: CGFloat(10 + index * 7) * scale))
            }
            let battery = CGRect(x: 1064 * scale, y: 82 * scale, width: 80 * scale, height: 38 * scale)
            context.setStrokeColor(statusColor)
            context.setLineWidth(4 * scale)
            context.addPath(CGPath(roundedRect: battery, cornerWidth: 7 * scale,
                cornerHeight: 7 * scale, transform: nil))
            context.strokePath()
            context.fill(battery.insetBy(dx: 7 * scale, dy: 7 * scale))
            context.fill(CGRect(x: 1146 * scale, y: 94 * scale, width: 7 * scale, height: 14 * scale))
        }
        drawText("Weixin", at: CGPoint(x: CGFloat(width) / 2 - 75 * scale, y: 209 * scale),
                 size: 42 * scale, color: CGColor(gray: dark || background != .plain ? 1 : 0, alpha: 1), in: context)
        guard let image = context.makeImage() else { throw CheckError.image }
        return image
    }

    /// Procedural photo-like lighting and texture, with no private image pixels.
    /// Dim pixels connect to black at the old threshold of 65, while remaining
    /// distinct from the near-black system indicators. The clock is white.
    private static func drawPatternedHeader(in context: CGContext, width: Int, height: Int,
                                            scale: CGFloat, background: HeaderBackground) throws {
        let rows = min(height, Int(ceil(420 * scale)))
        var bytes = [UInt8](repeating: 255, count: width * rows * 4)
        for y in 0..<rows {
            for x in 0..<width {
                let xx = Double(x) / Double(scale), yy = Double(y) / Double(scale)
                let grain = Double((x &* 73 &+ y &* 137 &+ (x &* y) % 29) % 11) - 5
                let value: Double
                if background == .unboundedShadow {
                    value = 8 + 3 * sin(xx / 23) + 2 * cos(yy / 17) + grain * 0.2
                } else if background == .textured {
                    value = 47 + 7 * sin(xx / 23) + 5 * cos(yy / 17) + grain * 0.5
                } else {
                    let dx = (xx - 627) / 434, dy = (yy - 100) / 210
                    let shadow = exp(-(dx * dx + dy * dy))
                    value = max(35, 140 - 98 * shadow + 9 * sin(xx / 67 + yy / 41) + grain)
                }
                let i = (y * width + x) * 4
                bytes[i] = UInt8(min(255, max(0, Int(value + 7))))
                bytes[i + 1] = UInt8(min(255, max(0, Int(value))))
                bytes[i + 2] = UInt8(min(255, max(0, Int(value - 6))))
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw CheckError.image
        }
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(rows))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: rows))
        context.restoreGState()
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

    private static func checkInpainterContract() {
        let width = 128, height = 72
        var mask = [UInt8](repeating: 0, count: width * height)
        // A small capsule and detached circle leave observed context on every
        // side and below the complete overlay, as required by production.
        for y in 0..<height {
            for x in 0..<width {
                let xx = Double(x) + 0.5, yy = Double(y) + 0.5
                let capsuleX = max(51, min(77, xx))
                if pow(xx - capsuleX, 2) + pow(yy - 21, 2) <= 81
                    || pow(xx - 101, 2) + pow(yy - 23, 2) <= 64 {
                    mask[y * width + x] = 255
                }
            }
        }
        var flat = [UInt8]()
        for gradient in [false, true] {
            var expected = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                    for channel in 0..<3 {
                        let slope = gradient ? Double(x) * 0.2 + Double(y) * 0.3 : 0
                        expected[index + channel] = UInt8((72 + Double(channel) * 24 + slope).rounded())
                    }
                    // Vary alpha while keeping valid premultiplied RGB. This
                    // proves preservation inside the mask as well as outside it.
                    expected[index + 3] = UInt8(190 + (x + 2 * y) % 66)
                }
            }
            var damaged = expected
            // Distinct observed side glyphs must remain byte-exact.
            for (x, y, rgba) in [(8, 18, [UInt8(180), 180, 180, 220]),
                                  (119, 20, [UInt8(20), 170, 45, 230])] {
                let index = (y * width + x) * 4
                for channel in 0..<4 { damaged[index + channel] = rgba[channel] }
            }
            for pixel in mask.indices where mask[pixel] != 0 {
                for channel in 0..<3 { damaged[pixel * 4 + channel] = 0 }
            }
            let label = gradient ? "linear gradient" : "flat background"
            let repaired = CaptureStatusBarInpainter.inpaintRGBA(damaged, width: width, height: height, mask: mask)
            require(repaired != nil, "Native inpainter repairs a bounded \(label) mask")
            let result = repaired!
            var absoluteError = 0, samples = 0
            var outsideUnchanged = true, alphaUnchanged = true
            for pixel in mask.indices {
                let index = pixel * 4
                alphaUnchanged = alphaUnchanged && result[index + 3] == damaged[index + 3]
                if mask[pixel] == 0 {
                    outsideUnchanged = outsideUnchanged && (0..<4).allSatisfy { result[index + $0] == damaged[index + $0] }
                } else {
                    for channel in 0..<3 {
                        absoluteError += abs(Int(result[index + channel]) - Int(expected[index + channel]))
                        samples += 1
                    }
                }
            }
            let meanError = Double(absoluteError) / Double(samples)
            require(gradient ? meanError < 1 : absoluteError == 0,
                    "Native \(label) reconstruction meets its masked RGB error bound: \(meanError)")
            require(outsideUnchanged, "Every unmasked \(label) RGBA byte, including side glyphs, remains unchanged")
            require(alphaUnchanged, "Every \(label) alpha byte remains unchanged, including inside the mask")
            require(CaptureStatusBarInpainter.inpaintRGBA(damaged, width: width, height: height, mask: mask) == result,
                    "Native \(label) repair is deterministic for the same input")
            if !gradient { flat = damaged }
        }
        let empty = [UInt8](repeating: 0, count: mask.count)
        require(CaptureStatusBarInpainter.inpaintRGBA(flat, width: width, height: height, mask: empty) == flat,
                "An empty inpainting mask is exact passthrough")
        var missingContext = empty
        missingContext[(height - 4) * width + width / 2] = 255
        require(CaptureStatusBarInpainter.inpaintRGBA(flat, width: width, height: height, mask: missingContext) == nil,
                "An interior mask with insufficient observed lower context is declined")
        require(CaptureStatusBarInpainter.inpaintRGBA(flat, width: width, height: height, mask: Array(mask.dropLast())) == nil,
                "A malformed mask length is declined")
        require(CaptureStatusBarInpainter.inpaintRGBA(Array(flat.dropLast()), width: width, height: height, mask: mask) == nil,
                "A malformed RGBA byte length is declined")
    }

    private static func checkNativeRepairMaskCoverage() throws {
        for width in [1005, 1206] {
            let scale = CGFloat(width) / 1206
            let height = width == 1005 ? 2185 : 2622
            for top: CGFloat in [37, 42.25, 43.75] {
                let split = top != 37
                let label = "\(width)px \(split ? "split" : "compact") at native y=\(top)"
                let image = try makeHeader(width: width, height: height, clockTop: 72 * scale,
                    capsuleTop: top, shape: split ? .splitRecording : .recordingCapsule,
                    scale: scale, background: split ? .photographic : .plain)
                let proof = CaptureStatusBarDetector.repairEvidence(in: image,
                    maximumBottom: floor(CGFloat(height) * 0.075))
                require(proof != nil, "Native mask coverage fixture must prove its clock and island: \(label)")
                let evidence = proof!
                let bytes = nativePixels(image, rect: CGRect(x: 0, y: 0, width: width, height: evidence.band))
                require(bytes.count == width * evidence.band * 4 && evidence.mask.count == width * evidence.band,
                        "Native source pixels and repair mask share exact row-major dimensions: \(label)")
                let main = CGRect(x: CGFloat(width) / 2 - 176 * scale, y: top,
                    width: 352 * scale, height: 108 * scale)
                var regions = [main]
                if split {
                    regions.append(CGRect(x: main.maxX + 24 * scale, y: top + 14 * scale,
                        width: 108 * scale, height: 108 * scale))
                }
                var counts: [Int] = [], uncovered = 0
                for region in regions {
                    var black = 0
                    // Inspect only the known indicator bounds, not dark photo
                    // content elsewhere. Every near-black edge pixel matters:
                    // even a small fixed black rim contaminates a Poisson fill.
                    for y in max(0, Int(floor(region.minY)))..<min(evidence.band, Int(ceil(region.maxY))) {
                        for x in max(0, Int(floor(region.minX)))..<min(width, Int(ceil(region.maxX))) {
                            let pixel = y * width + x, index = pixel * 4
                            if max(bytes[index], bytes[index + 1], bytes[index + 2]) < 28 {
                                black += 1
                                if evidence.mask[pixel] == 0 { uncovered += 1 }
                            }
                        }
                    }
                    counts.append(black)
                }
                require(counts.allSatisfy { $0 > 100 } && uncovered == 0,
                        "Native repair mask covers every source near-black main/circle pixel: \(label), sourceCounts=\(counts), uncovered=\(uncovered)")
            }
        }
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
        for background in [HeaderBackground.textured, .photographic] {
            for shape in [Shape.recordingCapsule, .splitRecording] {
                let patterned = try makeHeader(shape: shape, background: background)
                let clock = patterned.cropping(to: CGRect(x: 0, y: 0, width: 325, height: 218))!
                try VNImageRequestHandler(cgImage: clock).perform([probe])
                let text = (probe.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                require(text.contains("09:41") || text.contains("9:41"),
                        "Native Vision must recognize the white clock over \(background): \(text)")
                let lowerEdge: CGFloat = shape == .splitRecording ? 164 : 150
                let detected = CaptureStatusBarDetector.bottom(in: patterned, maximumBottom: 196)
                require(detected != nil && detected! >= lowerEdge && detected! < 178,
                        "The complete \(shape) status band is removed over \(background): \(String(describing: detected))")
                require(CaptureStatusBarDetector.capsuleBottom(in: patterned, maximumBottom: 196) == detected,
                        "Clock and geometry paths agree on the whole patterned status band")
                require(CaptureStatusBarDetector.bottom(in: patterned, maximumBottom: lowerEdge - 4) == nil,
                        "A content bound through the \(shape) lower edge preserves the whole source")
                require(detected! < 209, "The navigation title below the patterned status band is retained")
            }
        }
        let splitTall = try makeHeader(height: 7273, shape: .splitRecording, background: .photographic)
        let splitTallBottom = CaptureStatusBarDetector.bottom(in: splitTall, maximumBottom: floor(7273 * 0.075))
        require(splitTallBottom != nil && splitTallBottom! >= 164 && splitTallBottom! < 178,
                "Photographic tall results remove the captured split status band without using result height")
        let splitSmall = try makeHeader(width: 1005, height: 2185, clockTop: 60, capsuleTop: 35,
            shape: .splitRecording, scale: 5.0 / 6.0, background: .photographic)
        let splitSmallBottom = CaptureStatusBarDetector.bottom(in: splitSmall, maximumBottom: floor(2185 * 0.075))
        require(splitSmallBottom != nil && splitSmallBottom! >= 164 * 5.0 / 6.0 && splitSmallBottom! < 150,
                "A smaller native photographic header includes the complete separate recording bubble")
        let uncertainBubble = try makeHeader(shape: .spurredRecordingBubble, background: .photographic)
        require(CaptureStatusBarDetector.capsuleBottom(in: uncertainBubble, maximumBottom: 196) == nil,
                "A red-marked bubble joined to a near-black photo spur cannot fall back to the main island's lower edge")
        let negatives: [(String, CGImage)] = [
            ("low clock", try makeHeader(clockTop: 510)),
            ("bottom clock", try makeHeader(clockTop: 2440)),
            ("pill without clock", try makeHeader(clockTop: nil)),
            ("clock without pill", try makeHeader(shape: .absent)),
            ("rectangular app banner", try makeHeader(shape: .rectangle)),
            ("full dark screenshot", try makeHeader(dark: true)),
            ("landscape content", try makeHeader(width: 2622, height: 1206)),
            ("photo and white clock without island", try makeHeader(shape: .absent, background: .photographic)),
            ("textured white clock without island", try makeHeader(shape: .absent, background: .textured)),
            ("photo black rectangle and white clock", try makeHeader(shape: .rectangle, background: .photographic)),
            ("photo content circle and white clock", try makeHeader(shape: .circle, background: .photographic)),
            ("photo capsule without recording ring", try makeHeader(background: .photographic)),
            ("textured capsule without recording ring", try makeHeader(background: .textured)),
            ("unbounded near-black photographic shadow", try makeHeader(shape: .splitRecording, background: .unboundedShadow)),
            ("photo spur connected to red-marked recording bubble", uncertainBubble),
            ("photo recording indicators without clock", try makeHeader(clockTop: nil, shape: .splitRecording, background: .photographic)),
            ("photo recording indicators with low clock", try makeHeader(clockTop: 510, shape: .splitRecording, background: .photographic))
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
        require(image.width >= 200 && image.height > image.width * 3 / 2,
                "Expected an authorized native portrait result, got \(image.width)×\(image.height)")
        let scale = CGFloat(image.width) / 1206
        let bottom = CaptureStatusBarDetector.bottom(in: image, maximumBottom: floor(CGFloat(image.height) * 0.075))
        require(bottom != nil && bottom! >= 130 * scale && bottom! <= 200 * scale,
                "Authorized result must remove the complete island before the Weixin title: \(String(describing: bottom))")
        // Match the capture writer's JPEG quality without creating a private file.
        guard let captureJPEG = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let destination = CGImageDestinationCreateWithData(captureJPEG, "public.jpeg" as CFString, 1, nil) else {
            throw CheckError.image
        }
        CGImageDestinationAddImage(destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        require(CGImageDestinationFinalize(destination), "Private in-memory capture-quality JPEG encoding succeeds")
        guard let captureSource = CGImageSourceCreateWithData(captureJPEG, nil),
              let captureImage = CGImageSourceCreateImageAtIndex(captureSource, 0, nil) else { throw CheckError.image }
        require(captureImage.width == image.width && captureImage.height == image.height,
                "In-memory JPEG 0.9 preserves the private native dimensions")
        let captureBottom = CaptureStatusBarDetector.bottom(in: captureImage,
            maximumBottom: floor(CGFloat(captureImage.height) * 0.075))
        require(captureBottom != nil && captureBottom! >= 130 * scale && captureBottom! <= 200 * scale
                && abs(captureBottom! - bottom!) <= 6,
                "Capture-quality JPEG must preserve the complete private status boundary within six native pixels: \(String(describing: captureBottom))")
        require(try Data(contentsOf: url) == original, "Private image bytes remain unchanged")
        print("Private fixture inspected in place: \(image.width)×\(image.height); detected bottom=\(bottom!), in-memory JPEG 0.9 bottom=\(captureBottom!); no image saved or emitted.")
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
        checkCleanStatusHeader(source: source, output: kept, label: "Plain compact ON")
        require(nativePixelError(source, rect: CGRect(x: 0, y: 178, width: source.width, height: 360),
                                 kept, rect: CGRect(x: 0, y: 178, width: source.width, height: 360)) < 5,
                "Clean ON retains native navigation/title/body pixels below the proved band")
        let legacy = try stitch(frames, "legacy-positive", ratio: 0.075)
        require(try kept.height - readImage(legacy.outputURLs[0]).height == Int(floor(CGFloat(source.height) * 0.075)),
                "Previously recorded positive crop ratios keep their old meaning")
        let legacyOn = try stitch(frames, "legacy-positive-on", keep: true, ratio: 0.075)
        let legacyKept = try readImage(legacyOn.outputURLs[0])
        require(legacyKept.height == kept.height, "Legacy ON preserves the complete native status row")
        checkCleanStatusHeader(source: source, output: legacyKept, label: "Legacy positive-ratio ON")
        let unknownOff = try stitch(noStatus, "unknown-off")
        let unknownOn = try stitch(noStatus, "unknown-on", keep: true)
        require(try Data(contentsOf: unknownOff.outputURLs[0]) == Data(contentsOf: unknownOn.outputURLs[0]),
                "Absent captured status evidence preserves all header pixels")
        let reverse = try stitch(Array(frames.reversed()), "reverse")
        require(try Data(contentsOf: off.outputURLs[0]) == Data(contentsOf: reverse.outputURLs[0]),
                "Reverse recording detects the actual selected upper source")
        let reverseOn = try stitch(Array(frames.reversed()), "reverse-on", keep: true)
        require(try Data(contentsOf: on.outputURLs[0]) == Data(contentsOf: reverseOn.outputURLs[0]),
                "Clean ON uses the same actual upper prefix in forward and reverse recordings")
        for (url, data) in originals {
            try FramePreparationCache.store(FrameStitcher().prepareFrame(at: url, encodedData: data), for: url)
        }
        let cached = try stitch(frames, "cached", cached: true)
        require(cached.preparedFrameCount == frames.count, "Existing prepared payloads are reused")
        require(try Data(contentsOf: off.outputURLs[0]) == Data(contentsOf: cached.outputURLs[0]),
                "Prepared and original analysis paths produce byte-identical JPEG outputs")
        let cachedOn = try stitch(frames, "cached-on", keep: true, cached: true)
        require(cachedOn.preparedFrameCount == frames.count, "Clean ON reuses all prepared analysis payloads")
        require(try Data(contentsOf: on.outputURLs[0]) == Data(contentsOf: cachedOn.outputURLs[0]),
                "Clean ON has identical native output with cached and uncached analysis")
        let pages = frames + [frames[0]]
        let pageOff = try stitch(pages, "page-off", boundaries: [0, frames.count])
        let pageOn = try stitch(pages, "page-on", keep: true, boundaries: [0, frames.count])
        require(try readImage(pageOn.outputURLs[0]).height - readImage(pageOff.outputURLs[0]).height == 2 * cut,
                "Each explicit page removes its own status bar, including a static page")
        let pageKept = try readImage(pageOn.outputURLs[0])
        checkCleanStatusHeader(source: source, output: pageKept, label: "First explicit page ON")
        checkCleanStatusHeader(source: source, output: pageKept,
            outputY: kept.height + max(8, Int(floor(CGFloat(source.width) * 0.018))), label: "Static second page ON")
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
            checkCleanStatusHeader(source: raw, output: a, label: "Native geometry \(index) ON")
        }
        try checkPatternedIntegration(in: root.appendingPathComponent("patterned"))
        try checkCleanerNegatives(in: root.appendingPathComponent("cleaner-negatives"))
        try checkTransientOpeningIntegration(in: root.appendingPathComponent("transient-opening"))
        try checkPrefixPaginationIntegration(in: root.appendingPathComponent("prefix-pagination"))
        try checkHorizontalIntegration(in: root.appendingPathComponent("horizontal"))
        for (url, data) in originals {
            require(try Data(contentsOf: url) == data, "Every original JPEG remains byte-for-byte unchanged")
        }
        print("Status-bar UIKit integration passed (\(checks) assertions): unchanged OFF cropping, clean ON island/bubble removal, native clock/battery/title/body pixels, conservative negatives, legacy ratio, reverse, cache, explicit/static pages and geometry groups. Generated fixtures: \(root.path)")
    }

    private static func checkPatternedIntegration(in root: URL) throws {
        for background in [HeaderBackground.plain, .textured, .photographic] {
            let directory = root.appendingPathComponent(String(describing: background))
            let frames = try makeScrollFrames(in: directory.appendingPathComponent("frames"), status: true,
                count: 2, background: background, indicator: .splitRecording, jpegQuality: 0.9)
            let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
            let source = try readImage(frames[0])
            let detected = CaptureStatusBarDetector.bottom(in: source, maximumBottom: 196)
            require(detected != nil && detected! >= 164 && detected! < 178,
                    "JPEG \(background) source proves the complete split recording band")
            let cut = Int(detected!)
            let repaired = CaptureStatusBarCleaner.repairedHeader(in: source, maximumBottom: 196)
            require(repaired != nil, "\(background) split-recording header must produce a native cleaner patch")
            let patch = repaired!
            require(patch.width == source.width && patch.height <= 196 && patch.height >= 164,
                    "The cleaner returns a native top patch through the complete bubble, not a resized full image")
            checkCleanStatusHeader(source: source, output: patch, split: true, label: "\(background) native cleaner patch")
            let off = try FrameStitcher(options: CaptureOptions(keepsStatusBar: false)).stitch(
                frameURLs: frames, sessionURL: directory.appendingPathComponent("off"), topCropRatio: 0)
            let on = try FrameStitcher(options: CaptureOptions(keepsStatusBar: true)).stitch(
                frameURLs: frames, sessionURL: directory.appendingPathComponent("on"), topCropRatio: 0)
            require(off.outputURLs.count == 1 && on.outputURLs.count == 1,
                    "A patterned scrolling page produces one complete native result")
            let cropped = try readImage(off.outputURLs[0]), kept = try readImage(on.outputURLs[0])
            require(cropped.width == source.width && kept.width == source.width
                    && kept.height == source.height + 137 && kept.height - cropped.height == cut,
                    "Patterned OFF/ON retain every native body row and differ by only the proved band")
            require(nativePixelError(source, rect: CGRect(x: 0, y: cut, width: source.width, height: 360),
                                     cropped, rect: CGRect(x: 0, y: 0, width: source.width, height: 360)) < 5,
                    "Patterned OFF retains exact native navigation, title and first body pixels below the entire band")
            checkCleanStatusHeader(source: source, output: kept, split: true, label: "\(background) split-recording ON")
            require(nativePixelError(source, rect: CGRect(x: 0, y: 178, width: source.width, height: 360),
                                     kept, rect: CGRect(x: 0, y: 178, width: source.width, height: 360)) < 5,
                    "Patterned clean ON preserves native navigation/title/body below the entire island and bubble")
            let last = try readImage(frames[1])
            require(nativePixelError(last, rect: CGRect(x: 0, y: 440, width: last.width, height: 96),
                                     cropped, rect: CGRect(x: 0, y: 440 + 137 - cut, width: last.width, height: 96)) < 5,
                    "Patterned OFF retains newly observed scrolling body pixels at their native coordinates")
            for (url, bytes) in originals {
                require(try Data(contentsOf: url) == bytes, "Patterned source JPEG bytes remain unchanged")
            }
        }
    }

    private static func checkCleanerNegatives(in root: URL) throws {
        for (name, shape) in [("photo-clock-without-island", Shape.absent),
                               ("photo-content-rectangle", .rectangle),
                               ("photo-content-circle", .circle)] {
            let directory = root.appendingPathComponent(name)
            let frames = try makeScrollFrames(in: directory.appendingPathComponent("frames"), status: true,
                count: 2, background: .photographic, indicator: shape, jpegQuality: 0.9)
            let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
            let source = try readImage(frames[0])
            require(CaptureStatusBarCleaner.repairedHeader(in: source, maximumBottom: 196) == nil,
                    "The cleaner must decline unproved photographic content: \(name)")
            let off = try FrameStitcher(options: CaptureOptions(keepsStatusBar: false)).stitch(
                frameURLs: frames, sessionURL: directory.appendingPathComponent("off"), topCropRatio: 0)
            let on = try FrameStitcher(options: CaptureOptions(keepsStatusBar: true)).stitch(
                frameURLs: frames, sessionURL: directory.appendingPathComponent("on"), topCropRatio: 0)
            require(off.outputURLs.count == 1 && on.outputURLs.count == 1,
                    "Unproved photographic content still produces its complete scrolling page")
            require(try Data(contentsOf: off.outputURLs[0]) == Data(contentsOf: on.outputURLs[0]),
                    "Clean ON must not alter arbitrary photographic content or status sides: \(name)")
            for (url, bytes) in originals {
                require(try Data(contentsOf: url) == bytes, "Negative fixture source JPEG bytes remain unchanged")
            }
        }
        for (name, image) in [
            ("missing clock", try makeHeader(clockTop: nil, shape: .splitRecording, background: .photographic)),
            ("unbounded recording bubble", try makeHeader(shape: .spurredRecordingBubble, background: .photographic)),
            ("photo island without recording evidence", try makeHeader(background: .photographic))
        ] {
            require(CaptureStatusBarCleaner.repairedHeader(in: image, maximumBottom: 196) == nil,
                    "A cleaner patch needs the same conservative clock/island evidence: \(name)")
        }
    }

    private static func checkPrefixPaginationIntegration(in root: URL) throws {
        let frames = try makeScrollFrames(in: root.appendingPathComponent("frames"), status: true,
            count: 2, background: .photographic, indicator: .splitRecording, jpegQuality: 0.9)
        let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
        let source = try readImage(frames[0])
        let firstPageHeight = source.height + 137
        let separator = max(8, Int(floor(CGFloat(source.width) * 0.018)))
        let secondStart = firstPageHeight + separator
        let firstFragmentHeight = 70, prefixHeight = 196
        let pageLimit = secondStart + firstFragmentHeight
        let result = try FrameStitcher(usePreparedFrames: false,
            options: CaptureOptions(keepsStatusBar: true), testPageLimit: CGFloat(pageLimit)).stitch(
                frameURLs: frames + [frames[0]], sessionURL: root.appendingPathComponent("on"),
                topCropRatio: 0, segmentStarts: [0, frames.count])
        require(result.outputURLs.count == 2, "The second explicit status prefix crosses a real output-page boundary")
        let first = try readImage(result.outputURLs[0]), second = try readImage(result.outputURLs[1])
        require(first.height == pageLimit && first.width == source.width && second.width == source.width
                && first.height + second.height == secondStart + source.height,
                "Prefix pagination retains all native rows, including the explicit static page and separator")
        let leading = nativePixels(first, rect: CGRect(x: 0, y: secondStart,
            width: source.width, height: firstFragmentHeight))
        let trailing = nativePixels(second, rect: CGRect(x: 0, y: 0,
            width: source.width, height: prefixHeight - firstFragmentHeight))
        require(leading.count == source.width * firstFragmentHeight * 4
                && trailing.count == source.width * (prefixHeight - firstFragmentHeight) * 4,
                "Both native header fragments are present after splitting inside the clock/island band")
        // Reassemble only the196px prefix, never the complete long outputs.
        guard let provider = CGDataProvider(data: Data(leading + trailing) as CFData),
              let header = CGImage(width: source.width, height: prefixHeight,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: source.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw CheckError.image
        }
        checkCleanStatusHeader(source: source, output: header, split: true,
            label: "Paginated static-page prefix across70px break")
        let navigation = CGRect(x: 0, y: 178, width: source.width, height: 18)
        require(nativePixelError(source, rect: navigation, header, rect: navigation) < 5,
                "The second prefix fragment preserves native navigation rows below the entire repaired island and circle")
        for (url, bytes) in originals {
            require(try Data(contentsOf: url) == bytes, "Prefix-pagination source JPEG bytes remain unchanged")
        }
    }

    private static func checkTransientOpeningIntegration(in root: URL) throws {
        for scenario in ["same-viewport", "one-pixel-body-change", "different-position"] {
            let directory = root.appendingPathComponent(scenario)
            // Longer sequences need two agreeing moving edges; a duplicate
            // opening plus just one scroll is intentionally not usable motion.
            let offsets = scenario == "different-position" ? [0, 137, 274, 411] : [0, 0, 137, 274]
            let frames = try makeScrollFrames(in: directory.appendingPathComponent("frames"), status: true,
                count: offsets.count, jpegQuality: 0.9, scrollOffsets: offsets, transientOpening: true,
                changedOpeningCandidatePixel: scenario == "one-pixel-body-change")
            func stitch(keep: Bool) throws -> StitchResult {
                do {
                    return try FrameStitcher(options: CaptureOptions(keepsStatusBar: keep)).stitch(
                        frameURLs: frames, sessionURL: directory.appendingPathComponent(keep ? "on" : "off"), topCropRatio: 0)
                } catch {
                    FileHandle.standardError.write(Data("Transient-opening fixture failed: \(scenario), keep=\(keep), root=\(directory.path), error=\(error)\n".utf8))
                    throw error
                }
            }
            let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
            let opening = try readImage(frames[0]), stable = try readImage(frames[1])
            let bodyBottom = opening.height - Int(ceil(CGFloat(opening.height) * 0.19))
            let body = CGRect(x: 0, y: 304, width: opening.width, height: bodyBottom - 304)
            let sameBody = nativePixels(opening, rect: body) == nativePixels(stable, rect: body)
            require(sameBody == (scenario == "same-viewport"),
                    "Transient fixtures share exact native JPEG body pixels only for the genuine duplicate viewport: \(scenario)")
            require(CaptureStatusBarDetector.bottom(in: opening, maximumBottom: 196) == nil,
                    "The 190-pixel-high opening overlay cannot prove a normal compact status bar")
            require(CaptureStatusBarDetector.bottom(in: stable, maximumBottom: 196) != nil,
                    "The later candidate contains a genuine compact status bar")
            let on = try stitch(keep: true)
            require(on.outputURLs.count == 1, "Transient opening selection keeps one complete native result")
            let kept = try readImage(on.outputURLs[0])
            require(kept.width == opening.width && kept.height == opening.height + offsets.last!,
                    "Transient selection retains every observed native body row: \(scenario)")
            let overlayROI = CGRect(x: 400, y: 24, width: 420, height: 220)
            if scenario == "same-viewport" {
                checkCleanStatusHeader(source: stable, output: kept, capsuleOffset: 2,
                    label: "Settled duplicate opening ON")
                require(nativePixelError(stable, rect: CGRect(x: 0, y: 178, width: stable.width, height: 126),
                                         kept, rect: CGRect(x: 0, y: 178, width: stable.width, height: 126)) < 5,
                        "ON replaces the complete opening coverage, including the transient tail at rows196...222")
                let tail = CGRect(x: 0, y: 196, width: stable.width, height: 27)
                require(nativePixelError(stable, rect: tail, kept, rect: tail) < 5,
                        "The exact transient tail rows come from the settled viewport, not the original expanded overlay")
                require(nativePixelError(stable, rect: body, kept, rect: body) < 5,
                        "ON retains the complete first native body viewport when choosing its equivalent settled frame")
                let off = try stitch(keep: false)
                let cropped = try readImage(off.outputURLs[0])
                require(cropped.width == kept.width && cropped.height == kept.height,
                        "OFF retains its original no-proved-boundary dimensions for the transient prefix")
                require(nativePixelError(opening, rect: CGRect(x: 0, y: 0, width: opening.width, height: 304),
                                         cropped, rect: CGRect(x: 0, y: 0, width: opening.width, height: 304)) < 5,
                        "OFF keeps the original transient opening and tail; ON-only selection cannot change it")
                require(nativePixelError(opening, rect: overlayROI, cropped, rect: overlayROI) < 5,
                        "OFF preserves the original expanded overlay itself at native resolution")
            } else {
                require(nativePixelError(opening, rect: CGRect(x: 0, y: 0, width: opening.width, height: 304),
                                         kept, rect: CGRect(x: 0, y: 0, width: opening.width, height: 304)) < 5,
                        "A changed body or different scroll position cannot replace the authentic opening: \(scenario)")
                require(nativePixelError(opening, rect: overlayROI, kept, rect: overlayROI) < 5,
                        "The expanded overlay cannot be replaced by a nonidentical candidate: \(scenario)")
            }
            for (url, bytes) in originals {
                require(try Data(contentsOf: url) == bytes, "Transient source JPEG bytes remain unchanged")
            }
        }
    }

    private static func checkCleanStatusHeader(source: CGImage, output: CGImage, outputY: Int = 0,
                                              split: Bool = false, capsuleOffset: CGFloat = 0, label: String) {
        let scale = CGFloat(source.width) / 1206
        func scaled(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX * scale, y: rect.minY * scale,
                width: rect.width * scale, height: rect.height * scale).integral
        }
        for (name, rect) in [("clock", CGRect(x: 65, y: 60, width: 210, height: 90)),
                              ("battery/network", CGRect(x: 990, y: 60, width: 175, height: 90))] {
            let roi = scaled(rect)
            require(nativePixelError(source, rect: roi, output,
                rect: roi.offsetBy(dx: 0, dy: CGFloat(outputY))) < 5,
                "\(label) preserves the actual captured \(name) at native resolution")
        }
        let main = CGRect(x: CGFloat(source.width) / 2 - 176 * scale,
            y: (42 + capsuleOffset) * scale, width: 352 * scale, height: 108 * scale).integral
        var regions = [("main island", main)]
        if split {
            regions.append(("detached recording circle", CGRect(x: CGFloat(source.width) / 2 + 200 * scale,
                y: (56 + capsuleOffset) * scale, width: 108 * scale, height: 108 * scale).integral))
        }
        for (name, roi) in regions {
            let original = statusArtifactFractions(source, rect: roi)
            let cleaned = statusArtifactFractions(output, rect: roi.offsetBy(dx: 0, dy: CGFloat(outputY)))
            require(original.dark > 0.5, "\(label) source contains a real near-black \(name), so removal cannot pass vacuously")
            if split { require(original.red > 0.01, "\(label) source contains the \(name) recording mark") }
            require(cleaned.dark < 0.001 && cleaned.red < 0.002,
                    "\(label) removes the whole \(name), including its recording mark: dark=\(cleaned.dark), red=\(cleaned.red)")
        }
    }

    private static func statusArtifactFractions(_ image: CGImage, rect: CGRect) -> (dark: Double, red: Double) {
        let bytes = nativePixels(image, rect: rect)
        guard !bytes.isEmpty else { return (.infinity, .infinity) }
        var dark = 0, red = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let r = Int(bytes[index]), g = Int(bytes[index + 1]), b = Int(bytes[index + 2])
            if max(r, g, b) < 28 { dark += 1 }
            if r > 70 && Double(r) > Double(g) * 1.6 && Double(r) > Double(b) * 1.5 { red += 1 }
        }
        let count = Double(bytes.count / 4)
        return (Double(dark) / count, Double(red) / count)
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
        checkCleanStatusHeader(source: source, output: kept, label: "Horizontal compact ON")
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
        checkCleanStatusHeader(source: source, output: try readImage(animatedOn.outputURLs[0]),
            label: "Horizontal moving-indicator ON")
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
        let variedKept = try readImage(variedOn.outputURLs[0])
        require(try readImage(variedOff.outputURLs[0]).height == source.height && variedKept.height == source.height,
                "Different proved status extents preserve native row counts instead of bisecting a capsule")
        checkCleanStatusHeader(source: source, output: variedKept, label: "Horizontal unequal-status ON")
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
            checkCleanStatusHeader(source: raw, output: try readImage(geoOn.outputURLs[index]),
                label: "Horizontal geometry \(index) ON")
        }
        for (url, data) in originals {
            require(try Data(contentsOf: url) == data, "Horizontal source JPEGs remain byte-identical")
        }
    }

    private static func makeScrollFrames(in directory: URL, status: Bool, width: Int = 1206,
                                         height: Int = 2622, count: Int = 6, axis: CaptureAxis = .vertical,
                                         headerOffset: Int = 0, headerMovement: Int = 0, earlyMovingRow: Bool = false,
                                         background: HeaderBackground = .plain, indicator: Shape = .capsule,
                                         jpegQuality: CGFloat = 0.94, scrollOffsets: [Int]? = nil,
                                         transientOpening: Bool = false, changedOpeningCandidatePixel: Bool = false) throws -> [URL] {
        precondition(scrollOffsets == nil || scrollOffsets?.count == count)
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
            let scrollOffset = scrollOffsets?[index] ?? index * 137
            let header = try makeHeader(width: width, height: height,
                clockTop: status ? CGFloat(72 + temporalOffset) * scale : nil,
                capsuleTop: CGFloat(42 + temporalOffset) * scale,
                shape: status ? indicator : .absent, scale: scale, background: background)
            let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
                UIImage(cgImage: header).draw(at: .zero)
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: top, width: CGFloat(width), height: bottom - top))
                world.draw(at: CGPoint(x: axis == .horizontal ? -CGFloat(scrollOffset) : 0,
                                       y: top - (axis == .vertical ? CGFloat(scrollOffset) : 0)))
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
                if changedOpeningCandidatePixel && index == 1 {
                    // Mutate one raw pixel before the only JPEG encoding. No
                    // decode/re-encode pass can accidentally change the rest.
                    UIColor.magenta.setFill()
                    context.fill(CGRect(x: 600, y: 440, width: 1, height: 1))
                }
                if transientOpening && index == 0 {
                    // This unfinished system animation crosses the196px prefix
                    // boundary. A prefix-only replacement leaves a black tail.
                    let rect = CGRect(x: CGFloat(width) / 2 - 176 * scale, y: 32 * scale,
                        width: 352 * scale, height: 190 * scale)
                    context.cgContext.setFillColor(UIColor.black.cgColor)
                    context.cgContext.addPath(CGPath(roundedRect: rect, cornerWidth: 95 * scale,
                        cornerHeight: 95 * scale, transform: nil))
                    context.cgContext.fillPath()
                    let ring = CGRect(x: rect.maxX - 74 * scale, y: 66 * scale,
                        width: 40 * scale, height: 40 * scale)
                    context.cgContext.setFillColor(UIColor.red.cgColor)
                    context.cgContext.fillEllipse(in: ring)
                    context.cgContext.setFillColor(UIColor.black.cgColor)
                    context.cgContext.fillEllipse(in: ring.insetBy(dx: 11 * scale, dy: 11 * scale))
                }
            }
            let url = CaptureStorage.frameURL(index: index, sessionURL: directory)
            guard let data = image.jpegData(compressionQuality: jpegQuality) else { throw CheckError.image }
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

    /// No resizing: a missing row or a shifted title must remain visible to the oracle.
    private static func nativePixelError(_ first: CGImage, rect a: CGRect, _ second: CGImage, rect b: CGRect) -> Double {
        guard a.width == b.width, a.height == b.height, a.width > 0, a.height > 0 else { return .infinity }
        let left = nativePixels(first, rect: a), right = nativePixels(second, rect: b)
        guard left.count == right.count, !left.isEmpty else { return .infinity }
        var error = 0.0
        for index in left.indices where index % 4 != 3 {
            error += Double(abs(Int(left[index]) - Int(right[index])))
        }
        return error / Double(left.count / 4 * 3)
    }

#endif

    private static func nativePixels(_ image: CGImage, rect: CGRect) -> [UInt8] {
        guard let crop = image.cropping(to: rect), crop.width == Int(rect.width),
              crop.height == Int(rect.height), crop.width > 0, crop.height > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return true
        }
        return rendered ? bytes : []
    }
}

private enum CheckError: Error { case image }
