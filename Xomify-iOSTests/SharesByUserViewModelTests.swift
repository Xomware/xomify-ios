import XCTest
@testable import Xomify_iOS

@MainActor
final class SharesByUserViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeShare(id: String, sharedAt: String = "2026-04-23 10:00:00") -> Share {
        Share(
            shareId: id,
            sharedBy: "target@example.com",
            sharedAt: sharedAt,
            trackId: "t-\(id)",
            trackUri: "spotify:track:t-\(id)",
            trackName: "Song \(id)",
            artistName: "Artist"
        )
    }

    // MARK: - Tests

    func test_refresh_populatesSharesAndCursor() async {
        let mock = MockXomifyServiceProtocol()
        mock.getSharesByUserResponses = [
            FeedResponse(
                shares: [makeShare(id: "1"), makeShare(id: "2")],
                nextBefore: "2026-04-23 09:00:00"
            )
        ]

        let vm = SharesByUserViewModel(
            callerEmail: "me@example.com",
            targetEmail: "target@example.com",
            xomifyService: mock
        )

        await vm.refresh()

        XCTAssertEqual(vm.shares.count, 2)
        XCTAssertEqual(vm.shares.first?.shareId, "1")
        XCTAssertEqual(vm.nextBefore, "2026-04-23 09:00:00")
        XCTAssertTrue(vm.hasMorePages)
        XCTAssertNil(vm.errorMessage)

        let call = try? XCTUnwrap(mock.getSharesByUserCalls.first)
        XCTAssertEqual(call?.targetEmail, "target@example.com")
        XCTAssertNil(call?.before)
    }

    func test_loadMore_appendsAndAdvancesCursor() async {
        let mock = MockXomifyServiceProtocol()
        mock.getSharesByUserResponses = [
            FeedResponse(shares: [makeShare(id: "1")], nextBefore: "c1"),
            FeedResponse(shares: [makeShare(id: "2")], nextBefore: "c2")
        ]

        let vm = SharesByUserViewModel(
            callerEmail: "me@example.com",
            targetEmail: "target@example.com",
            xomifyService: mock
        )

        await vm.refresh()
        await vm.loadMore()

        XCTAssertEqual(vm.shares.map(\.shareId), ["1", "2"])
        XCTAssertEqual(vm.nextBefore, "c2")
        XCTAssertEqual(mock.getSharesByUserCalls.count, 2)
        XCTAssertEqual(mock.getSharesByUserCalls[1].before, "c1")
    }

    func test_refresh_emptyResponse_clearsHasMore() async {
        let mock = MockXomifyServiceProtocol()
        mock.getSharesByUserResponses = [FeedResponse(shares: [], nextBefore: nil)]

        let vm = SharesByUserViewModel(
            callerEmail: "me@example.com",
            targetEmail: "target@example.com",
            xomifyService: mock
        )

        await vm.refresh()

        XCTAssertTrue(vm.shares.isEmpty)
        XCTAssertFalse(vm.hasMorePages)
        XCTAssertNil(vm.nextBefore)
        XCTAssertNil(vm.errorMessage)
    }

    func test_refresh_error_surfacesMessage() async {
        let mock = MockXomifyServiceProtocol()
        mock.getSharesByUserError = NSError(
            domain: "test", code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Server error"]
        )

        let vm = SharesByUserViewModel(
            callerEmail: "me@example.com",
            targetEmail: "target@example.com",
            xomifyService: mock
        )

        await vm.refresh()

        XCTAssertTrue(vm.shares.isEmpty)
        XCTAssertEqual(vm.errorMessage, "Server error")
        XCTAssertFalse(vm.isRefreshing)
    }

    func test_loadMore_noCursor_isNoop() async {
        let mock = MockXomifyServiceProtocol()
        mock.getSharesByUserResponses = [FeedResponse(shares: [makeShare(id: "1")], nextBefore: nil)]

        let vm = SharesByUserViewModel(
            callerEmail: "me@example.com",
            targetEmail: "target@example.com",
            xomifyService: mock
        )

        await vm.refresh()
        await vm.loadMore()

        XCTAssertEqual(mock.getSharesByUserCalls.count, 1)
        XCTAssertFalse(vm.hasMorePages)
    }
}
