import SwiftUI

/// Taste tab on `ProfileView`. v1 delegates to existing surfaces:
///   `.me`    → embeds `TopItemsView` verbatim so the self-view picker and
///              rich tiles are preserved.
///   `.other` → reads the `FriendProfile` payload already loaded by
///              `UserProfileViewModel` and renders degraded text tiles with
///              a term picker. Empty-bucket fallback per contract.
struct ProfileTasteTab: View {

    let viewModel: UserProfileViewModel

    var body: some View {
        switch viewModel.context {
        case .me:
            TopItemsView()
                .padding(.horizontal, -16)
        case .other:
            OtherTasteView(viewModel: viewModel)
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
