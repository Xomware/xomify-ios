import Foundation

/// Drives the Playlists tab on the signed-in user's profile. Two modes:
/// - `.self`: fetches `/me/playlists` from Spotify on first `load()`.
/// - `.preloaded`: hydrated from the `FriendProfile.playlists` payload —
///   read-only, `load()` is a no-op.
@Observable
@MainActor
final class ProfilePlaylistsViewModel {

    enum Mode: Sendable, Equatable {
        case me
        case preloaded
    }

    var playlists: [SpotifyPlaylist] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var searchQuery: String = ""

    let mode: Mode
    private let spotify: SpotifyService

    init(spotify: SpotifyService = .shared) {
        self.mode = .me
        self.spotify = spotify
    }

    init(preloaded: [SpotifyPlaylist]) {
        self.mode = .preloaded
        self.spotify = .shared
        self.playlists = preloaded
    }

    /// Playlists filtered by the current `searchQuery`. Empty query -> all.
    var filteredPlaylists: [SpotifyPlaylist] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return playlists }
        return playlists.filter { playlist in
            if playlist.name.lowercased().contains(query) { return true }
            if let desc = playlist.description?.lowercased(), desc.contains(query) { return true }
            return false
        }
    }

    func load() async {
        guard mode == .me else { return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            playlists = try await spotify.getUserPlaylists(limit: 50)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
