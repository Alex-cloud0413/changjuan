import MessageUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FeedbackView: View {
    let diagnostics: String

    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @FocusState private var isEditingDescription: Bool
    @State private var issueDescription = ""
    @State private var includesDiagnostics = false
    @State private var showsCopyFallback = false
    @State private var notice: String?
    @State private var mailDraft: FeedbackMailDraft?

    private static let supportAddress = "wenshang017@gmail.com"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(language.text("请描述遇到的问题"), text: $issueDescription, axis: .vertical)
                        .lineLimit(4...8)
                        .focused($isEditingDescription)
                        .accessibilityLabel(language.text("问题描述"))
                        .accessibilityIdentifier("feedback.description")
                } header: {
                    Text(language.text("问题描述"))
                }
                Section {
                    Toggle(language.text("附带诊断信息"), isOn: $includesDiagnostics)
                        .accessibilityIdentifier("feedback.includeDiagnostics")
                    NavigationLink(language.text("查看诊断信息")) {
                        ScrollView {
                            Text(verbatim: diagnostics)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .accessibilityIdentifier("feedback.diagnosticsPayload")
                        }
                        .navigationTitle(language.text("诊断信息"))
                        .navigationBarTitleDisplayMode(.inline)
                    }
                    .accessibilityIdentifier("feedback.viewDiagnostics")
                } footer: {
                    Text(language.text("仅附加可查看的诊断文本，不附加录制画面或照片。"))
                }
                Section {
                    Button(language.text("继续到邮件"), action: prepareEmail)
                        .accessibilityIdentifier("feedback.continueToEmail")
                        .disabled(trimmedDescription.isEmpty)
                    if showsCopyFallback {
                        Button(language.text("拷贝反馈文本"), action: copyFeedback)
                            .accessibilityIdentifier("feedback.copyText")
                            .disabled(trimmedDescription.isEmpty)
                    }
                } footer: {
                    Text(language.text("请在邮件中确认发送。"))
                }
                if let notice {
                    Section {
                        Text(language.text(notice))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("feedback.result")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(language.text("问题反馈"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("关闭")) { dismiss() }
                }
            }
        }
        .onAppear {
            if !MFMailComposeViewController.canSendMail() { showsCopyFallback = true }
        }
        .interactiveDismissDisabled(!trimmedDescription.isEmpty)
        .sheet(item: $mailDraft) { draft in
            FeedbackMailComposer(draft: draft, onFinish: finishMail)
                .ignoresSafeArea()
                .interactiveDismissDisabled()
        }
    }

    private var trimmedDescription: String {
        issueDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draft: FeedbackMailDraft {
        FeedbackMailDraft(recipient: Self.supportAddress, subject: language.text("长卷问题反馈"),
                          body: trimmedDescription, diagnostics: includesDiagnostics ? diagnostics : nil)
    }

    private func prepareEmail() {
        let draft = draft
        guard !draft.body.isEmpty else { return }
        isEditingDescription = false
        notice = nil
        if MFMailComposeViewController.canSendMail() {
            mailDraft = draft
            return
        }
        showsCopyFallback = true
        guard let url = draft.mailtoURL(diagnosticsLabel: language.text("诊断信息")) else {
            showNotice("反馈内容较长，请拷贝后粘贴到邮件。")
            return
        }
        openURL(url) { accepted in
            if !accepted { showNotice("无法打开邮件 App，请拷贝反馈文本后手动发送。") }
        }
    }

    private func copyFeedback() {
        let draft = draft
        guard !draft.body.isEmpty else { return }
        isEditingDescription = false
        let text = ["\(language.text("收件人")): \(draft.recipient)",
                    "\(language.text("主题")): \(draft.subject)", "",
                    draft.inlineBody(diagnosticsLabel: language.text("诊断信息"))].joined(separator: "\n")
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]], options: [.localOnly: true])
        showNotice("已拷贝反馈文本。")
    }

    private func finishMail(_ result: MFMailComposeResult, error: Error?) {
        mailDraft = nil
        if error != nil {
            reportMailFailure()
            return
        }
        switch result {
        case .sent: showNotice("邮件已交给邮件 App 发送。")
        case .saved: showNotice("草稿已保存到邮件 App。")
        case .cancelled: showNotice("已取消邮件，反馈仍保留在此页。")
        case .failed: reportMailFailure()
        @unknown default: reportMailFailure()
        }
    }

    private func reportMailFailure() {
        showsCopyFallback = true
        showNotice("邮件未发送，可拷贝反馈文本后重试。")
    }

    private func showNotice(_ message: String) {
        notice = message
        UIAccessibility.post(notification: .announcement, argument: language.text(message))
    }
}

private struct FeedbackMailDraft: Identifiable {
    let id = UUID()
    let recipient: String
    let subject: String
    let body: String
    let diagnostics: String?

    func inlineBody(diagnosticsLabel: String) -> String {
        guard let diagnostics else { return body }
        return "\(body)\n\n\(diagnosticsLabel)\n\(diagnostics)"
    }

    func mailtoURL(diagnosticsLabel: String) -> URL? {
        let message = inlineBody(diagnosticsLabel: diagnosticsLabel)
        // Keep the handoff small and preserve the whole message when it fits.
        // Percent-encode user text so it cannot introduce more mail fields.
        let limit = 2_000
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard message.utf8.count <= limit,
              let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: unreserved),
              let encodedBody = message.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        let address = "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)"
        guard address.utf8.count <= limit else { return nil }
        return URL(string: address)
    }
}

private struct FeedbackMailComposer: UIViewControllerRepresentable {
    let draft: FeedbackMailDraft
    let onFinish: (MFMailComposeResult, Error?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.recipient])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        if let diagnostics = draft.diagnostics {
            controller.addAttachmentData(Data(diagnostics.utf8), mimeType: "application/json",
                                         fileName: "long-scroll-diagnostics.json")
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult, Error?) -> Void

        init(onFinish: @escaping (MFMailComposeResult, Error?) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result, error)
        }
    }
}
