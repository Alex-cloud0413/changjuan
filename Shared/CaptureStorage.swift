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
}
