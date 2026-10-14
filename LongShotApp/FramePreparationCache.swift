import Foundation
import UIKit

/// Derived only from the committed JPEG, using the same sampling operations as
/// the uncached stitcher. Original images remain the sole rendering source.
struct PreparedFrame: Codable {
    let version: Int
    let sourceByteCount: Int
    let sourceModifiedAt: Date
    let imageWidth: Int
    let imageHeight: Int
    let coarseHeight: Int
    let coarsePixels: Data
    let alignmentHeight: Int
    let alignmentPixels: Data
    let coveredTop: Double
    let isSystemPanel: Bool

    var gray: GrayFrame {
        GrayFrame(width: 72, height: coarseHeight, pixels: Array(coarsePixels))
    }

    var alignment: GrayFrame {
        GrayFrame(width: 72, height: alignmentHeight, pixels: Array(alignmentPixels))
    }
}

enum FramePreparationCache {
    static let version = 1

    static func cacheURL(for frame: URL) -> URL {
        frame.deletingLastPathComponent().appendingPathComponent("Analysis-v1", isDirectory: true)
            .appendingPathComponent(frame.lastPathComponent + ".plist")
    }

    static func sourceIdentity(for frame: URL) throws -> (bytes: Int, modifiedAt: Date) {
        // URL resource values may retain an earlier timestamp after a file is
        // replaced. Always stat the source again before accepting derived data.
        let values = try FileManager.default.attributesOfItem(atPath: frame.path)
        guard let bytes = (values[.size] as? NSNumber)?.intValue,
              let modifiedAt = values[.modificationDate] as? Date else {
            throw CocoaError(.fileReadUnknown)
        }
        return (bytes, modifiedAt)
    }

    static func load(for frame: URL) -> PreparedFrame? {
        let url = cacheURL(for: frame)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 2_000_000,
              let data = try? Data(contentsOf: url),
              let prepared = try? PropertyListDecoder().decode(PreparedFrame.self, from: data),
              prepared.version == version,
              let identity = try? sourceIdentity(for: frame),
              prepared.sourceByteCount == identity.bytes,
              prepared.sourceModifiedAt == identity.modifiedAt,
              prepared.imageWidth > 0, prepared.imageWidth <= 16_384,
              prepared.imageHeight > 0, prepared.imageHeight <= 16_384,
              prepared.coarseHeight >= 96, prepared.coarseHeight <= 16_384,
              prepared.alignmentHeight > 0, prepared.alignmentHeight <= 16_384,
              prepared.coarsePixels.count == 72 * prepared.coarseHeight,
              prepared.alignmentPixels.count == 72 * prepared.alignmentHeight,
              prepared.coveredTop.isFinite, prepared.coveredTop >= 0,
              prepared.coveredTop <= Double(prepared.imageHeight) else { return nil }
        return prepared
    }

    static func store(_ prepared: PreparedFrame, for frame: URL) throws {
        let identity = try sourceIdentity(for: frame)
        guard prepared.sourceByteCount == identity.bytes,
              prepared.sourceModifiedAt == identity.modifiedAt else { return }
        let url = cacheURL(for: frame)
        // Do not recreate a discarded session or replace its original images.
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(prepared).write(to: url, options: .atomic)
    }
}

/// Capturing never waits for analysis. At most two compressed frames are kept
/// in flight; overload or any cache failure falls back to the original JPEG.
final class FramePreprocessor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.gaoyiming.longshot.frame-preparation", qos: .utility)
    private let lock = NSLock()
    private var pendingCount = 0
    private let prepare: @Sendable (Data, URL) throws -> Void

    init(prepare: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
        let prepared = try FrameStitcher().prepareFrame(at: url, encodedData: data)
        try FramePreparationCache.store(prepared, for: url)
    }) {
        self.prepare = prepare
    }

    @discardableResult
    func enqueue(_ data: Data, for frame: URL) -> Bool {
        lock.lock()
        guard pendingCount < 2 else { lock.unlock(); return false }
        pendingCount += 1
        lock.unlock()
        queue.async { [self] in
            autoreleasepool { try? prepare(data, frame) }
            lock.lock()
            pendingCount -= 1
            lock.unlock()
        }
        return true
    }

#if LONGSHOT_CAPTURE_CHECKS
    // Only fixtures wait. Production finalization always falls back immediately.
    func waitForTesting() { queue.sync {} }
#endif
}
