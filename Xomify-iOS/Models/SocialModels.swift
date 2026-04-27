import Foundation

// MARK: - JSONValue
//
// Polymorphic JSON value kept for `FriendProfile` (backend returns arbitrarily
// shaped top-songs / top-artists / top-genres / playlists blobs).
// Share no longer uses this — the deployed `shares_feed` / `shares_create`
// contract is fully denormalized to scalar fields.

enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let v = try? container.decode(Bool.self) {
            self = .bool(v)
            return
        }
        // Prefer Int over Double when the number is integral
        if let v = try? container.decode(Int.self) {
            self = .int(v)
            return
        }
        if let v = try? container.decode(Double.self) {
            self = .double(v)
            return
        }
        if let v = try? container.decode(String.self) {
            self = .string(v)
            return
        }
        if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
            return
        }
        if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let v):
            try container.encode(v)
        case .int(let v):
            try container.encode(v)
        case .double(let v):
            try container.encode(v)
        case .string(let v):
            try container.encode(v)
        case .array(let v):
            try container.encode(v)
        case .object(let v):
            try container.encode(v)
        }
    }

    // MARK: - Convenience accessors

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        case .string(let v): return Int(v)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        case .string(let v): return Double(v)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }
}

// MARK: - MoodTag

/// Mood tags a sharer can attach to a share. Single enum, one per share.
/// Raw values match the deployed `shares_create` contract.
enum MoodTag: String, Codable, Sendable, CaseIterable, Identifiable {
    case hype
    case chill
    case sad
    case focus
    case party
    case romance
    case nostalgic
    case angry

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hype:       return "Hype"
        case .chill:      return "Chill"
        case .sad:        return "Sad"
        case .focus:      return "Focus"
        case .party:      return "Party"
        case .romance:    return "Romance"
        case .nostalgic:  return "Nostalgic"
        case .angry:      return "Angry"
        }
    }

    var emoji: String {
        switch self {
        case .hype:       return "🔥"
        case .chill:      return "😌"
        case .sad:        return "💧"
        case .focus:      return "🎯"
        case .party:      return "🎉"
        case .romance:    return "💗"
        case .nostalgic:  return "🕰️"
        case .angry:      return "😤"
        }
    }
}

// MARK: - Share
//
// Matches the deployed `shares_feed` / `shares_create` atom. Track fields are
// denormalized so the feed can render without a follow-up Spotify fetch per card.

struct Share: Codable, Identifiable, Sendable, Hashable {
    let shareId: String
    let sharedBy: String
    let sharedAt: String

    // Denormalized track fields
    let trackId: String
    let trackUri: String
    let trackName: String
    let artistName: String
    let albumName: String?
    let albumArtUrl: String?

    // Optional sharer metadata
    let caption: String?
    let moodTag: MoodTag?
    let genreTags: [String]?

    // Server-side enrichment (per-viewer)
    let queuedCount: Int
    let ratedCount: Int
    let viewerHasQueued: Bool
    let viewerRating: Int?
    let sharerRating: Int?

    // Target audience (xomify-backend#138). Legacy rows omit both fields and
    // are treated as public shares with no group targets.
    let groupIds: [String]
    let isPublic: Bool

    // Comments + emoji reactions (xomify-backend#139). Surfaced by
    // `/shares/detail`; `/shares/feed` may omit these for now — defaults
    // keep the row decodable either way.
    let commentCount: Int
    let reactionCounts: [String: Int]
    let viewerReactions: [String]

    var id: String { shareId }

    /// Parse sharedAt ("2025-04-17 14:30:00" UTC) into a Date. Falls back to ISO8601.
    var sharedAtDate: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: sharedAt) {
            return date
        }
        let iso = ISO8601DateFormatter()
        return iso.date(from: sharedAt)
    }

    /// Short relative time string ("3h ago", "just now").
    var relativeTime: String {
        guard let date = sharedAtDate else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3_600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h ago" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    /// `URL` for album art if valid.
    var albumArt: URL? {
        guard let s = albumArtUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Custom decoding — the backend stores the author as `email` on the
    /// `shares` table but some paths also emit `sharedBy`. Accept either so
    /// the feed doesn't hard-fail on the live payload. Enrichment fields are
    /// optional because cold-cache responses may omit them.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shareId         = try c.decode(String.self, forKey: .shareId)
        if let author = try c.decodeIfPresent(String.self, forKey: .sharedBy) {
            sharedBy = author
        } else {
            let fallback = try decoder.container(keyedBy: FallbackAuthorKey.self)
            sharedBy = try fallback.decode(String.self, forKey: .email)
        }
        sharedAt        = try c.decode(String.self, forKey: .sharedAt)
        trackId         = try c.decode(String.self, forKey: .trackId)
        trackUri        = try c.decode(String.self, forKey: .trackUri)
        trackName       = try c.decode(String.self, forKey: .trackName)
        artistName      = try c.decode(String.self, forKey: .artistName)
        albumName       = try c.decodeIfPresent(String.self, forKey: .albumName)
        albumArtUrl     = try c.decodeIfPresent(String.self, forKey: .albumArtUrl)
        caption         = try c.decodeIfPresent(String.self, forKey: .caption)
        moodTag         = try c.decodeIfPresent(MoodTag.self, forKey: .moodTag)
        genreTags       = try c.decodeIfPresent([String].self, forKey: .genreTags)
        queuedCount     = try c.decodeIfPresent(Int.self, forKey: .queuedCount) ?? 0
        ratedCount      = try c.decodeIfPresent(Int.self, forKey: .ratedCount) ?? 0
        viewerHasQueued = try c.decodeIfPresent(Bool.self, forKey: .viewerHasQueued) ?? false
        viewerRating    = try c.decodeIfPresent(Int.self, forKey: .viewerRating)
        sharerRating    = try c.decodeIfPresent(Int.self, forKey: .sharerRating)
        groupIds        = try c.decodeIfPresent([String].self, forKey: .groupIds) ?? []
        isPublic        = try c.decodeIfPresent(Bool.self, forKey: .isPublic) ?? true
        commentCount    = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        reactionCounts  = try c.decodeIfPresent([String: Int].self, forKey: .reactionCounts) ?? [:]
        viewerReactions = try c.decodeIfPresent([String].self, forKey: .viewerReactions) ?? []
    }

    private enum FallbackAuthorKey: String, CodingKey {
        case email
    }

    /// Memberwise initializer for tests and optimistic-update copies.
    init(
        shareId: String,
        sharedBy: String,
        sharedAt: String,
        trackId: String,
        trackUri: String,
        trackName: String,
        artistName: String,
        albumName: String? = nil,
        albumArtUrl: String? = nil,
        caption: String? = nil,
        moodTag: MoodTag? = nil,
        genreTags: [String]? = nil,
        queuedCount: Int = 0,
        ratedCount: Int = 0,
        viewerHasQueued: Bool = false,
        viewerRating: Int? = nil,
        sharerRating: Int? = nil,
        groupIds: [String] = [],
        isPublic: Bool = true,
        commentCount: Int = 0,
        reactionCounts: [String: Int] = [:],
        viewerReactions: [String] = []
    ) {
        self.shareId = shareId
        self.sharedBy = sharedBy
        self.sharedAt = sharedAt
        self.trackId = trackId
        self.trackUri = trackUri
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.albumArtUrl = albumArtUrl
        self.caption = caption
        self.moodTag = moodTag
        self.genreTags = genreTags
        self.queuedCount = queuedCount
        self.ratedCount = ratedCount
        self.viewerHasQueued = viewerHasQueued
        self.viewerRating = viewerRating
        self.sharerRating = sharerRating
        self.groupIds = groupIds
        self.isPublic = isPublic
        self.commentCount = commentCount
        self.reactionCounts = reactionCounts
        self.viewerReactions = viewerReactions
    }

    private enum CodingKeys: String, CodingKey {
        case shareId, sharedBy, sharedAt
        case trackId, trackUri, trackName, artistName, albumName, albumArtUrl
        case caption, moodTag, genreTags
        case queuedCount, ratedCount, viewerHasQueued, viewerRating, sharerRating
        case groupIds
        case isPublic = "public"
        case commentCount, reactionCounts, viewerReactions
    }

    /// Convenience for optimistic UI patches — produce a new Share with the
    /// reaction summary swapped out, leaving every other field intact.
    func withReactionSummary(counts: [String: Int], viewerReactions: [String]) -> Share {
        Share(
            shareId: shareId, sharedBy: sharedBy, sharedAt: sharedAt,
            trackId: trackId, trackUri: trackUri, trackName: trackName,
            artistName: artistName, albumName: albumName, albumArtUrl: albumArtUrl,
            caption: caption, moodTag: moodTag, genreTags: genreTags,
            queuedCount: queuedCount, ratedCount: ratedCount,
            viewerHasQueued: viewerHasQueued, viewerRating: viewerRating,
            sharerRating: sharerRating,
            groupIds: groupIds, isPublic: isPublic,
            commentCount: commentCount,
            reactionCounts: counts,
            viewerReactions: viewerReactions
        )
    }

    /// Optimistically patch the viewer's own rating onto the share so the
    /// downstream detail view (which builds its own VM from this Share) sees
    /// the rating the user just set on the feed card. `bumpRatedCount` adds 1
    /// to `ratedCount` when the viewer hadn't already rated this share —
    /// keeps the friends-rated stat in sync without a refetch.
    func withViewerRating(_ rating: Int?) -> Share {
        let bumpRatedCount = (viewerRating == nil && rating != nil) ? 1
            : (viewerRating != nil && rating == nil) ? -1 : 0
        return Share(
            shareId: shareId, sharedBy: sharedBy, sharedAt: sharedAt,
            trackId: trackId, trackUri: trackUri, trackName: trackName,
            artistName: artistName, albumName: albumName, albumArtUrl: albumArtUrl,
            caption: caption, moodTag: moodTag, genreTags: genreTags,
            queuedCount: queuedCount, ratedCount: max(0, ratedCount + bumpRatedCount),
            viewerHasQueued: viewerHasQueued, viewerRating: rating,
            sharerRating: sharerRating,
            groupIds: groupIds, isPublic: isPublic,
            commentCount: commentCount,
            reactionCounts: reactionCounts,
            viewerReactions: viewerReactions
        )
    }

    /// Same idea for comment count adjustments.
    func withCommentCount(_ newCount: Int) -> Share {
        Share(
            shareId: shareId, sharedBy: sharedBy, sharedAt: sharedAt,
            trackId: trackId, trackUri: trackUri, trackName: trackName,
            artistName: artistName, albumName: albumName, albumArtUrl: albumArtUrl,
            caption: caption, moodTag: moodTag, genreTags: genreTags,
            queuedCount: queuedCount, ratedCount: ratedCount,
            viewerHasQueued: viewerHasQueued, viewerRating: viewerRating,
            sharerRating: sharerRating,
            groupIds: groupIds, isPublic: isPublic,
            commentCount: newCount,
            reactionCounts: reactionCounts,
            viewerReactions: viewerReactions
        )
    }
}

// MARK: - Create Share Request

/// Request body for POST `/shares/create`. Denormalized track fields + optional metadata.
struct CreateShareRequest: Codable, Sendable {
    let email: String
    let trackId: String
    let trackUri: String
    let trackName: String
    let artistName: String
    let albumName: String?
    let albumArtUrl: String?
    let caption: String?
    let moodTag: MoodTag?
    let genreTags: [String]?
}

// MARK: - Feed Response

/// Response for GET `/shares/feed`. `nextBefore` is the pagination cursor
/// (the `sharedAt` of the last returned share) — null when exhausted.
struct FeedResponse: Codable, Sendable {
    let shares: [Share]
    let nextBefore: String?
    let totalCount: Int?

    init(shares: [Share], nextBefore: String? = nil, totalCount: Int? = nil) {
        self.shares = shares
        self.nextBefore = nextBefore
        self.totalCount = totalCount
    }
}

// MARK: - Cached Feed Wrapper

/// On-disk cache envelope. Versioned so future shape changes can be detected
/// and the cache invalidated silently on next launch.
struct CachedFeed: Codable, Sendable {
    static let currentVersion: Int = 1

    let version: Int
    let filterKey: String
    let shares: [Share]
    let cachedAt: String

    init(filterKey: String, shares: [Share], cachedAt: String = Self.nowString()) {
        self.version = Self.currentVersion
        self.filterKey = filterKey
        self.shares = shares
        self.cachedAt = cachedAt
    }

    private static func nowString() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: Date())
    }
}

// MARK: - Share Create Response

struct ShareCreateResponse: Codable, Sendable {
    let success: Bool?
    let shareId: String?
    let share: Share?
}

// MARK: - Reaction Response
//
// NOTE: Reactions are gated behind `FeatureFlags.reactionsEnabled`. The
// response shape is kept so `XomifyService.reactToShare` can stay wired for
// sub-feature 4 (`backend-interactions-and-notifications`).

struct ReactionResponse: Codable, Sendable {
    let success: Bool?
}

// MARK: - Share Interaction Response
//
// Placeholder for the upcoming `shares_interaction` endpoint (sub-feature 4).
// Kept here so the interaction write-path compiles ahead of time.

struct ShareInteractionResponse: Codable, Sendable {
    let success: Bool?
}

// MARK: - Invite Create Response

struct InviteCreateResponse: Codable, Sendable {
    let success: Bool?
    let inviteCode: String?
    let shareUrl: String?
    let expiresAt: String?
    let status: String?
}

// MARK: - Invite Accept Response

struct InviteAcceptResponse: Codable, Sendable {
    let success: Bool?
    let inviteCode: String?
    let friendEmail: String?
}

// MARK: - Pending Invite

/// A single deep-link invite that has been sent to the current user and is
/// awaiting their accept/decline action. Distinct from `Friend` which represents
/// an accepted social connection or an in-app friend request.
struct PendingInvite: Codable, Sendable, Identifiable, Hashable {
    let inviteCode: String
    let senderEmail: String
    let senderDisplayName: String?
    let senderAvatar: String?
    let createdAt: String?
    let expiresAt: String?

    var id: String { inviteCode }

    /// Human-facing sender label.
    var label: String {
        if let name = senderDisplayName, !name.isEmpty { return name }
        return senderEmail
    }

    /// Parse createdAt into a Date (best-effort).
    var createdAtDate: Date? {
        guard let createdAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: createdAt) {
            return date
        }
        return ISO8601DateFormatter().date(from: createdAt)
    }

    /// Short relative time string ("3h ago", "just now").
    var relativeTime: String {
        guard let date = createdAtDate else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3_600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h ago" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

/// Response for `GET /invites/pending?email=...`.
struct PendingInvitesResponse: Codable, Sendable {
    let email: String?
    let invites: [PendingInvite]?
    let totalCount: Int?
}

// MARK: - Friends

/// A single friend / friend-request row in any bucket.
struct Friend: Codable, Sendable, Hashable {
    let email: String
    let friendEmail: String?
    let displayName: String?
    let avatar: String?
    let status: String?
    let direction: String?
    let createdAt: String?
    let mutualCount: Int?

    /// Friend-side email (the target). For accepted/pending/requested rows the
    /// backend stores the row under the current user and identifies the other
    /// party via `friendEmail`.
    var targetEmail: String {
        if let fe = friendEmail, !fe.isEmpty { return fe }
        return email
    }

    /// Human-facing label.
    var label: String {
        if let name = displayName, !name.isEmpty { return name }
        return targetEmail
    }
}

/// Response for GET /friends/all?email=...
struct FriendsAllResponse: Codable, Sendable {
    let email: String?
    let accepted: [Friend]?
    let requested: [Friend]?
    let pending: [Friend]?
    let blocked: [Friend]?
    let acceptedCount: Int?
    let requestedCount: Int?
    let pendingCount: Int?
    let blockedCount: Int?
    let totalCount: Int?
}

/// Public profile of another user. Nested term maps are stored loosely since
/// the backend shape can vary (track objects vs id strings).
struct FriendProfile: Codable, Sendable {
    let email: String?
    let displayName: String?
    let userId: String?
    let avatar: String?
    let followersCount: Int?
    let followingCount: Int?
    let playlistCount: Int?
    let friendsCount: Int?
    /// Count of shares authored by this user. Optional: backend contract
    /// `ios-profile-redesign-contract.md` adds this in a follow-up; until it
    /// ships, header falls back to 3 stats instead of 4.
    let shareCount: Int?
    let topSongs: [String: JSONValue]?
    let topArtists: [String: JSONValue]?
    let topGenres: [String: JSONValue]?
    let playlists: [JSONValue]?
}

/// Response for GET /friends/list?email=... — every other user on the platform.
struct UserListResponse: Codable, Sendable {
    let users: [SearchResult]?
    let totalCount: Int?
}

/// A user in the "find friends" list. Action flags come from the backend.
struct SearchResult: Codable, Sendable, Identifiable, Hashable {
    let email: String
    let displayName: String?
    let avatar: String?
    let isFriend: Bool?
    let isPending: Bool?
    let isOutgoingRequest: Bool?
    let isIncomingRequest: Bool?
    let mutualCount: Int?

    var id: String { email }

    var label: String {
        if let name = displayName, !name.isEmpty { return name }
        return email
    }
}

// MARK: - Groups

/// A group you belong to.
///
/// The backend's `/groups/list` endpoint used to return only membership
/// rows (no `name`/`createdBy`), which crashed decoding. Backend now
/// hydrates from the Groups table, but we keep most fields optional so a
/// partial payload from any source degrades to a usable row rather than
/// failing the whole list. `groupId` is always required — without it the
/// row is meaningless.
struct XomifyGroup: Codable, Sendable, Identifiable, Hashable {
    let groupId: String
    let name: String?
    let description: String?
    let ownerEmail: String?
    let createdBy: String?
    let createdAt: String?
    let memberCount: Int?
    let trackCount: Int?
    let imageUrl: String?
    let role: String?
    let joinedAt: String?

    var id: String { groupId }

    /// Display-safe name — falls back to a short id suffix when the backend
    /// returns a headless row so the UI never renders an empty label.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        let suffix = groupId.suffix(6)
        return "Group \(suffix)"
    }

    /// Prefer `createdBy` (new hydrated shape) over `ownerEmail` (legacy).
    var ownerLabel: String? {
        createdBy ?? ownerEmail
    }
}

/// Response for GET /groups/list
struct GroupsListResponse: Codable, Sendable {
    let email: String?
    let groups: [XomifyGroup]?
    let totalCount: Int?
}

/// Response for GET /groups/info — group + members + tracks
struct GroupInfo: Codable, Sendable {
    let group: XomifyGroup?
    let members: [GroupMember]?
    let tracks: [GroupTrack]?
}

struct GroupMember: Codable, Sendable, Identifiable, Hashable {
    let email: String
    let displayName: String?
    let joinedAt: String?
    let isOwner: Bool?

    var id: String { email }

    var label: String {
        if let name = displayName, !name.isEmpty { return name }
        return email
    }
}

struct GroupTrack: Codable, Sendable, Identifiable, Hashable {
    let trackIdTimestamp: String
    let trackId: String?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let imageUrl: String?
    let addedBy: String?
    let addedAt: String?
    let listenedBy: [String]?

    var id: String { trackIdTimestamp }

    var image: URL? {
        guard let s = imageUrl else { return nil }
        return URL(string: s)
    }
}

/// POST /groups/create response — server returns the new group.
struct GroupCreateResponse: Codable, Sendable {
    let success: Bool?
    let group: XomifyGroup?
    let groupId: String?
}

/// Simple success ack.
struct SuccessResponse: Codable, Sendable {
    let success: Bool?
}

/// POST /groups/song-status response.
struct SongStatusResponse: Codable, Sendable {
    let success: Bool?
    let listened: Bool?
    let listenedBy: [String]?
}

// MARK: - Ratings

struct TrackRating: Codable, Sendable, Identifiable, Hashable {
    let email: String
    let trackId: String
    let trackName: String?
    let artistName: String?
    let rating: Int
    let review: String?
    let createdAt: String?
    let updatedAt: String?

    var id: String { trackId }
}

struct RatingsAllResponse: Codable, Sendable {
    let email: String?
    let ratings: [TrackRating]?
    let totalCount: Int?
}

// MARK: - Share Detail
//
// Response for GET `/shares/detail`. Backend-documented contract:
// `{ share, interactions, friendRatings }`. See
// xomify-backend/lambdas/shares_detail/handler.py.

/// One row under `interactions[]` — a friend who queued or rated the share.
struct ShareInteractionEntry: Codable, Sendable, Identifiable, Hashable {
    let email: String
    let displayName: String?
    let avatar: String?
    let action: String   // "queued" | "rated"
    let createdAt: String?

    /// Synthesized stable id — email + action — since the backend doesn't
    /// return one and a user can both queue and rate.
    var id: String { "\(email)#\(action)" }

    var avatarURL: URL? {
        guard let s = avatar, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var resolvedName: String {
        if let n = displayName, !n.isEmpty { return n }
        return email
    }
}

/// One row under `friendRatings[]` — a friend's rating of this track.
struct ShareFriendRating: Codable, Sendable, Identifiable, Hashable {
    let email: String
    let displayName: String?
    let avatar: String?
    let rating: Double
    let review: String?
    let ratedAt: String?

    var id: String { email }

    var avatarURL: URL? {
        guard let s = avatar, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var resolvedName: String {
        if let n = displayName, !n.isEmpty { return n }
        return email
    }

    /// Integer display for the 1-5 star UI. Backend persists as float.
    var displayStars: Int { Int(rating.rounded()) }
}

struct ShareDetailResponse: Codable, Sendable {
    let share: Share
    let interactions: [ShareInteractionEntry]
    let friendRatings: [ShareFriendRating]
}

// MARK: - Reactions
//
// Backend contract: xomify-backend#139. Six fixed emoji slugs; per (user,
// share, slug) toggle. Multiple emoji per user is allowed.

enum ShareReaction: String, Codable, Sendable, CaseIterable, Identifiable {
    case fire
    case heart
    case laugh
    case mindBlown = "mind_blown"
    case sad
    case thumbsUp = "thumbs_up"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .fire:       return "🔥"
        case .heart:      return "❤️"
        case .laugh:      return "😂"
        case .mindBlown:  return "🤯"
        case .sad:        return "😢"
        case .thumbsUp:   return "👍"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .fire:       return "Fire"
        case .heart:      return "Heart"
        case .laugh:      return "Laugh"
        case .mindBlown:  return "Mind blown"
        case .sad:        return "Sad"
        case .thumbsUp:   return "Thumbs up"
        }
    }
}

/// Response for POST `/shares/reactions`.
struct ReactionToggleResponse: Codable, Sendable {
    let active: Bool
    let reaction: String
    let counts: [String: Int]
    let viewerReactions: [String]
}

/// Response for GET `/shares/reactions`.
struct ReactionsListResponse: Codable, Sendable {
    let counts: [String: Int]
    let viewerReactions: [String]
}

// MARK: - Comments
//
// Backend contract: xomify-backend#139. POST/GET/DELETE `/shares/comments`.

struct ShareComment: Codable, Sendable, Identifiable, Hashable {
    let commentId: String
    let shareId: String
    let email: String
    let displayName: String?
    let avatar: String?
    let body: String
    let createdAt: String?

    var id: String { commentId }

    var avatarURL: URL? {
        guard let s = avatar, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var resolvedName: String {
        if let n = displayName, !n.isEmpty { return n }
        return email
    }

    var createdAtDate: Date? {
        guard let createdAt else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: createdAt) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: createdAt) { return d }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: createdAt)
    }

    var relativeTime: String {
        guard let date = createdAtDate else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3_600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h ago" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

/// Response for GET `/shares/comments`.
struct CommentsListResponse: Codable, Sendable {
    let comments: [ShareComment]
    let nextBefore: String?
}

/// Response for DELETE `/shares/comments`.
struct CommentDeleteResponse: Codable, Sendable {
    let deleted: Bool
    let commentId: String
}

// MARK: - Likes Push / By-User

/// A single track payload sent to POST `/likes/push`.
struct LikesPushTrack: Codable, Sendable {
    let trackId: String
    let addedAt: String?
    let name: String
    let artist: String
    let albumArt: String?
}

/// Request body for POST `/likes/push`.
struct LikesPushRequest: Codable, Sendable {
    let email: String
    let total: Int
    let tracks: [LikesPushTrack]
}

/// Response from POST `/likes/push`.
struct LikesPushResponse: Codable, Sendable {
    let success: Bool?
    let deduped: Bool?
    let count: Int?
}

/// A single track row returned by GET `/likes/by-user`.
struct LikesByUserTrack: Codable, Sendable, Identifiable, Hashable {
    let trackId: String
    let trackName: String?
    let artistName: String?
    let albumArt: String?
    let addedAt: String?

    var id: String { trackId }

    var albumArtURL: URL? {
        guard let s = albumArt, !s.isEmpty else { return nil }
        return URL(string: s)
    }
}

/// Response from GET `/likes/by-user`.
struct LikesByUserResponse: Codable, Sendable {
    let tracks: [LikesByUserTrack]
    let total: Int?
    let hasMore: Bool?
    let likesPublic: Bool?
}
