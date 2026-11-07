import Foundation

@main
struct FeedbackMailDraftCheck {
    private static let recipient = "support@example.invalid"
    private static let subject = "长卷问题反馈"
    private static let label = "诊断信息"
    private static let addressed = "mailto:support@example.invalid?subject=%E9%95%BF%E5%8D%B7%E9%97%AE%E9%A2%98%E5%8F%8D%E9%A6%88"

    static func main() {
        let body = "第一行 + 100% #状态\n第二行 &bcc=other@example.invalid 🤖"
        let report = #"{"mode":"vertical","event":"captureStopped"}"#
        let draft = FeedbackMailDraft(recipient: recipient, subject: subject, body: body, diagnostics: report)
        let inline = "\(body)\n\n\(label)\n\(report)"
        precondition(draft.inlineBody(diagnosticsLabel: label) == inline)
        checkFullURL(draft, expectedSubject: subject, expectedBody: inline)
        precondition(draft.addressedMailtoURL()?.absoluteString == addressed)

        let subjectWithDelimiters = "问题 + &cc=other@example.invalid"
        let delimiterDraft = FeedbackMailDraft(recipient: recipient, subject: subjectWithDelimiters,
                                               body: body, diagnostics: nil)
        checkFullURL(delimiterDraft, expectedSubject: subjectWithDelimiters, expectedBody: body)
        let delimiterAddress = delimiterDraft.addressedMailtoURL()!
        precondition(delimiterAddress.absoluteString ==
            "mailto:support@example.invalid?subject=%E9%97%AE%E9%A2%98%20%2B%20%26cc%3Dother%40example.invalid")

        // Chinese fits as UTF-8 text here, but its percent-encoded URL exceeds the cap.
        let longChinese = String(repeating: "截", count: 300)
        precondition(longChinese.utf8.count < 2_000)
        let oversizedBody = FeedbackMailDraft(recipient: recipient, subject: subject,
                                              body: longChinese, diagnostics: nil)
        precondition(oversizedBody.mailtoURL(diagnosticsLabel: label) == nil)
        precondition(oversizedBody.inlineBody(diagnosticsLabel: label) == longChinese)
        precondition(oversizedBody.addressedMailtoURL()?.absoluteString == addressed)

        let longReport = String(repeating: "report-token", count: 200)
        let oversizedReport = FeedbackMailDraft(recipient: recipient, subject: subject, body: body, diagnostics: longReport)
        precondition(oversizedReport.mailtoURL(diagnosticsLabel: label) == nil)
        precondition(oversizedReport.inlineBody(diagnosticsLabel: label) == "\(body)\n\n\(label)\n\(longReport)")
        precondition(oversizedReport.addressedMailtoURL()?.absoluteString == addressed)

        let withoutReport = FeedbackMailDraft(recipient: recipient, subject: subject, body: body, diagnostics: nil)
        checkFullURL(withoutReport, expectedSubject: subject, expectedBody: body)
        precondition(withoutReport.inlineBody(diagnosticsLabel: label) == body)
        precondition(withoutReport.addressedMailtoURL()?.absoluteString == addressed)

        print("Feedback email draft checks passed: Unicode round-trip, delimiter safety, length cap, and body-free fallback.")
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
