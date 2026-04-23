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
        guard !isUpdatingEnrollment, let email = user?.email else { return }
        isUpdatingEnrollment = true
        let newValue = !isWrappedEnrolled
        do {
            try await xomifyService.updateEnrollments(
                email: email,
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
        guard !isUpdatingEnrollment, let email = user?.email else { return }
        isUpdatingEnrollment = true
        let newValue = !isReleaseRadarEnrolled
        do {
            try await xomifyService.updateEnrollments(
                email: email,
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

    func logout() {
        authService.logout()
    }

    // MARK: - Private

    private func loadXomifyStatus(email: String) async {
        do {
            let userData = try await xomifyService.getUserData(email: email)
            isWrappedEnrolled = userData.activeWrapped
            isReleaseRadarEnrolled = userData.activeReleaseRadar
            print("✅ Settings: enrollment loaded — Wrapped: \(isWrappedEnrolled), RR: \(isReleaseRadarEnrolled)")
        } catch {
            // User may not exist yet in Xomify — that's fine.
            isWrappedEnrolled = false
            isReleaseRadarEnrolled = false
            print("⚠️ Settings: could not load Xomify enrollment — \(error)")
        }
    }

    /// Push the latest notification flags to the backend. Swallows network
    /// errors so the UI stays responsive; `UserDefaults` is the source of truth
    /// and the backend reconciles on the next token register.
    private func syncNotificationPreferences() {
        let queue = queueNotificationsEnabled
        let digest = digestEnabled
        Task { @MainActor in
            await notificationsService.updatePreferences(
                queueNotificationsEnabled: queue,
                digestEnabled: digest
            )
        }
    }
}
