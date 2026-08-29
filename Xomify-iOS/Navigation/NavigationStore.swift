import SwiftUI

// MARK: - SidebarDestination

/// All top-level destinations reachable from the sidebar drawer.
/// This is the sole primary-navigation enum — `ShellTab` has been removed.
enum SidebarDestination: Hashable {
    case overview
    case profile
    case feed
    case search
    case likes
    /// Friend-scoped likes page — backend `/likes/by-user` for the given email.
    case friendLikes(email: String)
    case recentlyPlayed
    case musicTaste
    case wrapped
    case releaseRadar
    case ratings
    case favorites
    case friends
    case following
    case builder
    case moodPicks
    case playlistAnalysis
    case settings
}

// MARK: - NavigationStore

@Observable
@MainActor
final class NavigationStore {

    /// The currently visible full-screen destination.
    ///
    /// Overview, not Feed. Landing straight in a social feed gave no sense of
    /// the user's own listening, and buried every other feature in the drawer.
    var currentDestination: SidebarDestination = .overview

    var isDrawerOpen: Bool = false

    // MARK: - Feed integration

    /// Toggled by the Feed screen's FAB and by composer dismissal.
    var composerSheetPresented: Bool = false

    /// When set, the next composer open will pre-populate this track.
    /// Consumed immediately by `FeedView` when it presents the sheet.
    var composerPrefilledTrack: SpotifyTrack? = nil

    /// Set by the Feed empty-state CTAs. `MainShell` observes this and calls
    /// `consumePendingDeepLink()` on the next runloop so the drawer animation
    /// and destination switch don't race.
    var pendingDeepLink: SidebarDestination?

    // MARK: - Drawer control

    func openDrawer() {
        // Spring, not a timed curve. A drawer is a physical object being
        // pulled — and unlike easeInOut, a spring survives interruption: if
        // the user grabs it mid-open it retargets from wherever it actually
        // is, instead of snapping.
        withAnimation(XomMotion.spring) {
            Haptics.light()
            isDrawerOpen = true
        }
    }

    func closeDrawer() {
        withAnimation(XomMotion.spring) {
            isDrawerOpen = false
        }
    }

    /// Select a sidebar destination. Sets `currentDestination` and closes the
    /// drawer in a single animation block so the dismiss + content swap happen
    /// together without an intermediate flash.
    func select(_ destination: SidebarDestination) {
        // Selection tick, not success: picking a destination is navigation,
        // and the screen changing is its own confirmation.
        Haptics.selection()
        withAnimation(XomMotion.spring) {
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
