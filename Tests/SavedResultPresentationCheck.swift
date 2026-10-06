import Foundation

@main
struct SavedResultPresentationCheck {
    static func main() throws {
        testSaveCanWaitForActivation()
        testAcknowledgmentDoesNotReplay()
        testUpgradeOffersOnlyLatestOnce()
        testOpeningOlderNotificationKeepsNewResultPending()
        testNewSaveReplacesUnseenOlderResult()
        try testReceiptSurvivesModelRelaunch()
        print("Saved result presentation checks passed (6)")
    }

    private static func testSaveCanWaitForActivation() {
        var state = SavedResultPresentationState()
        state.enqueue(sessionID: "background-save")
        require(state.pendingSessionID == "background-save")
        state.considerExistingResult(sessionID: "historical-result")
        require(state.pendingSessionID == "background-save")
    }

    private static func testAcknowledgmentDoesNotReplay() {
        var state = SavedResultPresentationState()
        state.enqueue(sessionID: "result-1")
        state.acknowledge(sessionID: "result-1")
        state.considerExistingResult(sessionID: "result-1")
        state.enqueue(sessionID: "result-1")
        require(state.pendingSessionID == nil)
        require(state.acknowledgedSessionID == "result-1")
    }

    private static func testUpgradeOffersOnlyLatestOnce() {
        var state = SavedResultPresentationState()
        state.considerExistingResult(sessionID: "latest-build-21-result")
        require(state.pendingSessionID == "latest-build-21-result")
        state.acknowledge(sessionID: "latest-build-21-result")
        state.considerExistingResult(sessionID: "older-success")
        require(state.pendingSessionID == nil)
        var freshInstall = SavedResultPresentationState()
        freshInstall.considerExistingResult(sessionID: nil)
        freshInstall.considerExistingResult(sessionID: "historical-import")
        require(freshInstall.pendingSessionID == nil)
    }

    private static func testOpeningOlderNotificationKeepsNewResultPending() {
        var state = SavedResultPresentationState()
        state.enqueue(sessionID: "new-result")
        state.acknowledge(sessionID: "old-notification-result")
        require(state.pendingSessionID == "new-result")
    }

    private static func testNewSaveReplacesUnseenOlderResult() {
        var state = SavedResultPresentationState()
        state.enqueue(sessionID: "first")
        state.enqueue(sessionID: "second")
        require(state.pendingSessionID == "second")
        state.acknowledge(sessionID: "second")
        require(state.pendingSessionID == nil)
    }

    private static func testReceiptSurvivesModelRelaunch() throws {
        let suite = "LongShotSavedResultChecks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Cannot create test suite") }
        let original = SavedResultPresentationStore(defaults: defaults)
        original.enqueue(sessionID: "saved-before-suspension")
        let relaunched = SavedResultPresentationStore(defaults: defaults)
        require(relaunched.state.pendingSessionID == "saved-before-suspension")
        relaunched.acknowledge(sessionID: "saved-before-suspension")
        let nextLaunch = SavedResultPresentationStore(defaults: defaults)
        require(nextLaunch.state.pendingSessionID == nil)
        require(nextLaunch.state.hasConsideredExistingResult)
        let encoded = try JSONEncoder().encode(nextLaunch.state)
        let decoded = try JSONDecoder().decode(SavedResultPresentationState.self, from: encoded)
        require(decoded == nextLaunch.state)
    }

    private static func require(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
        guard condition else { fatalError("Check failed", file: file, line: line) }
    }
}
