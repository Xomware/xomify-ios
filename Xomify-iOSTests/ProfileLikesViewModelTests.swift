import XCTest
@testable import Xomify_iOS

// MARK: - Mock

/// Canned `SpotifyLikesProviding` for unit-testing `LikesViewModel`.
final class MockSpotifyLikesProviding: SpotifyLikesProviding, @unchecked Sendable {

    struct Call: Equatable {
        let limit: Int
        let offset: Int
    }

    private(set) var calls: [Call] = []
    /// Queue of responses; each `getSavedTracks` call consumes one.
    var responses: [SavedTracksResponse] = []
    var error: Error?

    func getSavedTracks(limit: Int, offset: Int) async throws -> SavedTracksResponse {
        calls.append(Call(limit: limit, offset: offset))
        if let error { throw error }
        guard !responses.isEmpty else {
            return SavedTracksResponse(items: [], total: 0, limit: limit, offset: offset)
        }
        return responses.removeFirst()
    }
}

// MARK: - Helpers

private func makeSavedTrack(id: String = UUID().uuidString) -> SpotifySavedTrack {
    SpotifySavedTrack(
        addedAt: nil,
        track: SpotifyTrack(
            id: id,
            name: "Track \(id)",
            uri: "spotify:track:\(id)",
            durationMs: 180_000,
            artists: [],
            album: nil,
            externalUrls: nil,
            previewUrl: nil,
            popularity: nil,
            explicit: nil
        )
    )
}

private func makeResponse(
    items: [SpotifySavedTrack],
    total: Int,
    offset: Int = 0,
    limit: Int = 50
) -> SavedTracksResponse {
    SavedTracksResponse(items: items, total: total, limit: limit, offset: offset)
}

// MARK: - Tests

@MainActor
final class ProfileLikesViewModelTests: XCTestCase {

    // MARK: - Initial load

    func test_loadIfNeeded_populatesItemsAndTotal() async {
        let mock = MockSpotifyLikesProviding()
        let tracks = (0..<3).map { makeSavedTrack(id: "t\($0)") }
        mock.responses = [makeResponse(items: tracks, total: 3)]

        let vm = LikesViewModel(source: .spotifyDirect, spotifyService: mock)
        await vm.loadIfNeeded()

        XCTAssertEqual(vm.items.count, 3)
        XCTAssertEqual(vm.total, 3)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isLoadingMore)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(mock.calls[0].offset, 0)
    }

    func test_loadIfNeeded_isIdempotent() async {
        let mock = MockSpotifyLikesProviding()
        let tracks = [makeSavedTrack()]
        mock.responses = [makeResponse(items: tracks, total: 1)]

        let vm = LikesViewModel(source: .spotifyDirect, spotifyService: mock)
        await vm.loadIfNeeded()
        await vm.loadIfNeeded() // second call should no-op

        XCTAssertEqual(mock.calls.count, 1)
    }

    // MARK: - Pagination

    func test_loadMore_appendsAndIncrementsOffset() async {
        let mock = MockSpotifyLikesProviding()
        let page1 = (0..<50).map { makeSavedTrack(id: "p1_\($0)") }
        let page2 = (0..<10).map { makeSavedTrack(id: "p2_\($0)") }
        mock.responses = [
            makeResponse(items: page1, total: 60, offset: 0),
            makeResponse(items: page2, total: 60, offset: 50)
        ]

        let vm = LikesViewModel(source: .spotifyDirect, spotifyService: mock)
        await vm.loadIfNeeded()
        XCTAssertEqual(vm.items.count, 50)
        XCTAssertTrue(vm.hasMore)

        await vm.loadMore()
        XCTAssertEqual(vm.items.count, 60)
        XCTAssertFalse(vm.hasMore)

        XCTAssertEqual(mock.calls.count, 2)
        XCTAssertEqual(mock.calls[1].offset, 50)
    }

    // MARK: - hasMore

    func test_hasMore_falseWhenAllTracksLoaded() async {
        let mock = MockSpotifyLikesProviding()
        let tracks = (0..<5).map { makeSavedTrack(id: "t\($0)") }
        mock.responses = [makeResponse(items: tracks, total: 5)]

        let vm = LikesViewModel(source: .spotifyDirect, spotifyService: mock)
        await vm.loadIfNeeded()

        XCTAssertFalse(vm.hasMore)
    }

    func test_hasMore_trueWhenMorePagesExist() async {
        let mock = MockSpotifyLikesProviding()
        let tracks = (0..<50).map { makeSavedTrack(id: "t\($0)") }
        mock.responses = [makeResponse(items: tracks, total: 200)]

        let vm = LikesViewModel(source: .spotifyDirect, spotifyService: mock)
        await vm.loadIfNeeded()

        XCTAssertTrue(vm.hasMore)
    }

    func test_loadMore_noopsWhenNoMore() async {
        let mock = MockSpotifyLikesProviding()
        let tracks = [makeSavedTrack()]
        mock.responses = [makeResponse(items: tracks, total: 1)]

        let vm = LikesViewModel(source: .spotifyDirect, spotifyService: mock)
        await vm.loadIfNeeded()
        XCTAssertFalse(vm.hasMore)

        await vm.loadMore()

        XCTAssertEqual(mock.calls.count, 1) // no second call
    }

    // MARK: - Error handling

    func test_loadIfNeeded_errorSetsErrorMessageAndEmptyItems() async {
        let mock = MockSpotifyLikesProviding()
        mock.error = NSError(
            domain: "spotify", code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Unauthorized"]
        )

        let vm = LikesViewModel(source: .spotifyDirect, spotifyService: mock)
        await vm.loadIfNeeded()

        XCTAssertEqual(vm.errorMessage, "Unauthorized")
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertNil(vm.total)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Refresh

    func test_refresh_resetsToPage1() async {
        let mock = MockSpotifyLikesProviding()
        let firstLoad = (0..<50).map { makeSavedTrack(id: "first_\($0)") }
        let refreshLoad = (0..<3).map { makeSavedTrack(id: "refresh_\($0)") }
        mock.responses = [
            makeResponse(items: firstLoad, total: 50),
            makeResponse(items: refreshLoad, total: 3)
        ]

        let vm = LikesViewModel(source: .spotifyDirect, spotifyService: mock)
        await vm.loadIfNeeded()
        XCTAssertEqual(vm.items.count, 50)

        await vm.refresh()
        XCTAssertEqual(vm.items.count, 3)
        XCTAssertEqual(vm.total, 3)
        XCTAssertEqual(mock.calls[1].offset, 0)
    }

    // MARK: - Re-entrancy guard

    func test_loadMore_noopsWhenIsLoading() async {
        let mock = MockSpotifyLikesProviding()
        mock.responses = [makeResponse(items: [makeSavedTrack()], total: 100)]

        let vm = LikesViewModel(source: .spotifyDirect, spotifyService: mock)
        await vm.loadIfNeeded()

        XCTAssertEqual(mock.calls.count, 1)
    }

    // MARK: - Backend source (friend likes)

    func test_backendSource_populatesItemsFromBackend() async {
        let mockSpotify = MockSpotifyLikesProviding()
        let mockXomify = MockXomifyServiceProtocol()
        let backendTracks = [
            LikesByUserTrack(trackId: "t1", trackName: "Song A", artistName: "Artist X", albumArt: nil, addedAt: nil),
            LikesByUserTrack(trackId: "t2", trackName: "Song B", artistName: "Artist Y", albumArt: nil, addedAt: nil)
        ]
        mockXomify.getLikesByUserResponse = LikesByUserResponse(
            tracks: backendTracks, total: 2, hasMore: false, likesPublic: true
        )

        let vm = LikesViewModel(
            source: .backend(callerEmail: "me@example.com", targetEmail: "friend@example.com"),
            spotifyService: mockSpotify,
            xomifyService: mockXomify
        )
        await vm.loadIfNeeded()

        XCTAssertEqual(vm.items.count, 2)
        XCTAssertEqual(vm.items[0].name, "Song A")
        XCTAssertEqual(vm.items[1].artistNames, "Artist Y")
        XCTAssertEqual(mockXomify.getLikesByUserCalls.count, 1)
        XCTAssertEqual(mockXomify.getLikesByUserCalls[0].targetEmail, "friend@example.com")
    }
}
