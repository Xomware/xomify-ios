import SwiftUI

/// Slide-out navigation drawer. Overlays the leading edge of the screen.
/// Width: min(80 % of screen width, 320 pt).
///
/// The drawer is a pure menu: each row calls `navStore.select(_:)` which
/// sets `currentDestination` on `NavigationStore` AND closes the drawer in
/// a single animation. No inner `NavigationStack` lives here — destination
/// views render full-bleed inside `MainShell`.
struct DrawerView: View {
    @Environment(NavigationStore.self) private var navStore

    // MARK: - Drawer entries

    private struct DrawerEntry: Identifiable {
        let destination: SidebarDestination
        let label: String
        let systemImage: String
        var id: SidebarDestination { destination }
    }

    private let entries: [DrawerEntry] = [
        .init(destination: .feed,         label: "Feed",            systemImage: "sparkles"),
        .init(destination: .wrapped,      label: "Wrapped",         systemImage: "chart.bar.fill"),
        .init(destination: .releaseRadar, label: "Release Radar",   systemImage: "antenna.radiowaves.left.and.right"),
        .init(destination: .ratings,      label: "Ratings",         systemImage: "star.fill"),
        .init(destination: .groups,       label: "Groups",          systemImage: "person.3.fill"),
        .init(destination: .friends,      label: "Friends",         systemImage: "person.2.fill"),
        .init(destination: .profile,      label: "Profile",         systemImage: "person.fill"),
        .init(destination: .settings,     label: "Settings",        systemImage: "gearshape.fill"),
        .init(destination: .builder,      label: "Playlist Builder", systemImage: "music.note.list"),
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
        List {
            // App name header inside the drawer.
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
                ForEach(entries) { entry in
                    Button {
                        navStore.select(entry.destination)
                    } label: {
                        Label {
                            Text(entry.label)
                                .foregroundStyle(.white)
                        } icon: {
                            Image(systemName: entry.systemImage)
                                .foregroundStyle(Color.xomifyGreen)
                                .accessibilityHidden(true)
                        }
                    }
                    // 44 pt minimum touch target via explicit frame on the row.
                    .frame(minHeight: 44)
                    .accessibilityLabel(entry.label)
                    .listRowBackground(
                        navStore.currentDestination == entry.destination
                            ? Color.xomifyGreen.opacity(0.15)
                            : Color.xomifyCard
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.xomifyDark)
        .frame(width: drawerWidth)
    }
}
