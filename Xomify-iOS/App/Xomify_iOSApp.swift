import SwiftUI

@main
struct Xomify_iOSApp: App {
    /// APNs device-token registration + push-open dispatch.
    /// Owned here so the app has a single delegate for the whole lifecycle.
    @UIApplicationDelegateAdaptor(XomifyAppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    private let coordinator = SpotifyPlaybackCoordinator.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark) // Force dark mode for Xomify branding
                .environment(coordinator)
                .onOpenURL { url in
                    // Route deep links. Invite URLs (Universal Links and custom
                    // scheme) are stashed on `InviteCoordinator`; the Friends
                    // screen picks them up once it loads.
                    //
                    // Also forward to the SDK in case the URL carries a Spotify
                    // auth-handover token (xomify://callback?access_token=...).
                    coordinator.remote.handleOpenURL(url)
                    InviteCoordinator.shared.handle(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    // Universal Link handoff — the user tapped a Safari/Messages
                    // link that resolved to us. Extract the URL and delegate to
                    // the same coordinator path.
                    if let url = activity.webpageURL {
                        InviteCoordinator.shared.handle(url)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        Task { await coordinator.connectIfAuthenticated() }
                    case .background:
                        coordinator.disconnect()
                    default:
                        break
                    }
                }
        }
    }
}
