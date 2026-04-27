import Foundation

/// ViewModel for the Top Items / Music Taste screen.
///
/// **Sub-feature 2c (auth-identity epic)** — this VM previously fanned out
/// six direct calls to `/me/top/{tracks,artists}` against Spotify on every
/// load. It now reads from `XomifyService.getCurrentTopItems()` which
/// proxies a single backend request to `GET /user/top-items`, served from
/// a per-user, per-UTC-day cache (epic Q7). One Spotify call per user per
/// day instead of six per app launch.
///
/// Per-range partial failures are surfaced via `failedRanges` so the view
/// can render a soft retry hint for the affected term without losing the
/// data we did get.
@Observable
@MainActor
final class TopItemsViewModel {

    // MARK: - Properties

    var isLoading = false
    var errorMessage: String?

    // Tracks by term
    var shortTermTracks: [SpotifyTrack] = []
    var mediumTermTracks: [SpotifyTrack] = []
    var longTermTracks: [SpotifyTrack] = []

    // Artists by term
    var shortTermArtists: [SpotifyArtist] = []
    var mediumTermArtists: [SpotifyArtist] = []
    var longTermArtists: [SpotifyArtist] = []

    // Genres by term — backend ships weighted `{ genre: score }` per term;
    // we mirror the existing `(name, count)` tuple shape the view consumes.
    var shortTermGenres: [(name: String, count: Int)] = []
    var mediumTermGenres: [(name: String, count: Int)] = []
    var longTermGenres: [(name: String, count: Int)] = []

    /// Range names (raw values of `TimeRange`) the backend could not fetch
    /// from Spotify on the most recent load. Empty on full success.
    var failedRanges: Set<String> = []

    private let xomifyService = XomifyService.shared

    // MARK: - Actions

    func loadData() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await xomifyService.getCurrentTopItems()

            shortTermTracks  = response.tracks(for: .shortTerm)
            mediumTermTracks = response.tracks(for: .mediumTerm)
            longTermTracks   = response.tracks(for: .longTerm)

            shortTermArtists  = response.artists(for: .shortTerm)
            mediumTermArtists = response.artists(for: .mediumTerm)
            longTermArtists   = response.artists(for: .longTerm)

            shortTermGenres  = response.genres(for: .shortTerm)
            mediumTermGenres = response.genres(for: .mediumTerm)
            longTermGenres   = response.genres(for: .longTerm)

            failedRanges = Set(response.meta?.failedRanges ?? [])

            print("✅ TopItems: Loaded short=\(shortTermTracks.count) medium=\(mediumTermTracks.count) long=\(longTermTracks.count) tracks; failedRanges=\(failedRanges)")

        } catch {
            errorMessage = error.localizedDescription
            print("❌ TopItems: Error loading data - \(error)")
        }

        isLoading = false
    }

    // MARK: - Helpers

    /// `true` when the backend reported a partial Spotify failure for the
    /// given term on the most recent load.
    func didFail(term: TimeRange) -> Bool {
        failedRanges.contains(term.rawValue)
    }
}
