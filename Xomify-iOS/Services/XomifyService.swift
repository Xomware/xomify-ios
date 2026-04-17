import Foundation

/// Service for Xomify backend API calls
actor XomifyService {
    
    // MARK: - Singleton
    
    static let shared = XomifyService()
    
    private let network = NetworkService.shared
    
    private init() {}
    
    // MARK: - User / Enrollment
    
    /// Get user enrollment status and wraps
    func getUserData(email: String) async throws -> WrappedDataResponse {
        try await network.xomifyGet("/wrapped/data", queryParams: ["email": email])
    }
    
    /// Get user table data
    func getUserTableData(email: String) async throws -> XomifyUser {
        try await network.xomifyGet("/user/user-table", queryParams: ["email": email])
    }
    
    /// Enroll or update user enrollments
    func updateEnrollments(
        email: String,
        activeWrapped: Bool,
        activeReleaseRadar: Bool
    ) async throws {
        let _: EmptyResponse = try await network.xomifyPost("/user/user-table", body: [
            "email": email,
            "activeWrapped": activeWrapped,
            "activeReleaseRadar": activeReleaseRadar
        ])
    }
    
    // MARK: - Release Radar
    
    /// Get release radar history (past weeks)
    func getReleaseRadarHistory(email: String, limit: Int = 12) async throws -> ReleaseRadarHistoryResponse {
        try await network.xomifyGet("/release-radar/history", queryParams: [
            "email": email,
            "limit": String(limit)
        ])
    }
    
    /// Check release radar status
    func checkReleaseRadar(email: String) async throws -> ReleaseRadarCheckResponse {
        try await network.xomifyGet("/release-radar/check", queryParams: ["email": email])
    }
    
    
    // MARK: - Wrapped
    
    /// Get all wraps from wrapped/data endpoint
    func getWraps(email: String) async throws -> [MonthlyWrap] {
        let response: WrappedDataResponse = try await network.xomifyGet("/wrapped/data", queryParams: ["email": email])
        return response.wraps ?? []
    }
    
    /// Get specific wrap by month
    func getWrap(email: String, monthKey: String) async throws -> MonthlyWrap {
        try await network.xomifyGet("/wrapped/month", queryParams: [
            "email": email,
            "monthKey": monthKey
        ])
    }

    // MARK: - Social

    /// Create a new share in the feed
    @discardableResult
    func createShare(
        email: String,
        type: ShareType,
        payload: [String: Any],
        caption: String? = nil
    ) async throws -> ShareCreateResponse {
        var body: [String: Any] = [
            "email": email,
            "type": type.rawValue,
            "payload": payload
        ]
        if let caption = caption {
            body["caption"] = caption
        }
        return try await network.xomifyPost("/shares/create", body: body)
    }

    /// Get the social feed for a user
    func getFeed(email: String) async throws -> FeedResponse {
        try await network.xomifyGet("/shares/feed", queryParams: ["email": email])
    }

    /// React to a share (like / fire / love / none to remove)
    @discardableResult
    func reactToShare(
        shareId: String,
        email: String,
        action: ReactionAction
    ) async throws -> ReactionResponse {
        try await network.xomifyPost("/shares/react", body: [
            "shareId": shareId,
            "email": email,
            "action": action.rawValue
        ])
    }

    /// Create a friend invite code
    func createInvite(email: String) async throws -> InviteCreateResponse {
        try await network.xomifyPost("/invites/create", body: ["email": email])
    }

    /// Accept a friend invite code
    func acceptInvite(email: String, inviteCode: String) async throws -> InviteAcceptResponse {
        try await network.xomifyPost("/invites/accept", body: [
            "email": email,
            "inviteCode": inviteCode
        ])
    }
}
