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
            VStack(alignment: .leading, spacing: 20) {
                if let playlist = viewModel.selectedPlaylist {
                    HStack(spacing: 12) {
                        AsyncImage(url: playlist.imageUrl) { image in
                            image.resizable()
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 64, height: 64)
                        .cornerRadius(8)

                        Text(playlist.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }

                overviewGrid(analysis)

                section(title: "Top Artists", rows: analysis.topArtists.map { "\($0.name) — \($0.count)" })
                section(title: "Top Genres",  rows: analysis.topGenres.map { "\($0.genre) — \($0.count)" })
                section(title: "Decades",     rows: analysis.decades.map { "\($0.decade) — \($0.count)" })

                Button {
                    viewModel.analysis = nil
                    viewModel.selectedPlaylist = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Pick Another Playlist")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
                .padding(.top)
            }
            .padding()
        }
    }

    private func overviewGrid(_ analysis: PlaylistAnalysis) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metric(label: "Tracks", value: "\(analysis.totalTracks)")
            metric(label: "Duration", value: viewModel.formattedDuration(analysis.totalDurationMs))
            metric(label: "Avg Popularity", value: "\(analysis.avgPopularity)")
            metric(label: "Unique Artists", value: "\(analysis.uniqueArtistCount)")
            metric(label: "Explicit", value: "\(analysis.explicitCount)")
        }
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.gray)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    @ViewBuilder
    private func section(title: String, rows: [String]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline).foregroundColor(.white)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row)
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.xomifyCard)
                    .cornerRadius(8)
                }
            }
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
