import Foundation

/// ViewModel for the Profile screen.
/// Scope: identity (name, email, avatar) + social counts (followers, following).
/// Settings items (enrollment, account details, logout) live in `SettingsViewModel`.
@Observable
@MainActor
final class ProfileViewModel {

    // MARK: - Properties

    var user: SpotifyUser?
    var isLoading = false
    var errorMessage: String?

    /// Number of artists the user follows on Spotify.
    var followingCount = 0

    private let spotifyService = SpotifyService.shared

    // MARK: - Computed

    var displayName: String  { user?.displayName ?? "User" }
    var email: String        { user?.email ?? "" }
    var profileImageUrl: URL? { user?.profileImageUrl }
    var followersCount: Int  { user?.followers?.total ?? 0 }

    // MARK: - Actions

    func loadProfile() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            user = try await spotifyService.getCurrentUser()

            let followedArtists = try await spotifyService.getFollowedArtists()
            followingCount = followedArtists.count

            print("✅ Profile: loaded — \(displayName), following \(followingCount) artists")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Profile: error loading — \(error)")
        }

        isLoading = false
    }
}
