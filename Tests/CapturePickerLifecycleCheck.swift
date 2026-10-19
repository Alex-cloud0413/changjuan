import Foundation

@main
struct CapturePickerLifecycleCheck {
    @MainActor
    static func main() async throws {
        try await testExplicitRetryAndSuccessfulWaiters()
        try await testFailureWaitersAndNewRequestRecovery()
        try await testRepeatSessionsKeepRegistration()
        testStartingStoppingAndStreamGuards()
        try await testUnavailableIsImmediateFailure()
        try await testStaleCallbacksDoNotCancelNewRequest()
        print("Picker lifecycle behavior checks passed (6): explicit retry, continuation outcomes, repeat sessions, busy guards, unavailable, stale callbacks. Inert picker only; system presentation still needs a device check.")
    }

    @MainActor
    private static func testExplicitRetryAndSuccessfulWaiters() async throws {
        let subject = ScreenCaptureCoordinator()
        subject.presentPicker()
        let generation = subject.captureGeneration
        let observer = subject.pickerObserver
        let first = Task { @MainActor in try await subject.waitForPickerResolution() }
        let second = Task { @MainActor in try await subject.waitForPickerResolution() }
        await waitUntil { subject.pickerWaiters.count == 2 }

        subject.presentPicker()
        require(subject.picker.presentCount == 2, "Explicit retry must present the system picker again")
        require(subject.captureGeneration == generation, "Retry must retain the pending generation")
        require(subject.pickerObserver === observer, "Retry must retain the pending observer")
        require(subject.picker.observerAddCount == 1, "Retry must not register a second observer")
        require(subject.leaseBeginCount == 1, "Retry must retain the original consent lease")
        require(subject.delegate?.willPresentCount == 1, "Retry must not create a second choosing lifecycle")
        require(subject.events == ["request", "present", "represent"], "Retry must be diagnosable")
        require(!subject.picker.defaultConfiguration.showsMicrophoneControl
            && !subject.picker.defaultConfiguration.showsCameraControl,
            "Screenshot consent must never enable microphone or camera controls")

        subject.acceptSelectionForTesting()
        try await first.value
        try await second.value
        require(subject.pickerWaiters.isEmpty && !subject.awaitingPicker, "Success must drain every waiter")
        subject.resolveAgainForTesting()
        try await subject.waitForPickerResolution()
        require(subject.pickerWaiters.isEmpty, "Repeated resolution must not resume completed continuations")
    }

    @MainActor
    private static func testFailureWaitersAndNewRequestRecovery() async throws {
        let subject = ScreenCaptureCoordinator()
        subject.presentPicker()
        let oldGeneration = subject.captureGeneration
        let first = Task { @MainActor in try await subject.waitForPickerResolution() }
        let second = Task { @MainActor in try await subject.waitForPickerResolution() }
        await waitUntil { subject.pickerWaiters.count == 2 }
        let failure = NSError(domain: "LongShotPickerLifecycle.test", code: 71,
            userInfo: [NSLocalizedDescriptionKey: "Synthetic picker timeout"])
        subject.finishForTesting(error: failure)
        await requireFailure(first, code: 71)
        await requireFailure(second, code: 71)
        require(subject.pickerWaiters.isEmpty && !subject.awaitingPicker, "Failure must drain every waiter")
        require(subject.leaseEndCount == 1 && subject.picker.observerRemoveCount == 1,
            "Failure must release its lease and observer")
        do {
            try await subject.waitForPickerResolution()
            fatalError("A resolved picker failure must reach a later intent waiter")
        } catch {
            require((error as NSError).code == 71, "Late waiter must receive the actual picker failure")
        }
        subject.presentPicker()
        require(subject.captureGeneration != oldGeneration, "Fresh request must rotate its generation")
        require(subject.pickerFailure == nil, "Fresh request must clear the old picker failure")
        subject.acceptSelectionForTesting()
        try await subject.waitForPickerResolution()
        subject.finishForTesting()
    }

    @MainActor
    private static func testRepeatSessionsKeepRegistration() async throws {
        let subject = ScreenCaptureCoordinator()
        subject.presentPicker()
        let firstGeneration = subject.captureGeneration
        subject.acceptSelectionForTesting()
        try await subject.waitForPickerResolution()
        subject.finishForTesting()
        require(subject.picker.isActive, "Finishing a session must preserve system picker registration")
        require(subject.picker.activeTransitions == [true], "Cleanup must not unregister an otherwise usable picker")
        require(subject.picker.observers.isEmpty && subject.pickerObserver == nil,
            "Finished session observer must be removed")
        subject.presentPicker()
        require(subject.captureGeneration != firstGeneration, "New session must use a new generation")
        require(subject.picker.presentCount == 2 && subject.picker.observerAddCount == 2,
            "A subsequent session must present with exactly one new observer")
        require(subject.picker.activeTransitions == [true], "Repeat session must not re-register system sharing")
        require(subject.leaseBeginCount == 2 && subject.leaseEndCount == 1,
            "Each new request must own its own background lease")
        subject.finishForTesting()
    }

    @MainActor
    private static func testStartingStoppingAndStreamGuards() {
        let subject = ScreenCaptureCoordinator()
        let generation = subject.captureGeneration
        subject.isStarting = true
        subject.presentPicker()
        subject.isStarting = false
        subject.isStopping = true
        subject.presentPicker()
        subject.isStopping = false
        subject.stream = NSObject()
        subject.presentPicker()
        require(subject.picker.presentCount == 0 && subject.picker.observerAddCount == 0,
            "A start/stop/active stream must not trigger another consent panel")
        require(subject.captureGeneration == generation && !subject.awaitingPicker,
            "A blocked start must not mutate pending consent state")
        require(subject.events == ["requestBlocked", "requestBlocked", "requestBlocked"],
            "Every blocked request must leave a diagnostic event")
    }

    @MainActor
    private static func testUnavailableIsImmediateFailure() async throws {
        let picker = InertPicker()
        picker.isAvailable = false
        let subject = ScreenCaptureCoordinator(picker: picker)
        subject.presentPicker()
        require(!subject.awaitingPicker && subject.picker.presentCount == 0,
            "Unavailable device must not wait for a callback that cannot arrive")
        require(subject.delegate?.errors.count == 1 && subject.picker.observerAddCount == 0,
            "Unavailable device must report the failure without registering an observer")
        do {
            try await subject.waitForPickerResolution()
            fatalError("Unavailable device must fail its intent")
        } catch {
            require((error as NSError).code == 3, "Unavailable device must propagate its production error")
        }
        picker.isAvailable = true
        subject.presentPicker()
        require(subject.pickerFailure == nil && subject.awaitingPicker,
            "A new request must recover when recording becomes available")
        subject.acceptSelectionForTesting()
        try await subject.waitForPickerResolution()
        subject.finishForTesting()
    }

    @MainActor
    private static func testStaleCallbacksDoNotCancelNewRequest() async throws {
        let subject = ScreenCaptureCoordinator()
        subject.presentPicker()
        let oldGeneration = subject.captureGeneration
        subject.finishForTesting()
        subject.presentPicker()
        let generation = subject.captureGeneration
        await subject.cancelForTesting(generation: oldGeneration)
        await subject.failForTesting(error: NSError(domain: "test", code: 1), generation: oldGeneration)
        require(subject.abortCount == 0 && subject.awaitingPicker && subject.captureGeneration == generation,
            "Late callbacks from an earlier session must not abort the new picker")
        await subject.cancelForTesting(generation: generation)
        require(subject.abortCount == 1 && !subject.awaitingPicker, "Current picker cancellation must resolve")
        await subject.cancelForTesting(generation: generation)
        require(subject.abortCount == 1, "Duplicate cancellation must be ignored")
        try await subject.waitForPickerResolution()
    }

    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        fatalError("Async picker task did not reach its expected suspended state")
    }

    @MainActor
    private static func requireFailure(_ task: Task<Void, Error>, code: Int) async {
        do {
            try await task.value
            fatalError("Picker waiter unexpectedly succeeded")
        } catch {
            require((error as NSError).code == code, "Picker waiter must receive the original error")
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
