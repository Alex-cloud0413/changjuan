import Foundation

@main
struct SavedCaptureCleanupCheck {
    static let files = FileManager.default
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static var assertions = 0
    static var fixture: URL!

    static func main() throws {
        fixture = files.temporaryDirectory.appendingPathComponent("LongShotCleanupChecks-" + UUID().uuidString)
        try files.createDirectory(at: fixture, withIntermediateDirectories: false)
        try testSavedInputsAndQuality()
        try testUnsavedFailedAndInterruptedAreKept()
        try testAgeAndSaveDate()
        try testCountAndBytes()
        try testVisiblePreviewProtection()
        try testCancellationAndRetry()
        try testRetirementCrashRecovery()
        try testSymlinksAndUnknownData()
        try testRepeatedCaptureBound()
        try testExplicitRawCleanup()
        try testPartialResultRetention()
        CaptureStorage.testContainerURL = nil
        print("Saved capture cleanup passed (11 scenarios, \(assertions) assertions). Synthetic fixtures: \(fixture.path)")
    }

    static func useCase(_ name: String) throws {
        let root = fixture.appendingPathComponent(name)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        CaptureStorage.testContainerURL = root
    }

    static func session(age: TimeInterval = 0, state: CaptureSessionState = .complete,
                        saved: Bool = true, outputBytes: Int = 100) throws -> URL {
        let (url, original) = try CaptureStorage.createSession()
        var manifest = CaptureManifest(id: original.id, startedAt: now.addingTimeInterval(-age - 30),
            completedAt: now.addingTimeInterval(-age), frameCount: 2, state: state,
            autoStopped: false, failureMessage: state == .failed ? "test failure" : nil)
        manifest.savedToPhotos = saved
        try CaptureStorage.write(manifest, to: url)
        try Data(repeating: 31, count: 256).write(to: CaptureStorage.frameURL(index: 0, sessionURL: url))
        try Data(repeating: 32, count: 256).write(to: CaptureStorage.frameURL(index: 1, sessionURL: url))
        let cache = url.appendingPathComponent("Analysis-v1", isDirectory: true)
        try files.createDirectory(at: cache, withIntermediateDirectories: false)
        try Data(repeating: 33, count: 400).write(to: cache.appendingPathComponent("frame-000000.jpg.plist"))
        let output = try CaptureStorage.outputsDirectory(in: url).appendingPathComponent("long-001.jpg")
        try Data(repeating: 34, count: outputBytes).write(to: output)
        if saved {
            try CaptureStorage.markOutputsSavedToPhotos(in: url)
            try files.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: marker(url).path)
        }
        return url
    }

    static func testSavedInputsAndQuality() throws {
        try useCase("saved")
        let url = try session()
        let output = CaptureStorage.existingOutputs(in: url)[0]
        let before = try Data(contentsOf: output)
        let report = SavedCaptureCleanup.run(now: now)
        check(report.reclaimedBytes == 912 && report.failures == 0, "Only committed frames and analysis were removed")
        check(try CaptureStorage.frameURLs(in: url).isEmpty, "Saved frames gone")
        check(!exists(url.appendingPathComponent("Analysis-v1")), "Saved analysis gone")
        check(try Data(contentsOf: output) == before, "Output bytes unchanged")
        check(exists(marker(url)), "Save receipt preserved")
        let repeated = SavedCaptureCleanup.run(now: now)
        check(repeated.reclaimedBytes == 0 && repeated.removedSessionIDs.isEmpty, "Idempotent second pass")
    }

    static func testUnsavedFailedAndInterruptedAreKept() throws {
        try useCase("protected-recovery")
        let urls = try [session(age: 1_000_000, saved: false),
            session(age: 1_000_000, state: .failed), session(age: 1_000_000, state: .capturing)]
        // A manifest flag alone is not a Photos transaction receipt.
        var manifest = try CaptureStorage.readManifest(at: urls[0])
        manifest.savedToPhotos = true
        try CaptureStorage.write(manifest, to: urls[0])
        let before = try urls.map(snapshot)
        let report = SavedCaptureCleanup.run(now: now, policy: .init(maximumAge: 0, maximumCount: 0, maximumBytes: 0))
        check(report.removedSessionIDs.isEmpty && report.reclaimedBytes == 0, "Unsuccessful captures never pruned")
        for (index, url) in urls.enumerated() { check(try snapshot(url) == before[index], "Recoverable files byte identical") }
    }

    static func testAgeAndSaveDate() throws {
        try useCase("age")
        let expired = try session(age: 7 * 86400)
        let recent = try session(age: 7 * 86400 - 1)
        let recovered = try session(age: 20 * 86400)
        try files.setAttributes([.modificationDate: now], ofItemAtPath: marker(recovered).path)
        let report = SavedCaptureCleanup.run(now: now)
        check(Set(report.removedSessionIDs) == [expired.lastPathComponent], "7-day boundary")
        check(exists(recent) && exists(recovered), "Age measured from successful save, not recording start")
        check(try CaptureStorage.allSessions().count == 2, "Expired saved session cannot enter recovery")
    }

    static func testCountAndBytes() throws {
        try useCase("count")
        var urls: [URL] = []
        for index in 0..<12 { urls.append(try session(age: Double(index))) }
        let report = SavedCaptureCleanup.run(now: now)
        check(report.retainedCount == 10, "Keep at most 10 saved results")
        check(!exists(urls[10]) && !exists(urls[11]), "Oldest results evicted first")
        check(exists(urls[0]), "Newest result retained")

        try useCase("bytes")
        let oldest = try session(age: 5, outputBytes: 3000)
        let newest = try session(outputBytes: 3000)
        let bytes = SavedCaptureCleanup.run(now: now, policy: .init(maximumBytes: 5000))
        check(bytes.retainedBytes <= 5000 && bytes.retainedCount == 1, "Byte cap includes result metadata")
        check(!exists(oldest) && exists(newest), "Byte cap also evicts oldest first")
        let zero = SavedCaptureCleanup.run(now: now, policy: .init(maximumBytes: 0))
        check(zero.retainedBytes == 0 && zero.retainedCount == 0, "Oversized result retired after protection ends")
    }

    static func testVisiblePreviewProtection() throws {
        try useCase("visible")
        let url = try session(age: 9 * 86400)
        let policy = SavedCaptureCleanup.Policy(maximumCount: 0, maximumBytes: 0)
        let report = SavedCaptureCleanup.run(protectedSessionIDs: [url.lastPathComponent], now: now, policy: policy)
        check(report.removedSessionIDs.isEmpty && exists(url), "Visible result protected even over budget")
        check(try CaptureStorage.frameURLs(in: url).isEmpty, "Visible result does not retain raw inputs")
        let closed = SavedCaptureCleanup.run(now: now, policy: policy)
        check(closed.removedSessionIDs == [url.lastPathComponent], "Closing preview releases protection")
    }

    static func testCancellationAndRetry() throws {
        try useCase("cancel")
        let url = try session()
        let before = try snapshot(url)
        let cancelled = SavedCaptureCleanup.run(now: now, shouldCancel: { true })
        check(try cancelled.cancelled && snapshot(url) == before, "Cancelled cleanup leaves inputs untouched")
        var calls = 0
        let partial = SavedCaptureCleanup.run(now: now, shouldCancel: { calls += 1; return calls >= 3 })
        check(partial.cancelled && exists(url), "Interrupted cleanup retains session")
        let retry = SavedCaptureCleanup.run(now: now)
        check(try retry.failures == 0 && CaptureStorage.frameURLs(in: url).isEmpty, "Partial cleanup safely retries")
    }

    static func testRetirementCrashRecovery() throws {
        try useCase("crash")
        let url = try session(age: 8 * 86400)
        SavedCaptureCleanup.testAfterRetirement = { retired in
            // Simulate partial deletion followed by process termination.
            try files.removeItem(at: retired.appendingPathComponent(CaptureConstants.manifestFileName))
            throw CocoaError(.fileWriteUnknown)
        }
        let interrupted = SavedCaptureCleanup.run(now: now)
        SavedCaptureCleanup.testAfterRetirement = nil
        check(interrupted.failures == 1 && !exists(url), "Retirement remains committed if final deletion fails")
        check(try CaptureStorage.allSessions().isEmpty, "No re-stitch or duplicate Photos save after interruption")
        let trash = try CaptureStorage.sessionsDirectory().appendingPathComponent(".saved-preview-trash")
        check(try files.contentsOfDirectory(atPath: trash.path).count == 1, "Incomplete removal is recoverable")
        let resumed = SavedCaptureCleanup.run(now: now)
        check(resumed.failures == 0 && resumed.reclaimedBytes > 0, "Interrupted retirement removed next pass")
        check(try files.contentsOfDirectory(atPath: trash.path).isEmpty, "Trash does not accumulate")
    }

    static func testSymlinksAndUnknownData() throws {
        try useCase("safety")
        let external = fixture.appendingPathComponent("external-user-file")
        let secret = Data("not a capture".utf8)
        try secret.write(to: external)
        let linkedOutput = try session(age: 10 * 86400)
        try files.createSymbolicLink(at: linkedOutput.appendingPathComponent("Outputs/link.jpg"), withDestinationURL: external)
        let markerLink = try session(age: 10 * 86400, saved: false)
        try files.createSymbolicLink(at: marker(markerLink), withDestinationURL: external)
        let mismatched = try session(age: 10 * 86400)
        let bad = CaptureManifest(id: "wrong-id", startedAt: now, frameCount: 1,
            state: .complete, autoStopped: false)
        try CaptureStorage.write(bad, to: mismatched)
        let root = try CaptureStorage.sessionsDirectory()
        let linkedSession = root.appendingPathComponent("session-link")
        try files.createSymbolicLink(at: linkedSession, withDestinationURL: linkedOutput)
        let unknown = root.appendingPathComponent("unrecognised")
        try files.createDirectory(at: unknown, withIntermediateDirectories: false)
        try secret.write(to: unknown.appendingPathComponent("keep.txt"))
        let before = try [linkedOutput, markerLink, mismatched, unknown].map(snapshot)
        let report = SavedCaptureCleanup.run(now: now)
        check(report.removedSessionIDs.isEmpty, "Invalid and linked sessions preserved")
        for (index, url) in [linkedOutput, markerLink, mismatched, unknown].enumerated() {
            check(try snapshot(url) == before[index], "Unknown data unchanged")
        }
        check(try Data(contentsOf: external) == secret, "No traversal outside recording container")
        check(exists(linkedSession), "Session symlink not followed")
    }

    static func testRepeatedCaptureBound() throws {
        try useCase("many-captures")
        for index in 0..<45 {
            let url = try session(age: Double(45 - index), outputBytes: 2000)
            let report = SavedCaptureCleanup.run(protectedSessionIDs: [url.lastPathComponent], now: now)
            check(report.failures == 0 && report.retainedCount <= 10, "45 sequential saves remain bounded")
        }
        let sessions = try CaptureStorage.allSessions()
        check(sessions.count == 10, "Exactly 10 retained sessions")
        for entry in sessions { check(try CaptureStorage.frameURLs(in: entry.url).isEmpty, "No raw-frame history") }
    }

    static func testExplicitRawCleanup() throws {
        try useCase("manual-raw-only")
        let urls = try [session(), session(saved: false), session(state: .failed, saved: false),
                        session(state: .capturing, saved: false)]
        let outputs = urls.flatMap { CaptureStorage.existingOutputs(in: $0) }
        let before = try outputs.map { try Data(contentsOf: $0) }
        let unsafe = try session(saved: false)
        let external = fixture.appendingPathComponent("external-user-file")
        try files.createSymbolicLink(at: unsafe.appendingPathComponent("Analysis-v1/link"), withDestinationURL: external)
        let unsafeBefore = try snapshot(unsafe)
        let report = SavedCaptureCleanup.clearAllRawCaches()
        check(Set(report.clearedRawSessionIDs) == Set(urls.map(\.lastPathComponent)), "Explicit action includes unsaved and failed raw data")
        check(report.reclaimedBytes == 4 * 912, "Only raw JPEGs and derived analysis counted")
        check(report.failures == 1, "Unsafe linked tree rejected")
        check(try snapshot(unsafe) == unsafeBefore, "Unsafe session remains untouched")
        for url in urls {
            check(CaptureStorage.hasDiscardedRawFrames(in: url), "Durable tombstone before input deletion")
            check(try CaptureStorage.frameURLs(in: url).isEmpty, "All raw frames cleared")
            check(!exists(url.appendingPathComponent("Analysis-v1")), "Analysis removed")
            check(exists(url.appendingPathComponent(CaptureConstants.manifestFileName)), "Metadata preserved")
        }
        for (output, data) in zip(outputs, before) { check(try Data(contentsOf: output) == data, "Generated preview byte identical") }
        let again = SavedCaptureCleanup.clearAllRawCaches()
        check(again.reclaimedBytes == 0 && again.clearedRawSessionIDs.isEmpty, "Repeated manual clearing is idempotent")
    }

    static func testPartialResultRetention() throws {
        try useCase("partial-retention")
        let url = try session(age: 30 * 86400)
        var manifest = try CaptureStorage.readManifest(at: url)
        check(manifest.omittedOccludedBottomRows == nil, "Old manifest remains readable")
        manifest.omittedOccludedBottomRows = true
        try CaptureStorage.write(manifest, to: url)
        check(try CaptureStorage.readManifest(at: url).omittedOccludedBottomRows == true, "Qualification survives restart")
        let before = try snapshot(url)
        let policy = SavedCaptureCleanup.Policy(maximumAge: 0, maximumCount: 0, maximumBytes: 0)
        let cleanup = SavedCaptureCleanup.run(now: now, policy: policy)
        check(cleanup.reclaimedBytes == 0 && cleanup.removedSessionIDs.isEmpty, "Partial result never triggers automatic source deletion")
        check(try snapshot(url) == before, "Entire partial session remains byte identical")
        let explicit = SavedCaptureCleanup.clearAllRawCaches()
        check(explicit.clearedRawSessionIDs == [url.lastPathComponent], "Explicit cache clearing still releases partial recording")
        check(try CaptureStorage.frameURLs(in: url).isEmpty, "Explicit action removes raw inputs")
        check(!CaptureStorage.existingOutputs(in: url).isEmpty, "Explicit cache action retains preview")
        let retired = SavedCaptureCleanup.run(now: now, policy: policy)
        check(retired.removedSessionIDs == [url.lastPathComponent], "Ordinary preview retention resumes after explicit cache clearing")
    }

    static func marker(_ url: URL) -> URL { url.appendingPathComponent(CaptureConstants.savedToPhotosMarkerName) }
    static func exists(_ url: URL) -> Bool { files.fileExists(atPath: url.path) }
    static func check(_ condition: Bool, _ message: String, line: UInt = #line) {
        assertions += 1
        if !condition { fatalError("\(message), line \(line)") }
    }
    static func snapshot(_ url: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for name in try files.subpathsOfDirectory(atPath: url.path) {
            let child = url.appendingPathComponent(name)
            let type = try files.attributesOfItem(atPath: child.path)[.type] as? FileAttributeType
            if type == .typeRegular { result[name] = try Data(contentsOf: child) }
        }
        return result
    }
}
