import SwiftUI

/// Single card in the feed. Owns its own `ShareCardViewModel` so queue/rate
/// state is local to the card — the parent feed never sees optimistic flips.
struct ShareCardView: View {

    @State private var viewModel: ShareCardViewModel
    @State private var showRateSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false

    /// Live viewer email plumbed from the parent feed. Held as a view-level
    /// `let` (not just stashed in the VM at init) because the parent resolves
    /// the email asynchronously — when it later flips from `""` → real value,
    /// SwiftUI re-renders this view and the `.task(id:)` below re-syncs it
    /// into the VM so own-post detection and write paths actually work.
    let viewerEmail: String

    /// Resolved sharer identity (display name + avatar). Falls back to the
    /// email when unresolved — `FeedViewModel.identity(for:)` always returns
    /// a value, so the fallback tree is handled upstream.
    let sharerIdentity: SharerIdentity

    /// Optional callback fired when the viewer confirms deletion of their
    /// own post. When `nil` (or the share wasn't authored by the viewer)
    /// the delete menu entry is hidden.
    let onDelete: (() -> Void)?

    /// Optional callback fired when the viewer taps the card body (avatar,
    /// text, or album art — but NOT the action buttons). Wrapping the whole
    /// card in a NavigationLink swallows taps on the inner action buttons,
    /// so navigation is wired through this callback and the caller handles
    /// the push via `navigationDestination(item:)`.
    let onOpenDetail: (() -> Void)?

    init(
        share: Share,
        viewerEmail: String,
        sharerIdentity: SharerIdentity,
        onDelete: (() -> Void)? = nil,
        onOpenDetail: (() -> Void)? = nil
    ) {
        self.viewerEmail = viewerEmail
        _viewModel = State(initialValue: ShareCardViewModel(
            share: share,
            viewerEmail: viewerEmail
        ))
        self.sharerIdentity = sharerIdentity
        self.onDelete = onDelete
        self.onOpenDetail = onOpenDetail
    }

    private var isOwnPost: Bool {
        !viewerEmail.isEmpty && viewModel.share.sharedBy == viewerEmail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailTapZone
            actionRow
            if let error = viewModel.queueError {
                errorBanner(error)
            }
            if let error = viewModel.reactError {
                errorBanner(error)
            }
        }
        .padding(14)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: viewerEmail) {
            // Parent feed resolves `userEmail` asynchronously; once it lands,
            // re-sync the VM so write paths and own-post detection use the
            // real email instead of the empty string captured at init.
            viewModel.viewerEmail = viewerEmail
        }
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

    // MARK: - Tap zone

    /// Groups the non-interactive parts of the card (sharer, track, caption,
    /// tags) into a single accessible button so tapping the body opens the
    /// detail view. The action row below stays outside this button, so
    /// queue/rate/delete still fire normally.
    @ViewBuilder
    private var detailTapZone: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if let onOpenDetail {
            Button(action: onOpenDetail) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityHint("Double-tap to open post details")
        } else {
            content
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

            // Suppress on own posts -- the actions row already shows the
            // viewer's myRating chip, which is the same value here.
            if !isOwnPost, let rating = viewModel.share.sharerRating {
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
        }
    }

    /// Synthesize a minimal `SpotifyTrack` from the share so the shared
    /// `TrackActionsMenu` can drive play / queue / playlist-builder /
    /// share-to-feed without a round-trip to `/v1/tracks`. Mirrors the
    /// helper in `ShareDetailView`.
    private func makeTrackForActions() -> SpotifyTrack {
        let images: [SpotifyImage] = {
            guard let url = viewModel.share.albumArtUrl, !url.isEmpty else { return [] }
            return [SpotifyImage(url: url, height: nil, width: nil)]
        }()
        let album = SpotifyAlbum(
            id: "",
            name: viewModel.share.albumName ?? "",
            uri: nil,
            albumType: nil,
            totalTracks: nil,
            releaseDate: nil,
            releaseDatePrecision: nil,
            images: images,
            artists: nil,
            externalUrls: nil
        )
        let artist = SpotifyArtist(
            id: nil,
            name: viewModel.share.artistName,
            uri: nil,
            genres: nil,
            popularity: nil,
            followers: nil,
            images: nil,
            externalUrls: nil
        )
        return SpotifyTrack(
            id: viewModel.share.trackId,
            name: viewModel.share.trackName,
            uri: viewModel.share.trackUri,
            durationMs: 0,
            explicit: nil,
            popularity: nil,
            previewUrl: nil,
            album: album,
            artists: [artist],
            externalUrls: nil
        )
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

    /// Single icon-first row holding every front-of-card action so labels
    /// never wrap. The `Queue` shortcut moved into the Actions menu and the
    /// reaction bar (smiley + active pills) sits inline next to comment so
    /// users don't have to scan a separate row to react.
    /// Order: Actions ⋯ → Rate ☆ → 💬 N → 😊 reactions → friend-queued chip.
    private var actionRow: some View {
        HStack(spacing: 8) {
            TrackActionsMenu(
                track: makeTrackForActions(),
                style: .icon,
                onDelete: (isOwnPost && onDelete != nil) ? { showDeleteConfirm = true } : nil,
                shareId: viewModel.share.shareId,
                onListened: { viewModel.markListenedOptimistically() }
            )
            rateButton
            commentButton
            ReactionsBar(
                counts: viewModel.share.reactionCounts,
                viewerReactions: viewModel.share.viewerReactions,
                inFlightSlugs: viewModel.reactingSlugs,
                onToggle: { reaction in
                    Task { await viewModel.toggleReaction(reaction) }
                }
            )
            Spacer(minLength: 0)
            if !viewModel.share.viewerHasListened && !isOwnPost {
                notHeardBadge
            }
            if viewModel.displayedQueueCount > 0 {
                queueCountChip
            }
        }
    }

    /// Visual hint that the viewer has never queued or played this share.
    /// Backed by `share.viewerHasListened` (server-enriched, optimistically
    /// flipped on Play / Queue tap). Suppressed on the viewer's own posts —
    /// the backend backfill marks the author as listened, but local
    /// optimistic copies (composer prepend) won't have it set yet.
    private var notHeardBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "headphones")
                .font(.caption2)
            Text("Not heard")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(Color.xomifyPurple)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.xomifyPurple.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityLabel("You haven't listened to this yet")
    }

    /// Compact comment-thread shortcut. Mirrors how Instagram/Twitter surface
    /// reply counts on a card — tap goes to detail (which auto-loads comments).
    private var commentButton: some View {
        Button {
            onOpenDetail?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                    .font(.subheadline)
                if viewModel.share.commentCount > 0 {
                    Text("\(viewModel.share.commentCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(viewModel.share.commentCount) comments. Tap to open.")
    }

    private var rateButton: some View {
        Button {
            showRateSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.myRating != nil ? "star.fill" : "star")
                    .font(.subheadline)
                if let rating = viewModel.myRating {
                    Text("\(rating)/5")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(viewModel.myRating != nil ? Color.xomifyGreen : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
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
                            // Keep the sheet open on failure so the inline
                            // error below stays visible; only dismiss on success.
                            if viewModel.rateError == nil {
                                isPresented = false
                            }
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
