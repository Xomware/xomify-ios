import SwiftUI

/// Playlist Analysis: pick a playlist -> local aggregation -> results.
struct PlaylistAnalysisView: View {

    @State private var viewModel = PlaylistAnalysisViewModel()

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            content
        }
        .navigationTitle("Playlist Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.playlists.isEmpty {
                await viewModel.loadPlaylists()
            }
        }
        .tint(Color.xomifyGreen)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isAnalyzing {
            VStack(spacing: 12) {
                XomifyLoaderPulse()
                Text("Analyzing \(viewModel.selectedPlaylist?.name ?? "playlist")...")
                    .font(.caption).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let analysis = viewModel.analysis {
            analysisResults(analysis)
        } else if viewModel.isLoadingPlaylists {
            XomifyLoaderPulse()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            errorState(error)
        } else {
            pickerList
        }
    }

    // MARK: - Playlist picker

    private var pickerList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Pick a playlist to analyze")
                    .font(.headline).foregroundColor(.white)
                    .padding(.top, 4)

                if viewModel.playlists.isEmpty {
                    Text("No playlists found.")
                        .font(.caption).foregroundColor(.gray)
                } else {
                    ForEach(viewModel.playlists) { playlist in
                        Button {
                            Task { await viewModel.analyze(playlist) }
                        } label: {
                            playlistRow(playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    private func playlistRow(_ playlist: SpotifyPlaylist) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: playlist.imageUrl) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
            .frame(width: 50, height: 50)
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(playlist.tracks?.total ?? 0) tracks")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    // MARK: - Results

    private func analysisResults(_ analysis: PlaylistAnalysis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let playlist = viewModel.selectedPlaylist {
                    heroHeader(playlist)
                }

                overviewGrid(analysis)

                if !analysis.sampleTracks.isEmpty {
                    sampleTracksSection(analysis.sampleTracks)
                }

                topArtistsSection(analysis.topArtists)
                topGenresSection(analysis.topGenres)
                decadesSection(analysis.decades)

                Button {
                    viewModel.analysis = nil
                    viewModel.selectedPlaylist = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Pick Another Playlist")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
            .padding()
        }
    }

    // MARK: Hero header

    private func heroHeader(_ playlist: SpotifyPlaylist) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: playlist.imageUrl) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    LinearGradient.xomifyGradient
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 180)

            VStack(alignment: .leading, spacing: 4) {
                Text("Analyzing")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.xomifyGreen)
                    .textCase(.uppercase)
                Text(playlist.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Overview tiles

    private func overviewGrid(_ analysis: PlaylistAnalysis) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metric(icon: "music.note", tint: .xomifyGreen, label: "Tracks", value: "\(analysis.totalTracks)")
            metric(icon: "clock", tint: .xomifyPurple, label: "Duration", value: viewModel.formattedDuration(analysis.totalDurationMs))
            metric(icon: "flame.fill", tint: .orange, label: "Avg Popularity", value: "\(analysis.avgPopularity)")
            metric(icon: "person.2.fill", tint: .xomifyGreen, label: "Unique Artists", value: "\(analysis.uniqueArtistCount)")
            metric(icon: "e.circle.fill", tint: .red, label: "Explicit", value: "\(analysis.explicitCount)")
        }
    }

    private func metric(icon: String, tint: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.xomifyCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    // MARK: Sample tracks

    private func sampleTracksSection(_ tracks: [SpotifyTrack]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Sample Tracks", symbol: "music.note")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(tracks) { track in
                        VStack(alignment: .leading, spacing: 6) {
                            AsyncImage(url: track.imageUrl) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default:
                                    LinearGradient.xomifyGradient
                                }
                            }
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Text(track.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(track.artistNames)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                        .frame(width: 120)
                    }
                }
            }
        }
    }

    // MARK: Top artists

    private func topArtistsSection(_ artists: [ArtistCount]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Top Artists", symbol: "person.2.fill")
            ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                HStack(spacing: 12) {
                    rankBadge(index + 1)
                    AsyncImage(url: artist.imageUrl) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: gradientFallback
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(artist.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(artist.count) \(artist.count == 1 ? "track" : "tracks")")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer(minLength: 0)

                    countPill(artist.count, tint: .xomifyGreen)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.xomifyCard)
                )
            }
        }
    }

    // MARK: Top genres

    private func topGenresSection(_ genres: [GenreCount]) -> some View {
        guard !genres.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Top Genres", symbol: "music.quarternote.3")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(genres, id: \.genre) { g in
                            HStack(spacing: 6) {
                                Text(g.genre.capitalized)
                                    .font(.caption.weight(.semibold))
                                Text("\(g.count)")
                                    .font(.caption2.monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(LinearGradient(
                                    colors: [Color.xomifyPurple.opacity(0.35), Color.xomifyGreen.opacity(0.25)],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                            )
                        }
                    }
                }
            }
        )
    }

    // MARK: Decades (horizontal bar)

    private func decadesSection(_ decades: [DecadeCount]) -> some View {
        guard !decades.isEmpty else { return AnyView(EmptyView()) }
        let maxCount = decades.map(\.count).max() ?? 1
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Decades", symbol: "calendar")
                VStack(spacing: 8) {
                    ForEach(decades, id: \.decade) { item in
                        HStack(spacing: 12) {
                            Text(item.decade)
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 52, alignment: .leading)

                            GeometryReader { geo in
                                let pct = CGFloat(item.count) / CGFloat(maxCount)
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.07))
                                    Capsule()
                                        .fill(LinearGradient.xomifyGradient)
                                        .frame(width: max(8, geo.size.width * pct))
                                }
                            }
                            .frame(height: 10)

                            Text("\(item.count)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.xomifyCard)
                        )
                    }
                }
            }
        )
    }

    // MARK: Shared bits

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.xomifyGreen)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(Color.xomifyGreen)
            .frame(width: 22, alignment: .center)
    }

    private func countPill(_ count: Int, tint: Color) -> some View {
        Text("\(count)")
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(tint.opacity(0.15))
            )
    }

    private var gradientFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.xomifyPurple.opacity(0.35), Color.xomifyGreen.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "person.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange.opacity(0.7))
            Text("Error").font(.headline).foregroundColor(.white)
            Text(message).font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.loadPlaylists() }
            } label: {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color.xomifyPurple)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack { PlaylistAnalysisView() }
}
