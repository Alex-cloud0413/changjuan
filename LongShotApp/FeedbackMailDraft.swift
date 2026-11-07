import Foundation

enum FeedbackMailClient: CaseIterable {
    case systemDefault, gmail, outlook

    var composeEndpoint: String? {
        switch self {
        case .systemDefault: return nil
        case .gmail: return "googlegmail:/co"
        case .outlook: return "ms-outlook://compose"
        }
    }
}

enum FeedbackMailPaste: Equatable {
    case diagnostics(String)
    case body(String)
}

struct FeedbackMailHandoff: Identifiable {
    let client: FeedbackMailClient
    let url: URL
    let paste: FeedbackMailPaste?

    var id: FeedbackMailClient { client }
}

struct FeedbackMailDraft: Identifiable {
    let id = UUID()
    let recipient: String
    let subject: String
    let body: String
    let diagnostics: String?

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    func inlineBody(diagnosticsLabel: String) -> String {
        body + diagnosticsSuffix(label: diagnosticsLabel)
    }

    func addressedMailtoURL() -> URL? {
        guard let subject = subject.addingPercentEncoding(withAllowedCharacters: Self.unreserved) else { return nil }
        return URL(string: "mailto:\(recipient)?subject=\(subject)")
    }

    func mailtoURL(diagnosticsLabel: String, to client: FeedbackMailClient = .systemDefault) -> URL? {
        guard let header = addressedURL(for: client) else { return nil }
        return draftURL(header: header, message: inlineBody(diagnosticsLabel: diagnosticsLabel), client: client)
    }

    func externalHandoff(
        to client: FeedbackMailClient,
        diagnosticsLabel: String,
        diagnosticsPasteHint: String = "[Paste the copied diagnostics at the end of this email before sending.]",
        bodyPasteHint: String = "[Replace this line with the feedback copied from Long Scroll before sending.]"
    ) -> FeedbackMailHandoff? {
        if let url = mailtoURL(diagnosticsLabel: diagnosticsLabel, to: client) {
            return FeedbackMailHandoff(client: client, url: url, paste: nil)
        }
        guard let header = addressedURL(for: client) else { return nil }
        // Keep the user's description in the draft when only the diagnostics overflow.
        if diagnostics != nil,
           let url = draftURL(header: header, message: "\(body)\n\n\(diagnosticsPasteHint)", client: client)
                     ?? draftURL(header: header, message: body, client: client) {
            return FeedbackMailHandoff(client: client, url: url, paste: .diagnostics(diagnosticsSuffix(label: diagnosticsLabel)))
        }
        guard let url = draftURL(header: header, message: bodyPasteHint, client: client) else { return nil }
        return FeedbackMailHandoff(client: client, url: url, paste: .body(inlineBody(diagnosticsLabel: diagnosticsLabel)))
    }

    private func addressedURL(for client: FeedbackMailClient) -> URL? {
        guard let compose = client.composeEndpoint else { return addressedMailtoURL() }
        guard let recipient = recipient.addingPercentEncoding(withAllowedCharacters: Self.unreserved),
              let subject = subject.addingPercentEncoding(withAllowedCharacters: Self.unreserved) else { return nil }
        return URL(string: "\(compose)?to=\(recipient)&subject=\(subject)")
    }

    private func diagnosticsSuffix(label: String) -> String {
        guard let diagnostics else { return "" }
        return "\n\n\(label)\n\(diagnostics)"
    }

    private func draftURL(header: URL, message: String, client: FeedbackMailClient) -> URL? {
        // Cap the encoded URL, including the expansion of non-ASCII characters.
        let limit = 2_000
        guard !message.isEmpty, message.utf8.count <= limit else { return nil }
        let formatted = client == .outlook ? outlookBody(from: message) : message
        guard let body = formatted.addingPercentEncoding(withAllowedCharacters: Self.unreserved) else { return nil }
        let address = "\(header.absoluteString)&body=\(body)"
        guard address.utf8.count <= limit else { return nil }
        return URL(string: address)
    }

    private func outlookBody(from text: String) -> String {
        // Outlook accepts HTML in body. Treat feedback and diagnostics as plain text.
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
