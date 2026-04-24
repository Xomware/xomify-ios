import SwiftUI

/// Mood Picks: pick a mood -> fetch filtered top artists -> top tracks.
struct MoodPicksView: View {

    @State private var viewModel = MoodPicksViewModel()

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            VStack(spacing: 12) {
                moodChips
                content
            }
        }
        .navigationTitle("Mood Picks")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.xomifyGreen)
    }

    // MARK: - Chips

    private var moodChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MoodType.allCases) { mood in
                    Button {
                        Task { await viewModel.selectMood(mood) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(mood.emoji)
                            Text(mood.rawValue)
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            viewModel.selectedMood == mood
                                ? AnyShapeStyle(LinearGradient.xomifyGradient)
                                : AnyShapeStyle(Color.white.opacity(0.08))
                        )
                        .foregroundColor(.white)
                        .cornerRadius(18)
                    }
                    .disabled(viewModel.isLoading)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            VStack(spacing: 10) {
                XomifyLoaderPulse()
                Text("Building your \(viewModel.selectedMood?.rawValue ?? "") picks...")
                    .font(.caption).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            errorState(error)
        } else if viewModel.selectedMood == nil {
            emptyPrompt
        } else if viewModel.tracks.isEmpty {
            noMatches
        } else {
            tracksList
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            Text("Pick a mood").font(.headline).foregroundColor(.white)
            Text("We'll build a list of songs from your top artists that match the vibe.")
                .font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatches: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            Text("No matching songs").font(.headline).foregroundColor(.white)
            Text("Your top artists don't quite match this mood. Try another one.")
                .font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tracksList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.tracks) { track in
                    trackRow(track)
                }
            }
            .padding()
        }
    }

    private func trackRow(_ track: SpotifyTrack) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.imageUrl) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
            .frame(width: 50, height: 50)
            .cornerRadius(6)

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

            QueueButton(
                uri: track.uri ?? "spotify:track:\(track.id)",
                trackName: track.name
            )

            if let urlString = track.externalUrls?["spotify"], let url = URL(string: urlString) {
                Link(destination: url) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.xomifyGreen)
                }
            }
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange.opacity(0.7))
            Text("Error").font(.headline).foregroundColor(.white)
            Text(message).font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack { MoodPicksView() }
}
