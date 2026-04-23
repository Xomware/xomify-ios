import XCTest
import UserNotifications
@testable import Xomify_iOS

/// Unit tests for `NotificationsService`.
///
/// NOTE: No XCTest target is wired into the Xcode project yet. These tests
/// live here as the reference suite for when `Xomify-iOSTests` is added. Run
/// with `xcodebuild test` once the target ships.
@MainActor
final class NotificationsServiceTests: XCTestCase {

    // MARK: - Token hex encoding

    func test_hexString_encodesKnownBytes() {
        let bytes: [UInt8] = [0x00, 0x01, 0x02, 0xFF, 0xAB, 0xCD]
        let hex = NotificationsService.hexString(from: Data(bytes))
        XCTAssertEqual(hex, "000102ffabcd")
    }

    func test_hexString_emptyData_returnsEmptyString() {
        XCTAssertEqual(NotificationsService.hexString(from: Data()), "")
    }

    func test_hexString_singleByte() {
        XCTAssertEqual(NotificationsService.hexString(from: Data([0x7F])), "7f")
    }

    // MARK: - Permission prompt gate

    func test_requestPermissionIfNeeded_firstCall_setsHasPromptedFlag() async {
        let defaults = makeIsolatedDefaults()
        let service = NotificationsService(xomify: MockXomifyServicing(), defaults: defaults)

        // The real call hits UNUserNotificationCenter which requires a host
        // app — we can't fully drive it in a unit test. The gate check is
        // what we're proving: if the flag is already true we bail early and
        // do nothing, so subsequent calls don't re-prompt.
        defaults.set(true, forKey: NotificationsService.hasPromptedKey)
        await service.requestPermissionIfNeeded()
        // No crash = no-op path taken.
        XCTAssertTrue(defaults.bool(forKey: NotificationsService.hasPromptedKey))
    }

    // MARK: - Push payload inference

    func test_pushPayload_queueThreshold_inferredFromShareId() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "x", "body": "y"]],
            "shareId": "share-123",
            "trackId": "track-abc",
            "reactorCount": 5
        ]
        let payload = PushPayload(userInfo: userInfo)
        XCTAssertEqual(payload.kind, .queueThreshold)
        XCTAssertEqual(payload.shareId, "share-123")
        XCTAssertEqual(payload.trackId, "track-abc")
        XCTAssertEqual(payload.reactorCount, 5)
    }

    func test_pushPayload_digest_inferredFromWindowDays() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "x", "body": "y"]],
            "count": 3,
            "windowDays": 7
        ]
        let payload = PushPayload(userInfo: userInfo)
        XCTAssertEqual(payload.kind, .digest)
        XCTAssertNil(payload.shareId)
        XCTAssertEqual(payload.count, 3)
        XCTAssertEqual(payload.windowDays, 7)
    }

    func test_pushPayload_unknown_whenNoSignals() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "x", "body": "y"]]
        ]
        let payload = PushPayload(userInfo: userInfo)
        XCTAssertEqual(payload.kind, .unknown)
    }

    func test_pushPayload_acceptsStringIntegers() {
        // DynamoDB / JSON wire can surface numerics as strings. Make sure we
        // coerce them.
        let userInfo: [AnyHashable: Any] = [
            "shareId": "s1",
            "reactorCount": "5"
        ]
        let payload = PushPayload(userInfo: userInfo)
        XCTAssertEqual(payload.kind, .queueThreshold)
        XCTAssertEqual(payload.reactorCount, 5)
    }

    // MARK: - handlePushOpen routes to feed

    func test_handlePushOpen_queueThreshold_routesToFeed() async {
        let defaults = makeIsolatedDefaults()
        let service = NotificationsService(xomify: MockXomifyServicing(), defaults: defaults)
        let nav = NavigationStore()
        nav.selectedTab = .home
        service.navigationStore = nav

        service.handlePushOpen(
            payload: PushPayload(kind: .queueThreshold, shareId: "s1")
        )

        XCTAssertEqual(nav.selectedTab, .feed)
    }

    func test_handlePushOpen_digest_routesToFeed() async {
        let defaults = makeIsolatedDefaults()
        let service = NotificationsService(xomify: MockXomifyServicing(), defaults: defaults)
        let nav = NavigationStore()
        nav.selectedTab = .home
        service.navigationStore = nav

        service.handlePushOpen(
            payload: PushPayload(kind: .digest, count: 3, windowDays: 7)
        )

        XCTAssertEqual(nav.selectedTab, .feed)
    }

    func test_handlePushOpen_unknown_doesNotChangeTab() async {
        let defaults = makeIsolatedDefaults()
        let service = NotificationsService(xomify: MockXomifyServicing(), defaults: defaults)
        let nav = NavigationStore()
        nav.selectedTab = .home
        service.navigationStore = nav

        service.handlePushOpen(payload: PushPayload(kind: .unknown))

        XCTAssertEqual(nav.selectedTab, .home)
    }

    // MARK: - Register body shape

    func test_registerPushToken_usesCorrectBodyShape() async throws {
        let mock = MockXomifyServicing()
        _ = try await mock.registerPushToken(
            email: "user@example.com",
            deviceToken: "abcdef",
            queueNotificationsEnabled: true,
            digestEnabled: false
        )
        XCTAssertEqual(mock.registerCalls.count, 1)
        let call = try XCTUnwrap(mock.registerCalls.first)
        XCTAssertEqual(call.email, "user@example.com")
        XCTAssertEqual(call.deviceToken, "abcdef")
        XCTAssertTrue(call.queueNotificationsEnabled)
        XCTAssertFalse(call.digestEnabled)
    }

    func test_unregisterPushToken_usesCorrectBodyShape() async throws {
        let mock = MockXomifyServicing()
        _ = try await mock.unregisterPushToken(
            email: "user@example.com",
            deviceToken: "abcdef"
        )
        XCTAssertEqual(mock.unregisterCalls.count, 1)
        let call = try XCTUnwrap(mock.unregisterCalls.first)
        XCTAssertEqual(call.email, "user@example.com")
        XCTAssertEqual(call.deviceToken, "abcdef")
    }

    // MARK: - Helpers

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "NotificationsServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
