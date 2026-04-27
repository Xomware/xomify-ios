import Foundation

/// ViewModel for the Groups list screen.
@Observable
@MainActor
final class GroupsViewModel {

    var userEmail: String = ""
    var groups: [XomifyGroup] = []

    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?
    var isCreating = false

    /// Non-fatal informational banner (e.g. "3 of 5 members added").
    var infoMessage: String?

    /// Accepted-friends cache used by the create-sheet picker.
    var friends: [Friend] = []
    var isLoadingFriends = false
    var friendsError: String?

    private let xomify = XomifyService.shared

    var isEmpty: Bool { groups.isEmpty }

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

        do {
            let response = try await xomify.listGroups()
            groups = response.groups ?? []
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Groups: load failed - \(error)")
        }

        isLoading = false
    }

    func refresh() async {
        guard !userEmail.isEmpty else { return }
        isRefreshing = true
        await load(email: userEmail)
        isRefreshing = false
    }

    // MARK: - Friends (for create-sheet picker)

    func loadFriends() async {
        guard !userEmail.isEmpty else { return }
        isLoadingFriends = true
        friendsError = nil
        defer { isLoadingFriends = false }

        do {
            let response = try await xomify.getAllFriends()
            friends = response.accepted ?? []
        } catch {
            friendsError = error.localizedDescription
            print("❌ Groups: loadFriends failed - \(error)")
        }
    }

    // MARK: - Create

    /// Creates a group and fans out `addMember` calls for each picked friend.
    /// Returns the created group on success, `nil` on failure. Partial add
    /// failures are surfaced via `infoMessage` ("N of M members added") — the
    /// group itself is still created.
    @discardableResult
    func create(
        name: String,
        memberEmails: [String] = [],
        description: String? = nil
    ) async -> XomifyGroup? {
        guard !userEmail.isEmpty, !name.isEmpty, !isCreating else { return nil }
        isCreating = true
        infoMessage = nil
        defer { isCreating = false }

        do {
            let response = try await xomify.createGroup(
                name: name,
                description: description
            )

            let created: XomifyGroup?
            if let group = response.group {
                created = group
                groups.insert(group, at: 0)
            } else {
                await load(email: userEmail)
                created = groups.first
            }

            guard let group = created else { return nil }

            // Fan-out add each picked member.
            if !memberEmails.isEmpty {
                var addedCount = 0
                for email in memberEmails {
                    do {
                        _ = try await xomify.addMember(
                            groupId: group.groupId,
                            memberEmail: email
                        )
                        addedCount += 1
                    } catch {
                        print("❌ Groups: addMember during create failed for \(email) - \(error)")
                    }
                }
                if addedCount < memberEmails.count {
                    infoMessage = "Group created. \(addedCount) of \(memberEmails.count) members added — try re-adding the rest from the group."
                }
                // Re-fetch to update memberCount on the list row.
                await load(email: userEmail)
            }

            return group
        } catch {
            errorMessage = "Failed to create group: \(error.localizedDescription)"
            print("❌ Groups: create failed - \(error)")
            return nil
        }
    }

    // MARK: - Leave

    func leave(_ group: XomifyGroup) async {
        do {
            _ = try await xomify.leaveGroup(groupId: group.groupId)
            groups.removeAll { $0.groupId == group.groupId }
        } catch {
            errorMessage = "Failed to leave group: \(error.localizedDescription)"
            print("❌ Groups: leave failed - \(error)")
        }
    }

    // MARK: - Delete (owner-only — caller gates by ownership)

    @discardableResult
    func delete(_ group: XomifyGroup) async -> Bool {
        do {
            _ = try await xomify.removeGroup(groupId: group.groupId)
            groups.removeAll { $0.groupId == group.groupId }
            return true
        } catch {
            errorMessage = "Failed to delete group: \(error.localizedDescription)"
            print("❌ Groups: delete failed - \(error)")
            return false
        }
    }
}
