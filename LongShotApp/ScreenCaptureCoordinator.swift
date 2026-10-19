import CoreImage
import CoreMedia
import Foundation
import ImageIO
import UIKit
#if LONGSHOT_SCREEN_CAPTURE_KIT && canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

@MainActor
protocol ScreenCaptureCoordinatorDelegate: AnyObject {
    func screenCaptureCoordinatorWillPresentPicker(_ coordinator: ScreenCaptureCoordinator)
    func screenCaptureCoordinatorDidCancelPicker(_ coordinator: ScreenCaptureCoordinator)
    func screenCaptureCoordinator(
        _ coordinator: ScreenCaptureCoordinator,
        didStartSessionAt sessionURL: URL
    )
    func screenCaptureCoordinator(
        _ coordinator: ScreenCaptureCoordinator,
        didCaptureFrameCount frameCount: Int
    )
    func screenCaptureCoordinator(
        _ coordinator: ScreenCaptureCoordinator,
        didFinishSessionAt sessionURL: URL,
        manifest: CaptureManifest
    )
    func screenCaptureCoordinator(
        _ coordinator: ScreenCaptureCoordinator,
        didFailWith message: String
    )
}

#if LONGSHOT_SCREEN_CAPTURE_KIT && canImport(ScreenCaptureKit)
/// Owns the iOS 27 ScreenCaptureKit picker and stream. Frame processing happens on a dedicated
/// serial queue so it continues while the app is in the background.
@MainActor
final class ScreenCaptureCoordinator: NSObject {
    weak var delegate: ScreenCaptureCoordinatorDelegate?

    private let picker = SCContentSharingPicker.shared
    private var pickerObserver: ScreenCapturePickerObserver?
    private let captureQueue = DispatchQueue(
        label: "com.gaoyiming.longshot.screen-capture",
        qos: .userInitiated
    )
    nonisolated private let pipeline = ScreenFramePipeline()
    nonisolated private let streamGate = ScreenCaptureStreamGate()

    private var stream: SCStream?
    private var captureGeneration = UUID()
    private var isStarting = false
    private var isStopping = false
    private var pickerBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var awaitingPicker = false
    private var pickerWaiters: [CheckedContinuation<Void, Error>] = []
    private var pickerFailure: Error?

    var isChoosingSource: Bool { awaitingPicker }
    var isPausedForNextPage: Bool { captureQueue.sync { pipeline.isPausedForNextPage } }

    var isCapturing: Bool {
        !isStarting && !isStopping && stream?.isCapturing == true
    }

    func presentPicker() {
        guard !isStarting, !isStopping, stream == nil else {
            recordEvent("requestBlocked", detail: "starting=\(isStarting),stopping=\(isStopping),stream=\(stream != nil)")
            return
        }
        if awaitingPicker {
            // A second explicit tap retries a presentation lost by the system;
            // keep the same generation, observer and consent waiters.
            recordEvent("represent")
            picker.present(using: .display)
            return
        }
        pickerFailure = nil
        captureGeneration = UUID()
        recordEvent("request")
        guard picker.isAvailable else {
            let message = "这台设备当前不允许屏幕捕获，请检查系统的屏幕录制限制。"
            pickerFailure = NSError(domain: "com.gaoyiming.longshot.capture", code: 3,
                userInfo: [NSLocalizedDescriptionKey: message])
            recordEvent("unavailable")
            delegate?.screenCaptureCoordinator(self, didFailWith: message)
            return
        }

        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration

        let observer = ScreenCapturePickerObserver(owner: self, generation: captureGeneration)
        pickerObserver = observer
        picker.add(observer)
        if !picker.isActive { picker.isActive = true }

        awaitingPicker = true
        beginPickerBackgroundTask()
        delegate?.screenCaptureCoordinatorWillPresentPicker(self)
        recordEvent("present")
        picker.present(using: .display)
    }

    /// Keep the background LiveActivityIntent running through system consent,
    /// not merely until present() returns. This does not accept consent for the user.
    func waitForPickerResolution() async throws {
        guard awaitingPicker else {
            if let pickerFailure { throw pickerFailure }
            return
        }
        try await withCheckedThrowingContinuation { pickerWaiters.append($0) }
    }

    private func resolvePicker(error: Error? = nil) {
        awaitingPicker = false
        pickerFailure = error
        let waiters = pickerWaiters
        pickerWaiters.removeAll()
        for waiter in waiters {
            if let error { waiter.resume(throwing: error) }
            else { waiter.resume() }
        }
    }

    func stopCapture() async {
        await finishCapture(autoStopped: false, stopStream: true, trimTrailingFrames: true)
    }

    func togglePageTransition() -> Bool {
        guard isCapturing else { return false }
        return captureQueue.sync { pipeline.togglePageTransition() }
    }

    fileprivate func pickerDidCancel(generation: UUID) async {
        guard generation == captureGeneration, awaitingPicker else { return }
        await abortCapture(
            message: "你取消了屏幕捕获。", cancelled: true, stopStream: true
        )
    }

    fileprivate func pickerDidFail(with error: Error, generation: UUID) async {
        guard generation == captureGeneration, awaitingPicker else { return }
        await abortCapture(message: friendlyMessage(for: error), stopStream: true)
    }

    fileprivate func startCapture(with filter: SCContentFilter, generation: UUID) async {
        guard generation == captureGeneration, awaitingPicker,
              !isStarting, !isStopping, stream == nil else { return }
        isStarting = true
        recordEvent("selection")
        var startingStream: SCStream?

        do {
            let topCropRatio = Self.systemTopCropRatio()
            let sessionURL = try captureQueue.sync {
                try pipeline.beginSession(topCropRatio: topCropRatio)
            }

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = false

            let newStream = SCStream(
                filter: filter,
                configuration: configuration,
                delegate: self
            )
            // Retain and identify the stream before the first suspension: an
            // error or cancellation can arrive while startCapture is awaiting.
            startingStream = newStream
            stream = newStream
            captureQueue.sync { streamGate.activate(newStream, generation: generation) }
            try newStream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: captureQueue
            )
            try await newStream.startCapture()

            guard generation == captureGeneration, awaitingPicker,
                  isStarting, !isStopping, stream === newStream else {
                // A pending start may complete after cancellation. Never let
                // that completion resurrect the old capture or a sealed pipeline.
                try? await newStream.stopCapture()
                return
            }
            isStarting = false
            endPickerBackgroundTask()
            recordEvent("started")
            delegate?.screenCaptureCoordinator(self, didStartSessionAt: sessionURL)
            resolvePicker()
        } catch {
            guard generation == captureGeneration, awaitingPicker, !isStopping else {
                if let startingStream { try? await startingStream.stopCapture() }
                return
            }
            await abortCapture(message: friendlyMessage(for: error), stopStream: true)
        }
    }

    fileprivate func handleUnexpectedStop(
        _ error: Error,
        from sourceStream: SCStream,
        generation: UUID,
        streamAlreadyStopped: Bool
    ) async {
        guard isCurrentStream(sourceStream, generation: generation), !isStopping else { return }

        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain,
           nsError.code == -3817 { // SCStreamErrorUserStopped
            await finishCapture(autoStopped: false, stopStream: false, trimTrailingFrames: true)
            return
        }

        await abortCapture(
            message: friendlyMessage(for: error), stopStream: !streamAlreadyStopped
        )
    }

    /// Pipeline errors are not system-stop notifications. Stop the retained
    /// stream explicitly, and invalidate callbacks before delivering one result.
    private func abortCapture(
        message: String,
        cancelled: Bool = false,
        stopStream: Bool
    ) async {
        guard !isStopping else { return }
        isStopping = true
        isStarting = false
        let finishingTask = UIApplication.shared.beginBackgroundTask(withName: "清理屏幕捕获")
        defer {
            if finishingTask != .invalid { UIApplication.shared.endBackgroundTask(finishingTask) }
        }
        let completion = captureQueue.sync {
            streamGate.invalidate()
            pipeline.sealForFinishing()
            _ = pipeline.failSession(with: message)
            return pipeline.finishSession(autoStopped: false, trimTrailingFrames: false)
        }
        if let completion {
            CaptureProcessingDiagnostics.record("capturePipelineSnapshot",
                sessionID: completion.url.lastPathComponent,
                values: completion.diagnostics)
        }
        let currentStream = stream
        stream = nil
        if stopStream, let currentStream { try? await currentStream.stopCapture() }
        recordEvent(cancelled ? "cancelled" : "error", detail: message)
        let pickerError = cancelled ? nil : NSError(
            domain: "com.gaoyiming.longshot.capture", code: 4,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        deactivatePicker(error: pickerError)
        isStopping = false

        if cancelled {
            delegate?.screenCaptureCoordinatorDidCancelPicker(self)
        } else if let completion {
            delegate?.screenCaptureCoordinator(
                self,
                didFinishSessionAt: completion.url,
                manifest: completion.manifest
            )
        } else {
            delegate?.screenCaptureCoordinator(self, didFailWith: message)
        }
    }

    fileprivate func requestAutomaticStop(from sourceStream: SCStream, generation: UUID) async {
        guard !isStopping, isCurrentStream(sourceStream, generation: generation) else { return }
        await finishCapture(autoStopped: true, stopStream: true, trimTrailingFrames: false)
    }

    fileprivate func requestExplicitStop(from sourceStream: SCStream, generation: UUID) async {
        guard !isStopping, isCurrentStream(sourceStream, generation: generation) else { return }
        await finishCapture(autoStopped: false, stopStream: true, trimTrailingFrames: true)
    }

    fileprivate func isCurrentStream(_ sourceStream: SCStream, generation: UUID) -> Bool {
        generation == captureGeneration && stream === sourceStream
    }

    fileprivate func reportProgress(_ count: Int, from sourceStream: SCStream, generation: UUID) {
        guard !isStarting, !isStopping, isCurrentStream(sourceStream, generation: generation) else { return }
        delegate?.screenCaptureCoordinator(self, didCaptureFrameCount: count)
    }

    private func finishCapture(
        autoStopped: Bool,
        stopStream: Bool,
        trimTrailingFrames: Bool
    ) async {
        guard !isStopping else { return }
        let hasActiveSession = captureQueue.sync {
            pipeline.hasActiveSession
        }
        guard stream != nil || hasActiveSession else {
            deactivatePicker()
            return
        }

        isStopping = true
        isStarting = false
        CaptureProcessingDiagnostics.record("captureFinishStarted", values: ["autoStopped": autoStopped])
        let finishingTask = CaptureProcessingBackgroundTask(name: "完成屏幕捕获", stage: "captureFinish")
        defer { finishingTask.end() }
        let drainStartedAt = ProcessInfo.processInfo.systemUptime
        captureQueue.sync {
            // Drain already queued samples before sealing; do not erase any
            // committed tail frames. Later callbacks cannot enter a new session.
            streamGate.invalidate()
            pipeline.sealForFinishing()
        }
        CaptureProcessingDiagnostics.record("captureQueueDrained", values: [
            "seconds": ProcessInfo.processInfo.systemUptime - drainStartedAt
        ])
        let currentStream = stream
        stream = nil

        if stopStream, let currentStream {
            CaptureProcessingDiagnostics.record("streamStopStarted")
            let streamStopStartedAt = Date()
            try? await currentStream.stopCapture()
            CaptureProcessingDiagnostics.record("streamStopFinished", values: [
                "seconds": Date().timeIntervalSince(streamStopStartedAt)
            ])
        }

        let completion = captureQueue.sync {
            pipeline.finishSession(
                autoStopped: autoStopped,
                trimTrailingFrames: trimTrailingFrames
            )
        }
        if let completion {
            CaptureProcessingDiagnostics.record("capturePipelineSnapshot",
                sessionID: completion.url.lastPathComponent,
                values: completion.diagnostics)
        }
        recordEvent("stopped", detail: completion.map { "frames=\($0.manifest.frameCount)" })
        deactivatePicker()
        isStopping = false

        guard let completion else { return }
        delegate?.screenCaptureCoordinator(
            self,
            didFinishSessionAt: completion.url,
            manifest: completion.manifest
        )
    }

    private func deactivatePicker(error: Error? = nil) {
        resolvePicker(error: error)
        endPickerBackgroundTask()
        // isActive registers the singleton with system sharing UI; it is not
        // the stream's running state. Keep registration through repeat captures
        // rather than tearing it down and re-enabling it in a background intent.
        if let pickerObserver { picker.remove(pickerObserver) }
        pickerObserver = nil
    }

    private func beginPickerBackgroundTask() {
        endPickerBackgroundTask()
        let generation = captureGeneration
        pickerBackgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "等待屏幕捕获选择"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == captureGeneration, awaitingPicker else { return }
                endPickerBackgroundTask()
                await pickerDidFail(
                    with: NSError(
                        domain: "com.gaoyiming.longshot.capture",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey: "系统屏幕选择等待超时，请重新从控制中心开始。"
                        ]
                    ),
                    generation: generation
                )
            }
        }
    }

    private func endPickerBackgroundTask() {
        guard pickerBackgroundTask != .invalid else { return }
        let task = pickerBackgroundTask
        pickerBackgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    /// Small local lifecycle metadata only, never screenshots or screen content.
    private func recordEvent(_ name: String, detail: String? = nil) {
        do {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = directory.appendingPathComponent("LongShotCaptureLaunchEvents.json")
            var events = (try? Data(contentsOf: url)).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [[String: String]]
            } ?? []
            var event = [
                "event": name,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "generation": captureGeneration.uuidString,
                "applicationState": String(UIApplication.shared.applicationState.rawValue),
                "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                "pickerActive": String(picker.isActive),
                "awaitingPicker": String(awaitingPicker)
            ]
            if let detail { event["detail"] = detail }
            events.append(event)
            try JSONSerialization.data(withJSONObject: Array(events.suffix(80)), options: [.prettyPrinted, .sortedKeys])
                .write(to: url, options: .atomic)
        } catch { /* Diagnostics never interrupt capture. */ }
    }

    static func systemTopCropRatio() -> Double {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.windows.contains(where: \.isKeyWindow) }) ?? scenes.first
        guard let scene else { return 0.075 }
        let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        let safeTop = window?.safeAreaInsets.top ?? 0
        let statusTop = scene.statusBarManager?.statusBarFrame.height ?? 0
        let top = max(safeTop, statusTop)
        let height = scene.screen.bounds.height
        guard top > 0, height > 0 else { return 0.075 }
        return Double(top / height)
    }

    private nonisolated func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else {
            return error.localizedDescription
        }

        switch nsError.code {
        case -3801:
            return "你取消了屏幕捕获授权。"
        case -3803:
            return "屏幕捕获权限尚未配置完成，请重新安装此版本后再试。"
        case -3822:
            return "可用存储空间不足，无法继续生成长图。"
        case -3824:
            return "系统没有允许长卷在后台继续捕获，请重新安装此版本后再试。"
        default:
            return error.localizedDescription
        }
    }
}

extension ScreenCaptureCoordinator: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, let generation = streamGate.generation(for: stream) else { return }

        switch pipeline.consume(sampleBuffer) {
        case .none:
            break
        case .progress(let frameCount):
            Task { @MainActor [weak self] in
                guard let self else { return }
                reportProgress(frameCount, from: stream, generation: generation)
            }
        case .shouldStop(let autoStopped, let trimTrailingFrames):
            Task { @MainActor [weak self] in
                if autoStopped {
                    await self?.requestAutomaticStop(from: stream, generation: generation)
                } else if trimTrailingFrames {
                    await self?.requestExplicitStop(from: stream, generation: generation)
                }
            }
        case .failed(let message):
            Task { @MainActor [weak self] in
                guard let self else { return }
                await handleUnexpectedStop(
                    NSError(
                        domain: "com.gaoyiming.longshot.capture",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    ),
                    from: stream,
                    generation: generation,
                    streamAlreadyStopped: false
                )
            }
        }
    }
}

extension ScreenCaptureCoordinator: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard let generation = streamGate.generation(for: stream) else { return }
        Task { @MainActor [weak self] in
            await self?.handleUnexpectedStop(
                error, from: stream, generation: generation, streamAlreadyStopped: true
            )
        }
    }
}

private final class ScreenCapturePickerObserver: NSObject,
    SCContentSharingPickerObserver,
    @unchecked Sendable {
    private weak var owner: ScreenCaptureCoordinator?
    private let generation: UUID

    init(owner: ScreenCaptureCoordinator, generation: UUID) {
        self.owner = owner
        self.generation = generation
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak owner, generation] in
            await owner?.startCapture(with: filter, generation: generation)
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor [weak owner, generation] in
            await owner?.pickerDidCancel(generation: generation)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak owner, generation] in
            await owner?.pickerDidFail(with: error, generation: generation)
        }
    }
}

/// The sample queue and framework delegate queue may outlive a stream. A
/// generation token rejects their old buffers and actor tasks after replacement.
private final class ScreenCaptureStreamGate: @unchecked Sendable {
    private let lock = NSLock()
    private var streamID: ObjectIdentifier?
    private var activeGeneration: UUID?

    func activate(_ stream: SCStream, generation: UUID) {
        lock.lock()
        defer { lock.unlock() }
        streamID = ObjectIdentifier(stream)
        activeGeneration = generation
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        streamID = nil
        activeGeneration = nil
    }

    func generation(for stream: SCStream) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard streamID == ObjectIdentifier(stream) else { return nil }
        return activeGeneration
    }
}

/// The app-owned SCK stream can read visibility without cross-process I/O.
/// Scene callbacks publish on the main actor; samples read on the capture queue.
final class ScreenCaptureHostVisibility: @unchecked Sendable {
    static let shared = ScreenCaptureHostVisibility()

    private let lock = NSLock()
    private var foreground = false

    var isForeground: Bool {
        lock.lock()
        defer { lock.unlock() }
        return foreground
    }

    func setForeground(_ value: Bool) {
        lock.lock()
        foreground = value
        lock.unlock()
    }
}

/// Bounded, content-free counters owned exclusively by the serial capture queue.
/// No per-frame file I/O, hashes, screen text or image paths are collected.
struct ScreenFramePipelineDiagnostics {
    enum Rejection: String, CaseIterable {
        case sealed, finishRequest, paused, hostForeground, invalidBuffer, notReady
        case incompleteStatus, throttled, missingImage, encoding, writeFailed
    }

    private let beganAt = ProcessInfo.processInfo.systemUptime
    private(set) var callbackCount = 0
    private(set) var accepted = 0
    private var rejected: [String: Int] = [:]
    private var statuses: [String: Int] = [:]
    private var firstPTS: Double?
    private var lastPTS: Double?
    private var previousPTS: CMTime?
    private var invalidPTS = 0
    private var nonfinitePTS = 0
    private var backwardPTS = 0
    private var repeatedPTS = 0
    private var epochChanges = 0
    private var maximumPTSGap: Double = 0
    private var zeroDeltaFromSaved = 0
    private var negativeDeltaFromSaved = 0
    private var maximumCallbackGap: Double = 0
    private var firstCallbackAt: Double?
    private var previousCallbackAt: Double?
    private var samples: [[String: Any]] = []

    mutating func observeCallback(presentationTime: CMTime, lastSavedTime: CMTime?) {
        callbackCount += 1
        let now = ProcessInfo.processInfo.systemUptime
        if firstCallbackAt == nil { firstCallbackAt = now }
        if let previousCallbackAt {
            maximumCallbackGap = max(maximumCallbackGap, now - previousCallbackAt)
        }
        previousCallbackAt = now
        guard presentationTime.isValid else { invalidPTS += 1; return }
        let seconds = CMTimeGetSeconds(presentationTime)
        guard seconds.isFinite else { nonfinitePTS += 1; return }
        if firstPTS == nil { firstPTS = seconds }
        lastPTS = seconds
        if let previousPTS {
            if previousPTS.epoch != presentationTime.epoch {
                epochChanges += 1
            } else {
                let delta = CMTimeGetSeconds(presentationTime - previousPTS)
                if delta.isFinite {
                    if delta < 0 { backwardPTS += 1 }
                    if delta == 0 { repeatedPTS += 1 }
                    maximumPTSGap = max(maximumPTSGap, delta)
                }
            }
        }
        previousPTS = presentationTime
        if let lastSavedTime, lastSavedTime.isValid {
            let delta = CMTimeGetSeconds(presentationTime - lastSavedTime)
            if delta.isFinite {
                if delta == 0 { zeroDeltaFromSaved += 1 }
                if delta < 0 { negativeDeltaFromSaved += 1 }
            }
        }
    }

    mutating func reject(_ reason: Rejection) {
        rejected[reason.rawValue, default: 0] += 1
    }

    mutating func observeStatus(_ status: String) {
        statuses[status, default: 0] += 1
    }

    mutating func accept(index: Int, presentationTime: CMTime, width: Int, height: Int, bytes: Int) {
        accepted += 1
        guard samples.count < 12 else { return }
        var sample: [String: Any] = ["index": index,
            "uptimeOffset": ProcessInfo.processInfo.systemUptime - beganAt,
            "width": width, "height": height, "jpegBytes": bytes]
        let seconds = CMTimeGetSeconds(presentationTime)
        if presentationTime.isValid, seconds.isFinite { sample["presentationTime"] = seconds }
        sample["presentationTimeEpoch"] = presentationTime.epoch
        samples.append(sample)
    }

    func snapshot() -> [String: Any] {
        var counts = Dictionary(uniqueKeysWithValues: Rejection.allCases.map {
            ($0.rawValue, rejected[$0.rawValue, default: 0])
        })
        counts["accepted"] = accepted
        let now = ProcessInfo.processInfo.systemUptime
        var result: [String: Any] = ["schemaVersion": 1, "callbackCount": callbackCount, "counts": counts,
            "frameStatusCounts": statuses, "wallSeconds": now - beganAt,
            "invalidPTSCount": invalidPTS, "nonfinitePTSCount": nonfinitePTS,
            "backwardPTSCount": backwardPTS, "repeatedPTSCount": repeatedPTS,
            "ptsEpochChangeCount": epochChanges, "maximumPTSGap": maximumPTSGap,
            "zeroDeltaFromSavedCount": zeroDeltaFromSaved,
            "negativeDeltaFromSavedCount": negativeDeltaFromSaved,
            "maximumCallbackGap": maximumCallbackGap, "acceptedSamples": samples]
        if let firstPTS { result["firstPresentationTime"] = firstPTS }
        if let lastPTS { result["lastPresentationTime"] = lastPTS }
        if let firstCallbackAt { result["firstCallbackOffset"] = firstCallbackAt - beganAt }
        if let previousCallbackAt {
            result["lastCallbackOffset"] = previousCallbackAt - beganAt
            result["lastCallbackAgeSeconds"] = now - previousCallbackAt
        }
        return result
    }
}

final class ScreenFramePipeline: @unchecked Sendable {
    enum Event {
        case none
        case progress(Int)
        case shouldStop(autoStopped: Bool, trimTrailingFrames: Bool)
        case failed(String)
    }

    struct Completion {
        let url: URL
        let manifest: CaptureManifest
        let diagnostics: [String: Any]
    }

    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let preprocessor: FramePreprocessor
    private let hostIsForeground: @Sendable () -> Bool

    private var sessionURL: URL?
    private var manifest: CaptureManifest?
    private var frameIndex = 0
    private var lastSavedPresentationTime: CMTime?
    private var hasRequestedFinish = false
    private var diagnostics = ScreenFramePipelineDiagnostics()
    private(set) var isPausedForNextPage = false

    init(preprocessor: FramePreprocessor = FramePreprocessor(), hostIsForeground: @escaping @Sendable () -> Bool = {
        ScreenCaptureHostVisibility.shared.isForeground
    }) {
        self.hostIsForeground = hostIsForeground
        self.preprocessor = preprocessor
    }

    var hasActiveSession: Bool {
        sessionURL != nil
    }

    func beginSession(topCropRatio: Double, options: CaptureOptions = CaptureOptions.load()) throws -> URL {
        let session = try CaptureStorage.createSession()
        sessionURL = session.0
        manifest = session.1
        manifest?.topCropRatio = topCropRatio
        manifest?.segmentStarts = [0]
        manifest?.captureOptions = options
        if let manifest { try CaptureStorage.write(manifest, to: session.0) }
        frameIndex = 0
        lastSavedPresentationTime = nil
        hasRequestedFinish = false
        isPausedForNextPage = false
        diagnostics = ScreenFramePipelineDiagnostics()
        CaptureCommandStore.clearFinishRequest()
        return session.0
    }

    func consume(_ sampleBuffer: CMSampleBuffer) -> Event {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        diagnostics.observeCallback(presentationTime: presentationTime, lastSavedTime: lastSavedPresentationTime)
        guard !hasRequestedFinish else { diagnostics.reject(.sealed); return .none }

        if CaptureCommandStore.consumeFinishRequest() {
            diagnostics.reject(.finishRequest)
            hasRequestedFinish = true
            return .shouldStop(autoStopped: false, trimTrailingFrames: true)
        }

        guard !isPausedForNextPage else { diagnostics.reject(.paused); return .none }

        // Exclude our actual foreground UI, rather than losing a fixed amount
        // of useful content at the beginning and end of every capture.
        guard !hostIsForeground() else { diagnostics.reject(.hostForeground); return .none }

        guard let sessionURL else { diagnostics.reject(.notReady); return .none }
        guard CMSampleBufferIsValid(sampleBuffer) else { diagnostics.reject(.invalidBuffer); return .none }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { diagnostics.reject(.notReady); return .none }
        guard isCompleteFrame(sampleBuffer) else { diagnostics.reject(.incompleteStatus); return .none }

        if let lastSavedPresentationTime,
           presentationTime.isValid,
           lastSavedPresentationTime.isValid,
           CMTimeGetSeconds(presentationTime - lastSavedPresentationTime)
               < CaptureConstants.frameInterval {
            diagnostics.reject(.throttled)
            return .none
        }

        return autoreleasepool {
            guard let image = makeImage(from: sampleBuffer) else { diagnostics.reject(.missingImage); return .none }

            do {
                guard let data = image.jpegData(compressionQuality: 0.9) else { diagnostics.reject(.encoding); return .none }
                let url = CaptureStorage.frameURL(index: frameIndex, sessionURL: sessionURL)
                try data.write(to: url, options: .atomic)
                frameIndex += 1
                manifest?.frameCount = frameIndex
                if let manifest {
                    try CaptureStorage.write(manifest, to: sessionURL)
                }
                lastSavedPresentationTime = presentationTime
                diagnostics.accept(index: frameIndex - 1, presentationTime: presentationTime,
                    width: image.cgImage?.width ?? 0, height: image.cgImage?.height ?? 0, bytes: data.count)
                // The full-quality JPEG is already committed. A slow or full
                // preparation queue never drops capture frames or delays finish.
                preprocessor.enqueue(data, for: url, options: manifest?.captureOptions ?? CaptureOptions())
            } catch {
                diagnostics.reject(.writeFailed)
                let message = error.localizedDescription
                _ = failSession(with: message)
                return .failed(message)
            }

            return .progress(frameIndex)
        }
    }

    /// Called on the serial sample queue before awaiting the system's stop.
    /// Already committed images remain available; later callbacks cannot add UI.
    func sealForFinishing() {
        hasRequestedFinish = true
    }

    /// Called only on the capture queue. No fixed delay, lost tail trim, or
    /// second system consent. Empty page transitions never create empty ranges.
    @discardableResult
    func togglePageTransition() -> Bool {
        guard sessionURL != nil, !hasRequestedFinish else { return false }
        isPausedForNextPage.toggle()
        if !isPausedForNextPage {
            var starts = manifest?.segmentStarts ?? [0]
            if frameIndex > (starts.last ?? 0) { starts.append(frameIndex) }
            manifest?.segmentStarts = starts
            lastSavedPresentationTime = nil
        }
        if let manifest, let sessionURL { try? CaptureStorage.write(manifest, to: sessionURL) }
        return isPausedForNextPage
    }

    func finishSession(autoStopped: Bool, trimTrailingFrames _: Bool) -> Completion? {
        guard let sessionURL, var manifest else { return nil }

        // Keep the originals. The stitcher selects a scroll sequence without
        // erasing the last pages of a short capture to guess where UI begins.

        manifest.completedAt = Date()
        manifest.frameCount = frameIndex
        manifest.autoStopped = autoStopped

        if manifest.state != .failed {
            if frameIndex == 0 {
                manifest.state = .failed
                manifest.failureMessage = "没有捕获到可用画面。请选择整个屏幕，并在提示后切到目标 App。"
            } else {
                manifest.state = .complete
                manifest.failureMessage = nil
            }
        }

        try? CaptureStorage.write(manifest, to: sessionURL)
        let completion = Completion(url: sessionURL, manifest: manifest, diagnostics: diagnostics.snapshot())
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
        self.manifest = manifest
        hasRequestedFinish = true
        return Completion(url: sessionURL, manifest: manifest, diagnostics: diagnostics.snapshot())
    }

    private func reset() {
        sessionURL = nil
        manifest = nil
        frameIndex = 0
        lastSavedPresentationTime = nil
        hasRequestedFinish = false
        isPausedForNextPage = false
    }

    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
#if LONGSHOT_SCK_METADATA_STUB
        // Standalone JPEG/queue checks on an older simulator cannot load SCK.
        // Release builds always validate the actual ScreenCaptureKit metadata.
        diagnostics.observeStatus("metadataStub")
        return true
#else
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
        let attachment = attachments.first,
        let rawStatus = attachment[.status] as? Int else {
            diagnostics.observeStatus("missing")
            return true
        }
        diagnostics.observeStatus(String(rawStatus))
        guard let status = SCFrameStatus(rawValue: rawStatus) else { return true }
        return status == .complete || status == .started
#endif
    }

    private func makeImage(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        var image = CIImage(cvPixelBuffer: pixelBuffer)
#if !LONGSHOT_SCK_METADATA_STUB
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
        let rawOrientation = attachments.first?[.videoOrientation] as? NSNumber,
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation.uint32Value) {
            image = image.oriented(orientation)
        }
#endif

        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
#else
/// ScreenCaptureKit is device-only. Keeping a small simulator implementation lets the
/// real onboarding and home UI be rendered for App Store screenshots without changing
/// the shipping iOS 27 capture path.
@MainActor
final class ScreenCaptureCoordinator: NSObject {
    weak var delegate: ScreenCaptureCoordinatorDelegate?

    var isChoosingSource: Bool { false }
    var isCapturing: Bool { false }
    var isPausedForNextPage: Bool { false }
    func togglePageTransition() -> Bool { false }

    func presentPicker() {
        delegate?.screenCaptureCoordinator(
            self,
            didFailWith: "屏幕捕获需要在 iPhone 真机上使用。"
        )
    }

    func waitForPickerResolution() async {}
    func stopCapture() async {}
    func refreshSession() {}
    func cancelPicker() {}

    static func systemTopCropRatio() -> Double { 0 }
}

final class ScreenCaptureHostVisibility: @unchecked Sendable {
    static let shared = ScreenCaptureHostVisibility()

    var isForeground: Bool { true }

    func setForeground(_: Bool) {}
}
#endif
