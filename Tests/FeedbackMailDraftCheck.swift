import Foundation

@main
struct FeedbackMailDraftCheck {
    private static let recipient = "support@example.invalid"
    private static let subject = "长卷问题反馈"
    private static let label = "诊断信息"
    private static let diagnosticsPasteHint = "[Paste the copied diagnostics at the end.]"
    private static let bodyPasteHint = "[Replace this line with the copied feedback.]"
    private static let addressed = "mailto:support@example.invalid?subject=%E9%95%BF%E5%8D%B7%E9%97%AE%E9%A2%98%E5%8F%8D%E9%A6%88"
    private static let urlLimit = FeedbackMailDraft.maximumDraftURLBytes

    static func main() {
        let body = "第一行 + 100% #状态\n第二行 &bcc=other@example.invalid 🤖 <img src=\"https://example.invalid/x\"> 'quoted'"
        let report = #"{"mode":"vertical","event":"captureStopped"}"#
        let draft = FeedbackMailDraft(recipient: recipient, subject: subject, body: body, diagnostics: report)
        let inline = "\(body)\n\n\(label)\n\(report)"
        precondition(draft.inlineBody(diagnosticsLabel: label) == inline)
        checkFullURL(draft, expectedSubject: subject, expectedBody: inline)
        precondition(draft.addressedMailtoURL()?.absoluteString == addressed)
        checkHandoffs(draft, expectedBody: inline, expectedPaste: nil)
        let outlookDraft = draft.mailtoURL(diagnosticsLabel: label, to: .outlook)
        let outlookQuery = outlookDraft.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        precondition(outlookQuery?.last?.value?.contains(#"&lt;img src="https://example.invalid/x"&gt; 'quoted'"#) == true)

        checkReceiptScalePrefill()

        let subjectWithDelimiters = "问题 + &cc=other@example.invalid"
        let delimiterDraft = FeedbackMailDraft(recipient: recipient, subject: subjectWithDelimiters,
                                               body: body, diagnostics: nil)
        checkFullURL(delimiterDraft, expectedSubject: subjectWithDelimiters, expectedBody: body)
        let delimiterAddress = delimiterDraft.addressedMailtoURL()!
        precondition(delimiterAddress.absoluteString ==
            "mailto:support@example.invalid?subject=%E9%97%AE%E9%A2%98%20%2B%20%26cc%3Dother%40example.invalid")
        checkHandoffs(delimiterDraft, expectedBody: body, expectedPaste: nil)

        // Chinese fits as UTF-8 text here, but its percent-encoded URL exceeds the cap.
        let longChinese = String(repeating: "截", count: urlLimit / 9 + 1)
        precondition(longChinese.utf8.count < urlLimit)
        let oversizedBody = FeedbackMailDraft(recipient: recipient, subject: subject,
                                              body: longChinese, diagnostics: nil)
        precondition(oversizedBody.mailtoURL(diagnosticsLabel: label) == nil)
        precondition(oversizedBody.inlineBody(diagnosticsLabel: label) == longChinese)
        precondition(oversizedBody.addressedMailtoURL()?.absoluteString == addressed)
        checkHandoffs(oversizedBody, expectedBody: bodyPasteHint, expectedPaste: .body(longChinese))

        let oversizedBodyWithReport = FeedbackMailDraft(recipient: recipient, subject: subject,
                                                        body: longChinese, diagnostics: report)
        checkHandoffs(oversizedBodyWithReport, expectedBody: bodyPasteHint,
                      expectedPaste: .body("\(longChinese)\n\n\(label)\n\(report)"))

        let longReport = String(repeating: "report-token", count: urlLimit / "report-token".utf8.count + 1)
        let oversizedReport = FeedbackMailDraft(recipient: recipient, subject: subject, body: body, diagnostics: longReport)
        precondition(oversizedReport.mailtoURL(diagnosticsLabel: label) == nil)
        precondition(oversizedReport.inlineBody(diagnosticsLabel: label) == "\(body)\n\n\(label)\n\(longReport)")
        precondition(oversizedReport.addressedMailtoURL()?.absoluteString == addressed)
        let diagnosticsOnly = "\n\n\(label)\n\(longReport)"
        checkHandoffs(oversizedReport, expectedBody: "\(body)\n\n\(diagnosticsPasteHint)",
                      expectedPaste: .diagnostics(diagnosticsOnly))
        // If the hint itself would overflow, the original issue still fits.
        checkHandoffs(oversizedReport, expectedBody: body, expectedPaste: .diagnostics(diagnosticsOnly),
                      diagnosticsHint: String(repeating: "?", count: urlLimit))

        let withoutReport = FeedbackMailDraft(recipient: recipient, subject: subject, body: body, diagnostics: nil)
        checkFullURL(withoutReport, expectedSubject: subject, expectedBody: body)
        precondition(withoutReport.inlineBody(diagnosticsLabel: label) == body)
        precondition(withoutReport.addressedMailtoURL()?.absoluteString == addressed)
        checkHandoffs(withoutReport, expectedBody: body, expectedPaste: nil)

        let namedWithoutReport = FeedbackMailDraft(recipient: "support+longshot@example.invalid",
                                                   subject: subjectWithDelimiters, body: body, diagnostics: nil)
        checkHandoffs(namedWithoutReport, expectedBody: body, expectedPaste: nil,
                      namedHeader: "to=support%2Blongshot%40example.invalid&subject=%E9%97%AE%E9%A2%98%20%2B%20%26cc%3Dother%40example.invalid")

        checkExactURLLimit()

        print("Feedback email draft checks passed: body prefilling, safe HTML, length cap, and complete paste fallbacks.")
    }

    private static func checkReceiptScalePrefill() {
        let description = String(repeating: "滚动截图后检查邮件正文是否完整。", count: 9)
        // Synthetic capture data with the same shape and scale as a full report.
        let report = """
        {"appVersion":"1.1.5","build":"61","capture":{"axis":"vertical","keepsStatusBar":false},"events":[
        {"event":"captureStarted"},
        {"autoStopped":false,"event":"captureFinishStarted"},
        {"elapsedSeconds":{"seconds":0.052},"event":"captureQueueDrained"},
        {"elapsedSeconds":{"seconds":0.095},"event":"streamStopFinished"},
        {"counts":{"accepted":64,"backwardPTSCount":0,"callbackCount":843,"encoding":0,"finishRequest":1,
        "hostForeground":7,"incompleteStatus":4,"invalidBuffer":0,"invalidPTSCount":0,"missingImage":0,
        "negativeDeltaFromSavedCount":0,"nonfinitePTSCount":0,"notReady":0,"paused":0,"ptsEpochChangeCount":0,
        "repeatedPTSCount":2,"sealed":0,"throttled":777,"writeFailed":0,"zeroDeltaFromSavedCount":0},
        "elapsedSeconds":{"maximumCallbackGap":0.017,"maximumPTSGap":0.034,"wallSeconds":13.95},
        "event":"capturePipelineSnapshot","frameSize":{"height":2622,"width":1206}},
        {"counts":{"frameCount":64},"event":"captureStopped"},
        {"counts":{"frameCount":64,"inputPageCount":3},"elapsedSeconds":{"captureStoppedToProcessingSeconds":0.093},
        "event":"processingStarted"},
        {"counts":{"frameCount":64},"event":"stitchingQueued"},
        {"counts":{"fallbackFrameCount":0,"outputCount":1,"preparedAlignmentCount":63,"preparedFrameCount":64},
        "elapsedSeconds":{"assemblySeconds":0.843,"renderingSeconds":0.14,"samplingSeconds":1.071,
        "selectionSeconds":0.041,"stitchDispatchDelaySeconds":0.011,"stitchReturnDelaySeconds":0.004,
        "stitchingSeconds":2.067},"event":"stitchingFinished"},
        {"elapsedSeconds":{"seconds":0.006},"event":"photosAuthorizationFinished"},
        {"elapsedSeconds":{"photosCallbackResumeSeconds":0.008,"photosWriteSeconds":0.218},"event":"photosWriteFinished"},
        {"elapsedSeconds":{"processingWallSeconds":3.048,"resultPersistenceSeconds":0.027},"event":"resultSaved"}
        ],"osVersion":{"major":27,"minor":2,"patch":0},"schemaVersion":1}
        """.replacingOccurrences(of: "\n", with: "")
        precondition((1_800...2_000).contains(report.utf8.count))
        let reportJSON = (try? JSONSerialization.jsonObject(with: Data(report.utf8))) as? [String: Any]
        precondition((reportJSON?["events"] as? [[String: Any]])?.count == 12)

        let draft = FeedbackMailDraft(recipient: recipient, subject: subject, body: description, diagnostics: report)
        checkHandoffs(draft, expectedBody: "\(description)\n\n\(label)\n\(report)", expectedPaste: nil)
        for client in FeedbackMailClient.allCases {
            let encodedSize = draft.mailtoURL(diagnosticsLabel: label, to: client)?.absoluteString.utf8.count ?? 0
            precondition(encodedSize > 2_000, "The realistic fixture must exceed the old URL budget")
        }
    }

    private static func checkExactURLLimit() {
        let sample = FeedbackMailDraft(recipient: recipient, subject: subject, body: "x", diagnostics: nil)
        for client in FeedbackMailClient.allCases {
            let sampleSize = sample.mailtoURL(diagnosticsLabel: label, to: client)!.absoluteString.utf8.count
            let limitBody = String(repeating: "x", count: urlLimit - sampleSize + 1)
            let limitDraft = FeedbackMailDraft(recipient: recipient, subject: subject, body: limitBody, diagnostics: nil)
            precondition(limitDraft.mailtoURL(diagnosticsLabel: label, to: client)?.absoluteString.utf8.count == urlLimit)
            let overLimitDraft = FeedbackMailDraft(recipient: recipient, subject: subject, body: limitBody + "x", diagnostics: nil)
            precondition(overLimitDraft.mailtoURL(diagnosticsLabel: label, to: client) == nil)
        }
    }

    private static func checkHandoffs(_ draft: FeedbackMailDraft, expectedBody: String,
                                      expectedPaste: FeedbackMailPaste?, diagnosticsHint: String = diagnosticsPasteHint,
                                      namedHeader: String? = nil) {
        let routes: [(FeedbackMailClient, String)] = [
            (.systemDefault, "mailto:\(draft.recipient)?"), (.gmail, "googlegmail:/co?"),
            (.outlook, "ms-outlook://compose?")
        ]
        for (client, prefix) in routes {
            guard let handoff = draft.externalHandoff(to: client, diagnosticsLabel: label,
                                                     diagnosticsPasteHint: diagnosticsHint, bodyPasteHint: bodyPasteHint),
                  let components = URLComponents(url: handoff.url, resolvingAgainstBaseURL: false),
                  let items = components.queryItems, let body = items.last?.value else {
                fatalError("Expected a nonempty mail handoff for \(client)")
            }
            precondition(handoff.client == client)
            precondition(handoff.url.absoluteString.hasPrefix(prefix))
            precondition(handoff.url.absoluteString.utf8.count <= urlLimit)
            precondition(components.fragment == nil)
            let recipientItem = URLQueryItem(name: "to", value: draft.recipient)
            let subjectItem = URLQueryItem(name: "subject", value: draft.subject)
            precondition(Array(items.dropLast()) == (client == .systemDefault ? [subjectItem] : [recipientItem, subjectItem]))
            precondition(items.last?.name == "body" && !body.isEmpty)
            if let namedHeader, client != .systemDefault {
                precondition(handoff.url.absoluteString.hasPrefix(prefix + namedHeader + "&body="))
            }
            if client == .outlook {
                precondition(!body.contains("<img"), "User-provided markup must never become active HTML")
                precondition(decodeOutlookBody(body) == expectedBody)
            } else {
                precondition(body == expectedBody)
            }
            precondition(handoff.paste == expectedPaste)
        }
    }

    private static func decodeOutlookBody(_ body: String) -> String {
        body.replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func checkFullURL(_ draft: FeedbackMailDraft, expectedSubject: String, expectedBody: String) {
        guard let url = draft.mailtoURL(diagnosticsLabel: label),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            fatalError("Expected a bounded mailto URL")
        }
        precondition(components.scheme == "mailto" && components.path == recipient)
        precondition(components.fragment == nil)
        precondition(components.queryItems == [
            URLQueryItem(name: "subject", value: expectedSubject),
            URLQueryItem(name: "body", value: expectedBody)
        ])
        for token in ["%2B", "%25", "%23", "%0A", "%26bcc%3D"] {
            precondition(url.absoluteString.contains(token), "Missing percent encoding for \(token)")
        }
    }
}
