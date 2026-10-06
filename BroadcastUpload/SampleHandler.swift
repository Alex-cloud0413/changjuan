import CoreMedia
import Foundation
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let pipeline = ReplayFramePipeline()
    private let captureQueue = DispatchQueue(label: "com.gaoyiming.longshot.broadcast-frames")
    private var commandTimer: DispatchSourceTimer?
    private var status: ReplayBroadcastStore.Status?
    private var hasFinished = false
    private var lastPublishedAt = Date.distantPast
    private var lastHostCheckAt = Date.distantPast
    private var hostIsForeground = true

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        captureQueue.sync {
            do {
                let request = ReplayBroadcastStore.readRequest()
                let url = try pipeline.beginSession(topCropRatio: request?.topCropRatio ?? 0.075)
                hasFinished = false
                status = ReplayBroadcastStore.Status(
                    requestID: request?.id,
                    sessionID: url.lastPathComponent,
                    phase: .capturing,
                    frameCount: 0,
                    videoSampleCount: 0,
                    ignoredHostFrameCount: 0,
                    updatedAt: Date(),
                    failureMessage: nil
                )
                hostIsForeground = ReplayBroadcastStore.isHostForeground
                publishStatus(force: true)
                CaptureCommandStore.setState(.capturing)
                let timer = DispatchSource.makeTimerSource(queue: captureQueue)
                timer.schedule(deadline: .now(), repeating: .milliseconds(150))
                timer.setEventHandler { [weak self] in
                    guard let self, !self.hasFinished, let status = self.status else { return }
                    if ReplayBroadcastStore.consumeFinish(sessionID: status.sessionID) {
                        self.complete(stopSystemBroadcast: true)
                    } else {
                        self.publishStatus()
                    }
                }
                commandTimer = timer
                timer.resume()
            } catch {
                let failedStatus = ReplayBroadcastStore.Status(
                    requestID: ReplayBroadcastStore.readRequest()?.id,
                    sessionID: status?.sessionID ?? UUID().uuidString,
                    phase: .failed,
                    frameCount: 0,
                    videoSampleCount: 0,
                    ignoredHostFrameCount: 0,
                    updatedAt: Date(),
                    failureMessage: error.localizedDescription
                )
                try? ReplayBroadcastStore.writeStatus(failedStatus)
                CaptureCommandStore.setState(.failed)
                stopBroadcast(with: error)
            }
        }
    }

    override func broadcastPaused() {
        captureQueue.sync { publishStatus(force: true) }
    }

    override func broadcastResumed() {
        captureQueue.sync { publishStatus(force: true) }
    }

    override func broadcastFinished() {
        captureQueue.sync { complete(stopSystemBroadcast: false) }
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video else { return }
        captureQueue.sync {
            guard !hasFinished else { return }
            status?.videoSampleCount += 1
            let now = Date()
            if now.timeIntervalSince(lastHostCheckAt) >= 0.1 {
                hostIsForeground = ReplayBroadcastStore.isHostForeground
                lastHostCheckAt = now
            }
            // The host knows when its own UI is visible. This excludes LongShot
            // without guessing that the first/last N seconds must be discarded.
            if hostIsForeground {
                status?.ignoredHostFrameCount += 1
                return
            }
            switch pipeline.consume(sampleBuffer) {
            case .none:
                break
            case .progress(let frameCount):
                status?.frameCount = frameCount
                publishStatus()
            case .failed(let message):
                hasFinished = true
                commandTimer?.cancel()
                commandTimer = nil
                status?.phase = .failed
                status?.failureMessage = message
                publishStatus(force: true)
                CaptureCommandStore.setState(.failed)
                stopBroadcast(with: NSError(
                    domain: "com.gaoyiming.longshot.broadcast",
                    code: 1, userInfo: [NSLocalizedDescriptionKey: message]
                ))
            }
        }
    }

    /// The timer and all sample processing share one queue. Finishing commits
    /// the manifest before publishing completion, and cannot race a frame write.
    private func complete(stopSystemBroadcast: Bool) {
        guard !hasFinished else { return }
        hasFinished = true
        commandTimer?.cancel()
        commandTimer = nil
        guard let completion = pipeline.finishSession(trimTrailingFrames: false) else { return }
        let phase: CaptureSurfacePhase = completion.manifest.state == .complete ? .processing : .failed
        status?.frameCount = completion.manifest.frameCount
        status?.phase = phase
        status?.failureMessage = completion.manifest.failureMessage
        publishStatus(force: true)
        CaptureCommandStore.setState(phase, frameCount: completion.manifest.frameCount)
        if stopSystemBroadcast {
            // ReplayKit's upload extension exposes this as its only termination
            // API. The local capture is already complete, not a stitch failure.
            stopBroadcast(with: NSError(
                domain: "com.gaoyiming.longshot.broadcast.finished",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "长卷录制已完成，正在整理长图。"]
            ))
        }
    }

    private func stopBroadcast(with error: Error) {
        // Leave the frame queue before calling ReplayKit. A synchronous
        // broadcastFinished callback must never re-enter captureQueue.sync.
        DispatchQueue.main.async { [weak self] in
            self?.finishBroadcastWithError(error)
        }
    }

    private func publishStatus(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPublishedAt) >= 0.5,
              var snapshot = status else { return }
        snapshot.updatedAt = now
        status = snapshot
        try? ReplayBroadcastStore.writeStatus(snapshot)
        lastPublishedAt = now
    }
}
