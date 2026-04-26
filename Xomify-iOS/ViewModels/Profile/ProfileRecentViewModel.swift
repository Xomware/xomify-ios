import Foundation

/// Loads the signed-in user's last-25 recently played tracks from Spotify
/// so the Recent tab on Profile can offer a quick "what was I just listening
/// to?" surface — easy way to find songs to share to the feed without
/// leaving the app.
///
/// Liked songs have moved to the dedicated Likes tab (`ProfileLikesViewModel`).
@Observable
@MainActor
final class ProfileRecentViewModel {

    // MARK: - State

    var recentlyPlayed: [SpotifyTrack] = []

    var isLoading: Bool = false
    var recentError: String?

    private var hasLoaded: Bool = false

    // MARK: - Dependencies

    private let spotifyService: SpotifyRecentProviding

    init(spotifyService: SpotifyRecentProviding = SpotifyService.shared) {
        self.spotifyService = spotifyService
    }

    // MARK: - Load

    /// Run the fetch. Re-entrant safe — no-ops while in flight, and uses
    /// `hasLoaded` so `.task` doesn't re-fetch on every tab switch.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load()
    }

    /// Force a fresh fetch (used by pull-to-refresh).
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        recentError = nil
        defer { isLoading = false }

        do {
            let response = try await spotifyService.getRecentlyPlayed(limit: 25, before: nil)
            recentlyPlayed = response.items.map { $0.track }
        } catch {
            recentError = error.localizedDescription
            recentlyPlayed = []
        }

        hasLoaded = true
    }
}

/// Narrow protocol so the VM can be unit-tested without standing up the full
/// `SpotifyService` actor. Mirrors the pattern other Profile VMs use.
protocol SpotifyRecentProviding: Sendable {
    func getRecentlyPlayed(limit: Int, before: String?) async throws -> RecentlyPlayedResponse
}

extension SpotifyService: SpotifyRecentProviding {}
