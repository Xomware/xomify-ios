import Foundation
import SwiftUI
import UserNotifications

/// Drives the Settings screen's notification section. Views never call
/// `NotificationsService` directly — every toggle flip routes through here.
///
/// State mirrors `@AppStorage` (persisted across launches) but exposes the
/// values as `@Observable` fields so the view can bind without leaking
/// persistence concerns.
@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - Persisted toggle keys (shared with NotificationsService)

    static let queueEnabledKey = NotificationsService.queueEnabledKey
    static let digestEnabledKey = NotificationsService.digestEnabledKey

    // MARK: - State

    /// Queue-threshold push opt-in. Persisted to UserDefaults immediately on set.
    var queueNotificationsEnabled: Bool {
        didSet {
            guard oldValue != queueNotificationsEnabled else { return }
            defaults.set(queueNotificationsEnabled, forKey: Self.queueEnabledKey)
            syncPreferences()
        }
    }

    /// Weekly digest push opt-in.
    var digestEnabled: Bool {
        didSet {
            guard oldValue != digestEnabled else { return }
            defaults.set(digestEnabled, forKey: Self.digestEnabledKey)
            syncPreferences()
        }
    }

    /// Current system-level APNs authorization. Polled on view appear.
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Dependencies

    private let notificationsService: NotificationsService
    private let defaults: UserDefaults

    // MARK: - Init

    init(
        notificationsService: NotificationsService = NotificationsService.shared,
        defaults: UserDefaults = .standard
    ) {
        self.notificationsService = notificationsService
        self.defaults = defaults

        // Default both toggles to true (matches backend default + the
        // previously-stubbed `@AppStorage` defaults on `SettingsView`).
        self.queueNotificationsEnabled = defaults.object(forKey: Self.queueEnabledKey) as? Bool ?? true
        self.digestEnabled = defaults.object(forKey: Self.digestEnabledKey) as? Bool ?? true
    }

    // MARK: - Lifecycle

    /// Refresh the authorization status. Called on view appear.
    func refreshAuthorizationStatus() async {
        authorizationStatus = await notificationsService.currentAuthorizationStatus()
    }

    // MARK: - Derived UI state

    /// Whether the toggles should be editable. Disabled when the user has
    /// denied permission — they must visit System Settings first.
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

    /// Copy shown below the notifications section footer.
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

    // MARK: - System settings deep link

    /// URL used by the Settings screen's "Open System Settings" button when
    /// permission has been denied.
    var systemSettingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    // MARK: - Private

    /// Push the latest flags to the backend. Swallows network errors so the UI
    /// stays responsive; the local `@AppStorage` value is the source of truth
    /// and the backend reconciles on next register.
    private func syncPreferences() {
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
