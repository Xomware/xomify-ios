import SwiftUI

/// Composer sheet: Spotify track search → pick → caption/mood/genres/audience → Post.
/// Presented from the Feed tab's FAB.
struct ShareComposerView: View {

    @Bindable var viewModel: ShareComposerViewModel

    /// Called when a share is successfully submitted; caller should refresh the feed.
    let onSubmitted: (Share) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchSection

                    if let track = viewModel.selectedTrack {
                        selectedTrackRow(track)
                        captionSection
                        moodSection
                        genreSection
                        audienceSection
                    }

                    if let error = viewModel.submitError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(16)
            }
            .background(Color.xomifyDark.ignoresSafeArea())
            .navigationTitle("New Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.xomifyGreen)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Post").fontWeight(.semibold)
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .foregroundStyle(viewModel.canSubmit ? Color.xomifyGreen : Color.gray)
                }
            }
            .task { await viewModel.bootstrap() }
        }
    }

    // MARK: - Sections

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search Spotify")
                .font(.caption)
                .foregroundStyle(.gray)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.gray)
                TextField(
                    "",
                    text: $viewModel.searchQuery,
                    prompt: Text("Track name or artist").foregroundStyle(.gray)
                )
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: viewModel.searchQuery) { _, _ in
                    viewModel.search()
                }
                if viewModel.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
            .background(Color.xomifyCard)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if !viewModel.searchResults.isEmpty, viewModel.selectedTrack == nil {
                VStack(spacing: 6) {
                    ForEach(viewModel.searchResults) { track in
                        Button {
                            viewModel.selectTrack(track)
                        } label: {
                            searchResultRow(track)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func searchResultRow(_ track: SpotifyTrack) -> some View {
        HStack(spacing: 10) {
            if let url = track.imageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Color.xomifyPurple.opacity(0.3)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.xomifyPurple.opacity(0.3))
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artistNames)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.xomifyCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func selectedTrackRow(_ track: SpotifyTrack) -> some View {
        HStack(spacing: 12) {
            if let url = track.imageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Color.xomifyPurple.opacity(0.3)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.xomifyPurple.opacity(0.3))
                    .frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(track.artistNames)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                viewModel.clearSelectedTrack()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.gray)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change track")
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Caption")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                Text("\(viewModel.captionRemaining)")
                    .font(.caption2)
                    .foregroundStyle(viewModel.isCaptionValid ? .gray : Color.orange)
            }
            TextField(
                "",
                text: $viewModel.caption,
                prompt: Text("Say something about this track").foregroundStyle(.gray),
                axis: .vertical
            )
            .lineLimit(2...5)
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.xomifyCard)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mood")
                .font(.caption)
                .foregroundStyle(.gray)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MoodTag.allCases) { mood in
                        moodChip(mood)
                    }
                }
            }
        }
    }

    private func moodChip(_ mood: MoodTag) -> some View {
        let isSelected = viewModel.selectedMood == mood
        return Button {
            viewModel.selectedMood = isSelected ? nil : mood
        } label: {
            Text("\(mood.emoji) \(mood.displayName)")
                .font(.subheadline)
                .foregroundStyle(isSelected ? Color.black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(isSelected ? Color.xomifyGreen : Color.xomifyCard)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Genres")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                Text("\(viewModel.selectedGenres.count)/\(ShareComposerViewModel.maxGenreTags)")
                    .font(.caption2)
                    .foregroundStyle(viewModel.isGenreCountValid ? .gray : Color.orange)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShareComposerViewModel.genreSuggestions, id: \.self) { genre in
                        genreChip(genre)
                    }
                }
            }
        }
    }

    private func genreChip(_ genre: String) -> some View {
        let isSelected = viewModel.selectedGenres.contains(genre)
        let isAtCap = viewModel.selectedGenres.count >= ShareComposerViewModel.maxGenreTags && !isSelected

        return Button {
            viewModel.toggleGenre(genre)
        } label: {
            Text(genre)
                .font(.subheadline)
                .foregroundStyle(isSelected ? Color.black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(isSelected ? Color.xomifyGreen : Color.xomifyCard)
                .clipShape(Capsule())
                .opacity(isAtCap ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isAtCap)
    }

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Audience")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
                // Cosmetic disclosure — backend doesn't scope by audience at
                // write time yet (see plan Open Questions).
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .accessibilityLabel("Audience currently shown to anyone with access.")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    audienceChip(.all)
                    audienceChip(.friendsOnly)
                    ForEach(viewModel.availableGroups) { group in
                        audienceChip(.group(group))
                    }
                }
            }
        }
    }

    private func audienceChip(_ audience: ComposerAudience) -> some View {
        let isSelected = viewModel.selectedAudience == audience
        return Button {
            viewModel.selectedAudience = audience
        } label: {
            Text(audience.label)
                .font(.subheadline)
                .foregroundStyle(isSelected ? Color.black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(isSelected ? Color.xomifyGreen : Color.xomifyCard)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submit

    private func submit() async {
        if let share = await viewModel.submit() {
            onSubmitted(share)
            dismiss()
        }
    }
}
