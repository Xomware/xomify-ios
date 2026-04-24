import Foundation

// MARK: - FeedFilter

/// User-visible filter selection driving the filter chip row.
enum FeedFilter: Hashable, Sendable {
    case all
    case friends
    case group(XomifyGroup)

    /// Stable cache key for the filter, used by `FeedCacheService`.
    var cacheKey: String {
        switch self {
        case .all:                 return "all"
        case .friends:             return "friends"
        case .group(let group):    return "group:\(group.groupId)"
        }
    }

    /// The `groupId` to send to `shares_feed` when this filter is active.
    /// `nil` for `.all` and `.friends` — backend infers scope from the caller.
    var groupId: String? {
        if case .group(let g) = self { return g.groupId }
        return nil
    }

    /// Backend currently has no separate `friends-only` param — "all" and
    /// "friends" both return the friend-graph feed. Chip UI surfaces both so
    /// future backend splits don't need a UI change.
    var label: String {
        switch self {
        case .all:              return "All"
        case .friends:          return "Friends only"
        case .group(let group): return group.displayName
        }
    }
}

// MARK: - FeedViewModel

/// Drives the Feed tab. Cache-first bootstrap → network refresh → keyset pagination.
///
/// Ownership boundaries (MVVM):
/// - `FeedView` never touches `XomifyService` or `FeedCacheService` directly.
/// - Per-card actions (queue, rate) live in `ShareCardViewModel` which this VM
///   constructs lazily on demand.
@Observable
@MainActor
final class FeedViewModel {

    // MARK: - State

    var shares: [Share] = []
    var isLoading: Bool = false
    var isRefreshing: Bool = false
    var errorMessage: String?

    var selectedFilter: FeedFilter = .all
    var groups: [XomifyGroup] = []

    /// Pagination cursor — the `sharedAt` of the last received share, or `nil`
    /// when we've never fetched / there are no more pages.
    var nextBefore: String?
    var hasMorePages: Bool = true

    // MARK: - Dependencies

    private let xomifyService: XomifyServiceProtocol
    private let spotifyService: SpotifyCurrentUserProviding
    private let cacheService: FeedCacheService

    // MARK: - Private state

    /// Current user email — resolved once on `bootstrap` and cached.
    private(set) var userEmail: String = ""

    // MARK: - Init

    init(
        xomifyService: XomifyServiceProtocol = XomifyService.shared,
        spotifyService: SpotifyCurrentUserProviding = SpotifyService.shared,
        cacheService: FeedCacheService = .shared
    ) {
        self.xomifyService = xomifyService
        self.spotifyService = spotifyService
        self.cacheService = cacheService
    }

    // MARK: - Bootstrap

    /// Cache-first render, then network refresh. Safe to call from `.task`.
    func bootstrap() async {
        // 1. Resolve the current user once.
        if userEmail.isEmpty {
            do {
                let user = try await spotifyService.getCurrentUser()
                guard let email = user.email, !email.isEmpty else {
                    errorMessage = "Could not load feed — missing email."
                    return
                }
                userEmail = email
            } catch {
                errorMessage = "Could not load feed: \(error.localizedDescription)"
                return
            }
        }

        // 2. Paint from cache if we have one — instant first frame on cold launch.
        if let cached = await cacheService.load(filterKey: selectedFilter.cacheKey), !cached.isEmpty {
            shares = cached
        }

        // 3. Fire the network refresh.
        await refresh()
    }

    // MARK: - Refresh

    /// Pull-to-refresh + initial load. Replaces shares, resets pagination,
    /// rewrites cache for the current filter.
    func refresh() async {
        guard !userEmail.isEmpty else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil

        do {
            let response = try await xomifyService.getFeed(
                email: userEmail,
                groupId: selectedFilter.groupId,
                limit: FeedCacheService.maxSharesPerFilter,
                before: nil
            )
            shares = response.shares
            nextBefore = response.nextBefore
            hasMorePages = response.nextBefore != nil
            await cacheService.save(response.shares, forKey: selectedFilter.cacheKey)
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
        isLoading = false
    }

    // MARK: - Pagination

    /// Fetch the next page. No-op when already loading or `hasMorePages` is false.
    func loadMore() async {
        guard hasMorePages, !isLoading, !isRefreshing else { return }
        guard let before = nextBefore else {
            hasMorePages = false
            return
        }
        guard !userEmail.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await xomifyService.getFeed(
                email: userEmail,
                groupId: selectedFilter.groupId,
                limit: FeedCacheService.maxSharesPerFilter,
                before: before
            )
            shares.append(contentsOf: response.shares)
            nextBefore = response.nextBefore
            hasMorePages = response.nextBefore != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Filter switching

    /// Clear current list, reset cursor, bootstrap from the new filter's cache,
    /// then refresh from network.
    func switchFilter(_ filter: FeedFilter) async {
        guard filter != selectedFilter else { return }
        selectedFilter = filter
        shares = []
        nextBefore = nil
        hasMorePages = true

        if let cached = await cacheService.load(filterKey: filter.cacheKey), !cached.isEmpty {
            shares = cached
        }

        await refresh()
    }

    // MARK: - Groups (filter chips)

    /// Load the user's groups for the filter chip row. Safe to call on appear.
    func loadGroupsForChips() async {
        guard !userEmail.isEmpty else { return }

        do {
            let response = try await xomifyService.listGroups(email: userEmail)
            groups = response.groups ?? []
        } catch {
            // Non-fatal — chips just show `All` / `Friends only` without group rows.
        }
    }

    // MARK: - Share composer integration

    /// Prepend a freshly composed share locally + refresh from network to pull
    /// server-enriched counts. Avoids a "post then wait" UX beat.
    func prependShareAndRefresh(_ share: Share) async {
        shares.insert(share, at: 0)
        await refresh()
    }
}
