import XCTest
@testable import Xomify_iOS

/// Coverage for the push payload parsing and routing that B8 shipped without
/// any tests — the test target did not exist at the time.
final class PushPayloadTests: XCTestCase {

    // MARK: - Kind resolution

    func test_explicitPushType_wins() async {
        let payload = PushPayload(userInfo: [
            "pushType": "share_comment",
            "route": "share:abc",
        ])
        XCTAssertEqual(payload.kind, .shareComment)
    }

    func test_rawValuesAreTheBackendRegistryKeys() async {
        // These are the wire contract, not a style choice. Renaming one
        // silently breaks every push of that kind.
        XCTAssertEqual(PushKind.shareReceived.rawValue, "share_received")
        XCTAssertEqual(PushKind.queueThreshold.rawValue, "queue_threshold")
        XCTAssertEqual(PushKind.releaseRadarDrop.rawValue, "release_radar_drop")
    }

    func test_legacyPayloadWithShareIdFallsBackToQueueThreshold() async {
        // Pre-registry payloads carried no pushType, and the only kind that
        // ever carried a shareId was the queue threshold.
        let payload = PushPayload(userInfo: ["shareId": "abc"])
        XCTAssertEqual(payload.kind, .queueThreshold)
        XCTAssertEqual(payload.shareId, "abc")
    }

    func test_legacyDigestPayloadIsRecognised() async {
        let payload = PushPayload(userInfo: ["count": 3, "windowDays": 7])
        XCTAssertEqual(payload.kind, .digest)
    }

    func test_unrecognisedPushTypeDoesNotCrash() async {
        // A client one build behind must degrade, not explode.
        let payload = PushPayload(userInfo: ["pushType": "some_future_kind"])
        XCTAssertEqual(payload.kind, .unknown)
    }

    func test_emptyPayloadIsUnknown() async {
        XCTAssertEqual(PushPayload(userInfo: [:]).kind, .unknown)
    }

    // MARK: - Route parsing

    func test_shareIdIsReadFromTheRouteWhenNotExplicit() async {
        let payload = PushPayload(userInfo: [
            "pushType": "share_rated",
            "route": "share:xyz789",
        ])
        XCTAssertEqual(payload.shareId, "xyz789")
    }

    func test_subjectParsingIgnoresAMismatchedPrefix() async {
        XCTAssertNil(PushPayload.subject(of: "invite:abc", kind: "share"))
        XCTAssertNil(PushPayload.subject(of: "share:", kind: "share"))
        XCTAssertNil(PushPayload.subject(of: nil, kind: "share"))
        XCTAssertEqual(PushPayload.subject(of: "share:s1", kind: "share"), "s1")
    }

    // MARK: - Foreground presentation

    func test_catchUpKindsDoNotInterruptInForeground() async {
        // If the user is already in the app, catch-up content is noise — the
        // inbox is where catch-up belongs.
        XCTAssertFalse(PushKind.digest.interruptsInForeground)
        XCTAssertFalse(PushKind.broadcast.interruptsInForeground)
        XCTAssertFalse(PushKind.favoritesReminder.interruptsInForeground)
    }

    func test_socialAndDropKindsDoInterrupt() async {
        XCTAssertTrue(PushKind.shareReceived.interruptsInForeground)
        XCTAssertTrue(PushKind.friendRequest.interruptsInForeground)
        XCTAssertTrue(PushKind.wrappedDrop.interruptsInForeground)
    }

    // MARK: - Destination routing

    @MainActor
    func test_routeTokensMapToDestinations() async {
        let cases: [(String, SidebarDestination)] = [
            ("share:s1", .feed),
            ("shares", .feed),
            ("friends", .friends),
            ("friend:a@e.com", .friends),
            ("invite:CODE", .friends),
            ("wrapped:p1", .wrapped),
            ("release_radar:p1", .releaseRadar),
            ("home", .feed),
        ]
        for (token, expected) in cases {
            let payload = PushPayload(kind: .unknown, route: token)
            XCTAssertEqual(
                NotificationsService.destination(for: payload), expected,
                "route \(token) should resolve to \(expected)"
            )
        }
    }

    @MainActor
    func test_unknownRouteFallsBackToTheKind() async {
        // A payload with no usable route still routes by kind, which is how
        // pre-registry pushes keep working.
        let payload = PushPayload(kind: .friendAccepted, route: nil)
        XCTAssertEqual(NotificationsService.destination(for: payload), .friends)
    }

    @MainActor
    func test_completelyUnroutablePayloadGoesNowhere() async {
        // Better to leave the user where they are than yank them somewhere
        // arbitrary.
        let payload = PushPayload(kind: .unknown, route: nil)
        XCTAssertNil(NotificationsService.destination(for: payload))
    }
}
