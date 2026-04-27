import Foundation

// MARK: - Protocol

/// Narrow protocol for unit-testing without standing up the full
/// `SpotifyService` actor.
protocol SpotifyLikesProviding: Sendable {
    func getSavedTracks(limit: Int, offset: Int) async throws -> SavedTracksResponse
}

extension SpotifyService: SpotifyLikesProviding {}

// MARK: - LikesSource

/// Where to load likes from. `.spotifyDirect` hits `/me/tracks` (self only);
/// `.backend` calls `GET /likes/by-user` for a friend's cached tracks.
enum LikesSource {
    case spotifyDirect
    case backend(callerEmail: String, targetEmail: String)
}

// MARK: - LikesTrackDisplayItem

/// Unified display model for a liked track regardless of source.
struct LikesTrackDisplayItem: Identifiable, Hashable {
    let id: String          // trackId
    let name: String
    let artistNames: String  // comma-joined
    let albumArtURL: URL?
}

// MARK: - ViewModel

/// Loads liked tracks for the signed-in user (Spotify direct) or a friend
/// (backend). Parameterised by `LikesSource` — single VM, two data paths.
///
/// Self path: paginated `/me/tracks` (unchanged from v1).
/// Friend path: paginated `GET /likes/by-user` against backend.
@Observable
@MainActor
final class LikesViewModel {

    // MARK: - State

    private(set) var items: [LikesTrackDisplayItem] = []
    /// Parallel array of raw `SpotifyTrack` — only populated on `.spotifyDirect`
    /// path so `TrackActionsMenu` (which needs the full object) keeps working.
    private(set) var spotifyTracks: [SpotifyTrack] = []
    private(set) var total: Int?
    private(set) var offset: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var isLoadingMore: Bool = false
    var errorMessage: String?
    var searchQuery: String = ""

    var hasMore: Bool {
        guard let total else { return false }
        return items.count < total
    }

    var filteredItems: [LikesTrackDisplayItem] {
        guard !searchQuery.isEmpty else { return items }
        let q = searchQuery.lowercased()
        return items.filter {
            $0.name.lowercased().contains(q) || $0.artistNames.lowercased().contains(q)
        }
    }

    private var hasLoaded: Bool = false
    private static let pageSize = 50

    // MARK: - Dependencies

    let source: LikesSource
    private let spotifyService: SpotifyLikesProviding
    private let xomifyService: XomifyServiceProtocol

    init(
        source: LikesSource = .spotifyDirect,
        spotifyService: SpotifyLikesProviding = SpotifyService.shared,
        xomifyService: XomifyServiceProtocol = XomifyService.shared
    ) {
        self.source = source
        self.spotifyService = spotifyService
        self.xomifyService = xomifyService
    }

    // MARK: - Public API

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await fetchPage(reset: true)
    }

    func refresh() async {
        guard !isLoading else { return }
        await fetchPage(reset: true)
    }

    func loadMore() async {
        guard !isLoadingMore, !isLoading, hasMore else { return }
        await fetchPage(reset: false)
    }

    // MARK: - Private

    private func fetchPage(reset: Bool) async {
        if reset {
            isLoading = true
            errorMessage = nil
            items = []
            spotifyTracks = []
            offset = 0
            total = nil
        } else {
            isLoadingMore = true
        }

        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            switch source {
            case .spotifyDirect:
                try await fetchSpotifyPage()
            case .backend(let callerEmail, let targetEmail):
                try await fetchBackendPage(callerEmail: callerEmail, targetEmail: targetEmail)
            }
        } catch {
            errorMessage = error.localizedDescription
            if reset { items = []; spotifyTracks = [] }
        }
    }

    private func fetchSpotifyPage() async throws {
        let response = try await spotifyService.getSavedTracks(
            limit: Self.pageSize,
            offset: offset
        )
        total = response.total
        let newTracks = response.items.map { $0.track }
        spotifyTracks.append(contentsOf: newTracks)
        let newItems = newTracks.map { track -> LikesTrackDisplayItem in
            let artists = track.artists.compactMap { $0.name }.joined(separator: ", ")
            let artURL: URL? = {
                guard let urlString = track.album?.images?.first?.url else { return nil }
                return URL(string: urlString)
            }()
            return LikesTrackDisplayItem(
                id: track.id,
                name: track.name,
                artistNames: artists,
                albumArtURL: artURL
            )
        }
        items.append(contentsOf: newItems)
        offset += newTracks.count
        hasLoaded = true
    }

    private func fetchBackendPage(callerEmail: String, targetEmail: String) async throws {
        // Resolve caller email if not supplied at init (LikesView passes "" as placeholder).
        var resolvedCaller = callerEmail
        if resolvedCaller.isEmpty {
            let user = try await SpotifyService.shared.getCurrentUser()
            resolvedCaller = user.email ?? ""
        }

        let response = try await xomifyService.getLikesByUser(
            email: resolvedCaller,
            targetEmail: targetEmail,
            limit: Self.pageSize,
            offset: offset
        )
        total = response.total
        let newItems = response.tracks.map { t -> LikesTrackDisplayItem in
            LikesTrackDisplayItem(
                id: t.trackId,
                name: t.trackName ?? t.trackId,
                artistNames: t.artistName ?? "",
                albumArtURL: t.albumArtURL
            )
        }
        items.append(contentsOf: newItems)
        offset += response.tracks.count
        hasLoaded = true

        if response.hasMore == false {
            // Mark exhausted — set total to current count so hasMore → false.
            if total == nil { total = items.count }
        }
    }
}
