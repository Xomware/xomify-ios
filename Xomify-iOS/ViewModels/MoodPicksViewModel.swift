import Foundation

// MARK: - Mood preset

enum MoodType: String, CaseIterable, Identifiable, Sendable {
    case happy = "Happy"
    case chill = "Chill"
    case hype = "Hype"
    case focus = "Focus"
    case sad = "Sad"
    case party = "Party"
    case workout = "Workout"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .happy:   return "☀️"
        case .chill:   return "🌊"
        case .hype:    return "⚡"
        case .focus:   return "🧘"
        case .sad:     return "🌧️"
        case .party:   return "🎉"
        case .workout: return "💪"
        }
    }

    var description: String {
        switch self {
        case .happy:   return "Upbeat and joyful"
        case .chill:   return "Relaxed and mellow"
        case .hype:    return "High-energy bangers"
        case .focus:   return "Instrumental, clean"
        case .sad:     return "Introspective and emotional"
        case .party:   return "Loud, fun, danceable"
        case .workout: return "Drive-through-a-wall energy"
        }
    }

    var genreKeywords: [String] {
        switch self {
        case .happy:   return ["pop", "dance", "disco", "funk", "indie pop", "bubblegum"]
        case .chill:   return ["chill", "lo-fi", "lofi", "ambient", "acoustic", "bedroom", "singer-songwriter"]
        case .hype:    return ["edm", "trap", "drill", "electronic", "house", "dubstep", "hip hop", "rap"]
        case .focus:   return ["ambient", "classical", "post-rock", "instrumental", "minimal", "study"]
        case .sad:     return ["emo", "indie folk", "sad", "melancholy", "slowcore", "singer-songwriter", "ballad"]
        case .party:   return ["dance", "house", "pop", "reggaeton", "latin", "edm", "disco", "funk"]
        case .workout: return ["hip hop", "rap", "edm", "trap", "punk", "metal", "rock", "drill"]
        }
    }
}

/// ViewModel for Mood Picks. Pulls from the user's top artists (medium term),
/// filters by genre keywords, fetches top tracks for a sample, dedupes, shuffles.
@Observable
@MainActor
final class MoodPicksViewModel {

    // MARK: - State

    var selectedMood: MoodType?
    var tracks: [SpotifyTrack] = []

    var isLoading = false
    var errorMessage: String?

    private let spotify = SpotifyService.shared

    private let targetTracks = 30
    private let maxArtistsToSample = 12

    // MARK: - Actions

    func selectMood(_ mood: MoodType) async {
        guard !isLoading else { return }
        selectedMood = mood
        tracks = []
        isLoading = true
        errorMessage = nil

        do {
            // 1. Fetch user's top artists.
            let topArtists = try await spotify.getTopArtists(timeRange: .mediumTerm, limit: 50)

            // 2. Filter by genre keyword substring match (case-insensitive).
            let keywords = mood.genreKeywords.map { $0.lowercased() }
            var matched = topArtists.filter { artist in
                guard let genres = artist.genres else { return false }
                return genres.contains { genre in
                    let lower = genre.lowercased()
                    return keywords.contains { lower.contains($0) }
                }
            }

            // 3. Fall back to full top list if too few matches.
            if matched.count < 5 {
                matched = topArtists
            }

            // 4. Shuffle + take up to maxArtistsToSample.
            let sampled = Array(matched.shuffled().prefix(maxArtistsToSample))

            // 5. Fetch top tracks for each sampled artist, in parallel.
            var collected: [SpotifyTrack] = []
            try await withThrowingTaskGroup(of: [SpotifyTrack].self) { group in
                for artist in sampled {
                    guard let id = artist.id else { continue }
                    group.addTask { [spotify] in
                        (try? await spotify.getArtistTopTracks(id: id)) ?? []
                    }
                }
                for try await batch in group {
                    collected.append(contentsOf: batch)
                }
            }

            // 6. Dedupe by id, shuffle, slice.
            var seen = Set<String>()
            var deduped: [SpotifyTrack] = []
            for track in collected where !seen.contains(track.id) {
                seen.insert(track.id)
                deduped.append(track)
            }
            tracks = Array(deduped.shuffled().prefix(targetTracks))
        } catch {
            errorMessage = "Failed to load mood picks: \(error.localizedDescription)"
            print("❌ MoodPicks: failed - \(error)")
        }

        isLoading = false
    }
}
