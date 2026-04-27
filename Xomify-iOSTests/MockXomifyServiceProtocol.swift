import Foundation
@testable import Xomify_iOS

/// Mock for `XomifyServiceProtocol` — covers the surface used by Feed / profile
/// view models. Each method stubs a success response by default; individual
/// methods can be primed to throw or return a specific payload.
final class MockXomifyServiceProtocol: XomifyServiceProtocol, @unchecked Sendable {

    // MARK: - getSharesByUser

    struct GetSharesByUserCall: Equatable {
        let email: String
        let targetEmail: String
        let limit: Int
        let before: String?
    }

    private(set) var getSharesByUserCalls: [GetSharesByUserCall] = []
    var getSharesByUserResponses: [FeedResponse] = []
    var getSharesByUserError: Error?

    func getSharesByUser(
        email: String,
        targetEmail: String,
        limit: Int,
        before: String?
    ) async throws -> FeedResponse {
        getSharesByUserCalls.append(GetSharesByUserCall(
            email: email, targetEmail: targetEmail, limit: limit, before: before
        ))
        if let getSharesByUserError { throw getSharesByUserError }
        if getSharesByUserResponses.isEmpty {
            return FeedResponse(shares: [], nextBefore: nil)
        }
        return getSharesByUserResponses.removeFirst()
    }

    // MARK: - getFriendProfile

    struct GetFriendProfileCall: Equatable {
        let email: String
        let profileEmail: String
    }

    private(set) var getFriendProfileCalls: [GetFriendProfileCall] = []
    var getFriendProfileResponse: FriendProfile = FriendProfile(
        email: nil, displayName: nil, userId: nil, avatar: nil,
        followersCount: nil, followingCount: nil, playlistCount: nil,
        friendsCount: nil, shareCount: nil, likesCount: nil, likesUpdatedAt: nil,
        topSongs: nil, topArtists: nil, topGenres: nil, playlists: nil
    )
    var getFriendProfileError: Error?

    func getFriendProfile(email: String, profileEmail: String) async throws -> FriendProfile {
        getFriendProfileCalls.append(GetFriendProfileCall(email: email, profileEmail: profileEmail))
        if let getFriendProfileError { throw getFriendProfileError }
        return getFriendProfileResponse
    }

    // MARK: - Unused surface — return empty success shapes so the protocol compiles.

    func createShare(
        email: String, trackId: String, trackUri: String, trackName: String,
        artistName: String, albumName: String?, albumArtUrl: String?,
        caption: String?, moodTag: MoodTag?, genreTags: [String]?,
        groupIds: [String]?, isPublic: Bool?
    ) async throws -> ShareCreateResponse {
        throw NSError(domain: "mock", code: -1)
    }

    func getFeed(
        email: String, groupId: String?, limit: Int, before: String?
    ) async throws -> FeedResponse {
        FeedResponse(shares: [], nextBefore: nil)
    }

    func deleteShare(
        email: String, shareId: String, sharedAt: String
    ) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }

    // MARK: - getShareDetail

    struct GetShareDetailCall: Equatable {
        let email: String
        let shareId: String
        let sharedBy: String?
        let sharedAt: String?
    }

    private(set) var getShareDetailCalls: [GetShareDetailCall] = []
    var getShareDetailResponses: [ShareDetailResponse] = []
    var getShareDetailError: Error?

    func getShareDetail(
        email: String, shareId: String, sharedBy: String?, sharedAt: String?
    ) async throws -> ShareDetailResponse {
        getShareDetailCalls.append(GetShareDetailCall(
            email: email, shareId: shareId, sharedBy: sharedBy, sharedAt: sharedAt
        ))
        if let getShareDetailError { throw getShareDetailError }
        if getShareDetailResponses.isEmpty {
            throw NSError(domain: "mock", code: -1, userInfo: [NSLocalizedDescriptionKey: "no response primed"])
        }
        return getShareDetailResponses.removeFirst()
    }

    func listGroups(email: String) async throws -> GroupsListResponse {
        GroupsListResponse(email: email, groups: [], totalCount: 0)
    }

    func publishRating(
        email: String, trackId: String, trackName: String, artistName: String,
        albumArt: String?, rating: Int, review: String?
    ) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }

    func getAllRatings(email: String) async throws -> RatingsAllResponse {
        RatingsAllResponse(email: email, ratings: [], totalCount: 0)
    }

    func getAllFriends(email: String) async throws -> FriendsAllResponse {
        FriendsAllResponse(
            email: email,
            accepted: [], requested: [], pending: [], blocked: [],
            acceptedCount: 0, requestedCount: 0, pendingCount: 0, blockedCount: 0,
            totalCount: 0
        )
    }

    // MARK: - Comments + Reactions (xomify-backend#139)
    //
    // Stub default returns; specific tests can prime the response/error.

    var createCommentResponse: ShareComment?
    var createCommentError: Error?

    func createComment(
        email: String,
        shareId: String,
        body: String
    ) async throws -> ShareComment {
        if let createCommentError { throw createCommentError }
        return createCommentResponse ?? ShareComment(
            commentId: UUID().uuidString,
            shareId: shareId,
            email: email,
            displayName: nil,
            avatar: nil,
            body: body,
            createdAt: nil
        )
    }

    var listCommentsResponse: CommentsListResponse = CommentsListResponse(
        comments: [], nextBefore: nil
    )
    var listCommentsError: Error?

    func listComments(
        email: String,
        shareId: String,
        limit: Int,
        before: String?
    ) async throws -> CommentsListResponse {
        if let listCommentsError { throw listCommentsError }
        return listCommentsResponse
    }

    var deleteCommentError: Error?

    func deleteComment(
        email: String,
        shareId: String,
        commentId: String
    ) async throws -> CommentDeleteResponse {
        if let deleteCommentError { throw deleteCommentError }
        return CommentDeleteResponse(deleted: true, commentId: commentId)
    }

    var toggleReactionResponse: ReactionToggleResponse?
    var toggleReactionError: Error?

    func toggleReaction(
        email: String,
        shareId: String,
        reaction: ShareReaction
    ) async throws -> ReactionToggleResponse {
        if let toggleReactionError { throw toggleReactionError }
        return toggleReactionResponse ?? ReactionToggleResponse(
            active: true,
            reaction: reaction.rawValue,
            counts: [reaction.rawValue: 1],
            viewerReactions: [reaction.rawValue]
        )
    }

    var listReactionsResponse: ReactionsListResponse = ReactionsListResponse(
        counts: [:], viewerReactions: []
    )
    var listReactionsError: Error?

    func listReactions(
        email: String,
        shareId: String
    ) async throws -> ReactionsListResponse {
        if let listReactionsError { throw listReactionsError }
        return listReactionsResponse
    }

    // MARK: - Likes

    struct PushUserLikesCall: Equatable {
        let email: String
        let total: Int
        let trackCount: Int
    }

    private(set) var pushUserLikesCalls: [PushUserLikesCall] = []
    var pushUserLikesError: Error?

    func pushUserLikes(email: String, total: Int, tracks: [LikesPushTrack]) async throws -> LikesPushResponse {
        pushUserLikesCalls.append(PushUserLikesCall(email: email, total: total, trackCount: tracks.count))
        if let pushUserLikesError { throw pushUserLikesError }
        return LikesPushResponse(success: true, deduped: false, count: tracks.count)
    }

    struct GetLikesByUserCall: Equatable {
        let email: String
        let targetEmail: String
        let limit: Int
        let offset: Int
    }

    private(set) var getLikesByUserCalls: [GetLikesByUserCall] = []
    var getLikesByUserResponse: LikesByUserResponse = LikesByUserResponse(tracks: [], total: 0, hasMore: false, likesPublic: true)
    var getLikesByUserError: Error?

    func getLikesByUser(
        email: String,
        targetEmail: String,
        limit: Int,
        offset: Int
    ) async throws -> LikesByUserResponse {
        getLikesByUserCalls.append(GetLikesByUserCall(email: email, targetEmail: targetEmail, limit: limit, offset: offset))
        if let getLikesByUserError { throw getLikesByUserError }
        return getLikesByUserResponse
    }

    struct SetLikesPublicCall: Equatable {
        let email: String
        let value: Bool
    }

    private(set) var setLikesPublicCalls: [SetLikesPublicCall] = []
    var setLikesPublicError: Error?

    func setLikesPublic(email: String, value: Bool) async throws -> SuccessResponse {
        setLikesPublicCalls.append(SetLikesPublicCall(email: email, value: value))
        if let setLikesPublicError { throw setLikesPublicError }
        return SuccessResponse(success: true)
    }
}

// MARK: - SpotifyCurrentUserProviding mock

/// Mock for `SpotifyCurrentUserProviding` — returns a canned `SpotifyUser`
/// unless `error` is set. Records call count so tests can assert the caller
/// email is resolved exactly once.
final class MockSpotifyCurrentUserProviding: SpotifyCurrentUserProviding, @unchecked Sendable {
    private(set) var callCount: Int = 0
    var response: SpotifyUser = SpotifyUser(
        id: "mock-id",
        displayName: "Mock User",
        email: "me@example.com",
        images: nil,
        followers: nil,
        country: nil,
        product: nil,
        externalUrls: nil
    )
    var error: Error?

    func getCurrentUser() async throws -> SpotifyUser {
        callCount += 1
        if let error { throw error }
        return response
    }
}
