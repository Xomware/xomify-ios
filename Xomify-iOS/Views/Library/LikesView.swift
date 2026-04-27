import SwiftUI

/// Top-level destination: liked-songs library.
///
/// - Self path (default, `targetEmail == nil`): loads from Spotify `/me/tracks`
///   with full `TrackActionsMenu` support.
/// - Friend path (`targetEmail` set): loads from backend `/likes/by-user`,
///   read-only display (no queue/rate actions — not the viewer's library).
///
/// Both paths share this single view; only the data source differs.
struct LikesView: View {

    /// `nil` → self path (Spotify direct). Non-nil → friend path (backend).
    let targetEmail: String?

    @State private var viewModel: LikesViewModel

    init(targetEmail: String? = nil) {
        self.targetEmail = targetEmail
        // VM source is resolved at init. When targetEmail is set we need the
        // caller email too — it's resolved by LikesViewModel from Spotify on
        // the first load. We pass a placeholder here; the VM reads the real
        // caller email lazily in fetchBackendPage via SpotifyService.
        // For the backend path we seed callerEmail with "" and let the VM
        // resolve it on first fetch — the backend's JWT token provides the
        // real identity anyway, but we still need a non-empty string for the
        // query param. UserProfileViewModel has already resolved callerEmail
        // at this point, but LikesView is instantiated independently from the
        // shell. Resolution happens inside LikesViewModel via SpotifyService.
        if let email = targetEmail {
            _viewModel = State(initialValue: LikesViewModel(source: .backend(callerEmail: "", targetEmail: email)))
        } else {
            _viewModel = State(initialValue: LikesViewModel(source: .spotifyDirect))
        }
    }

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                if viewModel.isLoading && viewModel.items.isEmpty {
                    loadingState
                } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                    errorState(error)
                        .padding(.horizontal, 16)
                } else if viewModel.items.isEmpty {
                    emptyState
                        .padding(.horizontal, 16)
                } else {
                    trackList
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(targetEmail == nil ? "Likes" : "Liked Songs")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchQuery, prompt: "Search liked songs")
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
        ScrollView {
            LazyVStack(spacing: 8) {
                let displayed = viewModel.filteredItems
                ForEach(Array(displayed.enumerated()), id: \.offset) { index, item in
                    trackRow(index: index, item: item)
                        .padding(.horizontal, 16)
                        .onAppear {
                            if index >= viewModel.items.count - 5 {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }

                // Search hint — show when filtering and more pages exist.
                if !viewModel.searchQuery.isEmpty && viewModel.hasMore {
                    searchHintFooter
                        .padding(.horizontal, 16)
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        XomifyLoaderSpin()
                        Spacer()
                    }
                    .frame(minHeight: 60)
                    .accessibilityLabel("Loading more tracks")
                } else if !viewModel.hasMore && !viewModel.items.isEmpty && viewModel.searchQuery.isEmpty {
                    Text("All \(viewModel.items.count) songs loaded")
                        .font(.caption2)
                        .foregroundStyle(.gray.opacity(0.6))
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
                .foregroundStyle(.gray)
                .accessibilityHidden(true)
            if let total = viewModel.total {
                Text("Showing \(viewModel.items.count) of \(formattedCount(total)) — load more to search older")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            } else {
                Text("Load more to search older songs")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.xomifyCard.opacity(0.5))
        .clipShape(.rect(cornerRadius: 8))
    }

    // MARK: - Row

    private func trackRow(index: Int, item: LikesTrackDisplayItem) -> some View {
        // Look up the matching SpotifyTrack for the actions menu (self path only).
        let spotifyTrack: SpotifyTrack? = {
            guard targetEmail == nil else { return nil }
            let idx = viewModel.items.firstIndex(where: { $0.id == item.id })
            guard let idx, idx < viewModel.spotifyTracks.count else { return nil }
            return viewModel.spotifyTracks[idx]
        }()

        return HStack(spacing: 12) {
            indexLabel(index)
            albumArt(item.albumArtURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.artistNames)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let track = spotifyTrack {
                TrackActionsMenu(track: track)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index + 1). \(item.name) by \(item.artistNames)")
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
    private func albumArt(_ url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
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
        Text(targetEmail == nil ? "You haven't liked any songs yet." : "No liked songs to show.")
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
