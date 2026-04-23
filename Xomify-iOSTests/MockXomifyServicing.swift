import Foundation
@testable import Xomify_iOS

/// Lightweight mock implementing the full `XomifyServicing` protocol for use
/// in unit tests. Each call records its arguments for later assertion;
/// successful responses are returned by default and individual methods can be
/// stubbed to throw by setting the corresponding `...Error` property.
final class MockXomifyServicing: XomifyServicing, @unchecked Sendable {

    // MARK: - Register / unregister

    struct RegisterCall: Equatable {
        let email: String
        let deviceToken: String
        let queueNotificationsEnabled: Bool
        let digestEnabled: Bool
    }

    struct UnregisterCall: Equatable {
        let email: String
        let deviceToken: String
    }

    private(set) var registerCalls: [RegisterCall] = []
    private(set) var unregisterCalls: [UnregisterCall] = []

    var registerError: Error?
    var unregisterError: Error?

    func registerPushToken(
        email: String,
        deviceToken: String,
        queueNotificationsEnabled: Bool,
        digestEnabled: Bool
    ) async throws -> SuccessResponse {
        registerCalls.append(RegisterCall(
            email: email,
            deviceToken: deviceToken,
            queueNotificationsEnabled: queueNotificationsEnabled,
            digestEnabled: digestEnabled
        ))
        if let registerError { throw registerError }
        return SuccessResponse(success: true)
    }

    func unregisterPushToken(
        email: String,
        deviceToken: String
    ) async throws -> SuccessResponse {
        unregisterCalls.append(UnregisterCall(email: email, deviceToken: deviceToken))
        if let unregisterError { throw unregisterError }
        return SuccessResponse(success: true)
    }

    // MARK: - Friends (unused — returned as empty / success stubs)

    func getAllFriends(email: String) async throws -> FriendsAllResponse {
        FriendsAllResponse(
            email: email,
            accepted: [], requested: [], pending: [], blocked: [],
            acceptedCount: 0, requestedCount: 0, pendingCount: 0, blockedCount: 0,
            totalCount: 0
        )
    }

    func listUsers(email: String) async throws -> UserListResponse {
        UserListResponse(users: [], totalCount: 0)
    }

    func requestFriend(email: String, requestEmail: String) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }

    func acceptFriend(email: String, requestEmail: String) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }

    func rejectFriend(email: String, requestEmail: String) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }

    func removeFriend(email: String, friendEmail: String) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }

    // MARK: - Invites

    func createInvite(email: String) async throws -> InviteCreateResponse {
        InviteCreateResponse(
            success: true,
            inviteCode: "mock-code",
            shareUrl: "https://xomify.xomware.com/invite/mock-code",
            expiresAt: nil,
            status: "active"
        )
    }

    func acceptInvite(email: String, inviteCode: String) async throws -> InviteAcceptResponse {
        InviteAcceptResponse(success: true, inviteCode: inviteCode, friendEmail: nil)
    }

    func listPendingInvites(email: String) async throws -> PendingInvitesResponse {
        PendingInvitesResponse(email: email, invites: [], totalCount: 0)
    }

    func declineInvite(email: String, inviteCode: String) async throws -> SuccessResponse {
        SuccessResponse(success: true)
    }
}
