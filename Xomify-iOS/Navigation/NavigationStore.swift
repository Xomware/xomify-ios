import SwiftUI

// MARK: - SidebarDestination

/// All top-level destinations reachable from the sidebar drawer.
/// This is the sole primary-navigation enum — `ShellTab` has been removed.
enum SidebarDestination: Hashable {
    case profile
    case feed
    case likes
    case recentlyPlayed
    case musicTaste
    case wrapped
    case releaseRadar
    case ratings
    case friends
    case groups
    case builder
    case moodPicks
    case playlistAnalysis
    case settings
}

// MARK: - NavigationStore

@Observable
@MainActor
final class NavigationStore {

    /// The currently visible full-screen destination. Defaults to Feed on cold launch.
    var currentDestination: SidebarDestination = .feed

    var isDrawerOpen: Bool = false

    // MARK: - Feed integration

    /// Toggled by the Feed screen's FAB and by composer dismissal.
    var composerSheetPresented: Bool = false

    /// Set by the Feed empty-state CTAs. `MainShell` observes this and calls
    /// `consumePendingDeepLink()` on the next runloop so the drawer animation
    /// and destination switch don't race.
    var pendingDeepLink: SidebarDestination?

    // MARK: - Drawer control

    func openDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isDrawerOpen = true
        }
    }

    func closeDrawer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isDrawerOpen = false
        }
    }

    /// Select a sidebar destination. Sets `currentDestination` and closes the
    /// drawer in a single animation block so the dismiss + content swap happen
    /// together without an intermediate flash.
    func select(_ destination: SidebarDestination) {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentDestination = destination
            isDrawerOpen = false
        }
    }

    // MARK: - Deep-link intent

    /// Request a navigation deep link. The observer (`MainShell`) is responsible
    /// for consuming it via `consumePendingDeepLink()` on the next runloop.
    func requestDeepLink(_ destination: SidebarDestination) {
        pendingDeepLink = destination
    }

    /// Consume the pending deep link, switching to the destination.
    /// No-op when no link is pending.
    func consumePendingDeepLink() {
        guard let destination = pendingDeepLink else { return }
        pendingDeepLink = nil
        select(destination)
    }
}
