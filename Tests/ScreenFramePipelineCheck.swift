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
        try benchmarkFullSizeFrames()
#if LONGSHOT_SCK_METADATA_STUB
        print("ScreenFramePipeline JPEG/queue checks passed (6); SCK metadata/stream unavailable and excluded on this runtime.")
#else
        print("ScreenFramePipeline checks passed (6)")
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
