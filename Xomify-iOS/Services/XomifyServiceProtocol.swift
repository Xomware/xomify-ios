import Foundation

/// Narrow protocol facade over `XomifyService` for the surfaces the Feed
/// feature needs to mock in tests. Kept deliberately small — grow it as other
/// VMs migrate to constructor-injected services.
///
/// `XomifyService` (the concrete actor singleton) conforms via the extension
/// at the bottom of this file.
protocol XomifyServiceProtocol: Sendable {

    // MARK: - Shares

    func createShare(
        email: String,
        trackId: String,
        trackUri: String,
        trackName: String,
        artistName: String,
        albumName: String?,
        albumArtUrl: String?,
        caption: String?,
        moodTag: MoodTag?,
        genreTags: [String]?
    ) async throws -> ShareCreateResponse

    func getFeed(
        email: String,
        groupId: String?,
        limit: Int,
        before: String?
    ) async throws -> FeedResponse

    func getSharesByUser(
        email: String,
        targetEmail: String,
        limit: Int,
        before: String?
    ) async throws -> FeedResponse

    func deleteShare(
        email: String,
        shareId: String,
        sharedAt: String
    ) async throws -> SuccessResponse

    // MARK: - Friend profile (used by UserProfileViewModel)

    func getFriendProfile(
        email: String,
        profileEmail: String
    ) async throws -> FriendProfile

    // MARK: - Groups (for filter chips)

    func listGroups(email: String) async throws -> GroupsListResponse

    // MARK: - Ratings (used by ShareCardViewModel)

    func publishRating(
        email: String,
        trackId: String,
        trackName: String,
        artistName: String,
        rating: Int,
        review: String?
    ) async throws -> SuccessResponse

    // MARK: - Self-profile counts

    /// All ratings authored by the caller. Used by the self-profile header to
    /// populate the Ratings stat without a dedicated counts endpoint.
    func getAllRatings(email: String) async throws -> RatingsAllResponse

    /// Full friends payload for the caller. Used by the self-profile header
    /// (friend count) and the Friends drawer.
    func getAllFriends(email: String) async throws -> FriendsAllResponse
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
