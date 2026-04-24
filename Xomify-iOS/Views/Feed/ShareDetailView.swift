import SwiftUI

/// Detail screen for a single feed share. Pushed from the Feed and
/// profile Shares tab when the user taps a card.
///
/// Renders the full track context — big hero art, sharer's rating and
/// caption, aggregate listener/rating stats, and the shared
/// `TrackActionsMenu` so every playback + playlist + share action is
/// available from one place. Friend-by-friend ratings and a listener
/// list land when the backend endpoints for those are in place; for now
/// the aggregate counts keep the view useful.
struct ShareDetailView: View {

    let share: Share
    let viewerEmail: String
    let sharerIdentity: SharerIdentity

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
                    if let caption = share.caption, !caption.isEmpty {
                        captionBlock(caption)
                    }
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.xomifyGreen)
    }

    // MARK: - Hero art

    @ViewBuilder
    private var heroArt: some View {
        if let url = share.albumArt {
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
            Text(share.trackName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(3)
            Text(share.artistName)
                .font(.subheadline)
                .foregroundStyle(.gray)
                .lineLimit(2)
            if let album = share.albumName, !album.isEmpty {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.75))
                    .lineLimit(1)
            }
            if share.moodTag != nil || !(share.genreTags ?? []).isEmpty {
                tagsRow
                    .padding(.top, 4)
            }
        }
    }

    private var tagsRow: some View {
        HStack(spacing: 6) {
            if let mood = share.moodTag {
                tagPill(label: "\(mood.emoji) \(mood.displayName)", tint: Color.xomifyPurple)
            }
            ForEach(share.genreTags ?? [], id: \.self) { genre in
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
            avatarView
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shared by \(sharerIdentity.displayName)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(share.relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            Spacer(minLength: 8)

            if let rating = share.sharerRating {
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
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(LinearGradient.xomifyGradient)
                .frame(width: 40, height: 40)
            Text(String(sharerIdentity.displayName.prefix(1)).uppercased())
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(
                value: "\(share.queuedCount)",
                label: share.queuedCount == 1 ? "friend queued" : "friends queued",
                icon: "text.badge.plus"
            )
            statCard(
                value: "\(share.ratedCount)",
                label: share.ratedCount == 1 ? "friend rated" : "friends rated",
                icon: "star"
            )
            if let mine = share.viewerRating {
                statCard(
                    value: "\(mine)/5",
                    label: "your rating",
                    icon: "star.fill"
                )
            } else if share.viewerHasQueued {
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
            Spacer()
        }
    }

    /// Synthesize a minimal `SpotifyTrack` from the Share so the shared
    /// `TrackActionsMenu` can drive play / queue / playlist-builder /
    /// share-to-feed without a round-trip to `/v1/tracks`.
    private func makeTrackForActions() -> SpotifyTrack {
        let images: [SpotifyImage] = {
            guard let url = share.albumArtUrl, !url.isEmpty else { return [] }
            return [SpotifyImage(url: url, height: nil, width: nil)]
        }()
        let album = SpotifyAlbum(
            id: "",
            name: share.albumName ?? "",
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
            name: share.artistName,
            uri: nil,
            genres: nil,
            popularity: nil,
            followers: nil,
            images: nil,
            externalUrls: nil
        )
        return SpotifyTrack(
            id: share.trackId,
            name: share.trackName,
            uri: share.trackUri,
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
}
