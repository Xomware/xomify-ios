import SwiftUI

/// Self-only tab on `ProfileView` that lists the signed-in user's full
/// Spotify saved-tracks library (liked songs) in reverse date-added order,
/// paginated at 50 tracks per page. Shows a total count chip in the header.
///
/// Spotify's `/me/tracks` endpoint is scoped to the authenticated user, so
/// this tab is only shown on `.me` profiles.
struct ProfileLikesTab: View {

    var viewModel: ProfileLikesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            if viewModel.isLoading && viewModel.tracks.isEmpty {
                loadingState
            } else if let error = viewModel.errorMessage, viewModel.tracks.isEmpty {
                errorState(error)
                    .padding(.horizontal, 16)
            } else if viewModel.tracks.isEmpty {
                emptyState
                    .padding(.horizontal, 16)
            } else {
                trackList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.xomifyGreen)
                .accessibilityHidden(true)
            Text("Liked songs")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            if let total = viewModel.total {
                Text(formattedCount(total))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .accessibilityLabel("\(total) liked songs")
            }
        }
    }

    // MARK: - Track list

    private var trackList: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(viewModel.tracks.enumerated()), id: \.offset) { index, track in
                trackRow(index: index, track: track)
                    .padding(.horizontal, 16)
                    .onAppear {
                        if index >= viewModel.tracks.count - 5 {
                            Task { await viewModel.loadMore() }
                        }
                    }
            }

            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    XomifyLoaderSpin()
                    Spacer()
                }
                .frame(minHeight: 60)
                .accessibilityLabel("Loading more tracks")
            } else if !viewModel.hasMore && !viewModel.tracks.isEmpty {
                Text("All \(viewModel.tracks.count) songs loaded")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Row

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index + 1). \(track.name) by \(artistNames(track))")
    }

    private func indexLabel(_ index: Int) -> some View {
        Text("\(index + 1)")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: 18, alignment: .trailing)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func albumArt(_ track: SpotifyTrack) -> some View {
        if let url = track.album?.images?.first?.url, let imageUrl = URL(string: url) {
            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    albumArtPlaceholder
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 6))
        } else {
            albumArtPlaceholder
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 6))
        }
    }

    private var albumArtPlaceholder: some View {
        Color.xomifyPurple.opacity(0.25)
            .overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(Color.xomifyPurple)
            )
    }

    private func artistNames(_ track: SpotifyTrack) -> String {
        track.artists.compactMap { $0.name }.joined(separator: ", ")
    }

    // MARK: - States

    private var loadingState: some View {
        HStack {
            Spacer()
            XomifyLoaderSpin()
            Spacer()
        }
        .frame(minHeight: 120)
        .accessibilityLabel("Loading liked songs")
    }

    private var emptyState: some View {
        Text("You haven't liked any songs yet.")
            .font(.caption)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.xomifyCard.opacity(0.5))
            .clipShape(.rect(cornerRadius: 10))
    }

    private func errorState(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
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

    // MARK: - Helpers

    private func formattedCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
