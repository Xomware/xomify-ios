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

    private let xomify = XomifyService.shared

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
            let response = try await xomify.getAllRatings(email: email)
            ratings = response.ratings ?? []
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Ratings: load failed - \(error)")
        }

        isLoading = false
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
            _ = try await xomify.removeRating(email: userEmail, trackId: rating.trackId)
            ratings.removeAll { $0.trackId == rating.trackId }
        } catch {
            errorMessage = "Failed to delete rating: \(error.localizedDescription)"
            print("❌ Ratings: delete failed - \(error)")
        }
    }
}
