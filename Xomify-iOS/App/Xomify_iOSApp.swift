import SwiftUI


@main
struct Xomify_iOSApp: App {
    /// APNs device-token registration + push-open dispatch.
    /// Owned here so the app has a single delegate for the whole lifecycle.
    @UIApplicationDelegateAdaptor(XomifyAppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    private let coordinator = SpotifyPlaybackCoordinator.shared

    /// Gate the root view until `AuthService.ensureXomifyJwt()` has resolved.
    /// On existing TestFlight installs the keychain holds a Spotify refresh
    /// token but no Xomify JWT (the (0d) per-user JWT only mints inside the
    /// post-OAuth `saveRefreshTokenToXomify` flow). Without this gate, every
    /// view's `.task` modifier races the async mint and slams the backend
    /// with calls that 401 because (1k) removed the legacy email fallback.
    /// Mirrors the web hotfix `APP_INITIALIZER` pattern from PR #263.
    @State private var didBootstrap = false

    var body: some Scene {
        WindowGroup {
            Group {
                if didBootstrap {
                    ContentView()
                } else {
                    BootstrapSplash()
                }
            }
            .preferredColorScheme(.dark) // Force dark mode for Xomify branding
            .environment(coordinator)
            .task {
                // Best-effort: failure is fine (not-logged-in, network blip,
                // refresh token revoked). The bootstrap completes either way
                // so the user is never stuck on the splash. NetworkService
                // still has its single-shot 401-retry as a safety net.
                _ = await AuthService.shared.ensureXomifyJwt()
                didBootstrap = true
            }
            .onOpenURL { url in
                // Route deep links. Invite URLs (Universal Links and custom
                // scheme) are stashed on `InviteCoordinator`; the Friends
                // screen picks them up once it loads.
                //
                // Share deep links (`xomify://share?trackId=`) are stashed on
                // `ShareDeepLinkCoordinator`; `FeedView` consumes them on
                // appearance and pre-loads the composer.
                //
                // Also forward to the SDK in case the URL carries a Spotify
                // auth-handover token (xomify://callback?access_token=...).
                coordinator.remote.handleOpenURL(url)
                InviteCoordinator.shared.handle(url)
                ShareDeepLinkCoordinator.shared.handle(url)
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

/// Brief splash shown while the JWT bootstrap is in flight. Typical duration
/// is 200-500ms; on a cold start of a long-idle install it may stretch to
/// ~1s while the Spotify refresh + mint round-trips complete. We deliberately
/// keep this dead simple — no progress bar, no copy — because crashing into
/// a 401 cascade is the failure mode we are preventing, not slow startup.
private struct BootstrapSplash: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.xomifyDark, Color(red: 18/255, green: 18/255, blue: 37/255)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: XomSpacing.lg) {
                Image("banner-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 240)
                    .shadow(color: .xomifyPurple.opacity(0.5), radius: 20)
                    .accessibilityLabel("Xomify")

                // Paint, not Pulse: this is the splash, and the X drawing
                // itself is the one moment worth spending the full animation
                // on. Mirrors XomFit, which uses its paint loader here and
                // nowhere else at launch.
                XomifyLoaderPaint(size: 60)
            }
        }
    }
}
