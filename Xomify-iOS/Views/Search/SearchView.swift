import SwiftUI

/// Top-level Spotify search screen. Lets the user search Tracks / Artists /
/// Albums via an in-screen text field, with a 300 ms debounce on `searchText`
/// changes and a minimum query length of 2.
///
/// Result actions:
/// - Track  → presents the shared `TrackQuickInfoSheet`.
/// - Artist → pushes `ArtistView(artistId:)` onto the outer navigation stack
///   provided by `MainShell`.
/// - Album  → pushes `AlbumView(albumId:)` onto the outer navigation stack.
///
/// Architecture: state lives in this view rather than a separate VM. The
/// search surface is simple and self-contained — no shared mutation, no
/// cross-screen coordination — so a dedicated `@Observable` would just add
/// indirection. If/when search grows recents, suggestions, etc. it should be
/// extracted into `SearchViewModel`.
struct SearchView: View {

    // MARK: - State

    @State private var searchText: String = ""
    @State private var searchType: SearchType = .track

    @State private var trackResults: [SpotifyTrack] = []
    @State private var artistResults: [SpotifyArtist] = []
    @State private var albumResults: [SpotifyAlbum] = []

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    /// Track tapped — drives the quick-info sheet presentation.
    @State private var selectedTrack: SpotifyTrack?

    private let spotifyService = SpotifyService.shared

    /// Minimum characters before we'll fire a search request.
    private let minQueryLength: Int = 2

    /// Debounce window for `.task(id:)` driven searches.
    private let debounceNanoseconds: UInt64 = 300_000_000

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()

            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                typePicker
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                contentArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // MainShell provides the outer NavigationStack and a custom HeaderBar.
        // SearchView intentionally does not host its own NavigationStack — that
        // would isolate the inner navigation graph and make pushed
        // `ArtistView`/`AlbumView` from result rows live in a stack the rest of
        // the app can't reach. The custom `searchField` replaces `.searchable`
        // for the same reason: `.searchable` needs an attached NavigationStack
        // to render and would either double up nav chrome on top of the
        // HeaderBar or silently fail to show.
        .toolbar(.hidden, for: .navigationBar)
        .task(id: SearchKey(text: trimmedQuery, type: searchType)) {
            await runDebouncedSearch()
        }
        .trackQuickInfoSheet(track: $selectedTrack)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.white.opacity(0.55))

            TextField(
                "Search songs, artists, albums",
                text: $searchText,
                prompt: Text("Search songs, artists, albums")
                    .foregroundColor(.white.opacity(0.45))
            )
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .tint(Color.xomifyGreen)
            .submitLabel(.search)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .accessibilityLabel("Search query")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.55))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: XomRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: XomRadius.xl, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Type picker

    private var typePicker: some View {
        Picker("Search type", selection: $searchType) {
            ForEach(SearchType.allCases, id: \.self) { type in
                Text(type.pluralLabel).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Search type")
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if trimmedQuery.isEmpty {
            promptState(
                icon: "magnifyingglass",
                title: "Find anything on Spotify",
                subtitle: "Search by song, artist, or album."
            )
        } else if trimmedQuery.count < minQueryLength {
            promptState(
                icon: "character.cursor.ibeam",
                title: "Keep typing",
                subtitle: "Enter at least \(minQueryLength) characters to search."
            )
        } else if isLoading && currentResultsAreEmpty {
            loadingState
        } else if let error = errorMessage, currentResultsAreEmpty {
            errorState(error)
        } else if currentResultsAreEmpty {
            promptState(
                icon: "exclamationmark.magnifyingglass",
                title: "No results",
                subtitle: "Try a different search."
            )
        } else {
            resultsList
        }
    }

    // MARK: - Results list

    @ViewBuilder
    private var resultsList: some View {
        switch searchType {
        case .track:
            List(trackResults) { track in
                trackRow(track)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.white.opacity(0.08))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

        case .artist:
            List(artistResults, id: \.id) { artist in
                if let id = artist.id {
                    NavigationLink(destination: ArtistView(artistId: id)) {
                        artistRow(artist)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.white.opacity(0.08))
                } else {
                    artistRow(artist)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.white.opacity(0.08))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

        case .album:
            List(albumResults) { album in
                NavigationLink(destination: AlbumView(albumId: album.id)) {
                    albumRow(album)
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color.white.opacity(0.08))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Rows

    private func trackRow(_ track: SpotifyTrack) -> some View {
        Button {
            selectedTrack = track
        } label: {
            HStack(spacing: 12) {
                artwork(track.imageUrl, systemFallback: "music.note")
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.xomifySubheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(track.artistNames)
                        .font(.xomifyCaption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.name) by \(track.artistNames)")
    }

    private func artistRow(_ artist: SpotifyArtist) -> some View {
        HStack(spacing: 12) {
            artwork(artist.imageUrl, systemFallback: "person.fill", circular: true)
                .frame(width: 52, height: 52)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.xomifySubheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let followers = artist.followers?.total, followers > 0 {
                    Text("\(formatFollowers(followers)) followers")
                        .font(.xomifyCaption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                } else {
                    Text("Artist")
                        .font(.xomifyCaption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityLabel("Artist: \(artist.name)")
    }

    private func albumRow(_ album: SpotifyAlbum) -> some View {
        HStack(spacing: 12) {
            artwork(album.imageUrl, systemFallback: "square.stack")
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.xomifySubheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                let subtitle = albumSubtitle(album)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.xomifyCaption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityLabel("Album: \(album.name) by \(album.artistNames)")
    }

    @ViewBuilder
    private func artwork(_ url: URL?, systemFallback: String, circular: Bool = false) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure, .empty:
                ZStack {
                    Color.white.opacity(0.06)
                    Image(systemName: systemFallback)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.5))
                }
            @unknown default:
                Color.white.opacity(0.06)
            }
        }
    }

    // MARK: - Empty / loading / error states

    private func promptState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.xomifyPurple.opacity(0.85))
            Text(title)
                .font(.xomifyHeadline)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.xomifyCallout)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var loadingState: some View {
        VStack {
            XomifyLoaderPaint(size: 40)
                .padding(.top, 80)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange.opacity(0.85))
            Text("Search failed")
                .font(.xomifyHeadline)
                .foregroundStyle(.white)
            Text(message)
                .font(.xomifyFootnote)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            Button {
                Task { await performSearch(query: trimmedQuery, type: searchType) }
            } label: {
                Text("Try again")
                    .font(.xomifySubheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Color.xomifyPurple, in: Capsule())
            }
            .accessibilityLabel("Retry search")
        }
        .padding(.top, 80)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Search lifecycle

    /// Trimmed query used for both gating and as the `.task(id:)` identity.
    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Composite key so `.task(id:)` re-runs whenever either the query or the
    /// active type changes. Type swaps re-issue the search rather than reusing
    /// stale results from a different filter.
    private struct SearchKey: Equatable {
        let text: String
        let type: SearchType
    }

    private var currentResultsAreEmpty: Bool {
        switch searchType {
        case .track:  return trackResults.isEmpty
        case .artist: return artistResults.isEmpty
        case .album:  return albumResults.isEmpty
        }
    }

    /// Invoked by `.task(id:)` whenever the search key changes. Honors the
    /// minimum query length, debounces, and bails on cancellation.
    private func runDebouncedSearch() async {
        let query = trimmedQuery
        let type = searchType

        guard query.count >= minQueryLength else {
            // Below the floor — clear results for the active type so the
            // hint state renders cleanly.
            clearResults(for: type)
            errorMessage = nil
            isLoading = false
            return
        }

        // 300ms debounce — cooperative cancellation kills the in-flight task
        // when the user keeps typing.
        do {
            try await Task.sleep(nanoseconds: debounceNanoseconds)
        } catch {
            return
        }

        if Task.isCancelled { return }

        await performSearch(query: query, type: type)
    }

    /// Hits Spotify and routes the response into the matching results bucket.
    private func performSearch(query: String, type: SearchType) async {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let results = try await spotifyService.search(query: query, type: type, limit: 20)
            if Task.isCancelled { return }

            // Only populate the bucket matching the active type — guards
            // against a slow response landing after the user switched types.
            guard type == searchType else { return }

            switch type {
            case .track:
                trackResults = results.tracks?.items ?? []
            case .artist:
                artistResults = results.artists?.items ?? []
            case .album:
                albumResults = results.albums?.items ?? []
            }
        } catch is CancellationError {
            // Swallow — task was superseded by another keystroke.
        } catch {
            if Task.isCancelled { return }
            errorMessage = error.localizedDescription
            clearResults(for: type)
        }
    }

    private func clearResults(for type: SearchType) {
        switch type {
        case .track:  trackResults = []
        case .artist: artistResults = []
        case .album:  albumResults = []
        }
    }

    // MARK: - Helpers

    private func albumSubtitle(_ album: SpotifyAlbum) -> String {
        var parts: [String] = []
        if let type = album.albumType, !type.isEmpty {
            parts.append(type.capitalized)
        }
        let names = album.artistNames
        if !names.isEmpty {
            parts.append(names)
        }
        if let year = album.year {
            parts.append(year)
        }
        return parts.joined(separator: " • ")
    }

    private func formatFollowers(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

#Preview {
    SearchView()
        .preferredColorScheme(.dark)
}
