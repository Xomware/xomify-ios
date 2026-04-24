import SwiftUI

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

// MARK: - Self taste summary (top-3 per category, per term)

private struct SelfTasteSummary: View {
    let onSeeAll: () -> Void

    @State private var viewModel = TopItemsViewModel()
    @State private var selectedTerm: TimeRange = .shortTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Time range", selection: $selectedTerm) {
                Text("4 weeks").tag(TimeRange.shortTerm)
                Text("6 months").tag(TimeRange.mediumTerm)
                Text("All time").tag(TimeRange.longTerm)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Taste time range")

            if viewModel.isLoading && tracks.isEmpty && artists.isEmpty {
                VStack {
                    ProgressView().tint(.xomifyGreen)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                section(title: "Top Tracks", items: tracks.map(\.name))
                section(title: "Top Artists", items: artists.map(\.name))
                section(title: "Top Genres", items: genres.map(\.name))

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
        }
        .padding(.horizontal)
        .task { await viewModel.loadData() }
    }

    // MARK: Term-scoped slices (top 3 each)

    private var tracks: [SpotifyTrack] {
        Array(tracksForSelectedTerm.prefix(3))
    }

    private var artists: [SpotifyArtist] {
        Array(artistsForSelectedTerm.prefix(3))
    }

    private var genres: [(name: String, count: Int)] {
        Array(genresForSelectedTerm.prefix(3))
    }

    private var tracksForSelectedTerm: [SpotifyTrack] {
        switch selectedTerm {
        case .shortTerm:  return viewModel.shortTermTracks
        case .mediumTerm: return viewModel.mediumTermTracks
        case .longTerm:   return viewModel.longTermTracks
        }
    }

    private var artistsForSelectedTerm: [SpotifyArtist] {
        switch selectedTerm {
        case .shortTerm:  return viewModel.shortTermArtists
        case .mediumTerm: return viewModel.mediumTermArtists
        case .longTerm:   return viewModel.longTermArtists
        }
    }

    private var genresForSelectedTerm: [(name: String, count: Int)] {
        switch selectedTerm {
        case .shortTerm:  return viewModel.shortTermGenres
        case .mediumTerm: return viewModel.mediumTermGenres
        case .longTerm:   return viewModel.longTermGenres
        }
    }

    // MARK: Section

    @ViewBuilder
    private func section(title: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(Color.xomifyGreen)
                            .frame(width: 20, alignment: .leading)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.xomifyCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Other taste view

private struct OtherTasteView: View {
    let viewModel: UserProfileViewModel

    @State private var selectedTerm: TermRange = .mediumTerm

    private enum TermRange: String, CaseIterable, Hashable {
        case shortTerm  = "short_term"
        case mediumTerm = "medium_term"
        case longTerm   = "long_term"

        var title: String {
            switch self {
            case .shortTerm:  return "Last 4 weeks"
            case .mediumTerm: return "Last 6 months"
            case .longTerm:   return "All time"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Time range", selection: $selectedTerm) {
                ForEach(TermRange.allCases, id: \.self) { term in
                    Text(term.title).tag(term)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Taste time range")
            .accessibilityHint("Switches between last 4 weeks, last 6 months, and all time")

            let artistNames = names(from: viewModel.friendProfileTopArtists, term: selectedTerm)
            let songNames = names(from: viewModel.friendProfileTopSongs, term: selectedTerm)
            let genreNames = names(from: viewModel.friendProfileTopGenres, term: selectedTerm)

            if artistNames.isEmpty && songNames.isEmpty && genreNames.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundStyle(.gray.opacity(0.6))
                    Text("No taste data yet")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Text("This user hasn't built up enough listening history in this window.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                section(title: "Top Artists", items: artistNames)
                section(title: "Top Songs", items: songNames)
                section(title: "Top Genres", items: genreNames)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func section(title: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline).foregroundStyle(.white)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(items.prefix(20).enumerated()), id: \.offset) { _, item in
                            tile(item)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ label: String) -> some View {
        Text(label)
            .font(.caption).fontWeight(.medium)
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(width: 110, height: 60)
            .padding(.horizontal, 8)
            .background(Color.xomifyCard)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
    }

    // MARK: - JSON → names

    private func names(from termMap: [String: JSONValue]?, term: TermRange) -> [String] {
        guard let termMap else { return [] }
        let keys = [term.rawValue, camelCase(term.rawValue)]
        for key in keys {
            if let entry = termMap[key], let list = entry.arrayValue {
                return extractNames(from: list)
            }
        }
        return []
    }

    private func camelCase(_ snake: String) -> String {
        let parts = snake.split(separator: "_")
        guard let first = parts.first else { return snake }
        return ([String(first)] + parts.dropFirst().map { $0.capitalized }).joined()
    }

    private func extractNames(from list: [JSONValue]) -> [String] {
        list.compactMap { item -> String? in
            if let s = item.stringValue { return s }
            if let obj = item.objectValue {
                if let name = obj["name"]?.stringValue { return name }
                if let name = obj["trackName"]?.stringValue { return name }
                if let name = obj["artistName"]?.stringValue { return name }
            }
            return nil
        }
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
