import Foundation

// MARK: - Items

/// One entry in a favorites list. Mirrors the backend `Item` shape from
/// `favorites_get`: `{rank, spotifyId, name, artist, imageUrl}`.
struct FavoriteItem: Codable, Sendable, Equatable, Identifiable {
    var rank: Int
    let spotifyId: String
    let name: String
    let artist: String?
    let imageUrl: String?

    /// `spotifyId` rather than `rank` — rank changes on every reorder, and a
    /// list whose identity churns as you drag it animates as delete-and-insert
    /// instead of a move.
    var id: String { spotifyId }
}

// MARK: - Categories

enum FavoriteCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case songs
    case albums
    case artists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs:   return "Songs"
        case .albums:  return "Albums"
        case .artists: return "Artists"
        }
    }

    var singular: String {
        switch self {
        case .songs:   return "song"
        case .albums:  return "album"
        case .artists: return "artist"
        }
    }

    var systemImage: String {
        switch self {
        case .songs:   return "music.note"
        case .albums:  return "square.stack"
        case .artists: return "person.wave.2"
        }
    }
}

// MARK: - Lists

/// A favorites list — either one of the three per-year "overall" lists, or a
/// user-created genre list.
struct FavoriteList: Codable, Sendable, Equatable, Identifiable {
    let listId: String
    let year: Int
    let category: FavoriteCategory
    let genreLabel: String
    var items: [FavoriteItem]

    var id: String { listId }

    /// Overall lists are keyed `overall:<category>` by the backend, which
    /// auto-creates them on first write. Custom lists carry a generated id.
    var isOverall: Bool { listId.hasPrefix("overall:") }

    /// What the UI calls it. "Overall" as a genre label is backend bookkeeping,
    /// not something to show a person.
    var displayTitle: String {
        isOverall ? category.title : genreLabel
    }
}

/// `GET /favorites/get?year=` — the whole year in one response.
struct FavoritesYear: Codable, Sendable, Equatable {
    let year: Int
    let overall: FavoritesOverall?
    let lists: [FavoriteList]?
}

struct FavoritesOverall: Codable, Sendable, Equatable {
    let songs: [FavoriteItem]?
    let albums: [FavoriteItem]?
    let artists: [FavoriteItem]?

    func items(for category: FavoriteCategory) -> [FavoriteItem] {
        switch category {
        case .songs:   return songs ?? []
        case .albums:  return albums ?? []
        case .artists: return artists ?? []
        }
    }
}

// MARK: - History

/// One rank change. `fromRank == nil` is an addition, `toRank == nil` a removal.
struct FavoriteHistoryEvent: Codable, Sendable, Equatable, Identifiable {
    let ts: String
    let spotifyId: String
    let fromRank: Int?
    let toRank: Int?

    var id: String { "\(ts)#\(spotifyId)" }

    enum Change {
        case added(to: Int)
        case moved(from: Int, to: Int)
        case removed(from: Int)
    }

    var change: Change? {
        switch (fromRank, toRank) {
        case let (nil, .some(to)):    return .added(to: to)
        case let (.some(from), nil):  return .removed(from: from)
        case let (.some(from), .some(to)) where from != to:
            return .moved(from: from, to: to)
        default:
            return nil
        }
    }
}

struct FavoriteHistoryResponse: Codable, Sendable, Equatable {
    let listId: String
    let events: [FavoriteHistoryEvent]?
}

// MARK: - Recommendations

struct FavoriteRecommendations: Codable, Sendable, Equatable {
    let items: [FavoriteItem]?
}
