import CoreGraphics
import CoreText
import Foundation
import ImageIO
#if !LONGSHOT_OCR_STUB
import Vision
#endif

#if LONGSHOT_OCR_STUB
// Inert OCR adapter: only the accurate-fallback routing is substituted.
// Gray-card gating and text classification execute the production detector.
struct OCRCandidate {
    let string: String
    let confidence: Float
}
struct OCRObservation {
    let candidate: OCRCandidate
    func topCandidates(_ count: Int) -> [OCRCandidate] { [candidate] }
}
final class VNRecognizeTextRequest {
    enum Level { case fast, accurate }
    var recognitionLevel: Level = .fast
    var recognitionLanguages: [String] = []
    var usesLanguageCorrection = false
    var results: [OCRObservation]?
}
final class VNImageRequestHandler {
    static var fast: [(String, Float)] = []
    static var accurate: [(String, Float)] = []
    static var accurateCalls = 0
    init(cgImage: CGImage) {}
    func perform(_ requests: [VNRecognizeTextRequest]) throws {
        for request in requests {
            let observations: [(String, Float)]
            switch request.recognitionLevel {
            case .fast: observations = Self.fast
            case .accurate: observations = Self.accurate; Self.accurateCalls += 1
            }
            request.results = observations.map { OCRObservation(candidate: OCRCandidate(string: $0.0, confidence: $0.1)) }
        }
    }
}
#endif

@main
struct CaptureOverlayDetectorCheck {
    static func main() throws {
#if LONGSHOT_OCR_STUB
        try checkAccurateFallbackRouting()
        print("Overlay OCR fallback checks passed (4): English full-screen, English active-sharing, Chinese, partial-keyword negative. OCR adapter only.")
#else
        try checkNativeSyntheticImages()
        try checkCollapsingActivityGeometry()
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--fixture" {
            try checkAuthorizedFixture(URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
        }
        print("Overlay native-image checks passed (10): gray-sheet OCR, neutral negatives, collapsing activity, dark/low/no-red/blue/compact negatives.")
#endif
    }

    private static func makeImage(lines: [String]) throws -> CGImage {
        let width = 1024, height = 2048
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                colors: [CGColor(gray: 0.25, alpha: 1), CGColor(gray: 0.75, alpha: 1)] as CFArray,
                locations: [0, 1]) else { throw CheckError.image }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: width, y: 0), options: [])
        for (index, text) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 66, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let length = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: (Double(width) - length) / 2,
                y: Double(height) * (index == 0 ? 0.70 : 0.30))
            CTLineDraw(line, context)
        }
        guard let image = context.makeImage() else { throw CheckError.image }
        return image
    }

#if !LONGSHOT_OCR_STUB
    private static func checkNativeSyntheticImages() throws {
        let panel = try makeImage(lines: ["Screen Sharing", "Share Entire Screen"])
        // Probe the actual runtime first: a restricted process can make Vision
        // fail to initialize. Such a failure must never be reported as a pass.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: panel).perform([request])
        require(CaptureOverlayDetector.inspect(panel).isSystemPanel,
            "A blurred neutral sheet must not be missed because its gray shades vary")
        try require(!CaptureOverlayDetector.inspect(try makeImage(lines: [])).isSystemPanel,
            "Neutral gray background alone must never discard a frame")
        try require(!CaptureOverlayDetector.inspect(try makeImage(lines: ["Monthly Report", "Quarterly Summary"])).isSystemPanel,
            "Unrelated neutral app content must remain usable")
        try require(!CaptureOverlayDetector.inspect(try makeImage(lines: ["Screen Sharing", "Preferences"])).isSystemPanel,
            "One isolated sharing keyword does not identify system sharing controls")
    }

    private static func checkAuthorizedFixture(_ directory: URL) throws {
        for index in 0...13 {
            let url = directory.appendingPathComponent(String(format: "frame-%06d.jpg", index))
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CheckError.image }
            let detection = CaptureOverlayDetector.inspect(image)
            require(detection.isSystemPanel || detection.coveredTopRatio > 0,
                "The authorized initial system sharing/activity frame must be excluded (index \(index))")
        }
        for index in 14...40 {
            let url = directory.appendingPathComponent(String(format: "frame-%06d.jpg", index))
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CheckError.image }
            let detection = CaptureOverlayDetector.inspect(image)
            require(!detection.isSystemPanel && detection.coveredTopRatio == 0,
                "Clean authorized table frame must be retained (index \(index))")
        }
        print("Authorized local fixture: initial system/activity frames 0-13 excluded; clean frames 14-40 retained. No image content emitted.")
    }

    private static func checkCollapsingActivityGeometry() throws {
        let width = 1206, height = 2622
        for kind in 0...5 {
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CheckError.image }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(CGColor(gray: kind == 0 ? 0 : 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            if kind == 0 {
                // The existing full-dark screenshot negative: red content near
                // the top does not by itself identify an expanded activity.
                context.setFillColor(CGColor(red: 0.6, green: 0.24, blue: 0.18, alpha: 1))
                context.fill(CGRect(x: 0, y: 55, width: width, height: 150))
            } else {
                let y: CGFloat = kind == 1 ? 400 : 40
                let pill = kind == 5 ? CGRect(x: 300, y: y, width: 520, height: 110)
                    : CGRect(x: 250, y: y, width: 650, height: 170)
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.addPath(CGPath(roundedRect: pill, cornerWidth: 80, cornerHeight: 80, transform: nil))
                context.fillPath()
                if kind != 2 {
                    context.setFillColor(kind == 3
                        ? CGColor(red: 0.06, green: 0.13, blue: 0.25, alpha: 1)
                        : CGColor(red: 0.25, green: 0.07, blue: 0.06, alpha: 1))
                    context.fillEllipse(in: CGRect(x: pill.minX + 50, y: y + 45, width: 55, height: 60))
                }
            }
            guard let image = context.makeImage() else { throw CheckError.image }
            let detection = CaptureOverlayDetector.inspect(image)
            if kind == 4 {
                require(detection.coveredTopRatio > 0.07 && detection.coveredTopRatio < 0.11,
                    "Oversized collapsing activity with dim red recording indicators must be masked")
            } else {
                require(detection.coveredTopRatio == 0,
                    "Dark, low-positioned, no-red, blue and compact shapes must not be masked (case \(kind))")
            }
            require(!detection.isSystemPanel, "Activity geometry must not imply a system sharing sheet")
        }
    }
#else
    private static func checkAccurateFallbackRouting() throws {
        let image = try makeImage(lines: [])
        for strings in [["Share Entire Screen"], ["Screen Sharing", "Stop Sharing"], ["共享整个屏幕"]] {
            VNImageRequestHandler.fast = [("unrelated", 0.9)]
            VNImageRequestHandler.accurate = strings.map { ($0, Float(0.9)) }
            let previousCalls = VNImageRequestHandler.accurateCalls
            require(CaptureOverlayDetector.inspect(image).isSystemPanel,
                "Accurate OCR must recognize both supported languages")
            require(VNImageRequestHandler.accurateCalls == previousCalls + 1,
                "Fast OCR miss must reach the accurate fallback exactly once")
        }
        VNImageRequestHandler.fast = [("Screen Sharing", 0.2)]
        VNImageRequestHandler.accurate = [("Screen Sharing", 0.9)]
        require(!CaptureOverlayDetector.inspect(image).isSystemPanel,
            "Low-confidence or partial sharing text must not discard ordinary content")
    }
#endif

    private static func require(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        if try !value() { fatalError(message) }
    }
}

private enum CheckError: Error { case image }
