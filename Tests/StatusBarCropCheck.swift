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
        try checkClocklessRecordingDetector()
        if let flag = CommandLine.arguments.firstIndex(of: "--fixture") {
            require(flag + 1 < CommandLine.arguments.count, "--fixture needs a local image path")
            try checkPrivateFixture(URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
        }
        print("Status bar native checks passed (\(checks) assertions): real Vision, compact/split recording indicators, patterned/tall captures and conservative negatives.")
    }

    private static func require(_ value: Bool, _ message: String, line: UInt = #line) {
        checks += 1
        if !value { fatalError("\(message) (line \(line))") }
    }

    private enum Shape { case capsule, recordingCapsule, splitRecording, spurredRecordingBubble, rectangle, circle, absent }
    private enum HeaderBackground { case plain, textured, photographic, dimPhotographic, unboundedShadow }
    private enum FullScreenPair { case recording, joinedRecording, unmarked, unmarkedCircle, bareRedDot, uncertainCircleEdge, inContent, foregroundGlyph, thinDivider }

    /// All coordinates are native pixels measured from the top-left.
    private static func makeHeader(width: Int = 1206, height: Int = 2622,
                                   clockTop: CGFloat? = 72, capsuleTop: CGFloat = 42,
                                   shape: Shape = .capsule,
                                   dark: Bool = false, scale: CGFloat = 1,
                                   background: HeaderBackground = .plain,
                                   fullScreenPair: FullScreenPair? = nil,
                                   statusContrast: CGFloat = 1) throws -> CGImage {
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
        if let fullScreenPair {
            drawFullScreenPair(fullScreenPair, top: capsuleTop, width: width, scale: scale, in: context)
        } else if shape != .absent {
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
            let statusColor = CGColor(gray: dark || background != .plain ? statusContrast : 1 - statusContrast, alpha: 1)
            drawText("09:41", at: CGPoint(x: 78 * scale, y: clockTop), size: 52 * scale,
                     color: statusColor, in: context)
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

    /// Synthetic full-screen layout with no clock or network/battery glyphs.
    /// The recording capsule is offset left to make room for its aligned circle.
    private static func drawFullScreenPair(_ variant: FullScreenPair, top: CGFloat, width: Int,
                                           scale: CGFloat, in context: CGContext) {
        let y = variant == .inContent ? top + 210 * scale : top
        let main = CGRect(x: CGFloat(width) / 2 - 282 * scale, y: y,
            width: 470 * scale, height: 108 * scale)
        let circle = CGRect(x: main.maxX + 20 * scale, y: y,
            width: 116 * scale, height: 108 * scale)
        let black = CGColor(gray: 0, alpha: 1)
        let red = CGColor(red: 0.98, green: 0.13, blue: 0.19, alpha: 1)
        context.setFillColor(black)
        context.addPath(CGPath(roundedRect: main, cornerWidth: 54 * scale,
            cornerHeight: 54 * scale, transform: nil))
        context.fillPath()
        if variant != .bareRedDot { context.fillEllipse(in: circle) }
        if variant == .joinedRecording {
            context.fill(CGRect(x: main.maxX - 7 * scale, y: y + 42 * scale,
                width: 34 * scale, height: 24 * scale))
        }
        if variant == .uncertainCircleEdge {
            context.fill(CGRect(x: circle.midX - 20 * scale, y: y + 92 * scale,
                width: 40 * scale, height: 84 * scale))
        }
        guard variant != .unmarked else { return }
        let mainMark = CGRect(x: main.minX + 25 * scale, y: y + 30 * scale,
            width: 46 * scale, height: 46 * scale)
        context.setFillColor(CGColor(red: 0.62, green: 0.24, blue: 0.18, alpha: 1))
        context.fillEllipse(in: mainMark)
        context.setFillColor(black)
        // Leave a dark center after JPEG compression and detector downsampling.
        context.fillEllipse(in: mainMark.insetBy(dx: 8 * scale, dy: 8 * scale))
        guard variant != .unmarkedCircle else { return }
        let circleMark = CGRect(x: circle.midX - 26 * scale, y: circle.midY - 26 * scale,
            width: 52 * scale, height: 52 * scale)
        if variant != .bareRedDot {
            context.setFillColor(red)
            context.fillEllipse(in: circleMark)
            context.setFillColor(black)
            context.fillEllipse(in: circleMark.insetBy(dx: 7 * scale, dy: 7 * scale))
        }
        context.setFillColor(red)
        context.fillEllipse(in: circleMark.insetBy(dx: 16 * scale, dy: 16 * scale))
        if variant == .foregroundGlyph {
            let glyph = CGRect(x: 1020 * scale, y: y + 56 * scale, width: 32 * scale, height: 24 * scale)
            context.setFillColor(CGColor(red: 0.1, green: 0.55, blue: 0.95, alpha: 1))
            context.addPath(CGPath(roundedRect: glyph, cornerWidth: 6 * scale, cornerHeight: 6 * scale, transform: nil))
            context.fillPath()
        }
        if variant == .thinDivider {
            context.setFillColor(CGColor(gray: 0.8, alpha: 1))
            context.fill(CGRect(x: 45 * scale, y: y + 108 * scale, width: 215 * scale, height: 1))
        }
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
                    let photograph = max(35, 140 - 98 * shadow + 9 * sin(xx / 67 + yy / 41) + grain)
                    // Match the visible photo around the expanded activity.
                    // Its shadows must leave a bounded near-black contour.
                    value = background == .dimPhotographic ? max(50, photograph * 0.72) : photograph
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

    private static func checkClocklessRecordingDetector() throws {
        for variant in [FullScreenPair.foregroundGlyph, .thinDivider] {
            let foreground = try makeHeader(clockTop: nil, fullScreenPair: variant)
            require(CaptureStatusBarDetector.capsuleBottom(in: foreground, maximumBottom: 196) != nil,
                    "Foreground content beside the recording pair leaves its geometry intact")
            require(CaptureStatusBarDetector.bottom(in: foreground, maximumBottom: 196, allowsClocklessRecording: true) == nil,
                    "An app glyph or one-pixel divider above the cut prevents clockless cropping")
        }
        for (name, variant) in [("unmarked capsule and circle", FullScreenPair.unmarked),
                                ("recording capsule beside an unmarked circle", .unmarkedCircle),
                                ("bare red dot without a detached black circle", .bareRedDot),
                                ("detached circle connected to a lower black edge", .uncertainCircleEdge),
                                ("recording-like objects in the app content", .inContent)] {
            let image = try makeHeader(clockTop: nil, fullScreenPair: variant)
            require(CaptureStatusBarDetector.bottom(in: image, maximumBottom: 196, allowsClocklessRecording: true) == nil,
                    "Clockless content needs a complete recording pair before cropping. \(name)")
        }
        for (width, height) in [(1206, 2622), (1005, 2185)] {
            let scale = CGFloat(width) / 1206
            let image = try makeHeader(width: width, height: height, clockTop: nil,
                capsuleTop: 42 * scale, scale: scale, fullScreenPair: .recording)
            let limit = floor(CGFloat(height) * 0.075)
            let bottom = CaptureStatusBarDetector.bottom(in: image, maximumBottom: limit, allowsClocklessRecording: true)
            require(bottom != nil && bottom! >= 150 * scale && bottom! <= 170 * scale,
                    "A complete recording pair proves the full status band without clock or battery at native width \(width). Bottom \(String(describing: bottom))")
            require(CaptureStatusBarDetector.bottom(in: image, maximumBottom: 146 * scale, allowsClocklessRecording: true) == nil,
                    "Clockless recording proof preserves the frame when the maximum would bisect its circles")
            require(CaptureStatusBarDetector.bottom(in: image, maximumBottom: limit) == nil,
                    "Horizontal status analysis still requires clock evidence")
        }
    }

    private static func checkPrivateFixture(_ url: URL) throws {
        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CheckError.image }
        require(image.width >= 200 && image.height > image.width * 3 / 2,
                "Expected an authorized native portrait result, got \(image.width)×\(image.height)")
        let scale = CGFloat(image.width) / 1206
        let bottom = CaptureStatusBarDetector.bottom(in: image, maximumBottom: floor(CGFloat(image.height) * 0.075),
                                                     allowsClocklessRecording: true)
        require(bottom != nil && bottom! >= 130 * scale && bottom! <= 200 * scale,
                "Authorized result must remove the complete island before app navigation: \(String(describing: bottom))")
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
            maximumBottom: floor(CGFloat(captureImage.height) * 0.075), allowsClocklessRecording: true)
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
        checkRawStatusHeader(source: source, output: kept, label: "Plain portrait ON")
        let legacy = try stitch(frames, "legacy-positive", ratio: 0.075)
        require(try kept.height - readImage(legacy.outputURLs[0]).height == Int(floor(CGFloat(source.height) * 0.075)),
                "Previously recorded positive crop ratios keep their old meaning")
        let legacyOn = try stitch(frames, "legacy-on", keep: true, ratio: 0.075)
        checkRawStatusHeader(source: source, output: try readImage(legacyOn.outputURLs[0]), label: "Legacy-ratio ON")
        let unknownOff = try stitch(noStatus, "unknown-off")
        let unknownOn = try stitch(noStatus, "unknown-on", keep: true)
        require(try Data(contentsOf: unknownOff.outputURLs[0]) == Data(contentsOf: unknownOn.outputURLs[0]),
                "Absent captured status evidence preserves all header pixels")
        let reverse = try stitch(Array(frames.reversed()), "reverse")
        require(try Data(contentsOf: off.outputURLs[0]) == Data(contentsOf: reverse.outputURLs[0]),
                "Reverse recording detects the actual selected upper source")
        let reverseOn = try stitch(Array(frames.reversed()), "reverse-on", keep: true)
        require(try Data(contentsOf: on.outputURLs[0]) == Data(contentsOf: reverseOn.outputURLs[0]),
                "Reverse ON preserves the same actual upper-source header and native body")
        for (url, data) in originals {
            try FramePreparationCache.store(FrameStitcher().prepareFrame(at: url, encodedData: data), for: url)
        }
        let cached = try stitch(frames, "cached", cached: true)
        require(cached.preparedFrameCount == frames.count, "Existing prepared payloads are reused")
        require(try Data(contentsOf: off.outputURLs[0]) == Data(contentsOf: cached.outputURLs[0]),
                "Prepared and original analysis paths produce byte-identical JPEG outputs")
        let cachedOn = try stitch(frames, "cached-on", keep: true, cached: true)
        require(try cachedOn.preparedFrameCount == frames.count
                && Data(contentsOf: on.outputURLs[0]) == Data(contentsOf: cachedOn.outputURLs[0]),
                "Prepared and original ON paths preserve identical original header pixels")
        let pages = frames + [frames[0]]
        let pageOff = try stitch(pages, "page-off", boundaries: [0, frames.count])
        let pageOn = try stitch(pages, "page-on", keep: true, boundaries: [0, frames.count])
        require(try readImage(pageOn.outputURLs[0]).height - readImage(pageOff.outputURLs[0]).height == 2 * cut,
                "Each explicit page removes its own status bar, including a static page")
        let explicitKept = try readImage(pageOn.outputURLs[0])
        checkRawStatusHeader(source: source, output: explicitKept, label: "First explicit page ON")
        checkRawStatusHeader(source: source, output: explicitKept,
            outputY: kept.height + max(8, Int(floor(CGFloat(source.width) * 0.018))), label: "Static explicit page ON")
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
            checkRawStatusHeader(source: raw, output: a, label: "Native geometry \(index) ON")
        }
        try checkPatternedIntegration(in: root.appendingPathComponent("patterned"))
        try checkClocklessRecordingIntegration(in: root.appendingPathComponent("clockless-recording"))
        try checkExpandedPhotoOpeningIntegration(in: root.appendingPathComponent("expanded-photo-opening"))
        try checkLegacyMaskedOpening(in: root.appendingPathComponent("legacy-masked-opening"))
        try checkDetachedStatusPeerIntegration(in: root.appendingPathComponent("detached-status-peer"))
        try checkCapturedHeaderIntegration(in: root.appendingPathComponent("captured-header"))
        try checkHorizontalIntegration(in: root.appendingPathComponent("horizontal"))
        for (url, data) in originals {
            require(try Data(contentsOf: url) == data, "Every original JPEG remains byte-for-byte unchanged")
        }
        print("Status-bar UIKit integration passed (\(checks) assertions): OFF boundary cropping, original ON clock/island/circle/battery pixels, captured animation, fractional geometry, patterned headers, legacy ratio, reverse, cache and explicit/static pages. Generated fixtures: \(root.path)")
    }

    private static func checkPatternedIntegration(in root: URL) throws {
        for background in [HeaderBackground.textured, .photographic] {
            let directory = root.appendingPathComponent(String(describing: background))
            let frames = try makeScrollFrames(in: directory.appendingPathComponent("frames"), status: true,
                count: 2, background: background, indicator: .splitRecording, jpegQuality: 0.9)
            let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
            let source = try readImage(frames[0])
            let detected = CaptureStatusBarDetector.bottom(in: source, maximumBottom: 196)
            require(detected != nil && detected! >= 164 && detected! < 178,
                    "JPEG \(background) source proves the complete split recording band")
            let cut = Int(detected!)
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
            require(nativePixelError(source, rect: CGRect(x: 0, y: 0, width: source.width, height: 360),
                                     kept, rect: CGRect(x: 0, y: 0, width: source.width, height: 360)) < 5,
                    "Patterned ON retains the authentic photographic status header and title at native resolution")
            checkRawStatusHeader(source: source, output: kept, split: true, label: "\(background) split-header ON")
            let last = try readImage(frames[1])
            require(nativePixelError(last, rect: CGRect(x: 0, y: 440, width: last.width, height: 96),
                                     cropped, rect: CGRect(x: 0, y: 440 + 137 - cut, width: last.width, height: 96)) < 5,
                    "Patterned OFF retains newly observed scrolling body pixels at their native coordinates")
            for (url, bytes) in originals {
                require(try Data(contentsOf: url) == bytes, "Patterned source JPEG bytes remain unchanged")
            }
        }
    }

    private static func checkClocklessRecordingIntegration(in root: URL) throws {
        let frames = try makeScrollFrames(in: root.appendingPathComponent("frames"), status: true,
            count: 2, jpegQuality: 0.9, fullScreenPair: .recording)
        let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
        let source = try readImage(frames[0])
        let detected = CaptureStatusBarDetector.bottom(in: source, maximumBottom: 196, allowsClocklessRecording: true)
        require(detected != nil && detected! >= 150 && detected! <= 170,
                "Native capture-quality JPEG proves the full recording pair without a clock or battery")
        let cut = Int(detected!)
        func stitch(keep: Bool) throws -> StitchResult {
            do {
                return try FrameStitcher(options: CaptureOptions(keepsStatusBar: keep)).stitch(
                    frameURLs: frames, sessionURL: root.appendingPathComponent(keep ? "on" : "off"), topCropRatio: 0)
            } catch {
                FileHandle.standardError.write(Data("Clockless recording fixture failed at \(root.path), keep=\(keep), error=\(error)\n".utf8))
                throw error
            }
        }
        let off = try stitch(keep: false), on = try stitch(keep: true)
        require(off.outputURLs.count == 1 && on.outputURLs.count == 1,
                "Clockless recording produces one native scrolling result in both modes")
        let cropped = try readImage(off.outputURLs[0]), kept = try readImage(on.outputURLs[0])
        require(cropped.width == source.width && kept.width == source.width
                && kept.height == source.height + 137 && kept.height - cropped.height == cut,
                "OFF removes only the proved clockless recording band and ON retains all original rows")
        require(nativePixelError(source, rect: CGRect(x: 0, y: cut, width: source.width, height: 120),
                                 cropped, rect: CGRect(x: 0, y: 0, width: source.width, height: 120)) < 5,
                "OFF retains the navigation and content immediately below the recording pair")
        for (name, roi) in [("full top band", CGRect(x: 0, y: 0, width: source.width, height: 196)),
                            ("left recording mark", CGRect(x: 340, y: 66, width: 58, height: 58)),
                            ("detached recording circle", CGRect(x: 811, y: 42, width: 116, height: 108)),
                            ("detached recording mark", CGRect(x: 840, y: 66, width: 60, height: 60))] {
            require(nativePixelError(source, rect: roi, kept, rect: roi) < 5,
                    "ON preserves the captured clockless \(name) at native resolution")
        }
        for (url, bytes) in originals {
            require(try Data(contentsOf: url) == bytes, "Clockless recording source JPEG bytes remain unchanged")
        }
    }

    private enum PhotoOpening: String {
        case sameViewport, changedNavigation, movedViewport, legacyMasked, weakerStatusPeer
        case movedFlatViewport, movedFlatChangedNavigation

        var hasFlatStatusBackground: Bool { self == .movedFlatViewport || self == .movedFlatChangedNavigation }
        var startsScrollingImmediately: Bool { self == .movedViewport || hasFlatStatusBackground }
    }

    private static func checkExpandedPhotoOpeningIntegration(in root: URL) throws {
        let leftNav = CGRect(x: 30, y: 223, width: 79, height: 52)
        let rightNav = CGRect(x: 1014, y: 223, width: 80, height: 52)
        let centralTail = CGRect(x: 372, y: 196, width: 452, height: 94)
        for scenario in [PhotoOpening.sameViewport, .changedNavigation, .movedViewport] {
            let directory = root.appendingPathComponent(scenario.rawValue)
            let offsets = scenario == .movedViewport ? [0, 137, 274, 411] : [0, 0, 137, 274]
            let frames = try makeScrollFrames(in: directory.appendingPathComponent("frames"), status: true,
                count: offsets.count, background: .dimPhotographic, indicator: .splitRecording,
                jpegQuality: 0.9, scrollOffsets: offsets, photoOpening: scenario)
            let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
            let opening = try readImage(frames[0]), peer = try readImage(frames[1])
            let overlay = CaptureOverlayDetector.expandedIslandCandidate(in: opening)
            require(overlay != nil && overlay!.maxY > 270
                    && !overlay!.intersects(leftNav) && !overlay!.intersects(rightNav),
                    "The synthetic activity has a bounded contour reaching below the exposed navigation controls")
            let bodyBottom = opening.height - Int(ceil(CGFloat(opening.height) * 0.19))
            let body = CGRect(x: 0, y: 320, width: opening.width, height: bodyBottom - 320)
            require((nativePixelError(opening, rect: body, peer, rect: body) == 0) == (scenario != .movedViewport),
                    "Only the duplicate photo viewport has identical native body pixels in \(scenario.rawValue)")
            require((nativePixelError(opening, rect: leftNav, peer, rect: leftNav) > 5) == (scenario == .changedNavigation),
                    "The changed-navigation peer has different visible left navigation")
            require(nativePixelError(opening, rect: rightNav, peer, rect: rightNav) < 2,
                    "The right navigation remains visibly outside the expanded activity")
            require(nativePixelError(opening, rect: centralTail, peer, rect: centralTail) > 25,
                    "The expanded activity hides actual photo pixels below the usual matching boundary")

            func stitch(_ input: [URL], _ name: String, keep: Bool = false) throws -> StitchResult {
                try FrameStitcher(options: CaptureOptions(keepsStatusBar: keep)).stitch(
                    frameURLs: input, sessionURL: directory.appendingPathComponent(name), topCropRatio: 0)
            }
            if scenario == .sameViewport {
                do {
                    let detected = CaptureStatusBarDetector.bottom(in: peer, maximumBottom: 196)
                    require(detected != nil && detected! < leftNav.minY,
                            "The compact peer proves a status boundary above the photo navigation")
                    let cut = Int(detected!)
                    let baseline = try stitch(Array(frames.dropFirst()), "settled-off")
                    let off = try stitch(frames, "off")
                    let on = try stitch(frames, "on", keep: true)
                    require(off.outputURLs.count == 1 && on.outputURLs.count == 1 && baseline.outputURLs.count == 1,
                            "Both export modes recover one complete photo page")
                    let cropped = try readImage(off.outputURLs[0]), kept = try readImage(on.outputURLs[0])
                    let settled = try readImage(baseline.outputURLs[0])
                    require(cropped.width == opening.width && kept.width == opening.width
                            && kept.height == opening.height + 274 && kept.height - cropped.height == cut
                            && cropped.height == settled.height,
                            "OFF removes exactly the settled status band and retains all observed body rows")
                    let expected = CGRect(x: 0, y: 0, width: cropped.width, height: bodyBottom - cut)
                    require(nativePixelError(settled, rect: expected, cropped, rect: expected) < 1,
                            "The recovered opening matches the status-free export from the settled peer")
                    for (name, roi) in [("left navigation", leftNav), ("right navigation", rightNav),
                                        ("central photo below the matching boundary", centralTail)] {
                        require(nativePixelError(peer, rect: roi, cropped, rect: roi.offsetBy(dx: 0, dy: -CGFloat(cut))) < 5,
                                "OFF preserves the settled native \(name)")
                    }
                    let expanded = CGRect(x: 182, y: 39, width: 796, height: 251)
                    for (name, roi) in [("expanded island", expanded), ("left navigation", leftNav), ("right navigation", rightNav)] {
                        require(nativePixelError(opening, rect: roi, kept, rect: roi) < 5,
                                "ON retains the captured \(name) at its original position")
                    }
                } catch {
                    FileHandle.standardError.write(Data("Expanded photo opening fixture failed at \(directory.path). \(error)\n".utf8))
                    throw error
                }
            } else {
                do {
                    _ = try stitch(frames, "off")
                    fatalError("OFF accepted an unverified expanded photo opening in \(scenario.rawValue)")
                } catch StitchError.occludedOpening {
                    require(true, "OFF reports the obscured opening without an equivalent peer")
                } catch {
                    FileHandle.standardError.write(Data("Unexpected failure for expanded photo opening \(scenario.rawValue). \(error)\n".utf8))
                    throw error
                }
            }
            for (url, bytes) in originals {
                require(try Data(contentsOf: url) == bytes, "Expanded photo opening source JPEG bytes remain unchanged")
            }
        }
    }

    private static func checkLegacyMaskedOpening(in root: URL) throws {
        let frames = try makeScrollFrames(in: root.appendingPathComponent("frames"), status: true,
            count: 4, jpegQuality: 0.9, scrollOffsets: [0, 0, 137, 274], photoOpening: .legacyMasked)
        let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
        let opening = try readImage(frames[0]), peer = try readImage(frames[1])
        let legacy = CaptureOverlayDetector.inspect(opening)
        let legacyBottom = ceil(CGFloat(opening.height) * legacy.coveredTopRatio)
        let candidate = CaptureOverlayDetector.expandedIslandCandidate(in: opening)
        let detected = CaptureStatusBarDetector.bottom(in: peer, maximumBottom: 196)
        require(detected != nil && legacyBottom > detected! && legacyBottom < 196
                && (candidate?.maxY ?? 0) > 196 && !legacy.isSystemPanel,
                "Legacy mask ends inside the prefix, while the bounded activity covers the matching edge. Legacy \(legacyBottom), compact \(String(describing: detected)), expanded \(String(describing: candidate))")
        let cut = Int(detected!)
        let stitcher = FrameStitcher(options: CaptureOptions(keepsStatusBar: false))
        let baseline = try stitcher.stitch(frameURLs: Array(frames.dropFirst()),
            sessionURL: root.appendingPathComponent("baseline"), topCropRatio: 0)
        let recovered = try stitcher.stitch(frameURLs: frames,
            sessionURL: root.appendingPathComponent("recovered"), topCropRatio: 0)
        require(baseline.outputURLs.count == 1 && recovered.outputURLs.count == 1,
                "Both paths retain one complete native page")
        let expected = try readImage(baseline.outputURLs[0]), actual = try readImage(recovered.outputURLs[0])
        require(expected.height == opening.height + 274 - cut && actual.height == expected.height,
                "Recovery before legacy prefix gating retains every row below the compact cut")
        let witness = CGRect(x: 34, y: 174, width: 72, height: 18)
        require(nativePixelError(peer, rect: witness, actual,
                rect: witness.offsetBy(dx: 0, dy: -CGFloat(cut))) < 5,
                "Recovery retains exposed app pixels between the compact cut and the matching edge")
        for (url, bytes) in originals {
            require(try Data(contentsOf: url) == bytes, "Legacy masked opening source JPEG bytes remain unchanged")
        }
    }

    private static func checkDetachedStatusPeerIntegration(in root: URL) throws {
        let bridge = CGRect(x: 793, y: 89, width: 16, height: 16)
        let leftNav = CGRect(x: 30, y: 223, width: 79, height: 52)
        for scenario in [PhotoOpening.sameViewport, .changedNavigation, .movedViewport, .weakerStatusPeer,
                         .movedFlatViewport, .movedFlatChangedNavigation] {
            let directory = root.appendingPathComponent(scenario.rawValue)
            let offsets = scenario.startsScrollingImmediately ? [0, 137, 274, 411] : [0, 0, 137, 274]
            let frames = try makeScrollFrames(in: directory.appendingPathComponent("frames"), status: true,
                count: offsets.count, jpegQuality: 0.9, scrollOffsets: offsets,
                photoOpening: scenario, joinedStatusOpening: true)
            let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
            let opening = try readImage(frames[0]), peer = try readImage(frames[1])
            guard let openingStatus = CaptureStatusBarDetector.presentation(in: opening, maximumBottom: 196),
                  let peerStatus = CaptureStatusBarDetector.presentation(in: peer, maximumBottom: 196) else {
                preconditionFailure("Both compact status presentations must qualify in \(scenario.rawValue)")
            }
            require(!openingStatus.hasDetachedRecordingBubble && peerStatus.hasDetachedRecordingBubble,
                    "The recording circle is detached only in the candidate")
            let weaker = scenario == .weakerStatusPeer ? peerStatus : openingStatus
            let stronger = scenario == .weakerStatusPeer ? openingStatus : peerStatus
            require(weaker.clockDetail > 0 && weaker.rightDetail > 0
                    && weaker.clockDetail < stronger.clockDetail * 0.85
                    && weaker.rightDetail < stronger.rightDetail * 0.85,
                    "The synthetic clock and right indicators have different visible detail in \(scenario.rawValue)")
            let body = CGRect(x: 0, y: 320, width: opening.width, height: 512)
            require(nativePixelError(opening, rect: bridge, peer, rect: bridge) > 150,
                    "The actual opening joins the recording shapes and the peer has a clear gap")
            require((nativePixelError(opening, rect: body, peer, rect: body) == 0) == !scenario.startsScrollingImmediately,
                    "The compact peer has matching captured body pixels only at the duplicate viewport")
            let changesNavigation = scenario == .changedNavigation || scenario == .movedFlatChangedNavigation
            require((nativePixelError(opening, rect: leftNav, peer, rect: leftNav) > 5) == changesNavigation,
                    "The changed-navigation peer differs below the status band")

            let on = try FrameStitcher(options: CaptureOptions(keepsStatusBar: true)).stitch(
                frameURLs: frames, sessionURL: directory.appendingPathComponent("on"), topCropRatio: 0)
            require(on.outputURLs.count == 1, "Compact status selection retains one complete native page")
            let kept = try readImage(on.outputURLs[0])
            require(kept.width == opening.width && kept.height == opening.height + offsets.last!,
                    "ON retains native dimensions and every newly observed body row")
            let verifiedPeer = scenario == .sameViewport || scenario == .movedFlatViewport
            let source = verifiedPeer ? peer : opening
            for (name, roi) in [("full top band", CGRect(x: 0, y: 0, width: source.width, height: 196)),
                                ("clock", CGRect(x: 65, y: 60, width: 210, height: 90)),
                                ("battery", CGRect(x: 990, y: 60, width: 175, height: 90)),
                                ("left recording ring", CGRect(x: 340, y: 66, width: 58, height: 58)),
                                ("right recording circle", CGRect(x: 811, y: 42, width: 116, height: 112)),
                                ("bridge or gap", bridge)] {
                require(nativePixelError(source, rect: roi, kept, rect: roi) < 5,
                        "ON uses the actual captured \(name) from the \(verifiedPeer ? "detached peer" : "original opening") in \(scenario.rawValue)")
            }
            require(nativePixelError(opening, rect: leftNav, kept, rect: leftNav) < 5,
                    "ON retains the original visible application navigation")
            require(nativePixelError(opening, rect: body, kept, rect: body) < 5,
                    "ON retains the original opening body rows after any status substitution")
            if verifiedPeer {
                let cut = Int(CaptureStatusBarDetector.bottom(in: opening, maximumBottom: 196,
                    allowsClocklessRecording: true) ?? 0)
                let off = try FrameStitcher(options: CaptureOptions(keepsStatusBar: false)).stitch(
                    frameURLs: frames, sessionURL: directory.appendingPathComponent("off"), topCropRatio: 0)
                require(off.outputURLs.count == 1, "OFF retains one complete native page")
                let cropped = try readImage(off.outputURLs[0])
                require(cropped.width == opening.width && cropped.height == kept.height - cut,
                        "OFF uses the existing crop boundary of the opening frame")
                let sourceRows = CGRect(x: 0, y: cut, width: opening.width, height: 320 - cut)
                require(nativePixelError(opening, rect: sourceRows, cropped,
                        rect: sourceRows.offsetBy(dx: 0, dy: -CGFloat(cut))) < 5,
                        "ON-only compact selection does not change the source pixels retained by OFF")
            }
            for (url, bytes) in originals {
                require(try Data(contentsOf: url) == bytes, "Compact status peer source JPEG bytes remain unchanged")
            }
        }
    }

    private static func checkCapturedHeaderIntegration(in root: URL) throws {
        for (width, offset) in [(1206, CGFloat(0.25)), (1005, CGFloat(1.75))] {
            let directory = root.appendingPathComponent("fractional-\(width)")
            let frames = try makeScrollFrames(in: directory.appendingPathComponent("frames"), status: true,
                width: width, height: width == 1206 ? 2622 : 2185, count: 2, headerOffset: offset,
                background: .photographic, indicator: .splitRecording, jpegQuality: 0.9)
            let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
            let source = try readImage(frames[0])
            let result = try FrameStitcher(options: CaptureOptions(keepsStatusBar: true)).stitch(
                frameURLs: frames, sessionURL: directory.appendingPathComponent("on"), topCropRatio: 0)
            let output = try readImage(result.outputURLs[0])
            require(output.width == source.width && output.height == source.height + 137,
                    "Fractional native status geometry preserves every original body row")
            checkRawStatusHeader(source: source, output: output, split: true, islandTop: 42 + offset,
                label: "Fractional \(width)px captured ON")
            for (url, bytes) in originals {
                require(try Data(contentsOf: url) == bytes, "Fractional source JPEG bytes remain unchanged")
            }
        }

        let directory = root.appendingPathComponent("opening-animation")
        let frames = try makeScrollFrames(in: directory.appendingPathComponent("frames"), status: true,
            count: 4, jpegQuality: 0.9, scrollOffsets: [0, 0, 137, 274], transientOpening: true)
        let originals = try frames.map { ($0, try Data(contentsOf: $0)) }
        let opening = try readImage(frames[0]), later = try readImage(frames[1])
        let bodyBottom = opening.height - Int(ceil(CGFloat(opening.height) * 0.19))
        let body = CGRect(x: 0, y: 304, width: opening.width, height: bodyBottom - 304)
        require(nativePixelError(opening, rect: body, later, rect: body) == 0,
                "Captured-animation fixture offers a later compact frame with identical native body pixels")
        let result: StitchResult
        do {
            result = try FrameStitcher(options: CaptureOptions(keepsStatusBar: true)).stitch(
                frameURLs: frames, sessionURL: directory.appendingPathComponent("on"), topCropRatio: 0)
        } catch {
            FileHandle.standardError.write(Data("Captured-animation ON fixture failed at \(directory.path): \(error)\n".utf8))
            throw error
        }
        let output = try readImage(result.outputURLs[0])
        require(output.width == opening.width && output.height == opening.height + 274,
                "Original opening presentation preserves all observed native body rows")
        checkRawStatusHeader(source: opening, output: output, recording: true, islandTop: 32, islandHeight: 190,
            label: "Actual opening-animation ON")
        let tail = CGRect(x: 400, y: 196, width: 420, height: 27)
        require(nativePixelError(opening, rect: tail, output, rect: tail) < 5,
                "ON retains the original captured animation tail through222px")
        require(nativePixelError(opening, rect: body, output, rect: body) < 5,
                "Captured opening preservation leaves the entire first native body viewport intact")
        for (url, bytes) in originals {
            require(try Data(contentsOf: url) == bytes, "Captured-animation source JPEG bytes remain unchanged")
        }
    }

    private static func checkRawStatusHeader(source: CGImage, output: CGImage, outputY: Int = 0,
                                            split: Bool = false, recording: Bool = false,
                                            islandTop: CGFloat = 42, islandHeight: CGFloat = 108, label: String) {
        let scale = CGFloat(source.width) / 1206
        func scaled(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX * scale, y: rect.minY * scale,
                width: rect.width * scale, height: rect.height * scale).integral
        }
        var regions = [("complete original top band", CGRect(x: 0, y: 0,
            width: source.width, height: Int(floor(CGFloat(source.height) * 0.075)))),
            ("clock", scaled(CGRect(x: 65, y: 60, width: 210, height: 90))),
            ("battery/network", scaled(CGRect(x: 990, y: 60, width: 175, height: 90))),
            ("whole island", CGRect(x: CGFloat(source.width) / 2 - 176 * scale,
                y: islandTop * scale, width: 352 * scale, height: islandHeight * scale).integral)]
        if recording || split {
            regions.append(("island recording mark", CGRect(x: CGFloat(source.width) / 2 + 96 * scale,
                y: (islandTop + 28) * scale, width: 52 * scale, height: 52 * scale).integral))
        }
        if split {
            regions.append(("whole detached circle", CGRect(x: CGFloat(source.width) / 2 + 200 * scale,
                y: (islandTop + 14) * scale, width: 108 * scale, height: 108 * scale).integral))
            regions.append(("detached recording mark", CGRect(x: CGFloat(source.width) / 2 + 227 * scale,
                y: (islandTop + 41) * scale, width: 54 * scale, height: 54 * scale).integral))
        }
        for (name, rect) in regions {
            require(nativePixelError(source, rect: rect, output,
                rect: rect.offsetBy(dx: 0, dy: CGFloat(outputY))) < 5,
                "\(label) preserves the captured \(name) at native resolution")
        }
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
        checkRawStatusHeader(source: source, output: kept, label: "Horizontal ON")
        require(pixelError(kept, rect: CGRect(x: source.width + 20, y: 0, width: 100, height: cut),
                           kept, rect: CGRect(x: source.width + 140, y: 0, width: 100, height: cut)) < 1,
                "Horizontal ON leaves the extra wide status region uniform")
        let legacy = try stitch(frames, "legacy", ratio: 0.075)
        require(try readImage(legacy.outputURLs[0]).height == source.height - Int(floor(CGFloat(source.height) * 0.075)),
                "Horizontal legacy crop ratios retain their original meaning")
        let legacyOn = try stitch(frames, "legacy-on", keep: true, ratio: 0.075)
        checkRawStatusHeader(source: source, output: try readImage(legacyOn.outputURLs[0]),
            label: "Horizontal legacy-ratio ON")
        let animatedOff = try stitch(animated, "animated-off"), animatedOn = try stitch(animated, "animated-on", keep: true)
        require(try readImage(animatedOff.outputURLs[0]).width == source.width + 2 * 137
                && readImage(animatedOn.outputURLs[0]).height - readImage(animatedOff.outputURLs[0]).height == cut,
                "Moving compact status indicators cannot become a false column-identity layer")
        checkRawStatusHeader(source: try readImage(animated[0]), output: try readImage(animatedOn.outputURLs[0]),
            label: "Horizontal captured moving-status ON")
        let animatedReverse = try stitch(Array(animated.reversed()), "animated-reverse")
        require(try Data(contentsOf: animatedReverse.outputURLs[0]) == Data(contentsOf: animatedOff.outputURLs[0]),
                "Animated-status horizontal reverse preserves the same native output")
        let reverse = try stitch(Array(frames.reversed()), "reverse")
        require(try Data(contentsOf: reverse.outputURLs[0]) == Data(contentsOf: off.outputURLs[0]),
                "Horizontal reverse capture uses the selected original prefix")
        let reverseOn = try stitch(Array(frames.reversed()), "reverse-on", keep: true)
        require(try Data(contentsOf: reverseOn.outputURLs[0]) == Data(contentsOf: on.outputURLs[0]),
                "Horizontal reverse ON keeps the same original native status header")
        for (url, data) in originals {
            try FramePreparationCache.store(FrameStitcher(options: CaptureOptions(axis: .horizontal))
                .prepareFrame(at: url, encodedData: data), for: url)
        }
        let cached = try stitch(frames, "cached", cached: true)
        require(try cached.preparedFrameCount == frames.count && Data(contentsOf: cached.outputURLs[0]) == Data(contentsOf: off.outputURLs[0]),
                "Horizontal crop preserves cached/uncached output equivalence")
        let cachedOn = try stitch(frames, "cached-on", keep: true, cached: true)
        require(try cachedOn.preparedFrameCount == frames.count
                && Data(contentsOf: cachedOn.outputURLs[0]) == Data(contentsOf: on.outputURLs[0]),
                "Horizontal cached ON preserves identical original status and body pixels")
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
            checkRawStatusHeader(source: raw, output: try readImage(geoOn.outputURLs[index]),
                label: "Horizontal native geometry \(index) ON")
        }
        for (url, data) in originals {
            require(try Data(contentsOf: url) == data, "Horizontal source JPEGs remain byte-identical")
        }
    }

    private static func drawPhotoOpening(in context: CGContext, scale: CGFloat, expanded: Bool,
                                         changedNavigation: Bool, legacyMasked: Bool = false) {
        func rounded(_ rect: CGRect, radius: CGFloat, color: CGColor) {
            context.setFillColor(color)
            context.addPath(CGPath(roundedRect: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                width: rect.width * scale, height: rect.height * scale), cornerWidth: radius * scale,
                cornerHeight: radius * scale, transform: nil))
            context.fillPath()
        }
        if legacyMasked {
            rounded(CGRect(x: 42, y: 179, width: 56, height: 7), radius: 2,
                    color: CGColor(red: 0.04, green: 0.39, blue: 0.74, alpha: 1))
            if expanded {
                let red = CGColor(red: 0.9, green: 0.1, blue: 0.12, alpha: 1)
                rounded(CGRect(x: 247, y: 37, width: 670, height: 167), radius: 55,
                        color: CGColor(gray: 0, alpha: 1))
                rounded(CGRect(x: 480, y: 61, width: 180, height: 28), radius: 0, color: red)
                rounded(CGRect(x: 280, y: 150, width: 605, height: 16), radius: 0, color: red)
            }
            return
        }
        let white = CGColor(gray: 1, alpha: 1)
        for row in [234, 245, 256] {
            rounded(CGRect(x: 44, y: row, width: changedNavigation ? 25 : 52, height: 5), radius: 2, color: white)
        }
        rounded(CGRect(x: 1024, y: 231, width: 44, height: 36), radius: 9, color: white)
        rounded(CGRect(x: 1031, y: 238, width: 30, height: 22), radius: 4,
                color: CGColor(red: 0.30, green: 0.23, blue: 0.19, alpha: 1))
        guard expanded else { return }
        rounded(CGRect(x: 182, y: 39, width: 796, height: 251), radius: 94,
                color: CGColor(gray: 0, alpha: 1))
        rounded(CGRect(x: 280, y: 133, width: 186, height: 58), radius: 24,
                color: CGColor(gray: 0.065, alpha: 1))
        rounded(CGRect(x: 812, y: 143, width: 62, height: 52), radius: 23,
                color: CGColor(red: 0.29, green: 0.075, blue: 0.06, alpha: 1))
    }

    private static func makeScrollFrames(in directory: URL, status: Bool, width: Int = 1206,
                                         height: Int = 2622, count: Int = 6, axis: CaptureAxis = .vertical,
                                         headerOffset: CGFloat = 0, headerMovement: Int = 0, earlyMovingRow: Bool = false,
                                         background: HeaderBackground = .plain, indicator: Shape = .capsule,
                                         jpegQuality: CGFloat = 0.94, scrollOffsets: [Int]? = nil,
                                         transientOpening: Bool = false, fullScreenPair: FullScreenPair? = nil,
                                         photoOpening: PhotoOpening? = nil, joinedStatusOpening: Bool = false) throws -> [URL] {
        precondition(scrollOffsets == nil || scrollOffsets?.count == count)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let top = floor(CGFloat(height) * 0.075), bottom = CGFloat(height) - ceil(CGFloat(height) * 0.19)
        let scale = CGFloat(width) / 1206
        let bodyStart = photoOpening == nil ? top : 320 * scale
        let photoProfile = try joinedStatusOpening ? makeHeader(width: width, height: height,
            clockTop: nil, shape: .absent, scale: scale, background: .dimPhotographic) : nil
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
            let headerIndex = photoOpening?.hasFlatStatusBackground == true ? min(index, 1) : index
            let temporalOffset = headerOffset + CGFloat(headerIndex * (axis == .vertical ? 2 : headerMovement))
            let scrollOffset = scrollOffsets?[index] ?? index * 137
            let expandedPhoto = photoOpening != nil && index == 0 && !joinedStatusOpening
            let pair: FullScreenPair? = joinedStatusOpening ? (index == 0 ? .joinedRecording : .recording) : fullScreenPair
            let weakerStatus = joinedStatusOpening && index == (photoOpening == .weakerStatusPeer ? 1 : 0)
            let header = try makeHeader(width: width, height: height,
                clockTop: status && fullScreenPair == nil && !expandedPhoto ? CGFloat(72 + temporalOffset) * scale : nil,
                capsuleTop: CGFloat(42 + temporalOffset) * scale,
                shape: status && !expandedPhoto ? indicator : .absent, scale: scale, background: background,
                fullScreenPair: pair, statusContrast: weakerStatus ? 0.5 : 1)
            let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
                UIImage(cgImage: header).draw(at: .zero)
                if let photoProfile {
                    let navigationTop: CGFloat
                    switch photoOpening {
                    case .movedViewport: navigationTop = 157
                    case .movedFlatViewport, .movedFlatChangedNavigation: navigationTop = 202
                    default: navigationTop = 180
                    }
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: CGRect(x: 0, y: navigationTop * scale,
                        width: CGFloat(width), height: (320 - navigationTop) * scale))
                    UIImage(cgImage: photoProfile).draw(at: .zero)
                    context.cgContext.restoreGState()
                }
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: 0, y: bodyStart, width: CGFloat(width), height: bottom - bodyStart))
                world.draw(at: CGPoint(x: axis == .horizontal ? -CGFloat(scrollOffset) : 0,
                                       y: top - (axis == .vertical ? CGFloat(scrollOffset) : 0)))
                context.cgContext.restoreGState()
                if let photoOpening {
                    drawPhotoOpening(in: context.cgContext, scale: scale, expanded: expandedPhoto,
                        changedNavigation: (photoOpening == .changedNavigation
                            || photoOpening == .movedFlatChangedNavigation) && index > 0,
                        legacyMasked: photoOpening == .legacyMasked)
                } else {
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
                if transientOpening && index == 0 {
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
        func pixels(_ image: CGImage, _ rect: CGRect) -> [UInt8] {
            guard let crop = image.cropping(to: rect), crop.width == Int(rect.width),
                  crop.height == Int(rect.height) else { return [] }
            var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: crop.width, height: crop.height,
                    bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.interpolationQuality = .none
                context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
                return true
            }
            return rendered ? bytes : []
        }
        let left = pixels(first, a), right = pixels(second, b)
        guard left.count == right.count, !left.isEmpty else { return .infinity }
        var error = 0.0
        for index in left.indices where index % 4 != 3 {
            error += Double(abs(Int(left[index]) - Int(right[index])))
        }
        return error / Double(left.count / 4 * 3)
    }
#endif
}

private enum CheckError: Error { case image }
