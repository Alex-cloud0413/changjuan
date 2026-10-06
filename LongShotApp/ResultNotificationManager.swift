import Foundation
import UIKit
import UserNotifications

@MainActor
final class ResultNotificationManager {
    nonisolated static let sessionIDKey = "longshot-session-id"

    private let center = UNUserNotificationCenter.current()
    private let pendingKey = "longshot.pendingResultNotification.v1"
    private var postingSessionIDs = Set<String>()
    private var authorizationPreparationInFlight = false

    var pendingSessionID: String? { UserDefaults.standard.string(forKey: pendingKey) }

    /// Call from normal foreground setup, never from a capture intent. Recheck
    /// visibility and capture state after the asynchronous settings read so a
    /// delayed activation cannot put a permission sheet over capture startup.
    func prepareAuthorizationIfNeeded() async {
#if targetEnvironment(simulator)
        // Simulator runs are for UI verification and App Store screenshots; a system
        // notification prompt would obscure the first-run guide without testing delivery.
        return
#endif
        guard !authorizationPreparationInFlight else { return }
        authorizationPreparationInFlight = true
        defer { authorizationPreparationInFlight = false }

        var settings = await center.notificationSettings()
        var snapshot = makeSettingsSnapshot(settings, outcome: "checked")
        guard settings.authorizationStatus == .notDetermined else {
            snapshot.outcome = settings.authorizationStatus == .denied
                ? "permissionDenied" : "authorizationAlreadyDetermined"
            recordSettings(snapshot)
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            snapshot.outcome = "deferredUntilActive"
            recordSettings(snapshot)
            return
        }
        switch CaptureCommandStore.phase {
        case .choosing, .capturing, .paused, .processing:
            snapshot.outcome = "deferredWhileBusy"
            recordSettings(snapshot)
            return
        case .idle, .saved, .failed:
            break
        }

        snapshot.authorizationRequested = true
        snapshot.outcome = "requestingAuthorization"
        recordSettings(snapshot)
        var authorizationError: Error?
        do {
            _ = try await center.requestAuthorization(options: [.alert])
        } catch {
            authorizationError = error
        }
        settings = await center.notificationSettings()
        snapshot = makeSettingsSnapshot(
            settings,
            outcome: authorizationError != nil ? "authorizationRequestFailed"
                : settings.authorizationStatus == .denied ? "permissionDenied"
                : "authorizationRequestCompleted"
        )
        snapshot.authorizationRequested = true
        if let authorizationError {
            let error = authorizationError as NSError
            snapshot.authorizationErrorDomain = error.domain
            snapshot.authorizationErrorCode = error.code
        }
        recordSettings(snapshot)
    }

    /// Reads current system settings without displaying a prompt or changing
    /// preferences. The snapshot is also available before any capture is saved.
    @discardableResult
    func refreshSettingsSnapshot() async -> ResultNotificationSettingsSnapshot {
        let settings = await center.notificationSettings()
        let snapshot = makeSettingsSnapshot(settings, outcome: "refreshed")
        recordSettings(snapshot)
        return snapshot
    }

    func postSavedResult(
        image: UIImage?,
        sessionURL: URL,
        sessionID: String,
        pageCount: Int,
        mayRequestAuthorization: Bool = false
    ) async {
        guard postingSessionIDs.insert(sessionID).inserted else { return }
        defer { postingSessionIDs.remove(sessionID) }
        var settings = await center.notificationSettings()
        recordSettings(makeSettingsSnapshot(settings, outcome: "checkedBeforeResult"))
        var diagnostic = ResultNotificationDiagnostic(
            sessionID: sessionID,
            applicationState: UIApplication.shared.applicationState.rawValue,
            authorizationStatus: settings.authorizationStatus.rawValue,
            alertSetting: settings.alertSetting.rawValue,
            alertStyle: settings.alertStyle.rawValue,
            notificationCenterSetting: settings.notificationCenterSetting.rawValue
        )
        if settings.authorizationStatus == .notDetermined {
            guard mayRequestAuthorization, UIApplication.shared.applicationState == .active else {
                UserDefaults.standard.set(sessionID, forKey: pendingKey)
                diagnostic.outcome = "deferredUntilActive"
                record(diagnostic)
                return
            }
            diagnostic.authorizationRequested = true
            do {
                _ = try await center.requestAuthorization(options: [.alert])
            } catch {
                diagnostic.authorizationError = NotificationDiagnosticError(error)
            }
            settings = await center.notificationSettings()
            recordSettings(makeSettingsSnapshot(settings, outcome: "checkedAfterResultAuthorization"))
            diagnostic.authorizationStatus = settings.authorizationStatus.rawValue
            diagnostic.alertSetting = settings.alertSetting.rawValue
            diagnostic.alertStyle = settings.alertStyle.rawValue
            diagnostic.notificationCenterSetting = settings.notificationCenterSetting.rawValue
        }
        clearPending(sessionID: sessionID)
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
            diagnostic.outcome = settings.authorizationStatus == .denied ? "permissionDenied" : "permissionUnavailable"
            record(diagnostic)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = pageCount > 1 ? "长卷已保存为 \(pageCount) 张长图" : "长卷已保存"
        content.body = "轻点预览刚刚生成的长图"
        content.threadIdentifier = "longshot-results"
        content.userInfo = [Self.sessionIDKey: sessionID]

        if let image {
            do {
                let previewURL = try writeNotificationPreview(image, to: sessionURL)
                content.attachments = [try UNNotificationAttachment(
                    identifier: "longshot-preview", url: previewURL
                )]
                diagnostic.attachmentCreated = true
            } catch {
                diagnostic.attachmentError = NotificationDiagnosticError(error)
            }
        }

        let request = UNNotificationRequest(
            identifier: "longshot.saved.\(sessionID)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            diagnostic.requestEnqueued = true
            diagnostic.outcome = settings.authorizationStatus == .provisional
                || settings.alertSetting != .enabled || settings.alertStyle == .none
                ? "enqueuedWithoutGuaranteedBanner" : "enqueued"
        } catch {
            diagnostic.enqueueError = NotificationDiagnosticError(error)
            diagnostic.outcome = "enqueueFailed"
        }
        record(diagnostic)
    }

    func clearPending(sessionID: String) {
        if pendingSessionID == sessionID {
            UserDefaults.standard.removeObject(forKey: pendingKey)
        }
    }

    private func record(_ diagnostic: ResultNotificationDiagnostic) {
        do {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(diagnostic).write(
                to: directory.appendingPathComponent("LongShotResultNotificationDiagnostics.json"),
                options: .atomic
            )
        } catch { /* Notification diagnostics must never change Photos save status. */ }
    }

    private func makeSettingsSnapshot(
        _ settings: UNNotificationSettings,
        outcome: String
    ) -> ResultNotificationSettingsSnapshot {
        ResultNotificationSettingsSnapshot(
            applicationState: UIApplication.shared.applicationState.rawValue,
            authorizationStatus: settings.authorizationStatus.rawValue,
            alertsEnabled: settings.alertSetting == .enabled,
            alertSetting: settings.alertSetting.rawValue,
            alertStyle: settings.alertStyle.rawValue,
            notificationCenterSetting: settings.notificationCenterSetting.rawValue,
            configuredForBanner: (settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .ephemeral)
                && settings.alertSetting == .enabled && settings.alertStyle != .none,
            outcome: outcome
        )
    }

    private func recordSettings(_ snapshot: ResultNotificationSettingsSnapshot) {
        do {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(
                to: directory.appendingPathComponent("LongShotNotificationSettings.json"),
                options: .atomic
            )
        } catch { /* Reading notification settings must not interrupt the app. */ }
    }

    private func writeNotificationPreview(_ image: UIImage, to sessionURL: URL) throws -> URL {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            throw PreviewError.invalidImage
        }

        let previewWidth = min(CGFloat(900), sourceSize.width)
        let scale = previewWidth / sourceSize.width
        let sourceCropHeight = min(sourceSize.height, sourceSize.width * 0.78)
        let previewSize = CGSize(width: previewWidth, height: sourceCropHeight * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let preview = UIGraphicsImageRenderer(size: previewSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: previewSize))
            image.draw(
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: previewWidth,
                    height: sourceSize.height * scale
                )
            )
        }

        guard let data = preview.jpegData(compressionQuality: 0.86) else {
            throw PreviewError.encodingFailed
        }
        let url = sessionURL.appendingPathComponent("notification-preview.jpg")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Settings describe eligibility for a banner, not proof of delivery: Focus and
/// other system presentation choices still apply. No image or capture content
/// is included in this diagnostic snapshot.
struct ResultNotificationSettingsSnapshot: Codable {
    var recordedAt = Date()
    let applicationState: Int
    let authorizationStatus: Int
    let alertsEnabled: Bool
    let alertSetting: Int
    let alertStyle: Int
    let notificationCenterSetting: Int
    let configuredForBanner: Bool
    var authorizationRequested = false
    var authorizationErrorDomain: String?
    var authorizationErrorCode: Int?
    var outcome: String
}

/// Persistent, one-result handoff. Opening the app repeatedly cannot replay an
/// acknowledged result, while an interrupted save presentation remains pending.
struct SavedResultPresentationState: Codable, Equatable {
    var pendingSessionID: String?
    var acknowledgedSessionID: String?
    var hasConsideredExistingResult = false

    mutating func enqueue(sessionID: String) {
        hasConsideredExistingResult = true
        if acknowledgedSessionID != sessionID { pendingSessionID = sessionID }
    }

    mutating func considerExistingResult(sessionID: String?) {
        guard !hasConsideredExistingResult else { return }
        hasConsideredExistingResult = true
        if let sessionID, acknowledgedSessionID != sessionID {
            pendingSessionID = sessionID
        }
    }

    mutating func acknowledge(sessionID: String) {
        if pendingSessionID == sessionID { pendingSessionID = nil }
        acknowledgedSessionID = sessionID
        hasConsideredExistingResult = true
    }
}

struct SavedResultPresentationStore {
    private let defaults: UserDefaults
    private let key = "longshot.savedResultPresentation.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var state: SavedResultPresentationState {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(SavedResultPresentationState.self, from: data) else {
            return SavedResultPresentationState()
        }
        return value
    }

    func enqueue(sessionID: String) { update { $0.enqueue(sessionID: sessionID) } }
    func considerExistingResult(sessionID: String?) {
        update { $0.considerExistingResult(sessionID: sessionID) }
    }
    func acknowledge(sessionID: String) { update { $0.acknowledge(sessionID: sessionID) } }

    private func update(_ mutation: (inout SavedResultPresentationState) -> Void) {
        var value = state
        mutation(&value)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

private struct NotificationDiagnosticError: Codable {
    let domain: String
    let code: Int

    init(_ error: Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
    }
}

private struct ResultNotificationDiagnostic: Codable {
    let sessionID: String
    var recordedAt = Date()
    let applicationState: Int
    var authorizationStatus: Int
    var alertSetting: Int
    var alertStyle: Int
    var notificationCenterSetting: Int
    var authorizationRequested = false
    var authorizationError: NotificationDiagnosticError?
    var attachmentCreated = false
    var attachmentError: NotificationDiagnosticError?
    var requestEnqueued = false
    var enqueueError: NotificationDiagnosticError?
    var outcome = "notAttempted"
}

private enum PreviewError: Error {
    case invalidImage
    case encodingFailed
}
