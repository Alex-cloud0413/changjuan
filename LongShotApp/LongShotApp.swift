import SwiftUI
import UIKit
import UserNotifications

@main
struct LongShotApp: App {
    @UIApplicationDelegateAdaptor(LongShotApplicationDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel.shared)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.light)
                .task {
                    await model.activate()
                }
                .onChange(of: scenePhase) { _, newPhase in
#if LONGSHOT_SCREEN_CAPTURE_KIT
                    if newPhase == .active {
                        ScreenCaptureHostVisibility.shared.setForeground(true)
                    } else if newPhase == .background {
                        ScreenCaptureHostVisibility.shared.setForeground(false)
                    }
#else
                    if newPhase == .active {
                        ReplayBroadcastStore.setHostForeground(true)
                    } else if newPhase == .background {
                        ReplayBroadcastStore.setHostForeground(false)
                    }
#endif
                    guard newPhase == .active else { return }
                    Task {
                        await model.activate()
                    }
                }
        }
    }
}

@MainActor
final class LongShotApplicationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if LONGSHOT_BENCHMARK
        if ProcessInfo.processInfo.arguments.contains("--benchmark-latest") {
            Task { await Self.benchmarkLatestSession() }
            return true
        }
#endif
        AppModel.shared.prepareForSystemCommands()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionID = response.notification.request.content.userInfo[
            ResultNotificationManager.sessionIDKey
        ] as? String
        completionHandler()
        Task { @MainActor in
            await AppModel.shared.presentSavedPreview(sessionID: sessionID)
        }
    }

#if LONGSHOT_BENCHMARK
    /// Opt-in developer measurement. Never saves to Photos or alters capture records.
    private static func benchmarkLatestSession() async {
        do {
            let arguments = ProcessInfo.processInfo.arguments
            let requestedID = arguments.firstIndex(of: "--session-id").flatMap { index in
                index + 1 < arguments.count ? arguments[index + 1] : nil
            }
            guard let latest = try CaptureStorage.allSessions().first(where: {
                requestedID == nil || $0.manifest.id == requestedID
            }) else { return }
            let frames = try CaptureStorage.frameURLs(in: latest.url)
            let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LongShotBenchmark-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            // Explicit, developer-only diagnostic export of one selected local
            // recording. No network, Photos writes or original-file mutations.
            if arguments.contains("--export-frames") {
                let copy = destination.appendingPathComponent("Frames", isDirectory: true)
                try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
                for frame in frames {
                    try FileManager.default.copyItem(at: frame, to: copy.appendingPathComponent(frame.lastPathComponent))
                }
                try FileManager.default.copyItem(
                    at: latest.url.appendingPathComponent(CaptureConstants.manifestFileName),
                    to: copy.appendingPathComponent(CaptureConstants.manifestFileName)
                )
                print("LONGSHOT_EXPORT_DIRECTORY \(destination.lastPathComponent)")
            }
            let cropRatio = latest.manifest.topCropRatio ?? ScreenCaptureCoordinator.systemTopCropRatio()
            let symbol = UIImage(named: "LongJuanCapture")
            if let symbol {
                let configuration = UIImage.SymbolConfiguration(pointSize: 80, weight: .regular)
                let glyph = symbol.applyingSymbolConfiguration(configuration) ?? symbol
                let preview = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
                    glyph.withTintColor(.black, renderingMode: .alwaysOriginal).draw(
                        at: CGPoint(x: (240 - glyph.size.width) / 2, y: (240 - glyph.size.height) / 2)
                    )
                }
                try preview.pngData()?.write(to: destination.appendingPathComponent("ControlSymbol.png"))
            }
            print("LONGSHOT_BENCHMARK_BEGIN frames=\(frames.count)")
            let result = try await Task.detached(priority: .userInitiated) {
                try FrameStitcher().stitch(
                    frameURLs: frames, sessionURL: destination, topCropRatio: cropRatio,
                    segmentStarts: latest.manifest.segmentStarts ?? []
                )
            }.value
            let report: [String: Any] = [
                "frames": frames.count,
                "session": latest.manifest.id,
                "accepted": result.acceptedFrameCount,
                "skipped": result.skippedFrameCount,
                "topCropRatio": cropRatio,
                "customSymbolLoaded": symbol?.isSymbolImage == true,
                "timings": try JSONSerialization.jsonObject(with: JSONEncoder().encode(result.timings)),
                "outputSizes": result.outputURLs.compactMap { url -> [Int]? in
                    guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
                    return [image.width, image.height]
                }
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: destination.appendingPathComponent("report.json"))
            print("LONGSHOT_BENCHMARK_RESULT \(String(decoding: data, as: UTF8.self))")
            print("LONGSHOT_BENCHMARK_DIRECTORY \(destination.lastPathComponent)")
        } catch {
            print("LONGSHOT_BENCHMARK_ERROR \(error)")
        }
        exit(0)
    }
#endif
}
