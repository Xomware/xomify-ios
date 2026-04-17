import Foundation

// MARK: - Share Type

enum ShareType: String, Codable, Sendable {
    case wrapped
    case releaseRadar = "release_radar"
    case track
    case playlist
}

// MARK: - Reaction Action

enum ReactionAction: String, Codable, Sendable {
    case like
    case fire
    case love
    case none
}

// MARK: - JSONValue
//
// Polymorphic JSON value for the backend's arbitrary `payload` shape.
// Supports string / int / double / bool / array / dict / null.

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

// MARK: - Share

struct Share: Codable, Identifiable, Sendable {
    let shareId: String
    let email: String
    let type: ShareType
    let payload: [String: JSONValue]?
    let caption: String?
    let createdAt: String
    let interactionCounts: [String: Int]?

    var id: String { shareId }

    /// Count for a specific reaction type. Backend keys: "like", "fire", "love".
    func count(for reaction: ReactionAction) -> Int {
        guard reaction != .none else { return 0 }
        return interactionCounts?[reaction.rawValue] ?? 0
    }

    /// Parse createdAt ("2025-04-17 14:30:00" UTC) into a Date.
    var createdAtDate: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: createdAt) {
            return date
        }
        // Fallback: ISO8601
        let iso = ISO8601DateFormatter()
        return iso.date(from: createdAt)
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

// MARK: - Feed Response

struct FeedResponse: Codable, Sendable {
    let email: String?
    let totalCount: Int?
    let shares: [Share]
}

// MARK: - Share Create Response

struct ShareCreateResponse: Codable, Sendable {
    let success: Bool?
    let shareId: String?
}

// MARK: - Reaction Response

struct ReactionResponse: Codable, Sendable {
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
struct XomifyGroup: Codable, Sendable, Identifiable, Hashable {
    let groupId: String
    let name: String
    let description: String?
    let ownerEmail: String?
    let createdAt: String?
    let memberCount: Int?
    let trackCount: Int?

    var id: String { groupId }
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
