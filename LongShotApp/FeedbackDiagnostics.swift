import CoreFoundation
import Darwin
import Foundation

/// Projects the selected capture's local journal onto the feedback schema.
enum FeedbackDiagnostics {
    struct Capture: Encodable, Sendable {
        let axis: Axis
        let keepsStatusBar: Bool
    }

    enum Axis: String, Encodable, Sendable {
        case vertical, horizontal
    }

    private struct Report: Encodable {
        let schemaVersion = 1
        let appVersion: String?
        let build: String?
        let osVersion: OSVersion
        let capture: Capture?
        var events: [Event]
    }

    private struct OSVersion: Encodable {
        let major: Int
        let minor: Int
        let patch: Int
    }

    private struct Event: Encodable {
        let event: EventCode
        let counts: [String: Int]?
        let elapsedSeconds: [String: Double]?
        let frameSize: FrameSize?
        let autoStopped: Bool?
    }

    private struct FrameSize: Encodable {
        let width: Int
        let height: Int
    }

    private enum EventCode: String, Encodable {
        case captureStarted, captureFinishStarted, captureQueueDrained, streamStopFinished
        case capturePipelineSnapshot, captureStopped, processingStarted, stitchingQueued, stitchingFinished
        case processingFailed, photosAuthorizationFinished, photosWriteStarted, photosWriteFinished
        case resultSaved, backgroundTimeExpired
    }

    private static let maximumJournalBytes = 512 * 1024
    private static let maximumJournalRecords = 240
    private static let maximumReportEvents = 32
    private static let maximumReportBytes = 16 * 1024

    static func makeReport(journalURL: URL, sessionID: String?, appVersion: String, build: String,
                           capture: Capture?) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var report = Report(appVersion: numericVersion(appVersion), build: numericVersion(build),
                            osVersion: OSVersion(major: os.majorVersion, minor: os.minorVersion, patch: os.patchVersion),
                            capture: capture, events: events(from: journalURL, sessionID: sessionID))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        while let data = try? encoder.encode(report) {
            if data.count <= maximumReportBytes { return String(decoding: data, as: UTF8.self) }
            guard !report.events.isEmpty else { break }
            report.events.removeFirst()
        }
        return #"{"schemaVersion":1,"events":[]}"#
    }

    private static func numericVersion(_ value: String) -> String? {
        guard value.utf8.count <= 24 else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ part in
            (1...9).contains(part.utf8.count) && part.utf8.allSatisfy { (48...57).contains($0) }
        }) else { return nil }
        return value
    }

    private static func readJournal(_ url: URL) -> Data? {
        guard url.isFileURL, url.host == nil || url.host == "localhost" else { return nil }
        let path = url.path
        guard !path.utf8.contains(0) else { return nil }
        // The OS exposes these two aliases for the app container and temp directory.
        // Bypass only those aliases so the open can reject other symlinks atomically.
        let local = path.hasPrefix("/var/") || path.hasPrefix("/tmp/")
            ? URL(fileURLWithPath: "/private" + path) : url
        let fd = local.withUnsafeFileSystemRepresentation { name in
            guard let name else { return Int32(-1) }
            return open(name, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW_ANY)
        }
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1,
              metadata.st_size > 0, metadata.st_size <= maximumJournalBytes,
              let data = try? handle.read(upToCount: maximumJournalBytes + 1),
              data.count <= maximumJournalBytes else { return nil }
        return data
    }

    private static func events(from url: URL, sessionID: String?) -> [Event] {
        guard let sessionID, !sessionID.isEmpty, sessionID.utf8.count <= 64,
              let data = readJournal(url),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        var result: [Event] = []
        for row in rows.suffix(maximumJournalRecords).reversed() {
            guard let row = row as? [String: Any], let owner = row["sessionID"] as? String,
                  owner.utf8.elementsEqual(sessionID.utf8),
                  let name = row["event"] as? String, let code = EventCode(rawValue: name) else { continue }
            result.append(project(row, code: code))
            if result.count == maximumReportEvents { break }
        }
        return Array(result.reversed())
    }

    private static func project(_ row: [String: Any], code: EventCode) -> Event {
        let countKeys: [String]
        let durationKeys: [String]
        switch code {
        case .capturePipelineSnapshot:
            countKeys = ["callbackCount", "invalidPTSCount", "nonfinitePTSCount", "backwardPTSCount", "repeatedPTSCount",
                         "ptsEpochChangeCount", "zeroDeltaFromSavedCount", "negativeDeltaFromSavedCount"]
            durationKeys = ["wallSeconds", "maximumPTSGap", "maximumCallbackGap"]
        case .captureStopped, .stitchingQueued:
            countKeys = ["frameCount"]
            durationKeys = []
        case .processingStarted:
            countKeys = ["frameCount", "inputPageCount"]
            durationKeys = ["captureStoppedToProcessingSeconds"]
        case .stitchingFinished:
            countKeys = ["preparedFrameCount", "fallbackFrameCount", "preparedAlignmentCount", "outputCount"]
            durationKeys = ["stitchDispatchDelaySeconds", "stitchReturnDelaySeconds", "stitchingSeconds", "samplingSeconds",
                            "selectionSeconds", "assemblySeconds", "renderingSeconds"]
        case .captureQueueDrained, .streamStopFinished, .photosAuthorizationFinished:
            countKeys = []
            durationKeys = ["seconds"]
        case .photosWriteStarted:
            countKeys = ["outputCount"]
            durationKeys = []
        case .photosWriteFinished:
            countKeys = []
            durationKeys = ["photosWriteSeconds", "photosCallbackResumeSeconds"]
        case .resultSaved:
            countKeys = []
            durationKeys = ["processingWallSeconds", "resultPersistenceSeconds"]
        case .captureStarted, .captureFinishStarted, .processingFailed, .backgroundTimeExpired:
            countKeys = []
            durationKeys = []
        }

        var counts: [String: Int] = [:]
        for key in countKeys { counts[key] = integer(row[key]) }
        var durations: [String: Double] = [:]
        for key in durationKeys {
            guard let seconds = number(row[key]), (0...86_400).contains(seconds) else { continue }
            durations[key] = (seconds * 1_000).rounded() / 1_000
        }
        var size: FrameSize?
        if code == .capturePipelineSnapshot {
            if let pipeline = row["counts"] as? [String: Any] {
                for key in ["accepted", "sealed", "finishRequest", "paused", "hostForeground", "invalidBuffer", "notReady",
                            "incompleteStatus", "throttled", "missingImage", "encoding", "writeFailed"] {
                    counts[key] = integer(pipeline[key])
                }
            }
            if let samples = row["acceptedSamples"] as? [Any] {
                for sample in samples.prefix(12) {
                    guard let sample = sample as? [String: Any],
                          let width = integer(sample["width"], limit: 16_384), width > 0,
                          let height = integer(sample["height"], limit: 16_384), height > 0 else { continue }
                    size = FrameSize(width: width, height: height)
                    break
                }
            }
        }
        let autoStopped = code == .captureFinishStarted ? boolean(row["autoStopped"]) : nil
        return Event(event: code, counts: counts.isEmpty ? nil : counts,
                     elapsedSeconds: durations.isEmpty ? nil : durations, frameSize: size, autoStopped: autoStopped)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    private static func integer(_ value: Any?, limit: Int = 1_000_000) -> Int? {
        guard let value = number(value), value.rounded(.towardZero) == value,
              (0...Double(limit)).contains(value) else { return nil }
        return Int(value)
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
}
