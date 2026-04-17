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
