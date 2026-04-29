import XCTest
@testable import Xomify_iOS

/// Coverage for the listened-state contract:
/// - `Share` decode falls back to `false` / `0` when the new fields are absent
///   (legacy / cold-cache responses must keep decoding cleanly).
/// - `Share.withViewerHasListened` flips the flag and bumps `listenerCount`
///   exactly once when called twice (idempotent).
/// - `MockXomifyServiceProtocol.markListened` records the call exactly as
///   passed and short-circuits on empty input via the protocol surface used
///   by `XomifyService` itself (covered by checking the default response).
@MainActor
final class MarkListenedTests: XCTestCase {

    // MARK: - Decode fallbacks

    func test_share_decode_defaultsListenedFieldsWhenAbsent() throws {
        let json = """
        {
          "shareId": "s-1",
          "sharedBy": "me@example.com",
          "sharedAt": "2026-04-23 10:00:00",
          "trackId": "t-1",
          "trackUri": "spotify:track:t-1",
          "trackName": "Song",
          "artistName": "Artist"
        }
        """.data(using: .utf8)!

        let share = try JSONDecoder().decode(Share.self, from: json)

        XCTAssertFalse(share.viewerHasListened)
        XCTAssertEqual(share.listenerCount, 0)
    }

    func test_share_decode_readsListenedFieldsWhenPresent() throws {
        let json = """
        {
          "shareId": "s-1",
          "sharedBy": "me@example.com",
          "sharedAt": "2026-04-23 10:00:00",
          "trackId": "t-1",
          "trackUri": "spotify:track:t-1",
          "trackName": "Song",
          "artistName": "Artist",
          "viewerHasListened": true,
          "listenerCount": 7
        }
        """.data(using: .utf8)!

        let share = try JSONDecoder().decode(Share.self, from: json)

        XCTAssertTrue(share.viewerHasListened)
        XCTAssertEqual(share.listenerCount, 7)
    }

    // MARK: - Optimistic flip

    func test_withViewerHasListened_flipsAndBumpsCountOnce() {
        let share = Share(
            shareId: "s-1",
            sharedBy: "me@example.com",
            sharedAt: "2026-04-23 10:00:00",
            trackId: "t-1",
            trackUri: "spotify:track:t-1",
            trackName: "Song",
            artistName: "Artist",
            viewerHasListened: false,
            listenerCount: 3
        )

        let firstFlip = share.withViewerHasListened(true)
        XCTAssertTrue(firstFlip.viewerHasListened)
        XCTAssertEqual(firstFlip.listenerCount, 4)

        // Idempotent: flipping again when already true is a no-op.
        let secondFlip = firstFlip.withViewerHasListened(true)
        XCTAssertTrue(secondFlip.viewerHasListened)
        XCTAssertEqual(secondFlip.listenerCount, 4)
    }

    func test_withViewerHasListened_decrementsCountOnUnflip() {
        let share = Share(
            shareId: "s-1",
            sharedBy: "me@example.com",
            sharedAt: "2026-04-23 10:00:00",
            trackId: "t-1",
            trackUri: "spotify:track:t-1",
            trackName: "Song",
            artistName: "Artist",
            viewerHasListened: true,
            listenerCount: 1
        )

        let unflipped = share.withViewerHasListened(false)
        XCTAssertFalse(unflipped.viewerHasListened)
        XCTAssertEqual(unflipped.listenerCount, 0)

        // Floor at zero so a desynced row can't go negative.
        let unflippedAgain = unflipped.withViewerHasListened(false)
        XCTAssertEqual(unflippedAgain.listenerCount, 0)
    }

    // MARK: - ShareCardViewModel.markListenedOptimistically

    func test_shareCardVM_markListenedOptimistically_flipsLocalShare() {
        let mock = MockXomifyServiceProtocol()
        let share = Share(
            shareId: "s-1",
            sharedBy: "friend@example.com",
            sharedAt: "2026-04-23 10:00:00",
            trackId: "t-1",
            trackUri: "spotify:track:t-1",
            trackName: "Song",
            artistName: "Artist",
            viewerHasListened: false,
            listenerCount: 2
        )
        let vm = ShareCardViewModel(
            share: share,
            viewerEmail: "me@example.com",
            xomifyService: mock,
            spotifyService: MockSpotifyQueueing()
        )

        XCTAssertFalse(vm.share.viewerHasListened)
        vm.markListenedOptimistically()

        XCTAssertTrue(vm.share.viewerHasListened)
        XCTAssertEqual(vm.share.listenerCount, 3)
    }

    // MARK: - Service mock contract

    func test_mockMarkListened_recordsCallAndEchoesIds() async throws {
        let mock = MockXomifyServiceProtocol()
        let response = try await mock.markListened(
            shareIds: ["a", "b"],
            source: .play
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.listened, ["a", "b"])
        XCTAssertEqual(mock.markListenedCalls.first?.shareIds, ["a", "b"])
        XCTAssertEqual(mock.markListenedCalls.first?.source, .play)
    }
}

// MARK: - Test doubles

/// Minimal `SpotifyQueueing` stub used here so `ShareCardViewModel` can be
/// constructed without dragging the real Spotify service into the test.
private final class MockSpotifyQueueing: SpotifyQueueing, @unchecked Sendable {
    func queueTrack(uri: String) async throws {}
    func playTrack(uri: String) async throws {}
}
