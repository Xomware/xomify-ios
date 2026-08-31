import SwiftUI

struct PlaylistBuilderView: View {
    @State private var viewModel = PlaylistBuilderViewModel()
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingCreateSheet = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isEmpty && viewModel.successMessage == nil {
                    emptyState
                } else if let success = viewModel.successMessage {
                    successState(success)
                } else {
                    trackList
                    bottomBar
                }
            }
            .background(Color.xomifyDark.ignoresSafeArea())
            .navigationTitle("Playlist Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.xomifyPurple)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.isEmpty {
                        Button {
                            viewModel.clear()
                        } label: {
                            Text("Clear")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                createPlaylistSheet
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.xomifyPurple.opacity(0.5))
            
            Text("No Tracks Added")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Add songs from anywhere in the app\nusing the + button")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Success State
    
    private func successState(_ message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.xomifyGreen)
            
            Text("Playlist Created!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            
            if let url = viewModel.createdPlaylistUrl {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right")
                        Text("Open in Spotify")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 29/255, green: 185/255, blue: 84/255))
                    .foregroundColor(.white)
                    .cornerRadius(XomRadius.pill)
                }
                .padding(.horizontal, 40)
            }
            
            Button {
                viewModel.clearSuccess()
            } label: {
                Text("Build Another Playlist")
                    .font(.subheadline)
                    .foregroundColor(.xomifyPurple)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Track List
    
    private var trackList: some View {
        List {
            // Stats header
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.trackCount) tracks")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(viewModel.totalDuration)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    // Shuffle order button
                    Button {
                        viewModel.shuffleTracks()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.title3)
                            .foregroundColor(.xomifyPurple)
                    }
                }
                .listRowBackground(Color.xomifyCard)
            }
            
            // Tracks
            Section {
                ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, index: index)
                        .listRowBackground(Color.xomifyCard)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        viewModel.removeTrack(at: index)
                    }
                }
                .onMove { source, destination in
                    viewModel.moveTrack(from: source, to: destination)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }
    
    private func trackRow(_ track: SpotifyTrack, index: Int) -> some View {
        HStack(spacing: 12) {
            // Track number
            Text("\(index + 1)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 24)
            
            // Album art
            AsyncImage(url: track.imageUrl) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.white.opacity(0.08))
            }
            .frame(width: 44, height: 44)
            .cornerRadius(XomRadius.sm)
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(track.artistNames)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            
            Spacer()

            // Duration
            Text(track.duration)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))

            QueueButton(
                uri: track.uri ?? "spotify:track:\(track.id)",
                trackName: track.name
            )
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.05))
            
            HStack(spacing: 16) {
                // Track count
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.trackCount) tracks")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(viewModel.totalDuration)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // Create button
                Button {
                    viewModel.resetForm()
                    showingCreateSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Playlist")
                    }
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.xomifyPurple, .xomifyGreen], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(XomRadius.pill)
                }
            }
            .padding()
            .background(Color.xomifyCard)
        }
    }
    
    // MARK: - Create Playlist Sheet
    
    private var createPlaylistSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview
                VStack(spacing: 12) {
                    // Playlist art grid
                    playlistArtGrid
                    
                    Text("\(viewModel.trackCount) tracks • \(viewModel.totalDuration)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.top, 20)
                
                // Form
                VStack(spacing: 16) {
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Playlist Name")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.5))
                        
                        TextField("My Playlist", text: $viewModel.playlistName)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(XomRadius.xl)
                            .foregroundColor(.white)
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description (optional)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.5))
                        
                        TextField("Add a description...", text: $viewModel.playlistDescription)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(XomRadius.xl)
                            .foregroundColor(.white)
                    }
                    
                    // Public toggle
                    Toggle(isOn: $viewModel.isPublic) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Public Playlist")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Text("Others can find and follow")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .tint(.xomifyGreen)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(XomRadius.xl)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Error message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                // Create button
                Button {
                    Task {
                        await viewModel.createPlaylist()
                        if viewModel.successMessage != nil {
                            showingCreateSheet = false
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isCreating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Create Playlist")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(colors: [.xomifyPurple, .xomifyGreen], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(XomRadius.pill)
                }
                .disabled(viewModel.isCreating || viewModel.playlistName.isEmpty)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.xomifyDark.ignoresSafeArea())
            .navigationTitle("Create Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showingCreateSheet = false
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Playlist Art Grid
    
    private var playlistArtGrid: some View {
        let images = viewModel.previewImageUrls
        
        return ZStack {
            if images.count >= 4 {
                // 2x2 grid of album arts
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        albumArtImage(url: images[0])
                        albumArtImage(url: images[1])
                    }
                    HStack(spacing: 2) {
                        albumArtImage(url: images[2])
                        albumArtImage(url: images[3])
                    }
                }
                .frame(width: 160, height: 160)
                .cornerRadius(XomRadius.xl)
            } else if let firstImage = images.first {
                // Single image
                AsyncImage(url: firstImage) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.08))
                }
                .frame(width: 160, height: 160)
                .cornerRadius(XomRadius.xl)
            } else {
                // Placeholder
                RoundedRectangle(cornerRadius: XomRadius.xl)
                    .fill(Color.xomifyPurple.opacity(0.3))
                    .frame(width: 160, height: 160)
                    .overlay(
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundColor(.xomifyPurple)
                    )
            }
        }
    }
    
    private func albumArtImage(url: URL) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Color.white.opacity(0.08))
        }
        .frame(width: 79, height: 79)
        .clipped()
    }
}

// MARK: - Floating Button Overlay

struct PlaylistBuilderFloatingButton: View {
    private let manager = PlaylistBuilderManager.shared
    
    var body: some View {
        if manager.trackCount > 0 {
            Button {
                manager.show()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.subheadline)
                    
                    Text("\(manager.trackCount)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(LinearGradient(colors: [.xomifyPurple, .xomifyGreen], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: .xomifyPurple.opacity(0.5), radius: 10, x: 0, y: 5)
                )
                .foregroundColor(.white)
            }
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.3), value: manager.trackCount)
        }
    }
}

// MARK: - Add to Playlist Button

struct AddToPlaylistButton: View {
    let track: SpotifyTrack
    private let manager = PlaylistBuilderManager.shared
    
    var isAdded: Bool {
        manager.contains(track)
    }
    
    var body: some View {
        Button {
            if isAdded {
                manager.removeTrack(track)
            } else {
                manager.addTrack(track)
            }
        } label: {
            Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                .font(.title3)
                .foregroundColor(isAdded ? .xomifyGreen : .xomifyPurple)
        }
    }
}

#Preview {
    PlaylistBuilderView()
}
