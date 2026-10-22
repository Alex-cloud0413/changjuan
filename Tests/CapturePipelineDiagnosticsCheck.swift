import CoreMedia
import CoreVideo
import Foundation

enum CaptureCommandStore {
    nonisolated(unsafe) static var finishRequested = false
    static func clearFinishRequest() { finishRequested = false }
    static func consumeFinishRequest() -> Bool {
        defer { finishRequested = false }
        return finishRequested
    }
}

@main
struct CapturePipelineDiagnosticsCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LongShotNumericDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        CaptureStorage.testContainerURL = directory
        try testBoundedFiniteMetadata()
        try testProductionFilteringAndPTSRegression()
        try testInvalidNotReadyAndWriteFailure()
        print("Capture numeric diagnostics checks passed (3 groups): bounded finite metadata; unchanged PTS/filtering; invalid/not-ready/write failure. Synthetic buffers only; SCK status adapter stubbed.")
    }

    private static func testBoundedFiniteMetadata() throws {
        var diagnostics = ScreenFramePipelineDiagnostics()
        for reason in ScreenFramePipelineDiagnostics.Rejection.allCases { diagnostics.reject(reason) }
        diagnostics.observeCallback(presentationTime: .invalid, lastSavedTime: nil)
        diagnostics.observeCallback(presentationTime: .positiveInfinity, lastSavedTime: nil)
        diagnostics.observeCallback(presentationTime: CMTime(value: 1, timescale: 1, flags: .valid, epoch: 0), lastSavedTime: nil)
        diagnostics.observeCallback(presentationTime: CMTime(value: 2, timescale: 1, flags: .valid, epoch: 1), lastSavedTime: nil)
        for index in 0..<100 {
            diagnostics.accept(index: index, presentationTime: CMTime(value: Int64(index), timescale: 4),
                width: 120, height: 260, bytes: 1234)
        }
        let snapshot = diagnostics.snapshot()
        require(snapshot["schemaVersion"] as? Int == 1, "Numeric schema is versioned")
        require(snapshot["callbackCount"] as? Int == 4, "All callback observations counted")
        require(snapshot["invalidPTSCount"] as? Int == 1, "Invalid PTS counted")
        require(snapshot["nonfinitePTSCount"] as? Int == 1, "Infinite PTS never enters JSON")
        require(snapshot["ptsEpochChangeCount"] as? Int == 1, "Epoch changes counted independently")
        require((snapshot["acceptedSamples"] as? [[String: Any]])?.count == 12, "Accepted samples bounded to 12")
        let counts = snapshot["counts"] as! [String: Int]
        require(counts["accepted"] == 100, "Sample cap never caps accepted counter")
        for reason in ScreenFramePipelineDiagnostics.Rejection.allCases {
            require(counts[reason.rawValue] == 1, "Every rejection has its own counter")
        }
        require(JSONSerialization.isValidJSONObject(snapshot), "All snapshot numbers JSON finite")
        let encoded = try JSONSerialization.data(withJSONObject: snapshot)
        require(encoded.count < 5_000, "Snapshot remains bounded and small")
        require(!String(decoding: encoded, as: UTF8.self).contains("file:"), "No paths or screen contents")
    }

    private static func testProductionFilteringAndPTSRegression() throws {
        let visibility = ScreenCaptureHostVisibility()
        visibility.setSceneActivationState(.background)
        let preprocessor = FramePreprocessor { _, _ in }
        let pipeline = ScreenFramePipeline(preprocessor: preprocessor, hostIsForeground: { visibility.isForeground })
        let session = try pipeline.beginSession(topCropRatio: 0.075)
        let times: [CMTime] = [time(10), time(10), time(9), time(10.1), time(10.25), .invalid, time(10.5), time(10.75)]
        var savedCounts: [Int] = []
        for pts in times {
            if case .progress(let count) = pipeline.consume(try sample(pts)) { savedCounts.append(count) }
        }
        // A backwards PTS is still rejected by the original < 0.25s rule.
        // Invalid PTS still bypasses that rule; diagnostics must not repair it.
        require(savedCounts == [1, 2, 3, 4, 5], "Original PTS gating preserved exactly")
        visibility.setForeground(true)
        requireNone(pipeline.consume(try sample(time(11))))
        visibility.setForeground(false)
        require(pipeline.togglePageTransition(), "Pause before synthetic page switch")
        requireNone(pipeline.consume(try sample(time(12))))
        CaptureCommandStore.finishRequested = true
        guard case .shouldStop(autoStopped: false, trimTrailingFrames: true) = pipeline.consume(try sample(time(12.5))) else {
            fatalError("Explicit finish must still run before pause/host gates")
        }
        requireNone(pipeline.consume(try sample(time(13))))
        let completion = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)!
        let snapshot = completion.diagnostics
        let counts = snapshot["counts"] as! [String: Int]
        require(snapshot["callbackCount"] as? Int == 12, "All callbacks including early gates observed")
        require(counts.values.reduce(0, +) == 12, "Every production callback has exactly one outcome")
        require(counts["accepted"] == 5 && counts["throttled"] == 3, "Accepted/throttled exact")
        require(counts["hostForeground"] == 1 && counts["paused"] == 1
            && counts["finishRequest"] == 1 && counts["sealed"] == 1, "Gate reasons remain distinct")
        require((snapshot["frameStatusCounts"] as? [String: Int]) == ["metadataStub": 8],
            "Status observed before throttle but after foreground/pause checks")
        require(snapshot["backwardPTSCount"] as? Int == 1, "Callback PTS regression detected")
        require(snapshot["negativeDeltaFromSavedCount"] as? Int == 1, "Regression relative to saved PTS detected")
        require(snapshot["zeroDeltaFromSavedCount"] as? Int == 1, "Repeated saved PTS detected")
        let frameCount = try CaptureStorage.frameURLs(in: session).count
        require(completion.manifest.frameCount == 5 && frameCount == 5,
            "Diagnostics do not drop or add persisted images")
        _ = try pipeline.beginSession(topCropRatio: 0.075)
        guard case .progress(1) = pipeline.consume(try sample(time(0))) else { fatalError("Fresh session saves immediately") }
        let next = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)!
        require(next.diagnostics["callbackCount"] as? Int == 1, "New session resets all diagnostics")
        require(snapshot["callbackCount"] as? Int == 12, "Completion owns a snapshot that survives reset")
        preprocessor.waitForTesting()
    }

    private static func testInvalidNotReadyAndWriteFailure() throws {
        let pipeline = ScreenFramePipeline(preprocessor: FramePreprocessor { _, _ in }, hostIsForeground: { false })
        let session = try pipeline.beginSession(topCropRatio: 0.075)
        let invalid = try sample(time(0))
        CMSampleBufferInvalidate(invalid)
        requireNone(pipeline.consume(invalid))
        requireNone(pipeline.consume(try sample(time(1), ready: false)))
        // A directory at this exact synthetic frame path makes the existing
        // atomic JPEG write fail without touching any installed app data.
        try FileManager.default.createDirectory(at: CaptureStorage.frameURL(index: 0, sessionURL: session), withIntermediateDirectories: true)
        guard case .failed = pipeline.consume(try sample(time(2))) else { fatalError("Synthetic write must fail") }
        let result = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)!
        let counts = result.diagnostics["counts"] as! [String: Int]
        require(counts["invalidBuffer"] == 1 && counts["notReady"] == 1 && counts["writeFailed"] == 1,
            "Original early failures each accounted for")
        require(result.manifest.state == .failed && result.manifest.frameCount == 0, "Failure behavior preserved")
    }

    private static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    private static func sample(_ pts: CMTime, ready: Bool = true) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
        guard CVPixelBufferCreate(kCFAllocatorDefault, 120, 260, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else { throw CheckError.sample }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, 128, CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer, formatDescriptionOut: &format) == noErr, let format else { throw CheckError.sample }
        var timing = CMSampleTimingInfo(duration: time(0.25), presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
            dataReady: ready, makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &result) == noErr, let result else { throw CheckError.sample }
        return result
    }

    private static func requireNone(_ event: ScreenFramePipeline.Event) {
        guard case .none = event else { fatalError("Original discard outcome must remain .none") }
    }
    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
}

private enum CheckError: Error { case sample }
