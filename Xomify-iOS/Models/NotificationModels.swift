import Foundation

// MARK: - Device Token Registration

/// Request body for `POST /notifications/register`.
///
/// Mirrors the deployed `lambdas/notifications_register/handler.py` contract.
/// Keys are camelCase on the wire (no snake_case conversion).
struct DeviceTokenRegistration: Codable, Sendable, Equatable {
    let email: String
    let deviceToken: String
    let queueNotificationsEnabled: Bool
    let digestEnabled: Bool
}

// MARK: - Device Token Unregister

/// Request body for `POST /notifications/unregister`.
/// Mirrors `lambdas/notifications_unregister/handler.py`.
struct DeviceTokenUnregister: Codable, Sendable, Equatable {
    let email: String
    let deviceToken: String
}

// MARK: - Notification Preferences

/// Per-kind opt-in map, keyed by the backend's flag names.
///
/// Deliberately a dictionary rather than sixteen stored properties: the backend
/// registry owns the list, and a struct here would need editing every time a
/// kind is added — a second source of truth that silently drifts.
///
/// SPARSE BY DESIGN. Only flags the user has actually touched are sent. An
/// absent flag means "use the registry default", which is what lets the backend
/// add kinds without backfilling every device row.
struct NotificationPreferences: Codable, Sendable, Equatable {
    private(set) var flags: [String: Bool]

    init(flags: [String: Bool] = [:]) {
        self.flags = flags
    }

    /// Resolved value for one setting. `defaultValue` mirrors the backend
    /// registry default and is used when the server has told us nothing.
    func isEnabled(_ flag: String, default defaultValue: Bool = true) -> Bool {
        flags[flag] ?? defaultValue
    }

    mutating func set(_ flag: String, _ enabled: Bool) {
        flags[flag] = enabled
    }

    /// Merge a server response over local state. The server is authoritative —
    /// it knows about kinds this build may not.
    mutating func merge(server: [String: Bool]) {
        for (key, value) in server { flags[key] = value }
    }
}

/// One row in the Settings › Notifications list.
struct NotificationSetting: Identifiable, Sendable, Equatable {
    /// Backend opt-in flag name — the wire key.
    let id: String
    let title: String
    let subtitle: String
    let section: NotificationSection
    let defaultEnabled: Bool
}

enum NotificationSection: String, CaseIterable, Sendable {
    case sharesSocial
    case playlistDrops
    case remindersUpdates

    var title: String {
        switch self {
        case .sharesSocial:     return "Shares & Social"
        case .playlistDrops:    return "Playlist Drops"
        case .remindersUpdates: return "Reminders & Updates"
        }
    }
}

/// Mirrors `lambdas/common/notification_kinds.py`. Kept in the same order and
/// wording so the two Settings screens read identically.
enum NotificationCatalog {
    static let all: [NotificationSetting] = [
        .init(id: "shareReceivedEnabled", title: "Someone shares a song",
              subtitle: "When a friend sends you a track.", section: .sharesSocial, defaultEnabled: true),
        .init(id: "shareCommentEnabled", title: "Comments on your share",
              subtitle: "When someone replies on a song you sent.", section: .sharesSocial, defaultEnabled: true),
        .init(id: "shareReactionEnabled", title: "Reactions on your share",
              subtitle: "When someone reacts to a song you sent.", section: .sharesSocial, defaultEnabled: true),
        .init(id: "shareListenedEnabled", title: "Someone listens to your song",
              subtitle: "When a friend plays a track you sent.", section: .sharesSocial, defaultEnabled: true),
        .init(id: "shareRatedEnabled", title: "Someone rates your song",
              subtitle: "When a friend scores a track you sent.", section: .sharesSocial, defaultEnabled: true),
        .init(id: "queueNotificationsEnabled", title: "Your share takes off",
              subtitle: "When several friends queue the same song you sent.", section: .sharesSocial, defaultEnabled: true),
        .init(id: "friendRequestEnabled", title: "Friend requests",
              subtitle: "When someone sends you a friend request.", section: .sharesSocial, defaultEnabled: true),
        .init(id: "friendAcceptedEnabled", title: "Friend requests accepted",
              subtitle: "When someone accepts your friend request.", section: .sharesSocial, defaultEnabled: true),
        .init(id: "inviteReceivedEnabled", title: "Invites",
              subtitle: "When someone invites you to Xomify.", section: .sharesSocial, defaultEnabled: true),
        .init(id: "inviteAcceptedEnabled", title: "Invites accepted",
              subtitle: "When someone takes up your invite.", section: .sharesSocial, defaultEnabled: true),

        .init(id: "wrappedDropEnabled", title: "Monthly Wrapped is ready",
              subtitle: "When your Wrapped playlist is generated.", section: .playlistDrops, defaultEnabled: true),
        .init(id: "releaseRadarDropEnabled", title: "Release Radar is ready",
              subtitle: "When your weekly Release Radar is generated.", section: .playlistDrops, defaultEnabled: true),

        .init(id: "rateReminderEnabled", title: "Reminders to listen & rate",
              subtitle: "A single nudge, a day after a song lands unplayed.", section: .remindersUpdates, defaultEnabled: true),
        .init(id: "favoritesReminderEnabled", title: "Year-end favorites",
              subtitle: "A yearly nudge to record your favorites.", section: .remindersUpdates, defaultEnabled: true),
        // The one kind that is off unless asked for — see the backend registry.
        .init(id: "digestEnabled", title: "Weekly digest",
              subtitle: "A weekly summary of shares and activity.", section: .remindersUpdates, defaultEnabled: false),
        .init(id: "broadcastEnabled", title: "App updates",
              subtitle: "Occasional announcements about Xomify itself.", section: .remindersUpdates, defaultEnabled: true),
    ]

    static func settings(in section: NotificationSection) -> [NotificationSetting] {
        all.filter { $0.section == section }
    }
}

// MARK: - Inbox

/// One row of `GET /notifications/feed`.
struct InboxNotification: Codable, Sendable, Equatable, Identifiable {
    let tsId: String
    let kind: String
    let title: String
    let body: String
    let route: String?
    let actorName: String?
    let imageUrl: String?
    var read: Bool
    let createdAt: String

    var id: String { tsId }
}

struct InboxPage: Codable, Sendable, Equatable {
    let items: [InboxNotification]
    let nextCursor: String?
}

// MARK: - Push Payload
//
// The backend's `notifications_send` lambda flattens every `customData` key
// onto the top-level APNs payload alongside `aps`.
//
// It now sends an explicit `pushType` (the registry key from
// `lambdas/common/notification_kinds.py`) and a `route` token. This file used
// to INFER the kind from payload shape — "has shareId, therefore queue
// threshold" — which worked when there were two kinds and cannot possibly work
// with sixteen, since most of them carry a shareId.
//
// Shape inference is retained ONLY as a fallback for payloads already in
// flight from before the registry shipped.

/// Every notification the backend can send. Raw values are the backend's
/// registry keys verbatim — they are the wire contract, so they are snake_case
/// here even though Swift would prefer otherwise.
enum PushKind: String, Sendable, CaseIterable {
    // Shares & social
    case shareReceived      = "share_received"
    case shareComment       = "share_comment"
    case shareReaction      = "share_reaction"
    case shareListened      = "share_listened"
    case shareRated         = "share_rated"
    case queueThreshold     = "queue_threshold"
    case friendRequest      = "friend_request"
    case friendAccepted     = "friend_accepted"
    case inviteReceived     = "invite_received"
    case inviteAccepted     = "invite_accepted"
    // Playlist drops
    case wrappedDrop        = "wrapped_drop"
    case releaseRadarDrop   = "release_radar_drop"
    // Reminders & updates
    case rateReminder       = "rate_reminder"
    case favoritesReminder  = "favorites_reminder"
    case digest             = "digest"
    case broadcast          = "broadcast"

    case unknown            = "unknown"

    /// How loudly this kind arrives while the app is already open.
    ///
    /// The rule: if the user is *in the app*, anything they can already see is
    /// noise. Drops and social events are worth a banner; the weekly digest and
    /// broadcasts are not — they are catch-up content, and the inbox is where
    /// catch-up belongs.
    var interruptsInForeground: Bool {
        switch self {
        case .digest, .broadcast, .favoritesReminder:
            return false
        default:
            return true
        }
    }
}

/// Strongly-typed view onto an APNs userInfo dictionary. Every field optional —
/// a payload from an older backend must never crash the handler.
struct PushPayload: Sendable, Equatable {
    let kind: PushKind
    /// Backend route token, e.g. "share:<id>" or "friends". Shared with web,
    /// where the same string resolves to an Angular route.
    let route: String?
    let shareId: String?
    let trackId: String?
    let reactorCount: Int?
    let count: Int?
    let windowDays: Int?

    init(userInfo: [AnyHashable: Any]) {
        self.route = userInfo["route"] as? String
        self.trackId = userInfo["trackId"] as? String
        self.reactorCount = Self.asInt(userInfo["reactorCount"])
        self.count = Self.asInt(userInfo["count"])
        self.windowDays = Self.asInt(userInfo["windowDays"])

        // Prefer the explicit key, then the route's own subject id.
        let explicitShareId = userInfo["share_id"] as? String ?? userInfo["shareId"] as? String
        let routeShareId = Self.subject(of: userInfo["route"] as? String, kind: "share")
        self.shareId = explicitShareId ?? routeShareId

        if let raw = userInfo["pushType"] as? String, let known = PushKind(rawValue: raw) {
            self.kind = known
        } else if self.shareId != nil {
            // Legacy fallback: pre-registry payloads carrying a shareId were
            // always queue-threshold, because that was the only such push.
            self.kind = .queueThreshold
        } else if self.windowDays != nil || self.count != nil {
            self.kind = .digest
        } else {
            self.kind = .unknown
        }
    }

    init(
        kind: PushKind,
        route: String? = nil,
        shareId: String? = nil,
        trackId: String? = nil,
        reactorCount: Int? = nil,
        count: Int? = nil,
        windowDays: Int? = nil
    ) {
        self.kind = kind
        self.route = route
        self.shareId = shareId
        self.trackId = trackId
        self.reactorCount = reactorCount
        self.count = count
        self.windowDays = windowDays
    }

    /// Pull the id out of a "kind:id" route token.
    static func subject(of route: String?, kind: String) -> String? {
        guard let route, route.hasPrefix("\(kind):") else { return nil }
        let value = String(route.dropFirst(kind.count + 1))
        return value.isEmpty ? nil : value
    }

    private static func asInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let d = value as? Double { return Int(d) }
        return nil
    }
}

/// `POST /notifications/register` response. `preferences` is the EFFECTIVE map
/// — every kind with defaults resolved — not just what we sent.
struct NotificationRegisterResponse: Codable, Sendable {
    let preferences: [String: Bool]?
}

struct UnreadCountResponse: Codable, Sendable {
    let unread: Int?
}
