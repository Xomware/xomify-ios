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
@Observable
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

    // MARK: - Observable state

    /// Drives the bell badge in the shell header. Bumped locally on a
    /// foreground push and on mark-read so the badge never lags the UI, and
    /// reconciled against the server whenever the inbox is opened.
    var unreadCount: Int = 0

    /// Per-kind opt-ins, sparse — only what the user has actually touched.
    /// Hydrated from the server's effective map on every successful register.
    var preferences = NotificationPreferences()

    // MARK: - UserDefaults keys

    /// JSON blob of the sparse preference map. Survives relaunch so Settings
    /// renders the user's real choices before the first network round-trip
    /// instead of flashing defaults at them.
    static let preferencesKey = "notifications.preferences.v2"

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
        self.preferences = Self.loadPreferences(from: defaults)
    }

    private static func loadPreferences(from defaults: UserDefaults) -> NotificationPreferences {
        guard let data = defaults.data(forKey: preferencesKey),
              let flags = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            // Migration from the two-flag era: carry the old keys forward so a
            // user who had already turned the digest off does not silently get
            // it back on upgrade.
            var flags: [String: Bool] = [:]
            if let queue = defaults.object(forKey: queueEnabledKey) as? Bool {
                flags["queueNotificationsEnabled"] = queue
            }
            if let digest = defaults.object(forKey: digestEnabledKey) as? Bool {
                flags["digestEnabled"] = digest
            }
            return NotificationPreferences(flags: flags)
        }
        return NotificationPreferences(flags: flags)
    }

    private func persistPreferences() {
        if let data = try? JSONEncoder().encode(preferences.flags) {
            defaults.set(data, forKey: Self.preferencesKey)
        }
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

        // One retry on failure — token registration is non-critical, so we
        // don't surface errors to the user. Backend upsert is idempotent.
        for attempt in 1...2 {
            do {
                let effective = try await xomify.registerPushToken(
                    deviceToken: hex,
                    preferences: preferences.flags
                )
                // The server's map is authoritative: it knows about kinds this
                // build may not have shipped with.
                preferences.merge(server: effective)
                persistPreferences()
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

    /// Flip one setting and upsert it.
    ///
    /// Sends ONLY the flags the user has touched. Sending all sixteen would
    /// freeze today's defaults onto the device row and break the backend's
    /// absent-means-registry-default fallback — the thing that lets new kinds
    /// ship without a backfill.
    ///
    /// Local state is updated FIRST so the toggle responds instantly; a failed
    /// round-trip leaves the local value in place and the next successful
    /// register reconciles it. A switch that springs back under your finger is
    /// worse than one that is briefly optimistic.
    func setPreference(_ flag: String, enabled: Bool) async {
        preferences.set(flag, enabled)
        persistPreferences()

        guard let hex = defaults.string(forKey: Self.cachedTokenKey) else {
            // No token yet — the next handleDeviceToken sends the whole map.
            return
        }
        let hasCachedEmail = defaults.string(forKey: Self.cachedEmailKey)?.isEmpty == false
        let hasCurrentSpotifyEmail = await currentUserEmail() != nil
        guard hasCachedEmail || hasCurrentSpotifyEmail else { return }

        do {
            let effective = try await xomify.registerPushToken(
                deviceToken: hex,
                preferences: preferences.flags
            )
            preferences.merge(server: effective)
            persistPreferences()
        } catch {
            print("❌ Notifications: setPreference failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Inbox

    /// One page of the inbox, newest first.
    func fetchInbox(cursor: String? = nil) async throws -> InboxPage {
        try await xomify.fetchNotifications(limit: 25, cursor: cursor)
    }

    /// Refresh the badge from the server. Failures hold the previous value —
    /// a transient error should not blank a badge the user was relying on.
    func refreshUnreadCount() async {
        do {
            unreadCount = try await xomify.fetchUnreadNotificationCount()
        } catch {
            print("ℹ️ Notifications: unread count refresh failed — \(error.localizedDescription)")
        }
    }

    func markRead(_ tsId: String) async {
        unreadCount = max(0, unreadCount - 1)
        do {
            try await xomify.markNotificationRead(tsId: tsId)
        } catch {
            print("ℹ️ Notifications: markRead failed — \(error.localizedDescription)")
        }
    }

    func markAllRead() async {
        unreadCount = 0
        do {
            try await xomify.markAllNotificationsRead()
        } catch {
            print("ℹ️ Notifications: markAllRead failed — \(error.localizedDescription)")
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

    /// Foreground presentation, decided per kind by
    /// `PushKind.interruptsInForeground`.
    ///
    /// The rule: if the user is already in the app, anything they can see for
    /// themselves is noise. Social events and playlist drops still earn a
    /// banner; the weekly digest, broadcasts and the yearly favorites nudge do
    /// not — they are catch-up content, and the inbox is where catch-up lives.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let payload = PushPayload(userInfo: notification.request.content.userInfo)
        // A newly-arrived push is unread by definition — keep the badge honest
        // without waiting for the next inbox open.
        unreadCount += 1
        completionHandler(payload.kind.interruptsInForeground ? [.banner, .sound] : [])
    }

    /// Push-open routing, driven by the backend's `route` token.
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
        guard let destination = Self.destination(for: payload) else {
            // Nothing sensible to route to — leave the user where they were
            // rather than yanking them somewhere arbitrary.
            return
        }
        navigationStore?.select(destination)
    }

    /// Translate a backend route token into a drawer destination.
    ///
    /// The tokens are SHARED WITH WEB, where the same strings resolve to
    /// Angular routes. Anything unrecognised returns nil — a client that only
    /// half-understands a newer backend should do nothing, not guess.
    ///
    /// `share:<id>` lands on Feed rather than a detail screen: there is still
    /// no share-detail drawer destination, and Feed is the list containing it.
    static func destination(for payload: PushPayload) -> SidebarDestination? {
        let token = payload.route ?? ""
        let head = token.split(separator: ":").first.map(String.init) ?? token

        switch head {
        case "share", "shares":     return .feed
        case "friend", "friends":   return .friends
        case "invite":              return .friends
        case "wrapped":             return .wrapped
        case "release_radar":       return .releaseRadar
        case "favorites":           return .profile
        case "home":                return .feed
        default:
            // No usable route. Fall back on the kind for the pre-registry
            // payloads that predate `route` entirely.
            switch payload.kind {
            case .queueThreshold, .digest, .shareReceived, .shareComment,
                 .shareReaction, .shareListened, .shareRated, .rateReminder:
                return .feed
            case .friendRequest, .friendAccepted, .inviteReceived, .inviteAccepted:
                return .friends
            case .wrappedDrop:      return .wrapped
            case .releaseRadarDrop: return .releaseRadar
            default:                return nil
            }
        }
    }
}
