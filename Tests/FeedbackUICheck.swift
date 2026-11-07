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

    func testMailChooserCancelPreservesDraftAndDefaultHandsOffLongBody() {
        let app = XCUIApplication(bundleIdentifier: "com.gaoyiming.longshot.private")
        app.launchArguments = ["-longshot.hasCompletedUsageGuide.v1", "YES"]
        app.launch()

        let settings = homeButton(in: app, id: "home.settings", labels: ["Settings", "设置"])
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let feedback = app.buttons["settings.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        feedback.tap()

        let includeDiagnostics = app.switches["feedback.includeDiagnostics"]
        XCTAssertTrue(includeDiagnostics.waitForExistence(timeout: 5))
        includeDiagnostics.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()
        XCTAssertEqual(includeDiagnostics.value as? String, "1")

        let body = "Synthetic feedback " + String(repeating: "?", count: 680)
        let description = app.descendants(matching: .any).matching(identifier: "feedback.description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText(body)

        let handoff = app.buttons["feedback.continueToEmail"]
        reveal(handoff, in: app)
        XCTAssertTrue(["Choose mail app", "选择邮件 App"].contains(handoff.label))
        let defaultMail = app.buttons.matching(NSPredicate(format: "label IN %@", [
            "Default Mail App", "默认邮件 App"
        ])).firstMatch
        let systemDefaults = app.buttons.matching(NSPredicate(format: "label IN %@", [
            "Change system default mail app", "更改系统默认邮件 App"
        ])).firstMatch
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch

        handoff.tap()
        XCTAssertTrue(defaultMail.waitForExistence(timeout: 5))

        let chooser = XCTAttachment(screenshot: app.screenshot())
        chooser.name = "Feedback Mail Chooser"
        chooser.lifetime = .keepAlways
        add(chooser)

        if cancel.exists {
            cancel.tap()
        } else {
            // The popover form uses an outside tap in place of the Cancel button.
            let dismissalY: CGFloat = defaultMail.frame.midY < app.frame.midY ? 0.90 : 0.15
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dismissalY)).tap()
        }
        XCTAssertTrue(defaultMail.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.staticTexts["feedback.result"].exists, "Cancel leaves the draft without a handoff result")
        for _ in 0..<4 where !description.isHittable { app.swipeDown() }
        XCTAssertEqual(description.value as? String, body)
        XCTAssertEqual(includeDiagnostics.value as? String, "1")

        reveal(handoff, in: app)
        handoff.tap()
        XCTAssertTrue(systemDefaults.waitForExistence(timeout: 5))
        systemDefaults.tap()
        let settingsApp = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        if settingsApp.wait(for: .runningForeground, timeout: 5) {
            app.activate()
        } else {
            let notice = app.staticTexts["feedback.result"]
            XCTAssertTrue(notice.waitForExistence(timeout: 5))
            XCTAssertTrue(["Choose Email under Default Apps in Settings.",
                           "请在系统设置的默认 App 中选择电子邮件。"].contains(notice.label))
        }
        XCTAssertEqual(description.value as? String, body)
        XCTAssertEqual(includeDiagnostics.value as? String, "1")

        reveal(handoff, in: app)
        handoff.tap()
        XCTAssertTrue(defaultMail.waitForExistence(timeout: 5))
        defaultMail.tap()

        // A simulator with no configured account can open Mail setup or reject the handoff.
        // Observe the handoff or its recovery message without sending anything.
        let mail = XCUIApplication(bundleIdentifier: "com.apple.mobilemail")
        let result = app.staticTexts["feedback.result"]
        let handled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if app.state != .runningForeground { return mail.state == .runningForeground }
            guard result.exists else { return false }
            return ["Couldn’t open a mail app. Copy the feedback body and send it manually.",
                    "无法打开邮件 App，请拷贝反馈正文后手动发送。"].contains(result.label)
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
