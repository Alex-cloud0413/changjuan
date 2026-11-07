import MessageUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FeedbackView: View {
    let diagnostics: String

    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isEditingDescription: Bool
    @State private var issueDescription = ""
    @State private var includesDiagnostics = false
    @State private var canUseMailComposer = true
    @State private var showsCopyFallback = false
    @State private var notice: String?
    @State private var mailDraft: FeedbackMailDraft?

    private static let supportAddress = "wenshang017@gmail.com"

    var body: some View {
        let copyBeforeOpening = requiresClipboardHandoff
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
                    Button(language.text(copyBeforeOpening ? "拷贝正文并打开邮件" : "继续到邮件")) {
                        prepareEmail(copyBeforeOpening: copyBeforeOpening)
                    }
                    .accessibilityIdentifier("feedback.continueToEmail")
                    .disabled(trimmedDescription.isEmpty)
                    if !canUseMailComposer || showsCopyFallback {
                        Button(language.text("拷贝反馈正文"), action: copyFeedback)
                            .accessibilityIdentifier("feedback.copyText")
                            .disabled(trimmedDescription.isEmpty)
                        LabeledContent(language.text("收件人"), value: Self.supportAddress)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text(language.text(copyBeforeOpening ? "打开邮件后，请粘贴已拷贝的正文，再确认发送。" : "请在邮件中确认发送。"))
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
            canUseMailComposer = MFMailComposeViewController.canSendMail()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { canUseMailComposer = MFMailComposeViewController.canSendMail() }
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

    private var requiresClipboardHandoff: Bool {
        !canUseMailComposer && !trimmedDescription.isEmpty && draft.mailtoURL(diagnosticsLabel: language.text("诊断信息")) == nil
    }

    private func prepareEmail(copyBeforeOpening: Bool) {
        let draft = draft
        guard !draft.body.isEmpty else { return }
        isEditingDescription = false
        notice = nil
        canUseMailComposer = MFMailComposeViewController.canSendMail()
        if canUseMailComposer {
            mailDraft = draft
            return
        }
        if let url = draft.mailtoURL(diagnosticsLabel: language.text("诊断信息")) {
            openEmail(url, copiedBody: false)
            return
        }
        guard copyBeforeOpening, let url = draft.addressedMailtoURL() else {
            showNotice("正文较长，请选择拷贝正文并打开邮件。")
            return
        }
        copyBody(of: draft)
        showNotice("已拷贝正文，请在邮件中粘贴。")
        openEmail(url, copiedBody: true)
    }

    private func openEmail(_ url: URL, copiedBody: Bool) {
        openURL(url) { accepted in
            if !accepted {
                showNotice(copiedBody ? "无法打开邮件 App。正文已拷贝，可在其他邮件 App 中粘贴。"
                                      : "无法打开邮件 App，请拷贝反馈正文后手动发送。")
            }
        }
    }

    private func copyFeedback() {
        let draft = draft
        guard !draft.body.isEmpty else { return }
        isEditingDescription = false
        copyBody(of: draft)
        showNotice("已拷贝反馈正文。")
    }

    private func copyBody(of draft: FeedbackMailDraft) {
        let text = draft.inlineBody(diagnosticsLabel: language.text("诊断信息"))
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]], options: [.localOnly: true])
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
        showNotice("邮件未发送，可拷贝反馈正文后重试。")
    }

    private func showNotice(_ message: String) {
        notice = message
        UIAccessibility.post(notification: .announcement, argument: language.text(message))
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
