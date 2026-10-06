#if !LONGSHOT_SCREEN_CAPTURE_KIT
import Foundation
import ReplayKit
import UIKit

/// A system broadcast belongs to iOS and the upload extension. An
/// RPBroadcastController starts an in-app session, which cannot capture other apps.
@MainActor
final class ScreenCaptureCoordinator: NSObject {
    weak var delegate: ScreenCaptureCoordinatorDelegate?
    private var pickerController: ReplaySystemPickerController?
    private var pendingRequest: ReplayBroadcastStore.Request?
    private var activeSessionID: String?
    private var lastFinishedSessionID: String?
    private var lastFrameCount = -1
    private var monitoringTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var isStopping = false

    var isChoosingSource: Bool { pendingRequest != nil }

    var isCapturing: Bool {
        guard let status = ReplayBroadcastStore.readStatus(),
              status.phase == .capturing,
              Date().timeIntervalSince(status.updatedAt) < 15 else { return false }
        return pendingRequest == nil || status.requestID == pendingRequest?.id
    }

    func presentPicker() {
        guard pendingRequest == nil, !isCapturing else { return }
        do {
            pendingRequest = try ReplayBroadcastStore.prepare(topCropRatio: Self.systemTopCropRatio())
        } catch {
            delegate?.screenCaptureCoordinator(self, didFailWith: error.localizedDescription)
            return
        }
        activeSessionID = nil
        lastFrameCount = -1
        delegate?.screenCaptureCoordinatorWillPresentPicker(self)
        startMonitoring()

        // A Control Center intent can run before the foreground window exists.
        presentationTask?.cancel()
        presentationTask = Task { [weak self] in
            for _ in 0..<40 {
                guard !Task.isCancelled, let self, self.pendingRequest != nil else { return }
                if UIApplication.shared.applicationState == .active,
                   let presenter = Self.topViewController(),
                   presenter.viewIfLoaded?.window != nil,
                   !presenter.isBeingPresented, !presenter.isBeingDismissed {
                    let controller = ReplaySystemPickerController()
                    controller.onCancel = { [weak self] in self?.cancelPicker() }
                    self.pickerController = controller
                    presenter.present(controller, animated: true)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, !Task.isCancelled else { return }
            self.fail("系统录制面板暂时无法打开，请在长卷中重新轻点「开始收卷」。")
        }
    }

    /// Recover the extension-owned session after host suspension or relaunch.
    func refreshSession() {
        inspectSession()
        if isCapturing || isChoosingSource { startMonitoring() }
    }

    func stopCapture() async {
        guard !isStopping else { return }
        inspectSession()
        guard let status = ReplayBroadcastStore.readStatus(), status.phase == .capturing else { return }
        isStopping = true
        defer { isStopping = false }
        do {
            try ReplayBroadcastStore.requestFinish(sessionID: status.sessionID)
            CaptureCommandStore.clearFinishRequest()
        } catch {
            fail(error.localizedDescription)
            return
        }
        // Wait only for acknowledgement, never for extra capture footage.
        for _ in 0..<60 {
            inspectSession()
            if let updated = ReplayBroadcastStore.readStatus(),
               updated.sessionID == status.sessionID, updated.phase != .capturing { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        fail("系统录制尚未确认结束。请轻点 iPhone 顶部的录制标记停止，再回到长卷整理。")
    }

    func cancelPicker() {
        inspectSession()
        guard !isCapturing else { dismissPicker(); return }
        pendingRequest = nil
        presentationTask?.cancel()
        monitoringTask?.cancel()
        monitoringTask = nil
        dismissPicker()
        delegate?.screenCaptureCoordinatorDidCancelPicker(self)
    }

    private func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.inspectSession()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func inspectSession() {
        guard let status = ReplayBroadcastStore.readStatus() else {
            expirePendingRequestIfNeeded()
            return
        }
        if let pendingRequest, status.requestID != pendingRequest.id {
            // A user can take longer than the request's 120-second lifetime
            // reading Apple's sheet. Adopt only a newly started orphan session.
            guard status.requestID == nil,
                  status.updatedAt >= pendingRequest.createdAt,
                  let directory = try? CaptureStorage.sessionsDirectory(),
                  let manifest = try? CaptureStorage.readManifest(
                    at: directory.appendingPathComponent(status.sessionID)
                  ),
                  manifest.startedAt >= pendingRequest.createdAt.addingTimeInterval(-1) else {
                expirePendingRequestIfNeeded()
                return
            }
        }
        if pendingRequest == nil, activeSessionID == nil, status.phase != .capturing { return }
        if let activeSessionID, activeSessionID != status.sessionID {
            guard pendingRequest == nil, status.phase == .capturing,
                  Date().timeIntervalSince(status.updatedAt) < 15 else { return }
            self.activeSessionID = nil
            lastFrameCount = -1
        }
        if status.phase == .failed {
            fail(status.failureMessage ?? "系统录制未能完成，请重新开始。")
            return
        }
        guard let directory = try? CaptureStorage.sessionsDirectory() else {
            expirePendingRequestIfNeeded()
            return
        }
        let sessionURL = directory.appendingPathComponent(status.sessionID, isDirectory: true)
        guard let manifest = try? CaptureStorage.readManifest(at: sessionURL) else {
            expirePendingRequestIfNeeded()
            return
        }

        if status.phase == .capturing, manifest.state == .capturing {
            guard Date().timeIntervalSince(status.updatedAt) < 15 else {
                if activeSessionID != nil {
                    fail("系统录制已中断，已收到的画面仍保留在本机。请停止顶部的录制标记后重新开始。")
                } else {
                    expirePendingRequestIfNeeded()
                }
                return
            }
            if activeSessionID == nil {
                activeSessionID = status.sessionID
                pendingRequest = nil
                delegate?.screenCaptureCoordinator(self, didStartSessionAt: sessionURL)
            }
            if UIApplication.shared.applicationState == .active { dismissPicker() }
            if lastFrameCount != status.frameCount {
                lastFrameCount = status.frameCount
                delegate?.screenCaptureCoordinator(self, didCaptureFrameCount: status.frameCount)
            }
            return
        }

        guard manifest.state != .capturing,
              lastFinishedSessionID != status.sessionID else { return }
        lastFinishedSessionID = status.sessionID
        pendingRequest = nil
        activeSessionID = nil
        dismissPicker()
        monitoringTask?.cancel()
        monitoringTask = nil
        delegate?.screenCaptureCoordinator(self, didFinishSessionAt: sessionURL, manifest: manifest)
    }

    private func expirePendingRequestIfNeeded() {
        guard let pendingRequest,
              Date().timeIntervalSince(pendingRequest.createdAt) > 125 else { return }
        fail("没有收到系统录制的启动确认。请关闭录制面板，再轻点「开始收卷」重试。")
    }

    private func fail(_ message: String) {
        pendingRequest = nil
        activeSessionID = nil
        presentationTask?.cancel()
        monitoringTask?.cancel()
        monitoringTask = nil
        dismissPicker()
        delegate?.screenCaptureCoordinator(self, didFailWith: message)
    }

    private func dismissPicker() {
        guard let pickerController else { return }
        guard pickerController.presentedViewController == nil else { return }
        pickerController.dismiss(animated: true)
        self.pickerController = nil
    }

    private static func topViewController() -> UIViewController? {
        var controller = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    static func systemTopCropRatio() -> Double {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.windows.contains(where: \.isKeyWindow) }) ?? scenes.first
        guard let scene else { return 0.075 }
        let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        let top = max(window?.safeAreaInsets.top ?? 0, scene.statusBarManager?.statusBarFrame.height ?? 0)
        guard top > 0, scene.screen.bounds.height > 0 else { return 0.075 }
        return Double(top / scene.screen.bounds.height)
    }
}

/// Apple's actual visible system-broadcast button remains available if the
/// one-shot automatic UIKit control event cannot activate a future hierarchy.
@MainActor
private final class ReplaySystemPickerController: UIViewController {
    var onCancel: (() -> Void)?
    private let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))
    private var hasOpenedPicker = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        modalPresentationStyle = .pageSheet
        isModalInPresentation = true
        sheetPresentationController?.detents = [.medium()]
        picker.preferredExtension = "com.gaoyiming.longshot.private.BroadcastUpload"
        picker.showsMicrophoneButton = false
        picker.tintColor = .label
        picker.accessibilityLabel = "打开系统屏幕录制"
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.widthAnchor.constraint(equalToConstant: 72).isActive = true
        picker.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let title = UILabel()
        title.text = "开始系统录制"
        title.font = .preferredFont(forTextStyle: .title2)
        let detail = UILabel()
        detail.text = "按系统面板确认录制：可能显示「开始直播」，或「Share Entire Screen」。\n录制开始后，返回目标 App 滚动。\n面板未出现时，请轻点下方录制按钮。"
        detail.font = .preferredFont(forTextStyle: .body)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        detail.textAlignment = .center
        let cancel = UIButton(type: .system)
        cancel.setTitle("取消", for: .normal)
        cancel.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, detail, picker, cancel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -22)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasOpenedPicker else { return }
        hasOpenedPicker = true
        picker.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside)
    }
}
#endif
