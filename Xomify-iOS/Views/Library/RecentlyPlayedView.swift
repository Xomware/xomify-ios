import SwiftUI

/// Top-level destination: user's recently played Spotify tracks.
/// Loads 50 per page with cursor-based pagination (newest-first, `before=`
/// cursor for older history). Supports client-side search over loaded pages
/// with a hint footer when more history is available.
///
/// Self-only: `/me/player/recently-played` is scoped to the authenticated user.
struct RecentlyPlayedView: View {

    @State private var viewModel = RecentlyPlayedViewModel()

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()

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
        }
        .navigationTitle("Recently Played")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchQuery, prompt: "Search recently played")
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
            Image(systemName: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.xomifyGreen)
                .accessibilityHidden(true)
            Text("Recently played")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
        }
    }

    // MARK: - Track list

    private var trackList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                let displayed = viewModel.filteredTracks
                ForEach(Array(displayed.enumerated()), id: \.offset) { index, history in
                    trackRow(index: index, track: history.track)
                        .padding(.horizontal, 16)
                        .onAppear {
                            if index >= viewModel.tracks.count - 5 {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }

                // Search hint — show when filtering and more history exists.
                if !viewModel.searchQuery.isEmpty && viewModel.hasMore {
                    searchHintFooter
                        .padding(.horizontal, 16)
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        XomifyLoaderPaint(size: 36)
                        Spacer()
                    }
                    .frame(minHeight: 60)
                    .accessibilityLabel("Loading more tracks")
                } else if !viewModel.hasMore && !viewModel.tracks.isEmpty && viewModel.searchQuery.isEmpty {
                    Text("\(viewModel.tracks.count) tracks loaded")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var searchHintFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .accessibilityHidden(true)
            Text("Showing \(viewModel.tracks.count) tracks — load more to search older history")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.xomifyCard.opacity(0.5))
        .clipShape(.rect(cornerRadius: XomRadius.md))
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
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            TrackActionsMenu(track: track)
        }
        .trackContextMenu(track: track)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: XomRadius.lg, style: .continuous))
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
            .clipShape(.rect(cornerRadius: XomRadius.md))
        } else {
            albumArtPlaceholder
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: XomRadius.md))
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
            XomifyLoaderPaint(size: 36)
            Spacer()
        }
        .frame(minHeight: 120)
        .accessibilityLabel("Loading recently played tracks")
    }

    private var emptyState: some View {
        Text("Nothing played recently.")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.xomifyCard.opacity(0.5))
            .clipShape(.rect(cornerRadius: XomRadius.lg))
    }

    private func errorState(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.xomifyCard.opacity(0.6))
        .clipShape(.rect(cornerRadius: XomRadius.lg))
    }
}
