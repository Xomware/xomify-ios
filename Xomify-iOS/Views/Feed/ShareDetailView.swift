import SwiftUI

/// Detail screen for a single feed share. Pushed from the Feed and profile
/// Shares tab when the user taps a card.
///
/// Loads `/shares/detail` on appear so the listener + friend-rating lists are
/// always fresh. Hero + track header render immediately from the pushed
/// `Share` so there's no flash-of-empty while the detail load is in flight.
///
/// Rating lives here as well — the detail screen is a first-class rating
/// surface, not just a read-only expansion of the card.
struct ShareDetailView: View {

    @State private var viewModel: ShareDetailViewModel
    @State private var showRateSheet: Bool = false

    let sharerIdentity: SharerIdentity

    init(share: Share, viewerEmail: String, sharerIdentity: SharerIdentity) {
        _viewModel = State(initialValue: ShareDetailViewModel(
            share: share,
            viewerEmail: viewerEmail
        ))
        self.sharerIdentity = sharerIdentity
    }

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroArt
                    trackHeader
                    sharerBlock
                    statsRow
                    actionRow
                    if let caption = viewModel.share.caption, !caption.isEmpty {
                        captionBlock(caption)
                    }
                    friendRatingsSection
                    listenersSection
                    if let error = viewModel.errorMessage {
                        inlineErrorBanner(error)
                    }
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.xomifyGreen)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(isPresented: $showRateSheet) {
            DetailRateSheet(viewModel: viewModel, isPresented: $showRateSheet)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Hero art

    @ViewBuilder
    private var heroArt: some View {
        if let url = viewModel.share.albumArt {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholderArt
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 16))
        } else {
            placeholderArt
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 16))
        }
    }

    private var placeholderArt: some View {
        Color.xomifyPurple.opacity(0.25)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.xomifyPurple)
            )
    }

    // MARK: - Track header

    private var trackHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.share.trackName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(3)
            Text(viewModel.share.artistName)
                .font(.subheadline)
                .foregroundStyle(.gray)
                .lineLimit(2)
            if let album = viewModel.share.albumName, !album.isEmpty {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.75))
                    .lineLimit(1)
            }
            if viewModel.share.moodTag != nil || !(viewModel.share.genreTags ?? []).isEmpty {
                tagsRow
                    .padding(.top, 4)
            }
        }
    }

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

    // MARK: - Sharer block

    private var sharerBlock: some View {
        HStack(spacing: 12) {
            avatarView(url: sharerIdentity.avatarURL, initial: sharerIdentity.displayName.prefix(1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shared by \(sharerIdentity.displayName)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(viewModel.share.relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Spacer(minLength: 8)

            if let rating = viewModel.share.sharerRating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Color.xomifyGreen)
                    Text("\(rating)/5")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .accessibilityLabel("\(sharerIdentity.displayName) rated this \(rating) out of 5")
            }
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(
                value: "\(viewModel.share.queuedCount)",
                label: viewModel.share.queuedCount == 1 ? "friend queued" : "friends queued",
                icon: "text.badge.plus"
            )
            statCard(
                value: "\(viewModel.share.ratedCount)",
                label: viewModel.share.ratedCount == 1 ? "friend rated" : "friends rated",
                icon: "star"
            )
            if let mine = viewModel.myRating {
                statCard(
                    value: "\(mine)/5",
                    label: "your rating",
                    icon: "star.fill"
                )
            } else if viewModel.share.viewerHasQueued {
                statCard(
                    value: "✓",
                    label: "in your queue",
                    icon: "checkmark.circle.fill"
                )
            }
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.xomifyGreen)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .padding(10)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 12) {
            TrackActionsMenu(track: makeTrackForActions(), style: .pill)
            rateButton
            Spacer()
        }
    }

    private var rateButton: some View {
        Button {
            showRateSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.myRating != nil ? "star.fill" : "star")
                Text(viewModel.myRating.map { "\($0)/5" } ?? "Rate")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(viewModel.myRating != nil ? Color.xomifyGreen : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.myRating.map { "You rated this \($0) out of 5. Tap to change." } ?? "Rate this track")
    }

    /// Synthesize a minimal `SpotifyTrack` from the Share so the shared
    /// `TrackActionsMenu` can drive play / queue / playlist-builder /
    /// share-to-feed without a round-trip to `/v1/tracks`.
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

    // MARK: - Caption

    private func captionBlock(_ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note from \(sharerIdentity.displayName)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.xomifyGreen)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Friend ratings

    @ViewBuilder
    private var friendRatingsSection: some View {
        if !viewModel.sortedFriendRatings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "What friends think",
                    icon: "star.bubble",
                    count: viewModel.sortedFriendRatings.count
                )
                VStack(spacing: 8) {
                    ForEach(viewModel.sortedFriendRatings) { rating in
                        friendRatingRow(rating)
                    }
                }
            }
        } else if viewModel.isLoading {
            sectionPlaceholder(message: "Loading friend ratings…")
        }
    }

    private func friendRatingRow(_ rating: ShareFriendRating) -> some View {
        HStack(spacing: 12) {
            avatarView(url: rating.avatarURL, initial: rating.resolvedName.prefix(1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(rating.resolvedName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let review = rating.review, !review.isEmpty {
                    Text(review)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            starBadge(rating.displayStars)
        }
        .padding(10)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rating.resolvedName) rated this \(rating.displayStars) out of 5")
    }

    private func starBadge(_ stars: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(Color.xomifyGreen)
            Text("\(stars)/5")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: - Listeners

    @ViewBuilder
    private var listenersSection: some View {
        if !viewModel.listeners.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "Listeners",
                    icon: "headphones",
                    count: viewModel.listeners.count
                )
                VStack(spacing: 6) {
                    ForEach(viewModel.listeners) { listener in
                        listenerRow(listener)
                    }
                }
            }
        } else if viewModel.isLoading {
            sectionPlaceholder(message: "Loading listeners…")
        }
    }

    private func listenerRow(_ entry: ShareInteractionEntry) -> some View {
        HStack(spacing: 12) {
            avatarView(url: entry.avatarURL, initial: entry.resolvedName.prefix(1))
                .accessibilityHidden(true)
            Text(entry.resolvedName)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "text.badge.plus")
                .font(.caption2)
                .foregroundStyle(Color.xomifyGreen)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 10))
    }

    // MARK: - Shared helpers

    private func sectionHeader(title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.xomifyGreen)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.gray)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }

    private func sectionPlaceholder(message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.xomifyGreen)
            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.xomifyCard.opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func inlineErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func avatarView(url: URL?, initial: Substring) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarFallback(initial: initial)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            avatarFallback(initial: initial)
        }
    }

    private func avatarFallback(initial: Substring) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient.xomifyGradient)
                .frame(width: 36, height: 36)
            Text(String(initial).uppercased())
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Rate sheet (detail)

/// Mirrors `ShareCardView`'s `RateSheet` but binds to `ShareDetailViewModel`
/// instead of `ShareCardViewModel`. Shared UI would be ideal but the two VMs
/// have different surfaces; inlining keeps the dependency graph flat.
private struct DetailRateSheet: View {
    @Bindable var viewModel: ShareDetailViewModel
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
