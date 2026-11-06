import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import UIKit

// SCK is device-only. Keep its simulator substitutes limited to typed metadata
// keys and status values; all orientation/filtering/JPEG logic is production.
typealias SCStreamFrameInfo = String
extension String {
    static let status = "synthetic.status"
    static let videoOrientation = "synthetic.videoOrientation"
}
enum SCFrameStatus: Int { case complete = 0, idle, blank, suspended, started, stopped }
enum CaptureCommandStore {
    nonisolated(unsafe) static var finishRequested = false
    static func clearFinishRequest() { finishRequested = false }
    static func consumeFinishRequest() -> Bool {
        defer { finishRequested = false }
        return finishRequested
    }
}

@main
struct NativeCaptureRegressionsCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LongShotNativeRegressions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        CaptureStorage.testContainerURL = directory
        try testColdIntentAndInactiveVisibility()
        try testSceneGeometryAndUnknownGeometry()
        try testOrientationAndGeometryPersistence()
        try testRejectedFramesNeverCreateBoundaries()
        try testResumedGeometryHasOneBoundary()
        print("Native capture regressions passed (5 groups): cold/background intent; initially inactive host; scene geometry; metadata orientation/JPEG dimensions; pause/resume persistence and raw JPEG preservation. Synthetic SCK metadata keys; no stream/device coverage.")
    }

    private static func pipeline(_ visibility: ScreenCaptureHostVisibility) -> ScreenFramePipeline {
        ScreenFramePipeline(preprocessor: FramePreprocessor { _, _ in },
            hostIsForeground: { visibility.isForeground }, hostHasPartialWindow: { visibility.hasVisiblePartialWindow })
    }

    private static func testColdIntentAndInactiveVisibility() throws {
        for (state, scenes) in [(UIApplication.State.inactive, [UIScene.ActivationState]()),
                                (.inactive, [.background, .unattached]), (.background, [.background])] {
            let visibility = ScreenCaptureHostVisibility()
            let capture = pipeline(visibility)
            _ = try capture.beginSession(topCropRatio: 0)
            visibility.refresh(applicationState: state, sceneStates: scenes)
            progress(capture.consume(try sample(0)), 1, "Cold background intent must save its first target frame")
            _ = capture.finishSession(autoStopped: false, trimTrailingFrames: false)
        }
        let visibility = ScreenCaptureHostVisibility()
        let capture = pipeline(visibility)
        _ = try capture.beginSession(topCropRatio: 0)
        none(capture.consume(try sample(0)), "Unknown visibility excludes host UI")
        visibility.refresh(applicationState: .inactive, sceneStates: [.foregroundInactive])
        none(capture.consume(try sample(1)), "Initially inactive but visible host must be excluded")
        visibility.updateScene(activationState: .background, frameInDisplay: nil, displayBounds: .zero)
        progress(capture.consume(try sample(2)), 1, "No lead-in delay may lose the first target frame")
        _ = capture.finishSession(autoStopped: false, trimTrailingFrames: false)
    }

    private static func testSceneGeometryAndUnknownGeometry() throws {
        let portrait = CGRect(x: 0, y: 0, width: 402, height: 874)
        let landscape = CGRect(x: 0, y: 0, width: 874, height: 402)
        require(!ScreenCaptureHostVisibility.isPartialScene(portrait, in: portrait), "Ordinary portrait scene is full-screen")
        require(!ScreenCaptureHostVisibility.isPartialScene(landscape, in: landscape), "Ordinary landscape scene is full-screen")
        require(!ScreenCaptureHostVisibility.isPartialScene(landscape, in: portrait), "Transitional rotation outside display is unknown, not split")
        require(!ScreenCaptureHostVisibility.isPartialScene(.zero, in: portrait), "Missing geometry is unknown")
        require(ScreenCaptureHostVisibility.isPartialScene(CGRect(x: 210, y: 0, width: 192, height: 874), in: portrait), "Known split scene is partial")
        let visibility = ScreenCaptureHostVisibility()
        let capture = pipeline(visibility)
        let session = try capture.beginSession(topCropRatio: 0)
        visibility.refresh(applicationState: .background, sceneStates: [])
        progress(capture.consume(try sample(0)), 1, "Retain target before host appears")
        let original = try Data(contentsOf: CaptureStorage.frameURL(index: 0, sessionURL: session))
        for frame in [nil, .zero, landscape, portrait] {
            visibility.updateScene(activationState: .foregroundInactive, frameInDisplay: frame, displayBounds: portrait)
            none(capture.consume(try sample(1)), "Unknown/full ordinary geometry must exclude host without false split failure")
        }
        visibility.updateScene(activationState: .foregroundInactive,
            frameInDisplay: CGRect(x: 0, y: 0, width: 200, height: 874), displayBounds: portrait)
        guard case .failed = capture.consume(try sample(2)) else { fatalError("Known visible split scene must fail explicitly") }
        let completion = capture.finishSession(autoStopped: false, trimTrailingFrames: false)!
        require(completion.manifest.state == .failed && completion.manifest.frameCount == 1, "Split failure preserves committed count")
        require(try Data(contentsOf: CaptureStorage.frameURL(index: 0, sessionURL: session)) == original, "Failure must preserve original JPEG bytes")
    }

    private static func testOrientationAndGeometryPersistence() throws {
        let visibility = ScreenCaptureHostVisibility()
        visibility.refresh(applicationState: .background, sceneStates: [])
        let capture = pipeline(visibility)
        let session = try capture.beginSession(topCropRatio: 0)
        for (index, orientation) in [UInt32(1), 0, 3, 6, 8, 1].enumerated() {
            progress(capture.consume(try sample(index, orientation: orientation)), index + 1, "Oriented frame must commit")
        }
        let completion = capture.finishSession(autoStopped: false, trimTrailingFrames: false)!
        require(completion.manifest.segmentStarts == [0, 2, 3, 4, 5], "Same-size orientation changes and dimension changes need boundaries; invalid metadata normalizes up")
        let records = completion.manifest.geometrySegments!
        require(records.map(\.videoOrientation) == [1, 3, 6, 8, 1], "Normalized metadata must match the transform used for JPEGs")
        require(records.map(\.pixelWidth) == [120, 120, 260, 260, 120], "Orientation changes preserve native oriented dimensions")
        require(records.map(\.pixelHeight) == [260, 260, 120, 120, 260], "Rotated output is never scaled")
        for record in records {
            let image = UIImage(contentsOfFile: CaptureStorage.frameURL(index: record.startFrame, sessionURL: session).path)!.cgImage!
            require(image.width == record.pixelWidth && image.height == record.pixelHeight, "Manifest describes committed JPEG pixels")
        }
        require(try CaptureStorage.readManifest(at: session).geometrySegments == records, "Geometry survives disk round trip")
    }

    private static func testRejectedFramesNeverCreateBoundaries() throws {
        let visibility = ScreenCaptureHostVisibility()
        visibility.setForeground(false)
        let capture = pipeline(visibility)
        let session = try capture.beginSession(topCropRatio: 0)
        progress(capture.consume(try sample(0)), 1, "Initial frame")
        let original = try Data(contentsOf: CaptureStorage.frameURL(index: 0, sessionURL: session))
        require(capture.togglePageTransition(), "Pause")
        none(capture.consume(try sample(1, orientation: 6)), "Paused orientation cannot create geometry metadata")
        require(!capture.togglePageTransition(), "Resume")
        visibility.setForeground(true)
        none(capture.consume(try sample(2)), "Excluded host cannot commit a resumed page boundary")
        let invalid = try sample(3)
        CMSampleBufferInvalidate(invalid)
        visibility.setForeground(false)
        none(capture.consume(invalid), "Invalid target cannot commit a boundary")
        let completion = capture.finishSession(autoStopped: false, trimTrailingFrames: false)!
        require(completion.manifest.segmentStarts == [0], "Resume without a JPEG must not persist an empty page")
        require(completion.manifest.geometrySegments?.count == 1, "Rejected geometry is never persisted")
        require(try CaptureStorage.readManifest(at: session).segmentStarts == [0], "Empty resumed boundary must not reach disk")
        require(try Data(contentsOf: CaptureStorage.frameURL(index: 0, sessionURL: session)) == original, "Pause/finish preserves original JPEG bytes")
    }

    private static func testResumedGeometryHasOneBoundary() throws {
        let visibility = ScreenCaptureHostVisibility()
        visibility.setForeground(false)
        let capture = pipeline(visibility)
        _ = try capture.beginSession(topCropRatio: 0)
        progress(capture.consume(try sample(0)), 1, "First page")
        require(capture.togglePageTransition(), "Pause first page")
        require(!capture.togglePageTransition(), "Resume changed geometry")
        progress(capture.consume(try sample(1, orientation: 6)), 2, "Changed orientation after resume")
        require(capture.togglePageTransition(), "Pause second page")
        require(!capture.togglePageTransition(), "Resume without target")
        let completion = capture.finishSession(autoStopped: false, trimTrailingFrames: false)!
        require(completion.manifest.segmentStarts == [0, 1], "Resume and geometry change must share one committed boundary")
        require(completion.manifest.geometrySegments?.map(\.startFrame) == [0, 1], "No duplicate geometry record")
        _ = try capture.beginSession(topCropRatio: 0)
        progress(capture.consume(try sample(0)), 1, "New session clears pending resume")
        let next = capture.finishSession(autoStopped: false, trimTrailingFrames: false)!
        require(next.manifest.segmentStarts == [0], "No prior session boundary leaks")
    }

    private static func sample(_ index: Int, orientation: UInt32 = 1) throws -> CMSampleBuffer {
        var pixels: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
        guard CVPixelBufferCreate(kCFAllocatorDefault, 120, 260, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixels) == kCVReturnSuccess,
              let pixels else { throw CheckError.sample }
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            memset(base, 160, CVPixelBufferGetBytesPerRow(pixels) * CVPixelBufferGetHeight(pixels))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &format) == noErr,
              let format else { throw CheckError.sample }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 4),
            presentationTimeStamp: CMTime(value: Int64(index), timescale: 4), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) else { throw CheckError.sample }
        let entry = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        for (key, value) in [(String.videoOrientation, NSNumber(value: orientation)), (.status, NSNumber(value: SCFrameStatus.complete.rawValue))] {
            CFDictionarySetValue(entry, Unmanaged.passUnretained(key as CFString).toOpaque(), Unmanaged.passUnretained(value).toOpaque())
        }
        return sample
    }

    private static func require(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
    private static func none(_ event: ScreenFramePipeline.Event, _ message: String) {
        guard case .none = event else { fatalError(message) }
    }
    private static func progress(_ event: ScreenFramePipeline.Event, _ count: Int, _ message: String) {
        guard case .progress(count) = event else { fatalError(message) }
    }
}
private enum CheckError: Error { case sample }
