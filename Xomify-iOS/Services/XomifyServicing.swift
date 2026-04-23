import Foundation

/// Protocol surface for `FriendsViewModel` (and related screens) to interact with
/// the Xomify backend. Extracted to enable mocking in unit tests without having
/// to stub the full `XomifyService` actor.
///
/// Only the operations exercised by Friends / Invites flows are included here —
/// keep this surface tight and expand incrementally as other screens adopt it.
protocol XomifyServicing: Sendable {

    // MARK: - Friends

    func getAllFriends(email: String) async throws -> FriendsAllResponse
    func listUsers(email: String) async throws -> UserListResponse

    @discardableResult
    func requestFriend(email: String, requestEmail: String) async throws -> SuccessResponse

    @discardableResult
    func acceptFriend(email: String, requestEmail: String) async throws -> SuccessResponse

    @discardableResult
    func rejectFriend(email: String, requestEmail: String) async throws -> SuccessResponse

    @discardableResult
    func removeFriend(email: String, friendEmail: String) async throws -> SuccessResponse

    // MARK: - Invites

    func createInvite(email: String) async throws -> InviteCreateResponse

    func acceptInvite(email: String, inviteCode: String) async throws -> InviteAcceptResponse

    /// List deep-link invites sent to this user and awaiting accept/decline.
    /// TODO: endpoint lands in backend-interactions-and-friends-handlers PR.
    func listPendingInvites(email: String) async throws -> PendingInvitesResponse

    /// Decline a deep-link invite.
    /// TODO: endpoint lands in backend-interactions-and-friends-handlers PR.
    @discardableResult
    func declineInvite(email: String, inviteCode: String) async throws -> SuccessResponse

    // MARK: - Notifications

    /// Upsert an APNs device token + preference flags for the user.
    /// Idempotent on `(email, deviceToken)` — safe to call on every cold launch.
    @discardableResult
    func registerPushToken(
        email: String,
        deviceToken: String,
        queueNotificationsEnabled: Bool,
        digestEnabled: Bool
    ) async throws -> SuccessResponse

    /// Delete a device token from the backend. Called on sign-out.
    @discardableResult
    func unregisterPushToken(
        email: String,
        deviceToken: String
    ) async throws -> SuccessResponse
}

// Conformance on the real service — ensures production callers can keep using
// the existing singleton while tests inject a mock.
extension XomifyService: XomifyServicing {}
