import Foundation

/// Loads the signed-in user's full Spotify saved-tracks library in paginated
/// 50-track pages so the Likes tab can display an infinite-scroll list with
/// a total count chip.
///
/// Self-only: `/me/tracks` is scoped to the authenticated user.
@Observable
@MainActor
final class ProfileLikesViewModel {

    // MARK: - State

    private(set) var tracks: [SpotifyTrack] = []
    private(set) var total: Int?
    private(set) var offset: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var isLoadingMore: Bool = false
    var errorMessage: String?

    var hasMore: Bool {
        guard let total else { return false }
        return tracks.count < total
    }

    private var hasLoaded: Bool = false
    private static let pageSize = 50

    // MARK: - Dependencies

    private let spotifyService: SpotifyLikesProviding

    init(spotifyService: SpotifyLikesProviding = SpotifyService.shared) {
        self.spotifyService = spotifyService
    }

    // MARK: - Load

    /// Initial load — no-ops while in flight or already loaded.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await fetchPage(reset: true)
    }

    /// Force a fresh fetch from page 0. Used by pull-to-refresh.
    func refresh() async {
        guard !isLoading else { return }
        await fetchPage(reset: true)
    }

    /// Append the next page. No-ops if already loading more or no more pages.
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
            offset = 0
            total = nil
        } else {
            isLoadingMore = true
        }

        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let response = try await spotifyService.getSavedTracks(
                limit: Self.pageSize,
                offset: offset
            )
            total = response.total
            let newTracks = response.items.map { $0.track }
            tracks.append(contentsOf: newTracks)
            offset += newTracks.count
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
            if reset { tracks = [] }
        }
    }
}

/// Narrow protocol for unit-testing without standing up the full
/// `SpotifyService` actor.
protocol SpotifyLikesProviding: Sendable {
    func getSavedTracks(limit: Int, offset: Int) async throws -> SavedTracksResponse
}

extension SpotifyService: SpotifyLikesProviding {}
