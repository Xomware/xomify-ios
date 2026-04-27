import Foundation

/// Tab identifier for the segmented control on `ProfileView`.
enum ProfileTab: String, CaseIterable, Hashable, Sendable {
    case shares
    case ratings
    case taste
    case playlists
    /// Last-10 recently played tracks from Spotify. Self-only because the
    /// underlying endpoint is scoped to the authenticated user.
    /// A "See all" CTA deep-links to the top-level Recently Played destination.
    case recent

    var title: String {
        switch self {
        case .shares:    return "Posts"
        case .ratings:   return "Ratings"
        case .taste:     return "Taste"
        case .playlists: return "Playlists"
        case .recent:    return "Recent"
        }
    }

    /// SF Symbol used in the compact tab picker. Pinned to a filled glyph
    /// for the active pill's legibility on the gradient background.
    var systemImage: String {
        switch self {
        case .shares:    return "bubble.left.and.bubble.right.fill"
        case .ratings:   return "star.fill"
        case .taste:     return "waveform"
        case .playlists: return "music.note.list"
        case .recent:    return "clock.arrow.circlepath"
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
    /// Total liked songs count — self-only. Nil until loaded; chip hides when nil.
    var likesCount: Int?

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
    private var _playlistsVM: ProfilePlaylistsViewModel?

    /// Tabs visible for this profile's context. `.playlists` surfaces the
    /// signed-in user's Spotify playlists for `.me`, and the friend's public
    /// playlists for `.other` once the `FriendProfile` payload has loaded.
    /// `.recent` is self-only because the underlying Spotify endpoint is
    /// scoped to the authenticated user. Likes has moved to the sidebar.
    var visibleTabs: [ProfileTab] {
        switch context {
        case .me:    return [.shares, .ratings, .taste, .playlists, .recent]
        case .other: return [.shares, .ratings, .taste, .playlists]
        }
    }

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

    /// Lazy accessor for the Playlists tab view model. In `.me` context
    /// returns a fetch-backed VM; in `.other` context, seeds the VM from
    /// `FriendProfile.playlists` and runs in read-only mode.
    func playlistsViewModel() -> ProfilePlaylistsViewModel {
        if let existing = _playlistsVM { return existing }
        let vm: ProfilePlaylistsViewModel
        switch context {
        case .me:
            vm = ProfilePlaylistsViewModel()
        case .other:
            let preloaded = friendProfile?.playlists.flatMap(parsePreloadedPlaylists) ?? []
            vm = ProfilePlaylistsViewModel(preloaded: preloaded)
        }
        _playlistsVM = vm
        return vm
    }

    /// Convert the slim `FriendProfile.playlists` JSON payload (shape:
    /// `{ id, name, description, imageUrl, trackCount, uri, externalUrl }`)
    /// into `SpotifyPlaylist` values the shared Playlists tab can render.
    private func parsePreloadedPlaylists(_ values: [JSONValue]) -> [SpotifyPlaylist] {
        values.compactMap { value -> SpotifyPlaylist? in
            guard let obj = value.objectValue,
                  let id = obj["id"]?.stringValue,
                  let name = obj["name"]?.stringValue else { return nil }

            let imageUrl = obj["imageUrl"]?.stringValue
            let images: [SpotifyImage]? = imageUrl.map { [SpotifyImage(url: $0, height: nil, width: nil)] }
            let trackCount = obj["trackCount"]?.intValue ?? 0
            let external = obj["externalUrl"]?.stringValue
            let externalUrls: [String: String]? = external.map { ["spotify": $0] }

            return SpotifyPlaylist(
                id: id,
                name: name,
                description: obj["description"]?.stringValue,
                uri: obj["uri"]?.stringValue,
                images: images,
                owner: nil,
                tracks: SpotifyPlaylist.PlaylistTracks(total: trackCount),
                isPublic: true,
                collaborative: nil,
                externalUrls: externalUrls
            )
        }
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
        async let ratings: RatingsAllResponse? = try? xomifyService.getAllRatings()
        async let friends: FriendsAllResponse? = try? xomifyService.getAllFriends()
        async let shares: FeedResponse?       = try? xomifyService.getSharesByUser(
            targetEmail: callerEmail, limit: 1, before: nil
        )
        async let likedPage: SavedTracksResponse? = try? SpotifyService.shared.getSavedTracks(limit: 1, offset: 0)

        let (r, f, s, l) = await (ratings, friends, shares, likedPage)
        ratingCount = r?.totalCount ?? r?.ratings?.count
        friendCount = f?.acceptedCount ?? f?.accepted?.count
        shareCount  = s?.totalCount ?? s?.shares.count
        likesCount  = l?.total
    }

    private func loadOtherHeader(email: String) async throws {
        let profile = try await xomifyService.getFriendProfile(
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
