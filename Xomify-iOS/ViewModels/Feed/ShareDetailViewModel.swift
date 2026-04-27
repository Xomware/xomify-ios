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

    // Comments thread (xomify-backend#139). Newest-first; loaded lazily on
    // detail open and after the viewer posts a new comment.
    var comments: [ShareComment] = []
    var nextCommentBefore: String?
    var isLoadingComments: Bool = false
    var commentsError: String?

    /// Composer state for the inline reply box.
    var commentDraft: String = ""
    var isPostingComment: Bool = false
    var postCommentError: String?

    /// IDs currently being deleted, so the per-row destructive button can
    /// disable individually instead of blocking the whole thread.
    var deletingCommentIds: Set<String> = []

    // Reactions (xomify-backend#139). Slugs in flight so a fast double-tap
    // doesn't fire two competing toggles for the same emoji.
    var reactingSlugs: Set<String> = []
    var reactError: String?

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

    /// Average of all friend ratings (0–5). nil when no friend has rated yet
    /// so callers can pick their own empty-state copy.
    var averageFriendRating: Double? {
        let values = friendRatings.map(\.rating)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
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
                trackId: share.trackId,
                trackName: share.trackName,
                artistName: share.artistName,
                albumArt: share.albumArtUrl,
                rating: stars,
                review: nil
            )
            // Patch local share so a subsequent `load()` won't override the
            // viewer rating with a stale server value.
            share = share.withViewerRating(stars)
        } catch {
            myRating = previous
            rateError = error.localizedDescription
        }
    }

    // MARK: - Comments

    /// Load (or reload) the comment thread. First page only — pagination
    /// support is wired but not exposed in the UI yet.
    func loadComments() async {
        guard !isLoadingComments else { return }
        isLoadingComments = true
        commentsError = nil
        defer { isLoadingComments = false }

        do {
            let resp = try await xomifyService.listComments(
                shareId: share.shareId,
                limit: 50,
                before: nil
            )
            comments = resp.comments
            nextCommentBefore = resp.nextBefore
            // Keep the cached commentCount in sync with what the thread shows
            // — useful when the value on the parent feed is stale.
            share = share.withCommentCount(comments.count)
        } catch {
            commentsError = error.localizedDescription
        }
    }

    /// Post the current draft. On success: clears the draft, prepends the
    /// newly-returned (hydrated) comment, and bumps the cached count.
    func postComment() async {
        let trimmed = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPostingComment else { return }
        isPostingComment = true
        postCommentError = nil
        defer { isPostingComment = false }

        do {
            let comment = try await xomifyService.createComment(
                shareId: share.shareId,
                body: trimmed
            )
            comments.insert(comment, at: 0)
            share = share.withCommentCount(share.commentCount + 1)
            commentDraft = ""
        } catch {
            postCommentError = error.localizedDescription
        }
    }

    /// Whether the viewer is allowed to delete `comment` — author of the
    /// comment, or author of the share.
    func canDelete(_ comment: ShareComment) -> Bool {
        comment.email == viewerEmail || share.sharedBy == viewerEmail
    }

    /// Optimistically remove the comment from the local list; rollback on
    /// failure. Backend re-checks the delete authorization rule.
    func deleteComment(_ comment: ShareComment) async {
        guard canDelete(comment), !deletingCommentIds.contains(comment.commentId) else { return }
        deletingCommentIds.insert(comment.commentId)
        defer { deletingCommentIds.remove(comment.commentId) }

        guard let removeIndex = comments.firstIndex(where: { $0.commentId == comment.commentId }) else { return }
        let removed = comments.remove(at: removeIndex)
        share = share.withCommentCount(max(0, share.commentCount - 1))

        do {
            _ = try await xomifyService.deleteComment(
                shareId: share.shareId,
                commentId: comment.commentId
            )
        } catch {
            comments.insert(removed, at: removeIndex)
            share = share.withCommentCount(share.commentCount + 1)
            commentsError = error.localizedDescription
        }
    }

    // MARK: - Reactions

    /// Has the viewer toggled this reaction on?
    func viewerHasReacted(_ reaction: ShareReaction) -> Bool {
        share.viewerReactions.contains(reaction.rawValue)
    }

    /// Count for a given reaction slug (0 when missing).
    func count(for reaction: ShareReaction) -> Int {
        share.reactionCounts[reaction.rawValue] ?? 0
    }

    /// Toggle a reaction on/off. Optimistic patch via `withReactionSummary`,
    /// rollback on failure.
    func toggleReaction(_ reaction: ShareReaction) async {
        let slug = reaction.rawValue
        guard !reactingSlugs.contains(slug) else { return }
        reactingSlugs.insert(slug)
        defer { reactingSlugs.remove(slug) }

        let previousCounts = share.reactionCounts
        let previousViewer = share.viewerReactions

        // Optimistic patch
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
                shareId: share.shareId,
                reaction: reaction
            )
            // Trust server — it just walked DynamoDB for the canonical counts.
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
