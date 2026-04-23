import SwiftUI

/// Slide-out navigation drawer. Overlays leading edge of the screen.
/// Width: min(80% of screen width, 320pt) per plan spec.
struct DrawerView: View {
    @Environment(NavigationStore.self) private var navStore

    // MARK: - Drawer entries

    private struct DrawerEntry {
        let destination: DrawerDestination
        let label: String
        let systemImage: String
    }

    private let entries: [DrawerEntry] = [
        .init(destination: .profile,        label: "Profile",         systemImage: "person.fill"),
        .init(destination: .stats,          label: "Stats",           systemImage: "chart.bar.fill"),
        .init(destination: .following,      label: "Following",       systemImage: "music.mic"),
        .init(destination: .friends,        label: "Friends",         systemImage: "person.2.fill"),
        .init(destination: .groups,         label: "Groups",          systemImage: "person.3.fill"),
        .init(destination: .ratingsHistory, label: "Ratings History", systemImage: "star.fill"),
        .init(destination: .settings,       label: "Settings",        systemImage: "gearshape.fill"),
        .init(destination: .helpAbout,      label: "Help & About",    systemImage: "questionmark.circle.fill"),
    ]

    // MARK: - Layout constants

    private let drawerWidth: CGFloat = {
        let screenWidth = UIScreen.main.bounds.width
        return min(screenWidth * 0.80, 320)
    }()

    // MARK: - Body

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                drawerPanel
                Spacer()
            }
        }
        .offset(x: navStore.isDrawerOpen ? 0 : -drawerWidth)
    }

    // MARK: - Drawer panel

    private var drawerPanel: some View {
        NavigationStack(path: Binding(
            get: { navStore.drawerPath },
            set: { navStore.drawerPath = $0 }
        )) {
            List {
                // App name header inside drawer.
                Section {
                    Text("Xomify")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                // Navigation entries.
                Section {
                    ForEach(entries, id: \.destination) { entry in
                        Button {
                            navStore.navigate(to: entry.destination)
                        } label: {
                            Label {
                                Text(entry.label)
                                    .foregroundStyle(.white)
                                    .accessibilityLabel(entry.label)
                            } icon: {
                                Image(systemName: entry.systemImage)
                                    .foregroundStyle(Color.xomifyGreen)
                                    .accessibilityHidden(true)
                            }
                        }
                        .listRowBackground(Color.xomifyCard)
                    }
                }

                // Sign out at the bottom.
                Section {
                    Button(role: .destructive) {
                        navStore.closeDrawer()
                        AuthService.shared.logout()
                    } label: {
                        Label {
                            Text("Sign out")
                                .accessibilityLabel("Sign out")
                        } icon: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .accessibilityHidden(true)
                        }
                    }
                    .listRowBackground(Color.xomifyCard)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.xomifyDark)
            .navigationDestination(for: DrawerDestination.self) { destination in
                destinationView(for: destination)
            }
        }
        .frame(width: drawerWidth)
        .background(Color.xomifyDark)
    }

    // MARK: - Destination routing

    @ViewBuilder
    private func destinationView(for destination: DrawerDestination) -> some View {
        switch destination {
        case .profile:
            ProfileView()
        case .stats:
            StatsView()
        case .following:
            FollowingContent()
        case .friends:
            FriendsView()
        case .groups:
            GroupsView()
        case .ratingsHistory:
            RatingsHistoryView()
        case .settings:
            SettingsView()
        case .helpAbout:
            HelpAboutView()
        }
    }
}
