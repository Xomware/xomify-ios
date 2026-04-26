import Foundation

/// Owns per-card interactive state: queue-to-Spotify + rate. Local optimistic
/// state is authoritative for UI — the backend is a write-through.
///
/// Rating currently writes directly to `ratings/publish`. Once sub-feature 4
/// (`backend-interactions-and-notifications`) ships `shares_interaction`,
/// swap the call site over — the behaviour is identical from the user's POV.
@Observable
@MainActor
final class ShareCardViewModel {

    // MARK: - State

    /// Local copy so optimistic mutations don't fight the parent list's copy.
    var share: Share

    // Queue state
    var isQueuing: Bool = false
    var queuedLocally: Bool
    var queueError: String?

    // Rate state
    var myRating: Int?
    var isRating: Bool = false
    var rateError: String?

    // Reaction state — slugs in flight so a fast double-tap doesn't fire two
    // competing toggles for the same emoji.
    var reactingSlugs: Set<String> = []
    var reactError: String?

    // MARK: - Dependencies

    private let xomifyService: XomifyServiceProtocol
    private let spotifyService: SpotifyQueueing

    /// The authenticated viewer's email. Pushed down from the parent VM so the
    /// card doesn't need to re-resolve it on every interaction. Stored as `var`
    /// so `ShareCardView` can re-sync it once the parent's async email lookup
    /// resolves — otherwise rate/queue/react/delete would fire with an empty
    /// email and the own-post menu would never appear.
    var viewerEmail: String

    // MARK: - Init

    init(
        share: Share,
        viewerEmail: String,
        xomifyService: XomifyServiceProtocol = XomifyService.shared,
        spotifyService: SpotifyQueueing = SpotifyPlaybackCoordinator.shared
    ) {
        self.share = share
        self.viewerEmail = viewerEmail
        self.xomifyService = xomifyService
        self.spotifyService = spotifyService
        self.queuedLocally = share.viewerHasQueued
        self.myRating = share.viewerRating
    }

    // MARK: - Computed

    /// Visible "queued by N friends" count including the viewer's optimistic flip.
    var displayedQueueCount: Int {
        let base = share.queuedCount
        // If the viewer flipped locally but the share hadn't counted them yet, add one.
        if queuedLocally && !share.viewerHasQueued {
            return base + 1
        }
        return base
    }

    var displayedRatedCount: Int {
        let base = share.ratedCount
        if myRating != nil && share.viewerRating == nil {
            return base + 1
        }
        return base
    }

    // MARK: - Queue

    /// Queue the track on Spotify. Optimistically flips `queuedLocally`; rolls
    /// back on failure and surfaces an actionable message in `queueError`.
    func queue() async {
        guard !isQueuing else { return }

        isQueuing = true
        queueError = nil
        let wasQueued = queuedLocally
        queuedLocally = true
        defer { isQueuing = false }

        do {
            try await spotifyService.queueTrack(uri: share.trackUri)
        } catch let error as SpotifyServiceError {
            queuedLocally = wasQueued
            queueError = error.errorDescription
            return
        } catch {
            queuedLocally = wasQueued
            queueError = error.localizedDescription
            return
        }

        // Best-effort write-through so other viewers see the updated count on
        // their next refresh. Failure is silent — the Spotify queue succeeded,
        // which is what the user cared about.
        // TODO(sub-feature-4): swap to `shares_interaction` once deployed.
    }

    // MARK: - Rate

    /// Publish a rating (1–5). Optimistic update with rollback on failure.
    func rate(_ stars: Int) async {
        guard (1...5).contains(stars), !isRating else { return }

        isRating = true
        rateError = nil
        let previous = myRating
        myRating = stars
        defer { isRating = false }

        do {
            _ = try await xomifyService.publishRating(
                email: viewerEmail,
                trackId: share.trackId,
                trackName: share.trackName,
                artistName: share.artistName,
                albumArt: share.albumArtUrl,
                rating: stars,
                review: nil
            )
            // Patch the share so when the user navigates to the detail view,
            // the freshly-pushed Share carries `viewerRating = stars`.
            // Without this, ShareDetailViewModel.init reads the stale
            // server-side `nil` and the detail screen shows no rating.
            share = share.withViewerRating(stars)
        } catch {
            myRating = previous
            rateError = error.localizedDescription
        }
    }

    // MARK: - Reactions

    /// Toggle a reaction on/off. Optimistic patch via `withReactionSummary`,
    /// rollback on failure. Mirrors `ShareDetailViewModel.toggleReaction` so
    /// the feed card and detail screen stay in sync without sharing state.
    func toggleReaction(_ reaction: ShareReaction) async {
        let slug = reaction.rawValue
        guard !reactingSlugs.contains(slug) else { return }
        reactingSlugs.insert(slug)
        defer { reactingSlugs.remove(slug) }

        let previousCounts = share.reactionCounts
        let previousViewer = share.viewerReactions

        var nextCounts = previousCounts
        var nextViewer = previousViewer
        if previousViewer.contains(slug) {
            nextViewer.removeAll { $0 == slug }
            nextCounts[slug] = max(0, (nextCounts[slug] ?? 0) - 1)
            if nextCounts[slug] == 0 { nextCounts.removeValue(forKey: slug) }
        } else {
            nextViewer.append(slug)
            nextCounts[slug] = (nextCounts[slug] ?? 0) + 1
        }
        share = share.withReactionSummary(counts: nextCounts, viewerReactions: nextViewer)

        do {
            let resp = try await xomifyService.toggleReaction(
                email: viewerEmail,
                shareId: share.shareId,
                reaction: reaction
            )
            share = share.withReactionSummary(
                counts: resp.counts,
                viewerReactions: resp.viewerReactions
            )
        } catch {
            share = share.withReactionSummary(
                counts: previousCounts,
                viewerReactions: previousViewer
            )
            reactError = error.localizedDescription
        }
    }
}
