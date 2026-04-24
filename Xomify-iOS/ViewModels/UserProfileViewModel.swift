import Foundation

/// Tab identifier for the segmented control on `ProfileView`.
enum ProfileTab: String, CaseIterable, Hashable, Sendable {
    case shares
    case ratings
    case taste

    var title: String {
        switch self {
        case .shares:  return "Posts"
        case .ratings: return "Ratings"
        case .taste:   return "Taste"
        }
    }
}

/// Fan-out controller for the new tabbed `ProfileView`. Owns the context,
/// selected tab, and header fields; instantiates tab-specific view models
/// lazily so tab switches don't trigger re-fetches.
///
/// - `.me`     → header fields come from `SpotifyService.getCurrentUser`;
///               counts come from `XomifyService.getUserTableData` if we
///               need them later (v1 leaves self counts as zero where
///               backend doesn't expose them yet).
/// - `.other`  → header + counts come from `XomifyService.getFriendProfile`.
@Observable
@MainActor
final class UserProfileViewModel {

    // MARK: - Context

    let context: ProfileContext

    // MARK: - Selection state

    var selectedTab: ProfileTab = .shares

    // MARK: - Header state

    var displayName: String = ""
    var profileEmail: String = ""
    var avatarURL: URL?
    var shareCount: Int?
    var ratingCount: Int?
    var friendCount: Int?
    var followersCount: Int?
    var followingCount: Int?

    /// Raw `FriendProfile` payload for `.other` — retained so the Taste tab
    /// can read `topArtists` / `topSongs` / `topGenres` without a second fetch.
    var friendProfile: FriendProfile?

    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let xomifyService: XomifyServiceProtocol
    private let spotifyService: SpotifyCurrentUserProviding

    /// Signed-in user's email, resolved once on load. Required as the caller
    /// email for `/shares/user` requests.
    private(set) var callerEmail: String = ""

    // MARK: - Lazy child view models

    private var _sharesVM: SharesByUserViewModel?
    private var _ratingsVM: RatingsViewModel?

    /// `SharesByUserViewModel` scoped to the author (self or other). Created
    /// on first access and kept alive for the lifetime of this VM.
    func sharesViewModel() -> SharesByUserViewModel? {
        if let existing = _sharesVM { return existing }
        guard !callerEmail.isEmpty else { return nil }
        let target = context.email ?? callerEmail
        let vm = SharesByUserViewModel(
            callerEmail: callerEmail,
            targetEmail: target
        )
        _sharesVM = vm
        return vm
    }

    func ratingsViewModel() -> RatingsViewModel {
        if let existing = _ratingsVM { return existing }
        let vm = RatingsViewModel()
        _ratingsVM = vm
        return vm
    }

    // MARK: - Init

    init(
        context: ProfileContext,
        xomifyService: XomifyServiceProtocol = XomifyService.shared,
        spotifyService: SpotifyCurrentUserProviding = SpotifyService.shared
    ) {
        self.context = context
        self.xomifyService = xomifyService
        self.spotifyService = spotifyService
    }

    // MARK: - Loading

    /// Load header fields. Safe to call from `.task`.
    func loadHeader() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            try await resolveCallerEmail()
            switch context {
            case .me:
                try await loadSelfHeader()
            case .other(let email):
                try await loadOtherHeader(email: email)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Helpers

    private func resolveCallerEmail() async throws {
        guard callerEmail.isEmpty else { return }
        let user = try await spotifyService.getCurrentUser()
        guard let email = user.email, !email.isEmpty else {
            throw ProfileError.missingEmail
        }
        callerEmail = email
    }

    private func loadSelfHeader() async throws {
        let user = try await spotifyService.getCurrentUser()
        displayName = user.displayName ?? "You"
        profileEmail = user.email ?? callerEmail
        avatarURL = user.profileImageUrl
        followersCount = user.followers?.total

        // Populate the three header stats (Friends / Ratings / Posts) with
        // parallel fetches. Missing counts fall through to nil so the header
        // skeleton keeps working if any single call fails.
        async let ratings: RatingsAllResponse? = try? xomifyService.getAllRatings(email: callerEmail)
        async let friends: FriendsAllResponse? = try? xomifyService.getAllFriends(email: callerEmail)
        async let shares: FeedResponse?       = try? xomifyService.getSharesByUser(
            email: callerEmail, targetEmail: callerEmail, limit: 1, before: nil
        )

        let (r, f, s) = await (ratings, friends, shares)
        ratingCount = r?.totalCount ?? r?.ratings?.count
        friendCount = f?.acceptedCount ?? f?.accepted?.count
        shareCount  = s?.totalCount ?? s?.shares.count
    }

    private func loadOtherHeader(email: String) async throws {
        let profile = try await xomifyService.getFriendProfile(
            email: callerEmail,
            profileEmail: email
        )
        friendProfile = profile
        displayName = profile.displayName ?? email
        profileEmail = email
        if let avatarString = profile.avatar, let url = URL(string: avatarString) {
            avatarURL = url
        }
        shareCount = profile.shareCount
        followersCount = profile.followersCount
        followingCount = profile.followingCount
        friendCount = profile.friendsCount
    }
}

// MARK: - Errors

enum ProfileError: Error, LocalizedError {
    case missingEmail

    var errorDescription: String? {
        switch self {
        case .missingEmail: return "Could not resolve signed-in user email."
        }
    }
}
