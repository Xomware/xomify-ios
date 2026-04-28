import Foundation

// MARK: - User

struct SpotifyUser: Codable, Identifiable, Sendable {
    let id: String?
    let displayName: String?
    let email: String?
    let images: [SpotifyImage]?
    let followers: Followers?
    let country: String?
    let product: String?
    let externalUrls: [String: String]?
    
    var profileImageUrl: URL? {
        guard let urlString = images?.first?.url else { return nil }
        return URL(string: urlString)
    }
    
    struct Followers: Codable, Sendable {
        let total: Int?
    }
}

// MARK: - Image

struct SpotifyImage: Codable, Sendable {
    let url: String
    let height: Int?
    let width: Int?
}

// MARK: - Track

struct SpotifyTrack: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let uri: String?
    let durationMs: Int
    let explicit: Bool?
    let popularity: Int?
    let previewUrl: String?
    let album: SpotifyAlbum?
    let artists: [SpotifyArtist]
    let externalUrls: [String: String]?
    
    var imageUrl: URL? {
        guard let urlString = album?.images?.first?.url else { return nil }
        return URL(string: urlString)
    }
    
    var artistNames: String {
        artists.map { $0.name }.joined(separator: ", ")
    }
    
    var duration: String {
        let minutes = durationMs / 60000
        let seconds = (durationMs % 60000) / 1000
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Album

struct SpotifyAlbum: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let uri: String?
    let albumType: String?
    let totalTracks: Int?
    let releaseDate: String?
    let releaseDatePrecision: String?
    let images: [SpotifyImage]?
    let artists: [SpotifyArtist]?
    let externalUrls: [String: String]?
    
    var imageUrl: URL? {
        guard let urlString = images?.first?.url else { return nil }
        return URL(string: urlString)
    }
    
    var artistNames: String {
        artists?.map { $0.name }.joined(separator: ", ") ?? ""
    }
    
    var year: String? {
        guard let date = releaseDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }
}

// MARK: - Artist

struct SpotifyArtist: Codable, Identifiable, Sendable {
    let id: String?
    let name: String
    let uri: String?
    let genres: [String]?
    let popularity: Int?
    let followers: SpotifyUser.Followers?
    let images: [SpotifyImage]?
    let externalUrls: [String: String]?
    
    var imageUrl: URL? {
        guard let urlString = images?.first?.url else { return nil }
        return URL(string: urlString)
    }
}

// MARK: - Playlist

struct SpotifyPlaylist: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let uri: String?
    let images: [SpotifyImage]?
    let owner: PlaylistOwner?
    let tracks: PlaylistTracks?
    let isPublic: Bool?
    let collaborative: Bool?
    let externalUrls: [String: String]?
    
    var imageUrl: URL? {
        guard let urlString = images?.first?.url else { return nil }
        return URL(string: urlString)
    }
    
    struct PlaylistOwner: Codable, Sendable {
        let id: String
        let displayName: String?
    }
    
    struct PlaylistTracks: Codable, Sendable {
        let total: Int?
    }
}

// MARK: - Response Types

struct TopTracksResponse: Codable, Sendable {
    let items: [SpotifyTrack]
    let total: Int
    let limit: Int
    let offset: Int
}

struct TopArtistsResponse: Codable, Sendable {
    let items: [SpotifyArtist]
    let total: Int
    let limit: Int
    let offset: Int
}

struct FollowingArtistsResponse: Codable, Sendable {
    let artists: ArtistsPage
    
    struct ArtistsPage: Codable, Sendable {
        let items: [SpotifyArtist]
        let total: Int?
        let limit: Int
        let next: String?
        let cursors: Cursors?
        
        struct Cursors: Codable, Sendable {
            let after: String?
            let before: String?
        }
    }
}

struct ArtistAlbumsResponse: Codable, Sendable {
    let items: [SpotifyAlbum]
    let total: Int
    let limit: Int
    let offset: Int
    let next: String?
}

struct MultipleAlbumsResponse: Codable, Sendable {
    let albums: [SpotifyAlbum?]
}

struct MultipleArtistsResponse: Codable, Sendable {
    let artists: [SpotifyArtist?]
}

struct ArtistTopTracksResponse: Codable, Sendable {
    let tracks: [SpotifyTrack]
}

struct AlbumTracksResponse: Codable, Sendable {
    let items: [SpotifyTrack]
    let total: Int
    let limit: Int
    let offset: Int
}

struct MultipleTracksResponse: Codable, Sendable {
    let tracks: [SpotifyTrack?]
}

/// `/me/tracks` response item — wraps a `SpotifyTrack` with the date the user
/// hearted it. `addedAt` decodes from snake-case `added_at` thanks to the
/// network layer's `convertFromSnakeCase` policy.
struct SpotifySavedTrack: Codable, Sendable {
    let addedAt: String?
    let track: SpotifyTrack
}

struct SavedTracksResponse: Codable, Sendable {
    let items: [SpotifySavedTrack]
    let total: Int?
    let limit: Int?
    let offset: Int?
}

/// `/me/player/recently-played` response item — track + playback context +
/// when it was played.
struct SpotifyPlayHistory: Codable, Sendable {
    let track: SpotifyTrack
    let playedAt: String?
}

struct RecentlyPlayedResponse: Codable, Sendable {
    let items: [SpotifyPlayHistory]
    let next: String?
    let limit: Int?
    /// Cursor for backwards pagination. `before` is a string-encoded epoch
    /// timestamp (ms) — pass it as `before=` to get history older than that point.
    let cursors: RecentlyPlayedCursors?

    struct RecentlyPlayedCursors: Codable, Sendable {
        let before: String?
        let after: String?
    }
}

struct SearchResponse: Codable, Sendable {
    let tracks: SearchTracks?
    let artists: SearchArtists?
    let albums: SearchAlbums?

    struct SearchTracks: Codable, Sendable {
        let items: [SpotifyTrack]
        let total: Int
    }

    struct SearchArtists: Codable, Sendable {
        let items: [SpotifyArtist]
        let total: Int
    }

    struct SearchAlbums: Codable, Sendable {
        let items: [SpotifyAlbum]
        let total: Int
    }
}

/// Public alias used by `SearchView`. The underlying envelope is the same as
/// `SearchResponse` — `tracks` / `artists` / `albums` are each optional and the
/// container matching the requested `SearchType` is populated.
typealias SearchResults = SearchResponse

/// Single-type search filter for `SpotifyService.search(query:type:limit:)`.
/// Raw values match Spotify's `/search?type=` parameter values.
enum SearchType: String, CaseIterable, Hashable, Sendable {
    case track
    case artist
    case album

    /// User-facing pluralised label for the segmented picker.
    var pluralLabel: String {
        switch self {
        case .track:  return "Tracks"
        case .artist: return "Artists"
        case .album:  return "Albums"
        }
    }
}

struct PlaylistSnapshotResponse: Codable, Sendable {
    let snapshotId: String?
    
    enum CodingKeys: String, CodingKey {
        case snapshotId = "snapshot_id"
    }
}

struct PlaylistsResponse: Codable, Sendable {
    let items: [SpotifyPlaylist]
    let total: Int
    let limit: Int
    let offset: Int
}

/// A page of /playlists/{id}/tracks. `track` is optional because Spotify can
/// return `null` for removed/unplayable tracks.
struct PlaylistTracksResponse: Codable, Sendable {
    let items: [PlaylistTrackItem]?
    let total: Int?
    let limit: Int?
    let offset: Int?
}

struct PlaylistTrackItem: Codable, Sendable {
    let track: SpotifyTrack?
    let addedAt: String?
}

// MARK: - Time Range

enum TimeRange: String, CaseIterable, Sendable {
    case shortTerm = "short_term"
    case mediumTerm = "medium_term"
    case longTerm = "long_term"
    
    var displayName: String {
        switch self {
        case .shortTerm: return "Last 4 Weeks"
        case .mediumTerm: return "Last 6 Months"
        case .longTerm: return "All Time"
        }
    }
}
