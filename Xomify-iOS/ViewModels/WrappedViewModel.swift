import Foundation

/// ViewModel for Monthly Wrapped screen
@Observable
@MainActor
final class WrappedViewModel {
    
    // MARK: - Properties
    
    var isLoading = false
    var errorMessage: String?
    
    // Available wraps
    var wraps: [MonthlyWrap] = []
    var selectedWrap: MonthlyWrap?
    
    // Resolved data (Spotify objects)
    var topTracks: [SpotifyTrack] = []
    var topArtists: [SpotifyArtist] = []
    var topGenres: [(genre: String, count: Int)] = []
    
    // Selected term
    var selectedTerm: TimeRange = .shortTerm
    
    // User email
    var userEmail: String?
    
    // Cache for resolved data
    private var trackCache: [String: SpotifyTrack] = [:]
    private var artistCache: [String: SpotifyArtist] = [:]
    
    private let xomifyService = XomifyService.shared
    private let spotifyService = SpotifyService.shared
    
    // MARK: - Computed
    
    var hasWraps: Bool {
        !wraps.isEmpty
    }
    
    var hasSelectedWrap: Bool {
        selectedWrap != nil
    }
    
    var selectedWrapName: String {
        selectedWrap?.displayName ?? "Select a Month"
    }
    
    // MARK: - Actions
    
    func loadWraps() async {
        // Caller email rides the per-user JWT; we still gate on having a
        // resolved Spotify session locally so we don't fire when signed-out.
        guard userEmail?.isEmpty == false else {
            errorMessage = "Please log in first"
            return
        }

        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            wraps = try await xomifyService.getWraps()
            
            // Auto-select most recent wrap
            if let mostRecent = wraps.first {
                await selectWrap(mostRecent)
            }
            
            print("✅ Wrapped: Loaded \(wraps.count) wraps")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Wrapped: Error loading wraps - \(error)")
        }
        
        isLoading = false
    }
    
    func selectWrap(_ wrap: MonthlyWrap) async {
        selectedWrap = wrap
        await resolveWrapData()
    }
    
    func selectTerm(_ term: TimeRange) async {
        selectedTerm = term
        await resolveWrapData()
    }
    
    // MARK: - Data Resolution
    
    private func resolveWrapData() async {
        guard let wrap = selectedWrap else { return }
        
        isLoading = true
        
        // Resolve tracks
        let trackIds = getTrackIds(for: selectedTerm, from: wrap)
        topTracks = await resolveTracks(ids: trackIds)
        
        // Resolve artists
        let artistIds = getArtistIds(for: selectedTerm, from: wrap)
        topArtists = await resolveArtists(ids: artistIds)
        
        // Resolve genres
        topGenres = getGenres(for: selectedTerm, from: wrap)
        
        isLoading = false
    }
    
    private func getTrackIds(for term: TimeRange, from wrap: MonthlyWrap) -> [String] {
        guard let termData = wrap.topSongIds else { return [] }
        
        switch term {
        case .shortTerm: return termData.shortTerm ?? []
        case .mediumTerm: return termData.mediumTerm ?? []
        case .longTerm: return termData.longTerm ?? []
        }
    }
    
    private func getArtistIds(for term: TimeRange, from wrap: MonthlyWrap) -> [String] {
        guard let termData = wrap.topArtistIds else { return [] }
        
        switch term {
        case .shortTerm: return termData.shortTerm ?? []
        case .mediumTerm: return termData.mediumTerm ?? []
        case .longTerm: return termData.longTerm ?? []
        }
    }
    
    private func getGenres(for term: TimeRange, from wrap: MonthlyWrap) -> [(genre: String, count: Int)] {
        guard let termData = wrap.topGenres else { return [] }
        
        let genreDict: [String: Int]?
        switch term {
        case .shortTerm: genreDict = termData.shortTerm
        case .mediumTerm: genreDict = termData.mediumTerm
        case .longTerm: genreDict = termData.longTerm
        }
        
        guard let dict = genreDict else { return [] }
        
        return dict.map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
    }
    
    private func resolveTracks(ids: [String]) async -> [SpotifyTrack] {
        // Check cache first
        let uncachedIds = ids.filter { trackCache[$0] == nil }
        
        if !uncachedIds.isEmpty {
            do {
                let tracks = try await spotifyService.getTracks(ids: uncachedIds)
                for track in tracks {
                    trackCache[track.id] = track
                }
            } catch {
                print("❌ Wrapped: Error resolving tracks - \(error)")
            }
        }
        
        // Return in order
        return ids.compactMap { trackCache[$0] }
    }
    
    private func resolveArtists(ids: [String]) async -> [SpotifyArtist] {
        // Check cache first
        let uncachedIds = ids.filter { artistCache[$0] == nil }
        
        if !uncachedIds.isEmpty {
            do {
                let artists = try await spotifyService.getArtists(ids: uncachedIds)
                for artist in artists {
                    if let id = artist.id {
                        artistCache[id] = artist
                    }
                }
            } catch {
                print("❌ Wrapped: Error resolving artists - \(error)")
            }
        }
        
        // Return in order
        return ids.compactMap { artistCache[$0] }
    }
}
