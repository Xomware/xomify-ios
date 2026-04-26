import SwiftUI

/// Signed-in root view. Hosts a full-screen `NavigationStack` whose root
/// switches on `navStore.currentDestination`. The slide-out `DrawerView` and
/// its `DrawerScrim` are overlaid above the content column.
///
/// Architecture: the drawer is a pure menu — it mutates `currentDestination`
/// via `navStore.select(_:)` and never hosts its own navigation stack.
struct MainShell: View {

    // MARK: - State

    @State private var navStore = NavigationStore()
    @State private var avatarURL: URL? = nil
    @State private var displayName: String? = nil
    @State private var userEmail: String? = nil

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .leading) {
            // Ambient brand background — wandering blurred blobs + occasional
            // lightning. Purely decorative; hit-testing disabled.
            AmbientBackground()
                .opacity(0.35)

            // Primary content: header bar + full-screen destination.
            VStack(spacing: 0) {
                HeaderBar(avatarURL: avatarURL)
                    .environment(navStore)

                NavigationStack {
                    destinationRoot
                }
            }

            // Scrim — above content, below drawer.
            DrawerScrim()
                .environment(navStore)

            // Drawer — slides in from the leading edge.
            DrawerView(
                avatarURL: avatarURL,
                displayName: displayName,
                email: userEmail
            )
            .environment(navStore)

            // App-root toast for Queue actions. Floats above everything.
            QueueToastHost()
        }
        .environment(navStore)
        .ignoresSafeArea(edges: .bottom)
        .gesture(edgeDragGesture)
        .task {
            // Share the nav store with the push pipeline so push-open handlers
            // can call `select(.feed)`.
            NotificationsService.shared.navigationStore = navStore
            await fetchAvatar()
        }
        .onChange(of: navStore.pendingDeepLink) { _, newValue in
            // Feed empty-state CTAs set `pendingDeepLink`; consume on the next
            // runloop so the drawer animation runs cleanly.
            guard newValue != nil else { return }
            Task { @MainActor in
                navStore.consumePendingDeepLink()
            }
        }
    }

    // MARK: - Destination root

    @ViewBuilder
    private var destinationRoot: some View {
        switch navStore.currentDestination {
        case .profile:
            ProfileView()
        case .feed:
            FeedView()
        case .likes:
            LikesView()
        case .recentlyPlayed:
            RecentlyPlayedView()
        case .musicTaste:
            TopItemsView()
        case .wrapped:
            WrappedView()
        case .releaseRadar:
            ReleaseRadarView()
        case .ratings:
            RatingsHistoryView()
        case .friends:
            FriendsView()
        case .groups:
            GroupsView()
        case .builder:
            PlaylistBuilderTabView()
        case .moodPicks:
            MoodPicksView()
        case .playlistAnalysis:
            PlaylistAnalysisView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: - Edge swipe → drawer

    /// Edge swipe: a horizontal drag started near the leading edge that pulls
    /// the drawer open, mirroring the system-wide left-edge gesture you'd
    /// expect on iOS. We require the gesture to *start* in the leftmost ~30pt
    /// so it doesn't fight horizontal scrolls inside content (carousels, etc).
    private var edgeDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onEnded { value in
                let startedAtEdge = value.startLocation.x < 30
                let pulledRight = value.translation.width > 60
                let mostlyHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                guard !navStore.isDrawerOpen,
                      startedAtEdge,
                      pulledRight,
                      mostlyHorizontal else { return }
                navStore.openDrawer()
            }
    }

    // MARK: - Avatar fetch

    /// Fetches the current user's profile image URL and display info for the
    /// header bar + drawer profile card. Non-blocking — placeholders show
    /// until the request resolves.
    private func fetchAvatar() async {
        do {
            let user = try await SpotifyService.shared.getCurrentUser()
            avatarURL = user.profileImageUrl
            displayName = user.displayName
            userEmail = user.email
        } catch {
            // Silently fall back — non-critical.
        }
    }
}

#Preview {
    MainShell()
}
