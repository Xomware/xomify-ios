import Foundation

/// Drives the drawer-resident Ratings History screen.
/// Fetches the authenticated user's ratings from Xomify and supports optimistic deletion.
@Observable
@MainActor
final class RatingsHistoryViewModel {

    // MARK: - Published state

    var ratings: [TrackRating] = []
    var isLoading = false
    var errorMessage: String?

    /// Cover art URL per `trackId`. Resolved lazily after ratings load via
    /// the Spotify `GET /tracks` batch endpoint. Views fall back to a gradient
    /// placeholder when a key is missing.
    var artworkByTrackId: [String: URL] = [:]

    // MARK: - Dependencies

    private let spotifyService = SpotifyService.shared
    private let xomifyService = XomifyService.shared

    // MARK: - Actions

    /// Load all ratings for the current Spotify user. Safe to call from `.task` and `.refreshable`.
    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            // Ratings are scoped server-side by the Xomify JWT — no Spotify
            // user lookup needed here.
            let response = try await xomifyService.getAllRatings()
            let loaded = response.ratings ?? []
            ratings = loaded.sorted(by: Self.isMoreRecent)
            print("✅ RatingsHistory: loaded \(ratings.count) ratings")
            await resolveArtwork()
        } catch {
            errorMessage = error.localizedDescription
            print("❌ RatingsHistory: load failed - \(error)")
        }

        isLoading = false
    }

    /// Fetch album art for every rated track via Spotify's batch tracks
    /// endpoint. Skips ids already resolved. Best-effort — errors are logged
    /// and the view falls back to gradient placeholders.
    private func resolveArtwork() async {
        let missing = ratings.map(\.trackId).filter { !$0.isEmpty && artworkByTrackId[$0] == nil }
        guard !missing.isEmpty else { return }

        do {
            let tracks = try await spotifyService.getTracks(ids: missing)
            for track in tracks {
                if let url = track.imageUrl {
                    artworkByTrackId[track.id] = url
                }
            }
        } catch {
            print("⚠️ RatingsHistory: artwork fetch failed - \(error)")
        }
    }

    /// Optimistically remove a rating. On error, re-insert at original index and surface the message.
    func delete(_ rating: TrackRating) async {
        guard let index = ratings.firstIndex(where: { $0.trackId == rating.trackId }) else { return }

        let removed = ratings.remove(at: index)

        do {
            // Deletion is authorized server-side by the Xomify JWT — no Spotify
            // user lookup needed here.
            _ = try await xomifyService.removeRating(trackId: rating.trackId)
            print("🗑️ RatingsHistory: removed rating for \(rating.trackId)")
        } catch {
            // Clamp: the list may have shrunk further (another delete) while
            // the network call was in flight, so the original index can now be
            // past the end. Inserting there would trap.
            ratings.insert(removed, at: min(index, ratings.count))
            errorMessage = "Could not delete rating: \(error.localizedDescription)"
            print("❌ RatingsHistory: delete failed - \(error)")
        }
    }

    // MARK: - Sorting

    /// Most-recent first. Tiebreak on track name ascending.
    private static func isMoreRecent(_ lhs: TrackRating, _ rhs: TrackRating) -> Bool {
        let lhsDate = lhs.updatedAt ?? lhs.createdAt ?? ""
        let rhsDate = rhs.updatedAt ?? rhs.createdAt ?? ""
        if lhsDate == rhsDate {
            return (lhs.trackName ?? "") < (rhs.trackName ?? "")
        }
        return lhsDate > rhsDate
    }
}
