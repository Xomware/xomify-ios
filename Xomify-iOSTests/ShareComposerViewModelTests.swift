import XCTest
@testable import Xomify_iOS

// MARK: - Minimal mock for SpotifyTrackSearching

private final class MockSpotifyTrackSearching: SpotifyTrackSearching, @unchecked Sendable {
    var results: [SpotifyTrack] = []
    func searchTracks(query: String, limit: Int) async throws -> [SpotifyTrack] {
        return results
    }
}

// MARK: - Helpers

private func makeTrack(id: String = "track-1", name: String = "Test Track") -> SpotifyTrack {
    SpotifyTrack(
        id: id,
        name: name,
        uri: "spotify:track:\(id)",
        durationMs: 200_000,
        explicit: false,
        popularity: nil,
        previewUrl: nil,
        album: nil,
        artists: [SpotifyArtist(id: "a1", name: "Artist", uri: nil, genres: nil, popularity: nil, followers: nil, images: nil, externalUrls: nil)],
        externalUrls: nil
    )
}

// MARK: - Tests

@MainActor
final class ShareComposerViewModelTests: XCTestCase {

    // MARK: - Rating passthrough

    func test_submit_withRating_passesRatingToCreateShare() async {
        let service = MockXomifyServiceProtocol()
        let spotify = MockSpotifyCurrentUserProviding()
        let search = MockSpotifyTrackSearching()

        let vm = ShareComposerViewModel(
            xomifyService: service,
            spotifyService: search,
            currentUserProvider: spotify
        )

        vm.selectTrack(makeTrack())
        vm.selectedRating = 4

        let share = await vm.submit()

        XCTAssertNotNil(share)
        XCTAssertEqual(service.createShareCalls.count, 1)
        XCTAssertEqual(service.createShareCalls.first?.rating, 4)
    }

    func test_submit_withoutRating_sendsNilRating() async {
        let service = MockXomifyServiceProtocol()
        let spotify = MockSpotifyCurrentUserProviding()
        let search = MockSpotifyTrackSearching()

        let vm = ShareComposerViewModel(
            xomifyService: service,
            spotifyService: search,
            currentUserProvider: spotify
        )

        vm.selectTrack(makeTrack())
        // selectedRating is nil by default — no rating attached.

        let share = await vm.submit()

        XCTAssertNotNil(share)
        XCTAssertEqual(service.createShareCalls.count, 1)
        XCTAssertNil(service.createShareCalls.first?.rating)
    }

    func test_submit_ratingAppearsOnOptimisticShare() async {
        let service = MockXomifyServiceProtocol()
        // Return a response with no embedded Share so the VM synthesizes one.
        service.createShareResult = ShareCreateResponse(success: true, shareId: "s1", share: nil)

        let spotify = MockSpotifyCurrentUserProviding()
        let search = MockSpotifyTrackSearching()

        let vm = ShareComposerViewModel(
            xomifyService: service,
            spotifyService: search,
            currentUserProvider: spotify
        )

        vm.selectTrack(makeTrack())
        vm.selectedRating = 3

        let share = await vm.submit()

        XCTAssertEqual(share?.sharerRating, 3)
        XCTAssertEqual(share?.viewerRating, 3)
    }
}
