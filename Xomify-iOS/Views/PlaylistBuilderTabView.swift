import SwiftUI

// MARK: - Playlist Builder Tab

struct PlaylistBuilderTabView: View {
    @State private var viewModel = PlaylistBuilderViewModel()
    @State private var showingCreateSheet = false
    @State private var selectedTab = 0 // 0 = Playlist, 1 = Search

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                tabPicker

                // Content based on selected tab
                if selectedTab == 0 {
                    playlistTab
                } else {
                    searchTab
                }
            }
            .background(Color.xomifyDark.ignoresSafeArea())
            .navigationTitle("Playlist Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedTab == 0 && !viewModel.isEmpty {
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

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            // Playlist Tab
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = 0
                }
            } label: {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note.list")
                        Text("Playlist")
                        if viewModel.trackCount > 0 {
                            Text("(\(viewModel.trackCount))")
                                .font(.caption)
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(selectedTab == 0 ? .semibold : .regular)
                    .foregroundColor(selectedTab == 0 ? .white : .gray)

                    Rectangle()
                        .fill(selectedTab == 0 ? Color.xomifyPurple : Color.clear)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)

            // Search Tab
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = 1
                }
            } label: {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                    }
                    .font(.subheadline)
                    .fontWeight(selectedTab == 1 ? .semibold : .regular)
                    .foregroundColor(selectedTab == 1 ? .white : .gray)

                    Rectangle()
                        .fill(selectedTab == 1 ? Color.xomifyGreen : Color.clear)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .background(Color.xomifyCard)
    }

    // MARK: - Playlist Tab

    private var playlistTab: some View {
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
    }

    // MARK: - Search Tab

    private var searchTab: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            if viewModel.isSearching {
                Spacer()
                XomifyLoaderPulse()
                Spacer()
            } else if viewModel.searchResults.isEmpty {
                searchEmptyState
            } else {
                searchResultsList
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search for songs...", text: $viewModel.searchQuery)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .onSubmit {
                    Task { await viewModel.search() }
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .padding()
    }

    private var searchEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))

            Text("Search for Songs")
                .font(.headline)
                .foregroundColor(.white)

            Text("Find songs to add to your playlist")
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.searchResults) { track in
                    searchResultRow(track)
                }
            }
            .padding()
        }
    }

    private func searchResultRow(_ track: SpotifyTrack) -> some View {
        HStack(spacing: 12) {
            // Album art
            AsyncImage(url: track.imageUrl) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
            .frame(width: 50, height: 50)
            .cornerRadius(6)

            // Track info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(track.artistNames)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer()

            // Duration
            Text(track.duration)
                .font(.caption)
                .foregroundColor(.gray)

            // Add button
            Button {
                if viewModel.contains(track) {
                    viewModel.removeTrack(track)
                } else {
                    viewModel.addTrack(track)
                }
            } label: {
                Image(systemName: viewModel.contains(track) ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(viewModel.contains(track) ? Color.xomifyGreen : Color.xomifyPurple)
            }
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(Color.xomifyPurple.opacity(0.5))

            Text("No Tracks Added")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Add songs from anywhere in the app\nusing the + button")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            // Quick tips
            VStack(alignment: .leading, spacing: 12) {
                tipRow(icon: "music.note", text: "Tap + on any track to add it")
                tipRow(icon: "person.2.fill", text: "Add artist's top tracks")
                tipRow(icon: "square.stack.fill", text: "Add entire albums")
                tipRow(icon: "chart.bar.fill", text: "Save your top songs")
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .padding(.horizontal, 40)
            .padding(.top, 20)

            Spacer()
        }
        .padding()
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(Color.xomifyPurple)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Success State

    private func successState(_ message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(Color.xomifyGreen)

            Text("Playlist Created!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
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
                    .background(Color.spotifyGreen)
                    .foregroundColor(.white)
                    .cornerRadius(30)
                }
                .padding(.horizontal, 40)
            }

            Button {
                viewModel.clearSuccess()
            } label: {
                Text("Build Another Playlist")
                    .font(.subheadline)
                    .foregroundColor(Color.xomifyPurple)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    // MARK: - Track List

    private var trackList: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.trackCount) tracks")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(viewModel.totalDuration)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Button {
                        viewModel.shuffleTracks()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                        }
                        .font(.subheadline)
                        .foregroundColor(Color.xomifyPurple)
                    }
                }
                .listRowBackground(Color.xomifyCard)
            }

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
            Text("\(index + 1)")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 24)

            AsyncImage(url: track.imageUrl) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
            .frame(width: 44, height: 44)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(track.artistNames)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer()

            Text(track.duration)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.gray.opacity(0.3))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.trackCount) tracks")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(viewModel.totalDuration)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

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
                        LinearGradient(
                            colors: [Color.xomifyPurple, Color.xomifyGreen],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(25)
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
                VStack(spacing: 12) {
                    playlistArtGrid

                    Text("\(viewModel.trackCount) tracks • \(viewModel.totalDuration)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.top, 20)

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Playlist Name")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)

                        TextField("My Playlist", text: $viewModel.playlistName)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description (optional)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)

                        TextField("Add a description...", text: $viewModel.playlistDescription)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                    }

                    Toggle(isOn: $viewModel.isPublic) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Public Playlist")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Text("Others can find and follow")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .tint(Color.xomifyGreen)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

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
                        LinearGradient(
                            colors: [Color.xomifyPurple, Color.xomifyGreen],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(30)
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
                    .foregroundColor(.gray)
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
                .cornerRadius(12)
            } else if let firstImage = images.first {
                AsyncImage(url: firstImage) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 160, height: 160)
                .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.xomifyPurple.opacity(0.3))
                    .frame(width: 160, height: 160)
                    .overlay(
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundColor(Color.xomifyPurple)
                    )
            }
        }
    }

    private func albumArtImage(url: URL) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Color.gray.opacity(0.3))
        }
        .frame(width: 79, height: 79)
        .clipped()
    }
}
