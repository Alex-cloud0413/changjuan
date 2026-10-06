import ActivityKit
import Foundation

@MainActor
final class CaptureLiveActivityManager {
    private var activity: Activity<LongScrollActivityAttributes>?
    private var lastReportedFrameCount = -1

    func start(sessionID: String) {
        lastReportedFrameCount = -1

        for existing in Activity<LongScrollActivityAttributes>.activities {
            Task {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = LongScrollActivityAttributes.ContentState(
            phase: .capturing,
            frameCount: 0,
            pageCount: 0
        )

        do {
            activity = try Activity.request(
                attributes: LongScrollActivityAttributes(sessionID: sessionID),
                content: ActivityContent(state: state, staleDate: nil),
                style: .standard
            )
        } catch {
            activity = nil
        }
    }

    func updateCapturing(frameCount: Int) {
        guard frameCount == 0 || frameCount - lastReportedFrameCount >= 4 else { return }
        lastReportedFrameCount = frameCount
        update(phase: .capturing, frameCount: frameCount)
    }

    func markProcessing(frameCount: Int) {
        update(phase: .processing, frameCount: frameCount)
    }

    func markPageTransition(paused: Bool, frameCount: Int) {
        update(phase: paused ? .paused : .capturing, frameCount: frameCount)
    }

    func markSaved(pageCount: Int) {
        finish(phase: .saved, pageCount: pageCount, after: 8)
    }

    func markFailed() {
        finish(phase: .failed, pageCount: 0, after: 8)
    }

    private func update(
        phase: CaptureSurfacePhase,
        frameCount: Int = 0,
        pageCount: Int = 0
    ) {
        guard let activity else { return }
        let state = LongScrollActivityAttributes.ContentState(
            phase: phase,
            frameCount: frameCount,
            pageCount: pageCount
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func finish(
        phase: CaptureSurfacePhase,
        pageCount: Int,
        after delay: TimeInterval
    ) {
        guard let activity else { return }
        let state = LongScrollActivityAttributes.ContentState(
            phase: phase,
            frameCount: max(lastReportedFrameCount, 0),
            pageCount: pageCount
        )
        self.activity = nil
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(delay))
            )
        }
    }
}
