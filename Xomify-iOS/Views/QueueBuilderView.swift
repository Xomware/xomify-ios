import SwiftUI

// MARK: - Queue Builder View

struct QueueBuilderView: View {
    @State private var viewModel = QueueBuilderViewModel()
    @State private var selectedPanel = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                panelSelector
                
                TabView(selection: $selectedPanel) {
                    searchPanel.tag(0)
                    queuePanel.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color.xomifyDark.ignoresSafeArea())
            .navigationTitle("Queue Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Queue Builder").font(.headline).foregroundColor(.white)
                        Text("Search, build, and save playlists").font(.caption2).foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSaveModal) {
                savePlaylistSheet
            }
        }
    }
    
    private var panelSelector: some View {
        HStack(spacing: 8) {
            Button { withAnimation { selectedPanel = 0 } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
                .font(.subheadline).fontWeight(.medium)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(selectedPanel == 0 ? Color.xomifyPurple.opacity(0.3) : Color.clear)
                .foregroundColor(selectedPanel == 0 ? .xomifyPurple : .white.opacity(0.5))
                .cornerRadius(XomRadius.lg)
            }
            
            Button { withAnimation { selectedPanel = 1 } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                    Text("Queue")
                    if !viewModel.queue.isEmpty {
                        Text("(\(viewModel.queue.count))").font(.caption)
                    }
                }
                .font(.subheadline).fontWeight(.medium)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(selectedPanel == 1 ? Color.xomifyGreen.opacity(0.3) : Color.clear)
                .foregroundColor(selectedPanel == 1 ? .xomifyGreen : .white.opacity(0.5))
                .cornerRadius(XomRadius.lg)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color.xomifyCard)
    }
    
    // MARK: - Search Panel
    
    private var searchPanel: some View {
        VStack(spacing: 0) {
            // Search box
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundColor(.white.opacity(0.5))
                TextField("Search songs, artists...", text: $viewModel.searchQuery)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.searchQuery) { _, _ in viewModel.search() }
                if !viewModel.searchQuery.isEmpty {
                    Button { viewModel.clearSearch() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(XomRadius.xl)
            .padding()
            
            // Results
            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.isSearching {
                        XomifyLoaderPaint(size: 36).padding(.top, 40)
                    } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                        Text("No results found").foregroundColor(.white.opacity(0.5)).padding(.top, 40)
                    } else if viewModel.searchResults.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Search for tracks to add").foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(viewModel.searchResults) { track in
                            searchResultRow(track)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func searchResultRow(_ track: SpotifyTrack) -> some View {
        let isInQueue = viewModel.isInQueue(track.id)
        
        return HStack(spacing: 12) {
            // Album art
            AsyncImage(url: track.imageUrl) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.white.opacity(0.08))
            }
            .frame(width: 48, height: 48)
            .cornerRadius(XomRadius.md)
            
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
            
            // Add button
            Button {
                viewModel.addToQueue(track)
            } label: {
                Image(systemName: isInQueue ? "checkmark" : "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isInQueue ? .xomifyGreen : .white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isInQueue ? Color.xomifyGreen.opacity(0.2) : Color.xomifyGreen)
                    )
            }
            .disabled(isInQueue)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: XomRadius.lg)
                .fill(isInQueue ? Color.xomifyGreen.opacity(0.1) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: XomRadius.lg)
                        .stroke(isInQueue ? Color.xomifyGreen.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Queue Panel
    
    private var queuePanel: some View {
        VStack(spacing: 0) {
            // Header with stats
            if !viewModel.queue.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.queue.count) tracks")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(viewModel.totalDurationFormatted)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    Button {
                        viewModel.clearQueue()
                    } label: {
                        Text("Clear")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(XomRadius.md)
                    }
                }
                .padding()
            }
            
            // Queue list
            ScrollView {
                if viewModel.queue.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("Your queue is empty")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("Search and add tracks to build your playlist")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(viewModel.queue.enumerated()), id: \.element.id) { index, track in
                            queueRow(track, index: index)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // Action buttons
            if !viewModel.queue.isEmpty {
                VStack(spacing: 12) {
                    Button {
                        viewModel.openSaveModal()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save as Playlist")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.xomifyPurple, .xomifyPurple.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(XomRadius.xl)
                    }
                }
                .padding()
                .background(Color.xomifyCard)
            }
        }
    }
    
    private func queueRow(_ track: QueueTrack, index: Int) -> some View {
        HStack(spacing: 10) {
            // Rank
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 24)
            
            // Album art
            AsyncImage(url: track.albumImageUrl) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.white.opacity(0.08))
            }
            .frame(width: 40, height: 40)
            .cornerRadius(XomRadius.md)
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(track.artistNames)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Remove button
            Button {
                viewModel.removeFromQueue(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(XomRadius.md)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(XomRadius.md)
    }
    
    // MARK: - Save Playlist Sheet
    
    private var savePlaylistSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Playlist name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Playlist Name")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                    
                    TextField("Enter playlist name", text: $viewModel.playlistName)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (optional)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                    
                    TextField("Add a description...", text: $viewModel.playlistDescription, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                }
                
                // Public toggle
                Toggle("Make playlist public", isOn: $viewModel.isPublic)
                
                // Preview
                HStack {
                    Text("\(viewModel.queue.count) tracks")
                    Spacer()
                    Text(viewModel.totalDurationFormatted)
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(XomRadius.md)
                
                Spacer()
                
                // Save button
                Button {
                    Task {
                        await viewModel.saveAsPlaylist()
                    }
                } label: {
                    HStack {
                        if viewModel.isSaving {
                            ProgressView().tint(.black)
                        } else {
                            Text("Create Playlist")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.xomifyGreen)
                    .foregroundColor(.black)
                    .cornerRadius(XomRadius.xl)
                }
                .disabled(viewModel.playlistName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSaving)
            }
            .padding()
            .navigationTitle("Save Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.closeSaveModal()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    QueueBuilderView()
}
