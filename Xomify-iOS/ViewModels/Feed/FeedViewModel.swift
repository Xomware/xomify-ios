import Foundation

// MARK: - FeedFilter

/// User-visible filter selection driving the filter chip row. `.all` was
/// dropped in 2026-04: the feed is always friends-graph-scoped (plus the
/// caller themselves), so `.all` and `.friends` resolved to the same
/// backend query and having both was just UI noise.
enum FeedFilter: Hashable, Sendable {
    case friends
    case group(XomifyGroup)

    /// Stable cache key for the filter, used by `FeedCacheService`.
    var cacheKey: String {
        switch self {
        case .friends:             return "friends"
        case .group(let group):    return "group:\(group.groupId)"
        }
    }

    /// The `groupId` to send to `shares_feed` when this filter is active.
    /// `nil` for `.friends` — backend infers scope from the caller.
    var groupId: String? {
        if case .group(let g) = self { return g.groupId }
        return nil
    }

    var label: String {
        switch self {
        case .friends:          return "Friends"
        case .group(let group): return group.displayName
        }
    }
}

// MARK: - FeedRefinement

/// Client-side refinement on top of the currently loaded shares. These are
/// pure filtering + sorting knobs — the backend feed query itself doesn't
/// change when the user flips them. That's intentional: refinement runs
/// locally so switching a filter is instant and round-trip free.
struct FeedRefinement: Equatable, Sendable {

    /// Time window for `sharedAt`. Nothing outside the window renders.
    enum DateWindow: String, CaseIterable, Identifiable, Sendable {
        case anytime
        case today
        case past7Days
        case past30Days

        var id: String { rawValue }

        var label: String {
            switch self {
            case .anytime:     return "Anytime"
            case .today:       return "Today"
            case .past7Days:   return "Past 7 days"
            case .past30Days:  return "Past 30 days"
            }
        }

        /// Lower-bound `Date` the window admits; `nil` for `.anytime`.
        fileprivate func minDate(now: Date = Date()) -> Date? {
            let cal = Calendar.current
            switch self {
            case .anytime:    return nil
            case .today:      return cal.startOfDay(for: now)
            case .past7Days:  return cal.date(byAdding: .day, value: -7, to: now)
            case .past30Days: return cal.date(byAdding: .day, value: -30, to: now)
            }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable, Sendable {
        case newest
        case oldest

        var id: String { rawValue }

        var label: String {
            switch self {
            case .newest: return "Newest first"
            case .oldest: return "Oldest first"
            }
        }
    }

    /// Selected authors (emails). Empty set = no author filter.
    var authors: Set<String> = []
    var dateWindow: DateWindow = .anytime
    /// When true, hide shares the viewer has already queued on Spotify.
    var onlyUnlistened: Bool = false
    var sortOrder: SortOrder = .newest

    /// True when any non-default refinement is active. Drives the "Filters"
    /// chip accent so the user can tell at a glance.
    var isActive: Bool {
        !authors.isEmpty || dateWindow != .anytime || onlyUnlistened || sortOrder != .newest
    }

    /// Short summary for the chip label when active.
    var activeCount: Int {
        var n = 0
        if !authors.isEmpty { n += 1 }
        if dateWindow != .anytime { n += 1 }
        if onlyUnlistened { n += 1 }
        if sortOrder != .newest { n += 1 }
        return n
    }

    mutating func reset() {
        self = FeedRefinement()
    }
}

// MARK: - SharerIdentity

/// Resolved display name + avatar for a share author. Feed batches these
/// from `getAllFriends` + the viewer's own Spotify profile so the feed can
/// render "Dom" + avatar instead of raw emails.
struct SharerIdentity: Hashable, Sendable {
    let displayName: String
    let avatarURL: URL?
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

    var selectedFilter: FeedFilter = .friends
    var groups: [XomifyGroup] = []

    /// Client-side refinement (date window, authors, unlistened, sort).
    /// Bound by the refinement sheet; consumed by `filteredShares`.
    var refinement: FeedRefinement = FeedRefinement()

    /// displayName + avatar keyed by email. Populated on bootstrap from the
    /// viewer's own profile + all accepted friends. Falls back to email when
    /// a sharer isn't in the map (shouldn't happen for friend-graph feeds).
    var identitiesByEmail: [String: SharerIdentity] = [:]

    /// Pagination cursor — the `sharedAt` of the last received share, or `nil`
    /// when we've never fetched / there are no more pages.
    var nextBefore: String?
    var hasMorePages: Bool = true

    // MARK: - Dependencies

    private let xomifyService: XomifyServiceProtocol
    private let spotifyService: SpotifyCurrentUserProviding
    private let cacheService: FeedCacheService
    private let defaults: UserDefaults

    // MARK: - Persistence keys

    /// Last successfully-resolved Spotify email. Written after every
    /// `getCurrentUser` success, read as a fallback on bootstrap when the
    /// network call fails transiently. Prevents "posted, came back, now
    /// errors" UX when a transient 401/offline blip on bootstrap would
    /// otherwise leave the feed empty.
    private static let cachedEmailKey = "feed.cachedEmail"

    // MARK: - Private state

    /// Current user email — resolved once on `bootstrap` and cached.
    private(set) var userEmail: String = ""

    // MARK: - Init

    init(
        xomifyService: XomifyServiceProtocol = XomifyService.shared,
        spotifyService: SpotifyCurrentUserProviding = SpotifyService.shared,
        cacheService: FeedCacheService = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.xomifyService = xomifyService
        self.spotifyService = spotifyService
        self.cacheService = cacheService
        self.defaults = defaults
    }

    // MARK: - Bootstrap

    /// Cache-first render, then network refresh. Safe to call from `.task`.
    ///
    /// Resilient to transient Spotify `/me` failures: when `getCurrentUser`
    /// throws, falls back to the last-known email from UserDefaults and
    /// still paints the cached feed. Only surfaces an error when neither
    /// source resolves an email.
    func bootstrap() async {
        // 1. Paint from cache first — instant first frame, independent of
        //    whether we can resolve the current user right now.
        if let cached = await cacheService.load(filterKey: selectedFilter.cacheKey), !cached.isEmpty {
            shares = cached
        }

        // 2. Resolve the current user. Prefer the network, fall back to the
        //    last-known email from UserDefaults on failure.
        if userEmail.isEmpty {
            if let email = await resolveCurrentEmail() {
                userEmail = email
            } else {
                // Only surface an error when there's nothing painted AND we
                // have no way to refresh. If we already painted from cache,
                // the user gets the last-known feed and a quiet retry later.
                if shares.isEmpty {
                    errorMessage = "Could not load feed — please try again."
                }
                return
            }
        }

        // 3. Populate identity map in parallel with the refresh. Identity
        //    lookups aren't user-facing blockers — a miss just falls back to
        //    the email string.
        async let identitiesTask: Void = loadIdentities()
        async let refreshTask: Void = refresh()
        _ = await (identitiesTask, refreshTask)
    }

    /// Prefer network; fall back to UserDefaults cache on transient failure.
    /// Persists the email on every successful resolve.
    private func resolveCurrentEmail() async -> String? {
        do {
            let user = try await spotifyService.getCurrentUser()
            if let email = user.email, !email.isEmpty {
                defaults.set(email, forKey: Self.cachedEmailKey)
                return email
            }
        } catch {
            // Fall through to the cached email.
        }
        let cached = defaults.string(forKey: Self.cachedEmailKey)
        return (cached?.isEmpty == false) ? cached : nil
    }

    // MARK: - Refresh

    /// Pull-to-refresh + initial load. Replaces shares, resets pagination,
    /// rewrites cache for the current filter.
    ///
    /// When refresh fails but we already have cached shares painted, the
    /// error is swallowed so the user keeps seeing the last-known feed
    /// rather than an error screen. The full error is only surfaced when
    /// shares is empty (first-ever load or stale cache evicted).
    func refresh() async {
        guard !userEmail.isEmpty else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil

        do {
            let response = try await xomifyService.getFeed(
                groupId: selectedFilter.groupId,
                limit: FeedCacheService.maxSharesPerFilter,
                before: nil
            )
            shares = response.shares
            nextBefore = response.nextBefore
            hasMorePages = response.nextBefore != nil
            await cacheService.save(response.shares, forKey: selectedFilter.cacheKey)
        } catch {
            // Don't blow the UI away over a refresh hiccup if we already
            // have content painted from cache.
            if shares.isEmpty {
                errorMessage = error.localizedDescription
            }
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
            let response = try await xomifyService.listGroups()
            groups = response.groups ?? []
        } catch {
            // Non-fatal — chips just show `Friends` without group rows.
        }
    }

    // MARK: - Identities

    /// Populate `identitiesByEmail` from the viewer's own profile + all
    /// accepted friends. Best-effort: a failure here silently falls back to
    /// email-as-label on each card.
    private func loadIdentities() async {
        var map: [String: SharerIdentity] = [:]

        // Viewer's own identity from Spotify.
        if let user = try? await spotifyService.getCurrentUser(),
           let email = user.email, !email.isEmpty {
            let name = user.displayName?.isEmpty == false ? user.displayName! : email
            let url = (user.images?.first?.url).flatMap(URL.init(string:))
            map[email] = SharerIdentity(displayName: name, avatarURL: url)
        }

        // Friends — `email` on the row is the CALLER's email, `friendEmail`
        // is the other party. Always key by `targetEmail`.
        if let response = try? await xomifyService.getAllFriends() {
            for friend in response.accepted ?? [] {
                let email = friend.targetEmail
                guard !email.isEmpty else { continue }
                let name = friend.displayName?.isEmpty == false ? friend.displayName! : email
                let url = friend.avatar.flatMap(URL.init(string:))
                map[email] = SharerIdentity(displayName: name, avatarURL: url)
            }
        }

        identitiesByEmail = map
    }

    /// Resolve a display identity for a given email. Falls back to the
    /// email string when the user isn't in the map.
    func identity(for email: String) -> SharerIdentity {
        if let hit = identitiesByEmail[email] { return hit }
        return SharerIdentity(displayName: email, avatarURL: nil)
    }

    // MARK: - Share composer integration

    /// Prepend a freshly composed share locally + refresh from network to pull
    /// server-enriched counts. Avoids a "post then wait" UX beat.
    func prependShareAndRefresh(_ share: Share) async {
        shares.insert(share, at: 0)
        await refresh()
    }

    // MARK: - Refinement

    /// Shares after the current refinement (date window, authors,
    /// unlistened, sort) is applied. The raw `shares` array is preserved
    /// so pagination continues to work against the full list.
    var filteredShares: [Share] {
        let window = refinement.dateWindow.minDate()
        let authors = refinement.authors
        let onlyUnlistened = refinement.onlyUnlistened

        var result = shares.filter { share in
            if !authors.isEmpty, !authors.contains(share.sharedBy) {
                return false
            }
            if onlyUnlistened, share.viewerHasQueued {
                return false
            }
            if let minDate = window, let shareDate = share.sharedAtDate, shareDate < minDate {
                return false
            }
            return true
        }

        if refinement.sortOrder == .oldest {
            result.sort { ($0.sharedAtDate ?? .distantPast) < ($1.sharedAtDate ?? .distantPast) }
        }

        return result
    }

    /// Distinct authors visible in the currently loaded shares — powers the
    /// author picker so users only see people who've actually posted.
    var availableAuthors: [String] {
        let unique = Set(shares.map { $0.sharedBy })
        return unique.sorted { a, b in
            identity(for: a).displayName.localizedCaseInsensitiveCompare(
                identity(for: b).displayName
            ) == .orderedAscending
        }
    }

    // MARK: - Share deletion

    /// Delete a share authored by the current viewer. Optimistically removes
    /// the row from the feed + cache, then hits the backend. On failure the
    /// row is restored and an error surfaces.
    func deleteShare(_ share: Share) async {
        guard share.sharedBy == userEmail else { return }
        guard let index = shares.firstIndex(where: { $0.shareId == share.shareId }) else { return }

        let removed = shares.remove(at: index)
        await cacheService.save(shares, forKey: selectedFilter.cacheKey)

        do {
            _ = try await xomifyService.deleteShare(
                shareId: share.shareId,
                sharedAt: share.sharedAt
            )
        } catch {
            shares.insert(removed, at: min(index, shares.count))
            await cacheService.save(shares, forKey: selectedFilter.cacheKey)
            errorMessage = "Failed to delete post: \(error.localizedDescription)"
        }
    }
}
