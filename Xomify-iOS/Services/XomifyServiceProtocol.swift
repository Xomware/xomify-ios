import Foundation

/// Narrow protocol facade over `XomifyService` for the surfaces the Feed
/// feature needs to mock in tests. Kept deliberately small — grow it as other
/// VMs migrate to constructor-injected services.
///
/// `XomifyService` (the concrete actor singleton) conforms via the extension
/// at the bottom of this file.
///
/// Caller identity rides the per-user JWT (sub-feature 0d) and is resolved
/// server-side (1a–1i). Methods here only carry target identifiers.
protocol XomifyServiceProtocol: Sendable {

    // MARK: - Shares

    func createShare(
        trackId: String,
        trackUri: String,
        trackName: String,
        artistName: String,
        albumName: String?,
        albumArtUrl: String?,
        caption: String?,
        moodTag: MoodTag?,
        genreTags: [String]?,
        groupIds: [String]?,
        isPublic: Bool?,
        rating: Int?
    ) async throws -> ShareCreateResponse

    func getFeed(
        groupId: String?,
        limit: Int,
        before: String?
    ) async throws -> FeedResponse

    func getSharesByUser(
        targetEmail: String,
        limit: Int,
        before: String?
    ) async throws -> FeedResponse

    func deleteShare(
        shareId: String,
        sharedAt: String
    ) async throws -> SuccessResponse

    func getShareDetail(
        shareId: String,
        sharedBy: String?,
        sharedAt: String?
    ) async throws -> ShareDetailResponse

    // MARK: - Friend profile (used by UserProfileViewModel)

    func getFriendProfile(
        profileEmail: String
    ) async throws -> FriendProfile

    // MARK: - Groups (for filter chips)

    func listGroups() async throws -> GroupsListResponse

    // MARK: - Ratings (used by ShareCardViewModel)

    func publishRating(
        trackId: String,
        trackName: String,
        artistName: String,
        albumArt: String?,
        rating: Int,
        review: String?
    ) async throws -> SuccessResponse

    // MARK: - Self-profile counts

    /// All ratings authored by the caller. Used by the self-profile header to
    /// populate the Ratings stat without a dedicated counts endpoint.
    func getAllRatings() async throws -> RatingsAllResponse

    /// Full friends payload for the caller. Used by the self-profile header
    /// (friend count) and the Friends drawer.
    func getAllFriends() async throws -> FriendsAllResponse

    // MARK: - Comments + Reactions (xomify-backend#139)

    func createComment(
        shareId: String,
        body: String
    ) async throws -> ShareComment

    func listComments(
        shareId: String,
        limit: Int,
        before: String?
    ) async throws -> CommentsListResponse

    func deleteComment(
        shareId: String,
        commentId: String
    ) async throws -> CommentDeleteResponse

    func toggleReaction(
        shareId: String,
        reaction: ShareReaction
    ) async throws -> ReactionToggleResponse

    func listReactions(
        shareId: String
    ) async throws -> ReactionsListResponse

    // MARK: - Likes

    @discardableResult
    func pushUserLikes(email: String, total: Int, tracks: [LikesPushTrack]) async throws -> LikesPushResponse

    func getLikesByUser(
        email: String,
        targetEmail: String,
        limit: Int,
        offset: Int
    ) async throws -> LikesByUserResponse

    @discardableResult
    func setLikesPublic(email: String, value: Bool) async throws -> SuccessResponse
}

extension XomifyService: XomifyServiceProtocol {}

// MARK: - SpotifyCurrentUserProviding

/// Subset of `SpotifyService` needed to resolve the signed-in user's email.
/// Exists so FeedViewModel tests can swap a fixture in without dragging in the
/// full `SpotifyService` API surface.
protocol SpotifyCurrentUserProviding: Sendable {
    func getCurrentUser() async throws -> SpotifyUser
}

extension SpotifyService: SpotifyCurrentUserProviding {}

// MARK: - SpotifyQueueing

/// Subset of `SpotifyService` needed to queue or start playback. Split from
/// the full service so player-only tests can mock a smaller surface.
protocol SpotifyQueueing: Sendable {
    func queueTrack(uri: String) async throws
    func playTrack(uri: String) async throws
}

extension SpotifyService: SpotifyQueueing {}
