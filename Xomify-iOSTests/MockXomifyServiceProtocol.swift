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
        friendsCount: nil, shareCount: nil,
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
        rating: Int, review: String?
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
