import SwiftUI

struct ReleaseRadarView: View {
    @State private var viewModel = ReleaseRadarViewModel()
    @State private var showWeekPicker = false
    @State private var isLoadingUser = true
    
    @Bindable private var playlistBuilder = PlaylistBuilderManager.shared
    private let spotifyService = SpotifyService.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    BrandGradientHeader(
                        "Release Radar",
                        subtitle: "NEW DROPS · \(viewModel.displayWeekName.uppercased())",
                        systemImage: "antenna.radiowaves.left.and.right"
                    ) {
                        HStack(spacing: 12) {
                            Button {
                                Task { await viewModel.refresh() }
                            } label: {
                                if viewModel.isRefreshing {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                }
                            }
                            .disabled(viewModel.isRefreshing || isLoadingUser)

                            if viewModel.selectedWeek != nil || !viewModel.historyWeeks.isEmpty {
                                ShareLink(
                                    item: URL(string: "https://xomify.xomware.com/release-radar")!,
                                    subject: Text("My Release Radar"),
                                    message: Text(shareCaption)
                                ) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    Task { await publishReleaseRadarShare() }
                                })
                            }
                        }
                    }

                    // Week selector header
                    weekHeader

                    // Stats bar
                    if let stats = viewModel.displayStats {
                        statsBar(stats)
                    }

                    // Content
                    ScrollView {
                        if isLoadingUser || viewModel.isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text(isLoadingUser ? "Loading profile..." : "Loading releases...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.top, 60)
                        } else if let error = viewModel.errorMessage {
                            errorState(error)
                        } else if viewModel.displayReleases.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.displayReleases, id: \.stableId) { release in
                                    releaseCard(release)
                                }
                            }
                            .padding()
                            .padding(.bottom, 80) // Space for floating button
                        }
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
                await loadUserAndData()
            }
            .sheet(isPresented: $showWeekPicker) {
                weekPicker
            }
            .sheet(isPresented: $playlistBuilder.isShowing) {
                PlaylistBuilderView()
            }
        }
    }
    
    // MARK: - Load User and Data
    
    private func loadUserAndData() async {
        isLoadingUser = true
        
        do {
            // Get email directly from Spotify API - don't create a new ProfileViewModel
            let user = try await spotifyService.getCurrentUser()
            
            guard let email = user.email, !email.isEmpty else {
                viewModel.errorMessage = "Could not get email from Spotify"
                isLoadingUser = false
                return
            }
            
            viewModel.userEmail = email
            print("📧 ReleaseRadar: Got email: \(email)")
            
            // Now load release radar data
            await viewModel.loadData()
        } catch {
            print("❌ ReleaseRadar: Failed to get user: \(error)")
            viewModel.errorMessage = "Failed to load user profile: \(error.localizedDescription)"
        }
        
        isLoadingUser = false
    }
    
    // MARK: - Week Header
    
    private var weekHeader: some View {
        Button {
            showWeekPicker = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RELEASE RADAR")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.xomifyGreen)
                    
                    Text(viewModel.displayWeekName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    if let dateRange = viewModel.displayDateRange {
                        Text(dateRange)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                if viewModel.historyWeeks.count > 1 {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.xomifyGreen.opacity(0.7))
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.xomifyGreen.opacity(0.15), Color.xomifyCard],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .disabled(viewModel.historyWeeks.count <= 1)
    }
    
    // MARK: - Stats Bar
    
    private func statsBar(_ stats: ReleaseStats) -> some View {
        HStack(spacing: 0) {
            statItem(value: stats.releaseCount ?? 0, label: "Releases", color: .xomifyGreen)
            
            Divider()
                .frame(height: 30)
                .background(Color.gray.opacity(0.3))
            
            statItem(value: stats.artistCount ?? 0, label: "Artists", color: .xomifyPurple)
            
            Divider()
                .frame(height: 30)
                .background(Color.gray.opacity(0.3))
            
            statItem(value: stats.trackCount ?? 0, label: "Tracks", color: .xomifyGreen)
            
            Divider()
                .frame(height: 30)
                .background(Color.gray.opacity(0.3))
            
            statItem(value: stats.albumCount ?? 0, label: "Albums", color: .xomifyPurple)
            
            Divider()
                .frame(height: 30)
                .background(Color.gray.opacity(0.3))
            
            statItem(value: stats.singleCount ?? 0, label: "Singles", color: .xomifyGreen)
        }
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color.xomifyCard, Color.xomifyDark.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private func statItem(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Release Card
    
    private func releaseCard(_ release: Release) -> some View {
        HStack(spacing: 14) {
            // Album art - tap to go to album
            if let albumId = release.albumId ?? release.id {
                NavigationLink(destination: AlbumView(albumId: albumId)) {
                    AsyncImage(url: release.image) { image in
                        image.resizable()
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 70, height: 70)
                    .cornerRadius(XomRadius.md)
                }
            } else {
                AsyncImage(url: release.image) { image in
                    image.resizable()
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 70, height: 70)
                .cornerRadius(XomRadius.md)
            }
            
            // Release info
            VStack(alignment: .leading, spacing: 6) {
                // Album name - tap to go to album
                if let albumId = release.albumId ?? release.id {
                    NavigationLink(destination: AlbumView(albumId: albumId)) {
                        Text(release.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    Text(release.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
                
                // Artist name - tap to go to artist
                if let artistId = release.artistId {
                    NavigationLink(destination: ArtistView(artistId: artistId)) {
                        Text(release.displayArtist)
                            .font(.caption)
                            .foregroundColor(.xomifyPurple)
                            .lineLimit(1)
                    }
                } else {
                    Text(release.displayArtist)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    // Album type badge
                    if let type = release.albumType {
                        Text(type.capitalized)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeColor(for: type).opacity(0.2))
                            .foregroundColor(badgeColor(for: type))
                            .cornerRadius(XomRadius.sm)
                    }
                    
                    // Track count
                    if let tracks = release.totalTracks {
                        Text("\(tracks) tracks")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    
                    // Release date
                    if let date = release.releaseDate {
                        Text(formatDate(date))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: 12) {
                // Add to playlist button
                Button {
                    Task { await addReleaseToPlaylist(release) }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.xomifyPurple)
                }
                
                // Play button - opens in Spotify
                Button {
                    playRelease(release)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundColor(.xomifyGreen)
                }
            }
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(XomRadius.xl)
    }
    
    private func addReleaseToPlaylist(_ release: Release) async {
        guard let albumId = release.albumId ?? release.id else { return }
        
        do {
            let tracks = try await spotifyService.getAlbumTracks(id: albumId)
            playlistBuilder.addTracks(tracks)
            print("✅ Added \(tracks.count) tracks from '\(release.displayName)' to playlist builder")
        } catch {
            print("❌ Failed to add release tracks: \(error)")
        }
    }
    
    private func playRelease(_ release: Release) {
        // Try URI first (opens directly in Spotify app)
        if let uri = release.uri, let url = URL(string: uri) {
            UIApplication.shared.open(url)
        } else if let url = release.spotify {
            UIApplication.shared.open(url)
        }
    }
    
    private func badgeColor(for type: String) -> Color {
        switch type.lowercased() {
        case "album": return .xomifyPurple
        case "single": return .xomifyGreen
        case "ep": return .blue
        default: return .gray
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    // MARK: - Error State
    
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange.opacity(0.7))
            
            Text("Error Loading Data")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button {
                Task { await loadUserAndData() }
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
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Releases Yet")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Release data is updated weekly on Saturday mornings. Check back then for new music from your followed artists!")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }
    
    // MARK: - Share to Feed
    //
    // The deployed `shares_create` contract is strictly track-denormalized —
    // the legacy `release_radar` share type no longer exists. This tap only
    // publishes the native iOS Share Sheet (via `ShareLink`); no additional
    // feed write happens here.
    // TODO(future): share the Release Radar's top track to the feed via
    // `createShare` once we settle on a UX.

    private var shareCaption: String {
        "My Release Radar — \(viewModel.displayWeekName)"
    }

    private func publishReleaseRadarShare() async {
        // Intentionally a no-op under the new shares atom.
    }

    // MARK: - Week Picker

    private var weekPicker: some View {
        NavigationStack {
            List {
                ForEach(viewModel.historyWeeks) { week in
                    Button {
                        viewModel.selectWeek(week)
                        showWeekPicker = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(week.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                
                                if let dateRange = week.dateRange {
                                    Text(dateRange)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Spacer()
                            
                            if let stats = week.stats {
                                Text("\(stats.releaseCount ?? 0) releases")
                                    .font(.caption)
                                    .foregroundColor(.xomifyGreen)
                            }
                            
                            if viewModel.isWeekSelected(week) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.xomifyGreen)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .background(Color.xomifyDark)
            .scrollContentBackground(.hidden)
            .navigationTitle("Select Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showWeekPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Week Release Count Extension

extension ReleaseRadarWeek {
    var releaseCount: Int? {
        stats?.releaseCount ?? releases?.count
    }
}

#Preview {
    ReleaseRadarView()
}
