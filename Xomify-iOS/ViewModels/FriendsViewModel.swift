import Foundation

/// ViewModel for the Friends screen. Three buckets: accepted friends, requests
/// (incoming + outgoing), and a discovery list of all other users.
@Observable
@MainActor
final class FriendsViewModel {

    // MARK: - State

    var userEmail: String = ""

    var accepted: [Friend] = []
    var incoming: [Friend] = []   // pending (others -> me)
    var outgoing: [Friend] = []   // requested (me -> others)
    var discover: [SearchResult] = []

    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?

    /// Actions currently in flight, keyed by target email. Prevents double-taps.
    var inFlight: Set<String> = []

    private let xomify = XomifyService.shared

    // MARK: - Load

    func load(email: String) async {
        guard !email.isEmpty else {
            errorMessage = "Please log in first"
            return
        }
        userEmail = email
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        async let friendsBucket = xomify.getAllFriends(email: email)
        async let allUsers = xomify.listUsers(email: email)

        do {
            let (friendsResp, usersResp) = try await (friendsBucket, allUsers)
            accepted = friendsResp.accepted ?? []
            incoming = friendsResp.pending ?? []
            outgoing = friendsResp.requested ?? []
            discover = (usersResp.users ?? []).filter { $0.email != email }
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Friends: load failed - \(error)")
        }

        isLoading = false
    }

    func refresh() async {
        guard !userEmail.isEmpty else { return }
        isRefreshing = true
        await load(email: userEmail)
        isRefreshing = false
    }

    // MARK: - Actions

    func request(_ target: SearchResult) async {
        let targetEmail = target.email
        guard !inFlight.contains(targetEmail) else { return }
        inFlight.insert(targetEmail)
        defer { inFlight.remove(targetEmail) }

        do {
            _ = try await xomify.requestFriend(email: userEmail, requestEmail: targetEmail)
            // Optimistic: add to outgoing, flag discovery row.
            let friend = Friend(
                email: userEmail,
                friendEmail: targetEmail,
                displayName: target.displayName,
                avatar: target.avatar,
                status: "pending",
                direction: "outgoing",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                mutualCount: target.mutualCount
            )
            outgoing.append(friend)
            updateDiscoverFlags(for: targetEmail, isOutgoing: true)
        } catch {
            errorMessage = "Failed to send request: \(error.localizedDescription)"
            print("❌ Friends: request failed - \(error)")
        }
    }

    func accept(_ friend: Friend) async {
        let targetEmail = friend.targetEmail
        guard !inFlight.contains(targetEmail) else { return }
        inFlight.insert(targetEmail)
        defer { inFlight.remove(targetEmail) }

        do {
            _ = try await xomify.acceptFriend(email: userEmail, requestEmail: targetEmail)
            incoming.removeAll { $0.targetEmail == targetEmail }
            accepted.append(friend)
            updateDiscoverFlags(for: targetEmail, isFriend: true)
        } catch {
            errorMessage = "Failed to accept: \(error.localizedDescription)"
            print("❌ Friends: accept failed - \(error)")
        }
    }

    func reject(_ friend: Friend) async {
        let targetEmail = friend.targetEmail
        guard !inFlight.contains(targetEmail) else { return }
        inFlight.insert(targetEmail)
        defer { inFlight.remove(targetEmail) }

        do {
            _ = try await xomify.rejectFriend(email: userEmail, requestEmail: targetEmail)
            incoming.removeAll { $0.targetEmail == targetEmail }
            updateDiscoverFlags(for: targetEmail, clearAll: true)
        } catch {
            errorMessage = "Failed to reject: \(error.localizedDescription)"
            print("❌ Friends: reject failed - \(error)")
        }
    }

    func cancel(_ friend: Friend) async {
        // Cancelling an outgoing request uses the same /reject endpoint.
        let targetEmail = friend.targetEmail
        guard !inFlight.contains(targetEmail) else { return }
        inFlight.insert(targetEmail)
        defer { inFlight.remove(targetEmail) }

        do {
            _ = try await xomify.rejectFriend(email: userEmail, requestEmail: targetEmail)
            outgoing.removeAll { $0.targetEmail == targetEmail }
            updateDiscoverFlags(for: targetEmail, clearAll: true)
        } catch {
            errorMessage = "Failed to cancel: \(error.localizedDescription)"
            print("❌ Friends: cancel failed - \(error)")
        }
    }

    func remove(_ friend: Friend) async {
        let targetEmail = friend.targetEmail
        guard !inFlight.contains(targetEmail) else { return }
        inFlight.insert(targetEmail)
        defer { inFlight.remove(targetEmail) }

        do {
            _ = try await xomify.removeFriend(email: userEmail, friendEmail: targetEmail)
            accepted.removeAll { $0.targetEmail == targetEmail }
            updateDiscoverFlags(for: targetEmail, clearAll: true)
        } catch {
            errorMessage = "Failed to remove: \(error.localizedDescription)"
            print("❌ Friends: remove failed - \(error)")
        }
    }

    // MARK: - Helpers

    private func updateDiscoverFlags(
        for email: String,
        isFriend: Bool? = nil,
        isOutgoing: Bool? = nil,
        clearAll: Bool = false
    ) {
        guard let idx = discover.firstIndex(where: { $0.email == email }) else { return }
        let existing = discover[idx]
        discover[idx] = SearchResult(
            email: existing.email,
            displayName: existing.displayName,
            avatar: existing.avatar,
            isFriend: clearAll ? false : (isFriend ?? existing.isFriend),
            isPending: clearAll ? false : ((isOutgoing ?? false) ? true : (existing.isPending ?? false)),
            isOutgoingRequest: clearAll ? false : (isOutgoing ?? existing.isOutgoingRequest),
            isIncomingRequest: clearAll ? false : existing.isIncomingRequest,
            mutualCount: existing.mutualCount
        )
    }
}
