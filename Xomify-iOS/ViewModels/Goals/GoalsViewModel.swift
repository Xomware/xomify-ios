import Foundation
import SwiftUI

/// Drives the Weekly Goals screen.
///
/// Goals themselves live on the backend (`/goals/*`, shared with the web).
/// Progress does not: it is recomputed here on every load from the last 50
/// recently-played tracks, because a stored count would freeze a number that
/// keeps moving for the rest of the week.
@Observable
@MainActor
final class GoalsViewModel {

    // MARK: - State

    private(set) var goals: [Goal] = []
    /// Newest first, as the backend returns it.
    private(set) var history: [WeekHistoryEntry] = []
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    /// True when progress could not be computed — the goals loaded, but the
    /// listening history behind the numbers did not. Every `current` is 0 and
    /// the screen says so rather than implying a week of no listening.
    private(set) var progressUnavailable = false

    private let xomifyService: any XomifyServicing
    private let spotifyService: SpotifyService

    // MARK: - Init

    init(
        xomifyService: any XomifyServicing = XomifyService.shared,
        spotifyService: SpotifyService = SpotifyService.shared
    ) {
        self.xomifyService = xomifyService
        self.spotifyService = spotifyService
    }

    // MARK: - Derived

    var metCount: Int { goals.filter(\.completed).count }

    var allMet: Bool { !goals.isEmpty && metCount == goals.count }

    /// Weeks fully met, counting back from the most recent.
    ///
    /// The week in progress is SKIPPED when not yet met, rather than breaking
    /// the count. It is recorded from the first view on Monday, when nothing
    /// has been listened to yet — treating that as a miss would zero the streak
    /// every Monday and hold it there until the week was complete.
    var streak: Int {
        let thisWeek = Self.weekStartKey(Date())
        var count = 0
        for entry in history {
            if entry.allMet {
                count += 1
            } else if entry.weekStart == thisWeek {
                continue
            } else {
                break
            }
        }
        return count
    }

    var streakLabel: String? {
        streak == 0 ? nil : "\(streak)-week streak"
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let (stored, weeks) = try await xomifyService.fetchGoals()
            history = weeks

            let items = await loadThisWeekContext()
            goals = stored.map { goal in
                Goal(
                    id: goal.goalId,
                    metric: goal.metric,
                    target: goal.target,
                    label: goal.label,
                    current: items.map { progress(for: goal.metric, in: $0) } ?? 0
                )
            }
            progressUnavailable = items == nil
            isLoading = false

            await recordThisWeek()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Editing

    func addGoal(metric: GoalMetric, target: Int) async {
        let new = StoredGoal(
            goalId: UUID().uuidString,
            metric: metric,
            target: target,
            label: metric.label(target: target),
            // The web's icon vocabulary, so a goal added here looks right
            // there. iOS draws `metric.systemImage` instead.
            icon: Self.webIcon(for: metric)
        )
        await save(current().map(toStored) + [new])
    }

    func removeGoal(id: String) async {
        await save(current().filter { $0.id != id }.map(toStored))
    }

    /// Whole-set replace. The list that comes back is authoritative, but its
    /// goals carry no progress — so the reload after a successful save is what
    /// repopulates the bars.
    private func save(_ goals: [StoredGoal]) async {
        isSaving = true
        do {
            _ = try await xomifyService.setGoals(goals)
            isSaving = false
            await load()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() { errorMessage = nil }

    // MARK: - Week recording

    /// Upsert this week's outcome, skipping the call when the server already
    /// holds these numbers. The screen records on every open, and progress only
    /// moves when the user has listened to something since.
    private func recordThisWeek() async {
        // Nothing meaningful to record, and writing zeros would break the
        // streak for a week whose progress simply failed to load.
        guard !goals.isEmpty, !progressUnavailable else { return }

        let entry = WeekHistoryEntry(
            weekStart: Self.weekStartKey(Date()),
            allMet: allMet,
            metCount: metCount,
            totalCount: goals.count
        )
        if history.first(where: { $0.weekStart == entry.weekStart }) == entry { return }

        history = [entry] + history.filter { $0.weekStart != entry.weekStart }

        do {
            try await xomifyService.recordGoalWeek(entry)
        } catch {
            // The goals loaded fine and the next open rewrites this same week —
            // not worth an error banner over the screen.
            print("[Goals] Failed to record week: \(error)")
        }
    }

    // MARK: - Progress

    /// Everything the metrics are computed from, fetched once per load.
    private struct WeekContext {
        let thisWeek: [SpotifyPlayHistory]
        let earlier: [SpotifyPlayHistory]
        /// Distinct genres across this week's artists, from `/artists`.
        let genres: Set<String>
    }

    /// Returns nil when listening history could not be read — distinct from a
    /// genuinely empty week, which returns an empty context.
    private func loadThisWeekContext() async -> WeekContext? {
        do {
            // 50 is Spotify's per-request maximum for recently-played, and the
            // endpoint holds roughly the last 50 plays regardless — there is no
            // deeper week to page back to.
            let response = try await spotifyService.getRecentlyPlayed(limit: 50)
            let monday = Self.weekStart(for: Date())
            let items = response.items
            let thisWeek = items.filter { item in
                guard let played = Self.playedAt(item) else { return false }
                return played >= monday
            }
            let earlier = items.filter { item in
                guard let played = Self.playedAt(item) else { return false }
                return played < monday
            }
            return WeekContext(
                thisWeek: thisWeek,
                earlier: earlier,
                genres: await genres(for: thisWeek)
            )
        } catch {
            print("[Goals] Could not load listening history: \(error)")
            return nil
        }
    }

    /// Real genres for this week's artists.
    ///
    /// Recently-played carries no genres, only artist stubs — so this is one
    /// extra `/artists?ids=` call (50 ids per request, which the whole week
    /// fits inside). A failure returns an empty set, which reads as zero
    /// genres; the alternative the web shipped was `uniqueArtists / 2`, a
    /// number that was never a genre count at all.
    private func genres(for items: [SpotifyPlayHistory]) async -> Set<String> {
        let ids = Set(items.flatMap { $0.track.artists.compactMap(\.id) })
        guard !ids.isEmpty else { return [] }
        do {
            let artists = try await spotifyService.getArtists(ids: Array(ids))
            return Set(artists.flatMap { $0.genres ?? [] })
        } catch {
            print("[Goals] Could not load artist genres: \(error)")
            return []
        }
    }

    private func progress(for metric: GoalMetric, in context: WeekContext) -> Int {
        switch metric {
        case .minutesListened:
            let ms = context.thisWeek.reduce(0) { $0 + $1.track.durationMs }
            return Int((Double(ms) / 60_000).rounded())

        case .newArtists:
            // "New" is relative to what the same 50-play window shows earlier —
            // the only history available without a separate backend store, and
            // the definition the web already uses.
            let earlier = Set(context.earlier.flatMap { $0.track.artists.compactMap(\.id) })
            let week = Set(context.thisWeek.flatMap { $0.track.artists.compactMap(\.id) })
            return week.subtracting(earlier).count

        case .genresExplored:
            return context.genres.count

        case .songsFromTopArtist:
            var counts: [String: Int] = [:]
            for item in context.thisWeek {
                guard let id = item.track.artists.first?.id else { continue }
                counts[id, default: 0] += 1
            }
            return counts.values.max() ?? 0

        case .uniqueTracks:
            return Set(context.thisWeek.map { $0.track.id }).count
        }
    }

    // MARK: - Helpers

    private func current() -> [Goal] { goals }

    private func toStored(_ goal: Goal) -> StoredGoal {
        StoredGoal(
            goalId: goal.id,
            metric: goal.metric,
            target: goal.target,
            label: goal.label,
            icon: Self.webIcon(for: goal.metric)
        )
    }

    /// The web's `app-icon` names, mirrored so a goal created on iOS renders
    /// with an icon there instead of a blank slot.
    private static func webIcon(for metric: GoalMetric) -> String {
        switch metric {
        case .minutesListened:    return "headphones"
        case .newArtists:         return "mic"
        case .genresExplored:     return "music-note"
        case .songsFromTopArtist: return "sparkle"
        case .uniqueTracks:       return "trending-up"
        }
    }

    private static func playedAt(_ item: SpotifyPlayHistory) -> Date? {
        guard let raw = item.playedAt else { return nil }
        return ISO8601DateFormatter.xomifyFractional.date(from: raw)
            ?? ISO8601DateFormatter.xomifyPlain.date(from: raw)
    }

    /// Local Monday 00:00 of `date`'s week.
    static func weekStart(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2 // Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// `YYYY-MM-DD` of the local Monday — the backend's history key.
    ///
    /// Built from local calendar parts, NOT `ISO8601DateFormatter`, which
    /// converts to UTC first and would key local Monday midnight to the Sunday
    /// before anywhere east of Greenwich.
    static func weekStartKey(_ date: Date) -> String {
        let monday = weekStart(for: date)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: monday)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Renders a `YYYY-MM-DD` key as e.g. "Aug 24", parsing it as a local day.
    static func weekLabel(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return key }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = Calendar.current.date(from: components) else { return key }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private extension ISO8601DateFormatter {
    /// Spotify stamps `played_at` with milliseconds; the base formatter rejects
    /// them outright, so both spellings are tried.
    static let xomifyFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let xomifyPlain = ISO8601DateFormatter()
}
