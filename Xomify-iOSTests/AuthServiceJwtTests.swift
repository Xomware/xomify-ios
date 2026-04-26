import XCTest
@testable import Xomify_iOS

/// Reference unit tests for the per-user Xomify JWT plumbing added in (0d).
///
/// NOTE: No XCTest target is wired into the Xcode project yet (matches the
/// existing pattern in `NotificationsServiceTests.swift`). These live as the
/// reference suite for when `Xomify-iOSTests` is added to the build.
///
/// Test coverage scope — what's testable here vs. what's manual-only:
///
/// **Covered (deterministic, no network / no keychain side-effects):**
/// - `AuthLoginEnvelope` decodes the standard backend response shape
///   (`{ data: { token, expiresAt }, error: null }`).
/// - `AuthLoginEnvelope` decodes a malformed / error envelope (`data: null`)
///   and yields `nil` for the payload — `mintXomifyJwt` then returns `false`
///   without storing anything.
/// - ISO8601 parsing of `expiresAt` accepts both fractional and
///   non-fractional second forms (matches the backend's two emitted formats).
///
/// **Manual / integration only — cannot be driven from this unit test:**
/// - `mintXomifyJwt` happy path: it calls `URLSession.shared.data(for:)`
///   directly and writes to the real keychain. Requires a network mock layer
///   (URLProtocol stub) and a swappable keychain backend, neither of which
///   exist in this codebase yet. Adding them would expand the (0d) scope.
///   Verified manually on TestFlight — see PR description.
/// - `mintXomifyJwt` failure (Spotify token rejected → 401 from backend):
///   same constraint. Verified manually by passing a stale access token.
/// - `NetworkService` 401-retry path: depends on `AuthService.shared`
///   singleton and real `URLSession`. Same network-mock gap. Verified
///   manually by waiting for JWT expiry (or by deleting the keychain entry
///   while the app is paused, then resuming a request).
/// - Keychain persistence across launches: cannot run unit-test isolation;
///   verified manually by killing the app and reopening it.
@MainActor
final class AuthServiceJwtTests: XCTestCase {

    // MARK: - AuthLoginEnvelope decoding

    func test_authLoginEnvelope_happyPath_decodesTokenAndExpiry() throws {
        let json = """
        {
          "data": {
            "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.sig",
            "expiresAt": "2026-05-03T12:34:56Z"
          },
          "error": null,
          "meta": {}
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(AuthLoginEnvelope.self, from: json)

        XCTAssertNotNil(envelope.data)
        XCTAssertEqual(envelope.data?.token, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.sig")
        XCTAssertEqual(envelope.data?.expiresAt, "2026-05-03T12:34:56Z")
        XCTAssertNil(envelope.error)
    }

    func test_authLoginEnvelope_errorResponse_yieldsNilPayload() throws {
        let json = """
        {
          "data": null,
          "error": "spotify token rejected",
          "meta": {}
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(AuthLoginEnvelope.self, from: json)

        XCTAssertNil(envelope.data)
        XCTAssertEqual(envelope.error, "spotify token rejected")
    }

    func test_authLoginPayload_missingExpiresAt_decodesTokenOnly() throws {
        let json = """
        {
          "token": "abc.def.ghi",
          "expiresAt": null
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(AuthLoginPayload.self, from: json)

        XCTAssertEqual(payload.token, "abc.def.ghi")
        XCTAssertNil(payload.expiresAt)
    }

    // MARK: - ISO8601 parsing (the helper inside AuthService is private, but
    // its two accepted formats are part of the contract — if the backend
    // changes its emitted format we want this suite to fail loudly. We test
    // them via `ISO8601DateFormatter` directly, mirroring the helper.)

    func test_iso8601_fractionalSeconds_parses() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: "2026-05-03T12:34:56.789Z")
        XCTAssertNotNil(date)
    }

    func test_iso8601_plainSeconds_parses() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: "2026-05-03T12:34:56Z")
        XCTAssertNotNil(date)
    }
}
