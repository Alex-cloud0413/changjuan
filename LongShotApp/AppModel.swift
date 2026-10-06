import Combine
import Foundation
import Photos
import UIKit
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Phase: Equatable {
        case idle
        case choosingSource
        case capturing(Int)
        case processing
        case ready(pageCount: Int, accepted: Int, skipped: Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var outputURLs: [URL] = []
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var lastCaptureDate: Date?
    @Published private(set) var isSavedPreviewRequested = false
    @Published private(set) var isSavedThumbnailPresented = false
    @Published private(set) var isPageTransitionPaused = false

    private lazy var captureCoordinator: ScreenCaptureCoordinator = {
        let coordinator = ScreenCaptureCoordinator()
        coordinator.delegate = self
        return coordinator
    }()

    private var activeSessionURL: URL?
    private var processingSessionID: String?
    private let liveActivityManager = CaptureLiveActivityManager()
    private let resultNotificationManager = ResultNotificationManager()
    private let savedResultPresentationStore = SavedResultPresentationStore()
    private var thumbnailSessionID: String?
    private var explicitPreviewSessionID: String?
    private var processingBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var finishRequest: (sessionID: String, date: Date)?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: CaptureCommandStore.startRequested)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handlePendingStartRequest()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: CaptureCommandStore.finishRequested)
            .sink { [weak self] _ in
                Task { @MainActor in _ = await self?.handlePendingFinishRequest() }
            }
            .store(in: &cancellables)
    }

    func activate() async {
#if LONGSHOT_BENCHMARK
        if ProcessInfo.processInfo.arguments.contains("--benchmark-latest") { return }
#endif
#if LONGSHOT_SCREEN_CAPTURE_KIT
        updateHostVisibility()
#else
        ReplayBroadcastStore.setHostForeground(UIApplication.shared.applicationState != .background)
        captureCoordinator.refreshSession()
        exportCaptureDiagnostics()
#endif
        if await handlePendingFinishRequest() {
            return
        }
        await refreshAndProcessIfNeeded()
        handlePendingStartRequest()
        restorePendingSavedThumbnailIfNeeded()
        if UIApplication.shared.applicationState == .active, !isBusy, !isSavedPreviewRequested {
            await resultNotificationManager.prepareAuthorizationIfNeeded()
        }
        await deliverDeferredResultNotificationIfNeeded()
    }

    func prepareForSystemCommands() {
#if LONGSHOT_SCREEN_CAPTURE_KIT
        // iOS 27 intents call the model directly. Discard legacy shared-defaults
        // commands before a cold launch can race the new invocation.
        _ = CaptureCommandStore.consumeStartRequest()
        CaptureCommandStore.clearFinishRequest()
#else
        Task {
            if !(await handlePendingFinishRequest()) {
                handlePendingStartRequest()
            }
        }
#endif
    }

#if LONGSHOT_SCREEN_CAPTURE_KIT
    func performSystemCaptureAction(finishOnly: Bool) async throws {
        _ = CaptureCommandStore.consumeStartRequest()
        CaptureCommandStore.clearFinishRequest()
        updateHostVisibility()
        if captureCoordinator.isCapturing {
            await stopCapture()
        } else if captureCoordinator.isChoosingSource {
            if !finishOnly { await captureCoordinator.waitForPickerResolution() }
        } else if !finishOnly, !isBusy {
            beginCapture()
            await captureCoordinator.waitForPickerResolution()
        }
    }

    private func updateHostVisibility() {
        switch UIApplication.shared.applicationState {
        case .active: ScreenCaptureHostVisibility.shared.setForeground(true)
        case .background: ScreenCaptureHostVisibility.shared.setForeground(false)
        case .inactive: break // Preserve whether our UI was visible under a system sheet.
        @unknown default: break
        }
    }
#endif

    func beginCapture() {
        guard !isBusy else { return }
#if LONGSHOT_SCREEN_CAPTURE_KIT
        updateHostVisibility()
#endif
        dismissSavedThumbnail()
        explicitPreviewSessionID = nil
        isSavedPreviewRequested = false
        outputURLs = []
        previewImage = nil
        processingSessionID = nil
        finishRequest = nil
        isPageTransitionPaused = false
        phase = .choosingSource
        updateSystemState(.choosing)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        captureCoordinator.presentPicker()
    }

    func stopCapture() async {
        if captureCoordinator.isCapturing, let sessionID = activeSessionURL?.lastPathComponent {
            finishRequest = (sessionID, Date())
        }
        await captureCoordinator.stopCapture()
    }

    func togglePageTransition() async {
#if LONGSHOT_SCREEN_CAPTURE_KIT
        guard captureCoordinator.isCapturing else { return }
        isPageTransitionPaused = captureCoordinator.togglePageTransition()
        let count: Int
        if case .capturing(let value) = phase { count = value } else { count = 0 }
        updateSystemState(isPageTransitionPaused ? .paused : .capturing, frameCount: count)
        liveActivityManager.markPageTransition(paused: isPageTransitionPaused, frameCount: count)
#endif
    }

    func refreshAndProcessIfNeeded() async {
        // A notification may select an older result during cold launch. Scene
        // activation must not replace that explicit selection with the latest.
        guard explicitPreviewSessionID == nil else { return }
        // System confirmations also activate the app. Do not restore an old
        // failure over a picker, active extension, or in-progress stitch.
        if captureCoordinator.isChoosingSource || phase == .processing { return }
        if captureCoordinator.isCapturing {
            return
        }

        do {
            guard let latest = try CaptureStorage.allSessions().first else {
                phase = .idle
                updateSystemState(.idle)
                return
            }

            activeSessionURL = latest.url
            lastCaptureDate = latest.manifest.startedAt

            switch latest.manifest.state {
            case .capturing:
                presentFailure("上一次系统录制没有正常结束。请先停止顶部录制标记，再重新开始；本地画面已保留。")
            case .failed:
                presentFailure(latest.manifest.failureMessage ?? "屏幕捕获没有正常完成。")
            case .complete:
                let existing = CaptureStorage.existingOutputs(in: latest.url)
                if !existing.isEmpty {
                    let newlySaved = !CaptureStorage.hasSavedOutputsToPhotos(in: latest.url)
                    if newlySaved {
                        guard processingSessionID != latest.manifest.id else { return }
                        processingSessionID = latest.manifest.id
                        phase = .processing
                        updateSystemState(.processing, frameCount: latest.manifest.frameCount)
                        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "恢复保存长卷")
                        defer {
                            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
                        }
                        try await saveToPhotos(existing)
                        try CaptureStorage.markOutputsSavedToPhotos(in: latest.url)
                    }
                    var updatedManifest = latest.manifest
                    updatedManifest.state = .complete
                    updatedManifest.failureMessage = nil
                    updatedManifest.outputCount = existing.count
                    updatedManifest.savedToPhotos = true
                    try CaptureStorage.write(updatedManifest, to: latest.url)
                    if newlySaved {
                        await completeSavedResult(
                            urls: existing, sessionURL: latest.url, manifest: updatedManifest
                        )
                    } else if explicitPreviewSessionID == nil {
                        restoreSavedResult(urls: existing, sessionURL: latest.url, manifest: updatedManifest)
                    }
                    return
                }
                guard processingSessionID != latest.manifest.id else { return }
                processingSessionID = latest.manifest.id
                await process(sessionURL: latest.url, manifest: latest.manifest)
            }
        } catch {
            processingSessionID = nil
            presentFailure(error.localizedDescription)
        }
    }

    func retryProcessing() async {
        guard let activeSessionURL,
              let manifest = try? CaptureStorage.readManifest(at: activeSessionURL) else { return }
        processingSessionID = nil
        await process(sessionURL: activeSessionURL, manifest: manifest)
    }

    func discardCurrentSession() {
        guard let activeSessionURL else { return }
        do {
            try FileManager.default.removeItem(at: activeSessionURL)
            savedResultPresentationStore.acknowledge(sessionID: activeSessionURL.lastPathComponent)
            resultNotificationManager.clearPending(sessionID: activeSessionURL.lastPathComponent)
            isSavedThumbnailPresented = false
            thumbnailSessionID = nil
            explicitPreviewSessionID = nil
            self.activeSessionURL = nil
            processingSessionID = nil
            outputURLs = []
            previewImage = nil
            lastCaptureDate = nil
            phase = .idle
            updateSystemState(.idle)
        } catch {
            presentFailure(error.localizedDescription)
        }
    }

    func presentSavedPreview(sessionID: String?) async {
        do {
            let sessions = try CaptureStorage.allSessions()
            let selected = sessionID.map { requestedID in
                sessions.first { $0.manifest.id == requestedID }
            } ?? sessions.first
            guard let selected else { return }
            let existing = CaptureStorage.existingOutputs(in: selected.url)
            guard !existing.isEmpty else { return }

            explicitPreviewSessionID = selected.manifest.id
            savedResultPresentationStore.acknowledge(sessionID: selected.manifest.id)
            isSavedThumbnailPresented = false
            thumbnailSessionID = nil
            restoreSavedResult(urls: existing, sessionURL: selected.url, manifest: selected.manifest)
            isSavedPreviewRequested = true
        } catch {
            presentFailure(error.localizedDescription)
        }
    }

    func dismissSavedPreview() {
        isSavedPreviewRequested = false
        explicitPreviewSessionID = nil
        restorePendingSavedThumbnailIfNeeded()
    }

    func openSavedThumbnail() {
        guard let sessionID = thumbnailSessionID, !outputURLs.isEmpty else { return }
        savedResultPresentationStore.acknowledge(sessionID: sessionID)
        isSavedThumbnailPresented = false
        thumbnailSessionID = nil
        explicitPreviewSessionID = sessionID
        isSavedPreviewRequested = true
    }

    func dismissSavedThumbnail() {
        if let thumbnailSessionID {
            savedResultPresentationStore.acknowledge(sessionID: thumbnailSessionID)
        }
        isSavedThumbnailPresented = false
        thumbnailSessionID = nil
    }

    var isBusy: Bool {
        switch phase {
        case .choosingSource, .capturing, .processing:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    private func process(sessionURL: URL, manifest: CaptureManifest) async {
        phase = .processing
        updateSystemState(.processing, frameCount: manifest.frameCount)
        liveActivityManager.markProcessing(frameCount: manifest.frameCount)
        beginProcessingProtection()
        let backgroundTask = processingBackgroundTask
        processingBackgroundTask = .invalid
        defer {
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }

        do {
            let frames = try CaptureStorage.frameURLs(in: sessionURL)
            let result = try await Task.detached(priority: .userInitiated) {
                try FrameStitcher().stitch(
                    frameURLs: frames,
                    sessionURL: sessionURL,
                    topCropRatio: manifest.topCropRatio ?? 0.075,
                    segmentStarts: manifest.segmentStarts ?? []
                )
            }.value

            try await saveToPhotos(result.outputURLs)
            try CaptureStorage.markOutputsSavedToPhotos(in: sessionURL)
            var updatedManifest = manifest
            updatedManifest.state = .complete
            updatedManifest.failureMessage = nil
            updatedManifest.acceptedFrameCount = result.acceptedFrameCount
            updatedManifest.skippedFrameCount = result.skippedFrameCount
            updatedManifest.outputCount = result.outputURLs.count
            updatedManifest.savedToPhotos = true
            updatedManifest.processingSeconds = result.timings.total
            updatedManifest.samplingSeconds = result.timings.sampling
            updatedManifest.selectionSeconds = result.timings.selection
            updatedManifest.assemblySeconds = result.timings.assembly
            updatedManifest.renderingSeconds = result.timings.rendering
            try CaptureStorage.write(updatedManifest, to: sessionURL)
            await completeSavedResult(
                urls: result.outputURLs, sessionURL: sessionURL, manifest: updatedManifest
            )
        } catch {
            var failedManifest = manifest
            failedManifest.completedAt = Date()
            failedManifest.state = .failed
            failedManifest.failureMessage = error.localizedDescription
            failedManifest.savedToPhotos = false
            try? CaptureStorage.write(failedManifest, to: sessionURL)
            processingSessionID = nil
            presentFailure(error.localizedDescription)
        }
    }

    private func restoreSavedResult(urls: [URL], sessionURL: URL, manifest: CaptureManifest) {
        activeSessionURL = sessionURL
        lastCaptureDate = manifest.startedAt
        outputURLs = urls
        previewImage = urls.first.flatMap { UIImage(contentsOfFile: $0.path) }
        phase = .ready(
            pageCount: urls.count,
            accepted: manifest.acceptedFrameCount ?? manifest.frameCount,
            skipped: manifest.skippedFrameCount ?? 0
        )
        updateSystemState(.saved)
    }

    private func beginProcessingProtection() {
        guard processingBackgroundTask == .invalid else { return }
        processingBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "生成长卷")
    }

    /// Both a fresh stitch and an interrupted save recovered on activation use
    /// this path. Presentation/notification failures never undo a Photos save.
    private func completeSavedResult(urls: [URL], sessionURL: URL, manifest: CaptureManifest) async {
        recordCompletionTiming(manifest)
        savedResultPresentationStore.enqueue(sessionID: manifest.id)
        if explicitPreviewSessionID == nil || explicitPreviewSessionID == manifest.id {
            restoreSavedResult(urls: urls, sessionURL: sessionURL, manifest: manifest)
            isSavedThumbnailPresented = !isSavedPreviewRequested
                && savedResultPresentationStore.state.pendingSessionID == manifest.id
            thumbnailSessionID = isSavedThumbnailPresented ? manifest.id : nil
        }
        liveActivityManager.markSaved(pageCount: urls.count)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        exportCaptureDiagnostics()
        await resultNotificationManager.postSavedResult(
            image: urls.first.flatMap { UIImage(contentsOfFile: $0.path) },
            sessionURL: sessionURL,
            sessionID: manifest.id,
            pageCount: urls.count
        )
    }

    private func recordCompletionTiming(_ manifest: CaptureManifest) {
        var timing: [String: Any] = [
            "sessionID": manifest.id,
            "savedAt": ISO8601DateFormatter().string(from: Date()),
            "frameCount": manifest.frameCount,
            "stitchingSeconds": manifest.processingSeconds ?? 0
        ]
        if let sampling = manifest.samplingSeconds { timing["samplingSeconds"] = sampling }
        if let selection = manifest.selectionSeconds { timing["selectionSeconds"] = selection }
        if let assembly = manifest.assemblySeconds { timing["assemblySeconds"] = assembly }
        if let rendering = manifest.renderingSeconds { timing["renderingSeconds"] = rendering }
        if let finishRequest, finishRequest.sessionID == manifest.id {
            timing["finishToSavedSeconds"] = Date().timeIntervalSince(finishRequest.date)
        }
        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LongShotCompletionTiming.json")
        if let data = try? JSONSerialization.data(withJSONObject: timing, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: destination, options: .atomic)
        }
    }

    private func restorePendingSavedThumbnailIfNeeded() {
        guard !isBusy, explicitPreviewSessionID == nil, !isSavedPreviewRequested else { return }
        guard let sessions = try? CaptureStorage.allSessions() else { return }
        if !savedResultPresentationStore.state.hasConsideredExistingResult {
            // The upgrade may offer only the latest successful result once.
            let latestSaved = sessions.first {
                $0.manifest.state == .complete
                    && CaptureStorage.hasSavedOutputsToPhotos(in: $0.url)
                    && !CaptureStorage.existingOutputs(in: $0.url).isEmpty
            }
            savedResultPresentationStore.considerExistingResult(sessionID: latestSaved?.manifest.id)
        }
        guard let pendingID = savedResultPresentationStore.state.pendingSessionID else { return }
        guard let selected = sessions.first(where: { $0.manifest.id == pendingID }) else {
            savedResultPresentationStore.acknowledge(sessionID: pendingID)
            return
        }
        let existing = CaptureStorage.existingOutputs(in: selected.url)
        guard !existing.isEmpty else {
            savedResultPresentationStore.acknowledge(sessionID: pendingID)
            return
        }
        restoreSavedResult(urls: existing, sessionURL: selected.url, manifest: selected.manifest)
        thumbnailSessionID = pendingID
        isSavedThumbnailPresented = true
    }

    private func deliverDeferredResultNotificationIfNeeded() async {
        guard UIApplication.shared.applicationState == .active, !isBusy,
              let sessionID = resultNotificationManager.pendingSessionID else { return }
        guard let sessions = try? CaptureStorage.allSessions(),
              let selected = sessions.first(where: { $0.manifest.id == sessionID }) else {
            resultNotificationManager.clearPending(sessionID: sessionID)
            return
        }
        let existing = CaptureStorage.existingOutputs(in: selected.url)
        guard !existing.isEmpty else {
            resultNotificationManager.clearPending(sessionID: sessionID)
            return
        }
        await resultNotificationManager.postSavedResult(
            image: UIImage(contentsOfFile: existing[0].path),
            sessionURL: selected.url, sessionID: sessionID, pageCount: existing.count
        )
    }

    private func presentFailure(_ message: String) {
        phase = .failed(message)
        updateSystemState(.failed)
        liveActivityManager.markFailed()
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        exportCaptureDiagnostics()
    }

    private func handlePendingStartRequest() {
        guard !isBusy, CaptureCommandStore.consumeStartRequest() else { return }
        beginCapture()
    }

    private func handlePendingFinishRequest() async -> Bool {
#if !LONGSHOT_SCREEN_CAPTURE_KIT
        captureCoordinator.refreshSession()
#endif
        guard captureCoordinator.isCapturing else { return false }
        guard CaptureCommandStore.consumeFinishRequest() else { return false }
        await captureCoordinator.stopCapture()
        return true
    }

    func cancelCaptureChoice() {
#if !LONGSHOT_SCREEN_CAPTURE_KIT
        captureCoordinator.cancelPicker()
#endif
    }

    /// Local metadata only; enables troubleshooting without copying screenshots.
    private func exportCaptureDiagnostics() {
        do {
            let recent = try CaptureStorage.allSessions().prefix(5).map(\.manifest)
            let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Array(recent)).write(
                to: destination.appendingPathComponent("LongShotCaptureDiagnostics.json"), options: .atomic
            )
#if !LONGSHOT_SCREEN_CAPTURE_KIT
            if let status = ReplayBroadcastStore.readStatus() {
                try encoder.encode(status).write(
                    to: destination.appendingPathComponent("LongShotBroadcastStatus.json"), options: .atomic
                )
            }
#endif
        } catch { /* Diagnostics must not interrupt capturing. */ }
    }

    private func updateSystemState(
        _ state: CaptureSurfacePhase,
        frameCount: Int = 0
    ) {
        let previousState = CaptureCommandStore.phase
        CaptureCommandStore.setState(state, frameCount: frameCount)
        // Neither control displays frame counts. Reload only on phase changes,
        // not four times per second while a screenshot is being collected.
        guard previousState != state else { return }
        ControlCenter.shared.reloadControls(ofKind: CaptureSystem.controlKind)
        ControlCenter.shared.reloadControls(ofKind: CaptureSystem.pageControlKind)
    }

    private func saveToPhotos(_ urls: [URL]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoSaveError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                for url in urls {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoSaveError.unknown)
                }
            }
        }
    }
}

extension AppModel: ScreenCaptureCoordinatorDelegate {
    func screenCaptureCoordinatorWillPresentPicker(_ coordinator: ScreenCaptureCoordinator) {
        phase = .choosingSource
    }

    func screenCaptureCoordinatorDidCancelPicker(_ coordinator: ScreenCaptureCoordinator) {
        phase = .idle
        updateSystemState(.idle)
        Task { await refreshAndProcessIfNeeded() }
    }

    func screenCaptureCoordinator(
        _ coordinator: ScreenCaptureCoordinator,
        didStartSessionAt sessionURL: URL
    ) {
        activeSessionURL = sessionURL
        lastCaptureDate = Date()
        phase = .capturing(0)
        isPageTransitionPaused = false
        updateSystemState(.capturing)
        liveActivityManager.start(sessionID: sessionURL.lastPathComponent)
    }

    func screenCaptureCoordinator(
        _ coordinator: ScreenCaptureCoordinator,
        didCaptureFrameCount frameCount: Int
    ) {
        phase = .capturing(frameCount)
        updateSystemState(isPageTransitionPaused ? .paused : .capturing, frameCount: frameCount)
        if !isPageTransitionPaused { liveActivityManager.updateCapturing(frameCount: frameCount) }
    }

    func screenCaptureCoordinator(
        _ coordinator: ScreenCaptureCoordinator,
        didFinishSessionAt sessionURL: URL,
        manifest: CaptureManifest
    ) {
        activeSessionURL = sessionURL
        lastCaptureDate = manifest.startedAt
        isPageTransitionPaused = false

        if manifest.state == .failed {
            presentFailure(manifest.failureMessage ?? "屏幕捕获没有正常完成。")
            return
        }

        processingSessionID = manifest.id
        // Establish protection synchronously while the capture coordinator
        // still holds its finishing assertion, before scheduling async work.
        beginProcessingProtection()
        phase = .processing
        updateSystemState(.processing, frameCount: manifest.frameCount)
        liveActivityManager.markProcessing(frameCount: manifest.frameCount)
        Task {
            await process(sessionURL: sessionURL, manifest: manifest)
        }
    }

    func screenCaptureCoordinator(
        _ coordinator: ScreenCaptureCoordinator,
        didFailWith message: String
    ) {
        presentFailure(message)
    }
}

private enum PhotoSaveError: LocalizedError {
    case permissionDenied
    case unknown

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有获得保存到照片的权限。请在系统设置中允许“长卷”添加照片。"
        case .unknown:
            return "图片已经生成，但保存到照片时失败。"
        }
    }
}
