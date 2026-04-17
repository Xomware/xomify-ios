import SwiftUI

/// Renders a single Share in the feed.
struct ShareCardView: View {

    let share: Share
    let viewerReaction: ReactionAction?
    /// Called when the viewer taps a reaction. Tapping the current reaction removes it.
    let onReact: (ReactionAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            contentForType
            if let caption = share.caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            reactionBar
        }
        .padding(14)
        .background(Color.xomifyCard)
        .cornerRadius(14)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            // Avatar placeholder: gradient circle with first initial
            ZStack {
                Circle()
                    .fill(LinearGradient.xomifyGradient)
                    .frame(width: 36, height: 36)
                Text(String(share.email.prefix(1)).uppercased())
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(share.email)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    typeBadge
                    Text(share.relativeTime)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
    }

    private var typeBadge: some View {
        Text(typeDisplay)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(typeColor.opacity(0.2))
            .foregroundColor(typeColor)
            .cornerRadius(4)
    }

    private var typeDisplay: String {
        switch share.type {
        case .wrapped: return "WRAPPED"
        case .releaseRadar: return "RELEASE RADAR"
        case .track: return "TRACK"
        case .playlist: return "PLAYLIST"
        }
    }

    private var typeColor: Color {
        switch share.type {
        case .wrapped, .playlist: return .xomifyPurple
        case .releaseRadar, .track: return .xomifyGreen
        }
    }

    // MARK: - Content per type

    @ViewBuilder
    private var contentForType: some View {
        switch share.type {
        case .wrapped:
            wrappedContent
        case .releaseRadar:
            releaseRadarContent
        case .track:
            trackContent
        case .playlist:
            playlistContent
        }
    }

    private var wrappedContent: some View {
        let month = stringPayload(keys: ["month", "displayName"]) ?? "Monthly Wrap"
        let tracks = arrayPayload(keys: ["topTracks", "top_tracks"]) ?? []

        return VStack(alignment: .leading, spacing: 8) {
            Text(month)
                .font(.headline)
                .foregroundColor(.white)

            if tracks.isEmpty {
                Text("Top tracks")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(tracks.prefix(5).enumerated()), id: \.offset) { index, item in
                        trackLine(index: index + 1, item: item)
                    }
                }
            }
        }
    }

    private var releaseRadarContent: some View {
        let weekLabel = stringPayload(keys: ["weekLabel", "weekDisplay", "week_label"]) ?? "Release Radar"
        let releases = arrayPayload(keys: ["topReleases", "top_releases", "releases"]) ?? []

        return VStack(alignment: .leading, spacing: 8) {
            Text(weekLabel)
                .font(.headline)
                .foregroundColor(.white)

            if releases.isEmpty {
                Text("New releases")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(releases.prefix(5).enumerated()), id: \.offset) { index, item in
                        releaseLine(index: index + 1, item: item)
                    }
                }
            }
        }
    }

    private var trackContent: some View {
        let name = stringPayload(keys: ["name", "trackName", "track_name"]) ?? "Track"
        let artist = stringPayload(keys: ["artist", "artistName", "artist_name", "artists"])

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.xomifyPurple.opacity(0.3))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundColor(.xomifyPurple)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let artist = artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var playlistContent: some View {
        let name = stringPayload(keys: ["name", "playlistName", "playlist_name"]) ?? "Playlist"
        let trackCount = intPayload(keys: ["trackCount", "track_count", "count"])

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.xomifyGreen.opacity(0.3))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "music.note.list")
                        .foregroundColor(.xomifyGreen)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let trackCount = trackCount {
                    Text("\(trackCount) tracks")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Spacer()
        }
    }

    // MARK: - Line rows

    private func trackLine(index: Int, item: JSONValue) -> some View {
        let (title, subtitle) = titleSubtitle(from: item, titleKeys: ["name", "trackName", "track_name"], subtitleKeys: ["artist", "artistName", "artist_name", "artists"])
        return lineRow(index: index, title: title ?? "Track \(index)", subtitle: subtitle)
    }

    private func releaseLine(index: Int, item: JSONValue) -> some View {
        let (title, subtitle) = titleSubtitle(from: item, titleKeys: ["albumName", "album_name", "name"], subtitleKeys: ["artistName", "artist_name", "artist"])
        return lineRow(index: index, title: title ?? "Release \(index)", subtitle: subtitle)
    }

    private func lineRow(index: Int, title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(index)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.xomifyGreen)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    // MARK: - Reaction Bar

    private var reactionBar: some View {
        HStack(spacing: 12) {
            reactionButton(.fire, label: "🔥")
            reactionButton(.love, label: "❤️")
            reactionButton(.like, label: "👍")
            Spacer()
        }
        .padding(.top, 4)
    }

    private func reactionButton(_ action: ReactionAction, label: String) -> some View {
        let isActive = viewerReaction == action
        let count = share.count(for: action)

        return Button {
            // Toggle: if already active, send .none to remove. Otherwise set.
            onReact(isActive ? .none : action)
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.subheadline)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isActive ? .white : .gray)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.xomifyPurple.opacity(0.3) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? Color.xomifyPurple : Color.clear, lineWidth: 1)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Payload helpers

    private func stringPayload(keys: [String]) -> String? {
        guard let payload = share.payload else { return nil }
        for key in keys {
            if let value = payload[key]?.stringValue { return value }
        }
        return nil
    }

    private func intPayload(keys: [String]) -> Int? {
        guard let payload = share.payload else { return nil }
        for key in keys {
            if let value = payload[key]?.intValue { return value }
        }
        return nil
    }

    private func arrayPayload(keys: [String]) -> [JSONValue]? {
        guard let payload = share.payload else { return nil }
        for key in keys {
            if let value = payload[key]?.arrayValue { return value }
        }
        return nil
    }

    /// Try to extract a title/subtitle from a payload item that might be a string or an object.
    private func titleSubtitle(
        from item: JSONValue,
        titleKeys: [String],
        subtitleKeys: [String]
    ) -> (String?, String?) {
        if let s = item.stringValue {
            return (s, nil)
        }
        if let obj = item.objectValue {
            var title: String?
            for key in titleKeys {
                if let v = obj[key]?.stringValue { title = v; break }
            }
            var subtitle: String?
            for key in subtitleKeys {
                if let v = obj[key]?.stringValue { subtitle = v; break }
            }
            return (title, subtitle)
        }
        return (nil, nil)
    }
}
