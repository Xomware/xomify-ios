import UIKit
import UserNotifications

/// Minimal `UIApplicationDelegate` introduced solely to hook APNs device-token
/// registration. All business logic lives in `NotificationsService` — the
/// delegate forwards events and does nothing else.
///
/// Wired into the SwiftUI lifecycle via `@UIApplicationDelegateAdaptor` on
/// `Xomify_iOSApp`.
final class XomifyAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register `NotificationsService` as the notification center delegate so
        // foreground presentation + push-open dispatch route through it.
        UNUserNotificationCenter.current().delegate = NotificationsService.shared
        return true
    }

    // MARK: - APNs token lifecycle

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await NotificationsService.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationsService.shared.handleRegistrationFailure(error)
        }
    }
}
