import Foundation

enum FeedbackMailClient: CaseIterable {
    case systemDefault, gmail, outlook
}

struct FeedbackMailHandoff: Identifiable {
    let client: FeedbackMailClient
    let url: URL
    let bodyToCopy: String?

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
        guard let diagnostics else { return body }
        return "\(body)\n\n\(diagnosticsLabel)\n\(diagnostics)"
    }

    func addressedMailtoURL() -> URL? {
        guard let subject = subject.addingPercentEncoding(withAllowedCharacters: Self.unreserved) else { return nil }
        return URL(string: "mailto:\(recipient)?subject=\(subject)")
    }

    func mailtoURL(diagnosticsLabel: String) -> URL? {
        let message = inlineBody(diagnosticsLabel: diagnosticsLabel)
        // Cap the encoded URL, including the expansion of non-ASCII characters.
        let limit = 2_000
        guard message.utf8.count <= limit,
              let header = addressedMailtoURL(),
              let body = message.addingPercentEncoding(withAllowedCharacters: Self.unreserved) else { return nil }
        let address = "\(header.absoluteString)&body=\(body)"
        guard address.utf8.count <= limit else { return nil }
        return URL(string: address)
    }

    func externalHandoff(to client: FeedbackMailClient, diagnosticsLabel: String) -> FeedbackMailHandoff? {
        if client == .systemDefault, let url = mailtoURL(diagnosticsLabel: diagnosticsLabel) {
            return FeedbackMailHandoff(client: client, url: url, bodyToCopy: nil)
        }
        guard let url = addressedURL(for: client) else { return nil }
        // A named client's custom scheme carries only the address and subject.
        return FeedbackMailHandoff(client: client, url: url, bodyToCopy: inlineBody(diagnosticsLabel: diagnosticsLabel))
    }

    private func addressedURL(for client: FeedbackMailClient) -> URL? {
        let compose: String
        switch client {
        case .systemDefault: return addressedMailtoURL()
        case .gmail: compose = "googlegmail:/co"
        case .outlook: compose = "ms-outlook://compose"
        }
        guard let recipient = recipient.addingPercentEncoding(withAllowedCharacters: Self.unreserved),
              let subject = subject.addingPercentEncoding(withAllowedCharacters: Self.unreserved) else { return nil }
        return URL(string: "\(compose)?to=\(recipient)&subject=\(subject)")
    }
}
