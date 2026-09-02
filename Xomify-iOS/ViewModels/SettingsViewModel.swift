import Foundation
import SwiftUI
import UserNotifications

/// Drives the Settings screen.
///
/// Owns:
///  - Push-notification toggles (persisted to `UserDefaults` via `NotificationsService`).
///  - Xomify feature-enrollment toggles (Wrapped, Release Radar).
///  - Spotify account read-outs (country, subscription, user ID, profile URL).
///  - Sign-out action.
///
/// Views never touch `NotificationsService`, `XomifyService`, or `AuthService` directly —
/// every side-effect routes through this VM.
@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - Persisted notification toggle keys (shared with NotificationsService)

    static let queueEnabledKey = NotificationsService.queueEnabledKey
    static let digestEnabledKey = NotificationsService.digestEnabledKey

    // MARK: - Notification state

    /// Queue-threshold push opt-in. Persisted to `UserDefaults` immediately on set.
    var queueNotificationsEnabled: Bool {
        didSet {
            guard oldValue != queueNotificationsEnabled else { return }
            defaults.set(queueNotificationsEnabled, forKey: Self.queueEnabledKey)
            syncNotificationPreferences()
        }
    }

    /// Weekly digest push opt-in.
    var digestEnabled: Bool {
        didSet {
            guard oldValue != digestEnabled else { return }
            defaults.set(digestEnabled, forKey: Self.digestEnabledKey)
            syncNotificationPreferences()
        }
    }

    /// Current system-level APNs authorization. Refreshed on view appear.
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Enrollment state

    var isWrappedEnrolled: Bool = false
    var isReleaseRadarEnrolled: Bool = false
    var isUpdatingEnrollment: Bool = false

    // MARK: - Likes privacy

    /// Whether the user's liked songs are visible to friends.
    /// Defaults to `true` (matches backend default); persisted locally and
    /// synced to `/users/likes-public` when toggled.
    var likesPublic: Bool = true {
        didSet {
            guard oldValue != likesPublic else { return }
            syncLikesPublic()
        }
    }
    var isUpdatingLikesPublic: Bool = false

    // Friend visibility. Each syncs independently so flipping one never
    // rewrites the other two -- the endpoint takes a partial body for the same
    // reason. Default true matches the backend, which treats an unset flag as
    // `friends`.
    var wrappedVisible: Bool = true {
        didSet {
            guard oldValue != wrappedVisible, !isApplyingRemoteVisibility else { return }
            syncVisibility(wrapped: wrappedVisible)
        }
    }

    var releaseRadarVisible: Bool = true {
        didSet {
            guard oldValue != releaseRadarVisible, !isApplyingRemoteVisibility else { return }
            syncVisibility(releaseRadar: releaseRadarVisible)
        }
    }

    var topItemsVisible: Bool = true {
        didSet {
            guard oldValue != topItemsVisible, !isApplyingRemoteVisibility else { return }
            syncVisibility(topItems: topItemsVisible)
        }
    }

    var isUpdatingVisibility: Bool = false

    /// Set while adopting server state, so the toggles' didSet does not echo
    /// it straight back as three writes.
    private var isApplyingRemoteVisibility = false

    // MARK: - Account state

    /// The signed-in Spotify user. Populated by `load()`.
    private var user: SpotifyUser?

    var isLoading: Bool = false
    var errorMessage: String?

    var displayName: String { user?.displayName ?? "" }
    var country: String { user?.country ?? "" }
    var accountType: String { user?.product?.capitalized ?? "Free" }
    var userId: String { user?.id ?? "" }
    var spotifyProfileUrl: URL? {
        guard let urlString = user?.externalUrls?["spotify"] else { return nil }
        return URL(string: urlString)
    }
    var userEmail: String { user?.email ?? "" }

    // MARK: - Derived notification UI state

    /// Whether the notification toggles are editable. Disabled when the user
    /// has denied permission — they must visit System Settings first.
    var togglesEnabled: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Footer copy shown beneath the notifications section.
    var statusFooter: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Preferences sync instantly when you toggle them."
        case .notDetermined:
            return "Enable notifications to use these toggles."
        case .denied:
            return "Notifications are disabled in System Settings. Tap below to turn them on."
        @unknown default:
            return ""
        }
    }

    /// URL for the Settings screen's "Open System Settings" button.
    var systemSettingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    // MARK: - Dependencies

    private let notificationsService: NotificationsService
    private let spotifyService: SpotifyService
    private let xomifyService: XomifyService
    private let authService: AuthService
    private let defaults: UserDefaults

    // MARK: - Init

    init(
        notificationsService: NotificationsService = NotificationsService.shared,
        spotifyService: SpotifyService = SpotifyService.shared,
        xomifyService: XomifyService = XomifyService.shared,
        authService: AuthService = AuthService.shared,
        defaults: UserDefaults = .standard
    ) {
        self.notificationsService = notificationsService
        self.spotifyService = spotifyService
        self.xomifyService = xomifyService
        self.authService = authService
        self.defaults = defaults

        // Default both notification toggles to true — matches backend default.
        self.queueNotificationsEnabled = defaults.object(forKey: Self.queueEnabledKey) as? Bool ?? true
        self.digestEnabled = defaults.object(forKey: Self.digestEnabledKey) as? Bool ?? true
    }

    // MARK: - Lifecycle

    /// Load all settings data. Call from `.task` on the Settings screen.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        async let statusTask: Void = refreshAuthorizationStatus()

        do {
            let fetchedUser = try await spotifyService.getCurrentUser()
            user = fetchedUser

            if let email = fetchedUser.email {
                await loadXomifyStatus(email: email)
            }
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Settings: failed to load user — \(error)")
        }

        await statusTask
        isLoading = false
    }

    /// Refresh the APNs authorization status. Can be called independently on view appear.
    func refreshAuthorizationStatus() async {
        authorizationStatus = await notificationsService.currentAuthorizationStatus()
    }

    // MARK: - Enrollment

    func toggleWrappedEnrollment() async {
        guard !isUpdatingEnrollment, user?.email != nil else { return }
        isUpdatingEnrollment = true
        let newValue = !isWrappedEnrolled
        do {
            try await xomifyService.updateEnrollments(
                activeWrapped: newValue,
                activeReleaseRadar: isReleaseRadarEnrolled
            )
            isWrappedEnrolled = newValue
            print("✅ Settings: Wrapped enrollment → \(newValue)")
        } catch {
            print("❌ Settings: Failed to update Wrapped enrollment — \(error)")
        }
        isUpdatingEnrollment = false
    }

    func toggleReleaseRadarEnrollment() async {
        guard !isUpdatingEnrollment, user?.email != nil else { return }
        isUpdatingEnrollment = true
        let newValue = !isReleaseRadarEnrolled
        do {
            try await xomifyService.updateEnrollments(
                activeWrapped: isWrappedEnrolled,
                activeReleaseRadar: newValue
            )
            isReleaseRadarEnrolled = newValue
            print("✅ Settings: Release Radar enrollment → \(newValue)")
        } catch {
            print("❌ Settings: Failed to update Release Radar enrollment — \(error)")
        }
        isUpdatingEnrollment = false
    }

    // MARK: - Auth

    func logout() async {
        await authService.logout()
    }

    // MARK: - Private

    private func loadXomifyStatus(email: String) async {
        do {
            _ = email
            let userData = try await xomifyService.getUserData()
            isWrappedEnrolled = userData.activeWrapped ?? false
            isReleaseRadarEnrolled = userData.activeReleaseRadar ?? false
            print("✅ Settings: enrollment loaded — Wrapped: \(isWrappedEnrolled), RR: \(isReleaseRadarEnrolled)")

            // Separate call: enrollment comes from /wrapped/all, visibility
            // from /user/data. A failure here must not blank the toggles —
            // showing everything ON when we could not read the real state
            // would misreport who can see their data, so leave them alone.
            if let table = try? await xomifyService.getUserTableData() {
                adoptVisibility(table.visibility)
            }
        } catch {
            // User may not exist yet in Xomify — that's fine.
            isWrappedEnrolled = false
            isReleaseRadarEnrolled = false
            print("⚠️ Settings: could not load Xomify enrollment — \(error)")
        }
    }

    /// Push the latest notification flags to the backend. Swallows network
    /// errors so the UI stays responsive; the local value stands and the next
    /// successful token register reconciles it.
    ///
    /// These two toggles predate the per-kind registry and are kept because
    /// they are the ones already bound in the existing Settings drawer. They
    /// now write through the same `setPreference` path as every other kind, so
    /// there is one code path rather than two that can disagree.
    private func syncNotificationPreferences() {
        let queue = queueNotificationsEnabled
        let digest = digestEnabled
        Task { @MainActor in
            await notificationsService.setPreference("queueNotificationsEnabled", enabled: queue)
            await notificationsService.setPreference("digestEnabled", enabled: digest)
        }
    }

    /// Push the `likes_public` flag to the backend. Swallows errors — the
    /// in-memory toggle provides immediate UI feedback.
    /// Push ONE flag. On failure the toggle snaps back, because a switch that
    /// stays on after the write failed is a lie about who can see your data.
    /// Adopt the stored state WITHOUT firing the didSet writes — assigning
    /// through the observed properties would post three updates back to the
    /// server for values that just came from it.
    private func adoptVisibility(_ v: VisibilitySettings?) {
        guard let v else { return }
        isApplyingRemoteVisibility = true
        wrappedVisible = v.wrapped != VisibilitySettings.private
        releaseRadarVisible = v.releaseRadar != VisibilitySettings.private
        topItemsVisible = v.topItems != VisibilitySettings.private
        isApplyingRemoteVisibility = false
    }

    private func syncVisibility(wrapped: Bool? = nil, releaseRadar: Bool? = nil, topItems: Bool? = nil) {
        func value(_ on: Bool?) -> String? {
            on.map { $0 ? VisibilitySettings.friends : VisibilitySettings.private }
        }
        isUpdatingVisibility = true
        Task { @MainActor in
            do {
                try await xomifyService.setVisibility(
                    wrapped: value(wrapped),
                    releaseRadar: value(releaseRadar),
                    topItems: value(topItems)
                )
            } catch {
                print("⚠️ Settings: setVisibility failed — \(error)")
                if wrapped != nil { wrappedVisible.toggle() }
                if releaseRadar != nil { releaseRadarVisible.toggle() }
                if topItems != nil { topItemsVisible.toggle() }
            }
            isUpdatingVisibility = false
        }
    }

    private func syncLikesPublic() {
        let value = likesPublic
        isUpdatingLikesPublic = true
        Task { @MainActor in
            do {
                _ = try await xomifyService.setLikesPublic(value: value)
                print("✅ Settings: likesPublic → \(value)")
            } catch {
                print("⚠️ Settings: setLikesPublic failed — \(error)")
            }
            isUpdatingLikesPublic = false
        }
    }
}
