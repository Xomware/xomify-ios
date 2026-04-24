import Foundation

/// Loads and exposes the full detail payload for a single share — listeners,
/// friend ratings, and the share row itself (re-fetched so counts/flags are
/// accurate at detail time, even if the feed's cached copy is stale).
///
/// Rating writes happen through `XomifyService.publishRating` (shared with
/// `ShareCardViewModel.rate`). The detail view then patches its local copy of
/// `share` so the "your rating" stat updates without a full refetch.
@Observable
@MainActor
final class ShareDetailViewModel {

    // MARK: - State

    /// Live copy of the share. Starts with the value pushed in from the feed
    /// so the hero renders immediately; replaced when `/shares/detail` resolves.
    var share: Share

    var interactions: [ShareInteractionEntry] = []
    var friendRatings: [ShareFriendRating] = []

    var isLoading: Bool = false
    var errorMessage: String?

    // Rating state (mirrors ShareCardViewModel for detail-screen rating)
    var myRating: Int?
    var isRating: Bool = false
    var rateError: String?

    // MARK: - Dependencies

    private let xomifyService: XomifyServiceProtocol
    let viewerEmail: String

    // MARK: - Init

    init(
        share: Share,
        viewerEmail: String,
        xomifyService: XomifyServiceProtocol = XomifyService.shared
    ) {
        self.share = share
        self.viewerEmail = viewerEmail
        self.xomifyService = xomifyService
        self.myRating = share.viewerRating
    }

    // MARK: - Load

    /// Fetch `/shares/detail`. Safe to call multiple times; no-ops while a
    /// load is in flight.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let resp = try await xomifyService.getShareDetail(
                email: viewerEmail,
                shareId: share.shareId,
                sharedBy: share.sharedBy,
                sharedAt: share.sharedAt
            )
            share = resp.share
            interactions = resp.interactions
            friendRatings = resp.friendRatings
            myRating = resp.share.viewerRating ?? myRating
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived

    /// Listeners = friends who queued (the prompt called these "listeners").
    var listeners: [ShareInteractionEntry] {
        interactions.filter { $0.action == "queued" }
    }

    /// Friend ratings sorted by rated-at desc when the timestamp is present —
    /// stable alphabetical fallback otherwise.
    var sortedFriendRatings: [ShareFriendRating] {
        friendRatings.sorted { lhs, rhs in
            switch (lhs.ratedAt, rhs.ratedAt) {
            case let (l?, r?): return l > r
            case (.some, nil):  return true
            case (nil, .some):  return false
            default:            return lhs.resolvedName < rhs.resolvedName
            }
        }
    }

    // MARK: - Rate

    /// Publish a rating. Optimistic update with rollback on failure. Mirrors
    /// `ShareCardViewModel.rate` so the detail screen is a first-class rating
    /// surface.
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
                rating: stars,
                review: nil
            )
        } catch {
            myRating = previous
            rateError = error.localizedDescription
        }
    }
}
