import Foundation

/// Drives the Shares screen — tracks sent to and from you over iMessage,
/// read from the Xomtracks backend. Matches what the web app has always shown.
@Observable
@MainActor
final class SharesViewModel {

    private(set) var shares: [XtShare] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    var direction: XtDirection = .incoming {
        didSet { if oldValue != direction { Task { await load() } } }
    }

    var window: XtTimeWindow = .month {
        didSet { if oldValue != window { Task { await load() } } }
    }

    private let service: XomtracksService

    init(service: XomtracksService = XomtracksService.shared) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            // Newest first. The backend orders by ingest, which is not the same
            // as when the message was actually sent.
            shares = try await service.listShares(direction: direction, window: window)
                .sorted { ($0.messageDate ?? 0) > ($1.messageDate ?? 0) }
        } catch {
            errorMessage = error.localizedDescription
            shares = []
        }
        isLoading = false
    }

    /// Optimistic: the row flips immediately and reverts if the write fails.
    /// A tap that does nothing visible for a round trip reads as broken.
    func toggleHeard(_ share: XtShare) async {
        guard let trackKey = share.trackKey else { return }
        let target = !(share.heard ?? false)
        setHeardLocally(trackKey: trackKey, heard: target)

        do {
            _ = try await service.setHeard(trackKey: trackKey, heard: target)
        } catch {
            setHeardLocally(trackKey: trackKey, heard: !target)
            errorMessage = error.localizedDescription
        }
    }

    /// Every share of the same track shares its heard state — the backend keys
    /// it on `trackKey`, not on the individual share.
    private func setHeardLocally(trackKey: String, heard: Bool) {
        shares = shares.map { share in
            guard share.trackKey == trackKey else { return share }
            return XtShare(
                shareId: share.shareId, direction: share.direction,
                sourceUrl: share.sourceUrl, messageDate: share.messageDate,
                sharerHandle: share.sharerHandle, sharerName: share.sharerName,
                trackTitle: share.trackTitle, trackArtist: share.trackArtist,
                albumName: share.albumName, albumArtUrl: share.albumArtUrl,
                resolvedSpotifyId: share.resolvedSpotifyId,
                resolvedSpotifyUri: share.resolvedSpotifyUri,
                matchStatus: share.matchStatus, trackKey: share.trackKey,
                genres: share.genres, rating: share.rating, heard: heard
            )
        }
    }

    func dismissError() { errorMessage = nil }
}
