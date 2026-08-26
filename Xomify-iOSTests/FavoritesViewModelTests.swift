import XCTest
@testable import Xomify_iOS

@MainActor
final class FavoritesViewModelTests: XCTestCase {

    private func item(_ id: String, rank: Int) -> FavoriteItem {
        FavoriteItem(rank: rank, spotifyId: id, name: "Track \(id)", artist: "Artist", imageUrl: nil)
    }

    private func makeVM(_ mock: MockXomifyServicing) -> FavoritesViewModel {
        FavoritesViewModel(xomifyService: mock, year: 2026)
    }

    // MARK: - Loading

    func test_load_synthesisesTheThreeOverallLists() async {
        // The API returns overall lists as three bare arrays, not as list
        // objects. They still have to appear as first-class lists in the UI.
        let mock = MockXomifyServicing()
        mock.favoritesYear = FavoritesYear(
            year: 2026,
            overall: FavoritesOverall(songs: [item("a", rank: 1)], albums: nil, artists: nil),
            lists: nil
        )
        let vm = makeVM(mock)
        await vm.load()

        XCTAssertEqual(vm.overallLists.count, 3)
        XCTAssertEqual(Set(vm.overallLists.map(\.category)), Set(FavoriteCategory.allCases))
        XCTAssertEqual(vm.overallLists.first { $0.category == .songs }?.items.count, 1)
    }

    func test_overallListIdsMatchWhatTheBackendAutoCreates() async {
        // `overall:<category>` is the id the backend recognises and auto-creates
        // on first write. Inventing a different one here means the first save
        // 404s.
        let mock = MockXomifyServicing()
        let vm = makeVM(mock)
        await vm.load()

        XCTAssertTrue(vm.overallLists.allSatisfy { $0.listId.hasPrefix("overall:") })
        XCTAssertTrue(vm.overallLists.contains { $0.listId == "overall:songs" })
    }

    func test_load_keepsCustomListsAlongsideOverall() async {
        let mock = MockXomifyServicing()
        mock.favoritesYear = FavoritesYear(
            year: 2026, overall: nil,
            lists: [FavoriteList(listId: "l1", year: 2026, category: .albums,
                                 genreLabel: "Hip Hop", items: [])]
        )
        let vm = makeVM(mock)
        await vm.load()

        XCTAssertEqual(vm.lists.count, 4)
        XCTAssertEqual(vm.customLists.map(\.displayTitle), ["Hip Hop"])
    }

    func test_load_selectsAListSoTheScreenIsNeverBlank() async {
        let vm = makeVM(MockXomifyServicing())
        await vm.load()
        XCTAssertNotNil(vm.selectedListId)
    }

    func test_load_surfacesAnError() async {
        let mock = MockXomifyServicing()
        mock.favoritesError = NSError(domain: "t", code: 1)
        let vm = makeVM(mock)
        await vm.load()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.lists.isEmpty)
    }

    // MARK: - Editing

    func test_move_renumbersRanks() async {
        // Rank is position, so it must be recomputed on every reorder — a stale
        // rank is what the server writes into history.
        let mock = MockXomifyServicing()
        mock.favoritesYear = FavoritesYear(
            year: 2026,
            overall: FavoritesOverall(
                songs: [item("a", rank: 1), item("b", rank: 2), item("c", rank: 3)],
                albums: nil, artists: nil
            ),
            lists: nil
        )
        let vm = makeVM(mock)
        await vm.load()
        vm.selectedListId = "overall:songs"

        vm.move(from: IndexSet(integer: 2), to: 0)

        let items = vm.selectedList?.items ?? []
        XCTAssertEqual(items.map(\.spotifyId), ["c", "a", "b"])
        XCTAssertEqual(items.map(\.rank), [1, 2, 3])
    }

    func test_add_ignoresADuplicate() async {
        let mock = MockXomifyServicing()
        mock.favoritesYear = FavoritesYear(
            year: 2026,
            overall: FavoritesOverall(songs: [item("a", rank: 1)], albums: nil, artists: nil),
            lists: nil
        )
        let vm = makeVM(mock)
        await vm.load()
        vm.selectedListId = "overall:songs"

        vm.add(item("a", rank: 99))

        XCTAssertEqual(vm.selectedList?.items.count, 1)
    }

    func test_add_appendsAtTheEndWithTheNextRank() async {
        let mock = MockXomifyServicing()
        mock.favoritesYear = FavoritesYear(
            year: 2026,
            overall: FavoritesOverall(songs: [item("a", rank: 1)], albums: nil, artists: nil),
            lists: nil
        )
        let vm = makeVM(mock)
        await vm.load()
        vm.selectedListId = "overall:songs"

        vm.add(item("b", rank: 0))

        XCTAssertEqual(vm.selectedList?.items.map(\.rank), [1, 2])
        XCTAssertEqual(vm.selectedList?.items.last?.spotifyId, "b")
    }

    func test_remove_renumbersWhatIsLeft() async {
        let mock = MockXomifyServicing()
        mock.favoritesYear = FavoritesYear(
            year: 2026,
            overall: FavoritesOverall(
                songs: [item("a", rank: 1), item("b", rank: 2), item("c", rank: 3)],
                albums: nil, artists: nil
            ),
            lists: nil
        )
        let vm = makeVM(mock)
        await vm.load()
        vm.selectedListId = "overall:songs"

        vm.remove(at: IndexSet(integer: 0))

        XCTAssertEqual(vm.selectedList?.items.map(\.rank), [1, 2])
    }

    // MARK: - Saving

    func test_reordersAreDebouncedIntoOneWrite() async {
        // Dragging fires a move per crossed boundary. Writing each one is dozens
        // of PUTs for one gesture — and every one appends rank history, filling
        // the audit trail with positions the user never chose.
        let mock = MockXomifyServicing()
        mock.favoritesYear = FavoritesYear(
            year: 2026,
            overall: FavoritesOverall(
                songs: [item("a", rank: 1), item("b", rank: 2), item("c", rank: 3)],
                albums: nil, artists: nil
            ),
            lists: nil
        )
        let vm = makeVM(mock)
        await vm.load()
        vm.selectedListId = "overall:songs"

        vm.move(from: IndexSet(integer: 0), to: 3)
        vm.move(from: IndexSet(integer: 0), to: 2)
        vm.move(from: IndexSet(integer: 1), to: 0)

        XCTAssertTrue(mock.setListCalls.isEmpty, "must not write mid-gesture")

        await vm.flushPendingSave()
        XCTAssertEqual(mock.setListCalls.count, 1, "one gesture, one write")
    }

    func test_deleteRefusesToRemoveAnOverallList() async {
        // Overall lists are structural — the backend recreates them anyway.
        let vm = makeVM(MockXomifyServicing())
        await vm.load()
        vm.selectedListId = "overall:songs"

        await vm.deleteSelectedList()

        XCTAssertEqual(vm.overallLists.count, 3)
    }

    func test_createList_selectsTheNewList() async {
        let mock = MockXomifyServicing()
        let vm = makeVM(mock)
        await vm.load()

        await vm.createList(category: .albums, genreLabel: "Hip Hop")

        XCTAssertEqual(mock.createListCalls.first?.label, "Hip Hop")
        XCTAssertEqual(vm.selectedList?.displayTitle, "Hip Hop")
    }

    func test_createList_ignoresABlankLabel() async {
        let mock = MockXomifyServicing()
        let vm = makeVM(mock)
        await vm.load()

        await vm.createList(category: .songs, genreLabel: "   ")

        XCTAssertTrue(mock.createListCalls.isEmpty)
    }

    // MARK: - History

    func test_historyEventsClassifyThemselves() async {
        let added = FavoriteHistoryEvent(ts: "t", spotifyId: "a", fromRank: nil, toRank: 3)
        let removed = FavoriteHistoryEvent(ts: "t", spotifyId: "a", fromRank: 2, toRank: nil)
        let moved = FavoriteHistoryEvent(ts: "t", spotifyId: "a", fromRank: 5, toRank: 1)

        if case .added(let to) = added.change { XCTAssertEqual(to, 3) } else { XCTFail("added") }
        if case .removed(let from) = removed.change { XCTAssertEqual(from, 2) } else { XCTFail("removed") }
        if case .moved(let from, let to) = moved.change {
            XCTAssertEqual(from, 5); XCTAssertEqual(to, 1)
        } else { XCTFail("moved") }
    }

    func test_historyIsNewestFirst() async {
        // The API returns ascending; a change log reads newest-first.
        let mock = MockXomifyServicing()
        mock.favoritesHistory = [
            FavoriteHistoryEvent(ts: "2026-01-01", spotifyId: "a", fromRank: nil, toRank: 1),
            FavoriteHistoryEvent(ts: "2026-02-01", spotifyId: "b", fromRank: nil, toRank: 2),
        ]
        let vm = makeVM(mock)
        await vm.load()
        vm.selectedListId = "overall:songs"

        await vm.loadHistory()

        XCTAssertEqual(vm.history.first?.ts, "2026-02-01")
    }
}
