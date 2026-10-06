import CoreMedia
import CoreVideo
import Foundation

// This standalone executable deliberately omits CaptureSystemIntegration.
// The pipeline only needs to clear a pending command when starting a session.
enum CaptureCommandStore {
    static func clearFinishRequest() {}
}

@main
struct ReplayFramePipelineCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LongShotCaptureChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        CaptureStorage.testContainerURL = directory

        try testImmediateFirstFrame()
        try testUnchangedFramesReachStitching()
        try testFinalFramesArePreserved()
        try testEmptyCaptureFails()
        try testRapidSessionsDoNotShareFiles()
        print("ReplayFramePipeline checks passed (5). Fixtures: \(directory.path)")
    }

    private static func testImmediateFirstFrame() throws {
        let pipeline = ReplayFramePipeline()
        _ = try pipeline.beginSession(topCropRatio: 0.075)
        guard case .progress(1) = pipeline.consume(try makeSample(index: 0)) else {
            fatalError("The first target frame must be kept without a fixed lead-in delay")
        }
        let completion = pipeline.finishSession()
        require(completion?.manifest.frameCount == 1)
        require(completion?.manifest.state == .complete)
    }

    private static func testUnchangedFramesReachStitching() throws {
        let pipeline = ReplayFramePipeline()
        let sessionURL = try pipeline.beginSession(topCropRatio: 0.075)
        for index in 0..<4 {
            _ = pipeline.consume(try makeSample(index: index))
        }
        let completion = pipeline.finishSession()
        require(completion?.manifest.state == .complete)
        require(completion?.manifest.failureMessage == nil)
        require(try CaptureStorage.readManifest(at: sessionURL).state == .complete)
        // This means capture is complete, not that a still page is a long image.
        // ScrollSequenceSelector remains responsible for rejecting still content.
    }

    private static func testFinalFramesArePreserved() throws {
        let pipeline = ReplayFramePipeline()
        let sessionURL = try pipeline.beginSession(topCropRatio: 0.075)
        for index in 0..<12 {
            _ = pipeline.consume(try makeSample(index: index))
        }
        let lastURL = CaptureStorage.frameURL(index: 11, sessionURL: sessionURL)
        let lastData = try Data(contentsOf: lastURL)
        let completion = pipeline.finishSession(trimTrailingFrames: true)
        require(completion?.manifest.frameCount == 12)
        require(try CaptureStorage.frameURLs(in: sessionURL).count == 12)
        require(try Data(contentsOf: lastURL) == lastData)
        require(try CaptureStorage.readManifest(at: sessionURL).frameCount == 12)
    }

    private static func testEmptyCaptureFails() throws {
        let pipeline = ReplayFramePipeline()
        _ = try pipeline.beginSession(topCropRatio: 0.075)
        let completion = pipeline.finishSession()
        require(completion?.manifest.state == .failed)
        require(completion?.manifest.frameCount == 0)
        require(completion?.manifest.failureMessage != nil)
    }

    private static func testRapidSessionsDoNotShareFiles() throws {
        var seen = Set<URL>()
        for index in 0..<20 {
            let session = try CaptureStorage.createSession()
            require(seen.insert(session.0).inserted)
            require(try CaptureStorage.frameURLs(in: session.0).isEmpty)
            try Data([UInt8(index)]).write(
                to: CaptureStorage.frameURL(index: 0, sessionURL: session.0)
            )
        }
    }

    private static func makeSample(index: Int) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let width = 120
        let height = 260
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            throw FixtureError.pixelBuffer
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            throw FixtureError.pixelBuffer
        }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        memset(address, 255, rowBytes * height)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
            formatDescriptionOut: &format
        ) == noErr, let format else { throw FixtureError.format }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 4),
            presentationTimeStamp: CMTime(value: Int64(index), timescale: 4),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
            formatDescription: format, sampleTiming: &timing,
            sampleBufferOut: &sample
        ) == noErr, let sample else { throw FixtureError.sample }
        return sample
    }

    private static func require(
        _ condition: Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition else { fatalError("Check failed", file: file, line: line) }
    }
}

private enum FixtureError: Error {
    case pixelBuffer
    case format
    case sample
}
