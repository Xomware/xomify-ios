import Foundation

/// Protocol surface for `FriendsViewModel` (and related screens) to interact with
/// the Xomify backend. Extracted to enable mocking in unit tests without having
/// to stub the full `XomifyService` actor.
///
/// Only the operations exercised by Friends / Invites flows are included here —
/// keep this surface tight and expand incrementally as other screens adopt it.
///
/// Caller identity rides the per-user JWT (sub-feature 0d) and is resolved
/// server-side (1a–1i). Methods here only carry target identifiers.
protocol XomifyServicing: Sendable {

    // MARK: - Friends

    func getAllFriends() async throws -> FriendsAllResponse
    func listUsers() async throws -> UserListResponse

    @discardableResult
    func requestFriend(requestEmail: String) async throws -> SuccessResponse

    @discardableResult
    func acceptFriend(requestEmail: String) async throws -> SuccessResponse

    @discardableResult
    func rejectFriend(requestEmail: String) async throws -> SuccessResponse

    @discardableResult
    func removeFriend(friendEmail: String) async throws -> SuccessResponse

    // MARK: - Invites

    func createInvite() async throws -> InviteCreateResponse

    func acceptInvite(inviteCode: String) async throws -> InviteAcceptResponse

    /// List deep-link invites sent to this user and awaiting accept/decline.
    /// TODO: endpoint lands in backend-interactions-and-friends-handlers PR.
    func listPendingInvites() async throws -> PendingInvitesResponse

    /// Decline a deep-link invite.
    /// TODO: endpoint lands in backend-interactions-and-friends-handlers PR.
    @discardableResult
    func declineInvite(inviteCode: String) async throws -> SuccessResponse

    // MARK: - Notifications

    /// Upsert an APNs device token + preference flags for the caller.
    /// Idempotent on `(caller, deviceToken)` — safe to call on every cold launch.
    @discardableResult
    func registerPushToken(
        deviceToken: String,
        queueNotificationsEnabled: Bool,
        digestEnabled: Bool
    ) async throws -> SuccessResponse

    /// Delete a device token from the backend. Called on sign-out.
    @discardableResult
    func unregisterPushToken(
        deviceToken: String
    ) async throws -> SuccessResponse

    /// Upsert with the full per-kind preference map.
    ///
    /// `preferences` is SPARSE: only flags the user has actually touched. The
    /// backend leaves anything absent untouched, which is what allows new
    /// notification kinds to ship without backfilling every device row.
    /// Returns the effective map — every kind, defaults resolved — so Settings
    /// can render all sixteen rows from one response.
    func registerPushToken(
        deviceToken: String,
        preferences: [String: Bool]
    ) async throws -> [String: Bool]

    // MARK: - Notification inbox

    func fetchNotifications(limit: Int, cursor: String?) async throws -> InboxPage
    func markNotificationRead(tsId: String) async throws
    func markAllNotificationsRead() async throws
    func fetchUnreadNotificationCount() async throws -> Int

    // MARK: - Goals

    func fetchGoals() async throws -> (goals: [StoredGoal], history: [WeekHistoryEntry])
    func setGoals(_ goals: [StoredGoal]) async throws -> [StoredGoal]
    func recordGoalWeek(_ entry: WeekHistoryEntry) async throws

    // MARK: - Favorites

    func fetchFavorites(year: Int) async throws -> FavoritesYear
    func createFavoritesList(year: Int, category: FavoriteCategory, genreLabel: String) async throws -> FavoriteList
    func setFavoritesList(year: Int, listId: String, items: [FavoriteItem]) async throws -> FavoriteList
    func deleteFavoritesList(year: Int, listId: String) async throws
    func fetchFavoritesHistory(listId: String) async throws -> [FavoriteHistoryEvent]
    func fetchFavoritesRecommendations(year: Int, category: FavoriteCategory, listId: String) async throws -> [FavoriteItem]
}

// Conformance on the real service — ensures production callers can keep using
// the existing singleton while tests inject a mock.
extension XomifyService: XomifyServicing {}
