import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// Owns all push-notification plumbing:
///   - permission prompt (gated by `@AppStorage` so we only ask once),
///   - APNs device-token lifecycle (hex encoding, cache, register/unregister),
///   - foreground presentation (banner+sound for threshold, silent for digest),
///   - push-open dispatch (routes to the Feed tab via the shared
///     `NavigationStore` that `MainShell` observes).
///
/// Views never touch this directly — trigger points are called from
/// `ShareComposerViewModel`, `FriendsViewModel`, `SettingsViewModel`, and the
/// `AppDelegate`. `SettingsViewModel` mediates preference flips.
@MainActor
final class NotificationsService: NSObject {

    // MARK: - Singleton

    static let shared = NotificationsService()

    // MARK: - Dependencies

    private let xomify: any XomifyServicing
    private let defaults: UserDefaults

    /// Shared `NavigationStore` observed by `MainShell`. Published pushes land
    /// here as tab switches / deep-link requests. `weak` so we don't keep a
    /// detached shell alive during unit tests.
    weak var navigationStore: NavigationStore?

    // MARK: - UserDefaults keys

    /// Flipped to `true` the first time we call `requestAuthorization`, whether
    /// the user grants or denies. Prevents re-prompting (iOS silently drops
    /// subsequent prompts anyway — this flag makes the gate explicit).
    static let hasPromptedKey = "notifications.hasPromptedForPush"

    /// Hex-encoded APNs token from the most recent `didRegister` callback.
    /// Used by `unregister()` on sign-out and by `updatePreferences()` to
    /// upsert without re-soliciting the token.
    static let cachedTokenKey = "notifications.cachedDeviceToken"

    /// Mirror of the Settings toggles (kept in sync via `@AppStorage` on the
    /// view model side). Read here when the push pipeline needs the values
    /// without rebuilding the VM.
    static let queueEnabledKey = "notifications.push.enabled"
    static let digestEnabledKey = "notifications.digest.enabled"

    /// Cached user email for unregister. Written after a successful token
    /// upsert so sign-out can POST /notifications/unregister without needing
    /// to round-trip to Spotify (by the time sign-out runs the access token
    /// may already be cleared).
    static let cachedEmailKey = "notifications.cachedEmail"

    // MARK: - Init

    init(
        xomify: any XomifyServicing = XomifyService.shared,
        defaults: UserDefaults = .standard
    ) {
        self.xomify = xomify
        self.defaults = defaults
        super.init()
    }

    // MARK: - Public API

    /// Current authorization status from UNUserNotificationCenter. Async because
    /// the underlying API is callback-based.
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// First-share / first-accepted-invite trigger. No-op after the first call.
    /// Sets `hasPromptedForPush` regardless of grant/deny so we only ever
    /// prompt once — the Settings screen shows a "Open System Settings" button
    /// for users who deny.
    func requestPermissionIfNeeded() async {
        if defaults.bool(forKey: Self.hasPromptedKey) {
            return
        }
        defaults.set(true, forKey: Self.hasPromptedKey)

        let granted: Bool
        do {
            granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            print("❌ Notifications: requestAuthorization threw — \(error.localizedDescription)")
            return
        }

        guard granted else {
            print("ℹ️ Notifications: user denied push permission")
            return
        }

        // Kick APNs token registration. The delegate callback feeds back into
        // `handleDeviceToken(_:)` where we POST to the backend.
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Called from `XomifyAppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`.
    /// Hex-encodes the raw token, caches it, and upserts to the backend.
    ///
    /// Caller identity is read from the JWT context server-side
    /// (sub-feature 1f). We still gate on a resolvable Spotify email so we
    /// don't register a device against an empty session, and we still cache
    /// it so `unregister()` can run after the session has been torn down.
    func handleDeviceToken(_ data: Data) async {
        let hex = Self.hexString(from: data)
        defaults.set(hex, forKey: Self.cachedTokenKey)

        guard let email = await currentUserEmail() else {
            print("ℹ️ Notifications: token received but no current user — skipping register")
            return
        }

        let queueEnabled = defaults.object(forKey: Self.queueEnabledKey) as? Bool ?? true
        let digestEnabled = defaults.object(forKey: Self.digestEnabledKey) as? Bool ?? true

        // One retry on failure — token registration is non-critical, so we
        // don't surface errors to the user. Backend upsert is idempotent.
        for attempt in 1...2 {
            do {
                _ = try await xomify.registerPushToken(
                    deviceToken: hex,
                    queueNotificationsEnabled: queueEnabled,
                    digestEnabled: digestEnabled
                )
                defaults.set(email, forKey: Self.cachedEmailKey)
                print("✅ Notifications: device token registered (attempt \(attempt))")
                return
            } catch {
                print("❌ Notifications: registerPushToken failed (attempt \(attempt)) — \(error.localizedDescription)")
            }
        }
    }

    /// Called from the delegate when APNs registration fails. Simulator and
    /// unsigned-dev builds regularly hit this — not fatal.
    func handleRegistrationFailure(_ error: Error) {
        print("ℹ️ Notifications: APNs registration failed — \(error.localizedDescription)")
    }

    /// Flipped by `SettingsViewModel` when the user toggles either switch.
    /// Re-POSTs to `/notifications/register` as an upsert using the cached token.
    ///
    /// Caller identity is taken from the JWT context server-side
    /// (sub-feature 1f); this method only sends the token + preference flags.
    /// We still gate on having a session anchor (cached email or current
    /// Spotify user) to avoid issuing register requests for signed-out users.
    func updatePreferences(queueNotificationsEnabled: Bool, digestEnabled: Bool) async {
        guard let hex = defaults.string(forKey: Self.cachedTokenKey) else {
            // No token yet — next `handleDeviceToken` call will pick up the
            // latest flags from UserDefaults and POST them.
            return
        }
        let hasCachedEmail = defaults.string(forKey: Self.cachedEmailKey)?.isEmpty == false
        let hasCurrentSpotifyEmail = await currentUserEmail() != nil
        guard hasCachedEmail || hasCurrentSpotifyEmail else { return }

        do {
            _ = try await xomify.registerPushToken(
                deviceToken: hex,
                queueNotificationsEnabled: queueNotificationsEnabled,
                digestEnabled: digestEnabled
            )
        } catch {
            print("❌ Notifications: updatePreferences failed — \(error.localizedDescription)")
        }
    }

    /// Called on sign-out. Swallows errors — the user is leaving anyway, and a
    /// stale backend token expires on the next failed send (APNs 410).
    ///
    /// Caller identity is read from the JWT context server-side
    /// (sub-feature 1f); we only send the device token. The cached email is
    /// still consulted as a session anchor — when present we still had a
    /// signed-in user to whom this token belonged. This call must run before
    /// the JWT is cleared.
    func unregister() async {
        let hex = defaults.string(forKey: Self.cachedTokenKey)
        let cachedEmail = defaults.string(forKey: Self.cachedEmailKey)

        // Clear local state first so subsequent pushes/launches don't try to
        // reuse the old token before the network round-trip completes.
        defaults.removeObject(forKey: Self.cachedTokenKey)
        defaults.removeObject(forKey: Self.cachedEmailKey)
        defaults.removeObject(forKey: Self.hasPromptedKey)

        guard let hex, let cachedEmail, !cachedEmail.isEmpty else { return }

        do {
            _ = try await xomify.unregisterPushToken(deviceToken: hex)
        } catch {
            print("ℹ️ Notifications: unregister failed (swallowed) — \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Resolve the current user's email. Fetched from the Spotify profile since
    /// the backend keys tokens by email. Returns `nil` when not signed in.
    private func currentUserEmail() async -> String? {
        do {
            let user = try await SpotifyService.shared.getCurrentUser()
            return user.email
        } catch {
            return nil
        }
    }

    /// APNs device tokens arrive as raw `Data`; the backend stores them as hex.
    /// Matches `String(format: "%02x", ...)` byte-by-byte.
    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationsService: UNUserNotificationCenterDelegate {

    /// Foreground presentation. Queue-threshold pushes still show a banner +
    /// play a sound (the user likely wants immediate feedback). Digest pushes
    /// are suppressed in-app — if the user is already in the app, they don't
    /// need a banner telling them to come check it out.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let payload = PushPayload(userInfo: notification.request.content.userInfo)
        switch payload.kind {
        case .digest:
            completionHandler([])
        case .queueThreshold, .unknown:
            completionHandler([.banner, .sound])
        }
    }

    /// Push-open routing. `shareId` → route to the Feed tab so the user lands
    /// on the list that contains the share. `digest` → route to Feed tab too.
    ///
    /// The `Share`-detail destination does not yet exist as a drawer
    /// destination; the Feed tab is the correct landing spot until it does.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let payload = PushPayload(userInfo: response.notification.request.content.userInfo)
        handlePushOpen(payload: payload)
    }

    /// Dispatch a parsed push-open payload into the navigation layer. Split
    /// from the delegate callback so tests can drive it directly.
    func handlePushOpen(payload: PushPayload) {
        switch payload.kind {
        case .queueThreshold, .digest:
            navigationStore?.select(.feed)
        case .unknown:
            // Nothing to route — leave the user wherever they were.
            return
        }
    }
}
