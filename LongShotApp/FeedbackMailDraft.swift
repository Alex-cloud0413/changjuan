import Foundation

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
}
