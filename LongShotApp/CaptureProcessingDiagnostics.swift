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
