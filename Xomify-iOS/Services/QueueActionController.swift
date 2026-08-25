import Foundation
import UIKit

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
///
/// When the queue/play action originated from a feed share, callers pass a
/// non-nil `shareId` and the controller fires a best-effort
/// `markListened` write so the share's "viewer has listened" state flips
/// for the next feed refresh. Failure is silent — a failed listener-write
/// is invisible to the user, who already saw the queue/play succeed.
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
    private let xomifyService: XomifyServiceProtocol

    init(
        spotifyService: SpotifyQueueing = SpotifyPlaybackCoordinator.shared,
        xomifyService: XomifyServiceProtocol = XomifyService.shared
    ) {
        self.spotifyService = spotifyService
        self.xomifyService = xomifyService
    }

    func isQueuing(uri: String) -> Bool {
        inFlight.contains(uri)
    }

    /// Queue a track. Shows a success toast on 2xx, an actionable error
    /// message on failure. Safe to call while another queue is in flight for
    /// a different URI.
    ///
    /// When `shareId` is non-nil the controller also fires a best-effort
    /// `markListened` write tagged `source: queue`. Pass `nil` from contexts
    /// that aren't a share (track rows in Library, taste stage, etc.) to skip
    /// the listener-write — the backend has nothing to associate it with.
    func queue(uri: String, trackName: String? = nil, shareId: String? = nil) async {
        guard !uri.isEmpty else {
            toast = "Couldn't queue — missing track URI."
            return
        }
        guard !inFlight.contains(uri) else { return }

        inFlight.insert(uri)
        defer { inFlight.remove(uri) }

        do {
            try await spotifyService.queueTrack(uri: uri)
            // Confirm the state change the user caused. Placed here rather
            // than on each button so every call site gets it — and only on
            // the success path, so a failure never feels like it worked.
            Haptics.success()
            if let name = trackName, !name.isEmpty {
                toast = "Queued \(name)"
            } else {
                toast = "Queued on Spotify"
            }
            markListenedFireAndForget(shareId: shareId, source: .queue)
        } catch SpotifyServiceError.noActiveDevice {
            handleNoDevice(uri: uri, action: "queue")
        } catch let error as SpotifyServiceError {
            Haptics.failure()
            toast = error.errorDescription
        } catch {
            Haptics.failure()
            toast = error.localizedDescription
        }
    }

    /// Start playback on the user's active Spotify device. Falls back to
    /// deep-linking into the Spotify app when no device is active so the user
    /// can trivially resume a session.
    ///
    /// When `shareId` is non-nil the controller also fires a best-effort
    /// `markListened` write tagged `source: play`.
    func play(uri: String, trackName: String? = nil, shareId: String? = nil) async {
        guard !uri.isEmpty else {
            toast = "Couldn't play — missing track URI."
            return
        }
        guard !inFlight.contains(uri) else { return }

        inFlight.insert(uri)
        defer { inFlight.remove(uri) }

        do {
            try await spotifyService.playTrack(uri: uri)
            // Confirm the state change the user caused. Placed here rather
            // than on each button so every call site gets it — and only on
            // the success path, so a failure never feels like it worked.
            Haptics.success()
            if let name = trackName, !name.isEmpty {
                toast = "Playing \(name)"
            } else {
                toast = "Playing on Spotify"
            }
            markListenedFireAndForget(shareId: shareId, source: .play)
        } catch SpotifyServiceError.noActiveDevice {
            handleNoDevice(uri: uri, action: "play")
        } catch let error as SpotifyServiceError {
            Haptics.failure()
            toast = error.errorDescription
        } catch {
            Haptics.failure()
            toast = error.localizedDescription
        }
    }

    /// Best-effort `POST /shares/listened`. Errors are logged and swallowed —
    /// the user already saw the queue/play succeed and a failed listener
    /// write should not surface as a user-facing toast.
    private func markListenedFireAndForget(shareId: String?, source: ListenSource) {
        guard let shareId, !shareId.isEmpty else { return }
        let service = xomifyService
        Task {
            do {
                _ = try await service.markListened(shareIds: [shareId], source: source)
            } catch {
                print("⚠️ markListened failed for \(shareId) (source: \(source.rawValue)): \(error.localizedDescription)")
            }
        }
    }

    /// Web API fallback reported no active device. This is a rare edge case now
    /// that the SDK can wake Spotify directly — it typically means both the SDK
    /// path failed *and* Spotify isn't running. Deep-link into the track page as
    /// a last resort so the user can open Spotify and resume.
    private func handleNoDevice(uri: String, action: String) {
        if let url = URL(string: uri), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            toast = "Opening Spotify — try again once it's playing."
        } else {
            toast = SpotifyServiceError.noActiveDevice.errorDescription
        }
    }
}
