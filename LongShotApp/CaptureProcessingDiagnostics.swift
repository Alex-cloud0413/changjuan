import Foundation
import UIKit

/// Small, bounded local timing journal. It never includes screen contents,
/// image paths or user text, and a write failure cannot interrupt a capture.
@MainActor
enum CaptureProcessingDiagnostics {
    static var sessionID: String?
    static let processRunID = UUID().uuidString
    private static let maximumEvents = 240
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var buildMetadata: [String: Any] {
        [
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "optimizedBuild": !_isDebugAssertConfiguration(),
            "processRunID": processRunID
        ]
    }

    static func record(_ event: String, sessionID: String? = nil, values: [String: Any] = [:]) {
        do {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = directory.appendingPathComponent("LongShotProcessingEvents.json")
            var events = (try? Data(contentsOf: destination)).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]]
            } ?? []
            var entry = buildMetadata.merging(values) { _, new in new }
            entry["event"] = event
            entry["timestamp"] = timestampFormatter.string(from: Date())
            entry["uptimeSeconds"] = ProcessInfo.processInfo.systemUptime
            entry["sessionID"] = sessionID ?? Self.sessionID
            entry["applicationState"] = UIApplication.shared.applicationState.rawValue
            let remaining = UIApplication.shared.backgroundTimeRemaining
            // UIKit uses a very large sentinel when background time is unlimited.
            if remaining.isFinite, remaining < 86_400 { entry["backgroundTimeRemaining"] = remaining }
            events.append(entry)
            let data = try JSONSerialization.data(
                withJSONObject: Array(events.suffix(maximumEvents)), options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: destination, options: .atomic)
        } catch { /* Timing diagnostics must never affect saving. */ }
    }
}

/// Retains the task identifier while async processing owns the lease, so an
/// expiration is logged and ended exactly once even after ownership transfers.
@MainActor
final class CaptureProcessingBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let stage: String
    private let sessionID: String?

    init(name: String, stage: String) {
        self.stage = stage
        sessionID = CaptureProcessingDiagnostics.sessionID
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            guard let self else { return }
            CaptureProcessingDiagnostics.record("backgroundTimeExpired", sessionID: sessionID, values: ["stage": stage])
            end()
        }
        CaptureProcessingDiagnostics.record("backgroundTaskStarted", sessionID: sessionID, values: [
            "stage": stage, "granted": identifier != .invalid
        ])
    }

    func end() {
        guard identifier != .invalid else { return }
        let task = identifier
        identifier = .invalid
        CaptureProcessingDiagnostics.record("backgroundTaskEnded", sessionID: sessionID, values: ["stage": stage])
        UIApplication.shared.endBackgroundTask(task)
    }
}

#if LONGSHOT_STATUS_QUALITY_DIAGNOSTICS
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
import CryptoKit

/// Private-build instrumentation only. Never changes a capture, stitch or Photo.
/// The dedicated Documents subdirectory is replaced only after ownership checks.
enum StatusCaptureQualityDiagnostics {
    private static let lock = NSLock()
    private static let owner = "com.gaoyiming.longshot.status-quality.v1"
    private static let rootName = "LongShotStatusQuality"
    private static let markerName = ".longshot-status-quality-owner.json"
    private static let stagePrefix = ".LongShotStatusQuality-stage-"
    private static let maximumFrames = 8
    private static let maximumOutputs = 2
    private static let queue = DispatchQueue(label: "com.gaoyiming.longshot.status-quality", qos: .utility)
    private static let maximumPendingBytes = 32 * 1024 * 1024
    private static let maximumDiskBytes = 64 * 1024 * 1024
    private static var generation = UUID().uuidString
    private static var scheduledFrames = Set<Int>()
    private static var scheduledOutputs = 0
    private static var pendingBytes = 0
    private struct State {
        let sourceSession: URL
        let documents: URL
        let root: URL
        let directory: URL
        let token: String
        var attemptedFrames = Set<Int>()
        var frames: [Int: [String: Any]] = [:]
        var outputs: [[String: Any]] = []
        var errors: [String] = []
        var writtenBytes = 0
    }
    private static var state: State?
#if LONGSHOT_CAPTURE_CHECKS
    /// Set before begin() in an isolated test; interpreted as Documents, not root.
    nonisolated(unsafe) static var testDocumentsDirectoryURL: URL?
#endif

    static func begin(sessionURL: URL) {
        lock.lock()
        let token = UUID().uuidString
        generation = token; state = nil; scheduledFrames = []; scheduledOutputs = 0
        lock.unlock()
        queue.sync { beginWorker(sessionURL: sessionURL, token: token) }
    }

    private static func beginWorker(sessionURL: URL, token: String) {
        lock.lock(); defer { lock.unlock() }
        guard generation == token else { return }
        state = nil
        var createdStage: URL?
        do {
            guard sessionURL.isFileURL else { throw Failure("invalid_source_session") }
            let id = sessionURL.lastPathComponent
            guard validComponent(id) else { throw Failure("invalid_session_identifier") }
            let documents = try documentsURL()
            let root = documents.appendingPathComponent(rootName, isDirectory: true)
            let stage = documents.appendingPathComponent(stagePrefix + UUID().uuidString, isDirectory: true)
            // Exclusive creation prevents adopting someone else's ordinary folder.
            guard mkdir(stage.path, 0o700) == 0 else { throw Failure("stage_create_failed") }
            createdStage = stage
            try writeJSON(["owner": owner, "schemaVersion": 1, "token": token],
                          to: stage.appendingPathComponent(markerName))
            var backupURL = stage
            var backup = URLResourceValues(); backup.isExcludedFromBackup = true
            try backupURL.setResourceValues(backup)
            let stageSession = stage.appendingPathComponent(id, isDirectory: true)
            guard mkdir(stageSession.path, 0o700) == 0 else { throw Failure("session_create_failed") }
            var next = State(sourceSession: sessionURL.standardizedFileURL,
                documents: documents, root: root,
                directory: root.appendingPathComponent(id, isDirectory: true), token: token)
            try persist(next, directory: stageSession)
            if exists(root) {
                guard ownedDirectory(root, documents: documents, permitStage: false) else {
                    throw Failure("refused_unowned_root")
                }
                guard renamex_np(stage.path, root.path, UInt32(RENAME_SWAP)) == 0 else {
                    throw Failure("root_swap_failed")
                }
                // Recheck the retired directory after exchange before deleting.
                guard ownedDirectory(stage, documents: documents, permitStage: true) else {
                    if ownedDirectory(root, documents: documents, permitStage: false, token: token) {
                        _ = renamex_np(stage.path, root.path, UInt32(RENAME_SWAP))
                    }
                    throw Failure("retired_root_not_owned")
                }
                do { try FileManager.default.removeItem(at: stage) }
                catch { next.errors.append("retired_cleanup_failed"); log("retired_cleanup_failed", error) }
            } else {
                guard renamex_np(stage.path, root.path, UInt32(RENAME_EXCL)) == 0 else {
                    throw Failure("root_publish_failed")
                }
            }
            createdStage = nil
            guard ownedDirectory(root, documents: documents, permitStage: false, token: token),
                  plainDirectory(next.directory) else { throw Failure("published_root_invalid") }
            state = next
            try? persist(next)
        } catch {
            log("begin_failed", error)
            if let stage = createdStage {
                if let documents = try? documentsURL(), ownedDirectory(stage, documents: documents, permitStage: true) {
                    try? FileManager.default.removeItem(at: stage)
                } else {
                    // Only remove an empty directory created by this call.
                    _ = rmdir(stage.path)
                }
            }
        }
    }

    /// Retires only this helper's owned directory and invalidates queued jobs.
    static func clear() {
        lock.lock(); let token = UUID().uuidString; generation = token; state = nil
        scheduledFrames = []; scheduledOutputs = 0; lock.unlock()
        queue.sync {
            lock.lock(); let currentGeneration = generation; lock.unlock()
            guard currentGeneration == token else { return }
            do {
                let documents = try documentsURL()
                let root = documents.appendingPathComponent(rootName, isDirectory: true)
                if exists(root) {
                    guard ownedDirectory(root, documents: documents, permitStage: false) else {
                        throw Failure("refused_unowned_clear")
                    }
                    try FileManager.default.removeItem(at: root)
                }
            } catch { log("clear_failed", error) }
        }
    }

    static func captured(image: CGImage, encodedFrame: Data, index: Int,
                         sessionURL: URL, metadata: [String: Any] = [:]) {
        lock.lock()
        guard let current = state, current.sourceSession == sessionURL.standardizedFileURL,
              index >= 0, index < maximumFrames, !scheduledFrames.contains(index),
              let height = stripHeight(image), encodedFrame.count <= 16 * 1024 * 1024 else {
            lock.unlock(); return
        }
        scheduledFrames.insert(index)
        let bytes = image.width * height * 8 + encodedFrame.count
        guard pendingBytes <= maximumPendingBytes - bytes else { lock.unlock(); log("pending_budget", Failure("pending_budget_reached")); return }
        pendingBytes += bytes
        let token = current.token, originalWidth = image.width, originalHeight = image.height
        lock.unlock()
        guard let strip = copyStrip(image, height: height) else { releaseReservation(bytes); log("copy_strip", Failure("native_copy_unsupported")); return }
        // Bound optional descriptive metadata independently of image budgets.
        var safeMetadata: [String: Any] = [:]
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }).prefix(16) {
            guard key.utf8.count <= 64, JSONSerialization.isValidJSONObject([key: value]),
                  let data = try? JSONSerialization.data(withJSONObject: [key: value]), data.count <= 1024 else { continue }
            safeMetadata[key] = value
        }
        queue.async {
            defer { releaseReservation(bytes) }
            capturedWorker(image: strip, encodedFrame: encodedFrame, index: index,
                sessionURL: sessionURL, token: token, originalWidth: originalWidth,
                originalHeight: originalHeight, metadata: safeMetadata)
        }
    }

    static func exported(image: CGImage, encodedOutput: Data, sourceURL: URL,
                         sourceRect: CGRect, outputURL: URL) {
        lock.lock()
        guard let current = state, scheduledOutputs < maximumOutputs,
              let height = stripHeight(image), encodedOutput.count <= 16 * 1024 * 1024 else {
            lock.unlock(); return
        }
        scheduledOutputs += 1
        let bytes = image.width * height * 8 + encodedOutput.count
        guard pendingBytes <= maximumPendingBytes - bytes else { lock.unlock(); log("pending_budget", Failure("pending_budget_reached")); return }
        pendingBytes += bytes
        let token = current.token, originalWidth = image.width, originalHeight = image.height
        lock.unlock()
        guard let strip = copyStrip(image, height: height) else { releaseReservation(bytes); log("copy_strip", Failure("native_copy_unsupported")); return }
        // This hook returns before normal result delivery can retire raw frames.
        // Snapshot only a bounded source-file hash here; PNG work stays async.
        let sourceFileHash = sourceSnapshotHash(sourceURL, session: current.sourceSession)
        queue.async {
            defer { releaseReservation(bytes) }
            exportedWorker(image: strip, encodedOutput: encodedOutput, sourceURL: sourceURL,
                sourceRect: sourceRect, outputURL: outputURL, token: token,
                originalWidth: originalWidth, originalHeight: originalHeight,
                sourceFileHash: sourceFileHash)
        }
    }

    private static func releaseReservation(_ bytes: Int) {
        lock.lock(); pendingBytes = max(0, pendingBytes - bytes); lock.unlock()
    }

    /// Deep copy in the original native 8-bit bitmap format, never retaining
    /// the full-height frame on the writer queue or changing its pixel scale.
    private static func copyStrip(_ image: CGImage, height: Int) -> CGImage? {
        guard image.bitsPerComponent == 8, let space = image.colorSpace,
              let crop = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: height)),
              let context = CGContext(data: nil, width: crop.width, height: crop.height,
                bitsPerComponent: image.bitsPerComponent, bytesPerRow: 0,
                space: space, bitmapInfo: image.bitmapInfo.rawValue) else { return nil }
        context.interpolationQuality = .none; context.setBlendMode(.copy)
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        return context.makeImage()
    }

#if LONGSHOT_CAPTURE_CHECKS
    static func waitForPendingDiagnostics() { queue.sync {} }
#endif

    private static func capturedWorker(image: CGImage, encodedFrame: Data, index: Int, sessionURL: URL,
        token: String, originalWidth: Int, originalHeight: Int, metadata: [String: Any]) {
        guard var current = checkedState(token: token),
              current.sourceSession == sessionURL.standardizedFileURL,
              index >= 0, index < maximumFrames, !current.attemptedFrames.contains(index) else { return }
        current.attemptedFrames.insert(index)
        let prefix = String(format: "frame-%06d", index)
        var record: [String: Any] = ["index": index, "sourceFrameBasename": prefix + ".jpg",
            "nativeWidth": originalWidth, "nativeHeight": originalHeight,
            "encodedBytes": encodedFrame.count, "encodedFrameSHA256": digest(encodedFrame),
            "sourceSessionID": sessionURL.lastPathComponent, "captureMetadata": metadata,
            "nativeStage": "after_CI_orientation_before_JPEG", "status": "unsupported"]
        do {
            guard let height = stripHeight(image),
                  let raw = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: height)) else {
                throw Failure("capture_strip_unsupported")
            }
            let decoded = try decode(encodedFrame)
            record["encodedCodec"] = decoded.codec
            record["decodedWidth"] = decoded.image.width
            record["decodedHeight"] = decoded.image.height
            guard decoded.image.width == originalWidth, decoded.image.height == originalHeight,
                  let frameStrip = decoded.image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: height)) else {
                throw Failure("capture_dimension_mismatch")
            }
            let rawName = prefix + "-captureBeforeJPEG.png", decodedName = prefix + "-decoded-frame.png"
            try writePNG(raw, to: current.directory.appendingPathComponent(rawName), state: &current)
            try writePNG(frameStrip, to: current.directory.appendingPathComponent(decodedName), state: &current)
            record["nativePNG"] = rawName; record["decodedFramePNG"] = decodedName
            record["stripWidth"] = image.width; record["stripHeight"] = height
            record["status"] = "captured"
        } catch {
            record["reason"] = reason(error)
            addError(&current, "capture_\(index)_" + reason(error)); log("capture_failed", error)
        }
        current.frames[index] = record
        commit(current, token: token)
    }

    private static func exportedWorker(image: CGImage, encodedOutput: Data, sourceURL: URL,
        sourceRect: CGRect, outputURL: URL, token: String, originalWidth: Int, originalHeight: Int,
        sourceFileHash: String?) {
        guard var current = checkedState(token: token),
              current.outputs.count < maximumOutputs else { return }
        let ordinal = current.outputs.count
        var record: [String: Any] = ["ordinal": ordinal, "outputBasename": outputURL.lastPathComponent,
            "sourceFrameBasename": sourceURL.lastPathComponent,
            "sourceRect": rectJSON(sourceRect), "destinationOrigin": ["x": 0, "y": 0],
            "canvasWidth": originalWidth, "canvasHeight": originalHeight,
            "sourceSessionID": current.sourceSession.lastPathComponent,
            "encodedBytes": encodedOutput.count, "encodedOutputSHA256": digest(encodedOutput), "status": "unsupported"]
        do {
            guard sourceURL.isFileURL,
                  sourceURL.standardizedFileURL.deletingLastPathComponent() == current.sourceSession,
                  let index = frameIndex(sourceURL.lastPathComponent), index < maximumFrames else {
                throw Failure("source_frame_not_retained")
            }
            record["sourceFrameIndex"] = index
            guard let frame = current.frames[index], frame["status"] as? String == "captured",
                  frame["sourceFrameBasename"] as? String == sourceURL.lastPathComponent else {
                throw Failure("source_capture_pair_missing")
            }
            record["sourceEncodedFrameSHA256"] = frame["encodedFrameSHA256"]
            guard let sourceFileHash else { throw Failure("source_file_snapshot_unavailable") }
            record["exportSourceFileSHA256"] = sourceFileHash
            guard sourceFileHash == frame["encodedFrameSHA256"] as? String else {
                throw Failure("source_file_pair_mismatch")
            }
            guard [sourceRect.minX, sourceRect.minY, sourceRect.width, sourceRect.height].allSatisfy(\.isFinite),
                  sourceRect.minX == 0, sourceRect.minY == 0,
                  sourceRect.width == CGFloat(image.width), sourceRect.height > 0,
                  frame["nativeWidth"] as? Int == image.width,
                  let maximum = stripHeight(image) else { throw Failure("non_original_top_prefix") }
            // Never claim rows outside the supplied source piece belong to it.
            let height = min(maximum, Int(min(CGFloat(maximum), floor(sourceRect.height))))
            guard height > 0, let canvas = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: height)) else {
                throw Failure("export_strip_unsupported")
            }
            let decoded = try decode(encodedOutput)
            record["encodedCodec"] = decoded.codec
            record["decodedWidth"] = decoded.image.width; record["decodedHeight"] = decoded.image.height
            guard decoded.image.width == originalWidth, decoded.image.height == originalHeight,
                  let finalStrip = decoded.image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: height)) else {
                throw Failure("export_dimension_mismatch")
            }
            let prefix = String(format: "output-%02d", ordinal)
            let canvasName = prefix + "-native-canvas.png", finalName = prefix + "-decoded-output.png"
            try writePNG(canvas, to: current.directory.appendingPathComponent(canvasName), state: &current)
            try writePNG(finalStrip, to: current.directory.appendingPathComponent(finalName), state: &current)
            record["nativeCanvasPNG"] = canvasName; record["decodedOutputPNG"] = finalName
            record["comparisonRect"] = rectJSON(CGRect(x: 0, y: 0, width: image.width, height: height))
            record["status"] = "paired"
        } catch {
            record["reason"] = reason(error)
            addError(&current, "output_\(ordinal)_" + reason(error)); log("export_failed", error)
        }
        current.outputs.append(record)
        commit(current, token: token)
    }

    private struct Failure: Error { let code: String; init(_ code: String) { self.code = code } }
    private static func reason(_ error: Error) -> String {
        (error as? Failure)?.code ?? "io_failed"
    }
    private static func log(_ stage: String, _ error: Error) {
        let code = (error as NSError).code
        NSLog("LongShotStatusQuality %@ %@ (%ld)", stage, reason(error), code)
    }
    private static func addError(_ value: inout State, _ message: String) {
        if value.errors.count < 16 { value.errors.append(message) }
    }
    private static func documentsURL() throws -> URL {
#if LONGSHOT_CAPTURE_CHECKS
        if let override = testDocumentsDirectoryURL {
            guard override.isFileURL else { throw Failure("test_documents_not_file") }
            try FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override.standardizedFileURL.resolvingSymlinksInPath()
        }
#endif
        return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).standardizedFileURL.resolvingSymlinksInPath()
    }
    /// Only state/reservations use the lock. Serial writer work (including
    /// ownership checks, hashes, codecs and disk) never blocks the capture lock.
    private static func checkedState(token: String) -> State? {
        lock.lock()
        let value = generation == token ? state : nil
        lock.unlock()
        guard let value, value.token == token,
              ownedDirectory(value.root, documents: value.documents, permitStage: false, token: value.token),
              plainDirectory(value.directory) else { return nil }
        return value
    }
    private static func commit(_ value: State, token: String) {
        lock.lock()
        let current = generation == token && state?.token == token
        if current { state = value }
        lock.unlock()
        // begin/clear enqueue behind this worker before retiring the root.
        if current { try? persist(value) }
    }
    private static func exists(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])) != nil
    }
    private static func plainDirectory(_ url: URL) -> Bool {
        guard let info = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return info.isDirectory == true && info.isSymbolicLink != true
    }
    private static func ownedDirectory(_ url: URL, documents: URL, permitStage: Bool, token: String? = nil) -> Bool {
        guard url.standardizedFileURL.deletingLastPathComponent() == documents,
              url.lastPathComponent == rootName || (permitStage && url.lastPathComponent.hasPrefix(stagePrefix)),
              plainDirectory(url) else { return false }
        let marker = url.appendingPathComponent(markerName)
        guard let info = try? marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              info.isRegularFile == true, info.isSymbolicLink != true,
              let data = try? Data(contentsOf: marker), data.count < 4096,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["owner"] as? String == owner, object["schemaVersion"] as? Int == 1,
              let actual = object["token"] as? String, UUID(uuidString: actual) != nil else { return false }
        return token == nil || token == actual
    }
    private static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.utf8.count <= 128
            && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }
    }
    private static func frameIndex(_ name: String) -> Int? {
        guard name.hasPrefix("frame-"), name.hasSuffix(".jpg") else { return nil }
        let part = name.dropFirst(6).dropLast(4)
        guard part.count == 6, part.allSatisfy(\.isNumber), let index = Int(part), index >= 0 else { return nil }
        return index
    }
    private static func stripHeight(_ image: CGImage) -> Int? {
        guard image.width > 0, image.width <= 4096, image.height > 0 else { return nil }
        let height = min(image.height, Int(ceil(Double(image.width) * 0.18)))
        guard height > 0, height <= 768, image.width <= 2_000_000 / height else { return nil }
        return height
    }
    private static func decode(_ data: Data) throws -> (image: CGImage, codec: String) {
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldCacheImmediately: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw Failure("encoded_properties_missing")
        }
        // The encoded file may be a very tall exported image. Check its full
        // dimensions before any ImageIO image/decode allocation, not just ROI.
        let w = width.intValue, h = height.intValue
        guard w > 0, h > 0, w <= 16_000_000 / h else { throw Failure("encoded_pixel_budget") }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw Failure("encoded_decode_failed")
        }
        return (image, CGImageSourceGetType(source).map { $0 as String } ?? "unknown")
    }
    private static func sourceSnapshotHash(_ url: URL, session: URL) -> String? {
        guard url.isFileURL, url.standardizedFileURL.deletingLastPathComponent() == session,
              let index = frameIndex(url.lastPathComponent), index < maximumFrames,
              let info = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              info.isRegularFile == true, info.isSymbolicLink != true,
              let count = info.fileSize, count >= 0, count <= 16 * 1024 * 1024,
              let data = try? Data(contentsOf: url), data.count <= 16 * 1024 * 1024 else { return nil }
        return digest(data)
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func writePNG(_ image: CGImage, to url: URL, state: inout State) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure("png_destination_failed")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure("png_encoding_failed") }
        guard data.length <= maximumDiskBytes - state.writtenBytes else { throw Failure("disk_budget_reached") }
        try (data as Data).write(to: url, options: .atomic)
        state.writtenBytes += data.length
    }
    private static func rectJSON(_ rect: CGRect) -> [String: Any] {
        func number(_ value: CGFloat) -> Any { value.isFinite ? Double(value) : NSNull() }
        return ["x": number(rect.minX), "y": number(rect.minY), "width": number(rect.width), "height": number(rect.height)]
    }
    private static func persist(_ value: State, directory: URL? = nil) throws {
        try writeJSON(["schemaVersion": 1, "owner": owner, "sessionID": value.sourceSession.lastPathComponent,
            "token": value.token, "captureFrameLimit": maximumFrames, "outputLimit": maximumOutputs,
            "frames": value.frames.keys.sorted().compactMap { value.frames[$0] },
            "outputs": value.outputs, "errors": value.errors,
            "writtenPNGBytes": value.writtenBytes, "maximumPNGBytes": maximumDiskBytes,
            "captureNativeStage": "after_CI_orientation_before_JPEG",
            "note": "Private diagnostic build only. Native PNG strips are unscaled. Compare only the recorded comparisonRect; no image pixels are changed by diagnostics."],
            to: (directory ?? value.directory).appendingPathComponent("manifest.json"))
    }
    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
#endif
