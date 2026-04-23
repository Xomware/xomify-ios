import Foundation

/// ViewModel for a single group's detail screen: members + tracks.
@Observable
@MainActor
final class GroupDetailViewModel {

    var userEmail: String = ""
    var groupId: String = ""

    var group: XomifyGroup?
    var members: [GroupMember] = []
    var tracks: [GroupTrack] = []

    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?

    /// User email inputs to add a member (typed inline / by-email fallback).
    var addMemberEmail: String = ""
    var isAddingMember = false

    /// Spotify URL input for adding by URL.
    var addSongUrl: String = ""
    var isAddingSong = false

    /// Accepted-friends cache used by the add-member sheet picker.
    var friends: [Friend] = []
    var isLoadingFriends = false
    var friendsError: String?

    private let xomify = XomifyService.shared

    // MARK: - Load

    func load(email: String, groupId: String) async {
        guard !email.isEmpty, !groupId.isEmpty else {
            errorMessage = "Missing required info"
            return
        }
        userEmail = email
        self.groupId = groupId
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let info = try await xomify.getGroupInfo(groupId: groupId, email: email)
            group = info.group
            members = info.members ?? []
            tracks = info.tracks ?? []
        } catch {
            errorMessage = error.localizedDescription
            print("❌ GroupDetail: load failed - \(error)")
        }

        isLoading = false
    }

    func refresh() async {
        guard !groupId.isEmpty else { return }
        isRefreshing = true
        await load(email: userEmail, groupId: groupId)
        isRefreshing = false
    }

    // MARK: - Friends (for add-member picker)

    func loadFriends() async {
        guard !userEmail.isEmpty else { return }
        isLoadingFriends = true
        friendsError = nil
        defer { isLoadingFriends = false }

        do {
            let response = try await xomify.getAllFriends(email: userEmail)
            friends = response.accepted ?? []
        } catch {
            friendsError = error.localizedDescription
            print("❌ GroupDetail: loadFriends failed - \(error)")
        }
    }

    // MARK: - Members

    func addMember() async {
        let target = addMemberEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !isAddingMember else { return }
        isAddingMember = true
        defer { isAddingMember = false }

        do {
            _ = try await xomify.addMember(email: userEmail, groupId: groupId, memberEmail: target)
            addMemberEmail = ""
            await refresh()
        } catch {
            errorMessage = "Failed to add member: \(error.localizedDescription)"
            print("❌ GroupDetail: addMember failed - \(error)")
        }
    }

    /// Batch-add members via the friend picker. Optimistically inserts a
    /// skeleton row per email, rolls back the skeleton on a per-email failure,
    /// and finishes with a `refresh()` so server-canonical display names and
    /// `joinedAt` land. Partial failures are reported via `errorMessage`.
    func addMembers(_ emails: [String]) async {
        let clean = emails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }

        var succeeded = 0
        var failures: [String] = []

        for email in clean {
            // Optimistic insert (skip duplicates).
            let alreadyPresent = members.contains { $0.email == email }
            if !alreadyPresent {
                members.append(GroupMember(
                    email: email,
                    displayName: nil,
                    joinedAt: nil,
                    isOwner: false
                ))
            }

            do {
                _ = try await xomify.addMember(
                    email: userEmail,
                    groupId: groupId,
                    memberEmail: email
                )
                succeeded += 1
            } catch {
                // Roll back the skeleton we inserted.
                if !alreadyPresent {
                    members.removeAll { $0.email == email && $0.displayName == nil && $0.joinedAt == nil }
                }
                failures.append(email)
                print("❌ GroupDetail: addMembers failed for \(email) - \(error)")
            }
        }

        if succeeded == clean.count {
            // Pull canonical rows (display names, joinedAt).
            await refresh()
        } else if succeeded > 0 {
            errorMessage = "Added \(succeeded) of \(clean.count) — \(failures.count) failed."
            await refresh()
        } else {
            errorMessage = "Couldn't add any members. Please try again."
        }
    }

    func removeMember(_ member: GroupMember) async {
        do {
            _ = try await xomify.removeMember(
                email: userEmail,
                groupId: groupId,
                memberEmail: member.email
            )
            members.removeAll { $0.email == member.email }
        } catch {
            errorMessage = "Failed to remove member: \(error.localizedDescription)"
            print("❌ GroupDetail: removeMember failed - \(error)")
        }
    }

    // MARK: - Leave / Delete (pessimistic)

    /// Non-owner leave. Returns `true` on success so the view can dismiss.
    @discardableResult
    func leave() async -> Bool {
        guard !userEmail.isEmpty, !groupId.isEmpty else { return false }
        do {
            _ = try await xomify.leaveGroup(email: userEmail, groupId: groupId)
            return true
        } catch {
            errorMessage = "Failed to leave group: \(error.localizedDescription)"
            print("❌ GroupDetail: leave failed - \(error)")
            return false
        }
    }

    /// Owner-only delete. Caller MUST verify `group?.ownerEmail == userEmail`
    /// before invoking. Returns `true` on success.
    @discardableResult
    func delete() async -> Bool {
        guard !userEmail.isEmpty, !groupId.isEmpty else { return false }
        do {
            _ = try await xomify.removeGroup(email: userEmail, groupId: groupId)
            return true
        } catch {
            errorMessage = "Failed to delete group: \(error.localizedDescription)"
            print("❌ GroupDetail: delete failed - \(error)")
            return false
        }
    }

    // MARK: - Songs

    func addSongByUrl() async {
        let url = addSongUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !isAddingSong else { return }
        isAddingSong = true
        defer { isAddingSong = false }

        do {
            _ = try await xomify.addSongByUrl(
                email: userEmail,
                groupId: groupId,
                trackUrl: url
            )
            addSongUrl = ""
            await refresh()
        } catch {
            errorMessage = "Failed to add song: \(error.localizedDescription)"
            print("❌ GroupDetail: addSong failed - \(error)")
        }
    }

    func removeSong(_ track: GroupTrack) async {
        do {
            _ = try await xomify.removeSong(
                email: userEmail,
                groupId: groupId,
                trackIdTimestamp: track.trackIdTimestamp
            )
            tracks.removeAll { $0.trackIdTimestamp == track.trackIdTimestamp }
        } catch {
            errorMessage = "Failed to remove song: \(error.localizedDescription)"
            print("❌ GroupDetail: removeSong failed - \(error)")
        }
    }

    func markAllListened() async {
        do {
            _ = try await xomify.markAllListened(email: userEmail, groupId: groupId)
            await refresh()
        } catch {
            errorMessage = "Failed to mark listened: \(error.localizedDescription)"
            print("❌ GroupDetail: markAllListened failed - \(error)")
        }
    }
}
