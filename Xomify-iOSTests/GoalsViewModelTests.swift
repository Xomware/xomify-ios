import XCTest
@testable import Xomify_iOS

@MainActor
final class GoalsViewModelTests: XCTestCase {

    private func makeGoal(
        id: String = "g1",
        metric: GoalMetric = .uniqueTracks,
        target: Int = 10
    ) -> StoredGoal {
        StoredGoal(
            goalId: id, metric: metric, target: target,
            label: metric.label(target: target), icon: nil
        )
    }

    private func week(_ start: String, allMet: Bool, met: Int = 4, total: Int = 4) -> WeekHistoryEntry {
        WeekHistoryEntry(weekStart: start, allMet: allMet, metCount: met, totalCount: total)
    }

    // MARK: - Week keys

    func testWeekStartKeyIsTheLocalMonday() async {
        // A Thursday. Its Monday is the 24th regardless of timezone, because
        // the key is built from local calendar parts rather than a UTC instant.
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 27
        components.hour = 23; components.minute = 30
        let thursdayNight = Calendar.current.date(from: components)!

        XCTAssertEqual(GoalsViewModel.weekStartKey(thursdayNight), "2026-08-24")
    }

    func testMondayIsItsOwnWeekStart() async {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 24
        components.hour = 0; components.minute = 1
        let mondayJustAfterMidnight = Calendar.current.date(from: components)!

        XCTAssertEqual(GoalsViewModel.weekStartKey(mondayJustAfterMidnight), "2026-08-24")
    }

    func testWeekLabelNamesTheDayInTheKey() async {
        // `Date(iso: "2026-08-24")` would be UTC midnight and format as the
        // 23rd west of Greenwich. The label parses local parts instead.
        XCTAssertEqual(GoalsViewModel.weekLabel("2026-08-24"), "Aug 24")
    }

    // MARK: - Streak

    func testStreakCountsConsecutiveMetWeeks() async {
        let mock = MockXomifyServicing()
        mock.goalsHistory = [
            week("2026-08-17", allMet: true),
            week("2026-08-10", allMet: true),
            week("2026-08-03", allMet: false),
            week("2026-07-27", allMet: true),
        ]
        let viewModel = GoalsViewModel(xomifyService: mock)
        await viewModel.load()

        XCTAssertEqual(viewModel.streak, 2)
    }

    /// The regression this whole date pass came from: the week in progress is
    /// recorded from the first view on Monday, when nothing has been listened
    /// to yet. Counting that as a miss zeroed the streak every Monday.
    func testUnmetCurrentWeekDoesNotBreakTheStreak() async {
        let mock = MockXomifyServicing()
        mock.goalsHistory = [
            week(GoalsViewModel.weekStartKey(Date()), allMet: false, met: 0, total: 4),
            week("2026-08-17", allMet: true),
            week("2026-08-10", allMet: true),
        ]
        let viewModel = GoalsViewModel(xomifyService: mock)
        await viewModel.load()

        XCTAssertEqual(viewModel.streak, 2)
    }

    func testUnmetPastWeekDoesBreakTheStreak() async {
        let mock = MockXomifyServicing()
        mock.goalsHistory = [
            week("2026-08-17", allMet: false),
            week("2026-08-10", allMet: true),
        ]
        let viewModel = GoalsViewModel(xomifyService: mock)
        await viewModel.load()

        XCTAssertEqual(viewModel.streak, 0)
    }

    // MARK: - Loading

    func testLoadMapsStoredGoals() async {
        let mock = MockXomifyServicing()
        mock.goals = [makeGoal(id: "a", metric: .newArtists, target: 3)]
        let viewModel = GoalsViewModel(xomifyService: mock)
        await viewModel.load()

        XCTAssertEqual(viewModel.goals.count, 1)
        XCTAssertEqual(viewModel.goals.first?.id, "a")
        XCTAssertEqual(viewModel.goals.first?.metric, .newArtists)
        XCTAssertEqual(viewModel.goals.first?.target, 3)
    }

    func testLoadSurfacesAnError() async {
        let mock = MockXomifyServicing()
        mock.goalsError = URLError(.notConnectedToInternet)
        let viewModel = GoalsViewModel(xomifyService: mock)
        await viewModel.load()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Recording

    /// Progress failed to load, so every `current` is 0. Writing that as the
    /// week's outcome would record a miss the user did not earn.
    func testDoesNotRecordTheWeekWhenProgressIsUnavailable() async {
        let mock = MockXomifyServicing()
        mock.goals = [makeGoal()]
        let viewModel = GoalsViewModel(xomifyService: mock)
        await viewModel.load()

        XCTAssertTrue(viewModel.progressUnavailable, "no Spotify session in tests")
        XCTAssertTrue(mock.recordedWeeks.isEmpty)
    }

    func testDoesNotRecordWhenThereAreNoGoals() async {
        let mock = MockXomifyServicing()
        let viewModel = GoalsViewModel(xomifyService: mock)
        await viewModel.load()

        XCTAssertTrue(mock.recordedWeeks.isEmpty)
    }

    // MARK: - Editing

    func testRemovingSendsTheRemainingSet() async {
        let mock = MockXomifyServicing()
        mock.goals = [makeGoal(id: "a"), makeGoal(id: "b")]
        let viewModel = GoalsViewModel(xomifyService: mock)
        await viewModel.load()

        await viewModel.removeGoal(id: "a")

        // Whole-set replace: the goal is deleted by being absent, not by a
        // delete call.
        XCTAssertEqual(mock.setGoalsCalls.count, 1)
        XCTAssertEqual(mock.setGoalsCalls.first?.map(\.goalId), ["b"])
    }

    func testAddingAppendsToTheExistingSet() async {
        let mock = MockXomifyServicing()
        mock.goals = [makeGoal(id: "a")]
        let viewModel = GoalsViewModel(xomifyService: mock)
        await viewModel.load()

        await viewModel.addGoal(metric: .genresExplored, target: 5)

        let sent = mock.setGoalsCalls.first
        XCTAssertEqual(sent?.count, 2)
        XCTAssertEqual(sent?.last?.metric, .genresExplored)
        XCTAssertEqual(sent?.last?.target, 5)
        XCTAssertEqual(sent?.last?.label, "Explore 5 genres")
    }

    func testAddFailureSurfacesAndDoesNotWedgeSaving() async {
        let mock = MockXomifyServicing()
        let viewModel = GoalsViewModel(xomifyService: mock)
        await viewModel.load()
        mock.goalsError = URLError(.timedOut)

        await viewModel.addGoal(metric: .uniqueTracks, target: 20)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSaving)
    }

    // MARK: - Labels

    func testMinutesLabelSwitchesToHoursAtAnHour() async {
        XCTAssertEqual(GoalMetric.minutesListened.label(target: 45), "45 min listening")
        XCTAssertEqual(GoalMetric.minutesListened.label(target: 300), "5 hours listening")
    }

    func testSingularLabels() async {
        XCTAssertEqual(GoalMetric.newArtists.label(target: 1), "Discover 1 new artist")
        XCTAssertEqual(GoalMetric.genresExplored.label(target: 1), "Explore 1 genre")
    }

    /// Raw values are the backend's contract — `goals_set` validates against
    /// this exact set and rejects anything else.
    func testMetricRawValuesMatchTheBackend() async {
        XCTAssertEqual(
            Set(GoalMetric.allCases.map(\.rawValue)),
            ["minutes_listened", "new_artists", "genres_explored",
             "songs_from_top_artist", "unique_tracks"]
        )
    }
}
