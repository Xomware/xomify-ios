import SwiftUI

/// Long-press context menu for a track row.
///
/// Reuses `TrackActionsMenu.actionButtons` verbatim, so the long-press menu and
/// the ellipsis menu can never drift apart — which is the usual failure mode
/// when a context menu is bolted on next to an existing one.
///
/// ADDITIVE ON PURPOSE. The ellipsis button stays exactly where it is. A
/// context menu is a shortcut for people who expect one, not a replacement for
/// a visible affordance: an action that exists ONLY behind a long press is an
/// action most users never find, and it is invisible to VoiceOver users
/// navigating by element.
private struct TrackContextMenuModifier: ViewModifier {

    let track: SpotifyTrack
    let shareId: String?
    let onListened: (() -> Void)?
    let onDelete: (() -> Void)?

    func body(content: Content) -> some View {
        content.contextMenu {
            TrackActionsMenu(
                track: track,
                shareId: shareId,
                onListened: onListened
            )
            .actionButtons

            if let onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete post", systemImage: "trash")
                }
            }
        }
    }
}

extension View {
    /// Optional-aware overload.
    ///
    /// Several rows resolve their `SpotifyTrack` lazily and only render the
    /// ellipsis menu inside an `if let`, so the row's own modifier chain has
    /// no `track` in scope. Rather than push a conditional into every such
    /// call site, a nil track simply means no context menu.
    @ViewBuilder
    func trackContextMenu(
        track: SpotifyTrack?,
        shareId: String? = nil,
        onListened: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        if let track {
            self.trackContextMenu(
                track: track,
                shareId: shareId,
                onListened: onListened,
                onDelete: onDelete
            )
        } else {
            self
        }
    }

    /// Attach the standard track actions as a long-press context menu.
    ///
    /// Use ALONGSIDE `TrackActionsMenu`, never instead of it.
    func trackContextMenu(
        track: SpotifyTrack,
        shareId: String? = nil,
        onListened: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        modifier(
            TrackContextMenuModifier(
                track: track,
                shareId: shareId,
                onListened: onListened,
                onDelete: onDelete
            )
        )
    }
}
