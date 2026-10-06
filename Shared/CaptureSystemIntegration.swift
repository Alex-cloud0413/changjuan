import ActivityKit
import AppIntents
import Foundation

enum CaptureSurfacePhase: String, Codable, Hashable, Sendable {
    case idle
    case choosing
    case capturing
    case paused
    case processing
    case saved
    case failed
}

struct LongScrollActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: CaptureSurfacePhase
        var frameCount: Int
        var pageCount: Int
    }

    var sessionID: String
}

enum CaptureSystem {
    static let controlKind = "com.gaoyiming.longshot.capture-control"
    static let pageControlKind = "com.gaoyiming.longshot.next-page"

    static var appGroupIdentifier: String {
        guard let identifier = Bundle.main.object(
            forInfoDictionaryKey: "LongShotAppGroupIdentifier"
        ) as? String,
        !identifier.isEmpty,
        !identifier.contains("$(") else {
            return "group.com.gaoyiming.longshot.private"
        }
        return identifier
    }
}

#if !LONGSHOT_SCREEN_CAPTURE_KIT
/// Legacy cross-process ReplayKit state. It is excluded from the iOS 27
/// ScreenCaptureKit product and kept only as source history.
enum ReplayBroadcastStore {
    struct Request: Codable, Sendable {
        var id: String
        var createdAt: Date
        var topCropRatio: Double
    }

    struct Status: Codable, Sendable {
        var requestID: String?
        var sessionID: String
        var phase: CaptureSurfacePhase
        var frameCount: Int
        var videoSampleCount: Int
        var ignoredHostFrameCount: Int
        var updatedAt: Date
        var failureMessage: String?
    }

    private struct FinishRequest: Codable {
        var sessionID: String
    }

    private struct HostVisibility: Codable {
        var isForeground: Bool
    }

    private enum StoreError: LocalizedError {
        case sharedContainerUnavailable

        var errorDescription: String? {
            "无法访问本机录制共享空间，请重新打开长卷后重试。"
        }
    }

    static func prepare(topCropRatio: Double) throws -> Request {
        let directory = try directoryURL(createIfNeeded: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        // Only our finish commands are removed. The extension owns status.json;
        // the app matches its request ID instead of resetting extension state.
        for file in files where file.lastPathComponent.hasPrefix("finish-")
            && file.pathExtension == "json" {
            do {
                try FileManager.default.removeItem(at: file)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && error.code == NSFileNoSuchFileError {
                // The extension may have consumed this command concurrently.
            }
        }
        let request = Request(
            id: UUID().uuidString,
            createdAt: Date(),
            topCropRatio: topCropRatio
        )
        try write(request, named: "request.json")
        return request
    }

    static func readRequest() -> Request? {
        guard let request: Request = read(named: "request.json"),
              Date().timeIntervalSince(request.createdAt) <= 120 else {
            return nil
        }
        return request
    }

    /// Only the broadcast extension writes status; both processes may read it.
    static func writeStatus(_ status: Status) throws {
        try write(status, named: "status.json")
    }

    static func readStatus() -> Status? {
        read(named: "status.json")
    }

    static func requestFinish(sessionID: String) throws {
        try write(
            FinishRequest(sessionID: sessionID),
            named: finishFileName(sessionID: sessionID)
        )
    }

    static func consumeFinish(sessionID: String) -> Bool {
        guard let directory = try? directoryURL(createIfNeeded: false) else {
            return false
        }
        let source = directory.appendingPathComponent(finishFileName(sessionID: sessionID))
        let claimed = directory.appendingPathComponent(".consumed-\(UUID().uuidString).json")
        do {
            // A same-directory rename claims the command atomically. Concurrent
            // consumers cannot both read and act on the same finish request.
            try FileManager.default.moveItem(at: source, to: claimed)
            defer { try? FileManager.default.removeItem(at: claimed) }
            let request = try JSONDecoder().decode(
                FinishRequest.self,
                from: Data(contentsOf: claimed)
            )
            return request.sessionID == sessionID
        } catch {
            return false
        }
    }

    static func setHostForeground(_ isForeground: Bool) {
        try? write(HostVisibility(isForeground: isForeground), named: "host-visibility.json")
    }

    static var isHostForeground: Bool {
        let visibility: HostVisibility? = read(named: "host-visibility.json")
        return visibility?.isForeground ?? false
    }

    private static func finishFileName(sessionID: String) -> String {
        // Encode rather than interpolate an ID into a filesystem path.
        let encodedID = sessionID.utf8.map { String(format: "%02x", $0) }.joined()
        return "finish-\(encodedID).json"
    }

    private static func directoryURL(createIfNeeded: Bool) throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CaptureSystem.appGroupIdentifier
        ) else {
            throw StoreError.sharedContainerUnavailable
        }
        let directory = container.appendingPathComponent("replay-broadcast", isDirectory: true)
        if createIfNeeded {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return directory
    }

    private static func write<Value: Encodable>(_ value: Value, named name: String) throws {
        let url = try directoryURL(createIfNeeded: true).appendingPathComponent(name)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private static func read<Value: Decodable>(named name: String) -> Value? {
        guard let directory = try? directoryURL(createIfNeeded: false),
              let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else {
            return nil
        }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
#endif

enum CaptureCommandStore {
    static let startRequested = Notification.Name("LongShotStartRequested")
    static let finishRequested = Notification.Name("LongShotFinishRequested")

    private static let startRequestKey = "system-command.start-request"
    private static let finishRequestKey = "system-command.finish-request"
    private static let phaseKey = "system-command.phase"
    private static let frameCountKey = "system-command.frame-count"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: CaptureSystem.appGroupIdentifier) ?? .standard
    }

    static func requestStart() {
        defaults.set(UUID().uuidString, forKey: startRequestKey)
        defaults.removeObject(forKey: finishRequestKey)
        NotificationCenter.default.post(name: startRequested, object: nil)
    }

    static func consumeStartRequest() -> Bool {
        guard defaults.string(forKey: startRequestKey) != nil else { return false }
        defaults.removeObject(forKey: startRequestKey)
        return true
    }

    static func requestFinish() {
        defaults.set(UUID().uuidString, forKey: finishRequestKey)
#if !LONGSHOT_SCREEN_CAPTURE_KIT
        if let status = ReplayBroadcastStore.readStatus(), status.phase == .capturing {
            try? ReplayBroadcastStore.requestFinish(sessionID: status.sessionID)
        }
#endif
        NotificationCenter.default.post(name: finishRequested, object: nil)
    }

    static func consumeFinishRequest() -> Bool {
        guard defaults.string(forKey: finishRequestKey) != nil else { return false }
        defaults.removeObject(forKey: finishRequestKey)
        return true
    }

    static func clearFinishRequest() {
        defaults.removeObject(forKey: finishRequestKey)
    }

    static func setState(_ phase: CaptureSurfacePhase, frameCount: Int = 0) {
        defaults.set(phase.rawValue, forKey: phaseKey)
        defaults.set(frameCount, forKey: frameCountKey)
    }

    static var phase: CaptureSurfacePhase {
        guard let rawValue = defaults.string(forKey: phaseKey),
              let phase = CaptureSurfacePhase(rawValue: rawValue) else {
            return .idle
        }
        return phase
    }

    static var isCapturing: Bool {
        phase == .capturing || phase == .paused
    }
}

struct ToggleLongScrollIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "开始或完成长卷"
#if LONGSHOT_SCREEN_CAPTURE_KIT
    static let description = IntentDescription("在当前界面请求系统屏幕共享；捕获中再次轻点即可完成。")
    static let openAppWhenRun = false
    static var supportedModes: IntentModes { .background }
#else
    static let description = IntentDescription("打开长卷的系统录制确认；捕获中再次轻点即可完成。")
    static let openAppWhenRun = true
#endif

    func perform() async throws -> some IntentResult {
#if LONGSHOT_SCREEN_CAPTURE_KIT
#if LONGSHOT_MAIN_APP
        // LiveActivityIntent runs in the app process even when its control is
        // rendered by the widget extension. Keep this invocation alive until
        // the system picker resolves and capture starts, cancels, or fails.
        try await AppModel.shared.performSystemCaptureAction(finishOnly: false)
#endif
#else
        if let status = ReplayBroadcastStore.readStatus(),
           status.phase == .capturing,
           Date().timeIntervalSince(status.updatedAt) < 15 {
            CaptureCommandStore.requestFinish()
            return .result()
        }
        switch CaptureCommandStore.phase {
        case .capturing, .paused:
            // A previous crash or Build 20 session may leave the UI defaults
            // stuck in capturing. Only fresh extension status authorizes finish.
            CaptureCommandStore.requestStart()
        case .idle, .saved, .failed:
            CaptureCommandStore.requestStart()
        case .choosing, .processing:
            break
        }
#endif
        return .result()
    }
}

struct FinishLongScrollIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "完成长卷"
    static let description = IntentDescription("立即结束捕获并在后台生成长图。")
#if LONGSHOT_SCREEN_CAPTURE_KIT
    static let openAppWhenRun = false
    static var supportedModes: IntentModes { .background }
#else
    static let openAppWhenRun = true
#endif

    func perform() async throws -> some IntentResult {
#if LONGSHOT_SCREEN_CAPTURE_KIT
#if LONGSHOT_MAIN_APP
        try await AppModel.shared.performSystemCaptureAction(finishOnly: true)
#endif
#else
        CaptureCommandStore.requestFinish()
#endif
        return .result()
    }
}

/// An explicit boundary, not a guess based on unrelated pixels. The stream
/// remains authorized while app-switch animations are excluded from capture.
struct NextLongScrollPageIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "接下一页或继续收卷"
    static let description = IntentDescription("暂停采集以切换页面，在新页面轻点继续。")
    static let openAppWhenRun = false
#if LONGSHOT_SCREEN_CAPTURE_KIT
    static var supportedModes: IntentModes { .background }
#endif

    func perform() async throws -> some IntentResult {
#if LONGSHOT_SCREEN_CAPTURE_KIT && LONGSHOT_MAIN_APP
        await AppModel.shared.togglePageTransition()
#endif
        return .result()
    }
}
