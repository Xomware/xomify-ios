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

        // Re-register on EVERY launch, which Apple's documentation requires and
        // this app was not doing. APNs rotates a device token on reinstall,
        // restore-from-backup and some OS updates -- and registration only ever
        // ran inside `requestPermissionIfNeeded()`, which no-ops permanently
        // after the first prompt. So the first token was the only token ever
        // sent to the backend, and once it rotated every push went to a dead
        // address. APNs still answers 200 for a stale token, so nothing
        // upstream ever noticed.
        //
        // Gated on already-authorized: calling it unprompted would not show the
        // permission dialog, but it would register a device that has not opted
        // in and cannot receive anything.
        Task { await NotificationsService.shared.registerIfAuthorized() }

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
