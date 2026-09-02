import Foundation

/// ViewModel for the Top Items / Music Taste screen.
///
/// **Sub-feature 2c (auth-identity epic)** — this VM previously fanned out
/// six direct calls to `/me/top/{tracks,artists}` against Spotify on every
/// load. It now reads from `XomifyService.getCurrentTopItems()` which
/// proxies a single backend request to `GET /user/top-items`, served from
/// a per-user, per-UTC-day cache (epic Q7). One Spotify call per user per
/// day instead of six per app launch.
///
/// Per-range partial failures are surfaced via `failedRanges` so the view
/// can render a soft retry hint for the affected term without losing the
/// data we did get.
@Observable
@MainActor
final class TopItemsViewModel {

    // MARK: - Properties

    var isLoading = false
    var errorMessage: String?

    // Tracks by term
    var shortTermTracks: [SpotifyTrack] = []
    var mediumTermTracks: [SpotifyTrack] = []
    var longTermTracks: [SpotifyTrack] = []

    // Artists by term
    var shortTermArtists: [SpotifyArtist] = []
    var mediumTermArtists: [SpotifyArtist] = []
    var longTermArtists: [SpotifyArtist] = []

    // Genres by term — backend ships weighted `{ genre: score }` per term;
    // we mirror the existing `(name, count)` tuple shape the view consumes.
    var shortTermGenres: [(name: String, count: Int)] = []
    var mediumTermGenres: [(name: String, count: Int)] = []
    var longTermGenres: [(name: String, count: Int)] = []

    /// Range names (raw values of `TimeRange`) the backend could not fetch
    /// from Spotify on the most recent load. Empty on full success.
    var failedRanges: Set<String> = []

    // Friend scope.
    var showingFriends = false
    var viewingFriend: Friend?
    var friends: [Friend] = []
    var friendDataDenied = false
    /// The friend has not loaded their own top items yet. Distinct from a
    /// denial: the backend never fetches Spotify on someone else's behalf, so
    /// this is a real, temporary state rather than a refusal.
    var friendCacheCold = false

    private let xomifyService = XomifyService.shared

    // MARK: - Actions

    /// Names whose taste this is.
    var headerSubtitle: String {
        if showingFriends, let friend = viewingFriend {
            return "\(friend.displayName ?? friend.email) · top tracks, artists, genres"
        }
        return "Your top tracks, artists, and genres"
    }

    private func loadFriendTopItems(_ friend: Friend) async {
        defer { isLoading = false }
        do {
            let response = try await xomifyService.getFriendTopItems(email: friend.email)

            if response.cached != true {
                friendCacheCold = true
                clearItems()
                return
            }

            shortTermTracks  = response.tracks?["short_term"] ?? []
            mediumTermTracks = response.tracks?["medium_term"] ?? []
            longTermTracks   = response.tracks?["long_term"] ?? []
            shortTermArtists  = response.artists?["short_term"] ?? []
            mediumTermArtists = response.artists?["medium_term"] ?? []
            longTermArtists   = response.artists?["long_term"] ?? []
            shortTermGenres  = Self.genres(from: response.genres?["short_term"])
            mediumTermGenres = Self.genres(from: response.genres?["medium_term"])
            longTermGenres   = Self.genres(from: response.genres?["long_term"])
        } catch {
            print("[TopItems] friend top items unavailable: \(error)")
            clearItems()
            friendDataDenied = true
        }
    }

    /// Backend ships weighted `{ genre: score }`; the view consumes
    /// `(name, count)` tuples, ordered by weight.
    private static func genres(from weighted: [String: Double]?) -> [(name: String, count: Int)] {
        (weighted ?? [:])
            .sorted { $0.value > $1.value }
            .map { (name: $0.key, count: Int($0.value.rounded())) }
    }

    private func clearItems() {
        shortTermTracks = []; mediumTermTracks = []; longTermTracks = []
        shortTermArtists = []; mediumTermArtists = []; longTermArtists = []
        shortTermGenres = []; mediumTermGenres = []; longTermGenres = []
    }

    func loadData() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        friendDataDenied = false
        friendCacheCold = false

        do {
            if friends.isEmpty {
                friends = (try? await xomifyService.getAllFriends().accepted) ?? []
            }

            if showingFriends, let friend = viewingFriend {
                await loadFriendTopItems(friend)
                return
            }

            let response = try await xomifyService.getCurrentTopItems()

            shortTermTracks  = response.tracks(for: .shortTerm)
            mediumTermTracks = response.tracks(for: .mediumTerm)
            longTermTracks   = response.tracks(for: .longTerm)

            shortTermArtists  = response.artists(for: .shortTerm)
            mediumTermArtists = response.artists(for: .mediumTerm)
            longTermArtists   = response.artists(for: .longTerm)

            shortTermGenres  = response.genres(for: .shortTerm)
            mediumTermGenres = response.genres(for: .mediumTerm)
            longTermGenres   = response.genres(for: .longTerm)

            failedRanges = Set(response.meta?.failedRanges ?? [])

            print("✅ TopItems: Loaded short=\(shortTermTracks.count) medium=\(mediumTermTracks.count) long=\(longTermTracks.count) tracks; failedRanges=\(failedRanges)")

        } catch {
            errorMessage = error.localizedDescription
            print("❌ TopItems: Error loading data - \(error)")
        }

        isLoading = false
    }

    // MARK: - Helpers

    /// `true` when the backend reported a partial Spotify failure for the
    /// given term on the most recent load.
    func didFail(term: TimeRange) -> Bool {
        failedRanges.contains(term.rawValue)
    }
}
