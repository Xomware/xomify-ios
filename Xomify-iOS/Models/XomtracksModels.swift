import Foundation

// Mirrors the xomtracks-backend `Share` record from `GET /shares/list`, plus
// the enrichment those handlers attach (rating, heard, genres).
//
// Xomtracks is a SEPARATE backend from Xomify's own — it ingests the tracks
// people send you over iMessage. The in-app "Feed" this replaces read Xomify's
// `/shares/*`, which is the retired group-sharing system, so the two screens
// were showing different products entirely.

enum XtDirection: String, Codable, Sendable, CaseIterable, Identifiable {
    case incoming = "in"
    case outgoing = "out"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .incoming: return "Received"
        case .outgoing: return "Sent"
        }
    }
}

enum XtTimeWindow: String, Codable, Sendable, CaseIterable, Identifiable {
    case week
    case month
    case sixMonths = "6mo"
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week:      return "Week"
        case .month:     return "Month"
        case .sixMonths: return "6 months"
        case .all:       return "All"
        }
    }
}

enum XtMatchStatus: String, Codable, Sendable {
    case pending, matched, unmatched, manual
}

/// Whole-group rating aggregate plus the caller's own rating.
struct XtRating: Codable, Sendable, Equatable {
    /// Mean across everyone. 0 when nobody has rated.
    let avg: Double?
    let count: Int?
    /// The caller's own 1–5, 0 when they haven't rated.
    let myRating: Int?
}

struct XtShare: Codable, Sendable, Identifiable, Equatable {
    let shareId: String
    let direction: XtDirection
    let sourceUrl: String
    /// Unix epoch seconds — when the message was sent, not when we ingested it.
    let messageDate: Double?

    let sharerHandle: String?
    let sharerName: String?

    let trackTitle: String?
    let trackArtist: String?
    let albumName: String?
    let albumArtUrl: String?

    let resolvedSpotifyId: String?
    let resolvedSpotifyUri: String?
    let matchStatus: XtMatchStatus?

    /// Client-side identity for "same track" grouping, set by the backend feed.
    let trackKey: String?
    let genres: [String]?
    let rating: XtRating?
    /// The caller's own heard state. Absent means unheard.
    let heard: Bool?

    var id: String { shareId }

    var displayTitle: String { trackTitle ?? "Unknown track" }
    var displayArtist: String { trackArtist ?? "Unknown artist" }

    /// Who sent it. Falls back to the raw handle, which is a phone number or
    /// Apple ID when the contact has no name attached.
    var displaySharer: String? {
        sharerName ?? sharerHandle
    }

    var albumArt: URL? {
        guard let albumArtUrl, !albumArtUrl.isEmpty else { return nil }
        return URL(string: albumArtUrl)
    }

    var sentAt: Date? {
        guard let messageDate else { return nil }
        return Date(timeIntervalSince1970: messageDate)
    }

    /// A share is only openable in Spotify once the backend has matched it.
    var spotifyURL: URL? {
        guard let resolvedSpotifyId else { return URL(string: sourceUrl) }
        return URL(string: "https://open.spotify.com/track/\(resolvedSpotifyId)")
    }
}

struct XtSharesListResponse: Codable, Sendable {
    let shares: [XtShare]?
    let count: Int?
}

/// Every Xomtracks endpoint answers in this envelope, including on failure —
/// a non-null `error` arrives with HTTP 200, so unwrapping has to check it.
// `T: Codable` only, not `Codable & Sendable`. Under this project's default
// MainActor isolation the conformances are actor-isolated, and a Sendable
// constraint rejects them -- which is why NetworkService's generics are
// Decodable-only too.
struct XtEnvelope<T: Codable>: Codable {
    let data: T?
    let error: XtError?

    struct XtError: Codable, Sendable {
        let message: String?
        let status: Int?
    }
}

struct XtHeardState: Codable, Sendable {
    let trackKey: String?
    let heard: Bool?
}
