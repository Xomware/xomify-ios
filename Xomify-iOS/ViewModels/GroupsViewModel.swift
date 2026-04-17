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
            let response = try await xomify.listGroups(email: email)
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

    // MARK: - Create

    @discardableResult
    func create(name: String, description: String?) async -> XomifyGroup? {
        guard !userEmail.isEmpty, !name.isEmpty, !isCreating else { return nil }
        isCreating = true
        defer { isCreating = false }

        do {
            let response = try await xomify.createGroup(
                email: userEmail,
                name: name,
                description: description
            )
            // Prefer server response's group; fall back to reload.
            if let group = response.group {
                groups.insert(group, at: 0)
                return group
            }
            await load(email: userEmail)
            return groups.first
        } catch {
            errorMessage = "Failed to create group: \(error.localizedDescription)"
            print("❌ Groups: create failed - \(error)")
            return nil
        }
    }

    // MARK: - Leave

    func leave(_ group: XomifyGroup) async {
        do {
            _ = try await xomify.leaveGroup(email: userEmail, groupId: group.groupId)
            groups.removeAll { $0.groupId == group.groupId }
        } catch {
            errorMessage = "Failed to leave group: \(error.localizedDescription)"
            print("❌ Groups: leave failed - \(error)")
        }
    }
}
