import Foundation

/// ViewModel for the Friends screen. Four buckets:
/// - accepted friends,
/// - requests (incoming + outgoing in-app friend requests),
/// - discovery list of other users,
/// - incoming deep-link invites awaiting accept/decline.
///
/// Also owns invite-mint state for the "Invite a Friend" CTA.
@Observable
@MainActor
final class FriendsViewModel {

    // MARK: - State

    var userEmail: String = ""

    var accepted: [Friend] = []
    var incoming: [Friend] = []   // pending (others -> me)
    var outgoing: [Friend] = []   // requested (me -> others)
    var discover: [SearchResult] = []

    /// Deep-link invites the user has received. Sourced from the backend
    /// `/invites/pending` endpoint once it lands; renders as an empty list
    /// until then.
    var incomingInvites: [PendingInvite] = []

    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?

    // Invite-mint state for the Invite-a-Friend CTA.
    var isMintingInvite = false
    var lastMintedInvite: URL?
    var inviteMintError: String?

    /// Actions currently in flight, keyed by target email or invite code.
    /// Prevents double-taps.
    var inFlight: Set<String> = []

    private let xomify: any XomifyServicing

    // MARK: - Init

    init(xomify: any XomifyServicing = XomifyService.shared) {
        self.xomify = xomify
    }

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
        async let pendingInvites = loadPendingInvitesResult(email: email)

        do {
            let (friendsResp, usersResp, invitesResp) = try await (friendsBucket, allUsers, pendingInvites)
            accepted = friendsResp.accepted ?? []
            incoming = friendsResp.pending ?? []
            outgoing = friendsResp.requested ?? []
            discover = (usersResp.users ?? []).filter { $0.email != email }
            incomingInvites = invitesResp
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Friends: load failed - \(error)")
        }

        isLoading = false
    }

    /// Defensive wrapper around `listPendingInvites` — the backend endpoint is
    /// pending, so any error is swallowed here to avoid nuking the whole load.
    /// Returns an empty list on failure.
    private func loadPendingInvitesResult(email: String) async -> [PendingInvite] {
        do {
            let response = try await xomify.listPendingInvites(email: email)
            return response.invites ?? []
        } catch {
            // Endpoint not yet deployed — render an empty list. Not a fatal error.
            print("ℹ️ Friends: listPendingInvites unavailable - \(error.localizedDescription)")
            return []
        }
    }

    func refresh() async {
        guard !userEmail.isEmpty else { return }
        isRefreshing = true
        await load(email: userEmail)
        isRefreshing = false
    }

    // MARK: - Friend actions

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
            // Value-moment: first accepted friend request is a solid signal the
            // user wants to engage — prompt for push permission if we haven't.
            Task { await NotificationsService.shared.requestPermissionIfNeeded() }
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

    // MARK: - Invite mint

    /// Mint a fresh invite code + share URL for the current user. Updates
    /// `lastMintedInvite` on success, which the view observes to present the
    /// iOS share sheet.
    func mintInvite() async {
        guard !userEmail.isEmpty else {
            inviteMintError = "Please log in first"
            return
        }
        guard !isMintingInvite else { return }
        isMintingInvite = true
        inviteMintError = nil
        lastMintedInvite = nil

        do {
            let response = try await xomify.createInvite(email: userEmail)
            guard let shareUrl = response.shareUrl, let url = URL(string: shareUrl) else {
                inviteMintError = "Invite minted but URL was missing"
                isMintingInvite = false
                return
            }
            lastMintedInvite = url
        } catch {
            inviteMintError = "Failed to create invite: \(error.localizedDescription)"
            print("❌ Friends: mintInvite failed - \(error)")
        }

        isMintingInvite = false
    }

    /// Clear the last minted invite — call after the share sheet has been
    /// dismissed so the sheet can re-present cleanly on a future mint.
    func clearMintedInvite() {
        lastMintedInvite = nil
    }

    // MARK: - Incoming invite actions

    /// Accept an incoming deep-link invite by code.
    func acceptInvite(_ invite: PendingInvite) async {
        await acceptInvite(code: invite.inviteCode)
    }

    /// Accept a deep-link invite by its raw code. Used by both the in-app
    /// Invites list and the Universal-Link-triggered auto-accept flow.
    func acceptInvite(code: String) async {
        guard !userEmail.isEmpty else {
            errorMessage = "Please log in first"
            return
        }
        guard !inFlight.contains(code) else { return }
        inFlight.insert(code)
        defer { inFlight.remove(code) }

        do {
            let response = try await xomify.acceptInvite(email: userEmail, inviteCode: code)
            // Value-moment: accepting a deep-link invite = user just crossed a
            // meaningful threshold. Prompt for push permission if we haven't.
            Task { await NotificationsService.shared.requestPermissionIfNeeded() }
            // Remove the accepted row from the pending list.
            if let senderEmail = incomingInvites.first(where: { $0.inviteCode == code })?.senderEmail {
                incomingInvites.removeAll { $0.inviteCode == code }
                // Optimistically promote the sender to accepted if we can
                // reflect the friendship without a full refetch.
                if let friendEmail = response.friendEmail ?? Optional(senderEmail) {
                    let exists = accepted.contains { $0.targetEmail == friendEmail }
                    if !exists {
                        accepted.append(Friend(
                            email: userEmail,
                            friendEmail: friendEmail,
                            displayName: nil,
                            avatar: nil,
                            status: "accepted",
                            direction: "incoming",
                            createdAt: ISO8601DateFormatter().string(from: Date()),
                            mutualCount: nil
                        ))
                    }
                }
            } else {
                // Code came from a deep link — we may have no row to remove,
                // that's fine; just trigger a refresh to resync state.
                await refresh()
            }
        } catch {
            errorMessage = "Failed to accept invite: \(error.localizedDescription)"
            print("❌ Friends: acceptInvite failed - \(error)")
        }
    }

    /// Decline an incoming deep-link invite.
    func declineInvite(_ invite: PendingInvite) async {
        let code = invite.inviteCode
        guard !inFlight.contains(code) else { return }
        inFlight.insert(code)
        defer { inFlight.remove(code) }

        // Optimistic removal — restore on failure.
        let snapshot = incomingInvites
        incomingInvites.removeAll { $0.inviteCode == code }

        do {
            _ = try await xomify.declineInvite(email: userEmail, inviteCode: code)
        } catch {
            // Restore the row and surface the error — but only if the failure
            // wasn't "endpoint missing" (404/5xx). We still clear client-side
            // because the row has no other way out; flag via errorMessage.
            incomingInvites = snapshot.filter { $0.inviteCode != code }
            errorMessage = "Decline not yet supported: \(error.localizedDescription)"
            print("ℹ️ Friends: declineInvite failed - \(error)")
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
