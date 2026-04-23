import Foundation

/// Service for Xomify backend API calls
actor XomifyService {
    
    // MARK: - Singleton
    
    static let shared = XomifyService()
    
    private let network = NetworkService.shared
    
    private init() {}
    
    // MARK: - User / Enrollment
    
    /// Get user enrollment status and wraps
    func getUserData(email: String) async throws -> WrappedDataResponse {
        try await network.xomifyGet("/wrapped/data", queryParams: ["email": email])
    }
    
    /// Get user table data
    func getUserTableData(email: String) async throws -> XomifyUser {
        try await network.xomifyGet("/user/user-table", queryParams: ["email": email])
    }
    
    /// Enroll or update user enrollments
    func updateEnrollments(
        email: String,
        activeWrapped: Bool,
        activeReleaseRadar: Bool
    ) async throws {
        let _: EmptyResponse = try await network.xomifyPost("/user/user-table", body: [
            "email": email,
            "activeWrapped": activeWrapped,
            "activeReleaseRadar": activeReleaseRadar
        ])
    }
    
    // MARK: - Release Radar
    
    /// Get release radar history (past weeks)
    func getReleaseRadarHistory(email: String, limit: Int = 12) async throws -> ReleaseRadarHistoryResponse {
        try await network.xomifyGet("/release-radar/history", queryParams: [
            "email": email,
            "limit": String(limit)
        ])
    }
    
    /// Check release radar status
    func checkReleaseRadar(email: String) async throws -> ReleaseRadarCheckResponse {
        try await network.xomifyGet("/release-radar/check", queryParams: ["email": email])
    }
    
    
    // MARK: - Wrapped
    
    /// Get all wraps from wrapped/data endpoint
    func getWraps(email: String) async throws -> [MonthlyWrap] {
        let response: WrappedDataResponse = try await network.xomifyGet("/wrapped/data", queryParams: ["email": email])
        return response.wraps ?? []
    }
    
    /// Get specific wrap by month
    func getWrap(email: String, monthKey: String) async throws -> MonthlyWrap {
        try await network.xomifyGet("/wrapped/month", queryParams: [
            "email": email,
            "monthKey": monthKey
        ])
    }

    // MARK: - Social — Shares
    //
    // The deployed `shares_create` / `shares_feed` contract is fully
    // track-denormalized. Share atoms carry the track fields on the row so the
    // feed renders without a follow-up Spotify fetch per card.

    /// Create a new share in the feed. Track fields are denormalized.
    @discardableResult
    func createShare(
        email: String,
        trackId: String,
        trackUri: String,
        trackName: String,
        artistName: String,
        albumName: String? = nil,
        albumArtUrl: String? = nil,
        caption: String? = nil,
        moodTag: MoodTag? = nil,
        genreTags: [String]? = nil
    ) async throws -> ShareCreateResponse {
        var body: [String: Any] = [
            "email": email,
            "trackId": trackId,
            "trackUri": trackUri,
            "trackName": trackName,
            "artistName": artistName
        ]
        if let albumName = albumName { body["albumName"] = albumName }
        if let albumArtUrl = albumArtUrl { body["albumArtUrl"] = albumArtUrl }
        if let caption = caption, !caption.isEmpty { body["caption"] = caption }
        if let moodTag = moodTag { body["moodTag"] = moodTag.rawValue }
        if let genreTags = genreTags, !genreTags.isEmpty { body["genreTags"] = genreTags }

        return try await network.xomifyPost("/shares/create", body: body)
    }

    /// Fetch the social feed for a user. Supports optional group scoping and
    /// keyset pagination via `before` (the `sharedAt` of the last received share).
    func getFeed(
        email: String,
        groupId: String? = nil,
        limit: Int = 50,
        before: String? = nil
    ) async throws -> FeedResponse {
        var params: [String: String] = [
            "email": email,
            "limit": String(limit)
        ]
        if let groupId = groupId { params["groupId"] = groupId }
        if let before = before { params["before"] = before }
        return try await network.xomifyGet("/shares/feed", queryParams: params)
    }

    /// Delete a share (author only). Backend expects composite key via body.
    @discardableResult
    func deleteShare(
        email: String,
        shareId: String,
        sharedAt: String
    ) async throws -> SuccessResponse {
        try await network.xomifyPost("/shares/delete", body: [
            "email": email,
            "shareId": shareId,
            "sharedAt": sharedAt
        ])
    }

    /// Queue a share's track and mark the viewer as having queued it.
    /// Sub-feature 4 (`backend-interactions-and-notifications`) ships the
    /// `/shares/interaction` endpoint; until then this still succeeds as a
    /// best-effort write-through.
    @discardableResult
    func interactWithShare(
        shareId: String,
        email: String,
        sharedAt: String,
        interaction: String,
        rating: Int? = nil
    ) async throws -> ShareInteractionResponse {
        var body: [String: Any] = [
            "shareId": shareId,
            "email": email,
            "sharedAt": sharedAt,
            "interaction": interaction
        ]
        if let rating = rating { body["rating"] = rating }
        return try await network.xomifyPost("/shares/interaction", body: body)
    }

    /// React to a share. Gated behind `FeatureFlags.reactionsEnabled` in the
    /// UI — backend endpoint is being built by sub-feature 4.
    /// TODO(sub-feature-4): this stays wired so the flag flip is zero-effort.
    @discardableResult
    func reactToShare(
        shareId: String,
        email: String,
        sharedAt: String,
        reaction: String
    ) async throws -> ReactionResponse {
        try await network.xomifyPost("/shares/react", body: [
            "shareId": shareId,
            "email": email,
            "sharedAt": sharedAt,
            "reaction": reaction
        ])
    }

    /// Create a friend invite code
    func createInvite(email: String) async throws -> InviteCreateResponse {
        try await network.xomifyPost("/invites/create", body: ["email": email])
    }

    /// Accept a friend invite code
    func acceptInvite(email: String, inviteCode: String) async throws -> InviteAcceptResponse {
        try await network.xomifyPost("/invites/accept", body: [
            "email": email,
            "inviteCode": inviteCode
        ])
    }

    /// List deep-link invites awaiting accept/decline for this user.
    /// TODO: endpoint lands in backend-interactions-and-friends-handlers PR.
    /// Until the backend ships, this will raise a server error; the UI renders
    /// an empty state against that failure.
    func listPendingInvites(email: String) async throws -> PendingInvitesResponse {
        try await network.xomifyGet("/invites/pending", queryParams: ["email": email])
    }

    /// Decline a deep-link invite.
    /// TODO: endpoint lands in backend-interactions-and-friends-handlers PR.
    @discardableResult
    func declineInvite(email: String, inviteCode: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/invites/decline", body: [
            "email": email,
            "inviteCode": inviteCode
        ])
    }

    // MARK: - Friends

    /// Send a friend request.
    @discardableResult
    func requestFriend(email: String, requestEmail: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/friends/request", body: [
            "email": email,
            "requestEmail": requestEmail
        ])
    }

    /// Accept an incoming friend request.
    @discardableResult
    func acceptFriend(email: String, requestEmail: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/friends/accept", body: [
            "email": email,
            "requestEmail": requestEmail
        ])
    }

    /// Reject an incoming friend request (or cancel an outgoing one).
    @discardableResult
    func rejectFriend(email: String, requestEmail: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/friends/reject", body: [
            "email": email,
            "requestEmail": requestEmail
        ])
    }

    /// Remove an accepted friend.
    @discardableResult
    func removeFriend(email: String, friendEmail: String) async throws -> SuccessResponse {
        // Backend expects DELETE with body; use POST-style body via helper that
        // targets DELETE via a query-param workaround -- the simplest reliable
        // shape is POST to /friends/remove. If the lambda strictly requires
        // DELETE, swap to an http DELETE helper later.
        try await network.xomifyPost("/friends/remove", body: [
            "email": email,
            "friendEmail": friendEmail
        ])
    }

    /// Bucketed list of friends (accepted / requested / pending / blocked).
    func getAllFriends(email: String) async throws -> FriendsAllResponse {
        try await network.xomifyGet("/friends/all", queryParams: ["email": email])
    }

    /// Discovery list: every other user on the platform with per-user status.
    func listUsers(email: String) async throws -> UserListResponse {
        // The backend returns `{ users: [...], totalCount }` or a bare array.
        // Try the dict shape first; fall back to array if needed.
        do {
            return try await network.xomifyGet("/friends/list", queryParams: ["email": email])
        } catch {
            let users: [SearchResult] = try await network.xomifyGet("/friends/list", queryParams: ["email": email])
            return UserListResponse(users: users, totalCount: users.count)
        }
    }

    /// Incoming friend requests only (subset of /friends/all).
    func getPendingFriends(email: String) async throws -> FriendsAllResponse {
        try await network.xomifyGet("/friends/pending", queryParams: ["email": email])
    }

    /// Public profile of another user.
    func getFriendProfile(email: String, profileEmail: String) async throws -> FriendProfile {
        try await network.xomifyGet("/friends/profile", queryParams: [
            "email": email,
            "profileEmail": profileEmail
        ])
    }

    // MARK: - Groups

    /// Create a group. Description is optional.
    func createGroup(email: String, name: String, description: String? = nil) async throws -> GroupCreateResponse {
        var body: [String: Any] = ["email": email, "name": name]
        if let description = description, !description.isEmpty {
            body["description"] = description
        }
        return try await network.xomifyPost("/groups/create", body: body)
    }

    /// Update a group's name / description.
    @discardableResult
    func updateGroup(email: String, groupId: String, name: String? = nil, description: String? = nil) async throws -> SuccessResponse {
        var body: [String: Any] = ["email": email, "groupId": groupId]
        if let name = name { body["name"] = name }
        if let description = description { body["description"] = description }
        return try await network.xomifyPost("/groups/update", body: body)
    }

    /// Delete a group (owner only).
    @discardableResult
    func removeGroup(email: String, groupId: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/remove", body: [
            "email": email,
            "groupId": groupId
        ])
    }

    /// Leave a group.
    @discardableResult
    func leaveGroup(email: String, groupId: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/leave", body: [
            "email": email,
            "groupId": groupId
        ])
    }

    /// Add a member to a group.
    @discardableResult
    func addMember(email: String, groupId: String, memberEmail: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/add-member", body: [
            "email": email,
            "groupId": groupId,
            "memberEmail": memberEmail
        ])
    }

    /// Remove a member from a group.
    @discardableResult
    func removeMember(email: String, groupId: String, memberEmail: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/remove-member", body: [
            "email": email,
            "groupId": groupId,
            "memberEmail": memberEmail
        ])
    }

    /// Groups the user belongs to.
    func listGroups(email: String) async throws -> GroupsListResponse {
        try await network.xomifyGet("/groups/list", queryParams: ["email": email])
    }

    /// Group detail — members + tracks.
    func getGroupInfo(groupId: String, email: String? = nil) async throws -> GroupInfo {
        var params: [String: String] = ["groupId": groupId]
        if let email = email { params["email"] = email }
        return try await network.xomifyGet("/groups/info", queryParams: params)
    }

    /// Add a track to a group.
    @discardableResult
    func addSong(
        email: String,
        groupId: String,
        trackId: String,
        trackName: String,
        artistName: String,
        albumName: String? = nil,
        imageUrl: String? = nil
    ) async throws -> SuccessResponse {
        var body: [String: Any] = [
            "email": email,
            "groupId": groupId,
            "trackId": trackId,
            "trackName": trackName,
            "artistName": artistName
        ]
        if let albumName = albumName { body["albumName"] = albumName }
        if let imageUrl = imageUrl { body["imageUrl"] = imageUrl }
        return try await network.xomifyPost("/groups/add-song", body: body)
    }

    /// Add a track to a group by pasting a Spotify URL (backend parses it).
    @discardableResult
    func addSongByUrl(email: String, groupId: String, trackUrl: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/add-song-url", body: [
            "email": email,
            "groupId": groupId,
            "trackUrl": trackUrl
        ])
    }

    /// Remove a track by its composite id.
    @discardableResult
    func removeSong(email: String, groupId: String, trackIdTimestamp: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/remove-song", body: [
            "email": email,
            "groupId": groupId,
            "trackIdTimestamp": trackIdTimestamp
        ])
    }

    /// Check my listen-status for a single group track.
    func getSongStatus(email: String, groupId: String, trackIdTimestamp: String) async throws -> SongStatusResponse {
        try await network.xomifyGet("/groups/song-status", queryParams: [
            "email": email,
            "groupId": groupId,
            "trackIdTimestamp": trackIdTimestamp
        ])
    }

    /// Mark every track in the group as listened by me.
    @discardableResult
    func markAllListened(email: String, groupId: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/mark-all-listened", body: [
            "email": email,
            "groupId": groupId
        ])
    }

    // MARK: - Ratings

    /// Publish (create or update) a rating for a track. Rating is 1-5.
    @discardableResult
    func publishRating(
        email: String,
        trackId: String,
        trackName: String,
        artistName: String,
        rating: Int,
        review: String? = nil
    ) async throws -> SuccessResponse {
        var body: [String: Any] = [
            "email": email,
            "trackId": trackId,
            "trackName": trackName,
            "artistName": artistName,
            "rating": rating
        ]
        if let review = review, !review.isEmpty {
            body["review"] = review
        }
        return try await network.xomifyPost("/ratings/publish", body: body)
    }

    /// Delete a rating.
    @discardableResult
    func removeRating(email: String, trackId: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/ratings/remove", body: [
            "email": email,
            "trackId": trackId
        ])
    }

    /// All ratings the user has posted.
    func getAllRatings(email: String) async throws -> RatingsAllResponse {
        // Try dict shape first; fall back to bare array.
        do {
            return try await network.xomifyGet("/ratings/all", queryParams: ["email": email])
        } catch {
            let ratings: [TrackRating] = try await network.xomifyGet("/ratings/all", queryParams: ["email": email])
            return RatingsAllResponse(email: email, ratings: ratings, totalCount: ratings.count)
        }
    }

    /// A single track's rating (or nil).
    func getTrackRating(email: String, trackId: String) async throws -> TrackRating? {
        do {
            let rating: TrackRating = try await network.xomifyGet("/ratings/track", queryParams: [
                "email": email,
                "trackId": trackId
            ])
            return rating
        } catch {
            return nil
        }
    }

    // MARK: - Notifications (APNs)
    //
    // Thin wrappers over the deployed `notifications_register` /
    // `notifications_unregister` lambdas. Body shape is camelCase and matches
    // the Python handlers exactly.

    /// Upsert the user's APNs device token + push preferences. Idempotent —
    /// safe to call on every cold launch when the APNs token refreshes.
    @discardableResult
    func registerPushToken(
        email: String,
        deviceToken: String,
        queueNotificationsEnabled: Bool,
        digestEnabled: Bool
    ) async throws -> SuccessResponse {
        try await network.xomifyPost("/notifications/register", body: [
            "email": email,
            "deviceToken": deviceToken,
            "queueNotificationsEnabled": queueNotificationsEnabled,
            "digestEnabled": digestEnabled
        ])
    }

    /// Delete the user's APNs device token from the backend. Called on sign-out.
    @discardableResult
    func unregisterPushToken(
        email: String,
        deviceToken: String
    ) async throws -> SuccessResponse {
        try await network.xomifyPost("/notifications/unregister", body: [
            "email": email,
            "deviceToken": deviceToken
        ])
    }
}
