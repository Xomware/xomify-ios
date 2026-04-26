import Foundation

/// Routes Play / Queue actions through the Spotify iOS SDK first, falling back
/// to the Web API when the SDK is unavailable (Spotify not installed, not
/// connected) or when the user has enabled the force-fallback toggle in
/// Settings → Playback Diagnostics.
///
/// Call sites consume this via the `SpotifyQueueing` protocol — identical to
/// how they used `SpotifyService` directly. No call-site changes required.
@MainActor
@Observable
final class SpotifyPlaybackCoordinator: SpotifyQueueing {

    // MARK: - Singleton

    static let shared = SpotifyPlaybackCoordinator()

    // MARK: - Sub-services

    let remote = SpotifyRemoteService()
    private let web: SpotifyService = .shared

    // MARK: - Observable state

    /// When `true`, all play/queue actions bypass the SDK and hit the Web API
    /// directly. Persisted in `UserDefaults`.
    var forceWebFallback: Bool {
        get { UserDefaults.standard.bool(forKey: "xomify.playback.forceWebFallback") }
        set { UserDefaults.standard.set(newValue, forKey: "xomify.playback.forceWebFallback") }
    }

    /// Most recent error from a `connectIfAuthenticated()` call.
    private(set) var lastConnectError: Error?

    // MARK: - Init

    private init() {
        // Wire up the token-refresh hook so we push updated tokens into the
        // live SDK connection without needing to poll or reconnect.
        AuthService.shared.onTokenRefresh = { [weak self] newToken in
            Task { @MainActor [weak self] in
                self?.remote.updateAccessToken(newToken)
            }
        }
    }

    // MARK: - Connection lifecycle

    /// Fetches a valid access token and connects the SDK if not already connected.
    /// Swallows errors into `lastConnectError` — a connection failure must not
    /// surface to the user; we fall back to Web API silently.
    func connectIfAuthenticated() async {
        guard let token = await AuthService.shared.accessTokenForSDK() else { return }
        do {
            try await remote.connect(accessToken: token)
            lastConnectError = nil
        } catch {
            lastConnectError = error
            print("⚠️ SpotifyPlaybackCoordinator: SDK connect failed — \(error.localizedDescription)")
        }
    }

    /// Disconnects the SDK. Call on scene `.background`.
    func disconnect() {
        remote.disconnect()
    }

    // MARK: - SpotifyQueueing

    func queueTrack(uri: String) async throws {
        if forceWebFallback {
            try await web.queueTrack(uri: uri)
            return
        }
        do {
            try await remote.queueTrack(uri: uri)
        } catch SpotifyRemoteError.notConnected,
                SpotifyRemoteError.notInstalled {
            // SDK not available — fall through to Web API.
            try await web.queueTrack(uri: uri)
        }
        // `.connectFailed` and `.actionFailed` propagate — the action
        // controller's generic `catch` will surface them to the user.
    }

    func playTrack(uri: String) async throws {
        if forceWebFallback {
            try await web.playTrack(uri: uri)
            return
        }
        do {
            try await remote.playTrack(uri: uri)
        } catch SpotifyRemoteError.notConnected,
                SpotifyRemoteError.notInstalled {
            try await web.playTrack(uri: uri)
        }
    }
}
