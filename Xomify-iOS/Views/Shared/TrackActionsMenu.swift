import SwiftUI
import UIKit

/// Unified track action menu. One ellipsis button that exposes every
/// action users can perform on a track across the app:
///
/// - **Play now** — starts playback on the active Spotify device via the Web
///   API. Falls back to deep-linking into Spotify when no device is active.
/// - **Add to queue** — routes to `QueueActionController.shared`.
/// - **Open in Spotify** — deep-links into the Spotify app/web player.
/// - **Add to Playlist Builder** — stashes the track in `PlaylistBuilderManager`.
/// - **Share to Feed** — presents `ShareComposerView` pre-seeded with the track.
///
/// Replaces the scatter of bespoke per-row buttons (play link, queue button,
/// ad-hoc share entry points). Drop-in: pass a `SpotifyTrack` and an optional
/// style; the component owns its own sheet presentation.
struct TrackActionsMenu: View {

    enum Style {
        /// 32pt ellipsis glyph over a translucent circle. Use in dense rows.
        case icon
        /// Labelled pill matching `QueueButton.pill`. Use in card UIs.
        case pill
    }

    let track: SpotifyTrack
    var style: Style = .icon

    @State private var queueAction = QueueActionController.shared
    @State private var playlistBuilder = PlaylistBuilderManager.shared
    @State private var isComposerShown = false

    var body: some View {
        Menu {
            Button {
                Task { await queueAction.play(uri: resolvedUri, trackName: track.name) }
            } label: {
                Label("Play now", systemImage: "play.circle.fill")
            }
            .disabled(resolvedUri.isEmpty || queueAction.isQueuing(uri: resolvedUri))

            Button {
                Task { await queueAction.queue(uri: resolvedUri, trackName: track.name) }
            } label: {
                Label(
                    queueAction.isQueuing(uri: resolvedUri) ? "Queueing…" : "Add to queue",
                    systemImage: "text.badge.plus"
                )
            }
            .disabled(resolvedUri.isEmpty || queueAction.isQueuing(uri: resolvedUri))

            Button {
                openInSpotify()
            } label: {
                Label("Open in Spotify", systemImage: "arrow.up.right.square")
            }

            Button {
                playlistBuilder.addTrack(track)
            } label: {
                Label(
                    playlistBuilder.contains(track) ? "In Playlist Builder" : "Add to Playlist Builder",
                    systemImage: playlistBuilder.contains(track) ? "checkmark.circle.fill" : "plus.square.on.square"
                )
            }
            .disabled(playlistBuilder.contains(track))

            Button {
                isComposerShown = true
            } label: {
                Label("Share to Feed", systemImage: "bubble.left.and.bubble.right.fill")
            }
        } label: {
            switch style {
            case .icon: iconLabel
            case .pill: pillLabel
            }
        }
        .accessibilityLabel("More actions for \(track.name)")
        .sheet(isPresented: $isComposerShown) {
            ShareComposerView(viewModel: makeComposerViewModel()) { _ in
                // Fire-and-forget: the feed refreshes on its own next appearance.
                // Surfacing a global toast would require plumbing we don't have
                // at this call-site, and the post is visible in Spotify anyway.
            }
        }
    }

    // MARK: - Labels

    private var iconLabel: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 32, height: 32)
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private var pillLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "ellipsis.circle")
            Text("Actions")
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 16))
        .frame(minHeight: 44)
    }

    // MARK: - Actions

    private var resolvedUri: String {
        track.uri ?? "spotify:track:\(track.id)"
    }

    private func openInSpotify() {
        if let uri = track.uri, let url = URL(string: uri) {
            UIApplication.shared.open(url)
        } else if let urlString = track.externalUrls?["spotify"], let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "spotify:track:\(track.id)") {
            UIApplication.shared.open(url)
        }
    }

    private func makeComposerViewModel() -> ShareComposerViewModel {
        let vm = ShareComposerViewModel()
        vm.selectTrack(track)
        return vm
    }
}
