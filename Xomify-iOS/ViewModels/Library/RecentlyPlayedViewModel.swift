import Foundation

// MARK: - Protocol

/// Narrow protocol for unit-testing the top-level Recently Played VM
/// without standing up the full `SpotifyService` actor.
protocol SpotifyRecentlyPlayedProviding: Sendable {
    func getRecentlyPlayed(limit: Int, before: String?) async throws -> RecentlyPlayedResponse
}

extension SpotifyService: SpotifyRecentlyPlayedProviding {}

// MARK: - ViewModel

/// Powers the top-level Recently Played destination. Loads 50 tracks per page
/// using Spotify's cursor-based `before=` pagination (history is fetched
/// newest-first; `before` points older into the timeline).
///
/// Self-only: `/me/player/recently-played` is scoped to the authenticated user.
/// No total count is returned by Spotify, so `hasMore` is derived purely from
/// cursor presence.
@Observable
@MainActor
final class RecentlyPlayedViewModel {

    // MARK: - State

    private(set) var tracks: [SpotifyPlayHistory] = []
    private(set) var cursorBefore: String?
    private(set) var isLoading: Bool = false
    private(set) var isLoadingMore: Bool = false
    private(set) var hasMore: Bool = false
    var errorMessage: String?
    var searchQuery: String = ""

    /// Tracks filtered by `searchQuery` (case-insensitive, name + artist names).
    /// When the query is empty the full list is returned without copying.
    var filteredTracks: [SpotifyPlayHistory] {
        guard !searchQuery.isEmpty else { return tracks }
        let q = searchQuery.lowercased()
        return tracks.filter { history in
            let track = history.track
            return track.name.lowercased().contains(q)
                || track.artists.compactMap { $0.name }.joined(separator: " ").lowercased().contains(q)
        }
    }

    private var hasLoaded: Bool = false
    private static let pageSize = 50

    // MARK: - Dependencies

    private let spotifyService: SpotifyRecentlyPlayedProviding

    init(spotifyService: SpotifyRecentlyPlayedProviding = SpotifyService.shared) {
        self.spotifyService = spotifyService
    }

    // MARK: - Load

    /// Initial load — no-ops while in flight or already loaded.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await fetchPage(reset: true)
    }

    /// Force a fresh fetch. Used by pull-to-refresh.
    func refresh() async {
        guard !isLoading else { return }
        await fetchPage(reset: true)
    }

    /// Append the next page using the current `cursorBefore`. No-ops if
    /// already loading or no more pages are available.
    func loadMore() async {
        guard !isLoadingMore, !isLoading, hasMore else { return }
        await fetchPage(reset: false)
    }

    // MARK: - Private

    private func fetchPage(reset: Bool) async {
        if reset {
            isLoading = true
            errorMessage = nil
            tracks = []
            cursorBefore = nil
            hasMore = false
        } else {
            isLoadingMore = true
        }

        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let response = try await spotifyService.getRecentlyPlayed(
                limit: Self.pageSize,
                before: reset ? nil : cursorBefore
            )
            tracks.append(contentsOf: response.items)
            cursorBefore = response.cursors?.before
            hasMore = cursorBefore != nil
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
            if reset { tracks = [] }
        }
    }
}
