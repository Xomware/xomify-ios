import SwiftUI

/// Public wrapper — owns its own `NavigationStack` for standalone presentation.
/// When composed inside another `NavigationStack` (e.g. the drawer's Stats screen),
/// use ``WrappedContent`` directly to avoid nested stacks.
struct WrappedView: View {
    var body: some View {
        NavigationStack {
            WrappedContent()
        }
    }
}

/// Bare body — no wrapping `NavigationStack`. Safe to embed anywhere.
struct WrappedContent: View {
    @State private var wraps: [MonthlyWrap] = []
    @State private var selectedMonth: MonthlyWrap?
    @State private var showMonthPicker = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab = 0 // 0 = Songs, 1 = Artists, 2 = Genres
    @State private var selectedTerm = "shortTerm"

    // Content states
    @State private var tracks: [SpotifyTrack] = []
    @State private var artists: [SpotifyArtist] = []
    @State private var isLoadingContent = false
    @State private var isSaving = false

    @Bindable private var playlistBuilder = PlaylistBuilderManager.shared
    private let spotifyService = SpotifyService.shared
    private let xomifyService = XomifyService.shared

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                BrandGradientHeader(
                    "Wrapped",
                    subtitle: currentWrap.map { "MONTHLY RECAP · \($0.displayName.uppercased())" } ?? "YOUR MONTHLY RECAP",
                    systemImage: "gift.fill"
                ) {
                    if let wrap = currentWrap, let shareURL = URL(string: "https://xomify.xomware.com/wrapped") {
                        ShareLink(
                            item: shareURL,
                            subject: Text("My \(wrap.displayName) Wrap"),
                            message: Text("My top tracks from \(wrap.displayName)")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            Task { await publishWrappedShare() }
                        })
                    }
                }

                // Month selector header
                if !wraps.isEmpty {
                    monthHeader
                }

                // Tab picker
                if !wraps.isEmpty && !isLoading {
                    tabPicker

                    // Time range picker
                    timeRangePicker

                    // Action buttons for Songs tab
                    if selectedTab == 0 && !tracks.isEmpty {
                        actionButtons
                    }
                }

                // Content
                if isLoading {
                    Spacer()
                    loadingState
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    errorState(error)
                    Spacer()
                } else if wraps.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    contentView
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
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .sheet(isPresented: $showMonthPicker) {
            monthPicker
        }
        .sheet(isPresented: $playlistBuilder.isShowing) {
            PlaylistBuilderView()
        }
    }

    // MARK: - Share to Feed
    //
    // The deployed `shares_create` contract is strictly track-denormalized —
    // the legacy `wrapped` / `release_radar` share types no longer exist. This
    // tap only publishes the native iOS Share Sheet (via `ShareLink`); no
    // additional feed write happens here.
    // TODO(future): share the Wrap's #1 track to the feed via `createShare`
    // once we settle on a UX (confirm sheet? auto?).
    private func publishWrappedShare() async {
        // Intentionally a no-op under the new shares atom.
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        Button {
            showMonthPicker = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MONTHLY WRAP")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.xomifyPurple)

                    Text(selectedMonth?.displayName ?? wraps.first?.displayName ?? "Select Month")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }

                Spacer()

                Image(systemName: "chevron.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.xomifyPurple.opacity(0.7))
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.xomifyPurple.opacity(0.15), Color.xomifyCard],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .disabled(wraps.count <= 1)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabButton(title: "Songs", icon: "music.note", index: 0, color: .xomifyGreen)
            tabButton(title: "Artists", icon: "person.2", index: 1, color: .xomifyPurple)
            tabButton(title: "Genres", icon: "guitars", index: 2, color: .xomifyGreen)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private func tabButton(title: String, icon: String, index: Int, color: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
            Task { await loadContent() }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(selectedTab == index ? .semibold : .regular)
                }
                .foregroundStyle(selectedTab == index ? color : Color.gray)

                Rectangle()
                    .fill(selectedTab == index ? color : Color.clear)
                    .frame(height: 3)
                    .cornerRadius(1.5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        Picker("Time Range", selection: $selectedTerm) {
            Text("4 Weeks").tag("shortTerm")
            Text("6 Months").tag("mediumTerm")
            Text("All Time").tag("longTerm")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 12)
        .onChange(of: selectedTerm) { _, _ in
            Task { await loadContent() }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                playlistBuilder.addTracks(tracks)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add All to Builder")
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.xomifyPurple.opacity(0.2))
                .foregroundStyle(Color.xomifyPurple)
                .cornerRadius(20)
            }

            Button {
                Task { await savePlaylist() }
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.xomifyGreen)
                    } else {
                        Image(systemName: "square.and.arrow.down.fill")
                    }
                    Text("Save Playlist")
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.xomifyGreen.opacity(0.2))
                .foregroundStyle(Color.xomifyGreen)
                .cornerRadius(20)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView {
            if isLoadingContent {
                XomifyLoaderSpin()
                    .padding(.top, 40)
            } else {
                switch selectedTab {
                case 0:
                    songsContent
                case 1:
                    artistsContent
                default:
                    genresContent
                }
            }
        }
        .padding(.bottom, 80)
    }

    // MARK: - Songs Content

    private var songsContent: some View {
        LazyVStack(spacing: 0) {
            if tracks.isEmpty {
                emptyContentState(message: "No songs for this time range")
            } else {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(index: index, track: track)

                    if index < tracks.count - 1 {
                        Divider()
                            .background(Color.gray.opacity(0.2))
                            .padding(.leading, 70)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func trackRow(index: Int, track: SpotifyTrack) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(index + 1)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(index < 3 ? Color.xomifyGreen : Color.gray)
                .frame(width: 30)

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
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(track.artistNames)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }

            Spacer()

            TrackActionsMenu(track: track)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Artists Content

    private var artistsContent: some View {
        LazyVStack(spacing: 0) {
            if artists.isEmpty {
                emptyContentState(message: "No artists for this time range")
            } else {
                ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                    if let artistId = artist.id {
                        NavigationLink(destination: ArtistView(artistId: artistId)) {
                            artistRow(index: index, artist: artist)
                        }
                    } else {
                        artistRow(index: index, artist: artist)
                    }

                    if index < artists.count - 1 {
                        Divider()
                            .background(Color.gray.opacity(0.2))
                            .padding(.leading, 70)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func artistRow(index: Int, artist: SpotifyArtist) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(index + 1)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(index < 3 ? Color.xomifyPurple : Color.gray)
                .frame(width: 30)

            // Artist image
            AsyncImage(url: artist.imageUrl) { image in
                image.resizable()
            } placeholder: {
                Circle().fill(Color.gray.opacity(0.3))
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())

            // Artist name
            Text(artist.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Genres Content

    private var genresContent: some View {
        let genres = currentGenres
        let sortedGenres = genres.sorted { $0.value > $1.value }
        let maxCount = sortedGenres.first?.1 ?? 1

        return LazyVStack(spacing: 0) {
            if sortedGenres.isEmpty {
                emptyContentState(message: "No genre data for this time range")
            } else {
                ForEach(Array(sortedGenres.prefix(15).enumerated()), id: \.element.0) { index, genre in
                    genreRow(index: index, genre: genre, maxCount: maxCount)

                    if index < min(sortedGenres.count, 15) - 1 {
                        Divider()
                            .background(Color.gray.opacity(0.2))
                            .padding(.leading, 50)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func genreRow(index: Int, genre: (String, Int), maxCount: Int) -> some View {
        let percentage = Double(genre.1) / Double(maxCount)

        return HStack(spacing: 12) {
            // Rank
            Text("\(index + 1)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(index < 3 ? Color.xomifyGreen : Color.gray)
                .frame(width: 30)

            // Genre name
            Text(genre.0.capitalized)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)

            Spacer()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: XomRadius.sm)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: XomRadius.sm)
                        .fill(
                            LinearGradient(
                                colors: [.xomifyGreen, .xomifyPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * percentage)
                }
            }
            .frame(width: 100, height: 8)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private func emptyContentState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.gray.opacity(0.5))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helper Properties

    private var currentWrap: MonthlyWrap? {
        selectedMonth ?? wraps.first
    }

    private var currentGenres: [String: Int] {
        guard let wrap = currentWrap, let genres = wrap.topGenres else { return [:] }
        switch selectedTerm {
        case "shortTerm": return genres.shortTerm ?? [:]
        case "mediumTerm": return genres.mediumTerm ?? [:]
        default: return genres.longTerm ?? [:]
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            let user = try await spotifyService.getCurrentUser()

            guard let email = user.email, !email.isEmpty else {
                errorMessage = "Could not get email from Spotify"
                isLoading = false
                return
            }

            _ = email
            wraps = try await xomifyService.getWraps()

            if selectedMonth == nil {
                selectedMonth = wraps.first
            }

            print("✅ Wrapped: Loaded \(wraps.count) wraps")

            await loadContent()
        } catch {
            print("❌ Wrapped: Error - \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadContent() async {
        guard let wrap = currentWrap else { return }

        // Clear any prior error so a successful reload (tab/term switch or
        // retry) doesn't leave a stale error message rendered.
        errorMessage = nil
        isLoadingContent = true

        switch selectedTab {
        case 0:
            let ids: [String]?
            switch selectedTerm {
            case "shortTerm": ids = wrap.topSongIds?.shortTerm
            case "mediumTerm": ids = wrap.topSongIds?.mediumTerm
            default: ids = wrap.topSongIds?.longTerm
            }

            if let ids = ids, !ids.isEmpty {
                do {
                    tracks = try await spotifyService.getTracks(ids: Array(ids.prefix(50)))
                } catch {
                    print("❌ Failed to load tracks: \(error)")
                    tracks = []
                }
            } else {
                tracks = []
            }

        case 1:
            let ids: [String]?
            switch selectedTerm {
            case "shortTerm": ids = wrap.topArtistIds?.shortTerm
            case "mediumTerm": ids = wrap.topArtistIds?.mediumTerm
            default: ids = wrap.topArtistIds?.longTerm
            }

            if let ids = ids, !ids.isEmpty {
                do {
                    artists = try await spotifyService.getArtists(ids: Array(ids.prefix(50)))
                } catch {
                    print("❌ Failed to load artists: \(error)")
                    artists = []
                }
            } else {
                artists = []
            }

        default:
            break // Genres are computed, no loading needed
        }

        isLoadingContent = false
    }

    private func savePlaylist() async {
        guard let wrap = currentWrap else { return }

        let termDisplay = selectedTerm == "shortTerm" ? "Last 4 Weeks" : selectedTerm == "mediumTerm" ? "Last 6 Months" : "All Time"
        let playlistName = "Top Songs - \(termDisplay) (\(wrap.displayName))"

        isSaving = true

        do {
            let user = try await spotifyService.getCurrentUser()

            guard let userId = user.id else {
                print("❌ No user ID available")
                isSaving = false
                return
            }

            let playlist = try await spotifyService.createPlaylist(
                userId: userId,
                name: playlistName,
                description: "Created with Xomify",
                isPublic: false
            )

            let trackUris = tracks.map { "spotify:track:\($0.id)" }
            try await spotifyService.addTracksToPlaylist(playlistId: playlist.id, trackUris: trackUris)

            print("✅ Created playlist: \(playlistName)")

            if let url = URL(string: "spotify:playlist:\(playlist.id)") {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
            }
        } catch {
            print("❌ Failed to create playlist: \(error)")
        }

        isSaving = false
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            XomifyLoaderPulse()
            Text("Loading wrapped data...")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.orange.opacity(0.7))

            Text("Error Loading Data")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)

            Button {
                Task { await loadData() }
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
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "gift")
                .font(.system(size: 50))
                .foregroundStyle(.gray.opacity(0.5))

            Text("No Wrapped Data Yet")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Wrapped data is generated monthly. Check back after the first of the month!")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Month Picker

    private var monthPicker: some View {
        NavigationStack {
            List {
                ForEach(wraps) { wrap in
                    Button {
                        selectedMonth = wrap
                        showMonthPicker = false
                        Task { await loadContent() }
                    } label: {
                        HStack {
                            Text(wrap.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)

                            Spacer()

                            if selectedMonth?.monthKey == wrap.monthKey {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.xomifyGreen)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
            .background(Color.xomifyDark)
            .scrollContentBackground(.hidden)
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showMonthPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    WrappedView()
}
