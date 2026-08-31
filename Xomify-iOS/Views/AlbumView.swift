import SwiftUI

struct AlbumView: View {
    let albumId: String
    
    @State private var album: SpotifyAlbum?
    @State private var tracks: [SpotifyTrack] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var quickInfoTrack: SpotifyTrack?

    @Bindable private var playlistBuilder = PlaylistBuilderManager.shared
    private let spotifyService = SpotifyService.shared
    
    var body: some View {
        ZStack {
            ScrollView {
                if isLoading {
                    XomifyLoaderPaint(size: 40)
                        .padding(.top, 100)
                } else if let error = errorMessage {
                    errorState(error)
                } else if let album = album {
                    VStack(spacing: 0) {
                        // Album Header
                        albumHeader(album)
                        
                        // Action Buttons
                        actionButtons(album)
                        
                        // Track List
                        trackList
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
        .navigationTitle(album?.name ?? "Album")
        .navigationBarTitleDisplayMode(.inline)
        // Pushed from tabs that hide the system nav bar. Re-assert visibility
        // so the back button renders.
        .toolbar(.visible, for: .navigationBar)
        .task {
            await loadAlbum()
        }
        .sheet(isPresented: $playlistBuilder.isShowing) {
            PlaylistBuilderView()
        }
        .trackQuickInfoSheet(track: $quickInfoTrack)
    }

    // MARK: - Album Header
    
    private func albumHeader(_ album: SpotifyAlbum) -> some View {
        VStack(spacing: 16) {
            // Album Art
            AsyncImage(url: album.imageUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
            }
            .frame(width: 220, height: 220)
            .cornerRadius(XomRadius.xl)
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
            
            // Album Info
            VStack(spacing: 8) {
                Text(album.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(album.artistNames)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                
                HStack(spacing: 8) {
                    if let type = album.albumType {
                        Text(type.capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.xomifyPurple.opacity(0.3))
                            .foregroundColor(.xomifyPurple)
                            .cornerRadius(XomRadius.xl)
                    }
                    
                    if let year = album.year {
                        Text(year)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Text("•")
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("\(album.totalTracks ?? tracks.count) tracks")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.top, 20)
        .padding(.horizontal)
    }
    
    // MARK: - Action Buttons
    
    private func actionButtons(_ album: SpotifyAlbum) -> some View {
        VStack(spacing: 12) {
            // Main action row
            HStack(spacing: 16) {
                // Play on Spotify
                if let url = spotifyUrl(for: album) {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 29/255, green: 185/255, blue: 84/255))
                        .foregroundColor(.white)
                        .cornerRadius(XomRadius.pill)
                    }
                }
                
                // Shuffle on Spotify
                if let url = spotifyShuffleUrl(for: album) {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(XomRadius.pill)
                    }
                }
            }
            
            // Add all to playlist builder
            if !tracks.isEmpty {
                Button {
                    playlistBuilder.addTracks(tracks)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                        Text("Add All to Playlist Builder")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.xomifyPurple.opacity(0.2))
                    .foregroundColor(.xomifyPurple)
                    .cornerRadius(XomRadius.pill)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
    
    // MARK: - Track List
    
    private var trackList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tracks")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)
                .padding(.bottom, 12)
            
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                trackRow(track, number: index + 1)
                
                if index < tracks.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 56)
                }
            }
        }
        .padding(.bottom, 40)
    }
    
    private func trackRow(_ track: SpotifyTrack, number: Int) -> some View {
        HStack(spacing: 12) {
            // Track number
            Text("\(number)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 28, alignment: .center)
            
            // Track info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if track.artists.count > 1 || track.artistNames != album?.artistNames {
                    Text(track.artistNames)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Explicit badge
            if track.explicit == true {
                Text("E")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(XomRadius.sm)
            }
            
            // Duration
            Text(track.duration)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            
            TrackActionsMenu(track: track)
        }
        .trackContextMenu(track: track)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            quickInfoTrack = track
        }
        .accessibilityHint("Shows track details")
    }

    // MARK: - Error State
    
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange.opacity(0.7))
            
            Text("Error Loading Album")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            
            Button {
                Task { await loadAlbum() }
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
    
    // MARK: - Data Loading
    
    private func loadAlbum() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let albumData = spotifyService.getAlbum(id: albumId)
            async let tracksData = spotifyService.getAlbumTracks(id: albumId)
            
            album = try await albumData
            tracks = try await tracksData
            
            print("✅ AlbumView: Loaded '\(album?.name ?? "")' with \(tracks.count) tracks")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ AlbumView: Error - \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Playback

    private func spotifyUrl(for album: SpotifyAlbum) -> URL? {
        if let urlString = album.externalUrls?["spotify"] {
            return URL(string: urlString)
        }
        return URL(string: "spotify:album:\(album.id)")
    }
    
    private func spotifyShuffleUrl(for album: SpotifyAlbum) -> URL? {
        // Spotify URI with shuffle context
        return URL(string: "spotify:album:\(album.id):play")
    }
}

#Preview {
    NavigationStack {
        AlbumView(albumId: "4aawyAB9vmqN3uQ7FjRGTy")
    }
}
