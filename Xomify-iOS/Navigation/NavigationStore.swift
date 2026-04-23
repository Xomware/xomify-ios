import SwiftUI

// MARK: - ShellTab

enum ShellTab: Hashable, CaseIterable {
    case home, feed, releases, builder

    var label: String {
        switch self {
        case .home:     "Home"
        case .feed:     "Feed"
        case .releases: "Releases"
        case .builder:  "Builder"
        }
    }

    var systemImage: String {
        switch self {
        case .home:     "house.fill"
        case .feed:     "sparkles"
        case .releases: "antenna.radiowaves.left.and.right"
        case .builder:  "music.note.list"
        }
    }
}

// MARK: - DrawerDestination

enum DrawerDestination: Hashable {
    case profile
    case stats
    case following
    case friends
    case groups
    case ratingsHistory
    case settings
    case helpAbout
}

// MARK: - NavigationStore

@Observable
@MainActor
final class NavigationStore {
    var selectedTab: ShellTab = .home
    var isDrawerOpen: Bool = false
    var drawerPath: [DrawerDestination] = []

    // MARK: - Feed integration (ios-feed)

    /// Toggled by the Feed tab's FAB and by composer dismissal.
    var composerSheetPresented: Bool = false

    /// Set by the Feed empty-state CTAs. `MainShell` observes this, opens the
    /// drawer, and consumes the value via `consumePendingDeepLink()` on the
    /// next runloop so the drawer animation and path push don't race.
    var pendingDeepLink: DrawerDestination?

    func openDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isDrawerOpen = true
        }
    }

    func closeDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isDrawerOpen = false
            drawerPath.removeAll()
        }
    }

    func navigate(to destination: DrawerDestination) {
        drawerPath.append(destination)
    }

    // MARK: - Deep link intent

    /// Request a drawer deep link. The observer (`MainShell`) is responsible
    /// for opening the drawer and pushing the destination on the path.
    func requestDeepLink(_ destination: DrawerDestination) {
        pendingDeepLink = destination
    }

    /// Consume the pending deep link, opening the drawer + pushing the
    /// destination. No-op when no link is pending.
    func consumePendingDeepLink() {
        guard let destination = pendingDeepLink else { return }
        pendingDeepLink = nil
        openDrawer()
        drawerPath.append(destination)
    }
}
