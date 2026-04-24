import Foundation

// MARK: - Analysis Results

struct ArtistCount: Sendable, Hashable {
    let id: String
    let name: String
    let count: Int
    let imageUrl: URL?
}

struct GenreCount: Sendable, Hashable {
    let genre: String
    let count: Int
}

struct DecadeCount: Sendable, Hashable {
    let decade: String
    let count: Int
}

struct PlaylistAnalysis: Sendable {
    let totalTracks: Int
    let totalDurationMs: Int
    let avgPopularity: Int
    let explicitCount: Int
    let uniqueArtistCount: Int
    let topArtists: [ArtistCount]
    let topGenres: [GenreCount]
    let decades: [DecadeCount]
    /// A handful of tracks from the playlist (preserving order) to render as
    /// a visual preview row — drives the "Sample Tracks" strip in the view.
    let sampleTracks: [SpotifyTrack]
}

/// ViewModel for the Playlist Analysis screen.
/// Fetches playlist tracks + full artist metadata via Spotify, then aggregates
/// locally (no deprecated /audio-features endpoint).
@Observable
@MainActor
final class PlaylistAnalysisViewModel {

    // MARK: - State

    var playlists: [SpotifyPlaylist] = []
    var selectedPlaylist: SpotifyPlaylist?
    var analysis: PlaylistAnalysis?

    var isLoadingPlaylists = false
    var isAnalyzing = false
    var errorMessage: String?

    private let spotify = SpotifyService.shared

    // MARK: - Load user's playlists

    func loadPlaylists() async {
        guard !isLoadingPlaylists else { return }
        isLoadingPlaylists = true
        errorMessage = nil

        do {
            playlists = try await spotify.getUserPlaylists()
        } catch {
            errorMessage = "Failed to load playlists: \(error.localizedDescription)"
            print("❌ PlaylistAnalysis: load playlists failed - \(error)")
        }

        isLoadingPlaylists = false
    }

    // MARK: - Analyze

    func analyze(_ playlist: SpotifyPlaylist) async {
        guard !isAnalyzing else { return }
        selectedPlaylist = playlist
        analysis = nil
        isAnalyzing = true
        errorMessage = nil

        do {
            let tracks = try await spotify.getAllPlaylistTracks(playlistId: playlist.id)

            // Collect unique artist ids.
            var artistIdSet = Set<String>()
            for track in tracks {
                for artist in track.artists {
                    if let id = artist.id { artistIdSet.insert(id) }
                }
            }

            // Fetch full artist metadata (for genres).
            let artists = try await spotify.getArtists(ids: Array(artistIdSet))
            analysis = aggregate(tracks: tracks, artists: artists)
        } catch {
            errorMessage = "Failed to analyze playlist: \(error.localizedDescription)"
            print("❌ PlaylistAnalysis: analyze failed - \(error)")
        }

        isAnalyzing = false
    }

    // MARK: - Aggregation

    private func aggregate(tracks: [SpotifyTrack], artists: [SpotifyArtist]) -> PlaylistAnalysis {
        let totalTracks = tracks.count
        let totalDurationMs = tracks.reduce(0) { $0 + $1.durationMs }
        let avgPopularity: Int
        if totalTracks > 0 {
            let sum = tracks.reduce(0) { $0 + ($1.popularity ?? 0) }
            avgPopularity = Int(round(Double(sum) / Double(totalTracks)))
        } else {
            avgPopularity = 0
        }
        let explicitCount = tracks.filter { $0.explicit == true }.count

        // Per-artist appearance counts.
        var artistMeta: [String: SpotifyArtist] = [:]
        for a in artists {
            if let id = a.id { artistMeta[id] = a }
        }

        var counts: [String: (name: String, count: Int)] = [:]
        for track in tracks {
            for artist in track.artists {
                guard let id = artist.id else { continue }
                let name = artistMeta[id]?.name ?? artist.name
                counts[id, default: (name, 0)].count += 1
                counts[id]?.name = name
            }
        }

        let topArtists = counts
            .map { (id, tuple) -> ArtistCount in
                ArtistCount(
                    id: id,
                    name: tuple.name,
                    count: tuple.count,
                    imageUrl: artistMeta[id]?.imageUrl
                )
            }
            .sorted { $0.count > $1.count }
            .prefix(10)

        // Genres weighted by artist appearances.
        var genreCounts: [String: Int] = [:]
        for (id, tuple) in counts {
            guard let meta = artistMeta[id], let genres = meta.genres else { continue }
            for genre in genres {
                genreCounts[genre, default: 0] += tuple.count
            }
        }
        let topGenres = genreCounts
            .map { GenreCount(genre: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(10)

        // Decades from album.release_date.
        var decadeCounts: [String: Int] = [:]
        for track in tracks {
            guard let date = track.album?.releaseDate, date.count >= 4,
                  let year = Int(date.prefix(4)) else { continue }
            let decade = "\(Int(year / 10) * 10)s"
            decadeCounts[decade, default: 0] += 1
        }
        let decades = decadeCounts
            .map { DecadeCount(decade: $0.key, count: $0.value) }
            .sorted { $0.decade < $1.decade }

        // Visual preview — first 10 tracks with artwork available.
        let sampleTracks = Array(tracks.filter { $0.imageUrl != nil }.prefix(10))

        return PlaylistAnalysis(
            totalTracks: totalTracks,
            totalDurationMs: totalDurationMs,
            avgPopularity: avgPopularity,
            explicitCount: explicitCount,
            uniqueArtistCount: counts.count,
            topArtists: Array(topArtists),
            topGenres: Array(topGenres),
            decades: decades,
            sampleTracks: sampleTracks
        )
    }

    // MARK: - Formatting

    func formattedDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
