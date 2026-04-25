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

    /// Viewer's own display name + avatar — used to enrich the self-row in
    /// the members tab when the backend's GroupMember payload doesn't carry
    /// displayName/avatar fields. (Backend follow-up: enrich `/groups/info`
    /// member list with profile data so this hop isn't needed.)
    var viewerDisplayName: String?
    var viewerAvatarURL: URL?

    /// Shares posted to this group (the new primary content surface — replaces
    /// the legacy `tracks` list driven by `/groups/add-song`).
    var shares: [Share] = []
    var isLoadingShares = false
    var sharesError: String?

    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?

    /// User email inputs to add a member (typed inline / by-email fallback).
    var addMemberEmail: String = ""
    var isAddingMember = false

    /// Spotify URL input for adding by URL (legacy paste-URL flow, still
    /// supported as a fallback on the Add Song sheet).
    var addSongUrl: String = ""
    var isAddingSong = false

    /// Search state for the Add Song sheet.
    var songSearchQuery: String = ""
    var songSearchResults: [SpotifyTrack] = []
    var isSearchingSongs = false
    var songSearchError: String?

    /// Track IDs currently being added from the search results — used to
    /// disable the individual row while the network call is in flight.
    var addingTrackIds: Set<String> = []

    /// Monotonic counter on search task IDs so a stale query response can't
    /// overwrite results from a newer query.
    private var songSearchToken: Int = 0

    /// Edit-group form state (owner-only).
    var isSavingEdit = false

    /// Accepted-friends cache used by the add-member sheet picker.
    var friends: [Friend] = []
    var isLoadingFriends = false
    var friendsError: String?

    private let xomify = XomifyService.shared
    private let spotify = SpotifyService.shared

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

        // Fetch viewer profile for self-row enrichment. Best-effort; failures
        // just leave the row showing email + initial.
        if viewerDisplayName == nil {
            do {
                let me = try await spotify.getCurrentUser()
                viewerDisplayName = me.displayName
                viewerAvatarURL = me.profileImageUrl
            } catch {
                // silent — non-critical
            }
        }

        isLoading = false

        // Group-scoped shares feed lives under a separate request — kick it
        // off after the group/members payload so the header/members tab can
        // paint immediately.
        await loadShares()
    }

    func refresh() async {
        guard !groupId.isEmpty else { return }
        isRefreshing = true
        await load(email: userEmail, groupId: groupId)
        await loadShares()
        isRefreshing = false
    }

    // MARK: - Shares (group-scoped feed)

    /// Pulls shares scoped to this group via `/shares/feed?groupId=…`. Replaces
    /// the legacy `tracks` list as the primary content surface.
    func loadShares() async {
        guard !userEmail.isEmpty, !groupId.isEmpty else { return }
        isLoadingShares = true
        sharesError = nil
        defer { isLoadingShares = false }

        do {
            let response = try await xomify.getFeed(
                email: userEmail,
                groupId: groupId,
                limit: 50,
                before: nil
            )
            shares = response.shares ?? []
        } catch {
            sharesError = error.localizedDescription
            print("❌ GroupDetail: loadShares failed - \(error)")
        }
    }

    // MARK: - Stats (derived from `shares`)

    /// Per-user breakdown for the Stats tab.
    struct GroupUserStat: Identifiable, Hashable {
        let email: String
        let displayName: String
        let avatarURL: URL?
        let shareCount: Int
        let averageRating: Double?
        var id: String { email }
    }

    var totalShareCount: Int { shares.count }

    /// Average sharer-supplied rating across all loaded shares (the rating the
    /// poster gave when they shared). Nil when nobody rated.
    var averageSharerRating: Double? {
        let ratings = shares.compactMap { $0.sharerRating }
        guard !ratings.isEmpty else { return nil }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    /// Shares grouped by sharer email with count + average rating, sorted by
    /// share count desc.
    var perUserStats: [GroupUserStat] {
        let grouped = Dictionary(grouping: shares, by: { $0.sharedBy })
        return grouped.map { (email, posts) in
            let ratings = posts.compactMap { $0.sharerRating }
            let avg = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
            let member = members.first { $0.email == email }
            let resolvedName: String
            if email == userEmail, let mine = viewerDisplayName, !mine.isEmpty {
                resolvedName = mine
            } else {
                resolvedName = member?.label ?? email
            }
            let avatar = (email == userEmail) ? viewerAvatarURL : nil
            return GroupUserStat(
                email: email,
                displayName: resolvedName,
                avatarURL: avatar,
                shareCount: posts.count,
                averageRating: avg
            )
        }
        .sorted { $0.shareCount > $1.shareCount }
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

    // MARK: - Edit (owner-only)

    /// Owner-only edit of name + description. Optimistically patches `group`
    /// on success so the header re-renders without waiting for refresh.
    /// Returns `true` on success so the sheet can dismiss.
    @discardableResult
    func saveEdit(name: String, description: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !groupId.isEmpty, !userEmail.isEmpty else {
            errorMessage = "Name is required"
            return false
        }
        guard !isSavingEdit else { return false }
        isSavingEdit = true
        defer { isSavingEdit = false }

        do {
            _ = try await xomify.updateGroup(
                email: userEmail,
                groupId: groupId,
                name: trimmedName,
                description: trimmedDesc
            )
            if let current = group {
                group = XomifyGroup(
                    groupId: current.groupId,
                    name: trimmedName,
                    description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                    ownerEmail: current.ownerEmail,
                    createdBy: current.createdBy,
                    createdAt: current.createdAt,
                    memberCount: current.memberCount,
                    trackCount: current.trackCount,
                    imageUrl: current.imageUrl,
                    role: current.role,
                    joinedAt: current.joinedAt
                )
            }
            return true
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            print("❌ GroupDetail: saveEdit failed - \(error)")
            return false
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

    /// Run a Spotify track search for the Add Song sheet. Guards against
    /// stale completions — only the most recent query's results are applied.
    func searchSongs() async {
        let query = songSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            songSearchResults = []
            songSearchError = nil
            return
        }

        songSearchToken &+= 1
        let token = songSearchToken
        isSearchingSongs = true
        songSearchError = nil

        do {
            let results = try await spotify.searchTracks(query: query, limit: 25)
            guard token == songSearchToken else { return }
            songSearchResults = results
        } catch {
            guard token == songSearchToken else { return }
            songSearchError = error.localizedDescription
            songSearchResults = []
        }

        if token == songSearchToken {
            isSearchingSongs = false
        }
    }

    /// Clear search state when the Add Song sheet closes.
    func resetSongSearch() {
        songSearchQuery = ""
        songSearchResults = []
        songSearchError = nil
        addingTrackIds = []
        isSearchingSongs = false
    }

    /// Add a track from a Spotify search result. Shows a per-row spinner
    /// via `addingTrackIds` so the rest of the list stays tappable.
    func addSong(_ track: SpotifyTrack) async {
        guard !addingTrackIds.contains(track.id) else { return }
        addingTrackIds.insert(track.id)
        defer { addingTrackIds.remove(track.id) }

        do {
            _ = try await xomify.addSong(
                email: userEmail,
                groupId: groupId,
                trackId: track.id,
                trackName: track.name,
                artistName: track.artistNames,
                albumName: track.album?.name,
                imageUrl: track.album?.images?.first?.url
            )
            await refresh()
        } catch {
            errorMessage = "Failed to add song: \(error.localizedDescription)"
            print("❌ GroupDetail: addSong failed - \(error)")
        }
    }

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
