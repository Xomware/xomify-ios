import Foundation

/// Errors surfaced by `SpotifyService` calls that map one-to-one to a
/// user-facing recovery action (e.g. "open Spotify and play something first").
enum SpotifyServiceError: LocalizedError, Sendable, Equatable {
    /// Spotify Premium account required for the requested action.
    case premiumRequired
    /// No active Spotify device to route the action to.
    case noActiveDevice
    /// Fell through a status code we don't have a specific recovery for.
    case unexpected(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .premiumRequired:
            return "Spotify Premium is required for this action."
        case .noActiveDevice:
            return "Open Spotify on a device and play something first."
        case .unexpected(let code):
            return "Spotify returned status \(code)."
        }
    }
}

/// Service for Spotify API calls
/// Mirrors your Angular SpotifyService
actor SpotifyService {

    // MARK: - Singleton

    static let shared = SpotifyService()

    private let network = NetworkService.shared

    private init() {}
    
    // MARK: - User Profile
    
    /// Get current user's profile
    func getCurrentUser() async throws -> SpotifyUser {
        try await network.spotifyGet("/me")
    }
    
    // MARK: - Top Items
    
    /// Get user's top tracks
    func getTopTracks(timeRange: TimeRange = .shortTerm, limit: Int = 25) async throws -> [SpotifyTrack] {
        let response: TopTracksResponse = try await network.spotifyGet(
            "/me/top/tracks?time_range=\(timeRange.rawValue)&limit=\(limit)"
        )
        return response.items
    }
    
    /// Get user's top artists
    func getTopArtists(timeRange: TimeRange = .shortTerm, limit: Int = 25) async throws -> [SpotifyArtist] {
        let response: TopArtistsResponse = try await network.spotifyGet(
            "/me/top/artists?time_range=\(timeRange.rawValue)&limit=\(limit)"
        )
        return response.items
    }
    
    /// Get top tracks for all time ranges at once
    func getAllTopTracks(limit: Int = 25) async throws -> (shortTerm: [SpotifyTrack], mediumTerm: [SpotifyTrack], longTerm: [SpotifyTrack]) {
        async let short = getTopTracks(timeRange: .shortTerm, limit: limit)
        async let medium = getTopTracks(timeRange: .mediumTerm, limit: limit)
        async let long = getTopTracks(timeRange: .longTerm, limit: limit)
        
        return try await (short, medium, long)
    }
    
    /// Get top artists for all time ranges at once
    func getAllTopArtists(limit: Int = 25) async throws -> (shortTerm: [SpotifyArtist], mediumTerm: [SpotifyArtist], longTerm: [SpotifyArtist]) {
        async let short = getTopArtists(timeRange: .shortTerm, limit: limit)
        async let medium = getTopArtists(timeRange: .mediumTerm, limit: limit)
        async let long = getTopArtists(timeRange: .longTerm, limit: limit)
        
        return try await (short, medium, long)
    }
    
    // MARK: - Following
    
    /// Get all followed artists (handles pagination)
    func getFollowedArtists() async throws -> [SpotifyArtist] {
        var allArtists: [SpotifyArtist] = []
        var afterCursor: String? = nil
        
        repeat {
            var endpoint = "/me/following?type=artist&limit=50"
            if let cursor = afterCursor {
                endpoint += "&after=\(cursor)"
            }
            
            let response: FollowingArtistsResponse = try await network.spotifyGet(endpoint)
            allArtists.append(contentsOf: response.artists.items)
            afterCursor = response.artists.cursors?.after
            
        } while afterCursor != nil
        
        return allArtists
    }
    
    /// Check if following specific artists
    func isFollowing(artistIds: [String]) async throws -> [Bool] {
        let ids = artistIds.joined(separator: ",")
        return try await network.spotifyGet("/me/following/contains?type=artist&ids=\(ids)")
    }
    
    /// Follow an artist
    func followArtist(id: String) async throws {
        try await network.spotifyPut("/me/following?type=artist&ids=\(id)", body: [:])
    }
    
    /// Unfollow an artist
    func unfollowArtist(id: String) async throws {
        try await network.spotifyDelete("/me/following?type=artist&ids=\(id)")
    }
    
    // MARK: - Artists
    
    /// Get artist details
    func getArtist(id: String) async throws -> SpotifyArtist {
        try await network.spotifyGet("/artists/\(id)")
    }
    
    /// Get multiple artists
    func getArtists(ids: [String]) async throws -> [SpotifyArtist] {
        var allArtists: [SpotifyArtist] = []
        
        for chunk in ids.chunked(into: 50) {
            let idsParam = chunk.joined(separator: ",")
            let response: MultipleArtistsResponse = try await network.spotifyGet("/artists?ids=\(idsParam)")
            allArtists.append(contentsOf: response.artists.compactMap { $0 })
        }
        
        return allArtists
    }
    
    /// Get artist's albums
    func getArtistAlbums(
        id: String,
        includeGroups: [String] = ["album", "single"],
        limit: Int = 20
    ) async throws -> [SpotifyAlbum] {
        let groups = includeGroups.joined(separator: ",")
        let response: ArtistAlbumsResponse = try await network.spotifyGet(
            "/artists/\(id)/albums?include_groups=\(groups)&limit=\(limit)"
        )
        return response.items
    }
    
    /// Get artist's top tracks
    func getArtistTopTracks(id: String, market: String = "US") async throws -> [SpotifyTrack] {
        let response: ArtistTopTracksResponse = try await network.spotifyGet(
            "/artists/\(id)/top-tracks?market=\(market)"
        )
        return response.tracks
    }
    
    // MARK: - Albums
    
    /// Get album details
    func getAlbum(id: String) async throws -> SpotifyAlbum {
        try await network.spotifyGet("/albums/\(id)")
    }
    
    /// Get multiple albums
    func getAlbums(ids: [String]) async throws -> [SpotifyAlbum] {
        var allAlbums: [SpotifyAlbum] = []
        
        for chunk in ids.chunked(into: 20) {
            let idsParam = chunk.joined(separator: ",")
            let response: MultipleAlbumsResponse = try await network.spotifyGet("/albums?ids=\(idsParam)")
            allAlbums.append(contentsOf: response.albums.compactMap { $0 })
        }
        
        return allAlbums
    }
    
    /// Get album tracks
    func getAlbumTracks(id: String, limit: Int = 50) async throws -> [SpotifyTrack] {
        let response: AlbumTracksResponse = try await network.spotifyGet(
            "/albums/\(id)/tracks?limit=\(limit)"
        )
        return response.items
    }
    
    // MARK: - Library / Recently Played

    /// User's saved (liked) tracks, newest-first. Requires the
    /// `user-library-read` scope on the Spotify token.
    /// Returns the full `SavedTracksResponse` so callers can read `total` for
    /// count display and use `offset` for paginated fetches.
    func getSavedTracks(limit: Int = 50, offset: Int = 0) async throws -> SavedTracksResponse {
        try await network.spotifyGet(
            "/me/tracks?limit=\(limit)&offset=\(offset)"
        )
    }

    /// User's recently played tracks, newest-first. Requires the
    /// `user-read-recently-played` scope.
    ///
    /// - Parameters:
    ///   - limit: Number of items to return (max 50).
    ///   - before: Optional cursor (string-encoded epoch ms). When provided,
    ///     returns history older than that timestamp, enabling cursor-based
    ///     backwards pagination.
    /// - Returns: Full `RecentlyPlayedResponse` so callers can read `cursors.before`.
    func getRecentlyPlayed(limit: Int = 25, before: String? = nil) async throws -> RecentlyPlayedResponse {
        var path = "/me/player/recently-played?limit=\(limit)"
        if let before {
            path += "&before=\(before)"
        }
        return try await network.spotifyGet(path)
    }

    // MARK: - Tracks

    /// Get track details
    func getTrack(id: String) async throws -> SpotifyTrack {
        try await network.spotifyGet("/tracks/\(id)")
    }
    
    /// Get multiple tracks
    func getTracks(ids: [String]) async throws -> [SpotifyTrack] {
        var allTracks: [SpotifyTrack] = []
        
        for chunk in ids.chunked(into: 50) {
            let idsParam = chunk.joined(separator: ",")
            let response: MultipleTracksResponse = try await network.spotifyGet("/tracks?ids=\(idsParam)")
            allTracks.append(contentsOf: response.tracks.compactMap { $0 })
        }
        
        return allTracks
    }
    
    // MARK: - Playlists
    
    /// Get user's playlists.
    ///
    /// PAGES UNTIL EXHAUSTED. This used to issue one request capped at 50 and
    /// return whatever came back, so anyone with more than 50 playlists simply
    /// never saw the rest — silently, with no empty state or "load more" to
    /// hint that anything was missing. Web has always paged.
    ///
    /// `pageCap` bounds a pathological account rather than the common case;
    /// 20 pages is 1000 playlists.
    func getUserPlaylists(limit: Int = 50, pageCap: Int = 20) async throws -> [SpotifyPlaylist] {
        var all: [SpotifyPlaylist] = []
        var offset = 0

        for _ in 0..<pageCap {
            let response: PlaylistsResponse = try await network.spotifyGet(
                "/me/playlists?limit=\(limit)&offset=\(offset)"
            )
            all.append(contentsOf: response.items)
            if response.items.count < limit { break }
            offset += limit
        }
        return all
    }
    
    /// Get playlist details
    func getPlaylist(id: String) async throws -> SpotifyPlaylist {
        try await network.spotifyGet("/playlists/\(id)")
    }
    
    /// Create a playlist
    func createPlaylist(
        userId: String,
        name: String,
        description: String,
        isPublic: Bool = true
    ) async throws -> SpotifyPlaylist {
        try await network.spotifyPost(
            "/users/\(userId)/playlists",
            body: [
                "name": name,
                "description": description,
                "public": isPublic
            ]
        )
    }
    
    /// Add tracks to playlist
    func addTracksToPlaylist(playlistId: String, trackUris: [String]) async throws {
        for chunk in trackUris.chunked(into: 100) {
            let _: PlaylistSnapshotResponse = try await network.spotifyPost(
                "/playlists/\(playlistId)/tracks",
                body: ["uris": chunk]
            )
        }
    }
    
    /// Upload custom cover image to playlist
    /// The image must be a Base64 encoded JPEG image (max 256KB)
    func uploadPlaylistCover(playlistId: String, imageBase64: String) async throws {
        try await network.spotifyPutImage(
            "/playlists/\(playlistId)/images",
            imageBase64: imageBase64
        )
    }
    
    /// Get a single page of playlist tracks.
    func getPlaylistTracks(playlistId: String, limit: Int = 50, offset: Int = 0) async throws -> PlaylistTracksResponse {
        try await network.spotifyGet(
            "/playlists/\(playlistId)/tracks?limit=\(limit)&offset=\(offset)"
        )
    }

    /// Fetch every playlist track, paginating in 50-chunk pages.
    func getAllPlaylistTracks(playlistId: String) async throws -> [SpotifyTrack] {
        var all: [SpotifyTrack] = []
        var offset = 0
        let pageSize = 50

        while true {
            let page = try await getPlaylistTracks(playlistId: playlistId, limit: pageSize, offset: offset)
            let tracks = (page.items ?? []).compactMap { $0.track }
            all.append(contentsOf: tracks)

            let total = page.total ?? 0
            offset += pageSize
            if offset >= total || tracks.isEmpty { break }
        }

        return all
    }

    // MARK: - Search
    
    /// Search Spotify
    func search(
        query: String,
        types: [String] = ["track", "artist", "album"],
        limit: Int = 20
    ) async throws -> SearchResponse {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let typesParam = types.joined(separator: ",")
        return try await network.spotifyGet(
            "/search?q=\(encodedQuery)&type=\(typesParam)&limit=\(limit)"
        )
    }
    
    /// Search for tracks only
    func searchTracks(query: String, limit: Int = 20) async throws -> [SpotifyTrack] {
        let response = try await search(query: query, types: ["track"], limit: limit)
        return response.tracks?.items ?? []
    }

    /// Search for artists only
    func searchArtists(query: String, limit: Int = 20) async throws -> [SpotifyArtist] {
        let response = try await search(query: query, types: ["artist"], limit: limit)
        return response.artists?.items ?? []
    }

    /// Search for albums only
    func searchAlbums(query: String, limit: Int = 20) async throws -> [SpotifyAlbum] {
        let response = try await search(query: query, types: ["album"], limit: limit)
        return response.albums?.items ?? []
    }

    /// Single-type search for use by `SearchView`. Mirrors the existing
    /// multi-type `search(query:types:limit:)` but lets callers ask for one
    /// `SearchType` at a time and get the full `SearchResults` envelope back so
    /// the UI can read whichever container matches the requested type.
    func search(query: String, type: SearchType, limit: Int = 20) async throws -> SearchResults {
        try await search(query: query, types: [type.rawValue], limit: limit)
    }

    // MARK: - Player

    /// Queue a track on the user's active Spotify device. Requires a Premium
    /// account and an active device (otherwise throws `.premiumRequired` /
    /// `.noActiveDevice`).
    ///
    /// Docs: https://developer.spotify.com/documentation/web-api/reference/add-to-queue
    func queueTrack(uri: String) async throws {
        guard let encoded = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw SpotifyServiceError.unexpected(statusCode: 0)
        }

        let endpoint = "/me/player/queue?uri=\(encoded)"

        do {
            try await network.spotifyPostNoBody(endpoint)
        } catch let error as NetworkService.NetworkError {
            if case .serverError(let code, _) = error {
                switch code {
                case 403: throw SpotifyServiceError.premiumRequired
                case 404: throw SpotifyServiceError.noActiveDevice
                default:  throw SpotifyServiceError.unexpected(statusCode: code)
                }
            }
            throw error
        }
    }

    /// Start playback of a single track on the user's active Spotify device.
    /// Same failure mapping as `queueTrack` — Premium + active-device required.
    ///
    /// Docs: https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback
    func playTrack(uri: String) async throws {
        do {
            try await network.spotifyPut("/me/player/play", body: ["uris": [uri]])
        } catch let error as NetworkService.NetworkError {
            if case .serverError(let code, _) = error {
                switch code {
                case 403: throw SpotifyServiceError.premiumRequired
                case 404: throw SpotifyServiceError.noActiveDevice
                default:  throw SpotifyServiceError.unexpected(statusCode: code)
                }
            }
            throw error
        }
    }
}

// MARK: - Array Extension

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
