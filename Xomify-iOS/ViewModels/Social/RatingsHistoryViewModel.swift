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

    // MARK: - Dependencies

    private let spotifyService = SpotifyService.shared
    private let xomifyService = XomifyService.shared

    // MARK: - Actions

    /// Load all ratings for the current Spotify user. Safe to call from `.task` and `.refreshable`.
    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let user = try await spotifyService.getCurrentUser()
            guard let email = user.email, !email.isEmpty else {
                errorMessage = "Could not load ratings — missing email."
                isLoading = false
                return
            }

            let response = try await xomifyService.getAllRatings(email: email)
            let loaded = response.ratings ?? []
            ratings = loaded.sorted(by: Self.isMoreRecent)
            print("✅ RatingsHistory: loaded \(ratings.count) ratings")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ RatingsHistory: load failed - \(error)")
        }

        isLoading = false
    }

    /// Optimistically remove a rating. On error, re-insert at original index and surface the message.
    func delete(_ rating: TrackRating) async {
        guard let index = ratings.firstIndex(where: { $0.trackId == rating.trackId }) else { return }

        let removed = ratings.remove(at: index)

        do {
            let user = try await spotifyService.getCurrentUser()
            guard let email = user.email, !email.isEmpty else {
                ratings.insert(removed, at: index)
                errorMessage = "Could not delete rating — missing email."
                return
            }
            _ = try await xomifyService.removeRating(email: email, trackId: rating.trackId)
            print("🗑️ RatingsHistory: removed rating for \(rating.trackId)")
        } catch {
            ratings.insert(removed, at: index)
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
