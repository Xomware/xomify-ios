import SwiftUI
import UIKit

/// Taste tab on `ProfileView`. Compact summary — top 3 of each category per
/// term — with a "See all" CTA that jumps to the full `Music Taste` drawer
/// destination (`TopItemsView`). Keeps the profile lightweight and steers
/// users to the richer surface.
///   `.me`    → fetches from `TopItemsViewModel` once on first appear.
///   `.other` → renders degraded text tiles from the already-loaded
///              `FriendProfile` payload; empty-bucket fallback per contract.
struct ProfileTasteTab: View {

    let viewModel: UserProfileViewModel
    @Environment(NavigationStore.self) private var navStore

    var body: some View {
        switch viewModel.context {
        case .me:
            SelfTasteSummary(onSeeAll: { navStore.select(.musicTaste) })
        case .other:
            OtherTasteView(viewModel: viewModel)
        }
    }
}

// MARK: - Self taste summary (auto-rotating top-3 per category, per term)

/// Auto-rotates through 9 stages — (category × term) — cross-fading every
/// ~6 seconds: 1mo tracks → 1mo artists → 1mo genres → 6mo tracks … → 1yr
/// genres → loop. Tap anywhere on the card to advance manually.
private struct SelfTasteSummary: View {
    let onSeeAll: () -> Void

    @State private var viewModel = TopItemsViewModel()
    @State private var stage: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 9 stages, ordered by term then category. Matches Dom's spec:
    /// "top 3 tracks, artists, genres for 1 month, then same for 6 months then 1 year then back".
    private static let stages: [Stage] = [
        .init(term: .shortTerm,  kind: .tracks),
        .init(term: .shortTerm,  kind: .artists),
        .init(term: .shortTerm,  kind: .genres),
        .init(term: .mediumTerm, kind: .tracks),
        .init(term: .mediumTerm, kind: .artists),
        .init(term: .mediumTerm, kind: .genres),
        .init(term: .longTerm,   kind: .tracks),
        .init(term: .longTerm,   kind: .artists),
        .init(term: .longTerm,   kind: .genres)
    ]

    private var currentStage: Stage { Self.stages[stage % Self.stages.count] }

    private func termLabel(_ term: TimeRange) -> String {
        switch term {
        case .shortTerm:  return "1 month"
        case .mediumTerm: return "6 months"
        case .longTerm:   return "1 year"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if viewModel.isLoading && allEmpty {
                VStack {
                    XomifyLoaderPulse(size: 48)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                stageCard
                    .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { advance() }
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                let horizontal = value.translation.width
                                if horizontal < -40 {
                                    advance()
                                } else if horizontal > 40 {
                                    retreat()
                                }
                            }
                    )
                    .accessibilityHint("Swipe left or right to switch stage")
                progressIndicator
                seeAllButton
            }
        }
        .padding(.horizontal)
        .task { await viewModel.loadData() }
        .task { await autoAdvanceLoop() }
    }

    // MARK: Header + progress

    private var header: some View {
        HStack(spacing: 8) {
            Text(currentStage.kindLabel)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .id("kind-\(stage)")
            Text("·").foregroundStyle(.white.opacity(0.4))
            Text(termLabel(currentStage.term))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .contentTransition(.opacity)
                .id("term-\(stage)")
            Spacer(minLength: 0)
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.stages.count, id: \.self) { idx in
                Capsule()
                    .fill(idx == (stage % Self.stages.count)
                          ? Color.xomifyGreen
                          : Color.white.opacity(0.18))
                    .frame(width: idx == (stage % Self.stages.count) ? 18 : 6, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: stage)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Stage card — cross-fades via .id + transition

    @ViewBuilder
    private var stageCard: some View {
        Group {
            switch currentStage.kind {
            case .tracks:
                trackSection(tracks: Array(tracks(for: currentStage.term).prefix(3)))
            case .artists:
                artistSection(artists: Array(artists(for: currentStage.term).prefix(3)))
            case .genres:
                genreSection(items: Array(genres(for: currentStage.term).prefix(3)).map(\.name))
            }
        }
        .id(stage)
        .transition(.asymmetric(
            insertion: .opacity.animation(.easeIn(duration: 0.45)),
            removal: .opacity.animation(.easeOut(duration: 0.25))
        ))
    }

    private var seeAllButton: some View {
        Button(action: onSeeAll) {
            HStack(spacing: 6) {
                Text("See all")
                    .fontWeight(.semibold)
                Image(systemName: "arrow.right")
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.xomifyPurple, Color.xomifyGreen],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityHint("Opens the full Music Taste screen")
    }

    // MARK: Rotation

    private func advance() {
        withAnimation(.easeInOut(duration: 0.35)) {
            stage = (stage + 1) % Self.stages.count
        }
    }

    private func retreat() {
        withAnimation(.easeInOut(duration: 0.35)) {
            stage = (stage - 1 + Self.stages.count) % Self.stages.count
        }
    }

    private func autoAdvanceLoop() async {
        while !Task.isCancelled {
            let delay: UInt64 = reduceMotion ? 8_000_000_000 : 6_000_000_000
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }
            advance()
        }
    }

    // MARK: Data slices

    private var allEmpty: Bool {
        viewModel.shortTermTracks.isEmpty && viewModel.shortTermArtists.isEmpty
        && viewModel.mediumTermTracks.isEmpty && viewModel.mediumTermArtists.isEmpty
    }

    private func tracks(for term: TimeRange) -> [SpotifyTrack] {
        switch term {
        case .shortTerm:  return viewModel.shortTermTracks
        case .mediumTerm: return viewModel.mediumTermTracks
        case .longTerm:   return viewModel.longTermTracks
        }
    }

    private func artists(for term: TimeRange) -> [SpotifyArtist] {
        switch term {
        case .shortTerm:  return viewModel.shortTermArtists
        case .mediumTerm: return viewModel.mediumTermArtists
        case .longTerm:   return viewModel.longTermArtists
        }
    }

    private func genres(for term: TimeRange) -> [(name: String, count: Int)] {
        switch term {
        case .shortTerm:  return viewModel.shortTermGenres
        case .mediumTerm: return viewModel.mediumTermGenres
        case .longTerm:   return viewModel.longTermGenres
        }
    }

    // MARK: Stage definition

    private struct Stage {
        let term: TimeRange
        let kind: Kind

        enum Kind {
            case tracks, artists, genres
        }

        var kindLabel: String {
            switch kind {
            case .tracks:  return "Top Tracks"
            case .artists: return "Top Artists"
            case .genres:  return "Top Genres"
            }
        }
    }

    // MARK: Section

    @ViewBuilder
    private func genreSection(items: [String]) -> some View {
        if items.isEmpty {
            emptyStageState(symbol: "music.note.list", label: "No genres yet")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        indexLabel(index)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.xomifyCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func trackSection(tracks: [SpotifyTrack]) -> some View {
        if tracks.isEmpty {
            emptyStageState(symbol: "music.note", label: "No tracks yet")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    trackRow(track: track, index: index)
                }
            }
        }
    }

    @ViewBuilder
    private func artistSection(artists: [SpotifyArtist]) -> some View {
        if artists.isEmpty {
            emptyStageState(symbol: "person.2", label: "No artists yet")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                    artistRow(artist: artist, index: index)
                }
            }
        }
    }

    private func emptyStageState(symbol: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.gray.opacity(0.55))
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private func trackRow(track: SpotifyTrack, index: Int) -> some View {
        HStack(spacing: 12) {
            indexLabel(index)
            artworkThumb(url: track.imageUrl)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artistNames)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            QueueButton(uri: track.uri ?? "spotify:track:\(track.id)", trackName: track.name)
            trackActions(trackId: track.id, uri: track.uri ?? "spotify:track:\(track.id)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func artistRow(artist: SpotifyArtist, index: Int) -> some View {
        HStack(spacing: 12) {
            indexLabel(index)
            artworkThumb(url: artist.imageUrl, circular: true)
            Text(artist.name)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let artistId = artist.id {
                Button {
                    openURL("spotify:artist:\(artistId)")
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Open \(artist.name) in Spotify")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func trackActions(trackId: String, uri: String) -> some View {
        Menu {
            Button {
                openURL(uri)
            } label: {
                Label("Open in Spotify", systemImage: "arrow.up.forward.app")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .accessibilityLabel("Track actions")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
    }

    private func indexLabel(_ index: Int) -> some View {
        Text("\(index + 1)")
            .font(.subheadline.monospacedDigit().weight(.bold))
            .foregroundStyle(Color.xomifyGreen)
            .frame(width: 20, alignment: .leading)
    }

    @ViewBuilder
    private func artworkThumb(url: URL?, circular: Bool = false) -> some View {
        let shape: AnyShape = circular
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: artworkThumbFallback
                    }
                }
            } else {
                artworkThumbFallback
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(shape)
    }

    private var artworkThumbFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.xomifyPurple.opacity(0.35), Color.xomifyGreen.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Other taste view
//
// Mirrors `SelfTasteSummary` — same 9-stage rotating carousel, same row
// styling, same progress indicator — but sourced from the raw JSON payload
// attached to `FriendProfile` (Spotify top-tracks / top-artists objects +
// a `{genre: score}` dict). No "See all" CTA since `TopItemsView` is
// scoped to the signed-in user.

private struct OtherTasteView: View {
    let viewModel: UserProfileViewModel

    @State private var stage: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stages: [TasteStage] = [
        .init(term: .shortTerm,  kind: .tracks),
        .init(term: .shortTerm,  kind: .artists),
        .init(term: .shortTerm,  kind: .genres),
        .init(term: .mediumTerm, kind: .tracks),
        .init(term: .mediumTerm, kind: .artists),
        .init(term: .mediumTerm, kind: .genres),
        .init(term: .longTerm,   kind: .tracks),
        .init(term: .longTerm,   kind: .artists),
        .init(term: .longTerm,   kind: .genres)
    ]

    private var currentStage: TasteStage { Self.stages[stage % Self.stages.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if allEmpty {
                emptyState
            } else {
                stageCard
                    .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { advance() }
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                let horizontal = value.translation.width
                                if horizontal < -40 { advance() }
                                else if horizontal > 40 { retreat() }
                            }
                    )
                    .accessibilityHint("Swipe left or right to switch stage")
                progressIndicator
            }
        }
        .padding(.horizontal)
        .task { await autoAdvanceLoop() }
    }

    // MARK: Header + progress

    private var header: some View {
        HStack(spacing: 8) {
            Text(currentStage.kindLabel)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .id("other-kind-\(stage)")
            Text("·").foregroundStyle(.white.opacity(0.4))
            Text(termLabel(currentStage.term))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .contentTransition(.opacity)
                .id("other-term-\(stage)")
            Spacer(minLength: 0)
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.stages.count, id: \.self) { idx in
                Capsule()
                    .fill(idx == (stage % Self.stages.count)
                          ? Color.xomifyGreen
                          : Color.white.opacity(0.18))
                    .frame(width: idx == (stage % Self.stages.count) ? 18 : 6, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: stage)
            }
        }
        .accessibilityHidden(true)
    }

    private func termLabel(_ term: TimeRange) -> String {
        switch term {
        case .shortTerm:  return "1 month"
        case .mediumTerm: return "6 months"
        case .longTerm:   return "1 year"
        }
    }

    // MARK: Stage card

    @ViewBuilder
    private var stageCard: some View {
        Group {
            switch currentStage.kind {
            case .tracks:
                let items = parsedTracks(for: currentStage.term)
                if items.isEmpty {
                    emptyStageState(symbol: "music.note", label: "No tracks yet")
                } else {
                    trackSection(items)
                }
            case .artists:
                let items = parsedArtists(for: currentStage.term)
                if items.isEmpty {
                    emptyStageState(symbol: "person.2", label: "No artists yet")
                } else {
                    artistSection(items)
                }
            case .genres:
                let items = parsedGenres(for: currentStage.term)
                if items.isEmpty {
                    emptyStageState(symbol: "music.note.list", label: "No genres yet")
                } else {
                    genreSection(items)
                }
            }
        }
        .id(stage)
        .transition(.asymmetric(
            insertion: .opacity.animation(.easeIn(duration: 0.45)),
            removal: .opacity.animation(.easeOut(duration: 0.25))
        ))
    }

    @ViewBuilder
    private func trackSection(_ tracks: [DisplayTrack]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(tracks.prefix(3).enumerated()), id: \.offset) { index, track in
                HStack(spacing: 12) {
                    indexLabel(index)
                    artworkThumb(url: track.imageUrl)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(track.artistNames)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let uri = track.uri {
                        QueueButton(uri: uri, trackName: track.name)
                    }
                    if let uri = track.uri {
                        openButton(urlString: uri, label: "Open \(track.name) in Spotify")
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.xomifyCard)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func artistSection(_ artists: [DisplayArtist]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(artists.prefix(3).enumerated()), id: \.offset) { index, artist in
                HStack(spacing: 12) {
                    indexLabel(index)
                    artworkThumb(url: artist.imageUrl, circular: true)
                    Text(artist.name)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let id = artist.id {
                        openButton(urlString: "spotify:artist:\(id)", label: "Open \(artist.name) in Spotify")
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.xomifyCard)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func genreSection(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { index, item in
                HStack(spacing: 12) {
                    indexLabel(index)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.xomifyCard)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: Common row bits

    private func indexLabel(_ index: Int) -> some View {
        Text("\(index + 1)")
            .font(.subheadline.monospacedDigit().weight(.bold))
            .foregroundStyle(Color.xomifyGreen)
            .frame(width: 20, alignment: .leading)
    }

    @ViewBuilder
    private func artworkThumb(url: URL?, circular: Bool = false) -> some View {
        let shape: AnyShape = circular
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: artworkThumbFallback
                    }
                }
            } else {
                artworkThumbFallback
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(shape)
    }

    private var artworkThumbFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.xomifyPurple.opacity(0.35), Color.xomifyGreen.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func openButton(urlString: String, label: String) -> some View {
        Button {
            if let url = URL(string: urlString) { UIApplication.shared.open(url) }
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundStyle(.gray.opacity(0.6))
            Text("No taste data yet")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text("This user hasn't built up enough listening history.")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func emptyStageState(symbol: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.gray.opacity(0.55))
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    // MARK: Rotation

    private func advance() {
        withAnimation(.easeInOut(duration: 0.35)) {
            stage = (stage + 1) % Self.stages.count
        }
    }

    private func retreat() {
        withAnimation(.easeInOut(duration: 0.35)) {
            stage = (stage - 1 + Self.stages.count) % Self.stages.count
        }
    }

    private func autoAdvanceLoop() async {
        while !Task.isCancelled {
            let delay: UInt64 = reduceMotion ? 8_000_000_000 : 6_000_000_000
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }
            advance()
        }
    }

    // MARK: JSON parsing

    private var allEmpty: Bool {
        TimeRange.allCases.allSatisfy {
            parsedTracks(for: $0).isEmpty
            && parsedArtists(for: $0).isEmpty
            && parsedGenres(for: $0).isEmpty
        }
    }

    private func parsedTracks(for term: TimeRange) -> [DisplayTrack] {
        guard let array = arrayEntry(from: viewModel.friendProfileTopSongs, term: term) else { return [] }
        return array.compactMap { value -> DisplayTrack? in
            guard let obj = value.objectValue,
                  let name = obj["name"]?.stringValue else { return nil }
            let artistNames = (obj["artists"]?.arrayValue ?? [])
                .compactMap { $0.objectValue?["name"]?.stringValue }
                .joined(separator: ", ")
            let imageUrl = firstImageURL(from: obj["album"]?.objectValue?["images"]?.arrayValue)
            let uri = obj["uri"]?.stringValue
                ?? obj["id"]?.stringValue.map { "spotify:track:\($0)" }
            return DisplayTrack(
                name: name,
                artistNames: artistNames.isEmpty ? "—" : artistNames,
                imageUrl: imageUrl,
                uri: uri
            )
        }
    }

    private func parsedArtists(for term: TimeRange) -> [DisplayArtist] {
        guard let array = arrayEntry(from: viewModel.friendProfileTopArtists, term: term) else { return [] }
        return array.compactMap { value -> DisplayArtist? in
            guard let obj = value.objectValue,
                  let name = obj["name"]?.stringValue else { return nil }
            let imageUrl = firstImageURL(from: obj["images"]?.arrayValue)
            let id = obj["id"]?.stringValue
            return DisplayArtist(name: name, id: id, imageUrl: imageUrl)
        }
    }

    private func parsedGenres(for term: TimeRange) -> [String] {
        guard let termMap = viewModel.friendProfileTopGenres else { return [] }
        let entry = termEntry(from: termMap, term: term)
        // Backend ships genres as a `{genre: score}` object (weighted, already
        // sorted descending). Legacy shape was an array of strings — tolerate
        // both.
        if let array = entry?.arrayValue {
            return array.compactMap { $0.stringValue ?? $0.objectValue?["name"]?.stringValue }
        }
        if let obj = entry?.objectValue {
            // Preserve insertion order — JSONDecoder's default [String: Value]
            // doesn't, so fall back to score-descending sort.
            return obj
                .map { (key: $0.key, score: $0.value.intValue ?? 0) }
                .sorted { $0.score > $1.score }
                .map(\.key)
        }
        return []
    }

    private func arrayEntry(from termMap: [String: JSONValue]?, term: TimeRange) -> [JSONValue]? {
        termEntry(from: termMap, term: term)?.arrayValue
    }

    private func termEntry(from termMap: [String: JSONValue]?, term: TimeRange) -> JSONValue? {
        guard let termMap else { return nil }
        let raw = term.rawValue
        if let v = termMap[raw] { return v }
        return termMap[camelCase(raw)]
    }

    private func camelCase(_ snake: String) -> String {
        let parts = snake.split(separator: "_")
        guard let first = parts.first else { return snake }
        return ([String(first)] + parts.dropFirst().map { $0.capitalized }).joined()
    }

    private func firstImageURL(from images: [JSONValue]?) -> URL? {
        guard let first = images?.first?.objectValue,
              let urlString = first["url"]?.stringValue else { return nil }
        return URL(string: urlString)
    }

    // MARK: Stage types

    private struct TasteStage {
        let term: TimeRange
        let kind: Kind

        enum Kind { case tracks, artists, genres }

        var kindLabel: String {
            switch kind {
            case .tracks:  return "Top Tracks"
            case .artists: return "Top Artists"
            case .genres:  return "Top Genres"
            }
        }
    }

    private struct DisplayTrack {
        let name: String
        let artistNames: String
        let imageUrl: URL?
        let uri: String?
    }

    private struct DisplayArtist {
        let name: String
        let id: String?
        let imageUrl: URL?
    }
}


// MARK: - Expose FriendProfile top-item dictionaries on UserProfileViewModel

extension UserProfileViewModel {
    /// Raw `FriendProfile.topArtists` payload when the context is `.other`.
    /// Loaded in `loadOtherHeader`. Cached on the VM so the Taste tab doesn't
    /// re-fetch.
    var friendProfileTopArtists: [String: JSONValue]? { friendProfile?.topArtists }
    var friendProfileTopSongs: [String: JSONValue]?   { friendProfile?.topSongs }
    var friendProfileTopGenres: [String: JSONValue]?  { friendProfile?.topGenres }
}
