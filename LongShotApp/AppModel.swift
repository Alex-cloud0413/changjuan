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
    @Published var isSavedPreviewUnavailable = false
    @Published private(set) var isClearingCaches = false

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
    private var processingBackgroundTask: CaptureProcessingBackgroundTask?
    private var finishRequest: (sessionID: String, date: Date)?
    private var storageMaintenanceTask: Task<Void, Never>?
    private var storageMaintenanceWorker: Task<SavedCaptureCleanup.Report, Never>?
    private var storageMaintenanceRequested = false
    private var resultDeliverySessions: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        for (notification, event) in [
            (UIApplication.didBecomeActiveNotification, "appBecameActive"),
            (UIApplication.willResignActiveNotification, "appWillResignActive"),
            (UIApplication.didEnterBackgroundNotification, "appEnteredBackground"),
            (UIApplication.willEnterForegroundNotification, "appWillEnterForeground")
        ] {
            NotificationCenter.default.publisher(for: notification)
                .sink { _ in
                    Task { @MainActor in CaptureProcessingDiagnostics.record(event) }
                }
                .store(in: &cancellables)
        }
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
        // Run on every idle activation, including the first launch after upgrade.
        // Old saved sessions are retired before recovery can select them.
        if !isBusy { scheduleStorageMaintenance() }
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
        CaptureProcessingDiagnostics.record("systemCaptureActionRequested", values: [
            "finishOnly": finishOnly, "busy": isBusy,
            "capturing": captureCoordinator.isCapturing,
            "choosingSource": captureCoordinator.isChoosingSource
        ])
        _ = CaptureCommandStore.consumeStartRequest()
        CaptureCommandStore.clearFinishRequest()
        updateHostVisibility()
        if captureCoordinator.isCapturing {
            await stopCapture()
        } else if captureCoordinator.isChoosingSource {
            if !finishOnly {
                captureCoordinator.presentPicker()
                try await captureCoordinator.waitForPickerResolution()
            }
        } else if !finishOnly, !isBusy {
            beginCapture()
            try await captureCoordinator.waitForPickerResolution()
        } else {
            CaptureProcessingDiagnostics.record("systemCaptureActionSkipped", values: [
                "finishOnly": finishOnly, "busy": isBusy
            ])
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
        dismissSavedThumbnail(scheduleCleanup: false)
        storageMaintenanceWorker?.cancel()
        storageMaintenanceRequested = false
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
            CaptureProcessingDiagnostics.record("finishRequested", sessionID: sessionID)
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
        await waitForStorageMaintenance()
        guard !isClearingCaches else { return }
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
            guard let latest = try CaptureStorage.allSessions().first(where: {
                !CaptureStorage.hasDiscardedRawFrames(in: $0.url)
                    || ($0.manifest.state == .complete && !CaptureStorage.existingOutputs(in: $0.url).isEmpty)
            }) else {
                phase = .idle
                updateSystemState(.idle)
                return
            }

            activeSessionURL = latest.url
            CaptureProcessingDiagnostics.sessionID = latest.manifest.id
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
                    var recoveryTiming: [String: Any] = ["recoveredExistingOutput": true]
                    if newlySaved {
                        guard processingSessionID != latest.manifest.id else { return }
                        processingSessionID = latest.manifest.id
                        phase = .processing
                        updateSystemState(.processing, frameCount: latest.manifest.frameCount)
                        let backgroundTask = CaptureProcessingBackgroundTask(name: "恢复保存长卷", stage: "recovery")
                        defer { backgroundTask.end() }
                        CaptureProcessingDiagnostics.record("recoveringExistingOutput", values: ["outputCount": existing.count])
                        recoveryTiming.merge(try await saveToPhotos(existing, sessionID: latest.manifest.id)) { _, new in new }
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
                            urls: existing, sessionURL: latest.url, manifest: updatedManifest, timing: recoveryTiming
                        )
                    } else if explicitPreviewSessionID == nil {
                        restoreSavedResult(urls: existing, sessionURL: latest.url, manifest: updatedManifest)
                    }
                    return
                }
                if CaptureStorage.hasSavedOutputsToPhotos(in: latest.url) {
                    // Never regenerate or save a duplicate Photos asset when a
                    // previously saved preview has gone missing.
                    outputURLs = []
                    previewImage = nil
                    phase = .idle
                    updateSystemState(.idle)
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
        await waitForStorageMaintenance()
        guard !isBusy else { return }
        guard let activeSessionURL,
              !CaptureStorage.hasDiscardedRawFrames(in: activeSessionURL),
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
        await waitForStorageMaintenance()
        guard !isBusy else { return }
        do {
            let sessions = try CaptureStorage.allSessions()
            let selected = sessionID.map { requestedID in
                sessions.first { $0.manifest.id == requestedID }
            } ?? sessions.first
            guard let selected else { isSavedPreviewUnavailable = true; return }
            let existing = CaptureStorage.existingOutputs(in: selected.url)
            guard !existing.isEmpty else { isSavedPreviewUnavailable = true; return }

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
        scheduleStorageMaintenance()
    }

    func openSavedThumbnail() {
        guard let sessionID = thumbnailSessionID, !outputURLs.isEmpty else { return }
        savedResultPresentationStore.acknowledge(sessionID: sessionID)
        isSavedThumbnailPresented = false
        thumbnailSessionID = nil
        explicitPreviewSessionID = sessionID
        isSavedPreviewRequested = true
    }

    func dismissSavedThumbnail(scheduleCleanup: Bool = true) {
        if let thumbnailSessionID {
            savedResultPresentationStore.acknowledge(sessionID: thumbnailSessionID)
        }
        isSavedThumbnailPresented = false
        thumbnailSessionID = nil
        if scheduleCleanup { scheduleStorageMaintenance() }
    }

    var isBusy: Bool {
        if isClearingCaches { return true }
        switch phase {
        case .choosingSource, .capturing, .processing:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    func clearAllRawCaches() async -> SavedCaptureCleanup.Report? {
        guard !isBusy else { return nil }
        isClearingCaches = true
        defer { isClearingCaches = false }
        await waitForStorageMaintenance()
        let protection = CaptureProcessingBackgroundTask(name: "清理录制缓存", stage: "manualCacheCleanup")
        defer { protection.end() }
        let report = await Task.detached(priority: .utility) { SavedCaptureCleanup.clearAllRawCaches() }.value
        if let activeSessionURL, report.clearedRawSessionIDs.contains(activeSessionURL.lastPathComponent),
           case .failed = phase {
            self.activeSessionURL = nil
            outputURLs = []
            previewImage = nil
            phase = .idle
            updateSystemState(.idle)
        }
        CaptureProcessingDiagnostics.record("manualCacheCleanupFinished", values: [
            "reclaimedBytes": report.reclaimedBytes, "failures": report.failures,
            "clearedSessionCount": report.clearedRawSessionIDs.count
        ])
        return report
    }

    private func process(sessionURL: URL, manifest: CaptureManifest) async {
        let processingStartedAt = Date()
        CaptureProcessingDiagnostics.sessionID = manifest.id
        CaptureProcessingDiagnostics.record("processingStarted", values: [
            "frameCount": manifest.frameCount,
            "inputPageCount": max(1, manifest.segmentStarts?.count ?? 1),
            "captureStoppedToProcessingSeconds": manifest.completedAt.map { processingStartedAt.timeIntervalSince($0) } ?? 0
        ])
        phase = .processing
        updateSystemState(.processing, frameCount: manifest.frameCount)
        liveActivityManager.markProcessing(frameCount: manifest.frameCount)
        beginProcessingProtection()
        let backgroundTask = processingBackgroundTask
        processingBackgroundTask = nil
        defer { backgroundTask?.end() }

        do {
            let frames = try CaptureStorage.frameURLs(in: sessionURL)
            CaptureProcessingDiagnostics.record("stitchingQueued", values: ["frameCount": frames.count])
            let queuedAt = ProcessInfo.processInfo.systemUptime
            let work = try await Task.detached(priority: .userInitiated) {
                let startedAt = ProcessInfo.processInfo.systemUptime
                let result = try FrameStitcher(options: manifest.captureOptions ?? CaptureOptions()).stitch(
                    frameURLs: frames,
                    sessionURL: sessionURL,
                    topCropRatio: manifest.topCropRatio ?? 0.075,
                    segmentStarts: manifest.segmentStarts ?? []
                )
                return (result, startedAt, ProcessInfo.processInfo.systemUptime)
            }.value
            let result = work.0
            var timing: [String: Any] = [
                "stitchDispatchDelaySeconds": work.1 - queuedAt,
                "stitchReturnDelaySeconds": ProcessInfo.processInfo.systemUptime - work.2,
                "preparedFrameCount": result.preparedFrameCount,
                "fallbackFrameCount": frames.count - result.preparedFrameCount,
                "preparedAlignmentCount": result.preparedAlignmentCount,
                "processingStartedAt": ISO8601DateFormatter().string(from: processingStartedAt)
            ]
            CaptureProcessingDiagnostics.record("stitchingFinished", values: timing.merging([
                "stitchingSeconds": result.timings.total,
                "samplingSeconds": result.timings.sampling,
                "selectionSeconds": result.timings.selection,
                "assemblySeconds": result.timings.assembly,
                "renderingSeconds": result.timings.rendering,
                "outputCount": result.outputURLs.count
            ]) { _, new in new })

            let photosTiming = try await saveToPhotos(result.outputURLs, sessionID: manifest.id)
            timing.merge(photosTiming) { _, new in new }
            let persistenceStartedAt = Date()
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
            timing["resultPersistenceSeconds"] = Date().timeIntervalSince(persistenceStartedAt)
            timing["processingWallSeconds"] = Date().timeIntervalSince(processingStartedAt)
            await completeSavedResult(
                urls: result.outputURLs, sessionURL: sessionURL, manifest: updatedManifest, timing: timing
            )
        } catch {
            let diagnosticError = error as NSError
            CaptureProcessingDiagnostics.record("processingFailed", sessionID: manifest.id, values: [
                "errorDomain": diagnosticError.domain, "errorCode": diagnosticError.code
            ])
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
        guard processingBackgroundTask == nil else { return }
        processingBackgroundTask = CaptureProcessingBackgroundTask(name: "生成长卷", stage: "processing")
    }

    /// Both a fresh stitch and an interrupted save recovered on activation use
    /// this path. Presentation/notification failures never undo a Photos save.
    private func completeSavedResult(
        urls: [URL], sessionURL: URL, manifest: CaptureManifest, timing: [String: Any] = [:]
    ) async {
        resultDeliverySessions.insert(manifest.id)
        recordCompletionTiming(manifest, stages: timing)
        CaptureProcessingDiagnostics.record("resultSaved", sessionID: manifest.id, values: timing)
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
        CaptureProcessingDiagnostics.record("resultNotificationStarted", sessionID: manifest.id)
        await resultNotificationManager.postSavedResult(
            image: urls.first.flatMap { UIImage(contentsOfFile: $0.path) },
            sessionURL: sessionURL,
            sessionID: manifest.id,
            pageCount: urls.count
        )
        CaptureProcessingDiagnostics.record("resultNotificationFinished", sessionID: manifest.id)
        resultDeliverySessions.remove(manifest.id)
        // Saving, feedback and notification delivery are already finished. Cleanup
        // runs off the main actor and never extends the measured stitching time.
        scheduleStorageMaintenance()
    }

    private func scheduleStorageMaintenance() {
        guard !isBusy else { return }
        guard storageMaintenanceTask == nil else {
            storageMaintenanceRequested = true
            return
        }
        storageMaintenanceRequested = false
        let protectedIDs = Set([explicitPreviewSessionID, thumbnailSessionID].compactMap { $0 })
            .union(resultDeliverySessions)
        let protection = CaptureProcessingBackgroundTask(name: "清理已保存画面", stage: "storageCleanup")
        let worker = Task.detached(priority: .utility) {
            SavedCaptureCleanup.run(protectedSessionIDs: protectedIDs)
        }
        storageMaintenanceWorker = worker
        storageMaintenanceTask = Task { [weak self] in
            defer { protection.end() }
            let report = await worker.value
            guard let self else { return }
            for id in report.removedSessionIDs {
                self.savedResultPresentationStore.forget(sessionID: id)
                self.resultNotificationManager.removeExpiredResult(sessionID: id)
            }
            // A new capture may have started while the disk worker was running.
            // Do not change its phase, active session or preview state.
            if !self.isBusy, let active = self.activeSessionURL,
               report.removedSessionIDs.contains(active.lastPathComponent) {
                self.activeSessionURL = nil
                self.outputURLs = []
                self.previewImage = nil
                self.lastCaptureDate = nil
                self.phase = .idle
                self.updateSystemState(.idle)
            }
            CaptureProcessingDiagnostics.record("storageCleanupFinished", values: [
                "reclaimedBytes": report.reclaimedBytes,
                "removedSessionCount": report.removedSessionIDs.count,
                "retainedPreviewCount": report.retainedCount,
                "retainedPreviewBytes": report.retainedBytes,
                "failures": report.failures,
                "cancelled": report.cancelled
            ])
            self.storageMaintenanceWorker = nil
            self.storageMaintenanceTask = nil
            if self.storageMaintenanceRequested { self.scheduleStorageMaintenance() }
        }
    }

    private func waitForStorageMaintenance() async {
        while let task = storageMaintenanceTask { await task.value }
    }

    private func recordCompletionTiming(_ manifest: CaptureManifest, stages: [String: Any]) {
        var timing = CaptureProcessingDiagnostics.buildMetadata.merging(stages) { _, new in new }
        timing.merge([
            "schemaVersion": 2,
            "sessionID": manifest.id,
            "savedAt": ISO8601DateFormatter().string(from: Date()),
            "frameCount": manifest.frameCount,
            "inputPageCount": max(1, manifest.segmentStarts?.count ?? 1),
            "stitchingSeconds": manifest.processingSeconds ?? 0
        ]) { _, new in new }
        if let sampling = manifest.samplingSeconds { timing["samplingSeconds"] = sampling }
        if let selection = manifest.selectionSeconds { timing["selectionSeconds"] = selection }
        if let assembly = manifest.assemblySeconds { timing["assemblySeconds"] = assembly }
        if let rendering = manifest.renderingSeconds { timing["renderingSeconds"] = rendering }
        if let finishRequest, finishRequest.sessionID == manifest.id {
            timing["finishToSavedSeconds"] = Date().timeIntervalSince(finishRequest.date)
        }
        // Available even after a system stop or a process restart, unlike the
        // in-memory finishRequest. This includes background suspension time.
        if let stoppedAt = manifest.completedAt {
            timing["captureStoppedToSavedSeconds"] = Date().timeIntervalSince(stoppedAt)
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
        await waitForStorageMaintenance()
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
        resultDeliverySessions.insert(sessionID)
        await resultNotificationManager.postSavedResult(
            image: UIImage(contentsOfFile: existing[0].path),
            sessionURL: selected.url, sessionID: sessionID, pageCount: existing.count
        )
        resultDeliverySessions.remove(sessionID)
        scheduleStorageMaintenance()
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

    /// Presentation-only refresh. Never starts, stops or resets a session.
    func refreshLanguagePresentation() {
        liveActivityManager.refreshLanguage()
        ControlCenter.shared.reloadControls(ofKind: CaptureSystem.controlKind)
        ControlCenter.shared.reloadControls(ofKind: CaptureSystem.pageControlKind)
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

    @discardableResult
    private func saveToPhotos(_ urls: [URL], sessionID: String) async throws -> [String: Any] {
        let authorizationStartedAt = Date()
        CaptureProcessingDiagnostics.record("photosAuthorizationStarted", sessionID: sessionID)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        let authorizationSeconds = Date().timeIntervalSince(authorizationStartedAt)
        CaptureProcessingDiagnostics.record("photosAuthorizationFinished", sessionID: sessionID, values: [
            "seconds": authorizationSeconds, "authorizationStatus": status.rawValue
        ])
        guard status == .authorized || status == .limited else {
            throw PhotoSaveError.permissionDenied
        }

        CaptureProcessingDiagnostics.record("photosWriteStarted", sessionID: sessionID, values: ["outputCount": urls.count])
        let writeStartedAt = Date()
        let callbackAt: Date = try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                for url in urls {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: Date())
                } else {
                    continuation.resume(throwing: PhotoSaveError.unknown)
                }
            }
        }
        let timing: [String: Any] = [
            "photosAuthorizationSeconds": authorizationSeconds,
            "photosWriteSeconds": callbackAt.timeIntervalSince(writeStartedAt),
            "photosCallbackResumeSeconds": Date().timeIntervalSince(callbackAt)
        ]
        CaptureProcessingDiagnostics.record("photosWriteFinished", sessionID: sessionID, values: timing)
        return timing
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
        CaptureProcessingDiagnostics.sessionID = sessionURL.lastPathComponent
        CaptureProcessingDiagnostics.record("captureStarted")
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
        CaptureProcessingDiagnostics.sessionID = manifest.id
        CaptureProcessingDiagnostics.record("captureStopped", values: ["frameCount": manifest.frameCount])
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
