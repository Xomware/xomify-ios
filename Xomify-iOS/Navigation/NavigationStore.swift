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
}
