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

// MARK: - Digest Preferences

/// UI-facing preference tuple for the Settings screen. Persisted client-side via
/// `@AppStorage`; mirrored to the backend through `registerPushToken` (upsert).
struct DigestPreferences: Codable, Sendable, Equatable {
    var queueNotificationsEnabled: Bool
    var digestEnabled: Bool

    init(queueNotificationsEnabled: Bool = true, digestEnabled: Bool = true) {
        self.queueNotificationsEnabled = queueNotificationsEnabled
        self.digestEnabled = digestEnabled
    }
}

// MARK: - Push Payload
//
// The backend's `notifications_send` lambda flattens every `customData` key
// onto the top-level APNs payload alongside `aps`. Queue-threshold pushes
// (emitted by `shares_react`) carry `shareId`, `trackId`, `trackName`,
// `artistName`, `reactorCount`. Digest pushes (emitted by `cron_shares_digest`)
// carry `count`, `windowDays`. There is no explicit `pushType` field — the
// kind must be inferred from the shape.

/// Classification of an incoming push, derived from payload shape.
enum PushKind: String, Sendable {
    case queueThreshold
    case digest
    case unknown
}

/// Strongly-typed view onto an APNs userInfo dictionary. Tolerates missing
/// fields — all optional. Use `kind` + `shareId` for routing decisions.
struct PushPayload: Sendable, Equatable {
    let kind: PushKind
    let shareId: String?
    let trackId: String?
    let reactorCount: Int?
    let count: Int?
    let windowDays: Int?

    /// Construct from a raw APNs userInfo dictionary (e.g., the
    /// `notification.request.content.userInfo` passed by UserNotifications).
    init(userInfo: [AnyHashable: Any]) {
        self.shareId = userInfo["shareId"] as? String
        self.trackId = userInfo["trackId"] as? String
        self.reactorCount = Self.asInt(userInfo["reactorCount"])
        self.count = Self.asInt(userInfo["count"])
        self.windowDays = Self.asInt(userInfo["windowDays"])

        // Kind inference:
        //  - Queue threshold pushes always carry `shareId`.
        //  - Digest pushes carry `windowDays` (no `shareId`).
        if self.shareId != nil {
            self.kind = .queueThreshold
        } else if self.windowDays != nil || self.count != nil {
            self.kind = .digest
        } else {
            self.kind = .unknown
        }
    }

    /// Direct-init for tests + call sites that already have typed fields.
    init(
        kind: PushKind,
        shareId: String? = nil,
        trackId: String? = nil,
        reactorCount: Int? = nil,
        count: Int? = nil,
        windowDays: Int? = nil
    ) {
        self.kind = kind
        self.shareId = shareId
        self.trackId = trackId
        self.reactorCount = reactorCount
        self.count = count
        self.windowDays = windowDays
    }

    private static func asInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) }
        if let d = value as? Double { return Int(d) }
        return nil
    }
}
