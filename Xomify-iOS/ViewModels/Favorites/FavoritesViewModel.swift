import Foundation
import SwiftUI

/// Drives the Favorites screen: a year of ranked best-of lists.
///
/// Three "overall" lists (songs / albums / artists) always exist per year — the
/// backend auto-creates them on first write — plus any genre lists the user
/// adds.
@Observable
@MainActor
final class FavoritesViewModel {

    // MARK: - State

    private(set) var year: Int
    private(set) var lists: [FavoriteList] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    /// Which list the user is looking at. Nil until the first load resolves.
    var selectedListId: String?

    /// Recommendations for the selected list, fetched on demand.
    private(set) var recommendations: [FavoriteItem] = []
    private(set) var isLoadingRecommendations = false

    private(set) var history: [FavoriteHistoryEvent] = []
    private(set) var isLoadingHistory = false

    /// Reorders are debounced into one write — see `scheduleSave`.
    private var saveTask: Task<Void, Never>?
    private(set) var isSaving = false

    private let xomifyService: any XomifyServicing

    // MARK: - Init

    init(
        xomifyService: any XomifyServicing = XomifyService.shared,
        year: Int? = nil
    ) {
        self.xomifyService = xomifyService
        self.year = year ?? Calendar.current.component(.year, from: Date())
    }

    // MARK: - Derived

    var selectedList: FavoriteList? {
        guard let selectedListId else { return nil }
        return lists.first { $0.listId == selectedListId }
    }

    var overallLists: [FavoriteList] {
        lists.filter(\.isOverall)
    }

    var customLists: [FavoriteList] {
        lists.filter { !$0.isOverall }
    }

    /// Years offered in the picker: this year back to 2020, newest first.
    var availableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array(stride(from: current, through: 2020, by: -1))
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await xomifyService.fetchFavorites(year: year)
            lists = Self.flatten(response, year: year)
            // Keep the user on the same list across a year change where one
            // with the same id exists; otherwise fall back to the first.
            if selectedListId == nil || !lists.contains(where: { $0.listId == selectedListId }) {
                selectedListId = lists.first?.listId
            }
        } catch {
            errorMessage = error.localizedDescription
            lists = []
        }
        isLoading = false
    }

    func selectYear(_ newYear: Int) async {
        guard newYear != year else { return }
        // Flush any pending reorder before the list is replaced, or the debounce
        // fires against the wrong year.
        await flushPendingSave()
        year = newYear
        recommendations = []
        history = []
        await load()
    }

    /// Turns the API's split overall/custom shape into one flat list.
    ///
    /// The backend returns overall lists as three bare arrays under `overall`
    /// and custom lists under `lists`. The UI treats them uniformly, so the
    /// synthetic `overall:<category>` ids the backend already recognises are
    /// used here too — meaning a write to one round-trips without a special case.
    private static func flatten(_ response: FavoritesYear, year: Int) -> [FavoriteList] {
        var result: [FavoriteList] = []
        let overall = response.overall
        for category in FavoriteCategory.allCases {
            result.append(
                FavoriteList(
                    listId: "overall:\(category.rawValue)",
                    year: year,
                    category: category,
                    genreLabel: "Overall",
                    items: overall?.items(for: category) ?? []
                )
            )
        }
        result.append(contentsOf: response.lists ?? [])
        return result
    }

    // MARK: - Editing

    /// Move items within the selected list, then save.
    func move(from source: IndexSet, to destination: Int) {
        guard let index = lists.firstIndex(where: { $0.listId == selectedListId }) else { return }
        lists[index].items.move(fromOffsets: source, toOffset: destination)
        renumber(&lists[index].items)
        scheduleSave(listId: lists[index].listId)
    }

    func remove(at offsets: IndexSet) {
        guard let index = lists.firstIndex(where: { $0.listId == selectedListId }) else { return }
        lists[index].items.remove(atOffsets: offsets)
        renumber(&lists[index].items)
        scheduleSave(listId: lists[index].listId)
    }

    func add(_ item: FavoriteItem) {
        guard let index = lists.firstIndex(where: { $0.listId == selectedListId }) else { return }
        guard !lists[index].items.contains(where: { $0.spotifyId == item.spotifyId }) else { return }
        var copy = item
        copy.rank = lists[index].items.count + 1
        lists[index].items.append(copy)
        recommendations.removeAll { $0.spotifyId == item.spotifyId }
        scheduleSave(listId: lists[index].listId)
    }

    private func renumber(_ items: inout [FavoriteItem]) {
        for offset in items.indices {
            items[offset].rank = offset + 1
        }
    }

    // MARK: - Saving

    /// Debounced.
    ///
    /// Dragging a row fires a move per frame the finger crosses a boundary.
    /// Writing each one would be dozens of PUTs for one gesture, and every one
    /// of them appends rank-change history — so the audit trail would fill with
    /// intermediate positions the user never chose.
    private func scheduleSave(listId: String) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.save(listId: listId)
        }
    }

    /// Wait for any in-flight debounce so a view can leave without losing edits.
    func flushPendingSave() async {
        guard let task = saveTask else { return }
        task.cancel()
        saveTask = nil
        if let listId = selectedListId {
            await save(listId: listId)
        }
        _ = await task.result
    }

    private func save(listId: String) async {
        guard let list = lists.first(where: { $0.listId == listId }) else { return }
        isSaving = true
        do {
            let updated = try await xomifyService.setFavoritesList(
                year: year, listId: listId, items: list.items
            )
            // Adopt the server's echo so an auto-created overall list picks up
            // its real metadata.
            if let index = lists.firstIndex(where: { $0.listId == listId }) {
                lists[index] = updated
            }
        } catch {
            errorMessage = "Couldn't save that change."
        }
        isSaving = false
    }

    // MARK: - Lists

    func createList(category: FavoriteCategory, genreLabel: String) async {
        let label = genreLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        do {
            let created = try await xomifyService.createFavoritesList(
                year: year, category: category, genreLabel: label
            )
            lists.append(created)
            selectedListId = created.listId
        } catch {
            errorMessage = "Couldn't create that list."
        }
    }

    func deleteSelectedList() async {
        guard let list = selectedList, !list.isOverall else { return }
        do {
            try await xomifyService.deleteFavoritesList(year: year, listId: list.listId)
            lists.removeAll { $0.listId == list.listId }
            selectedListId = lists.first?.listId
        } catch {
            errorMessage = "Couldn't delete that list."
        }
    }

    // MARK: - Recommendations & history

    func loadRecommendations() async {
        guard let list = selectedList else { return }
        isLoadingRecommendations = true
        do {
            recommendations = try await xomifyService.fetchFavoritesRecommendations(
                year: year, category: list.category, listId: list.listId
            )
        } catch {
            recommendations = []
        }
        isLoadingRecommendations = false
    }

    func loadHistory() async {
        guard let list = selectedList else { return }
        isLoadingHistory = true
        do {
            history = try await xomifyService.fetchFavoritesHistory(listId: list.listId)
                .reversed()   // newest first; the API returns ascending
        } catch {
            history = []
        }
        isLoadingHistory = false
    }

    func dismissError() {
        errorMessage = nil
    }
}
