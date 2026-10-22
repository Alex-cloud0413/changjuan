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
struct ScreenFramePipelineCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LongShotSCKPipelineChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        CaptureStorage.testContainerURL = directory
        try testHostExclusionAndImmediateTargetFrame()
        try testSealAndTailPreservation()
        try testExplicitFinishWhileHostIsVisible()
        try testEmptyCaptureFails()
        try testExplicitPageTransitions()
        try testGeometryChangesAndPausedResume()
        try testSideBySideHostFailsExplicitly()
        try testPreparationBackpressurePreservesAllFrames()
        try testPreparationFailurePreservesAllFrames()
        try testLatePreparationCannotRecreateCleanedFiles()
        try testOptionsSnapshotAndManualCleanup()
        try benchmarkFullSizeFrames()
#if LONGSHOT_SCK_METADATA_STUB
        print("ScreenFramePipeline JPEG/queue checks passed (12); SCK metadata/stream unavailable and excluded on this runtime.")
#else
        print("ScreenFramePipeline checks passed (12)")
#endif
        print("Fixtures: \(directory.path)")
    }

    private static func testHostExclusionAndImmediateTargetFrame() throws {
        let visibility = ScreenCaptureHostVisibility()
        visibility.setForeground(true)
        let pipeline = ScreenFramePipeline(hostIsForeground: { visibility.isForeground })
        _ = try pipeline.beginSession(topCropRatio: 0.075)
        guard case .none = pipeline.consume(try makeSample(index: 0)) else {
            fatalError("Host UI must be excluded")
        }
        visibility.setForeground(false)
        guard case .progress(1) = pipeline.consume(try makeSample(index: 1)) else {
            fatalError("First target frame must be retained immediately")
        }
        let result = pipeline.finishSession(autoStopped: false, trimTrailingFrames: true)
        require(result?.manifest.frameCount == 1)
        require(result?.manifest.state == .complete)
    }

    private static func testSealAndTailPreservation() throws {
        let pipeline = ScreenFramePipeline(hostIsForeground: { false })
        let url = try pipeline.beginSession(topCropRatio: 0.075)
        for index in 0..<12 { _ = pipeline.consume(try makeSample(index: index)) }
        pipeline.sealForFinishing()
        guard case .none = pipeline.consume(try makeSample(index: 12)) else {
            fatalError("No frames may enter after explicit finish is sealed")
        }
        let result = pipeline.finishSession(autoStopped: false, trimTrailingFrames: true)
        require(result?.manifest.state == .complete)
        require(result?.manifest.frameCount == 12)
        require(try CaptureStorage.frameURLs(in: url).count == 12)
        require(FileManager.default.fileExists(atPath: CaptureStorage.frameURL(index: 11, sessionURL: url).path))
    }

    private static func testExplicitFinishWhileHostIsVisible() throws {
        let pipeline = ScreenFramePipeline(hostIsForeground: { true })
        _ = try pipeline.beginSession(topCropRatio: 0.075)
        CaptureCommandStore.finishRequested = true
        guard case .shouldStop(autoStopped: false, trimTrailingFrames: _) = pipeline.consume(try makeSample(index: 0)) else {
            fatalError("Host exclusion must not block the finish command")
        }
        _ = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)
    }

    private static func testEmptyCaptureFails() throws {
        let pipeline = ScreenFramePipeline(hostIsForeground: { false })
        _ = try pipeline.beginSession(topCropRatio: 0.075)
        let result = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)
        require(result?.manifest.state == .failed)
        require(result?.manifest.frameCount == 0)
    }

    private static func testExplicitPageTransitions() throws {
        let pipeline = ScreenFramePipeline(hostIsForeground: { false })
        let session = try pipeline.beginSession(topCropRatio: 0.075)
        for index in 0..<4 { _ = pipeline.consume(try makeSample(index: index)) }
        require(pipeline.togglePageTransition())
        for index in 4..<8 {
            guard case .none = pipeline.consume(try makeSample(index: index)) else {
                fatalError("Page-switch animations must never be committed")
            }
        }
        require(!pipeline.togglePageTransition())
        guard case .progress(5) = pipeline.consume(try makeSample(index: 8)) else {
            fatalError("Continue must retain the next frame immediately")
        }
        require(pipeline.togglePageTransition())
        let completion = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)
        require(completion?.manifest.segmentStarts == [0, 4])
        require(completion?.manifest.frameCount == 5)
        require(try CaptureStorage.frameURLs(in: session).count == 5)
        _ = try pipeline.beginSession(topCropRatio: 0.075)
        require(!pipeline.isPausedForNextPage)
        _ = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)
    }

    private static func testGeometryChangesAndPausedResume() throws {
        let pipeline = ScreenFramePipeline(hostIsForeground: { false })
        let session = try pipeline.beginSession(topCropRatio: 0)
        for index in 0..<4 { _ = pipeline.consume(try makeSample(index: index)) }
        for index in 4..<8 { _ = pipeline.consume(try makeSample(index: index, width: 240, height: 260)) }
        require(pipeline.togglePageTransition())
        requireNoneForGeometry(pipeline.consume(try makeSample(index: 8, width: 300, height: 120)))
        require(!pipeline.togglePageTransition())
        for index in 9..<13 { _ = pipeline.consume(try makeSample(index: index, width: 120, height: 260)) }
        let completion = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)!
        require(completion.manifest.segmentStarts == [0, 4, 8])
        require(completion.manifest.geometrySegments?.map(\.startFrame) == [0, 4, 8])
        require(completion.manifest.geometrySegments?.map(\.pixelWidth) == [120, 240, 120])
        require(completion.manifest.frameCount == 12)
        require(try CaptureStorage.frameURLs(in: session).count == 12)
        let decoded = try CaptureStorage.readManifest(at: session)
        require(decoded.geometrySegments == completion.manifest.geometrySegments)
        print("Native geometry changes create ordered page boundaries; paused transitions add no empty pages; raw JPEGs and metadata round trip")
    }

    private static func requireNoneForGeometry(_ event: ScreenFramePipeline.Event) {
        guard case .none = event else { fatalError("Paused geometry must not enter raw frames") }
    }

    private static func testSideBySideHostFailsExplicitly() throws {
        let visibility = ScreenCaptureHostVisibility()
        visibility.setForeground(false)
        let pipeline = ScreenFramePipeline(hostIsForeground: { visibility.isForeground },
            hostHasPartialWindow: { visibility.hasVisiblePartialWindow })
        let session = try pipeline.beginSession(topCropRatio: 0)
        _ = pipeline.consume(try makeSample(index: 0))
        let original = try Data(contentsOf: CaptureStorage.frameURL(index: 0, sessionURL: session))
        visibility.setPartialWindow(true)
        visibility.setForeground(true)
        guard case .failed(let message) = pipeline.consume(try makeSample(index: 1)) else {
            fatalError("Unsupported side-by-side capture must fail explicitly instead of silently dropping every target frame")
        }
        require(message.contains("全屏"))
        let result = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)!
        require(result.manifest.state == .failed && result.manifest.frameCount == 1)
        require(try Data(contentsOf: CaptureStorage.frameURL(index: 0, sessionURL: session)) == original)
        let initiallyInactive = ScreenCaptureHostVisibility()
        initiallyInactive.setPartialWindow(true)
        initiallyInactive.setSceneActivationState(.foregroundInactive)
        let cold = ScreenFramePipeline(hostIsForeground: { initiallyInactive.isForeground },
            hostHasPartialWindow: { initiallyInactive.hasVisiblePartialWindow })
        _ = try cold.beginSession(topCropRatio: 0)
        guard case .failed = cold.consume(try makeSample(index: 0)) else {
            fatalError("An initially inactive but visible host window must never enter captured pixels")
        }
        require(cold.finishSession(autoStopped: false, trimTrailingFrames: false)?.manifest.frameCount == 0)
    }

    private static func benchmarkFullSizeFrames() throws {
        let queue = DispatchQueue(label: "LongShotSCKPipelineBenchmark")
        let pipeline = ScreenFramePipeline(hostIsForeground: { false })
        _ = try queue.sync { try pipeline.beginSession(topCropRatio: 0.075) }
        var times: [Double] = []
        for index in 0..<16 {
            try autoreleasepool {
                let sample = try makeSample(index: index, width: 1206, height: 2622)
                let started = ProcessInfo.processInfo.systemUptime
                let event = queue.sync { pipeline.consume(sample) }
                times.append(ProcessInfo.processInfo.systemUptime - started)
                guard case .progress = event else { fatalError("Full-size frame not committed") }
            }
        }
        let finishStarted = ProcessInfo.processInfo.systemUptime
        let result = queue.sync {
            pipeline.sealForFinishing()
            return pipeline.finishSession(autoStopped: false, trimTrailingFrames: true)
        }
        let finish = ProcessInfo.processInfo.systemUptime - finishStarted
        require(result?.manifest.frameCount == 16)
        let sorted = times.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        print(String(format: "1206x2622 frames=16; JPEG+write median=%.4fs p95=%.4fs max=%.4fs; sealed manifest finish=%.4fs", median, p95, sorted.last!, finish))
    }

    private static func testPreparationBackpressurePreservesAllFrames() throws {
        let blocked = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        let preprocessor = FramePreprocessor { data, url in
            entered.signal()
            _ = blocked.wait(timeout: .now() + 5)
            try FramePreparationCache.store(FrameStitcher().prepareFrame(at: url, encodedData: data), for: url)
        }
        let pipeline = ScreenFramePipeline(preprocessor: preprocessor, hostIsForeground: { false })
        let firstSession = try pipeline.beginSession(topCropRatio: 0.075)
        _ = pipeline.consume(try makeSample(index: 0))
        require(entered.wait(timeout: .now() + 5) == .success)
        for index in 1..<12 {
            guard case .progress(index + 1) = pipeline.consume(try makeSample(index: index)) else {
                fatalError("A full preparation queue must never discard a recorded frame")
            }
        }
        let started = ProcessInfo.processInfo.systemUptime
        pipeline.sealForFinishing()
        let completion = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)
        require(ProcessInfo.processInfo.systemUptime - started < 0.5)
        require(completion?.manifest.frameCount == 12)
        require(try CaptureStorage.frameURLs(in: firstSession).count == 12)
        // A new session may start while the old preparation job still runs.
        let secondSession = try pipeline.beginSession(topCropRatio: 0.075)
        _ = pipeline.consume(try makeSample(index: 0))
        _ = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)
        blocked.signal(); blocked.signal()
        preprocessor.waitForTesting()
        require(FramePreparationCache.load(for: CaptureStorage.frameURL(index: 0, sessionURL: firstSession)) != nil)
        require(FramePreparationCache.load(for: CaptureStorage.frameURL(index: 1, sessionURL: firstSession)) != nil)
        require(FramePreparationCache.load(for: CaptureStorage.frameURL(index: 2, sessionURL: firstSession)) == nil)
        require(FramePreparationCache.load(for: CaptureStorage.frameURL(index: 0, sessionURL: secondSession)) == nil)
    }

    private static func testPreparationFailurePreservesAllFrames() throws {
        let preprocessor = FramePreprocessor { _, _ in throw CheckError.sample }
        let pipeline = ScreenFramePipeline(preprocessor: preprocessor, hostIsForeground: { false })
        let session = try pipeline.beginSession(topCropRatio: 0.075)
        for index in 0..<6 { _ = pipeline.consume(try makeSample(index: index)) }
        let completion = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)
        preprocessor.waitForTesting()
        require(completion?.manifest.state == .complete)
        require(completion?.manifest.frameCount == 6)
        require(try CaptureStorage.frameURLs(in: session).count == 6)
    }

    private static func testLatePreparationCannotRecreateCleanedFiles() throws {
        let prepared = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let preprocessor = FramePreprocessor { data, url in
            let cached = try FrameStitcher().prepareFrame(at: url, encodedData: data)
            prepared.signal()
            _ = resume.wait(timeout: .now() + 5)
            try FramePreparationCache.store(cached, for: url)
        }
        let pipeline = ScreenFramePipeline(preprocessor: preprocessor, hostIsForeground: { false })
        let session = try pipeline.beginSession(topCropRatio: 0.075)
        _ = pipeline.consume(try makeSample(index: 0))
        require(prepared.wait(timeout: .now() + 5) == .success)
        _ = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)
        try CaptureStorage.markOutputsSavedToPhotos(in: session)
        let report = SavedCaptureCleanup.run(protectedSessionIDs: [session.lastPathComponent])
        require(report.failures == 0)
        require(try CaptureStorage.frameURLs(in: session).isEmpty)
        resume.signal()
        preprocessor.waitForTesting()
        require(!FileManager.default.fileExists(atPath: session.appendingPathComponent("Analysis-v1").path))
        require(try CaptureStorage.frameURLs(in: session).isEmpty)
    }

    private static func testOptionsSnapshotAndManualCleanup() throws {
        let prepared = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let options = CaptureOptions(axis: .horizontal, keepsStatusBar: true)
        let preprocessor = FramePreprocessor { data, url in
            let cache = try FrameStitcher(options: options).prepareFrame(at: url, encodedData: data)
            prepared.signal()
            _ = resume.wait(timeout: .now() + 5)
            try FramePreparationCache.store(cache, for: url)
        }
        let pipeline = ScreenFramePipeline(preprocessor: preprocessor, hostIsForeground: { false })
        let session = try pipeline.beginSession(topCropRatio: 0.075, options: options)
        require(try CaptureStorage.readManifest(at: session).captureOptions == options)
        _ = pipeline.consume(try makeSample(index: 0))
        require(prepared.wait(timeout: .now() + 5) == .success)
        let completion = pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)
        require(completion?.manifest.captureOptions == options)
        let report = SavedCaptureCleanup.clearAllRawCaches()
        require(report.failures == 0 && report.clearedRawSessionIDs.contains(session.lastPathComponent))
        resume.signal()
        preprocessor.waitForTesting()
        require(CaptureStorage.hasDiscardedRawFrames(in: session))
        require(!FileManager.default.fileExists(atPath: session.appendingPathComponent("Analysis-v1").path))
        // Old manifest files are decoded without invented preferences.
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: session.appendingPathComponent("manifest.json"))) as! [String: Any]
        json.removeValue(forKey: "captureOptions")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(CaptureManifest.self, from: JSONSerialization.data(withJSONObject: json))
        require(legacy.captureOptions == nil)
    }

    private static func makeSample(index: Int, width: Int = 120, height: Int = 260) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { throw CheckError.sample }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            throw CheckError.sample
        }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            let row = address.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let shade = UInt8(30 + ((x / 11 * 29 + (y + index * 31) / 13 * 37) % 210))
                row[x * 4] = shade
                row[x * 4 + 1] = shade
                row[x * 4 + 2] = shade
                row[x * 4 + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format) == noErr,
              let format else { throw CheckError.sample }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 4), presentationTimeStamp: CMTime(value: Int64(index), timescale: 4), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { throw CheckError.sample }
        return sample
    }

    private static func require(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
        guard condition else { fatalError("Check failed", file: file, line: line) }
    }
}

private enum CheckError: Error { case sample }
