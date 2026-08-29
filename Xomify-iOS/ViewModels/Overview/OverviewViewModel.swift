import Foundation

/// Drives the Overview screen — the app's landing page.
///
/// Composes what other screens already load rather than adding endpoints:
/// recently-played from Spotify, and top items from the backend's cached
/// `/user/top-items`. Nothing here is a new network contract.
@Observable
@MainActor
final class OverviewViewModel {

    private(set) var recentlyPlayed: [SpotifyPlayHistory] = []
    private(set) var topTracks: [SpotifyTrack] = []
    private(set) var topArtists: [SpotifyArtist] = []
    private(set) var isLoading = true

    /// Each section reports its own failure. A dashboard that blanks entirely
    /// because one of three calls failed is worse than one that shows what it
    /// has and says which part is missing.
    private(set) var recentlyPlayedFailed = false
    private(set) var topItemsFailed = false

    private let spotifyService: SpotifyService
    private let topItems: TopItemsViewModel

    // TopItemsViewModel is @MainActor, so it cannot be constructed in a
    // default argument -- those are evaluated in a nonisolated context.
    init(
        spotifyService: SpotifyService = SpotifyService.shared,
        topItems: TopItemsViewModel? = nil
    ) {
        self.spotifyService = spotifyService
        self.topItems = topItems ?? TopItemsViewModel()
    }

    /// Greeting that matches the user's clock, not a fixed "Welcome back".
    var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:     return "Good evening"
        }
    }

    var isEmpty: Bool {
        recentlyPlayed.isEmpty && topTracks.isEmpty && topArtists.isEmpty
    }

    func load() async {
        isLoading = true
        recentlyPlayedFailed = false
        topItemsFailed = false

        // Concurrently: the two sources are unrelated, and serialising them
        // would make the landing screen as slow as their sum.
        async let recent: Void = loadRecentlyPlayed()
        async let top: Void = loadTopItems()
        _ = await (recent, top)

        isLoading = false
    }

    private func loadRecentlyPlayed() async {
        do {
            // 12 is what the row can show after de-duplication; asking for more
            // costs the same request but more decoding.
            let response = try await spotifyService.getRecentlyPlayed(limit: 20)
            var seen = Set<String>()
            recentlyPlayed = response.items.filter { seen.insert($0.track.id).inserted }
        } catch {
            print("[Overview] recently played failed: \(error)")
            recentlyPlayedFailed = true
        }
    }

    private func loadTopItems() async {
        await topItems.loadData()
        if topItems.errorMessage != nil {
            topItemsFailed = true
            return
        }
        // Short term is "the last four weeks" -- the only range that belongs on
        // a page about right now.
        topTracks = Array(topItems.shortTermTracks.prefix(10))
        topArtists = Array(topItems.shortTermArtists.prefix(10))
    }
}
