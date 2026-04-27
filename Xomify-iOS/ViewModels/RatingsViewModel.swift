import Foundation

/// ViewModel for the Ratings screen. Lists ratings grouped by stars.
@Observable
@MainActor
final class RatingsViewModel {

    var userEmail: String = ""
    var ratings: [TrackRating] = []

    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?

    /// Cover art URL per `trackId`. Resolved after ratings load — see
    /// `RatingsHistoryViewModel` for the same pattern.
    var artworkByTrackId: [String: URL] = [:]

    private let xomify = XomifyService.shared
    private let spotify = SpotifyService.shared

    var isEmpty: Bool { ratings.isEmpty }

    /// Ratings grouped by score, highest first.
    var grouped: [(stars: Int, ratings: [TrackRating])] {
        let dict = Dictionary(grouping: ratings, by: { $0.rating })
        return dict
            .map { ($0.key, $0.value.sorted { lhs, rhs in
                (lhs.updatedAt ?? lhs.createdAt ?? "") > (rhs.updatedAt ?? rhs.createdAt ?? "")
            }) }
            .sorted { $0.0 > $1.0 }
    }

    // MARK: - Load

    func load(email: String) async {
        guard !email.isEmpty else {
            errorMessage = "Please log in first"
            return
        }
        userEmail = email
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await xomify.getAllRatings()
            ratings = response.ratings ?? []
            await resolveArtwork()
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Ratings: load failed - \(error)")
        }

        isLoading = false
    }

    private func resolveArtwork() async {
        let missing = ratings.map(\.trackId).filter { !$0.isEmpty && artworkByTrackId[$0] == nil }
        guard !missing.isEmpty else { return }

        do {
            let tracks = try await spotify.getTracks(ids: missing)
            for track in tracks {
                if let url = track.imageUrl {
                    artworkByTrackId[track.id] = url
                }
            }
        } catch {
            print("⚠️ Ratings: artwork fetch failed - \(error)")
        }
    }

    func refresh() async {
        guard !userEmail.isEmpty else { return }
        isRefreshing = true
        await load(email: userEmail)
        isRefreshing = false
    }

    // MARK: - Actions

    func delete(_ rating: TrackRating) async {
        do {
            _ = try await xomify.removeRating(trackId: rating.trackId)
            ratings.removeAll { $0.trackId == rating.trackId }
        } catch {
            errorMessage = "Failed to delete rating: \(error.localizedDescription)"
            print("❌ Ratings: delete failed - \(error)")
        }
    }
}
