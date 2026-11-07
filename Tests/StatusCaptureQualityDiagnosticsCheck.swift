import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import Darwin

@main struct DiagnosticsCheck {
    static var groups = 0
    static let fm = FileManager.default
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "DiagnosticsCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func group(_ title: String, _ body: () throws -> Void) throws {
        try body(); groups += 1; print("PASS \(title)")
    }
    static func image(width: Int = 320, height: Int = 720) -> CGImage {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let p = (y * width + x) * 4
            rgba[p] = UInt8((x * 17 + y * 3) % 256)
            rgba[p+1] = UInt8((x / 5 * 41 + y * 7) % 256)
            rgba[p+2] = UInt8(((x % 11 < 5 ? 20 : 210) + y) % 256); rgba[p+3] = 255
        } }
        let data = Data(rgba) as CFData
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    static func jpeg(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination)); return data as Data
    }
    static func decode(_ url: URL) throws -> CGImage { try decode(Data(contentsOf: url)) }
    static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw NSError(domain: "decode", code: 1) }
        return image
    }
    static func pixels(_ image: CGImage) -> Data {
        let c = CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        c.interpolationQuality = .none; c.setBlendMode(.copy)
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: c.data!, count: image.width * image.height * 4)
    }
    static func object(_ url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func main() throws {
        let base = CommandLine.arguments.count > 1
            ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            : fm.temporaryDirectory.appendingPathComponent("longshot-quality-check-" + UUID().uuidString, isDirectory: true)
        try check(!fm.fileExists(atPath: base.path), "test directory must not exist")
        let docs = base.appendingPathComponent("Documents", isDirectory: true)
        let session = base.appendingPathComponent("RawSessions/session-a", isDirectory: true)
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        try fm.createDirectory(at: session, withIntermediateDirectories: true)
        let canary = docs.appendingPathComponent("normal-app-data.txt"), canaryData = Data("preserve app data".utf8)
        try canaryData.write(to: canary)
        StatusCaptureQualityDiagnostics.testDocumentsDirectoryURL = docs
        let root = docs.appendingPathComponent("LongShotStatusQuality", isDirectory: true)
        let diag = root.appendingPathComponent("session-a", isDirectory: true)
        let native = image(), encoded = jpeg(native), originalPixels = pixels(native)
        let source = session.appendingPathComponent("frame-000000.jpg")
        try encoded.write(to: source)
        let output = base.appendingPathComponent("exported.jpg")
        let outputBytes = jpeg(native); try outputBytes.write(to: output)
        StatusCaptureQualityDiagnostics.begin(sessionURL: session)
        for index in 0...8 {
            StatusCaptureQualityDiagnostics.captured(image: native, encodedFrame: encoded,
                index: index, sessionURL: session, metadata: ["bufferWidth": 320, "orientation": "up"])
        }
        StatusCaptureQualityDiagnostics.exported(image: native, encodedOutput: outputBytes,
            sourceURL: source, sourceRect: CGRect(x: 0, y: 0, width: 320, height: 54), outputURL: output)
        StatusCaptureQualityDiagnostics.exported(image: native, encodedOutput: outputBytes,
            sourceURL: source, sourceRect: CGRect(x: 0, y: 1, width: 320, height: 54), outputURL: output)
        StatusCaptureQualityDiagnostics.exported(image: native, encodedOutput: outputBytes,
            sourceURL: source, sourceRect: CGRect(x: 0, y: 0, width: 320, height: 54), outputURL: output)
        StatusCaptureQualityDiagnostics.waitForPendingDiagnostics()
        let manifest = try object(diag.appendingPathComponent("manifest.json"))
        let frames = manifest["frames"] as! [[String: Any]], outputs = manifest["outputs"] as! [[String: Any]]
        try group("immutable inputs and native pixel strips") {
            try check(pixels(native) == originalPixels, "CGImage pixels changed")
            try check(try Data(contentsOf: source) == encoded, "source JPEG changed")
            try check(try Data(contentsOf: output) == outputBytes, "output JPEG changed")
            let raw = try decode(diag.appendingPathComponent("frame-000000-captureBeforeJPEG.png"))
            let jpegStrip = try decode(diag.appendingPathComponent("frame-000000-decoded-frame.png"))
            try check(raw.width == 320 && raw.height == 58 && jpegStrip.width == 320 && jpegStrip.height == 58, "strip was resized")
            try check(pixels(raw) == pixels(native.cropping(to: CGRect(x: 0, y: 0, width: 320, height: 58))!), "native PNG pixels differ")
            try check(pixels(jpegStrip) == pixels(try decode(encoded).cropping(to: CGRect(x: 0, y: 0, width: 320, height: 58))!), "decoded JPEG strip differs")
            let canvas = try decode(diag.appendingPathComponent("output-00-native-canvas.png"))
            let final = try decode(diag.appendingPathComponent("output-00-decoded-output.png"))
            try check(canvas.width == 320 && canvas.height == 54 && final.height == 54, "comparison included rows outside source prefix")
            try check(pixels(canvas) == pixels(native.cropping(to: CGRect(x: 0, y: 0, width: 320, height: 54))!), "canvas PNG pixels differ")
        }
        try group("frame, session, source-file SHA256 and destination pairing") {
            try check(frames[0]["encodedFrameSHA256"] as? String == hash(encoded), "capture hash wrong")
            try check(outputs[0]["sourceFrameIndex"] as? Int == 0 && outputs[0]["sourceSessionID"] as? String == "session-a", "pair identity wrong")
            try check(outputs[0]["sourceEncodedFrameSHA256"] as? String == hash(encoded) && outputs[0]["exportSourceFileSHA256"] as? String == hash(encoded), "export source hash wrong")
            try check((outputs[0]["destinationOrigin"] as? [String: Int]) == ["x": 0, "y": 0], "destination was not top origin")
        }
        try group("bounded captures and unsupported pairing") {
            try check(frames.count == 8 && frames.allSatisfy { $0["status"] as? String == "captured" }, "first-eight bound failed")
            try check(outputs.count == 2 && outputs[0]["status"] as? String == "paired", "first-two output bound failed")
            try check(outputs[1]["status"] as? String == "unsupported" && outputs[1]["reason"] as? String == "non_original_top_prefix", "non-top source fabricated a pair")
            try check(!fm.fileExists(atPath: diag.appendingPathComponent("output-01-native-canvas.png").path), "unsupported output PNG exists")
        }
        let nextSession = base.appendingPathComponent("RawSessions/session-b", isDirectory: true)
        try fm.createDirectory(at: nextSession, withIntermediateDirectories: true)
        try group("latest owned session cleanup and unrelated data preservation") {
            StatusCaptureQualityDiagnostics.begin(sessionURL: nextSession)
            StatusCaptureQualityDiagnostics.waitForPendingDiagnostics()
            try check(!fm.fileExists(atPath: diag.path), "prior diagnostic session retained")
            try check(fm.fileExists(atPath: root.appendingPathComponent("session-b/manifest.json").path), "new session missing")
            try check(try Data(contentsOf: canary) == canaryData, "normal app data deleted")
            var refreshedRoot = URL(fileURLWithPath: root.path, isDirectory: true)
            refreshedRoot.removeAllCachedResourceValues()
            let excluded = try refreshedRoot.resourceValues(forKeys: [.isExcludedFromBackupKey])
#if os(macOS)
            // macOS /tmp reports false even immediately after setting the
            // documented resource key; verify its actual backup xattr instead.
            let hasBackupAttribute = root.withUnsafeFileSystemRepresentation { path in
                getxattr(path!, "com.apple.metadata:com_apple_backup_excludeItem", nil, 0, 0, 0) > 0
            }
            try check(hasBackupAttribute, "backup exclusion attribute missing")
#else
            try check(excluded.isExcludedFromBackup == true, "diagnostics not excluded from backup")
#endif
            StatusCaptureQualityDiagnostics.clear()
            try check(!fm.fileExists(atPath: root.path) && fm.fileExists(atPath: canary.path), "clear touched wrong tree")
        }
        try group("source hash survives immediate normal raw cleanup") {
            let raw = base.appendingPathComponent("RawSessions/session-cleanup", isDirectory: true)
            try fm.createDirectory(at: raw, withIntermediateDirectories: true)
            let frame = raw.appendingPathComponent("frame-000000.jpg"); try encoded.write(to: frame)
            StatusCaptureQualityDiagnostics.begin(sessionURL: raw)
            for index in 0..<8 {
                StatusCaptureQualityDiagnostics.captured(image: native, encodedFrame: encoded, index: index, sessionURL: raw)
            }
            StatusCaptureQualityDiagnostics.exported(image: native, encodedOutput: outputBytes,
                sourceURL: frame, sourceRect: CGRect(x: 0, y: 0, width: 320, height: 54), outputURL: output)
            try fm.removeItem(at: raw)
            StatusCaptureQualityDiagnostics.waitForPendingDiagnostics()
            let result = try object(root.appendingPathComponent("session-cleanup/manifest.json"))
            let pairs = result["outputs"] as! [[String: Any]]
            try check(pairs.first?["status"] as? String == "paired", "raw cleanup broke retained pair")
            try check(pairs.first?["exportSourceFileSHA256"] as? String == hash(encoded), "snapshot hash wrong")
            StatusCaptureQualityDiagnostics.clear()
        }
        try group("oversized encoded dimensions rejected before image creation") {
            let raw = base.appendingPathComponent("RawSessions/session-large", isDirectory: true)
            try fm.createDirectory(at: raw, withIntermediateDirectories: true)
            let frame = raw.appendingPathComponent("frame-000000.jpg"); try encoded.write(to: frame)
            var largeHeader = [UInt8](outputBytes)
            var found = false
            for i in 0..<(largeHeader.count - 8) where largeHeader[i] == 0xff && (largeHeader[i+1] == 0xc0 || largeHeader[i+1] == 0xc2) {
                largeHeader[i+5] = 0xea; largeHeader[i+6] = 0x60 // 60,000 * 320 = 19.2M pixels.
                found = true; break
            }
            try check(found, "synthetic JPEG has no SOF dimensions")
            StatusCaptureQualityDiagnostics.begin(sessionURL: raw)
            StatusCaptureQualityDiagnostics.captured(image: native, encodedFrame: encoded, index: 0, sessionURL: raw)
            StatusCaptureQualityDiagnostics.exported(image: native, encodedOutput: Data(largeHeader),
                sourceURL: frame, sourceRect: CGRect(x: 0, y: 0, width: 320, height: 54), outputURL: output)
            StatusCaptureQualityDiagnostics.waitForPendingDiagnostics()
            let result = try object(root.appendingPathComponent("session-large/manifest.json"))
            let pairs = result["outputs"] as! [[String: Any]]
            try check(pairs.first?["reason"] as? String == "encoded_pixel_budget", "oversized decode was not rejected by header budget")
            try check(!fm.fileExists(atPath: root.appendingPathComponent("session-large/output-00-native-canvas.png").path), "oversized pair wrote pixels")
            StatusCaptureQualityDiagnostics.clear()
        }
        try group("unowned diagnostic-name directory and symlink preserved") {
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            let ownedByUser = root.appendingPathComponent("user-data.txt")
            try canaryData.write(to: ownedByUser)
            StatusCaptureQualityDiagnostics.begin(sessionURL: session)
            StatusCaptureQualityDiagnostics.clear()
            try check(try Data(contentsOf: ownedByUser) == canaryData, "unowned tree deleted")
            try fm.removeItem(at: root)
            let target = base.appendingPathComponent("UnrelatedTarget", isDirectory: true)
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            let targetCanary = target.appendingPathComponent("canary.txt"); try canaryData.write(to: targetCanary)
            try fm.createSymbolicLink(at: root, withDestinationURL: target)
            StatusCaptureQualityDiagnostics.begin(sessionURL: session)
            StatusCaptureQualityDiagnostics.clear()
            try check(try Data(contentsOf: targetCanary) == canaryData, "symlink target changed")
            try check(try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true, "unowned symlink deleted")
            try fm.removeItem(at: root)
        }
        try group("invalid side path safely ignored") {
            let bad = base.appendingPathComponent("DocumentsIsFile"); try canaryData.write(to: bad)
            StatusCaptureQualityDiagnostics.testDocumentsDirectoryURL = bad
            StatusCaptureQualityDiagnostics.begin(sessionURL: session)
            StatusCaptureQualityDiagnostics.captured(image: native, encodedFrame: encoded, index: 0, sessionURL: session)
            StatusCaptureQualityDiagnostics.clear()
            StatusCaptureQualityDiagnostics.waitForPendingDiagnostics()
            try check(try Data(contentsOf: bad) == canaryData && pixels(native) == originalPixels, "failure changed original data")
        }
        print("PASS \(groups)/\(groups) diagnostic groups")
    }
}
