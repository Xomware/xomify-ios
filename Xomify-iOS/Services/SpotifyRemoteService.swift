import Foundation
import UIKit
import SpotifyiOS

/// Wraps `SPTAppRemote` and bridges its Objective-C delegate callbacks to
/// Swift async/await. Conforms to `SpotifyQueueing` so it can be swapped in
/// wherever `SpotifyService` is used today.
///
/// All SDK interaction — including delegate callbacks — happens on the main
/// actor. `SPTAppRemote` is not `Sendable` and must never cross actor
/// boundaries.
@MainActor
@Observable
final class SpotifyRemoteService: NSObject, SpotifyQueueing {

    // MARK: - Observable state

    /// Whether the SDK is currently connected to the Spotify app.
    private(set) var isConnected: Bool = false

    /// The most recent SDK-level error (connection or player action).
    private(set) var lastError: SpotifyRemoteError?

    // MARK: - Private

    private let appRemote: SPTAppRemote

    /// Pending continuation for an in-flight `connect()` call.
    private var connectContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Init

    override init() {
        let clientID = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String ?? ""
        let redirectURL = URL(string: "xomify://callback")!
        let config = SPTConfiguration(clientID: clientID, redirectURL: redirectURL)

        appRemote = SPTAppRemote(configuration: config, logLevel: .error)
        super.init()
        appRemote.delegate = self
    }

    // MARK: - Connection

    /// Connects to the Spotify app using a pre-fetched access token.
    /// Throws `SpotifyRemoteError.notInstalled` if Spotify isn't installed,
    /// or `.connectFailed` if the handshake is rejected.
    func connect(accessToken: String) async throws {
        guard UIApplication.shared.canOpenURL(URL(string: "spotify:")!) else {
            lastError = .notInstalled
            throw SpotifyRemoteError.notInstalled
        }

        if appRemote.isConnected {
            // Already connected — just refresh the token in case it changed.
            appRemote.connectionParameters.accessToken = accessToken
            isConnected = true
            return
        }

        appRemote.connectionParameters.accessToken = accessToken

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectContinuation = continuation
            appRemote.connect()
        }
    }

    /// Disconnects from the Spotify app. Idempotent.
    func disconnect() {
        guard appRemote.isConnected else { return }
        appRemote.disconnect()
    }

    /// Pushes a new access token into the live connection (called after token refresh).
    func updateAccessToken(_ token: String) {
        appRemote.connectionParameters.accessToken = token
    }

    // MARK: - SpotifyQueueing

    func queueTrack(uri: String) async throws {
        guard isConnected, let playerAPI = appRemote.playerAPI else {
            throw SpotifyRemoteError.notConnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            playerAPI.enqueueTrackUri(uri) { _, error in
                if let error {
                    continuation.resume(throwing: SpotifyRemoteError.actionFailed(underlying: error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func playTrack(uri: String) async throws {
        guard isConnected, let playerAPI = appRemote.playerAPI else {
            throw SpotifyRemoteError.notConnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            playerAPI.play(uri) { _, error in
                if let error {
                    continuation.resume(throwing: SpotifyRemoteError.actionFailed(underlying: error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - URL handling

    /// Forward the URL received in `onOpenURL` to the SDK's auth-handover parser.
    /// Call this from the app entry's `.onOpenURL` modifier.
    func handleOpenURL(_ url: URL) {
        guard let params = appRemote.authorizationParameters(from: url) else { return }

        if let token = params[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = token
            appRemote.connect()
        } else if let errorDescription = params[SPTAppRemoteErrorDescriptionKey] {
            print("❌ SpotifyRemoteService: Auth callback error — \(errorDescription)")
            lastError = .connectFailed(underlying: NSError(
                domain: "SpotifyRemote",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: errorDescription]
            ))
        }
    }
}

// MARK: - SPTAppRemoteDelegate

extension SpotifyRemoteService: SPTAppRemoteDelegate {

    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            self.isConnected = true
            self.lastError = nil
            self.connectContinuation?.resume()
            self.connectContinuation = nil
            print("✅ SpotifyRemoteService: Connected")
        }
    }

    nonisolated func appRemote(
        _ appRemote: SPTAppRemote,
        didFailConnectionAttemptWithError error: Error?
    ) {
        Task { @MainActor in
            self.isConnected = false
            let remoteError = SpotifyRemoteError.connectFailed(
                underlying: error ?? NSError(domain: "SpotifyRemote", code: -1)
            )
            self.lastError = remoteError
            self.connectContinuation?.resume(throwing: remoteError)
            self.connectContinuation = nil
            print("❌ SpotifyRemoteService: Connection failed — \(error?.localizedDescription ?? "unknown")")
        }
    }

    nonisolated func appRemote(
        _ appRemote: SPTAppRemote,
        didDisconnectWithError error: Error?
    ) {
        Task { @MainActor in
            self.isConnected = false
            if let error {
                self.lastError = .connectFailed(underlying: error)
                print("⚠️ SpotifyRemoteService: Disconnected with error — \(error.localizedDescription)")
            } else {
                print("ℹ️ SpotifyRemoteService: Disconnected cleanly")
            }
        }
    }
}
