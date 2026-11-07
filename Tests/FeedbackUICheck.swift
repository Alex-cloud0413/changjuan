import XCTest

final class FeedbackUICheck: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSettingsFeedbackPreviewAndCopyFallback() throws {
        let app = XCUIApplication(bundleIdentifier: "com.gaoyiming.longshot.private")
        app.launchArguments = ["-longshot.hasCompletedUsageGuide.v1", "YES"]
        app.launch()

        let settings = homeButton(in: app, id: "home.settings", labels: ["Settings", "设置"])
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let feedback = app.buttons["settings.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        feedback.tap()

        let continueToEmail = app.buttons["feedback.continueToEmail"]
        XCTAssertTrue(continueToEmail.waitForExistence(timeout: 5))
        XCTAssertFalse(continueToEmail.isEnabled, "An empty description cannot create an email")
        let copy = app.buttons["feedback.copyText"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Use a simulator with Mail unconfigured")
        XCTAssertFalse(copy.isEnabled, "An empty description cannot be copied as feedback")

        let includeDiagnostics = app.switches["feedback.includeDiagnostics"]
        XCTAssertEqual(includeDiagnostics.value as? String, "0", "Diagnostics require explicit opt-in")
        // SwiftUI exposes the whole row as the switch; tap the trailing control.
        let switchControl = includeDiagnostics.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5))
        switchControl.tap()
        XCTAssertEqual(includeDiagnostics.value as? String, "1")
        let report = try openDiagnostics(in: app)
        XCTAssertEqual(report["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(report["events"] as? [[String: Any]])

        let diagnosticsBar = app.navigationBars.matching(NSPredicate(format: "identifier IN %@", ["Diagnostics", "诊断信息"])).firstMatch
        XCTAssertTrue(diagnosticsBar.exists)
        diagnosticsBar.buttons.firstMatch.tap()
        XCTAssertTrue(includeDiagnostics.waitForExistence(timeout: 5))
        switchControl.tap()
        XCTAssertEqual(includeDiagnostics.value as? String, "0")

        let description = app.descendants(matching: .any).matching(identifier: "feedback.description").firstMatch
        XCTAssertTrue(description.exists)
        description.tap()
        description.typeText("Synthetic simulator feedback")
        XCTAssertTrue(continueToEmail.isEnabled)
        XCTAssertTrue(copy.isEnabled)
        reveal(copy, in: app)
        copy.tap()
        let result = app.staticTexts["feedback.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(["Feedback body copied.", "已拷贝反馈正文。"].contains(result.label))
        XCTAssertEqual(app.state, .runningForeground)

        let close = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "关闭"])).firstMatch
        XCTAssertTrue(close.exists)
        close.tap()
        XCTAssertTrue(feedback.waitForExistence(timeout: 5), "Closing feedback returns to Settings")
    }

    func testLongBodyCopiesAndHandsOffToMail() {
        let app = XCUIApplication(bundleIdentifier: "com.gaoyiming.longshot.private")
        app.launchArguments = ["-longshot.hasCompletedUsageGuide.v1", "YES"]
        app.launch()

        let settings = homeButton(in: app, id: "home.settings", labels: ["Settings", "设置"])
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let feedback = app.buttons["settings.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        feedback.tap()

        let description = app.descendants(matching: .any).matching(identifier: "feedback.description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Synthetic feedback " + String(repeating: "?", count: 680))

        let handoff = app.buttons["feedback.continueToEmail"]
        reveal(handoff, in: app)
        XCTAssertTrue(["Copy body and open email", "拷贝正文并打开邮件"].contains(handoff.label))
        handoff.tap()

        // A simulator with no configured account can open Mail setup or reject the handoff.
        // Observe the handoff or its recovery message without sending anything.
        let mail = XCUIApplication(bundleIdentifier: "com.apple.mobilemail")
        let result = app.staticTexts["feedback.result"]
        let handled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if app.state != .runningForeground { return mail.state == .runningForeground }
            guard result.exists else { return false }
            return ["Couldn’t open a mail app. The body is copied and can be pasted into another mail app.",
                    "无法打开邮件 App。正文已拷贝，可在其他邮件 App 中粘贴。"].contains(result.label)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [handled], timeout: 10), .completed)
    }

    func testCaptureFailureFeedbackHasNoCaptureEvents() throws {
        let app = XCUIApplication(bundleIdentifier: "com.gaoyiming.longshot.private")
        app.launchArguments = ["-longshot.hasCompletedUsageGuide.v1", "YES"]
        app.launch()

        // ScreenCaptureKit returns a device-only error on this simulator build.
        let capture = homeButton(in: app, id: "home.capture", labels: ["Start capture", "开始收卷"])
        XCTAssertTrue(capture.waitForExistence(timeout: 15))
        capture.tap()
        let feedback = homeButton(in: app, id: "home.feedback", labels: ["Feedback", "问题反馈"])
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        feedback.tap()

        let report = try openDiagnostics(in: app)
        XCTAssertEqual(report["schemaVersion"] as? Int, 1)
        XCTAssertEqual((report["events"] as? [[String: Any]])?.count, 0)
        XCTAssertNil(report["capture"], "A failure before capture has no session to include")
    }

    private func homeButton(in app: XCUIApplication, id: String, labels: [String]) -> XCUIElement {
        // SwiftUI can propagate the home container's identifier to its children.
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", id, labels)).firstMatch
    }

    private func openDiagnostics(in app: XCUIApplication) throws -> [String: Any] {
        let preview = app.buttons["feedback.viewDiagnostics"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        let payload = app.staticTexts["feedback.diagnosticsPayload"]
        XCTAssertTrue(payload.waitForExistence(timeout: 5))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.label.utf8)) as? [String: Any])
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
