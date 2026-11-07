import Darwin
import Foundation

@main
struct FeedbackDiagnosticsCheck {
    private static let selected = "selected-capture-id"
    private static let secret = "/private/capture.png | device-id | raw OCR text | 2026-11-07T10:22:33Z"

    private static func report(_ url: URL, session: String? = selected,
                               version: String = "1.1.5", build: String = "57") throws -> (String, [String: Any]) {
        let text = FeedbackDiagnostics.makeReport(journalURL: url, sessionID: session, appVersion: version,
            build: build, capture: .init(axis: .horizontal, keepsStatusBar: false))
        let json = try JSONSerialization.jsonObject(with: Data(text.utf8))
        guard let object = json as? [String: Any] else { fatalError("Expected a JSON report object") }
        return (text, object)
    }

    private static func write(_ rows: [[String: Any]], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: rows)
        try data.write(to: url, options: .atomic)
    }

    private static func events(in report: [String: Any]) -> [[String: Any]] {
        guard let events = report["events"] as? [[String: Any]] else { fatalError("Expected a JSON event array") }
        return events
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let journal = root.appendingPathComponent("journal.json")
        try write([
            ["event": "captureStopped", "sessionID": "unrelated", "frameCount": 999],
            ["event": "captureStopped", "nested": ["sessionID": selected], "frameCount": 998],
            ["event": secret, "sessionID": selected, "frameCount": 997],
            ["event": "capturePipelineSnapshot", "sessionID": selected, "timestamp": secret, "processRunID": secret,
             "deviceName": secret, "appVersion": secret, "callbackCount": 401, "invalidPTSCount": true,
             "nonfinitePTSCount": "2", "backwardPTSCount": 1.5, "wallSeconds": 17.12544,
             "maximumPTSGap": -1.0, "maximumCallbackGap": 86_401, "firstPresentationTime": 123_456.5,
             "counts": ["accepted": 53, "throttled": 320, "sealed": true, "writeFailed": 1_000_001, secret: 45],
             "frameStatusCounts": [secret: 78], "acceptedSamples": [
                ["width": 0, "height": 2622],
                ["width": 1206, "height": 2622, "index": 32, "jpegBytes": 543_210,
                 "presentationTime": 123_456.5, "presentationTimeEpoch": 3, "screenshot": secret]
             ]],
            ["event": "captureFinishStarted", "sessionID": selected, "autoStopped": true, "seconds": 1.23],
            ["event": "captureFinishStarted", "sessionID": selected, "autoStopped": 1],
            ["event": "stitchingFinished", "sessionID": selected, "preparedFrameCount": 48, "outputCount": 2,
             "stitchingSeconds": 6.25, "samplingSeconds": ["raw": secret], "processingStartedAt": secret],
            ["event": "processingFailed", "sessionID": selected, "errorDomain": secret, "errorCode": 11,
             "description": secret, "outputCount": 3]
        ], to: journal)

        let (text, result) = try report(journal)
        precondition(Set(result.keys) == ["schemaVersion", "appVersion", "build", "osVersion", "capture", "events"])
        precondition(result["schemaVersion"] as? Int == 1)
        precondition(result["appVersion"] as? String == "1.1.5" && result["build"] as? String == "57")
        let os = ProcessInfo.processInfo.operatingSystemVersion
        precondition(result["osVersion"] as? [String: Int] == ["major": os.majorVersion, "minor": os.minorVersion, "patch": os.patchVersion])
        let capture = result["capture"] as? [String: Any]
        precondition(Set(capture?.keys.map { $0 } ?? []) == ["axis", "keepsStatusBar"])
        precondition(capture?["axis"] as? String == "horizontal" && capture?["keepsStatusBar"] as? Bool == false)
        let emitted = events(in: result)
        precondition(emitted.compactMap { $0["event"] as? String } ==
            ["capturePipelineSnapshot", "captureFinishStarted", "captureFinishStarted", "stitchingFinished", "processingFailed"])
        precondition(Set(emitted[0].keys) == ["event", "counts", "elapsedSeconds", "frameSize"])
        precondition(emitted[0]["counts"] as? [String: Int] == ["accepted": 53, "throttled": 320, "callbackCount": 401])
        precondition(emitted[0]["elapsedSeconds"] as? [String: Double] == ["wallSeconds": 17.125])
        precondition(emitted[0]["frameSize"] as? [String: Int] == ["width": 1206, "height": 2622])
        precondition(Set(emitted[1].keys) == ["event", "autoStopped"] && emitted[1]["autoStopped"] as? Bool == true)
        precondition(Set(emitted[2].keys) == ["event"])
        precondition(emitted[3]["counts"] as? [String: Int] == ["preparedFrameCount": 48, "outputCount": 2])
        precondition(emitted[3]["elapsedSeconds"] as? [String: Double] == ["stitchingSeconds": 6.25])
        precondition(Set(emitted[4].keys) == ["event"])
        for disallowed in [selected, "unrelated", "capture.png", "device-id", "OCR", "2026-11-07", "sessionID",
                           "timestamp", "processRunID", "presentationTime", "acceptedSamples", "errorDomain", "errorCode"] {
            precondition(!text.contains(disallowed), "Disallowed diagnostics token: \(disallowed)")
        }

        for id in [nil, "", "missing", String(repeating: "x", count: 65)] {
            let unselected = try report(journal, session: id).1
            precondition(events(in: unselected).isEmpty)
        }
        let invalidVersions = try report(journal, version: secret, build: "１.9").1
        precondition(invalidVersions["appVersion"] == nil && invalidVersions["build"] == nil)
        for invalid in [".1", "1.", "1..2", "1.2.3.4", "-3", "1\n", "1234567890"] {
            let rejectedVersion = try report(journal, version: invalid, build: invalid).1
            precondition(rejectedVersion["appVersion"] == nil && rejectedVersion["build"] == nil)
        }

        let fileLink = root.appendingPathComponent("journal-link.json")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: journal)
        let parentLink = root.appendingPathComponent("parent-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: root)
        let fifo = root.appendingPathComponent("journal-fifo")
        precondition(mkfifo(fifo.path, 0o600) == 0)
        for rejected in [fileLink, parentLink.appendingPathComponent("journal.json"), fifo, root,
                         root.appendingPathComponent("missing.json"), URL(string: "https://example.invalid/diagnostics")!] {
            let rejectedReport = try report(rejected).1
            precondition(events(in: rejectedReport).isEmpty)
        }

        try Data("[invalid\n".utf8).write(to: journal)
        let malformed = try report(journal).1
        precondition(events(in: malformed).isEmpty)
        let oneEvent = "[{\"event\":\"captureStarted\",\"sessionID\":\"\(selected)\"}]"
        try Data((oneEvent + String(repeating: " ", count: 512 * 1024)).utf8).write(to: journal)
        let oversized = try report(journal).1
        precondition(events(in: oversized).isEmpty)

        let oneSelected: [String: Any] = ["event": "captureStarted", "sessionID": selected]
        let unrelated: [String: Any] = ["event": "captureStarted", "sessionID": "unrelated"]
        try write([oneSelected] + Array(repeating: unrelated, count: 240), to: journal)
        let pastReadBound = try report(journal).1
        precondition(events(in: pastReadBound).isEmpty)
        try write((1...40).map { ["event": "captureStopped", "sessionID": selected, "frameCount": $0] }, to: journal)
        let (boundedText, bounded) = try report(journal)
        precondition(boundedText.utf8.count <= 16 * 1024)
        precondition(events(in: bounded).compactMap { ($0["counts"] as? [String: Int])?["frameCount"] } == Array(9...40))
        print("Feedback diagnostics passed: selected-session projection, strict field types, privacy, link safety and size bounds.")
    }
}
