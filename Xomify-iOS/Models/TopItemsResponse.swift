import Foundation

// MARK: - Top Items Response (`GET /user/top-items`)
//
// Live, daily-cached top tracks/artists/genres for the signed-in user. The
// backend serves snake_case keys (`short_term`, `medium_term`, `long_term`,
// `failed_ranges`) and `NetworkService.xomifyGet` decodes with
// `keyDecodingStrategy = .convertFromSnakeCase`, so the Swift property names
// here are the camelCased equivalents.
//
// Each per-term value is optional — the backend isolates per-range failures
// and emits `null` for any range it could not fetch, populating
// `meta.failed_ranges` with the union of failing range names. Genres for a
// failed artists range are also `null` (genres are derived from artists).
//
// Cache contract (epic Q7): the response is at most ~24h stale, refreshed
// once per UTC day on first request. iOS does not need a client-side cache.

/// Envelope returned by `GET /user/top-items`. Fields are mirrors of the
/// Spotify shapes already in use (`SpotifyTrack`, `SpotifyArtist`) plus a
/// `genres` map of `{ genre: weighted_score }` per term.
struct TopItemsResponse: Codable, Sendable {
    let tracks: TopItemsTracks?
    let artists: TopItemsArtists?
    let genres: TopItemsGenres?
    let meta: TopItemsMeta?

    struct TopItemsTracks: Codable, Sendable {
        let shortTerm: [SpotifyTrack]?
        let mediumTerm: [SpotifyTrack]?
        let longTerm: [SpotifyTrack]?
    }

    struct TopItemsArtists: Codable, Sendable {
        let shortTerm: [SpotifyArtist]?
        let mediumTerm: [SpotifyArtist]?
        let longTerm: [SpotifyArtist]?
    }

    /// Backend ships genres as `{ genre_name: weighted_score }` per term.
    /// Mirrors the existing `MonthlyWrap.TermGenres` shape so callers can
    /// reuse the same render path.
    struct TopItemsGenres: Codable, Sendable {
        let shortTerm: [String: Int]?
        let mediumTerm: [String: Int]?
        let longTerm: [String: Int]?
    }

    /// Present only on partial failure. `failedRanges` is a sorted list of
    /// `short_term` / `medium_term` / `long_term` strings (raw enum values
    /// of `TimeRange`) that the backend could not fetch from Spotify.
    struct TopItemsMeta: Codable, Sendable {
        let failedRanges: [String]?
    }
}

extension TopItemsResponse {
    /// Convenience: tracks for a given `TimeRange`, or empty array if the
    /// range is missing / nulled by partial failure.
    func tracks(for term: TimeRange) -> [SpotifyTrack] {
        switch term {
        case .shortTerm:  return tracks?.shortTerm ?? []
        case .mediumTerm: return tracks?.mediumTerm ?? []
        case .longTerm:   return tracks?.longTerm ?? []
        }
    }

    /// Convenience: artists for a given `TimeRange`, or empty array if the
    /// range is missing / nulled by partial failure.
    func artists(for term: TimeRange) -> [SpotifyArtist] {
        switch term {
        case .shortTerm:  return artists?.shortTerm ?? []
        case .mediumTerm: return artists?.mediumTerm ?? []
        case .longTerm:   return artists?.longTerm ?? []
        }
    }

    /// Convenience: genres for a given `TimeRange` as a count-descending
    /// list of `(name, count)` tuples, mirroring the shape `TopItemsView`
    /// already renders.
    func genres(for term: TimeRange) -> [(name: String, count: Int)] {
        let dict: [String: Int]?
        switch term {
        case .shortTerm:  dict = genres?.shortTerm
        case .mediumTerm: dict = genres?.mediumTerm
        case .longTerm:   dict = genres?.longTerm
        }
        guard let dict else { return [] }
        return dict
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// `true` when the backend reported a partial Spotify failure for the
    /// given term — UI can use this to surface a soft retry hint without
    /// hiding the data we did get.
    func didFail(term: TimeRange) -> Bool {
        guard let failed = meta?.failedRanges else { return false }
        return failed.contains(term.rawValue)
    }
}
