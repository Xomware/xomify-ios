import SwiftUI

/// Public wrapper — owns its own `NavigationStack` for callers that push this
/// as a top-level screen. The drawer-resident path uses ``FollowingContent``
/// directly so we don't nest navigation stacks.
struct FollowingView: View {
    var body: some View {
        NavigationStack {
            FollowingContent()
        }
    }
}

/// Bare body — no wrapping `NavigationStack`. Safe to push inside any existing
/// `NavigationStack` (e.g. the drawer's).
struct FollowingContent: View {
    @State private var artists: [SpotifyArtist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    private let spotifyService = SpotifyService.shared

    var filteredArtists: [SpotifyArtist] {
        if searchText.isEmpty {
            return artists
        }
        return artists.filter { artist in
            artist.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            if !artists.isEmpty {
                searchBar
            }

            // Content
            ScrollView {
                if isLoading {
                    ProgressView()
                        .padding(.top, 60)
                } else if let error = errorMessage {
                    errorState(error)
                } else if artists.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredArtists) { artist in
                            artistRow(artist)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Following")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Following")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(artists.count) artists")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
        }
        .task {
            await loadArtists()
        }
        .refreshable {
            await loadArtists()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)

            TextField("Search artists...", text: $searchText)
                .foregroundStyle(.white)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(XomRadius.xl)
        .padding()
    }

    // MARK: - Artist Row

    private func artistRow(_ artist: SpotifyArtist) -> some View {
        NavigationLink(destination: ArtistView(artistId: artist.id ?? "")) {
            HStack(spacing: 14) {
                // Artist image
                AsyncImage(url: artist.imageUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

                // Artist info
                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let genres = artist.genres, !genres.isEmpty {
                        Text(genres.prefix(2).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }

                    if let followers = artist.followers?.total {
                        Text("\(formatNumber(followers)) followers")
                            .font(.caption2)
                            .foregroundStyle(Color.xomifyGreen)
                    }
                }

                Spacer()

                // Popularity indicator
                if let popularity = artist.popularity {
                    VStack(spacing: 2) {
                        Text("\(popularity)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.xomifyPurple)
                        Text("POP")
                            .font(.system(size: 8))
                            .foregroundStyle(.gray)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .padding(12)
            .background(Color.xomifyCard)
            .cornerRadius(XomRadius.xl)
        }
    }

    // MARK: - States

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.orange.opacity(0.7))

            Text("Error Loading Artists")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)

            Button {
                Task { await loadArtists() }
            } label: {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.xomifyPurple)
                    .foregroundStyle(.white)
                    .cornerRadius(XomRadius.xl)
            }
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 50))
                .foregroundStyle(.gray.opacity(0.5))

            Text("Not Following Anyone")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Follow artists on Spotify to see them here")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }

    // MARK: - Data Loading

    private func loadArtists() async {
        isLoading = true
        errorMessage = nil

        do {
            var loaded = try await spotifyService.getFollowedArtists()
            // Sort by name
            loaded.sort { $0.name.lowercased() < $1.name.lowercased() }
            artists = loaded

            print("✅ FollowingView: Loaded \(artists.count) followed artists")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ FollowingView: Error - \(error)")
        }

        isLoading = false
    }

    // MARK: - Helpers

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
}

#Preview {
    FollowingView()
}
