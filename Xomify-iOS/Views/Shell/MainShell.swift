import SwiftUI

/// Signed-in root view. Replaces MainTabView.
/// ZStack layout: persistent HeaderBar + 4-tab TabView, with DrawerView + DrawerScrim overlaid.
struct MainShell: View {

    // MARK: - State

    @State private var navStore = NavigationStore()
    @State private var avatarURL: URL? = nil

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .leading) {
            // Primary content: header + tab bar.
            VStack(spacing: 0) {
                HeaderBar(avatarURL: avatarURL)
                    .environment(navStore)

                TabView(selection: Binding(
                    get: { navStore.selectedTab },
                    set: { navStore.selectedTab = $0 }
                )) {
                    // Home — routes to ProfileView (existing Home screen).
                    NavigationStack {
                        ProfileView()
                    }
                    .tabItem {
                        Label(ShellTab.home.label, systemImage: ShellTab.home.systemImage)
                    }
                    .tag(ShellTab.home)

                    // Feed — placeholder until ios-feed (#5).
                    FeedPlaceholderView()
                        .tabItem {
                            Label(ShellTab.feed.label, systemImage: ShellTab.feed.systemImage)
                        }
                        .tag(ShellTab.feed)

                    // Releases.
                    NavigationStack {
                        ReleaseRadarView()
                    }
                    .tabItem {
                        Label(ShellTab.releases.label, systemImage: ShellTab.releases.systemImage)
                    }
                    .tag(ShellTab.releases)

                    // Builder.
                    PlaylistBuilderTabView()
                        .tabItem {
                            Label(ShellTab.builder.label, systemImage: ShellTab.builder.systemImage)
                        }
                        .tag(ShellTab.builder)
                }
                .tint(Color.xomifyGreen)
            }

            // Scrim — renders above content, below drawer.
            DrawerScrim()
                .environment(navStore)

            // Drawer — slides in from leading edge.
            DrawerView()
                .environment(navStore)
        }
        .environment(navStore)
        .ignoresSafeArea(edges: .bottom)
        .task {
            await fetchAvatar()
        }
    }

    // MARK: - Avatar fetch

    /// Fetches the current user profile for the header avatar.
    /// Non-blocking — placeholder shown until resolved.
    private func fetchAvatar() async {
        do {
            let user = try await SpotifyService.shared.getCurrentUser()
            await MainActor.run {
                avatarURL = user.profileImageUrl
            }
        } catch {
            // Silently fall back to SF symbol placeholder — non-critical.
        }
    }
}

#Preview {
    MainShell()
}
