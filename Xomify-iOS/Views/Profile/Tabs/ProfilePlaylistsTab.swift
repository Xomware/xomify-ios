import SwiftUI

/// Profile tab: signed-in user's Spotify playlists. Minimal v1 — search +
/// list. Taps open Spotify externally since we don't ship a native
/// playlist detail view yet.
struct ProfilePlaylistsTab: View {

    @Bindable var viewModel: ProfilePlaylistsViewModel

    var body: some View {
        VStack(spacing: 12) {
            searchField

            if viewModel.isLoading && viewModel.playlists.isEmpty {
                XomifyLoaderPaint(size: 40)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let error = viewModel.errorMessage, viewModel.playlists.isEmpty {
                errorState(error)
            } else if viewModel.filteredPlaylists.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .padding(.horizontal)
        .task {
            if viewModel.playlists.isEmpty {
                await viewModel.load()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)
            TextField(
                "Search playlists",
                text: $viewModel.searchQuery
            )
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: XomRadius.lg, style: .continuous))
    }

    private var list: some View {
        LazyVStack(spacing: 10) {
            ForEach(viewModel.filteredPlaylists) { playlist in
                Button {
                    openExternally(playlist)
                } label: {
                    row(playlist)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ playlist: SpotifyPlaylist) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: playlist.imageUrl) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(playlist.tracks?.total ?? 0) tracks")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.gray)
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: XomRadius.lg, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.name), \(playlist.tracks?.total ?? 0) tracks")
        .accessibilityHint("Opens in Spotify")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.system(size: 32))
                .foregroundStyle(.gray)
            Text(viewModel.searchQuery.isEmpty ? "No playlists yet" : "No playlists match \"\(viewModel.searchQuery)\"")
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("Could not load playlists")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.bordered)
            .tint(.xomifyGreen)
        }
        .padding(24)
    }

    private func openExternally(_ playlist: SpotifyPlaylist) {
        if let urlString = playlist.externalUrls?["spotify"], let url = URL(string: urlString) {
            UIApplication.shared.open(url)
            return
        }
        if let uri = playlist.uri, let url = URL(string: uri) {
            UIApplication.shared.open(url)
        }
    }
}
