import Foundation

enum CaptureStorageError: LocalizedError {
    case appGroupUnavailable(String)
    case invalidManifest(URL)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let identifier):
            return "无法访问本地共享空间（\(identifier)）。请检查两个 Target 的 App Group 是否一致。"
        case .invalidManifest(let url):
            return "录制记录损坏：\(url.lastPathComponent)"
        }
    }
}

enum CaptureStorage {
    // Cache commits and reclamation share a short file-system critical section.
    // A queued preprocessor must not recreate Analysis-v1 after a successful save.
    private static let frameCacheLock = NSLock()

    static func withFrameCacheMutation<T>(_ body: () throws -> T) rethrows -> T {
        frameCacheLock.lock()
        defer { frameCacheLock.unlock() }
        return try body()
    }
#if LONGSHOT_CAPTURE_CHECKS
    // Standalone regression checks use their own temporary directory, never
    // the installed app's recordings or App Group status.
    nonisolated(unsafe) static var testContainerURL: URL?
#endif

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func containerURL() throws -> URL {
#if LONGSHOT_CAPTURE_CHECKS
        if let testContainerURL { return testContainerURL }
#endif
        let identifier = CaptureConstants.appGroupIdentifier
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
#if targetEnvironment(simulator)
            let fallback = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("LongJuanSimulator", isDirectory: true)
            try FileManager.default.createDirectory(
                at: fallback,
                withIntermediateDirectories: true
            )
            return fallback
#else
            throw CaptureStorageError.appGroupUnavailable(identifier)
#endif
        }
        return url
    }

    static func sessionsDirectory() throws -> URL {
        let url = try containerURL().appendingPathComponent(
            CaptureConstants.sessionsDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func createSession() throws -> (URL, CaptureManifest) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let id = "\(timestamp)-\(UUID().uuidString.lowercased())"
        let url = try sessionsDirectory().appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let manifest = CaptureManifest(
            id: id,
            startedAt: Date(),
            completedAt: nil,
            frameCount: 0,
            state: .capturing,
            autoStopped: false,
            failureMessage: nil
        )
        try write(manifest, to: url)
        return (url, manifest)
    }

    static func write(_ manifest: CaptureManifest, to sessionURL: URL) throws {
        let data = try encoder.encode(manifest)
        try data.write(
            to: sessionURL.appendingPathComponent(CaptureConstants.manifestFileName),
            options: .atomic
        )
        try data.write(
            to: containerURL().appendingPathComponent(CaptureConstants.latestStatusFileName),
            options: .atomic
        )
    }

    static func readManifest(at sessionURL: URL) throws -> CaptureManifest {
        let url = sessionURL.appendingPathComponent(CaptureConstants.manifestFileName)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? decoder.decode(CaptureManifest.self, from: data) else {
            throw CaptureStorageError.invalidManifest(url)
        }
        return manifest
    }

    static func allSessions() throws -> [(url: URL, manifest: CaptureManifest)] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: sessionsDirectory(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url in
            guard let manifest = try? readManifest(at: url) else { return nil }
            return (url, manifest)
        }
        .sorted { $0.manifest.startedAt > $1.manifest.startedAt }
    }

    static func frameURL(index: Int, sessionURL: URL) -> URL {
        let name = String(format: "%@%06d.%@", CaptureConstants.framePrefix, index, CaptureConstants.frameExtension)
        return sessionURL.appendingPathComponent(name)
    }

    static func frameURLs(in sessionURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: sessionURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter {
            $0.lastPathComponent.hasPrefix(CaptureConstants.framePrefix)
                && $0.pathExtension.lowercased() == CaptureConstants.frameExtension
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func outputsDirectory(in sessionURL: URL) throws -> URL {
        let url = sessionURL.appendingPathComponent(
            CaptureConstants.outputsDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func existingOutputs(in sessionURL: URL) -> [URL] {
        let url = sessionURL.appendingPathComponent(CaptureConstants.outputsDirectoryName, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files
            .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func hasSavedOutputsToPhotos(in sessionURL: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: sessionURL.appendingPathComponent(
                CaptureConstants.savedToPhotosMarkerName
            ).path
        )
    }

    static func markOutputsSavedToPhotos(in sessionURL: URL) throws {
        try Data().write(
            to: sessionURL.appendingPathComponent(
                CaptureConstants.savedToPhotosMarkerName
            ),
            options: .atomic
        )
    }

    static func hasDiscardedRawFrames(in sessionURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: sessionURL.appendingPathComponent(".raw-frames-cleared").path)
    }
}

/// Only a completed session with a durable Photos-success marker is disposable.
/// Failed, interrupted, unrecognised and unsaved recordings are never age-pruned.
enum SavedCaptureCleanup {
#if LONGSHOT_CAPTURE_CHECKS
    nonisolated(unsafe) static var testAfterRetirement: ((URL) throws -> Void)?
#endif
    struct Policy {
        var maximumAge: TimeInterval = 7 * 24 * 60 * 60
        var maximumCount = 10
        var maximumBytes: Int64 = 100_000_000
    }

    struct Report: Sendable {
        var removedSessionIDs: [String] = []
        var clearedRawSessionIDs: [String] = []
        var reclaimedBytes: Int64 = 0
        var failures = 0
        var retainedCount = 0
        var retainedBytes: Int64 = 0
        var cancelled = false
    }

    private static let trashName = ".saved-preview-trash"

    /// Explicit destructive action only. The model must exclude recording and
    /// processing for the whole operation; unlike automatic cleanup this also
    /// removes unsaved inputs after the user confirms the loss of recovery.
    static func clearAllRawCaches() -> Report {
        var report = Report()
        let files = FileManager.default
        do {
            let root = try CaptureStorage.sessionsDirectory()
            guard try isDirectory(root) else { report.failures += 1; return report }
            for url in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                do {
                    guard try isDirectory(url),
                          try isRegularFile(url.appendingPathComponent(CaptureConstants.manifestFileName)),
                          let manifest = try? CaptureStorage.readManifest(at: url), manifest.id == url.lastPathComponent else {
                        // Report incomplete cleanup rather than claiming unknown
                        // or corrupt sessions were cleared. Never guess ownership.
                        report.failures += 1
                        continue
                    }
                    try CaptureStorage.withFrameCacheMutation {
                        _ = try treeBytes(url)
                        let rawFiles = try files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).filter {
                            try $0.lastPathComponent == "Analysis-v1" ||
                            ($0.lastPathComponent.hasPrefix(CaptureConstants.framePrefix)
                             && $0.pathExtension.lowercased() == CaptureConstants.frameExtension && isRegularFile($0))
                        }
                        guard !rawFiles.isEmpty else { return }
                        // Persist before deleting: a crash cannot later mistake
                        // a deliberately emptied recording for recoverable work.
                        try Data().write(to: url.appendingPathComponent(".raw-frames-cleared"), options: .atomic)
                        report.clearedRawSessionIDs.append(manifest.id)
                        for raw in rawFiles {
                            let bytes = try treeBytes(raw)
                            try files.removeItem(at: raw)
                            report.reclaimedBytes += bytes
                        }
                    }
                } catch { report.failures += 1 }
            }
        } catch { report.failures += 1 }
        return report
    }

    static func run(
        protectedSessionIDs: Set<String> = [], now: Date = Date(), policy: Policy = Policy(),
        shouldCancel: () -> Bool = { Task.isCancelled }
    ) -> Report {
        var report = Report()
        let files = FileManager.default
        do {
            let root = try CaptureStorage.sessionsDirectory()
            guard try isDirectory(root) else { return report }
            let trash = root.appendingPathComponent(trashName, isDirectory: true)
            // Retirement is an atomic move. A crash during removal leaves only
            // disposable files here, never a session that can be reprocessed.
            if files.fileExists(atPath: trash.path) {
                guard try isDirectory(trash) else { return report }
                for retired in try files.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
                    if shouldCancel() { report.cancelled = true; return report }
                    guard retired.lastPathComponent.hasPrefix("retired-"),
                          UUID(uuidString: String(retired.lastPathComponent.dropFirst(8))) != nil else { continue }
                    do {
                        let bytes = try treeBytes(retired)
                        try files.removeItem(at: retired)
                        report.reclaimedBytes += bytes
                    } catch { report.failures += 1 }
                }
            }

            var retained: [(url: URL, id: String, savedAt: Date, bytes: Int64)] = []
            for url in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                if shouldCancel() { report.cancelled = true; return report }
                do {
                    guard try isDirectory(url),
                          try isRegularFile(url.appendingPathComponent(CaptureConstants.manifestFileName)),
                          let manifest = try? CaptureStorage.readManifest(at: url),
                          manifest.id == url.lastPathComponent, manifest.state == .complete else { continue }
                    // An occluded partial output is not a complete backup. Keep
                    // the entire source until the user's explicit cache clearing.
                    guard manifest.omittedOccludedBottomRows != true
                        || CaptureStorage.hasDiscardedRawFrames(in: url) else { continue }
                    let marker = url.appendingPathComponent(CaptureConstants.savedToPhotosMarkerName)
                    guard try isRegularFile(marker) else { continue }
                    // Validate the whole tree before any mutation. Do not follow
                    // symlinks, including links inside the analysis/output folders.
                    _ = try treeBytes(url)
                    let savedAt = (try files.attributesOfItem(atPath: marker.path)[.modificationDate] as? Date)
                        ?? manifest.completedAt ?? manifest.startedAt
                    try CaptureStorage.withFrameCacheMutation {
                        for child in try files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                            if shouldCancel() { return }
                            let name = child.lastPathComponent
                            let isFrame = try name.hasPrefix(CaptureConstants.framePrefix)
                                && child.pathExtension.lowercased() == CaptureConstants.frameExtension
                                && isRegularFile(child)
                            guard isFrame || name == "Analysis-v1" else { continue }
                            let bytes = try treeBytes(child)
                            try files.removeItem(at: child)
                            report.reclaimedBytes += bytes
                        }
                    }
                    retained.append((url, manifest.id, savedAt, try treeBytes(url)))
                } catch { report.failures += 1 }
            }
            retained.sort { $0.savedAt == $1.savedAt ? $0.id > $1.id : $0.savedAt > $1.savedAt }
            report.retainedCount = retained.count
            report.retainedBytes = retained.reduce(0) { $0 + $1.bytes }
            for item in retained.reversed() {
                if shouldCancel() { report.cancelled = true; return report }
                // A visible preview/thumbnail may temporarily exceed the limits;
                // closing it schedules another pass. No image is cut off on screen.
                guard !protectedSessionIDs.contains(item.id) else { continue }
                let expired = now.timeIntervalSince(item.savedAt) >= policy.maximumAge
                guard expired || report.retainedCount > policy.maximumCount
                    || report.retainedBytes > policy.maximumBytes else { continue }
                do {
                    // Recheck eligibility immediately before retiring. Never infer
                    // a successful Photos save from manifest.savedToPhotos alone.
                    let current = try CaptureStorage.readManifest(at: item.url)
                    guard current.state == .complete,
                          current.omittedOccludedBottomRows != true || CaptureStorage.hasDiscardedRawFrames(in: item.url),
                          try isRegularFile(item.url.appendingPathComponent(CaptureConstants.savedToPhotosMarkerName)) else { continue }
                    if !files.fileExists(atPath: trash.path) {
                        try files.createDirectory(at: trash, withIntermediateDirectories: false)
                    }
                    guard try isDirectory(trash) else { continue }
                    let destination = trash.appendingPathComponent("retired-" + UUID().uuidString, isDirectory: true)
                    try files.moveItem(at: item.url, to: destination)
                    report.removedSessionIDs.append(item.id)
                    report.retainedCount -= 1
                    report.retainedBytes -= item.bytes
#if LONGSHOT_CAPTURE_CHECKS
                    try testAfterRetirement?(destination)
#endif
                    try files.removeItem(at: destination)
                    report.reclaimedBytes += item.bytes
                } catch { report.failures += 1 }
            }
        } catch { report.failures += 1 }
        return report
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory
    }

    private static func isRegularFile(_ url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular
    }

    private static func treeBytes(_ url: URL) throws -> Int64 {
        let files = FileManager.default
        let attributes = try files.attributesOfItem(atPath: url.path)
        switch attributes[.type] as? FileAttributeType {
        case .typeRegular:
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        case .typeDirectory:
            return try files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .reduce(Int64(0)) { try $0 + treeBytes($1) }
        default:
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }
}
