import SwiftUI

/// Public wrapper — owns its own `NavigationStack` for standalone presentation.
/// When composed inside another `NavigationStack` (e.g. the drawer's Stats screen),
/// use ``TopItemsContent`` directly to avoid nested stacks.
struct TopItemsView: View {
    var body: some View {
        NavigationStack {
            TopItemsContent()
        }
    }
}

/// Bare body — no wrapping `NavigationStack`. Safe to embed anywhere.
struct TopItemsContent: View {
    @State private var viewModel = TopItemsViewModel()
    @State private var selectedCategory = 0 // 0: Tracks, 1: Artists, 2: Genres
    @State private var selectedTerm: TimeRange = .shortTerm
    @State private var showingSaveToPlaylistAlert = false
    @State private var isSavingPlaylist = false
    @State private var playlistSaveMessage: String?
    @State private var savedPlaylistUrl: URL?

    @Bindable private var playlistBuilder = PlaylistBuilderManager.shared

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                BrandGradientHeader(
                    "Music Taste",
                    subtitle: "Your top tracks, artists, and genres",
                    systemImage: "waveform"
                )

                // Category selector
                categorySelector

                // Term selector
                termSelector

                // Content
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if viewModel.isLoading {
                            ProgressView()
                                .padding(.top, 40)
                        } else if let error = viewModel.errorMessage {
                            errorState(error)
                        } else {
                            // Soft retry hint when the backend reported a
                            // partial Spotify failure for the selected term.
                            // Data for other terms is still rendered.
                            if viewModel.didFail(term: selectedTerm) {
                                partialFailureHint
                            }

                            switch selectedCategory {
                            case 0:
                                tracksContent
                            case 1:
                                artistsContent
                            case 2:
                                genresContent
                            default:
                                EmptyView()
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 100) // Space for floating button
                }
            }

            // Floating playlist builder button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    PlaylistBuilderFloatingButton()
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadData()
        }
        .refreshable {
            await viewModel.loadData()
        }
        .sheet(isPresented: $playlistBuilder.isShowing) {
            PlaylistBuilderView()
        }
        .alert("Playlist Created!", isPresented: .init(
            get: { playlistSaveMessage != nil },
            set: { if !$0 { playlistSaveMessage = nil; savedPlaylistUrl = nil } }
        )) {
            if let url = savedPlaylistUrl {
                Button("Open in Spotify") {
                    UIApplication.shared.open(url)
                    playlistSaveMessage = nil
                    savedPlaylistUrl = nil
                }
            }
            Button("OK", role: .cancel) {
                playlistSaveMessage = nil
                savedPlaylistUrl = nil
            }
        } message: {
            Text(playlistSaveMessage ?? "")
        }
    }

    private var categorySelector: some View {
        HStack(spacing: 8) {
            categoryButton(title: "Tracks", icon: "music.note", index: 0)
            categoryButton(title: "Artists", icon: "person.2.fill", index: 1)
            categoryButton(title: "Genres", icon: "guitars.fill", index: 2)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.xomifyCard)
    }

    private func categoryButton(title: String, icon: String, index: Int) -> some View {
        Button {
            withAnimation { selectedCategory = index }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedCategory == index ? Color.xomifyPurple.opacity(0.3) : Color.clear)
            .foregroundStyle(selectedCategory == index ? Color.xomifyPurple : Color.gray)
            .cornerRadius(10)
        }
    }

    private var termSelector: some View {
        HStack(spacing: 8) {
            ForEach(TimeRange.allCases, id: \.self) { term in
                Button {
                    withAnimation { selectedTerm = term }
                } label: {
                    Text(term.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedTerm == term ? Color.xomifyGreen : Color.white.opacity(0.05))
                        .foregroundStyle(selectedTerm == term ? Color.black : Color.gray)
                        .cornerRadius(20)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Tracks Content

    private var tracksContent: some View {
        let tracks = getTracks(for: selectedTerm)
        return VStack(spacing: 12) {
            // Save to Playlist button
            if !tracks.isEmpty {
                saveToPlaylistButton(tracks: tracks, term: selectedTerm)
            }

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                trackRow(track, rank: index + 1)
            }
        }
    }

    private func saveToPlaylistButton(tracks: [SpotifyTrack], term: TimeRange) -> some View {
        HStack(spacing: 12) {
            // Add all to builder
            Button {
                playlistBuilder.addTracks(tracks)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("Add to Builder")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.xomifyPurple.opacity(0.2))
                .foregroundStyle(Color.xomifyPurple)
                .cornerRadius(20)
            }

            // Save directly to Spotify playlist
            Button {
                Task {
                    await saveTracksToPlaylist(tracks: tracks, term: term)
                }
            } label: {
                HStack(spacing: 6) {
                    if isSavingPlaylist {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text("Save as Playlist")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.xomifyGreen)
                .foregroundStyle(Color.black)
                .cornerRadius(20)
            }
            .disabled(isSavingPlaylist)

            Spacer()
        }
        .padding(.bottom, 8)
    }

    private func saveTracksToPlaylist(tracks: [SpotifyTrack], term: TimeRange) async {
        isSavingPlaylist = true

        let spotifyService = SpotifyService.shared
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"
        let dateString = dateFormatter.string(from: Date())

        let playlistName = "Top Songs - \(term.displayName) (\(dateString))"
        let description = "Your top \(tracks.count) songs - \(term.displayName.lowercased()) • Created with Xomify"

        do {
            // Get user ID
            let user = try await spotifyService.getCurrentUser()
            guard let userId = user.id else {
                throw NSError(domain: "TopItems", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get user ID"])
            }

            // Create playlist
            let playlist = try await spotifyService.createPlaylist(
                userId: userId,
                name: playlistName,
                description: description,
                isPublic: false
            )

            // Add tracks
            let trackUris = tracks.compactMap { $0.uri }
            if !trackUris.isEmpty {
                try await spotifyService.addTracksToPlaylist(playlistId: playlist.id, trackUris: trackUris)
            }

            // Upload cover image
            let coverImage = XomifyConstants.xomifyCoverBase64
            if !coverImage.isEmpty && coverImage != "PASTE_YOUR_BASE64_IMAGE_HERE" {
                do {
                    try await spotifyService.uploadPlaylistCover(playlistId: playlist.id, imageBase64: coverImage)
                } catch {
                    print("⚠️ TopItems: Cover upload failed - \(error)")
                }
            }

            playlistSaveMessage = "Created '\(playlistName)' with \(tracks.count) tracks!"
            if let urlString = playlist.externalUrls?["spotify"] {
                savedPlaylistUrl = URL(string: urlString)
            }

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        } catch {
            playlistSaveMessage = "Failed: \(error.localizedDescription)"

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }

        isSavingPlaylist = false
    }

    private func getTracks(for term: TimeRange) -> [SpotifyTrack] {
        switch term {
        case .shortTerm: return viewModel.shortTermTracks
        case .mediumTerm: return viewModel.mediumTermTracks
        case .longTerm: return viewModel.longTermTracks
        }
    }

    private func trackRow(_ track: SpotifyTrack, rank: Int) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(rank)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(Color.xomifyGreen)
                .frame(width: 30)

            // Album art - tap to go to album
            if let album = track.album {
                NavigationLink(destination: AlbumView(albumId: album.id)) {
                    AsyncImage(url: track.imageUrl) { image in
                        image.resizable()
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 50, height: 50)
                    .cornerRadius(6)
                }
            } else {
                AsyncImage(url: track.imageUrl) { image in
                    image.resizable()
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .cornerRadius(6)
            }

            // Track info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // Artist names - tap to go to first artist
                if let firstArtist = track.artists.first, let artistId = firstArtist.id {
                    NavigationLink(destination: ArtistView(artistId: artistId)) {
                        Text(track.artistNames)
                            .font(.caption)
                            .foregroundStyle(Color.xomifyPurple)
                            .lineLimit(1)
                    }
                } else {
                    Text(track.artistNames)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }

            Spacer()

            TrackActionsMenu(track: track)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Artists Content

    private var artistsContent: some View {
        let artists = getArtists(for: selectedTerm)
        return ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
            artistRow(artist, rank: index + 1)
        }
    }

    private func getArtists(for term: TimeRange) -> [SpotifyArtist] {
        switch term {
        case .shortTerm: return viewModel.shortTermArtists
        case .mediumTerm: return viewModel.mediumTermArtists
        case .longTerm: return viewModel.longTermArtists
        }
    }

    private func artistRow(_ artist: SpotifyArtist, rank: Int) -> some View {
        NavigationLink(destination: ArtistView(artistId: artist.id ?? "")) {
            HStack(spacing: 12) {
                // Rank
                Text("\(rank)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.xomifyPurple)
                    .frame(width: 30)

                // Artist image
                AsyncImage(url: artist.imageUrl) { image in
                    image.resizable()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())

                // Artist info
                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let genres = artist.genres, !genres.isEmpty {
                        Text(genres.prefix(2).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Popularity
                if let popularity = artist.popularity {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                        Text("\(popularity)")
                            .font(.caption)
                    }
                    .foregroundStyle(.yellow.opacity(0.8))
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(10)
        }
    }

    // MARK: - Genres Content

    private var genresContent: some View {
        let genres = getGenres(for: selectedTerm)
        return ForEach(Array(genres.enumerated()), id: \.element.name) { index, genre in
            genreRow(genre, rank: index + 1, maxCount: genres.first?.count ?? 1)
        }
    }

    private func getGenres(for term: TimeRange) -> [(name: String, count: Int)] {
        switch term {
        case .shortTerm: return viewModel.shortTermGenres
        case .mediumTerm: return viewModel.mediumTermGenres
        case .longTerm: return viewModel.longTermGenres
        }
    }

    private func genreRow(_ genre: (name: String, count: Int), rank: Int, maxCount: Int) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(rank)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.blue)
                .frame(width: 30)

            // Genre info
            VStack(alignment: .leading, spacing: 8) {
                Text(genre.name.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                            .cornerRadius(3)

                        Rectangle()
                            .fill(LinearGradient(colors: [.xomifyPurple, .xomifyGreen], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(genre.count) / CGFloat(maxCount), height: 6)
                            .cornerRadius(3)
                    }
                }
                .frame(height: 6)
            }

            Spacer()

            // Count
            Text("\(genre.count)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.xomifyGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.xomifyGreen.opacity(0.15))
                .cornerRadius(12)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
    }

    // MARK: - Error / Partial-failure States

    /// Hard error — the whole `/user/top-items` request failed. Shows a
    /// retry CTA that re-runs `loadData()`.
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.orange.opacity(0.7))

            Text("Couldn't Load Top Items")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.loadData() }
            } label: {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.xomifyPurple)
                    .foregroundStyle(.white)
                    .cornerRadius(20)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
    }

    /// Soft retry hint — backend reported a per-range partial failure for
    /// the current term. Data for other terms is still rendered; tapping
    /// "Refresh" reissues the request which will re-attempt failing
    /// ranges (the partial response was not cached server-side).
    private var partialFailureHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Partial data for \(selectedTerm.displayName)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text("Spotify hiccupped. Pull to refresh or tap retry.")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Spacer()

            Button {
                Task { await viewModel.loadData() }
            } label: {
                Text("Retry")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .cornerRadius(12)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: XomRadius.lg)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(10)
        .padding(.bottom, 4)
    }

    // MARK: - Playback

    private func playTrack(_ track: SpotifyTrack) {
        // Open in Spotify app via URI (best experience)
        if let uri = track.uri, let url = URL(string: uri) {
            UIApplication.shared.open(url)
        } else if let urlString = track.externalUrls?["spotify"], let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    TopItemsView()
}
