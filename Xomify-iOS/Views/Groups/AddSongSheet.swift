import SwiftUI

/// Sheet presented from `GroupDetailView` to add a track to the group.
/// Primary path: search Spotify and tap a result to add. Secondary (opt-in)
/// fallback: paste a Spotify URL — kept behind a disclosure so it doesn't
/// clutter the primary UX.
struct AddSongSheet: View {

    @Bindable var viewModel: GroupDetailViewModel
    let onDismiss: () -> Void

    @State private var showByUrl = false
    @State private var searchDebounceTask: Task<Void, Never>?

    /// Track IDs already on the group, to dim "already added" results.
    private var existingTrackIds: Set<String> {
        Set(viewModel.tracks.compactMap { $0.trackId })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()

                VStack(spacing: 12) {
                    searchField
                    resultsArea
                    urlFallback
                }
                .padding(.top, 8)
            }
            .navigationTitle("Add Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .tint(Color.xomifyGreen)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)
            TextField("Search tracks on Spotify", text: $viewModel.songSearchQuery)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(.white)
                .onChange(of: viewModel.songSearchQuery) { _, _ in
                    scheduleSearch()
                }

            if !viewModel.songSearchQuery.isEmpty {
                Button {
                    viewModel.songSearchQuery = ""
                    viewModel.songSearchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 10))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var resultsArea: some View {
        if viewModel.isSearchingSongs && viewModel.songSearchResults.isEmpty {
            VStack { XomifyLoaderPulse() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.songSearchError {
            errorState(error)
        } else if viewModel.songSearchQuery.isEmpty {
            emptyPrompt
        } else if viewModel.songSearchResults.isEmpty {
            emptyResults
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.songSearchResults) { track in
                        resultRow(track)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func resultRow(_ track: SpotifyTrack) -> some View {
        let alreadyAdded = existingTrackIds.contains(track.id)
        let isAdding = viewModel.addingTrackIds.contains(track.id)

        return HStack(spacing: 12) {
            AsyncImage(url: track.imageUrl) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
            .frame(width: 48, height: 48)
            .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artistNames)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if alreadyAdded {
                Label("Added", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.xomifyGreen)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Already in group")
            } else {
                Button {
                    Task { await viewModel.addSong(track) }
                } label: {
                    if isAdding {
                        ProgressView().tint(.white)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.xomifyGreen)
                            .frame(width: 44, height: 44)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isAdding)
                .accessibilityLabel("Add \(track.name)")
            }
        }
        .padding(10)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 10))
        .opacity(alreadyAdded ? 0.6 : 1)
    }

    // MARK: - URL fallback

    @ViewBuilder
    private var urlFallback: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation { showByUrl.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showByUrl ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Paste a Spotify URL instead")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.gray)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            if showByUrl {
                HStack(spacing: 8) {
                    TextField("https://open.spotify.com/track/...", text: $viewModel.addSongUrl)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .clipShape(.rect(cornerRadius: 10))
                        .foregroundStyle(.white)

                    Button {
                        Task {
                            await viewModel.addSongByUrl()
                            if viewModel.errorMessage == nil {
                                onDismiss()
                            }
                        }
                    } label: {
                        if viewModel.isAddingSong {
                            ProgressView().tint(.white)
                                .frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.xomifyGreen)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .disabled(viewModel.isAddingSong || viewModel.addSongUrl.isEmpty)
                    .accessibilityLabel("Add track from URL")
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    // MARK: - Empty / error states

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.gray.opacity(0.6))
            Text("Search Spotify")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Type a track or artist to start.")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 36))
                .foregroundStyle(.gray.opacity(0.6))
            Text("No matches")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Try a different search term.")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange.opacity(0.8))
            Text("Search failed")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Debounce

    /// Debounce typed input so we don't hammer Spotify on every keystroke.
    private func scheduleSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await viewModel.searchSongs()
        }
    }
}
