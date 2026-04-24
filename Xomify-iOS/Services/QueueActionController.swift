import Foundation

/// Shared controller that powers every "Add to Spotify queue" button in the app.
///
/// Why this exists:
/// - The taste stage + other track rows were calling `SpotifyService.queueTrack`
///   with `try?`, swallowing every error silently. Users tapped the button and
///   saw nothing happen (especially when no device was active).
/// - Each track row would otherwise have to reimplement the same in-flight +
///   error-surfacing dance.
///
/// Errors are routed to a single `toast` string that `QueueToastHost` renders
/// at `MainShell`. Per-URI `isQueuing(uri:)` lets buttons show a spinner +
/// disable themselves while a queue attempt is in flight.
@Observable
@MainActor
final class QueueActionController {

    static let shared = QueueActionController()

    /// The most recent user-visible message from a queue attempt. Nil when no
    /// toast should be shown. `QueueToastHost` auto-clears this after a delay.
    var toast: String?

    /// URIs currently mid-flight. Used so double-taps of the same button no-op
    /// and so the button can show a spinner without each call site tracking it.
    private var inFlight: Set<String> = []

    private let spotifyService: SpotifyQueueing

    init(spotifyService: SpotifyQueueing = SpotifyService.shared) {
        self.spotifyService = spotifyService
    }

    func isQueuing(uri: String) -> Bool {
        inFlight.contains(uri)
    }

    /// Queue a track. Shows a success toast on 2xx, an actionable error
    /// message on failure. Safe to call while another queue is in flight for
    /// a different URI.
    func queue(uri: String, trackName: String? = nil) async {
        guard !uri.isEmpty else {
            toast = "Couldn't queue — missing track URI."
            return
        }
        guard !inFlight.contains(uri) else { return }

        inFlight.insert(uri)
        defer { inFlight.remove(uri) }

        do {
            try await spotifyService.queueTrack(uri: uri)
            if let name = trackName, !name.isEmpty {
                toast = "Queued \(name)"
            } else {
                toast = "Queued on Spotify"
            }
        } catch let error as SpotifyServiceError {
            toast = error.errorDescription
        } catch {
            toast = error.localizedDescription
        }
    }
}
