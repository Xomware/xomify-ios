import Foundation

/// Drives the Playlists tab on the signed-in user's profile. Fetches
/// `/me/playlists` from Spotify and holds a simple search filter — mirrors
/// the web app's My Playlists page at a profile-tab scope.
@Observable
@MainActor
final class ProfilePlaylistsViewModel {

    var playlists: [SpotifyPlaylist] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var searchQuery: String = ""

    private let spotify: SpotifyService

    init(spotify: SpotifyService = .shared) {
        self.spotify = spotify
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
