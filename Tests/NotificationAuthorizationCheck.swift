import Foundation

// Run with: node Tests/check-notification-authorization.mjs
// The runner extracts the actual production authorization methods and redirects
// only their Documents output to a temporary folder. These fixtures replace iOS
// UI/notification services, so no permission prompt or user setting is touched.
enum UNAuthorizationStatus: Int { case notDetermined, denied, authorized, provisional, ephemeral }
enum UNNotificationSetting: Int { case notSupported, disabled, enabled }
enum UNAlertStyle: Int { case none, banner, alert }
struct UNAuthorizationOptions: OptionSet {
    let rawValue: Int
    static let alert = Self(rawValue: 1)
    static let sound = Self(rawValue: 2)
    static let badge = Self(rawValue: 4)
}
struct UNNotificationSettings {
    var authorizationStatus: UNAuthorizationStatus
    var alertSetting = UNNotificationSetting.enabled
    var alertStyle = UNAlertStyle.banner
    var notificationCenterSetting = UNNotificationSetting.enabled
}
@MainActor
final class UNUserNotificationCenter {
    var settings: UNNotificationSettings
    var resultStatus = UNAuthorizationStatus.authorized
    var requestCalls = 0
    var requestedOptions: UNAuthorizationOptions?
    var requestError: Error?
    var onRead: (() -> Void)?
    var onRequest: (() async -> Void)?

    init(status: UNAuthorizationStatus) { settings = .init(authorizationStatus: status) }
    func notificationSettings() async -> UNNotificationSettings {
        onRead?()
        return settings
    }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestCalls += 1
        requestedOptions = options
        await onRequest?()
        if let requestError { throw requestError }
        settings.authorizationStatus = resultStatus
        return resultStatus == .authorized
    }
}
enum CaptureSurfacePhase { case idle, choosing, capturing, paused, processing, saved, failed }
@MainActor
enum CaptureCommandStore { static var phase = CaptureSurfacePhase.idle }
@MainActor
final class UIApplication {
    enum State: Int { case active, inactive, background }
    static let shared = UIApplication()
    var applicationState = State.active
}
@MainActor
final class RequestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

@main
@MainActor
struct NotificationAuthorizationCheck {
    static func main() async throws {
        try await deniedIsNeverRequestedAgain()
        try await determinedStatesAreReadOnly()
        try await onlyIdleForegroundRequestsAlert()
        try await backgroundAndInactiveNeverPrompt()
        try await captureWorkNeverPrompts()
        try await settingsReadRechecksVisibility()
        try await settingsReadRechecksCaptureState()
        try await duplicateActivationsShareOnePrompt()
        try await requestDenialIsRecorded()
        try await requestErrorIsMetadataOnly()
        try await explicitRefreshIsReadOnly()
        print("Notification authorization checks passed (11)")
    }

    private static func reset() {
        UIApplication.shared.applicationState = .active
        CaptureCommandStore.phase = .idle
    }

    private static func deniedIsNeverRequestedAgain() async throws {
        reset()
        let center = UNUserNotificationCenter(status: .denied)
        let manager = ResultNotificationManager(center: center)
        await manager.prepareAuthorizationIfNeeded()
        await manager.prepareAuthorizationIfNeeded()
        require(center.requestCalls == 0)
        let snapshot = try recordedSnapshot()
        require(snapshot.authorizationStatus == UNAuthorizationStatus.denied.rawValue)
        require(snapshot.outcome == "permissionDenied")
        require(!snapshot.authorizationRequested)
    }

    private static func determinedStatesAreReadOnly() async throws {
        for status in [UNAuthorizationStatus.authorized, .provisional, .ephemeral] {
            reset()
            let center = UNUserNotificationCenter(status: status)
            await ResultNotificationManager(center: center).prepareAuthorizationIfNeeded()
            require(center.requestCalls == 0)
            let snapshot = try recordedSnapshot()
            require(snapshot.configuredForBanner == (status != .provisional))
        }
    }

    private static func onlyIdleForegroundRequestsAlert() async throws {
        reset()
        let center = UNUserNotificationCenter(status: .notDetermined)
        await ResultNotificationManager(center: center).prepareAuthorizationIfNeeded()
        require(center.requestCalls == 1)
        require(center.requestedOptions == .alert)
        let snapshot = try recordedSnapshot()
        require(snapshot.authorizationRequested)
        require(snapshot.authorizationStatus == UNAuthorizationStatus.authorized.rawValue)
        require(snapshot.outcome == "authorizationRequestCompleted")
    }

    private static func backgroundAndInactiveNeverPrompt() async throws {
        for state in [UIApplication.State.inactive, .background] {
            reset()
            UIApplication.shared.applicationState = state
            let center = UNUserNotificationCenter(status: .notDetermined)
            await ResultNotificationManager(center: center).prepareAuthorizationIfNeeded()
            require(center.requestCalls == 0)
            require(try recordedSnapshot().outcome == "deferredUntilActive")
        }
    }

    private static func captureWorkNeverPrompts() async throws {
        for phase in [CaptureSurfacePhase.choosing, .capturing, .paused, .processing] {
            reset()
            CaptureCommandStore.phase = phase
            let center = UNUserNotificationCenter(status: .notDetermined)
            await ResultNotificationManager(center: center).prepareAuthorizationIfNeeded()
            require(center.requestCalls == 0)
            require(try recordedSnapshot().outcome == "deferredWhileBusy")
        }
    }

    private static func settingsReadRechecksVisibility() async throws {
        reset()
        let center = UNUserNotificationCenter(status: .notDetermined)
        center.onRead = { UIApplication.shared.applicationState = .background }
        await ResultNotificationManager(center: center).prepareAuthorizationIfNeeded()
        require(center.requestCalls == 0)
        require(try recordedSnapshot().outcome == "deferredUntilActive")
    }

    private static func settingsReadRechecksCaptureState() async throws {
        reset()
        let center = UNUserNotificationCenter(status: .notDetermined)
        center.onRead = { CaptureCommandStore.phase = .choosing }
        await ResultNotificationManager(center: center).prepareAuthorizationIfNeeded()
        require(center.requestCalls == 0)
        require(try recordedSnapshot().outcome == "deferredWhileBusy")
    }

    private static func duplicateActivationsShareOnePrompt() async throws {
        reset()
        let center = UNUserNotificationCenter(status: .notDetermined)
        let gate = RequestGate()
        center.onRequest = { await gate.wait() }
        let manager = ResultNotificationManager(center: center)
        let first = Task { await manager.prepareAuthorizationIfNeeded() }
        for _ in 0..<1000 where center.requestCalls == 0 { await Task.yield() }
        require(center.requestCalls == 1)
        require(try recordedSnapshot().outcome == "requestingAuthorization")
        await manager.prepareAuthorizationIfNeeded()
        require(center.requestCalls == 1)
        gate.release()
        await first.value
        require(try recordedSnapshot().outcome == "authorizationRequestCompleted")
    }

    private static func requestDenialIsRecorded() async throws {
        reset()
        let center = UNUserNotificationCenter(status: .notDetermined)
        center.resultStatus = .denied
        let manager = ResultNotificationManager(center: center)
        await manager.prepareAuthorizationIfNeeded()
        let snapshot = try recordedSnapshot()
        require(snapshot.authorizationRequested && snapshot.outcome == "permissionDenied")
        await manager.prepareAuthorizationIfNeeded()
        require(center.requestCalls == 1)
    }

    private static func requestErrorIsMetadataOnly() async throws {
        reset()
        let center = UNUserNotificationCenter(status: .notDetermined)
        center.requestError = NSError(domain: "TestAuthorization", code: 42,
                                      userInfo: [NSLocalizedDescriptionKey: "DO_NOT_SERIALIZE_THIS_TEXT"])
        await ResultNotificationManager(center: center).prepareAuthorizationIfNeeded()
        let snapshot = try recordedSnapshot()
        require(snapshot.authorizationErrorDomain == "TestAuthorization")
        require(snapshot.authorizationErrorCode == 42)
        require(snapshot.outcome == "authorizationRequestFailed")
        let text = try String(contentsOf: snapshotURL, encoding: .utf8)
        require(!text.contains("DO_NOT_SERIALIZE_THIS_TEXT"))
    }

    private static func explicitRefreshIsReadOnly() async throws {
        reset()
        let center = UNUserNotificationCenter(status: .notDetermined)
        center.settings.alertSetting = .disabled
        center.settings.alertStyle = .none
        let snapshot = await ResultNotificationManager(center: center).refreshSettingsSnapshot()
        require(center.requestCalls == 0)
        require(!snapshot.alertsEnabled && !snapshot.configuredForBanner)
        require(snapshot.outcome == "refreshed")
        let persisted = try recordedSnapshot()
        require(persisted.alertSetting == UNNotificationSetting.disabled.rawValue)
        require(persisted.outcome == "refreshed")
    }

    private static var snapshotURL: URL {
        URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .appendingPathComponent("LongShotNotificationSettings.json")
    }

    private static func recordedSnapshot() throws -> ResultNotificationSettingsSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResultNotificationSettingsSnapshot.self, from: Data(contentsOf: snapshotURL))
    }

    private static func require(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
        guard condition else { fatalError("Check failed", file: file, line: line) }
    }
}
