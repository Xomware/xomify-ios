import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

/// Minimal Share Extension entry point.
///
/// When the user taps Share on a track in Spotify and selects "Xomify",
/// iOS instantiates this controller. We:
///   1. Read the incoming URL from the extension context.
///   2. Parse the Spotify track id.
///   3. Show a minimal UI — track id preview + "Continue in Xomify" button.
///   4. On tap, open `xomify://share?trackId=<id>` and dismiss.
///
/// ## Xcode Setup (manual — see EXTENSION_SETUP.md)
/// This file is included in the project repository but the Share Extension
/// target must be added in Xcode. Follow the steps in `EXTENSION_SETUP.md`.
final class ShareViewController: UIViewController {

    // MARK: - UI

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 20
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let logoLabel: UILabel = {
        let l = UILabel()
        l.text = "Xomify"
        l.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        l.textColor = .white
        return l
    }()

    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        l.textColor = UIColor.lightGray
        l.textAlignment = .center
        l.numberOfLines = 2
        return l
    }()

    private let continueButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Continue in Xomify"
        config.baseForegroundColor = .black
        config.baseBackgroundColor = UIColor(red: 0.08, green: 0.82, blue: 0.54, alpha: 1) // xomifyGreen
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        let b = UIButton(configuration: config)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let cancelButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Cancel"
        config.baseForegroundColor = .lightGray
        let b = UIButton(configuration: config)
        return b
    }()

    // MARK: - State

    private var resolvedTrackId: String?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractTrackId()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 1) // xomifyDark

        stackView.addArrangedSubview(logoLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(continueButton)
        stackView.addArrangedSubview(cancelButton)

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            continueButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])

        continueButton.addTarget(self, action: #selector(didTapContinue), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)

        subtitleLabel.text = "Loading track…"
        continueButton.isEnabled = false
    }

    // MARK: - Track ID Extraction

    private func extractTrackId() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            subtitleLabel.text = "No track found"
            return
        }

        let typeURL = UTType.url.identifier

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(typeURL) {
                provider.loadItem(forTypeIdentifier: typeURL, options: nil) { [weak self] item, _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        let url: URL?
                        if let u = item as? URL {
                            url = u
                        } else if let s = item as? String {
                            url = URL(string: s)
                        } else {
                            url = nil
                        }
                        self.handleResolvedURL(url)
                    }
                }
                return
            }
        }
        subtitleLabel.text = "No URL found in share"
    }

    private func handleResolvedURL(_ url: URL?) {
        guard let url = url,
              let trackId = url.xomifyShareTrackId else {
            subtitleLabel.text = url != nil
                ? "Not a Spotify track link"
                : "Could not read URL"
            return
        }
        resolvedTrackId = trackId
        subtitleLabel.text = "Track: …\(trackId.suffix(8))"
        continueButton.isEnabled = true
    }

    // MARK: - Actions

    @objc private func didTapContinue() {
        guard let trackId = resolvedTrackId,
              let deepLink = URL(string: "xomify://share?trackId=\(trackId)") else {
            extensionContext?.cancelRequest(withError: NSError(domain: "XomifyShareExtension", code: 1))
            return
        }

        // Open the main app with the deep link.
        // `extensionContext?.open` is not available on Share extensions targeting
        // iOS < 17 without a UIApplication reference. The safest approach
        // cross-version is to use the responder chain trick.
        var responder: UIResponder? = self
        while let next = responder?.next {
            responder = next
            if let application = responder as? UIApplication {
                application.open(deepLink, options: [:], completionHandler: nil)
                break
            }
        }

        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    @objc private func didTapCancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "XomifyShareExtension", code: 0))
    }
}
