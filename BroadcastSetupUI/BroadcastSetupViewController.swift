import ReplayKit
import UIKit

/// ReplayKit requires a setup UI service before it can vend an
/// `RPBroadcastController`. The user has already explicitly requested capture
/// by tapping "开始收卷", so this service completes the local-only setup without
/// adding another product-specific confirmation step.
final class BroadcastSetupViewController: UIViewController {
    private var hasCompletedSetup = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()

        let title = UILabel()
        title.text = "正在准备长卷录制…"
        title.font = .preferredFont(forTextStyle: .headline)
        title.textColor = .label

        let stack = UIStackView(arrangedSubviews: [indicator, title])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasCompletedSetup else { return }
        hasCompletedSetup = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            // ReplayKit serializes this value through an item provider. A custom
            // URL scheme can fail that hand-off on iOS with an empty file-system
            // representation, so use a normal HTTPS service URL just like
            // Apple's Broadcast Setup UI template. No frames are uploaded to it;
            // the Broadcast Upload extension still stores everything locally.
            let broadcastURL = URL(string: "https://longscroll.invalid/broadcast/local")!
            let setupInfo: [String: NSCoding & NSObjectProtocol] = [
                "mode": "local-long-scroll" as NSString
            ]
            extensionContext?.completeRequest(
                withBroadcast: broadcastURL,
                setupInfo: setupInfo
            )
        }
    }
}
