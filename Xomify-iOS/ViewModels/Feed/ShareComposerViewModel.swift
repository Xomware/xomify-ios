import Foundation

// MARK: - Composer Targets
//
// Multi-target routing (xomify-backend#138). A share can hit the public
// friends feed, one-or-more groups, or both. Backend rejects
// `public=false` with no groups.

/// Validation state for the composer's target selection. Kept as a small
/// enum so the submit button can disable + show an inline hint without the
/// view duplicating the check.
enum ComposerTargetState: Equatable {
    case ok
    case noTargets  // public off AND no groups → backend would 400

    var hint: String? {
        switch self {
        case .ok:         return nil
        case .noTargets:  return "Pick at least one target."
        }
    }
}

/// Sub-protocol for `ShareComposerViewModel` — just track search.
/// Split from `SpotifyCurrentUserProviding` so the composer can mock only what it needs.
protocol SpotifyTrackSearching: Sendable {
    func searchTracks(query: String, limit: Int) async throws -> [SpotifyTrack]
}

extension SpotifyService: SpotifyTrackSearching {}

// MARK: - ShareComposerViewModel

/// Drives the composer sheet: track search → select → caption/mood/genres/audience → submit.
@Observable
@MainActor
final class ShareComposerViewModel {

    // MARK: - Constraints

    static let captionLimit: Int = 140
    static let maxGenreTags: Int = 3
    static let genreSuggestions: [String] = [
        "pop", "rock", "hip-hop", "rnb", "indie", "electronic",
        "country", "jazz", "classical", "metal", "folk", "latin"
    ]

    // MARK: - Search state

    var searchQuery: String = ""
    var searchResults: [SpotifyTrack] = []
    var isSearching: Bool = false
    var searchError: String?
    var selectedTrack: SpotifyTrack?

    // MARK: - Form state

    var caption: String = ""
    var selectedMood: MoodTag?
    var selectedGenres: [String] = []
    /// Whether to publish to the public friends feed. Defaults to true —
    /// matches the legacy single-target behavior.
    var shareToPublic: Bool = true
    /// Group ids the user has picked as additional (or exclusive) targets.
    var selectedGroupIds: Set<String> = []
    var availableGroups: [XomifyGroup] = []

    // MARK: - Submit state

    var isSubmitting: Bool = false
    var submitError: String?

    // MARK: - Dependencies

    private let xomifyService: XomifyServiceProtocol
    private let spotifyService: SpotifyTrackSearching
    private let currentUserProvider: SpotifyCurrentUserProviding

    private var userEmail: String = ""

    /// Debounce task for the search field. Cancelled on each keystroke.
    private var searchTask: Task<Void, Never>?

    // MARK: - Init

    init(
        xomifyService: XomifyServiceProtocol = XomifyService.shared,
        spotifyService: SpotifyTrackSearching = SpotifyService.shared,
        currentUserProvider: SpotifyCurrentUserProviding = SpotifyService.shared,
        prefilledGroupIds: Set<String> = [],
        defaultShareToPublic: Bool = true
    ) {
        self.xomifyService = xomifyService
        self.spotifyService = spotifyService
        self.currentUserProvider = currentUserProvider
        self.selectedGroupIds = prefilledGroupIds
        self.shareToPublic = defaultShareToPublic
    }

    // MARK: - Bootstrap

    /// Resolve the viewer email + load groups once on sheet appear.
    func bootstrap() async {
        if userEmail.isEmpty {
            if let user = try? await currentUserProvider.getCurrentUser(),
               let email = user.email, !email.isEmpty {
                userEmail = email
            }
        }
        if !userEmail.isEmpty, availableGroups.isEmpty {
            if let response = try? await xomifyService.listGroups(email: userEmail) {
                availableGroups = response.groups ?? []
            }
        }
    }

    // MARK: - Derived

    var captionRemaining: Int {
        Self.captionLimit - caption.count
    }

    var isCaptionValid: Bool {
        caption.count <= Self.captionLimit
    }

    var isGenreCountValid: Bool {
        selectedGenres.count <= Self.maxGenreTags
    }

    /// Backend rejects `public=false` with no groupIds — catch it client-side
    /// so the Post button can stay disabled instead of firing a 400.
    var targetState: ComposerTargetState {
        if !shareToPublic && selectedGroupIds.isEmpty { return .noTargets }
        return .ok
    }

    var canSubmit: Bool {
        selectedTrack != nil
            && isCaptionValid
            && isGenreCountValid
            && targetState == .ok
            && !isSubmitting
    }

    /// User-visible summary of the target selection — drives the small
    /// subtitle under the Targets section header.
    var targetSummary: String {
        switch (shareToPublic, selectedGroupIds.count) {
        case (true, 0):      return "Friends feed"
        case (true, let n):  return "Friends feed + \(n) group\(n == 1 ? "" : "s")"
        case (false, 0):     return "No targets"
        case (false, let n): return "\(n) group\(n == 1 ? "" : "s")"
        }
    }

    // MARK: - Search

    /// Debounced track search. Cancels any in-flight search on each call.
    func search() {
        searchTask?.cancel()

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        searchTask = Task { [weak self] in
            // 300ms debounce.
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            await self?.performSearch(query: query)
        }
    }

    /// Perform the actual network search. Split out so tests can call directly
    /// without waiting for the debounce.
    func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            let results = try await spotifyService.searchTracks(query: query, limit: 20)
            searchResults = results
        } catch {
            searchError = error.localizedDescription
            searchResults = []
        }
    }

    // MARK: - Form mutations

    func selectTrack(_ track: SpotifyTrack) {
        selectedTrack = track
        // Keep search state around in case the user wants to pick a different track.
    }

    func clearSelectedTrack() {
        selectedTrack = nil
    }

    /// Toggle membership of a group in the target set.
    func toggleGroup(_ groupId: String) {
        if selectedGroupIds.contains(groupId) {
            selectedGroupIds.remove(groupId)
        } else {
            selectedGroupIds.insert(groupId)
        }
    }

    /// Toggle a genre tag. Refuses to add a 4th tag.
    func toggleGenre(_ tag: String) {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }

        if let index = selectedGenres.firstIndex(of: normalized) {
            selectedGenres.remove(at: index)
        } else if selectedGenres.count < Self.maxGenreTags {
            selectedGenres.append(normalized)
        }
    }

    // MARK: - Submit

    /// Submit the composer. Returns the newly created `Share` on success (as
    /// an optimistic insertion target for the feed) or `nil` on failure.
    func submit() async -> Share? {
        guard canSubmit, let track = selectedTrack else { return nil }
        if userEmail.isEmpty {
            // Fall back if bootstrap hasn't resolved yet.
            if let user = try? await currentUserProvider.getCurrentUser(),
               let email = user.email, !email.isEmpty {
                userEmail = email
            } else {
                submitError = "Could not resolve user."
                return nil
            }
        }

        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedCaption: String? = trimmedCaption.isEmpty ? nil : trimmedCaption
        let capturedGenres: [String]? = selectedGenres.isEmpty ? nil : selectedGenres
        let capturedGroupIds: [String] = Array(selectedGroupIds)
        let capturedIsPublic: Bool = shareToPublic

        do {
            let response = try await xomifyService.createShare(
                email: userEmail,
                trackId: track.id,
                trackUri: track.uri ?? "",
                trackName: track.name,
                artistName: track.artistNames,
                albumName: track.album?.name,
                albumArtUrl: track.album?.imageUrl?.absoluteString,
                caption: capturedCaption,
                moodTag: selectedMood,
                genreTags: capturedGenres,
                groupIds: capturedGroupIds.isEmpty ? nil : capturedGroupIds,
                isPublic: capturedIsPublic
            )

            // Value-moment trigger for the APNs permission prompt — fire-and-forget.
            // `NotificationsService` gates on `hasPromptedForPush` so this only
            // ever surfaces the iOS dialog on the first successful share.
            Task { await NotificationsService.shared.requestPermissionIfNeeded() }

            if let returned = response.share {
                return returned
            }

            // Backend didn't echo the full share — synthesize one locally so the
            // feed can paint it optimistically. Next refresh will overwrite.
            return Share(
                shareId: response.shareId ?? UUID().uuidString,
                sharedBy: userEmail,
                sharedAt: Self.nowString(),
                trackId: track.id,
                trackUri: track.uri ?? "",
                trackName: track.name,
                artistName: track.artistNames,
                albumName: track.album?.name,
                albumArtUrl: track.album?.imageUrl?.absoluteString,
                caption: capturedCaption,
                moodTag: selectedMood,
                genreTags: capturedGenres,
                queuedCount: 0,
                ratedCount: 0,
                viewerHasQueued: false,
                viewerRating: nil,
                sharerRating: nil,
                groupIds: capturedGroupIds,
                isPublic: capturedIsPublic
            )
        } catch {
            submitError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Helpers

    private static func nowString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}
