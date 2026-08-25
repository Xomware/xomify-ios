import SwiftUI
import UIKit

/// Bottom sheet that mirrors the web "card flip" surface: tap a track row,
/// see the album art, basic metadata (artist, album, year, duration), a
/// popularity bar, and quick actions (open in Spotify, add to queue, add to
/// playlist builder). iOS doesn't have a natural row-flip equivalent so we
/// promote the same content to a modal instead of trying to recreate the
/// flip animation 1:1.
///
/// Use via `.trackQuickInfoSheet(track:)` on any container.
struct TrackQuickInfoSheet: View {

    let track: SpotifyTrack

    @Environment(\.dismiss) private var dismiss
    @State private var queueAction = QueueActionController.shared
    @State private var playlistBuilder = PlaylistBuilderManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    artwork
                    titleBlock
                    metadataRow
                    popularityBar
                    actions
                    // TODO: 30s preview playback. `track.previewUrl` is a
                    // direct mp3 from Spotify and would need an AVPlayer +
                    // a small audio coordinator. There's no PlayerService
                    // in the app yet, so leaving as a follow-up rather than
                    // bolting one on inline.
                }
                .padding(.horizontal, XomSpacing.lg)
                .padding(.top, XomSpacing.sm)
                .padding(.bottom, XomSpacing.xl)
            }
            .background(Color.xomifyDark.ignoresSafeArea())
            .navigationTitle("Track Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var artwork: some View {
        AsyncImage(url: track.imageUrl) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
        }
        .frame(width: 200, height: 200)
        .clipShape(.rect(cornerRadius: XomRadius.xl))
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text(track.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(track.artistNames)
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.name) by \(track.artistNames)")
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 12) {
            metadataPill(
                icon: "opticaldisc",
                title: "Album",
                value: albumLine
            )
            metadataPill(
                icon: "clock",
                title: "Duration",
                value: track.duration
            )
        }
    }

    private var albumLine: String {
        let name = track.album?.name ?? "—"
        if let year = track.album?.year {
            return "\(name) · \(year)"
        }
        return name
    }

    private func metadataPill(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption)
            .foregroundStyle(.gray)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(XomSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(.rect(cornerRadius: XomRadius.lg))
    }

    private var popularityBar: some View {
        let popularity = max(0, min(100, track.popularity ?? 0))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Popularity")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                Text("\(popularity)/100")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.xomifyPurple, .xomifyGreen],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(popularity) / 100)
                }
            }
            .frame(height: 8)
        }
        .padding(XomSpacing.md)
        .background(Color.white.opacity(0.05))
        .clipShape(.rect(cornerRadius: XomRadius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Popularity \(popularity) out of 100")
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                openInSpotify()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Open in Spotify")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.xomifyGreen)
                .foregroundStyle(.black)
                .clipShape(.rect(cornerRadius: XomRadius.pill))
            }
            .frame(minHeight: 44)

            HStack(spacing: 10) {
                Button {
                    Task { await queueAction.queue(uri: resolvedUri, trackName: track.name) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.badge.plus")
                        Text(queueAction.isQueuing(uri: resolvedUri) ? "Queueing…" : "Queue")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, XomSpacing.md)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: XomRadius.pill))
                }
                .frame(minHeight: 44)
                .disabled(queueAction.isQueuing(uri: resolvedUri))

                Button {
                    playlistBuilder.addTrack(track)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: playlistBuilder.contains(track) ? "checkmark.circle.fill" : "plus.square.on.square")
                        Text(playlistBuilder.contains(track) ? "Added" : "Builder")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, XomSpacing.md)
                    .background(Color.xomifyPurple.opacity(0.25))
                    .foregroundStyle(Color.xomifyPurple)
                    .clipShape(.rect(cornerRadius: XomRadius.pill))
                }
                .frame(minHeight: 44)
                .disabled(playlistBuilder.contains(track))
            }
        }
        .padding(.top, XomSpacing.xs)
    }

    // MARK: - Helpers

    private var resolvedUri: String {
        track.uri ?? "spotify:track:\(track.id)"
    }

    private func openInSpotify() {
        if let urlString = track.externalUrls?["spotify"], let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        } else if let uri = track.uri, let url = URL(string: uri) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "spotify:track:\(track.id)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Convenience modifier

extension View {
    /// Presents `TrackQuickInfoSheet` when `track` is non-nil. Pair with a
    /// `@State var quickInfoTrack: SpotifyTrack?` and assign on tap.
    func trackQuickInfoSheet(track: Binding<SpotifyTrack?>) -> some View {
        sheet(item: track) { TrackQuickInfoSheet(track: $0) }
    }
}
