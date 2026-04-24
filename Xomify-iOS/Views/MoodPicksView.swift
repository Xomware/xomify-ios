import SwiftUI
import UIKit

/// Mood Picks: pick a mood -> fetch filtered top artists -> top tracks.
struct MoodPicksView: View {

    @State private var viewModel = MoodPicksViewModel()

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            VStack(spacing: 12) {
                BrandGradientHeader(
                    "Mood Picks",
                    subtitle: viewModel.selectedMood.map { "VIBE · \($0.rawValue.uppercased())" } ?? "PICK A VIBE, WE'LL BUILD THE LIST",
                    systemImage: "sparkles"
                )

                moodChips
                createPlaylistCTA
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Color.xomifyGreen)
    }

    // MARK: - Create playlist CTA

    @ViewBuilder
    private var createPlaylistCTA: some View {
        if !viewModel.tracks.isEmpty {
            VStack(spacing: 8) {
                Button {
                    Task { await viewModel.createPlaylistFromCurrentTracks() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isCreatingPlaylist {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "plus.square.on.square")
                        }
                        Text(viewModel.isCreatingPlaylist ? "Creating..." : "Create Playlist")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(LinearGradient.xomifyGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(viewModel.isCreatingPlaylist)
                .buttonStyle(.plain)
                .accessibilityHint("Saves the current list as a new Spotify playlist")

                if let url = viewModel.createdPlaylistUrl {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.xomifyGreen)
                            Text("Playlist created — open in Spotify")
                                .font(.caption)
                                .foregroundStyle(.white)
                            Image(systemName: "arrow.up.forward")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                } else if let err = viewModel.createPlaylistError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
        }
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

            TrackActionsMenu(track: track)
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
