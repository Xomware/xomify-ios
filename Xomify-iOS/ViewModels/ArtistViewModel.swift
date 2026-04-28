import Foundation

/// ViewModel backing `ArtistView`. Owns the parallel-fetch of artist details,
/// top tracks, albums, and singles, plus follow state. Mirrors the web
/// `artist-profile` page: dedupes albums by name (preferring `album_type ==
/// "album"` on collisions, since the same record often appears as both album
/// and single across markets) and sorts each list by `releaseDate` desc.
///
/// Spotify orders within each `include_groups` value rather than across, so
/// "albums" and "singles" are fetched in separate calls instead of a single
/// mixed request — keeps the lists correctly grouped before our local sort.
@Observable
@MainActor
final class ArtistViewModel {

    // MARK: - State

    var artist: SpotifyArtist?
    var topTracks: [SpotifyTrack] = []
    var albums: [SpotifyAlbum] = []
    var singles: [SpotifyAlbum] = []
    var isFollowing = false
    var isLoading = true
    var isTogglingFollow = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let spotifyService: SpotifyService

    init(spotifyService: SpotifyService = .shared) {
        self.spotifyService = spotifyService
    }

    // MARK: - Loading

    func load(artistId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch artist core record first so the header can render even if
            // a downstream request stalls or fails.
            artist = try await spotifyService.getArtist(id: artistId)

            // Spotify orders within each include_groups value, not across the
            // whole result set. Two separate calls keep "albums" and
            // "singles" correctly grouped before we apply our own sort.
            async let tracksData = spotifyService.getArtistTopTracks(id: artistId)
            async let albumsData = spotifyService.getArtistAlbums(id: artistId, includeGroups: ["album"], limit: 50)
            async let singlesData = spotifyService.getArtistAlbums(id: artistId, includeGroups: ["single"], limit: 50)
            async let followingData = spotifyService.isFollowing(artistIds: [artistId])

            topTracks = try await tracksData
            albums = Self.dedupedAndSorted(try await albumsData)
            singles = Self.dedupedAndSorted(try await singlesData)

            let followingStatus = try await followingData
            isFollowing = followingStatus.first ?? false

            print("✅ ArtistViewModel: Loaded '\(artist?.name ?? "")' - \(topTracks.count) tracks, \(albums.count) albums, \(singles.count) singles")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ ArtistViewModel: Error - \(error)")
        }

        isLoading = false
    }

    // MARK: - Follow

    func toggleFollow(artistId: String) async {
        guard !isTogglingFollow else { return }
        isTogglingFollow = true

        do {
            if isFollowing {
                try await spotifyService.unfollowArtist(id: artistId)
                isFollowing = false
            } else {
                try await spotifyService.followArtist(id: artistId)
                isFollowing = true
            }
        } catch {
            print("❌ ArtistViewModel: Failed to toggle follow - \(error)")
        }

        isTogglingFollow = false
    }

    // MARK: - Helpers

    /// Dedupes by lowercased name, preferring `albumType == "album"` over
    /// other types when names collide (same logic as the web client). Sorts
    /// the result by `releaseDate` desc; missing dates sort last.
    static func dedupedAndSorted(_ items: [SpotifyAlbum]) -> [SpotifyAlbum] {
        var byName: [String: SpotifyAlbum] = [:]
        for item in items {
            let key = item.name.lowercased()
            if let existing = byName[key] {
                // Prefer the entry tagged as a full album, otherwise prefer
                // the one with the more recent release date.
                let existingIsAlbum = existing.albumType?.lowercased() == "album"
                let candidateIsAlbum = item.albumType?.lowercased() == "album"
                if candidateIsAlbum && !existingIsAlbum {
                    byName[key] = item
                } else if candidateIsAlbum == existingIsAlbum,
                          (item.releaseDate ?? "") > (existing.releaseDate ?? "") {
                    byName[key] = item
                }
            } else {
                byName[key] = item
            }
        }
        return byName.values.sorted { lhs, rhs in
            (lhs.releaseDate ?? "") > (rhs.releaseDate ?? "")
        }
    }
}
