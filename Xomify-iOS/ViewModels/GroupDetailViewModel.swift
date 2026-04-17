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

    /// User email inputs to add a member (typed inline).
    var addMemberEmail: String = ""
    var isAddingMember = false

    /// Spotify URL input for adding by URL.
    var addSongUrl: String = ""
    var isAddingSong = false

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
