import SwiftUI

struct ArtistView: View {
    let artistId: String

    @State private var viewModel = ArtistViewModel()
    @State private var selectedSection = 0 // 0: Top Tracks, 1: Albums, 2: Singles
    @State private var quickInfoTrack: SpotifyTrack?

    @Bindable private var playlistBuilder = PlaylistBuilderManager.shared

    // Mirrored access keeps the view body terse and unchanged below.
    private var artist: SpotifyArtist? { viewModel.artist }
    private var topTracks: [SpotifyTrack] { viewModel.topTracks }
    private var albums: [SpotifyAlbum] { viewModel.albums }
    private var singles: [SpotifyAlbum] { viewModel.singles }
    private var isFollowing: Bool { viewModel.isFollowing }
    private var isLoading: Bool { viewModel.isLoading }
    private var isTogglingFollow: Bool { viewModel.isTogglingFollow }
    private var errorMessage: String? { viewModel.errorMessage }
    
    var body: some View {
        ZStack {
            ScrollView {
                if isLoading {
                    XomifyLoaderPaint(size: 40)
                        .padding(.top, 100)
                } else if let error = errorMessage {
                    errorState(error)
                } else if let artist = artist {
                    VStack(spacing: 0) {
                        // Artist Header
                        artistHeader(artist)
                        
                        // Stats Bar
                        statsBar(artist)
                        
                        // Action Buttons
                        actionButtons(artist)
                        
                        // Section Picker
                        sectionPicker
                        
                        // Content
                        sectionContent
                    }
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
        .navigationTitle(artist?.name ?? "Artist")
        .navigationBarTitleDisplayMode(.inline)
        // Pushed from tabs that hide the system nav bar (TopItems, Wrapped,
        // ReleaseRadar). Re-assert visibility so the back button renders.
        .toolbar(.visible, for: .navigationBar)
        .task {
            await viewModel.load(artistId: artistId)
        }
        .sheet(isPresented: $playlistBuilder.isShowing) {
            PlaylistBuilderView()
        }
        .trackQuickInfoSheet(track: $quickInfoTrack)
    }
    
    // MARK: - Artist Header
    
    private func artistHeader(_ artist: SpotifyArtist) -> some View {
        VStack(spacing: 16) {
            // Artist Image
            AsyncImage(url: artist.imageUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.white.opacity(0.08))
            }
            .frame(width: 180, height: 180)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(colors: [.xomifyPurple, .xomifyGreen], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 4
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
            
            // Artist Name
            Text(artist.name)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Genres
            if let genres = artist.genres, !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres.prefix(5), id: \.self) { genre in
                            Text(genre.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.1))
                                .foregroundColor(.white.opacity(0.5))
                                .cornerRadius(XomRadius.xxl)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Stats Bar
    
    private func statsBar(_ artist: SpotifyArtist) -> some View {
        HStack(spacing: 0) {
            statItem(
                value: formatNumber(artist.followers?.total ?? 0),
                label: "Followers"
            )
            
            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.05))
            
            statItem(
                value: "\(artist.popularity ?? 0)",
                label: "Popularity"
            )
            
            Divider()
                .frame(height: 30)
                .background(Color.white.opacity(0.05))
            
            statItem(
                value: "\(albums.count + singles.count)",
                label: "Releases"
            )
        }
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.03))
        .cornerRadius(XomRadius.xl)
        .padding(.horizontal)
        .padding(.top, 16)
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.xomifyGreen)
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Action Buttons
    
    private func actionButtons(_ artist: SpotifyArtist) -> some View {
        HStack(spacing: 16) {
            // Follow/Unfollow Button
            Button {
                Task { await viewModel.toggleFollow(artistId: artistId) }
            } label: {
                HStack(spacing: 8) {
                    if isTogglingFollow {
                        ProgressView()
                            .tint(isFollowing ? .xomifyGreen : .white)
                    } else {
                        Image(systemName: isFollowing ? "checkmark" : "plus")
                        Text(isFollowing ? "Following" : "Follow")
                    }
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isFollowing ? Color.xomifyGreen.opacity(0.2) : Color.xomifyGreen)
                .foregroundColor(isFollowing ? .xomifyGreen : .black)
                .cornerRadius(XomRadius.pill)
                .overlay(
                    RoundedRectangle(cornerRadius: XomRadius.pill)
                        .stroke(isFollowing ? Color.xomifyGreen : Color.clear, lineWidth: 1)
                )
            }
            .disabled(isTogglingFollow)
            
            // Open in Spotify
            if let url = spotifyUrl(for: artist) {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right")
                        Text("Spotify")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(XomRadius.pill)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
    
    // MARK: - Section Picker
    
    private var sectionPicker: some View {
        HStack(spacing: 8) {
            sectionButton(title: "Top Tracks", count: topTracks.count, index: 0)
            sectionButton(title: "Albums", count: albums.count, index: 1)
            sectionButton(title: "Singles", count: singles.count, index: 2)
        }
        .padding(.horizontal)
        .padding(.top, 24)
    }
    
    private func sectionButton(title: String, count: Int, index: Int) -> some View {
        Button {
            withAnimation { selectedSection = index }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(count)")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedSection == index ? Color.xomifyPurple.opacity(0.3) : Color.white.opacity(0.05))
            .foregroundColor(selectedSection == index ? .xomifyPurple : .white.opacity(0.5))
            .cornerRadius(XomRadius.lg)
        }
    }
    
    // MARK: - Section Content
    
    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case 0:
            topTracksSection
        case 1:
            albumsGrid(albums)
        case 2:
            albumsGrid(singles)
        default:
            EmptyView()
        }
    }
    
    // MARK: - Top Tracks Section
    
    private var topTracksSection: some View {
        VStack(spacing: 0) {
            // Add all to builder button
            if !topTracks.isEmpty {
                Button {
                    playlistBuilder.addTracks(topTracks)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                        Text("Add All Top Tracks to Builder")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.xomifyPurple.opacity(0.2))
                    .foregroundColor(.xomifyPurple)
                    .cornerRadius(XomRadius.pill)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            
            ForEach(Array(topTracks.enumerated()), id: \.element.id) { index, track in
                trackRow(track, rank: index + 1)
                
                if index < topTracks.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 70)
                }
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
    }
    
    private func trackRow(_ track: SpotifyTrack, rank: Int) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(rank)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.xomifyGreen)
                .frame(width: 28)
            
            // Album art
            AsyncImage(url: track.imageUrl) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.white.opacity(0.08))
            }
            .frame(width: 48, height: 48)
            .cornerRadius(XomRadius.md)
            
            // Track info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(track.album?.name ?? "")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            
            Spacer()

            TrackActionsMenu(track: track)
        }
        .trackContextMenu(track: track)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            quickInfoTrack = track
        }
        .accessibilityHint("Shows track details")
    }

    // MARK: - Albums Grid
    
    private func albumsGrid(_ items: [SpotifyAlbum]) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 20) {
            ForEach(items) { album in
                NavigationLink(destination: AlbumView(albumId: album.id)) {
                    albumCard(album)
                }
            }
        }
        .padding()
    }
    
    private func albumCard(_ album: SpotifyAlbum) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Album Art
            AsyncImage(url: album.imageUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
            }
            .frame(height: 160)
            .cornerRadius(XomRadius.md)
            
            // Album Info
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    if let year = album.year {
                        Text(year)
                    }
                    if let type = album.albumType {
                        Text("•")
                        Text(type.capitalized)
                    }
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    // MARK: - Error State
    
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange.opacity(0.7))
            
            Text("Error Loading Artist")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            
            Button {
                Task { await viewModel.load(artistId: artistId) }
            } label: {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.xomifyPurple)
                    .foregroundColor(.white)
                    .cornerRadius(XomRadius.xl)
            }
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }
    
    // MARK: - Helpers

    private func spotifyUrl(for artist: SpotifyArtist) -> URL? {
        if let urlString = artist.externalUrls?["spotify"] {
            return URL(string: urlString)
        }
        if let id = artist.id {
            return URL(string: "spotify:artist:\(id)")
        }
        return nil
    }

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
    NavigationStack {
        ArtistView(artistId: "0TnOYISbd1XYRBk9myaseg")
    }
}
