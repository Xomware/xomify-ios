import Foundation

/// Parses incoming `xomify://share?trackId=<id>` deep links (and equivalent
/// Spotify HTTPS / URI formats) and stashes the track id so the Feed view can
/// open the composer pre-loaded with that track once the user is authenticated.
///
/// Call sites:
///   1. `Xomify_iOSApp.onOpenURL` — forwards the raw URL here.
///   2. `XomifyShareExtension.ShareViewController` — builds the URL and hands
///      control back to the main app via `extensionContext?.open(_:)`.
///   3. `FeedView` — observes `pendingTrackId` and consumes it on appearance.
///
/// Accepted URL shapes:
///   xomify://share?trackId=<id>
///   https://open.spotify.com/track/<id>     (share sheet copy-link)
///   spotify:track:<id>                       (Spotify URI)
@Observable
@MainActor
final class ShareDeepLinkCoordinator {

    static let shared = ShareDeepLinkCoordinator()

    /// Stashed track id — consumed by `FeedView` once it appears.
    private(set) var pendingTrackId: String?

    private init() {}

    /// Parse `url` and, if it is a share deep link, stash the track id.
    /// Safe to call with any URL — unrecognised shapes are ignored.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let trackId = url.xomifyShareTrackId else { return false }
        pendingTrackId = trackId
        return true
    }

    /// Consume and return the pending track id, clearing it immediately so
    /// subsequent appearances do not re-trigger the composer.
    func consume() -> String? {
        defer { pendingTrackId = nil }
        return pendingTrackId
    }
}
