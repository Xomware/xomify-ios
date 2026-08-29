import SwiftUI

/// The app's landing screen — mirrors the web dashboard at `/`.
///
/// Replaces Feed as the cold-launch destination. Landing straight in a social
/// feed gave no sense of the user's own listening, and made every other feature
/// something you had to go looking for in the drawer.
struct OverviewView: View {

    let displayName: String?
    let avatarURL: URL?

    @Environment(NavigationStore.self) private var navStore
    @State private var viewModel = OverviewViewModel()

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()

            if viewModel.isLoading {
                XomifyLoaderPulse(size: 52)
            } else {
                content
            }
        }
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomSpacing.xl) {
                header

                if !viewModel.recentlyPlayed.isEmpty {
                    trackRow(
                        title: "Jump back in",
                        tracks: viewModel.recentlyPlayed.map(\.track),
                        destination: .recentlyPlayed
                    )
                } else if viewModel.recentlyPlayedFailed {
                    sectionUnavailable("Recently played")
                }

                if !viewModel.topTracks.isEmpty {
                    trackRow(
                        title: "Your top tracks",
                        subtitle: "Last 4 weeks",
                        tracks: viewModel.topTracks,
                        destination: .musicTaste
                    )
                }

                if !viewModel.topArtists.isEmpty {
                    artistRow
                } else if viewModel.topItemsFailed {
                    sectionUnavailable("Your top items")
                }

                quickLinks

                if viewModel.isEmpty && !viewModel.recentlyPlayedFailed && !viewModel.topItemsFailed {
                    emptyState
                }
            }
            .padding(.vertical, XomSpacing.md)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: XomSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.greeting)
                    .font(.xomifyCaption)
                    .foregroundStyle(.white.opacity(0.6))
                Text(displayName ?? "Welcome")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XomSpacing.md)
    }

    // MARK: - Rows

    private func trackRow(
        title: String,
        subtitle: String? = nil,
        tracks: [SpotifyTrack],
        destination: SidebarDestination
    ) -> some View {
        VStack(alignment: .leading, spacing: XomSpacing.sm) {
            sectionHeader(title, subtitle: subtitle, destination: destination)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XomSpacing.sm) {
                    ForEach(tracks, id: \.id) { track in
                        OverviewTrackTile(track: track)
                    }
                }
                .padding(.horizontal, XomSpacing.md)
            }
        }
    }

    private var artistRow: some View {
        VStack(alignment: .leading, spacing: XomSpacing.sm) {
            sectionHeader("Your top artists", subtitle: "Last 4 weeks", destination: .musicTaste)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XomSpacing.sm) {
                    ForEach(viewModel.topArtists, id: \.name) { artist in
                        VStack(spacing: XomSpacing.xs) {
                            AsyncImage(url: artist.imageUrl) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.xomifyCard
                            }
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())

                            Text(artist.name)
                                .font(.xomifyCaption)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .frame(width: 88)
                        }
                    }
                }
                .padding(.horizontal, XomSpacing.md)
            }
        }
    }

    private func sectionHeader(
        _ title: String,
        subtitle: String? = nil,
        destination: SidebarDestination
    ) -> some View {
        Button {
            navStore.select(destination)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: XomSpacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.xomifyCaption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, XomSpacing.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick links

    private struct QuickLink: Identifiable {
        let destination: SidebarDestination
        let label: String
        let systemImage: String
        var id: SidebarDestination { destination }
    }

    /// The six the web dashboard promotes. Everything else stays in the drawer —
    /// a grid of fifteen would repeat the problem the drawer grouping fixed.
    private let links: [QuickLink] = [
        .init(destination: .wrapped,      label: "Wrapped",       systemImage: "chart.bar.fill"),
        .init(destination: .releaseRadar, label: "Release Radar", systemImage: "antenna.radiowaves.left.and.right"),
        .init(destination: .shares,         label: "Shares",        systemImage: "square.and.arrow.up"),
        .init(destination: .favorites,    label: "My Favorites",  systemImage: "bookmark.fill"),
        .init(destination: .builder,      label: "Playlist Builder", systemImage: "music.note.list"),
        .init(destination: .moodPicks,    label: "Mood Picks",    systemImage: "face.smiling"),
    ]

    private var quickLinks: some View {
        VStack(alignment: .leading, spacing: XomSpacing.sm) {
            Text("Explore")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, XomSpacing.md)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: XomSpacing.sm),
                          GridItem(.flexible(), spacing: XomSpacing.sm)],
                spacing: XomSpacing.sm
            ) {
                ForEach(links) { link in
                    Button {
                        navStore.select(link.destination)
                    } label: {
                        HStack(spacing: XomSpacing.sm) {
                            Image(systemName: link.systemImage)
                                .font(.body)
                                .foregroundStyle(Color.xomifyGreen)
                                .frame(width: 24)
                            Text(link.label)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(XomSpacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: XomRadius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, XomSpacing.md)
        }
    }

    // MARK: - States

    /// One section failed, the rest did not. Say which, rather than showing an
    /// empty row that reads as "you have not listened to anything".
    private func sectionUnavailable(_ name: String) -> some View {
        Label("\(name) couldn't load right now.", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(XomSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: XomRadius.sm))
            .padding(.horizontal, XomSpacing.md)
    }

    private var emptyState: some View {
        VStack(spacing: XomSpacing.sm) {
            Image(systemName: "music.note")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.35))
            Text("Nothing to show yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Play something on Spotify and it will turn up here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XomSpacing.xl)
    }
}

// MARK: - Track tile

private struct OverviewTrackTile: View {
    let track: SpotifyTrack

    var body: some View {
        VStack(alignment: .leading, spacing: XomSpacing.xs) {
            AsyncImage(url: track.imageUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.xomifyCard
            }
            .frame(width: 132, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: XomRadius.md))

            Text(track.name)
                .font(.xomifyCaption)
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(track.artists.first?.name ?? "")
                .font(.xomifyCaption)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(width: 132)
        .trackContextMenu(track: track)
    }
}
