import SwiftUI

/// Self-only tab on `ProfileView` that lists the signed-in user's last-25
/// recently-played tracks. Powers the "what was I just listening to?" quick
/// lookup so tracks can be shared to the feed without bouncing to Spotify.
///
/// Liked songs have moved to the dedicated Likes tab.
/// Each row uses the shared `TrackActionsMenu` for play / queue / share actions.
struct ProfileRecentTab: View {

    @State private var viewModel = ProfileRecentViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section(
                title: "Recently played",
                icon: "clock.arrow.circlepath",
                tracks: viewModel.recentlyPlayed,
                error: viewModel.recentError,
                emptyText: "Nothing played recently."
            )
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        icon: String,
        tracks: [SpotifyTrack],
        error: String?,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.xomifyGreen)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if !tracks.isEmpty {
                    Text("\(tracks.count)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            if let error {
                errorRow(error)
            } else if viewModel.isLoading && tracks.isEmpty {
                loadingRow
            } else if tracks.isEmpty {
                emptyRow(emptyText)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        trackRow(index: index, track: track)
                    }
                }
            }
        }
    }

    private func trackRow(index: Int, track: SpotifyTrack) -> some View {
        HStack(spacing: 12) {
            indexLabel(index)
            albumArt(track)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(artistNames(track))
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            TrackActionsMenu(track: track)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func indexLabel(_ index: Int) -> some View {
        Text("\(index + 1)")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: 18, alignment: .trailing)
    }

    @ViewBuilder
    private func albumArt(_ track: SpotifyTrack) -> some View {
        if let url = track.album?.images?.first?.url, let imageUrl = URL(string: url) {
            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 6))
        } else {
            placeholder
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 6))
        }
    }

    private var placeholder: some View {
        Color.xomifyPurple.opacity(0.25)
            .overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(Color.xomifyPurple)
            )
    }

    private func artistNames(_ track: SpotifyTrack) -> String {
        track.artists.compactMap { $0.name }.joined(separator: ", ")
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            XomifyLoaderSpin()
            Spacer()
        }
        .frame(minHeight: 80)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.xomifyCard.opacity(0.5))
            .clipShape(.rect(cornerRadius: 10))
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.xomifyCard.opacity(0.6))
        .clipShape(.rect(cornerRadius: 10))
    }
}
