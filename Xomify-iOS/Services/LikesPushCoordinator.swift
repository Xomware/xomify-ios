import Foundation

/// Pushes the signed-in user's top-200 Spotify saved tracks to the backend
/// on cold app open. Fire-and-forget — never blocks the UI.
///
/// Dedupe: the backend short-circuits if `total` and first-track `addedAt`
/// are unchanged since the last push, so calling this on every launch is safe.
///
/// The push fires once per app process lifetime (tracked via `hasFiredThisSession`).
/// A concurrent launch won't double-fire because the flag is checked and set
/// synchronously inside the `Task` before any network I/O begins.
actor LikesPushCoordinator {

    // MARK: - Singleton

    static let shared = LikesPushCoordinator()

    private init() {}

    // MARK: - State

    private var hasFiredThisSession: Bool = false

    // MARK: - Constants

    private static let maxTracks = 200
    private static let pageSize  = 50    // Spotify page cap

    // MARK: - Public API

    /// Call from `MainShell.task` (or equivalent cold-open hook) after auth
    /// resolves. Returns immediately — all I/O runs in a detached task.
    nonisolated func triggerIfNeeded(
        spotifyService: SpotifyLikesProviding = SpotifyService.shared,
        xomifyService: XomifyService = XomifyService.shared
    ) {
        Task.detached(priority: .utility) {
            await self.fire(spotifyService: spotifyService, xomifyService: xomifyService)
        }
    }

    // MARK: - Private

    private func fire(
        spotifyService: SpotifyLikesProviding,
        xomifyService: XomifyService
    ) async {
        // One push per process lifetime.
        guard !hasFiredThisSession else { return }
        hasFiredThisSession = true

        do {
            // Resolve the caller's email via Spotify.
            let user = try await SpotifyService.shared.getCurrentUser()
            guard let email = user.email, !email.isEmpty else { return }

            // Fetch the total count first (limit=1 is cheapest).
            let firstPage = try await spotifyService.getSavedTracks(limit: 1, offset: 0)
            guard let total = firstPage.total, total > 0 else { return }

            // Paginate up to maxTracks (200), 50 per page → max 4 calls.
            let pagesToFetch = Int(ceil(Double(min(total, Self.maxTracks)) / Double(Self.pageSize)))
            var allTracks: [LikesPushTrack] = []

            for page in 0..<pagesToFetch {
                let offset = page * Self.pageSize
                let remaining = min(Self.maxTracks, total) - offset
                guard remaining > 0 else { break }
                let limit = min(Self.pageSize, remaining)

                let response = try await spotifyService.getSavedTracks(limit: limit, offset: offset)
                let pushTracks: [LikesPushTrack] = response.items.compactMap { saved -> LikesPushTrack? in
                    let track = saved.track
                    guard !track.id.isEmpty else { return nil }
                    let albumArt = track.album?.images?.first?.url
                    let artist = track.artists.compactMap { $0.name }.first ?? ""
                    return LikesPushTrack(
                        trackId: track.id,
                        addedAt: saved.addedAt,
                        name: track.name,
                        artist: artist,
                        albumArt: albumArt
                    )
                }
                allTracks.append(contentsOf: pushTracks)
            }

            guard !allTracks.isEmpty else { return }

            _ = try await xomifyService.pushUserLikes(
                email: email,
                total: total,
                tracks: allTracks
            )

            print("✅ LikesPushCoordinator: pushed \(allTracks.count) tracks (total: \(total))")
        } catch {
            // Non-critical — backend may not yet have the route (infra in progress).
            print("⚠️ LikesPushCoordinator: push failed — \(error)")
        }
    }
}
