import Foundation

/// Errors produced by `SpotifyRemoteService` (SDK path).
///
/// Distinct from `SpotifyServiceError` (Web API path) so `SpotifyPlaybackCoordinator`
/// can pattern-match SDK-specific failure modes when deciding whether to fall back
/// to the Web API.
enum SpotifyRemoteError: LocalizedError, Sendable {
    /// The Spotify app is not installed on this device.
    case notInstalled
    /// The SDK is not currently connected to the Spotify app.
    case notConnected
    /// The SDK connection attempt failed with the given underlying error.
    case connectFailed(underlying: Error)
    /// A player action (queue / play) failed with the given underlying error.
    case actionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The Spotify app is not installed."
        case .notConnected:
            return "Not connected to Spotify. Try again in a moment."
        case .connectFailed(let error):
            return "Could not connect to Spotify: \(error.localizedDescription)"
        case .actionFailed(let error):
            return "Spotify action failed: \(error.localizedDescription)"
        }
    }
}
