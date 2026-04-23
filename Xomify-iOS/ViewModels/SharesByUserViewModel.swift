import Foundation

/// Drives the Shares tab on `ProfileView`. Paginated list of one author's shares
/// keyed off `sharedAt` (matches `/shares/feed` cursor semantics).
///
/// Mirrors `FeedViewModel`'s pagination shape but without cache, filters, or
/// share-composer integration — those belong to the Feed surface.
@Observable
@MainActor
final class SharesByUserViewModel {

    // MARK: - State

    var shares: [Share] = []
    var isLoading: Bool = false
    var isRefreshing: Bool = false
    var errorMessage: String?
    var hasMorePages: Bool = true

    /// Pagination cursor — `sharedAt` of the last received share, or `nil` before
    /// the first load / when the server returns no `nextBefore`.
    var nextBefore: String?

    // MARK: - Dependencies

    private let xomifyService: XomifyServiceProtocol
    private let callerEmail: String
    private let targetEmail: String

    // MARK: - Init

    /// - Parameters:
    ///   - callerEmail: The signed-in user's email (backend requires this even for
    ///     profile lookups — reserved for future friendship gating / enrichment).
    ///   - targetEmail: The author whose shares we're listing.
    init(
        callerEmail: String,
        targetEmail: String,
        xomifyService: XomifyServiceProtocol = XomifyService.shared
    ) {
        self.callerEmail = callerEmail
        self.targetEmail = targetEmail
        self.xomifyService = xomifyService
    }

    // MARK: - Load

    /// Initial load. Safe to call from `.task`. No-op if already populated (use
    /// `refresh` to force a re-fetch).
    func bootstrap() async {
        guard shares.isEmpty else { return }
        await refresh()
    }

    /// Pull-to-refresh + first load. Replaces the list and resets pagination.
    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil

        do {
            let response = try await xomifyService.getSharesByUser(
                email: callerEmail,
                targetEmail: targetEmail,
                limit: 50,
                before: nil
            )
            shares = response.shares
            nextBefore = response.nextBefore
            hasMorePages = response.nextBefore != nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    /// Fetch the next page. No-op when already loading or no more pages.
    func loadMore() async {
        guard hasMorePages, !isLoading, !isRefreshing else { return }
        guard let before = nextBefore else {
            hasMorePages = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await xomifyService.getSharesByUser(
                email: callerEmail,
                targetEmail: targetEmail,
                limit: 50,
                before: before
            )
            shares.append(contentsOf: response.shares)
            nextBefore = response.nextBefore
            hasMorePages = response.nextBefore != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
