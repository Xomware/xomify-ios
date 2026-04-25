import Foundation

/// Loads the signed-in user's last-25 liked tracks and last-25 recently
/// played tracks from Spotify so the Recent tab on Profile can offer a
/// quick "what was I just into?" surface — Dom's ask: easy way to find
/// songs to add to the feed without leaving the app.
///
/// Both endpoints are best-effort; one failing doesn't block the other.
@Observable
@MainActor
final class ProfileRecentViewModel {

    // MARK: - State

    var likedTracks: [SpotifyTrack] = []
    var recentlyPlayed: [SpotifyTrack] = []

    var isLoading: Bool = false
    var likedError: String?
    var recentError: String?

    private var hasLoaded: Bool = false

    // MARK: - Dependencies

    private let spotifyService: SpotifyRecentProviding

    init(spotifyService: SpotifyRecentProviding = SpotifyService.shared) {
        self.spotifyService = spotifyService
    }

    // MARK: - Load

    /// Run both fetches in parallel. Re-entrant safe — no-ops while in flight,
    /// and uses `hasLoaded` so `.task` doesn't re-fetch on every tab switch.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load()
    }

    /// Force a fresh fetch (used by pull-to-refresh).
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        likedError = nil
        recentError = nil
        defer { isLoading = false }

        async let likedTask: [SpotifySavedTrack] = fetchLiked()
        async let recentTask: [SpotifyPlayHistory] = fetchRecent()

        do {
            likedTracks = try await likedTask.map { $0.track }
        } catch {
            likedError = error.localizedDescription
            likedTracks = []
        }

        do {
            recentlyPlayed = try await recentTask.map { $0.track }
        } catch {
            recentError = error.localizedDescription
            recentlyPlayed = []
        }

        hasLoaded = true
    }

    private func fetchLiked() async throws -> [SpotifySavedTrack] {
        try await spotifyService.getSavedTracks(limit: 25)
    }

    private func fetchRecent() async throws -> [SpotifyPlayHistory] {
        try await spotifyService.getRecentlyPlayed(limit: 25)
    }
}

/// Narrow protocol so the VM can be unit-tested without standing up the full
/// `SpotifyService` actor. Mirrors the pattern other Profile VMs use.
protocol SpotifyRecentProviding: Sendable {
    func getSavedTracks(limit: Int) async throws -> [SpotifySavedTrack]
    func getRecentlyPlayed(limit: Int) async throws -> [SpotifyPlayHistory]
}

extension SpotifyService: SpotifyRecentProviding {}
