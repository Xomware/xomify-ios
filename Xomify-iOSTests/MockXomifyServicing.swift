import Foundation
@testable import Xomify_iOS

/// Lightweight mock implementing the full `XomifyServicing` protocol for use
/// in unit tests. Each call records its arguments for later assertion;
/// successful responses are returned by default and individual methods can be
/// stubbed to throw by setting the corresponding `...Error` property.
final class MockXomifyServicing: XomifyServicing, @unchecked Sendable {

    // MARK: - Register / unregister

    struct RegisterCall: Equatable {
        let deviceToken: String
        let queueNotificationsEnabled: Bool
        let digestEnabled: Bool
    }

    struct UnregisterCall: Equatable {
        let deviceToken: String
    }

    private(set) var registerCalls: [RegisterCall] = []
    private(set) var unregisterCalls: [UnregisterCall] = []

    var registerError: Error?
    var unregisterError: Error?

    func registerPushToken(
        deviceToken: String,
        queueNotificationsEnabled: Bool,
        digestEnabled: Bool
    ) async throws -> SuccessResponse {
        registerCalls.append(RegisterCall(
            deviceToken: deviceToken,
            queueNotificationsEnabled: queueNotificationsEnabled,
            digestEnabled: digestEnabled
        ))
        if let registerError { throw registerError }
        return SuccessResponse(success: true)
    }

    func unregisterPushToken(
        deviceToken: String
    ) async throws -> SuccessResponse {
        unregisterCalls.append(UnregisterCall(deviceToken: deviceToken))
        if let unregisterError { throw unregisterError }
        return SuccessResponse(success: true)
    }

    // MARK: - Per-kind preferences (relaunch epic, B2/B8)

    struct PreferenceRegisterCall: Equatable {
        let deviceToken: String
        let preferences: [String: Bool]
    }

    private(set) var preferenceRegisterCalls: [PreferenceRegisterCall] = []

    /// What the server "already knows". Merged over whatever the client sends,
    /// so tests can model the effective-map behaviour.
    var storedPreferences: [String: Bool] = [:]

    func registerPushToken(
        deviceToken: String,
        preferences: [String: Bool]
    ) async throws -> [String: Bool] {
        preferenceRegisterCalls.append(
            PreferenceRegisterCall(deviceToken: deviceToken, preferences: preferences)
        )
        if let registerError { throw registerError }
        for (key, value) in preferences { storedPreferences[key] = value }
        return storedPreferences
    }

    // MARK: - Inbox

    var inboxPages: [InboxPage] = []
    var unreadCount: Int = 0
    var inboxError: Error?
    private(set) var markReadCalls: [String] = []
    private(set) var markAllReadCallCount = 0
    private(set) var fetchCursors: [String?] = []

    func fetchNotifications(limit: Int, cursor: String?) async throws -> InboxPage {
        fetchCursors.append(cursor)
        if let inboxError { throw inboxError }
        guard !inboxPages.isEmpty else { return InboxPage(items: [], nextCursor: nil) }
        return inboxPages.removeFirst()
    }

    func markNotificationRead(tsId: String) async throws {
        markReadCalls.append(tsId)
        if let inboxError { throw inboxError }
    }

    func markAllNotificationsRead() async throws {
        markAllReadCallCount += 1
        if let inboxError { throw inboxError }
    }

    func fetchUnreadNotificationCount() async throws -> Int {
        if let inboxError { throw inboxError }
        return unreadCount
    }

    // MARK: - Goals

    var goals: [StoredGoal] = []
    var goalsHistory: [WeekHistoryEntry] = []
    var goalsError: Error?

    private(set) var setGoalsCalls: [[StoredGoal]] = []
    private(set) var recordedWeeks: [WeekHistoryEntry] = []

    func fetchGoals() async throws -> (goals: [StoredGoal], history: [WeekHistoryEntry]) {
        if let goalsError { throw goalsError }
        return (goals, goalsHistory)
    }

    func setGoals(_ goals: [StoredGoal]) async throws -> [StoredGoal] {
        if let goalsError { throw goalsError }
        setGoalsCalls.append(goals)
        self.goals = goals
        return goals
    }

    func recordGoalWeek(_ entry: WeekHistoryEntry) async throws {
        recordedWeeks.append(entry)
    }

    // MARK: - Favorites

    var favoritesYear: FavoritesYear?
    var favoritesRecommendations: [FavoriteItem] = []
    var favoritesHistory: [FavoriteHistoryEvent] = []
    var favoritesError: Error?

    private(set) var setListCalls: [(listId: String, items: [FavoriteItem])] = []
    private(set) var createListCalls: [(category: FavoriteCategory, label: String)] = []
    private(set) var deleteListCalls: [String] = []

    func fetchFavorites(year: Int) async throws -> FavoritesYear {
        if let favoritesError { throw favoritesError }
        return favoritesYear ?? FavoritesYear(year: year, overall: nil, lists: nil)
    }

    func createFavoritesList(
        year: Int, category: FavoriteCategory, genreLabel: String
    ) async throws -> FavoriteList {
        createListCalls.append((category, genreLabel))
        if let favoritesError { throw favoritesError }
        return FavoriteList(
            listId: "list-\(createListCalls.count)",
            year: year,
            category: category,
            genreLabel: genreLabel,
            items: []
        )
    }

    func setFavoritesList(
        year: Int, listId: String, items: [FavoriteItem]
    ) async throws -> FavoriteList {
        setListCalls.append((listId, items))
        if let favoritesError { throw favoritesError }
        return FavoriteList(
            listId: listId, year: year, category: .songs,
            genreLabel: "Overall", items: items
        )
    }

    func deleteFavoritesList(year: Int, listId: String) async throws {
        deleteListCalls.append(listId)
        if let favoritesError { throw favoritesError }
    }

    func fetchFavoritesHistory(listId: String) async throws -> [FavoriteHistoryEvent] {
        if let favoritesError { throw favoritesError }
        return favoritesHistory
    }

    func fetchFavoritesRecommendations(
        year: Int, category: FavoriteCategory, listId: String
    ) async throws -> [FavoriteItem] {
        if let favoritesError { throw favoritesError }
        return favoritesRecommendations
    }

    // MARK: - Friends (unused — returned as empty / success stubs)

    func getAllFriends() async throws -> FriendsAllResponse {
        FriendsAllResponse(
            email: "mock@example.com",
            accepted: [], requested: [], pending: [], blocked: [],
            acceptedCount: 0, requestedCount: 0, pendingCount: 0, blockedCount: 0,
            totalCount: 0
        )
    }

    func listUsers() async throws -> UserListResponse {
        UserListResponse(users: [], totalCount: 0)
    }

    func requestFriend(requestEmail: String) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }

    func acceptFriend(requestEmail: String) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }

    func rejectFriend(requestEmail: String) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }

    func removeFriend(friendEmail: String) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }

    // MARK: - Invites

    func createInvite() async throws -> InviteCreateResponse {
        InviteCreateResponse(
            success: true,
            inviteCode: "mock-code",
            shareUrl: "https://xomify.xomware.com/invite/mock-code",
            expiresAt: nil,
            status: "active"
        )
    }

    func acceptInvite(inviteCode: String) async throws -> InviteAcceptResponse {
        InviteAcceptResponse(success: true, inviteCode: inviteCode, friendEmail: nil)
    }

    func listPendingInvites() async throws -> PendingInvitesResponse {
        PendingInvitesResponse(email: "mock@example.com", invites: [], totalCount: 0)
    }

    func declineInvite(inviteCode: String) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }
}
