import Foundation

/// Service for Xomify backend API calls
///
/// Caller identity is sourced from the per-user JWT in the Authorization
/// header (sub-feature 0d). Backend handlers extract `email` + `userId` from
/// the API Gateway authorizer context (sub-features 1a–1i). Methods here
/// therefore no longer take or transmit the caller's email — only target
/// identifiers (`friendEmail`, `requestEmail`, `targetEmail`,
/// `memberEmail`, `groupId`, `shareId`, `inviteCode`, `trackId`, etc.) ride
/// the wire.
actor XomifyService {

    // MARK: - Singleton

    static let shared = XomifyService()

    private let network = NetworkService.shared

    private init() {}

    // MARK: - User / Enrollment

    /// Get user enrollment status and wraps
    func getUserData() async throws -> WrappedDataResponse {
        try await network.xomifyGet("/wrapped/all")
    }

    /// Get user table data
    func getUserTableData() async throws -> XomifyUser {
        try await network.xomifyGet("/user/data")
    }

    /// Enroll or update user enrollments
    func updateEnrollments(
        activeWrapped: Bool,
        activeReleaseRadar: Bool
    ) async throws {
        let _: EmptyResponse = try await network.xomifyPost("/user/update", body: [
            "wrappedEnrolled": activeWrapped,
            "releaseRadarEnrolled": activeReleaseRadar
        ])
    }

    // MARK: - Release Radar

    /// Get release radar history (past weeks)
    func getReleaseRadarHistory(limit: Int = 12) async throws -> ReleaseRadarHistoryResponse {
        try await network.xomifyGet("/release-radar/history", queryParams: [
            "limit": String(limit)
        ])
    }

    /// Check release radar status
    func checkReleaseRadar() async throws -> ReleaseRadarCheckResponse {
        try await network.xomifyGet("/release-radar/check")
    }


    // MARK: - Wrapped

    /// Get all wraps
    func getWraps() async throws -> [MonthlyWrap] {
        let response: WrappedDataResponse = try await network.xomifyGet("/wrapped/all")
        return response.wraps ?? []
    }

    /// Get specific wrap by month
    func getWrap(monthKey: String) async throws -> MonthlyWrap {
        try await network.xomifyGet("/wrapped/month", queryParams: [
            "monthKey": monthKey
        ])
    }

    // MARK: - Top Items (live, daily-cached)

    /// Live top tracks/artists/genres for the signed-in user, served from a
    /// per-user, per-UTC-day cache on the backend (epic Q7). Caller identity
    /// is resolved server-side from the per-user JWT in the `Authorization`
    /// header — no `email` query param. Replaces the per-range Spotify calls
    /// the iOS client used to make for the "Last 4 Weeks (Current)" /
    /// "Music Taste" surface (sub-feature 2c, auth-identity epic).
    ///
    /// On per-range partial failure the backend returns the ranges it could
    /// fetch and lists the failed range names in `meta.failedRanges`; the
    /// UI can render a soft retry hint without losing the data we did get.
    func getCurrentTopItems() async throws -> TopItemsResponse {
        try await network.xomifyGet("/user/top-items")
    }

    // MARK: - Social — Shares
    //
    // The deployed `shares_create` / `shares_feed` contract is fully
    // track-denormalized. Share atoms carry the track fields on the row so the
    // feed renders without a follow-up Spotify fetch per card.

    /// Create a new share in the feed. Track fields are denormalized.
    ///
    /// `groupIds` + `isPublic` drive multi-target routing (xomify-backend#138).
    /// Defaults preserve legacy behavior: public-only, no group targets.
    /// Backend rejects `public=false` with empty `groupIds`.
    @discardableResult
    func createShare(
        trackId: String,
        trackUri: String,
        trackName: String,
        artistName: String,
        albumName: String? = nil,
        albumArtUrl: String? = nil,
        caption: String? = nil,
        moodTag: MoodTag? = nil,
        genreTags: [String]? = nil,
        groupIds: [String]? = nil,
        isPublic: Bool? = nil,
        rating: Int? = nil
    ) async throws -> ShareCreateResponse {
        var body: [String: Any] = [
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
        if let groupIds = groupIds, !groupIds.isEmpty { body["groupIds"] = groupIds }
        if let isPublic = isPublic { body["public"] = isPublic }
        if let rating = rating, (1...5).contains(rating) { body["rating"] = rating }

        return try await network.xomifyPost("/shares/create", body: body)
    }

    /// Fetch the social feed for the caller. Supports optional group scoping and
    /// keyset pagination via `before` (the `sharedAt` of the last received share).
    func getFeed(
        groupId: String? = nil,
        limit: Int = 50,
        before: String? = nil
    ) async throws -> FeedResponse {
        var params: [String: String] = [
            "limit": String(limit)
        ]
        if let groupId = groupId { params["groupId"] = groupId }
        if let before = before { params["before"] = before }
        return try await network.xomifyGet("/shares/feed", queryParams: params)
    }

    /// Fetch shares authored by a specific user (`targetEmail`). Caller
    /// identity is read from the JWT context server-side.
    ///
    /// Response shape is identical to `/shares/feed` — reuse `FeedResponse`.
    /// `nextBefore` is the pagination cursor (ISO8601 `createdAt`).
    func getSharesByUser(
        targetEmail: String,
        limit: Int = 50,
        before: String? = nil
    ) async throws -> FeedResponse {
        var params: [String: String] = [
            "targetEmail": targetEmail,
            "limit": String(limit)
        ]
        if let before = before { params["before"] = before }
        return try await network.xomifyGet("/shares/user", queryParams: params)
    }

    /// Fetch full detail for one share — includes the share row plus the
    /// friend listener/rating activity needed to render listeners +
    /// per-friend ratings on `ShareDetailView`.
    ///
    /// Endpoint is query-param only; backend accepts `sharedBy` / `sharedAt`
    /// for forward-compat but ignores them today.
    func getShareDetail(
        shareId: String,
        sharedBy: String? = nil,
        sharedAt: String? = nil
    ) async throws -> ShareDetailResponse {
        var params: [String: String] = [
            "shareId": shareId
        ]
        if let sharedBy = sharedBy { params["sharedBy"] = sharedBy }
        if let sharedAt = sharedAt { params["sharedAt"] = sharedAt }
        return try await network.xomifyGet("/shares/detail", queryParams: params)
    }

    /// Delete a share (author only). Backend expects composite key via body.
    /// Route is wired as DELETE in api-gateway-service; using POST here
    /// triggers a 403 ForbiddenException from API GW (unmatched method).
    @discardableResult
    func deleteShare(
        shareId: String,
        sharedAt: String
    ) async throws -> SuccessResponse {
        try await network.xomifyDelete("/shares/delete", body: [
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
        sharedAt: String,
        interaction: String,
        rating: Int? = nil
    ) async throws -> ShareInteractionResponse {
        var body: [String: Any] = [
            "shareId": shareId,
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
        sharedAt: String,
        reaction: String
    ) async throws -> ReactionResponse {
        try await network.xomifyPost("/shares/react", body: [
            "shareId": shareId,
            "sharedAt": sharedAt,
            "reaction": reaction
        ])
    }

    /// Mark one or more shares as listened by the caller.
    ///
    /// Server cap is 25 ids per call; this client mirrors that and chunks
    /// larger batches sequentially so a future caller that hands in a longer
    /// list still gets the full write-through. The aggregate response merges
    /// the per-chunk `listened` / `skipped` arrays.
    ///
    /// Empty `shareIds` short-circuits — no network call, returns an empty
    /// success response. The viewer-level write path is fire-and-forget from
    /// callers (queue/play already succeeded), so this method intentionally
    /// surfaces errors via `throws` rather than swallowing them — let the
    /// caller decide whether to log or ignore.
    @discardableResult
    func markListened(
        shareIds: [String],
        source: ListenSource = .queue
    ) async throws -> MarkListenedResponse {
        guard !shareIds.isEmpty else {
            return MarkListenedResponse(ok: true, listened: [], skipped: [])
        }

        let chunkSize = 25
        var listened: [String] = []
        var skipped: [String] = []
        var ok = true

        for chunkStart in stride(from: 0, to: shareIds.count, by: chunkSize) {
            let chunk = Array(shareIds[chunkStart..<min(chunkStart + chunkSize, shareIds.count)])
            let body: [String: Any] = [
                "shareIds": chunk,
                "source": source.rawValue
            ]
            let response: MarkListenedResponse = try await network.xomifyPost(
                "/shares/listened",
                body: body
            )
            ok = ok && response.ok
            listened.append(contentsOf: response.listened)
            skipped.append(contentsOf: response.skipped)
        }

        return MarkListenedResponse(ok: ok, listened: listened, skipped: skipped)
    }

    /// Create a friend invite code
    func createInvite() async throws -> InviteCreateResponse {
        try await network.xomifyPost("/invites/create", body: [:])
    }

    /// Accept a friend invite code
    func acceptInvite(inviteCode: String) async throws -> InviteAcceptResponse {
        try await network.xomifyPost("/invites/accept", body: [
            "inviteCode": inviteCode
        ])
    }

    /// List deep-link invites awaiting accept/decline for this user.
    /// TODO: endpoint lands in backend-interactions-and-friends-handlers PR.
    /// Until the backend ships, this will raise a server error; the UI renders
    /// an empty state against that failure.
    func listPendingInvites() async throws -> PendingInvitesResponse {
        try await network.xomifyGet("/invites/pending")
    }

    /// Decline a deep-link invite.
    /// TODO: endpoint lands in backend-interactions-and-friends-handlers PR.
    @discardableResult
    func declineInvite(inviteCode: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/invites/decline", body: [
            "inviteCode": inviteCode
        ])
    }

    // MARK: - Friends

    /// Send a friend request to `requestEmail`.
    @discardableResult
    func requestFriend(requestEmail: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/friends/request", body: [
            "requestEmail": requestEmail
        ])
    }

    /// Accept an incoming friend request from `requestEmail`.
    @discardableResult
    func acceptFriend(requestEmail: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/friends/accept", body: [
            "requestEmail": requestEmail
        ])
    }

    /// Reject an incoming friend request (or cancel an outgoing one).
    @discardableResult
    func rejectFriend(requestEmail: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/friends/reject", body: [
            "requestEmail": requestEmail
        ])
    }

    /// Remove an accepted friend.
    @discardableResult
    func removeFriend(friendEmail: String) async throws -> SuccessResponse {
        // Backend expects DELETE with body; use POST-style body via helper that
        // targets DELETE via a query-param workaround -- the simplest reliable
        // shape is POST to /friends/remove. If the lambda strictly requires
        // DELETE, swap to an http DELETE helper later.
        try await network.xomifyPost("/friends/remove", body: [
            "friendEmail": friendEmail
        ])
    }

    /// Bucketed list of friends (accepted / requested / pending / blocked).
    /// Hits `/friends/list` — backend resolves the caller from JWT context.
    /// `/friends/all` is a full-table scan helper and must not be used here.
    func getAllFriends() async throws -> FriendsAllResponse {
        try await network.xomifyGet("/friends/list")
    }

    /// Discovery list: every other user on the platform. `/user/all` returns a
    /// bare JSON array; the backend filters self out server-side using the
    /// caller email from the JWT context.
    func listUsers() async throws -> UserListResponse {
        let users: [SearchResult] = try await network.xomifyGet("/user/all")
        return UserListResponse(users: users, totalCount: users.count)
    }

    /// Incoming friend requests only (subset of /friends/all).
    func getPendingFriends() async throws -> FriendsAllResponse {
        try await network.xomifyGet("/friends/pending")
    }

    /// Public profile of another user. Backend expects `friendEmail` and
    /// resolves the caller from the JWT context.
    func getFriendProfile(profileEmail: String) async throws -> FriendProfile {
        try await network.xomifyGet("/friends/profile", queryParams: [
            "friendEmail": profileEmail
        ])
    }

    // MARK: - Groups

    /// Create a group. Description is optional.
    func createGroup(name: String, description: String? = nil) async throws -> GroupCreateResponse {
        var body: [String: Any] = ["name": name]
        if let description = description, !description.isEmpty {
            body["description"] = description
        }
        return try await network.xomifyPost("/groups/create", body: body)
    }

    /// Update a group's name / description. Backend route is `PUT
    /// /groups/update` — sending POST here would be rejected by API Gateway
    /// before reaching the lambda.
    @discardableResult
    func updateGroup(groupId: String, name: String? = nil, description: String? = nil) async throws -> SuccessResponse {
        var body: [String: Any] = ["groupId": groupId]
        if let name = name { body["name"] = name }
        if let description = description { body["description"] = description }
        return try await network.xomifyPut("/groups/update", body: body)
    }

    /// Delete a group (owner only). Backend route is `DELETE
    /// /groups/remove` and reads identifiers from query params (not body).
    @discardableResult
    func removeGroup(groupId: String) async throws -> SuccessResponse {
        try await network.xomifyDelete("/groups/remove", queryParams: [
            "groupId": groupId
        ])
    }

    /// Leave a group.
    @discardableResult
    func leaveGroup(groupId: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/leave", body: [
            "groupId": groupId
        ])
    }

    /// Add a member to a group.
    @discardableResult
    func addMember(groupId: String, memberEmail: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/add-member", body: [
            "groupId": groupId,
            "memberEmail": memberEmail
        ])
    }

    /// Remove a member from a group. Backend is `DELETE
    /// /groups/remove-member` with query params.
    @discardableResult
    func removeMember(groupId: String, memberEmail: String) async throws -> SuccessResponse {
        try await network.xomifyDelete("/groups/remove-member", queryParams: [
            "groupId": groupId,
            "memberEmail": memberEmail
        ])
    }

    /// Groups the caller belongs to.
    func listGroups() async throws -> GroupsListResponse {
        try await network.xomifyGet("/groups/list")
    }

    /// Group detail — members + tracks.
    func getGroupInfo(groupId: String) async throws -> GroupInfo {
        try await network.xomifyGet("/groups/info", queryParams: ["groupId": groupId])
    }

    /// Add a track to a group.
    @discardableResult
    func addSong(
        groupId: String,
        trackId: String,
        trackName: String,
        artistName: String,
        albumName: String? = nil,
        imageUrl: String? = nil
    ) async throws -> SuccessResponse {
        var body: [String: Any] = [
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
    func addSongByUrl(groupId: String, trackUrl: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/add-song-url", body: [
            "groupId": groupId,
            "trackUrl": trackUrl
        ])
    }

    /// Remove a track by its composite id. Backend is `DELETE
    /// /groups/remove-song` and reads `songId` (not `trackIdTimestamp`)
    /// from query params.
    @discardableResult
    func removeSong(groupId: String, trackIdTimestamp: String) async throws -> SuccessResponse {
        try await network.xomifyDelete("/groups/remove-song", queryParams: [
            "groupId": groupId,
            "songId": trackIdTimestamp
        ])
    }

    /// Check the caller's listen-status for a single group track.
    func getSongStatus(groupId: String, trackIdTimestamp: String) async throws -> SongStatusResponse {
        try await network.xomifyGet("/groups/song-status", queryParams: [
            "groupId": groupId,
            "trackIdTimestamp": trackIdTimestamp
        ])
    }

    /// Mark every track in the group as listened by the caller.
    @discardableResult
    func markAllListened(groupId: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/groups/mark-all-listened", body: [
            "groupId": groupId
        ])
    }

    // MARK: - Social — Comments (xomify-backend#139)
    //
    // The deployed paths are verb-disambiguated (`/shares/comments-create`
    // etc.) because the `api-gateway-service` Terraform module keys API GW
    // resources by `path_part` and doesn't share a node across HTTP verbs
    // yet. xomify-infrastructure#72 has the follow-up to collapse them into
    // RESTful `/shares/comments` later — when that lands, just rename here.

    /// Post a new comment on a share. Backend trims + caps at 500 chars and
    /// rejects whitespace-only bodies. Returns the persisted, profile-hydrated
    /// row so the UI can render it without a follow-up fetch.
    @discardableResult
    func createComment(
        shareId: String,
        body: String
    ) async throws -> ShareComment {
        try await network.xomifyPost("/shares/comments-create", body: [
            "shareId": shareId,
            "body": body
        ])
    }

    /// Page through the comment thread on a share. Newest first. `before`
    /// is the `createdAt` cursor from the previous page; nil for the first
    /// page. `limit` is capped at 100 server-side.
    func listComments(
        shareId: String,
        limit: Int = 20,
        before: String? = nil
    ) async throws -> CommentsListResponse {
        var params: [String: String] = [
            "shareId": shareId,
            "limit": String(limit)
        ]
        if let before = before { params["before"] = before }
        return try await network.xomifyGet("/shares/comments-list", queryParams: params)
    }

    /// Delete a single comment. Backend allows the comment author OR the
    /// share author to delete; everyone else gets 403.
    @discardableResult
    func deleteComment(
        shareId: String,
        commentId: String
    ) async throws -> CommentDeleteResponse {
        try await network.xomifyDelete("/shares/comments-delete", body: [
            "shareId": shareId,
            "commentId": commentId
        ])
    }

    // MARK: - Social — Reactions (xomify-backend#139)
    //
    // Distinct from `/shares/react` (Spotify queued/rated). These are emoji
    // reactions: fire / heart / laugh / mind_blown / sad / thumbs_up.

    /// Toggle one reaction. If active for (viewer, share, slug) it's removed,
    /// otherwise added. Multiple slugs per viewer per share is allowed.
    @discardableResult
    func toggleReaction(
        shareId: String,
        reaction: ShareReaction
    ) async throws -> ReactionToggleResponse {
        try await network.xomifyPost("/shares/reactions-toggle", body: [
            "shareId": shareId,
            "reaction": reaction.rawValue
        ])
    }

    /// Read-only fetch of the full reaction summary for a share.
    func listReactions(
        shareId: String
    ) async throws -> ReactionsListResponse {
        try await network.xomifyGet("/shares/reactions-list", queryParams: [
            "shareId": shareId
        ])
    }

    // MARK: - Ratings

    /// Publish (create or update) a rating for a track. Rating is 1-5.
    /// `albumArt` is required by the backend (`/ratings/publish` rejects with
    /// 400 when missing). Pass `share.albumArtUrl` from the feed; for non-feed
    /// rate surfaces, hand in `track.imageUrl?.absoluteString`.
    @discardableResult
    func publishRating(
        trackId: String,
        trackName: String,
        artistName: String,
        albumArt: String?,
        rating: Int,
        review: String? = nil
    ) async throws -> SuccessResponse {
        var body: [String: Any] = [
            "trackId": trackId,
            "trackName": trackName,
            "artistName": artistName,
            "albumArt": albumArt ?? "",
            "rating": rating
        ]
        if let review = review, !review.isEmpty {
            body["review"] = review
        }
        return try await network.xomifyPost("/ratings/publish", body: body)
    }

    /// Delete a rating.
    @discardableResult
    func removeRating(trackId: String) async throws -> SuccessResponse {
        try await network.xomifyPost("/ratings/remove", body: [
            "trackId": trackId
        ])
    }

    /// All ratings the caller has posted.
    func getAllRatings() async throws -> RatingsAllResponse {
        // Try dict shape first; fall back to bare array.
        do {
            return try await network.xomifyGet("/ratings/all")
        } catch {
            let ratings: [TrackRating] = try await network.xomifyGet("/ratings/all")
            return RatingsAllResponse(email: nil, ratings: ratings, totalCount: ratings.count)
        }
    }

    /// A single track's rating (or nil).
    func getTrackRating(trackId: String) async throws -> TrackRating? {
        do {
            let rating: TrackRating = try await network.xomifyGet("/ratings/track", queryParams: [
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
    // the Python handlers exactly. Caller identity is read from the JWT
    // context server-side.

    /// Upsert the caller's APNs device token + push preferences. Idempotent —
    /// safe to call on every cold launch when the APNs token refreshes.
    @discardableResult
    func registerPushToken(
        deviceToken: String,
        queueNotificationsEnabled: Bool,
        digestEnabled: Bool
    ) async throws -> SuccessResponse {
        try await network.xomifyPost("/notifications/register", body: [
            "deviceToken": deviceToken,
            "queueNotificationsEnabled": queueNotificationsEnabled,
            "digestEnabled": digestEnabled
        ])
    }

    /// Delete the caller's APNs device token from the backend. Called on sign-out.
    @discardableResult
    func unregisterPushToken(
        deviceToken: String
    ) async throws -> SuccessResponse {
        try await network.xomifyPost("/notifications/unregister", body: [
            "deviceToken": deviceToken
        ])
    }

    /// Upsert with the full per-kind preference map (relaunch epic, B2).
    ///
    /// Sends ONLY the flags supplied. The backend treats an absent flag as
    /// "leave it alone" and falls back to its registry default when reading —
    /// sending all sixteen every time would freeze today's defaults onto the
    /// row and break that.
    func registerPushToken(
        deviceToken: String,
        preferences: [String: Bool]
    ) async throws -> [String: Bool] {
        var body: [String: Any] = ["deviceToken": deviceToken]
        if !preferences.isEmpty { body["preferences"] = preferences }

        let response: NotificationRegisterResponse =
            try await network.xomifyPost("/notifications/register", body: body)
        return response.preferences ?? [:]
    }

    // MARK: - Notification inbox

    func fetchNotifications(limit: Int, cursor: String?) async throws -> InboxPage {
        // queryParams, NOT string interpolation: a tsId contains '#'. Spliced
        // into the path raw it terminates the query string and the cursor
        // silently vanishes — the client would then re-request page one
        // forever. URLComponents encodes it.
        var params = ["limit": String(limit)]
        if let cursor { params["cursor"] = cursor }
        return try await network.xomifyGet("/notifications/feed", queryParams: params)
    }

    func markNotificationRead(tsId: String) async throws {
        let _: SuccessResponse = try await network.xomifyPost(
            "/notifications/read", body: ["tsId": tsId]
        )
    }

    func markAllNotificationsRead() async throws {
        let _: SuccessResponse = try await network.xomifyPost(
            "/notifications/read", body: ["all": true]
        )
    }

    func fetchUnreadNotificationCount() async throws -> Int {
        let response: UnreadCountResponse =
            try await network.xomifyGet("/notifications/unread-count")
        return response.unread ?? 0
    }

    // MARK: - Favorites

    func fetchFavorites(year: Int) async throws -> FavoritesYear {
        try await network.xomifyGet("/favorites/get", queryParams: ["year": String(year)])
    }

    func createFavoritesList(
        year: Int,
        category: FavoriteCategory,
        genreLabel: String
    ) async throws -> FavoriteList {
        try await network.xomifyPost("/favorites/list-create", body: [
            "year": year,
            "category": category.rawValue,
            "genreLabel": genreLabel,
        ])
    }

    /// Replaces a list's items wholesale. The backend diffs ranks against what
    /// it had and appends history events, so the client sends the final order
    /// rather than a sequence of moves.
    func setFavoritesList(
        year: Int,
        listId: String,
        items: [FavoriteItem]
    ) async throws -> FavoriteList {
        let payload: [[String: Any]] = items.enumerated().map { index, item in
            var row: [String: Any] = [
                // Rank is 1-based and derived from position — never trusted
                // from the item, which may carry a stale value after a drag.
                "rank": index + 1,
                "spotifyId": item.spotifyId,
                "name": item.name,
            ]
            if let artist = item.artist { row["artist"] = artist }
            if let imageUrl = item.imageUrl { row["imageUrl"] = imageUrl }
            return row
        }
        return try await network.xomifyPut("/favorites/list-set", body: [
            "year": year,
            "listId": listId,
            "items": payload,
        ])
    }

    func deleteFavoritesList(year: Int, listId: String) async throws {
        let _: SuccessResponse = try await network.xomifyDelete(
            "/favorites/list-delete",
            queryParams: ["year": String(year), "listId": listId]
        )
    }

    func fetchFavoritesHistory(listId: String) async throws -> [FavoriteHistoryEvent] {
        let response: FavoriteHistoryResponse = try await network.xomifyGet(
            "/favorites/list-history", queryParams: ["listId": listId]
        )
        return response.events ?? []
    }

    func fetchFavoritesRecommendations(
        year: Int,
        category: FavoriteCategory,
        listId: String
    ) async throws -> [FavoriteItem] {
        let response: FavoriteRecommendations = try await network.xomifyGet(
            "/favorites/recommendations",
            queryParams: [
                "year": String(year),
                "category": category.rawValue,
                "listId": listId,
            ]
        )
        return response.items ?? []
    }

    // MARK: - Likes

    /// Push the caller's top-200 saved tracks to the backend.
    /// Verb-disambiguated path: `/likes/push` (POST).
    @discardableResult
    func pushUserLikes(total: Int, tracks: [LikesPushTrack]) async throws -> LikesPushResponse {
        let trackDicts: [[String: Any]] = tracks.map { t -> [String: Any] in
            var row: [String: Any] = [
                "trackId": t.trackId,
                "name": t.name,
                "artist": t.artist
            ]
            if let addedAt = t.addedAt { row["addedAt"] = addedAt }
            if let albumArt = t.albumArt { row["albumArt"] = albumArt }
            return row
        }
        let body: [String: Any] = [
            "total": total,
            "tracks": trackDicts
        ]
        return try await network.xomifyPost("/likes/push", body: body)
    }

    /// Fetch a friend's (or self) liked tracks from the backend.
    /// Verb-disambiguated path: `/likes/by-user` (GET).
    func getLikesByUser(
        targetEmail: String,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> LikesByUserResponse {
        try await network.xomifyGet("/likes/by-user", queryParams: [
            "targetEmail": targetEmail,
            "limit": String(limit),
            "offset": String(offset)
        ])
    }

    /// Set the caller's `likes_public` flag.
    @discardableResult
    func setLikesPublic(value: Bool) async throws -> SuccessResponse {
        try await network.xomifyPost("/users/likes-public", body: [
            "value": value
        ])
    }
}
