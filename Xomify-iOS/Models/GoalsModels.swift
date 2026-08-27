import Foundation

// MARK: - GoalMetric

/// What a weekly goal counts. Raw values are the backend's keys — `goals_set`
/// validates against this exact set, so a new case here needs the same case
/// there before it can be saved.
enum GoalMetric: String, Codable, Sendable, CaseIterable, Identifiable {
    case minutesListened     = "minutes_listened"
    case newArtists          = "new_artists"
    case genresExplored      = "genres_explored"
    case songsFromTopArtist  = "songs_from_top_artist"
    case uniqueTracks        = "unique_tracks"

    var id: String { rawValue }

    /// Menu label. Names the metric, not a target — see `label(target:)`.
    var pickerLabel: String {
        switch self {
        case .minutesListened:    return "Minutes Listened"
        case .newArtists:         return "New Artists Discovered"
        case .genresExplored:     return "Genres Explored"
        case .songsFromTopArtist: return "Songs from Top Artist"
        case .uniqueTracks:       return "Unique Tracks"
        }
    }

    /// The goal as a sentence, e.g. "Discover 3 new artists". Matches the web's
    /// `getMetricLabel` so a goal created on one client reads the same on the
    /// other — the label is stored, not recomputed.
    func label(target: Int) -> String {
        switch self {
        case .minutesListened:
            return target >= 60
                ? "\(Int((Double(target) / 60).rounded())) hours listening"
                : "\(target) min listening"
        case .newArtists:
            return "Discover \(target) new artist\(target == 1 ? "" : "s")"
        case .genresExplored:
            return "Explore \(target) genre\(target == 1 ? "" : "s")"
        case .songsFromTopArtist:
            return "\(target) songs from top artist"
        case .uniqueTracks:
            return "\(target) unique tracks"
        }
    }

    /// SF Symbol. The backend stores the WEB's icon name (`headphones`, `mic`,
    /// …), which means nothing to SwiftUI — so iOS derives its own from the
    /// metric and ignores the stored string entirely.
    var systemImage: String {
        switch self {
        case .minutesListened:    return "headphones"
        case .newArtists:         return "mic.fill"
        case .genresExplored:     return "music.note.list"
        case .songsFromTopArtist: return "sparkles"
        case .uniqueTracks:       return "chart.line.uptrend.xyaxis"
        }
    }

    /// Sensible starting target when the metric is picked in the create sheet.
    var suggestedTarget: Int {
        switch self {
        case .minutesListened:    return 300
        case .newArtists:         return 3
        case .genresExplored:     return 4
        case .songsFromTopArtist: return 10
        case .uniqueTracks:       return 50
        }
    }
}

// MARK: - Goal

/// One weekly target.
///
/// `current` and `completed` are NOT part of the stored record and never sent:
/// the backend rejects them. They are computed on each load from recently-played
/// — a stored count would freeze a number that keeps moving for the rest of the
/// week, and let two clients disagree about the same day.
struct Goal: Identifiable, Sendable, Equatable {
    let id: String
    let metric: GoalMetric
    let target: Int
    let label: String

    var current: Int = 0

    var completed: Bool { current >= target }

    /// 0…1, clamped — progress past the target still reads as a full bar.
    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1)
    }
}

/// The wire shape of a goal. Deliberately separate from `Goal`: this is what
/// crosses the network, and it has no progress fields to accidentally send.
struct StoredGoal: Codable, Sendable {
    let goalId: String
    let metric: GoalMetric
    let target: Int
    let label: String
    let icon: String?
}

// MARK: - History

/// One completed (or in-progress) week's outcome.
struct WeekHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    /// `YYYY-MM-DD`, the local Monday. Also the upsert key.
    let weekStart: String
    let allMet: Bool
    let metCount: Int
    let totalCount: Int

    var id: String { weekStart }
}

// MARK: - Responses

struct GoalsResponse: Codable, Sendable {
    let goals: [StoredGoal]?
    /// Newest first.
    let history: [WeekHistoryEntry]?
}

struct GoalsSetResponse: Codable, Sendable {
    let goals: [StoredGoal]?
}
