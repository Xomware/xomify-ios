import SwiftUI

/// Single card in the feed. Owns its own `ShareCardViewModel` so queue/rate
/// state is local to the card — the parent feed never sees optimistic flips.
struct ShareCardView: View {

    @State private var viewModel: ShareCardViewModel
    @State private var showRateSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false

    /// Resolved sharer identity (display name + avatar). Falls back to the
    /// email when unresolved — `FeedViewModel.identity(for:)` always returns
    /// a value, so the fallback tree is handled upstream.
    let sharerIdentity: SharerIdentity

    /// Optional callback fired when the viewer confirms deletion of their
    /// own post. When `nil` (or the share wasn't authored by the viewer)
    /// the delete menu entry is hidden.
    let onDelete: (() -> Void)?

    init(
        share: Share,
        viewerEmail: String,
        sharerIdentity: SharerIdentity,
        onDelete: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: ShareCardViewModel(
            share: share,
            viewerEmail: viewerEmail
        ))
        self.sharerIdentity = sharerIdentity
        self.onDelete = onDelete
    }

    private var isOwnPost: Bool {
        viewModel.share.sharedBy == viewModel.viewerEmail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sharerRow
            trackBlock
            if let caption = viewModel.share.caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if viewModel.share.moodTag != nil || !(viewModel.share.genreTags ?? []).isEmpty {
                tagsRow
            }
            actionRow
            if let error = viewModel.queueError {
                errorBanner(error)
            }
        }
        .padding(14)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $showRateSheet) {
            RateSheet(viewModel: viewModel, isPresented: $showRateSheet)
                .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Delete this post?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove your share from the feed. This can't be undone.")
        }
    }

    // MARK: - Sharer row

    private var sharerRow: some View {
        HStack(spacing: 10) {
            avatarView
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(sharerIdentity.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(viewModel.share.relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            Spacer()

            if let rating = viewModel.share.sharerRating {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.xomifyGreen)
                    Text("\(rating)/5")
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .accessibilityLabel("\(sharerIdentity.displayName) rated this \(rating) out of 5")
            }

            if isOwnPost, onDelete != nil {
                ownPostMenu
            }
        }
    }

    private var ownPostMenu: some View {
        Menu {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete post", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Post options")
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = sharerIdentity.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarFallback
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(LinearGradient.xomifyGradient)
                .frame(width: 36, height: 36)
            Text(String(sharerIdentity.displayName.prefix(1)).uppercased())
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Track block

    private var trackBlock: some View {
        HStack(spacing: 12) {
            albumArt
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.share.trackName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(viewModel.share.artistName)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                if let albumName = viewModel.share.albumName, !albumName.isEmpty {
                    Text(albumName)
                        .font(.caption2)
                        .foregroundStyle(.gray.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var albumArt: some View {
        if let url = viewModel.share.albumArt {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholderArt
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholderArt
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var placeholderArt: some View {
        Color.xomifyPurple.opacity(0.25)
            .overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(Color.xomifyPurple)
            )
    }

    // MARK: - Tags

    private var tagsRow: some View {
        HStack(spacing: 6) {
            if let mood = viewModel.share.moodTag {
                tagPill(label: "\(mood.emoji) \(mood.displayName)", tint: Color.xomifyPurple)
            }
            ForEach(viewModel.share.genreTags ?? [], id: \.self) { genre in
                tagPill(label: genre, tint: Color.xomifyGreen)
            }
        }
    }

    private func tagPill(label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 10) {
            queueButton
            rateButton
            Spacer()
            if viewModel.displayedQueueCount > 0 {
                queueCountChip
            }
        }
    }

    private var queueButton: some View {
        Button {
            Task { await viewModel.queue() }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isQueuing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: viewModel.queuedLocally ? "checkmark.circle.fill" : "text.badge.plus")
                }
                Text(viewModel.queuedLocally ? "Queued" : "Queue")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(viewModel.queuedLocally ? Color.xomifyGreen.opacity(0.25) : Color.xomifyPurple)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isQueuing)
        .accessibilityLabel(viewModel.queuedLocally ? "Queued on Spotify" : "Queue on Spotify")
    }

    private var rateButton: some View {
        Button {
            showRateSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.myRating != nil ? "star.fill" : "star")
                Text(viewModel.myRating.map { "\($0)/5" } ?? "Rate")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(viewModel.myRating != nil ? Color.xomifyGreen : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.myRating.map { "Rated \($0) out of 5. Tap to change." } ?? "Rate this track")
    }

    private var queueCountChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.caption2)
            Text("\(viewModel.displayedQueueCount)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.gray)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityLabel("\(viewModel.displayedQueueCount) friends queued this")
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption2)
            .foregroundStyle(Color.orange)
            .padding(.top, 2)
    }
}

// MARK: - Rate Sheet

private struct RateSheet: View {
    @Bindable var viewModel: ShareCardViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Rate this track")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(viewModel.share.trackName)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            .padding(.top, 24)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { stars in
                    Button {
                        Task {
                            await viewModel.rate(stars)
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: (viewModel.myRating ?? 0) >= stars ? "star.fill" : "star")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.xomifyGreen)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(stars) star\(stars == 1 ? "" : "s")")
                }
            }

            if let error = viewModel.rateError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.xomifyDark)
    }
}
