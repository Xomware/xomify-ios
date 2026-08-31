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
                        ratingSection
                        moodSection
                        genreSection
                        targetsSection
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
                            ProgressView().tint(.white)
                        } else {
                            Text("Post").fontWeight(.semibold)
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .foregroundStyle(viewModel.canSubmit ? Color.xomifyGreen : Color.white.opacity(0.5))
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
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.5))
                TextField(
                    "",
                    text: $viewModel.searchQuery,
                    prompt: Text("Track name or artist").foregroundStyle(.white.opacity(0.5))
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
            .clipShape(RoundedRectangle(cornerRadius: XomRadius.lg, style: .continuous))

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
                .clipShape(RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: XomRadius.md)
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
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.xomifyCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous))
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
                .clipShape(RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: XomRadius.md)
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
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                viewModel.clearSelectedTrack()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change track")
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: XomRadius.xl, style: .continuous))
    }

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Caption")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(viewModel.captionRemaining)")
                    .font(.caption2)
                    .foregroundStyle(viewModel.isCaptionValid ? .white.opacity(0.5) : Color.orange)
            }
            TextField(
                "",
                text: $viewModel.caption,
                prompt: Text("Say something about this track").foregroundStyle(.white.opacity(0.5)),
                axis: .vertical
            )
            .lineLimit(2...5)
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.xomifyCard)
            .clipShape(RoundedRectangle(cornerRadius: XomRadius.lg, style: .continuous))
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rate this track")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if viewModel.selectedRating != nil {
                    Button("Clear") {
                        viewModel.selectedRating = nil
                    }
                    .font(.caption)
                    .foregroundStyle(Color.xomifyGreen)
                }
            }
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        if viewModel.selectedRating == star {
                            viewModel.selectedRating = nil
                        } else {
                            viewModel.selectedRating = star
                        }
                    } label: {
                        Image(systemName: (viewModel.selectedRating ?? 0) >= star ? "star.fill" : "star")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                (viewModel.selectedRating ?? 0) >= star
                                    ? Color.xomifyGreen
                                    : Color.white.opacity(0.4)
                            )
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
            }
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mood")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

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
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(viewModel.selectedGenres.count)/\(ShareComposerViewModel.maxGenreTags)")
                    .font(.caption2)
                    .foregroundStyle(viewModel.isGenreCountValid ? .white.opacity(0.5) : Color.orange)
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

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Post to")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(viewModel.targetSummary)
                    .font(.caption2)
                    .foregroundStyle(viewModel.targetState == .ok ? .white.opacity(0.5) : Color.orange)
            }

            publicToggleRow

            if let hint = viewModel.targetState.hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private var publicToggleRow: some View {
        Button {
            viewModel.shareToPublic.toggle()
        } label: {
            HStack(spacing: 12) {
                checkbox(isOn: viewModel.shareToPublic)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friends feed")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text("Anyone who follows you")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "globe")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(12)
            .frame(minHeight: 44)
            .background(Color.xomifyCard)
            .clipShape(RoundedRectangle(cornerRadius: XomRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(viewModel.shareToPublic ? .isSelected : [])
        .accessibilityLabel(viewModel.shareToPublic ? "Friends feed selected" : "Friends feed")
    }

    private func checkbox(isOn: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous)
                .fill(isOn ? Color.xomifyGreen : Color.clear)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous)
                        .stroke(isOn ? Color.xomifyGreen : Color.white.opacity(0.3), lineWidth: 1.5)
                )
            if isOn {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.black)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Submit

    private func submit() async {
        if let share = await viewModel.submit() {
            onSubmitted(share)
            dismiss()
        }
    }
}
