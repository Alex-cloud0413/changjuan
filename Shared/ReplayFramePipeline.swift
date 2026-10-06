import CoreImage
import CoreMedia
import Foundation
import ImageIO
import ReplayKit
import UIKit

final class ReplayFramePipeline: @unchecked Sendable {
    enum Event {
        case none
        case progress(Int)
        case failed(String)
    }

    struct Completion {
        let url: URL
        let manifest: CaptureManifest
    }

    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let leadInSeconds: TimeInterval

    private var sessionURL: URL?
    private var manifest: CaptureManifest?
    private var frameIndex = 0
    private var startedAtUptime = ProcessInfo.processInfo.systemUptime
    private var lastSavedPresentationTime: CMTime?

    init(leadInSeconds: TimeInterval = 0) {
        self.leadInSeconds = leadInSeconds
    }

    func beginSession(topCropRatio: Double) throws -> URL {
        let session = try CaptureStorage.createSession()
        sessionURL = session.0
        manifest = session.1
        manifest?.topCropRatio = topCropRatio
        frameIndex = 0
        startedAtUptime = ProcessInfo.processInfo.systemUptime
        lastSavedPresentationTime = nil
        CaptureCommandStore.clearFinishRequest()
        return session.0
    }

    func consume(_ sampleBuffer: CMSampleBuffer) -> Event {
        guard let sessionURL,
              CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer) else { return .none }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let lastSavedPresentationTime,
           presentationTime.isValid,
           lastSavedPresentationTime.isValid,
           CMTimeGetSeconds(presentationTime - lastSavedPresentationTime)
               < CaptureConstants.frameInterval {
            return .none
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - startedAtUptime >= leadInSeconds else { return .none }

        return autoreleasepool {
            guard let image = makeImage(from: sampleBuffer) else { return .none }
            do {
                guard let data = image.jpegData(compressionQuality: 0.9) else { return .none }
                let url = CaptureStorage.frameURL(index: frameIndex, sessionURL: sessionURL)
                try data.write(to: url, options: .atomic)
                frameIndex += 1
                manifest?.frameCount = frameIndex
                if let manifest {
                    try CaptureStorage.write(manifest, to: sessionURL)
                }
                lastSavedPresentationTime = presentationTime
            } catch {
                let message = error.localizedDescription
                _ = failSession(with: message)
                return .failed(message)
            }

            return .progress(frameIndex)
        }
    }

    func finishSession(trimTrailingFrames _: Bool = false) -> Completion? {
        guard let sessionURL, var manifest else { return nil }

        // Keep every captured frame. The scroll selector can exclude system
        // transitions without deleting a short recording's useful final pages.

        manifest.completedAt = Date()
        manifest.frameCount = frameIndex
        manifest.autoStopped = false

        if manifest.state != .failed {
            if frameIndex == 0 {
                manifest.state = .failed
                manifest.failureMessage = "没有捕获到可用画面。开始广播后，请切回目标 App 并向下滚动。"
            } else {
                // A coarse whole-screen difference is not proof of scrolling.
                // Let the stitcher assess the retained frames instead.
                manifest.state = .complete
                manifest.failureMessage = nil
            }
        }

        try? CaptureStorage.write(manifest, to: sessionURL)
        let completion = Completion(url: sessionURL, manifest: manifest)
        reset()
        return completion
    }

    func failSession(with message: String) -> Completion? {
        guard let sessionURL, var manifest else { return nil }
        manifest.completedAt = Date()
        manifest.frameCount = frameIndex
        manifest.autoStopped = false
        manifest.state = .failed
        manifest.failureMessage = message
        try? CaptureStorage.write(manifest, to: sessionURL)
        let completion = Completion(url: sessionURL, manifest: manifest)
        reset()
        return completion
    }

    private func reset() {
        sessionURL = nil
        manifest = nil
        frameIndex = 0
        lastSavedPresentationTime = nil
    }

    private func makeImage(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if let rawOrientation = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        ) as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: rawOrientation.uint32Value) {
            image = image.oriented(orientation)
        }

        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
