import SwiftUI

/// My Favorites — ranked best-of lists per year.
///
/// Web parity (`xomify-frontend/src/app/pages/favorites`). Reordering is a
/// native drag on a `List` rather than the web's arrow buttons: dragging is
/// what a phone is for, and the whole feature is ordering things.
struct FavoritesView: View {

    @State private var viewModel = FavoritesViewModel()
    @State private var showingNewList = false
    @State private var showingRecommendations = false
    @State private var showingHistory = false
    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()

            if viewModel.isLoading {
                XomifyLoaderPaint(size: 64)
            } else {
                content
            }
        }
        .navigationTitle("My Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await viewModel.load() }
        // Any pending reorder is flushed on the way out — a debounce that
        // outlives its screen is a silently dropped edit.
        .onDisappear { Task { await viewModel.flushPendingSave() } }
        .sheet(isPresented: $showingNewList) {
            NewFavoritesListSheet { category, label in
                Task { await viewModel.createList(category: category, genreLabel: label) }
            }
        }
        .sheet(isPresented: $showingRecommendations) {
            FavoritesRecommendationsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingHistory) {
            FavoritesHistorySheet(viewModel: viewModel)
        }
        .alert("Delete this list?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteSelectedList() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(viewModel.selectedList?.displayTitle ?? "This list") and its ranking will be removed.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            yearStrip
            listStrip

            if let list = viewModel.selectedList {
                if list.items.isEmpty {
                    emptyState(for: list)
                } else {
                    itemsList(for: list)
                }
            } else {
                emptyYearState
            }
        }
    }

    private var yearStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XomSpacing.sm) {
                ForEach(viewModel.availableYears, id: \.self) { year in
                    Button {
                        Task { await viewModel.selectYear(year) }
                    } label: {
                        Text(String(year))
                            .font(.xomifyFootnote)
                            .fontWeight(year == viewModel.year ? .bold : .regular)
                            .foregroundStyle(year == viewModel.year ? Color.black : Color.white)
                            .padding(.horizontal, XomSpacing.md)
                            .padding(.vertical, XomSpacing.sm)
                            .background(year == viewModel.year ? Color.xomifyGreen : Color.xomifyCard)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, XomSpacing.md)
        }
        .padding(.vertical, XomSpacing.sm)
    }

    private var listStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XomSpacing.sm) {
                ForEach(viewModel.overallLists + viewModel.customLists) { list in
                    chip(for: list)
                }

                Button {
                    showingNewList = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.xomifyCaption)
                        .foregroundStyle(Color.xomifyGreen)
                        .padding(.horizontal, XomSpacing.md)
                        .padding(.vertical, XomSpacing.sm)
                        .overlay(Capsule().stroke(Color.xomifyGreen.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, XomSpacing.md)
        }
        .padding(.bottom, XomSpacing.sm)
    }

    private func chip(for list: FavoriteList) -> some View {
        let selected = list.listId == viewModel.selectedListId
        return Button {
            viewModel.selectedListId = list.listId
        } label: {
            HStack(spacing: 5) {
                Image(systemName: list.category.systemImage)
                    .font(.caption2)
                Text(list.displayTitle)
                    .font(.xomifyCaption)
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.5))
            .padding(.horizontal, XomSpacing.md)
            .padding(.vertical, XomSpacing.sm)
            .background(selected ? Color.xomifyPurple : Color.xomifyCard)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private func itemsList(for list: FavoriteList) -> some View {
        List {
            ForEach(list.items) { item in
                FavoriteRow(item: item)
                    .listRowBackground(Color.xomifyCard)
            }
            .onMove { source, destination in
                viewModel.move(from: source, to: destination)
                Haptics.selection()
            }
            .onDelete { offsets in
                viewModel.remove(at: offsets)
                Haptics.light()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Always-on edit mode: the drag handles ARE the feature, and hiding
        // them behind an Edit button means most people never find them.
        .environment(\.editMode, .constant(.active))
    }

    private func emptyState(for list: FavoriteList) -> some View {
        VStack(spacing: XomSpacing.md) {
            Spacer()
            Image(systemName: list.category.systemImage)
                .font(.system(size: 38))
                .foregroundStyle(.white.opacity(0.5))
            Text("No \(list.category.singular)s yet")
                .font(.xomifyTitle3)
                .foregroundStyle(.white)
            Text("Add from your listening, then drag to rank them.")
                .font(.xomifyFootnote)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button("Add from your top \(list.category.rawValue)") {
                showingRecommendations = true
            }
            .font(.xomifyFootnote)
            .fontWeight(.semibold)
            .foregroundStyle(Color.xomifyGreen)
            .frame(minHeight: 44)
            Spacer()
        }
        .padding(.horizontal, XomSpacing.xl)
    }

    private var emptyYearState: some View {
        VStack(spacing: XomSpacing.sm) {
            Spacer()
            Text("Nothing for \(String(viewModel.year))")
                .font(.xomifyTitle3)
                .foregroundStyle(.white)
            Spacer()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showingRecommendations = true
                } label: {
                    Label("Add from your listening", systemImage: "sparkles")
                }

                Button {
                    showingHistory = true
                } label: {
                    Label("Rank history", systemImage: "clock.arrow.circlepath")
                }

                if let list = viewModel.selectedList, !list.isOverall {
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete list", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.white)
            }
            .disabled(viewModel.selectedList == nil)
        }

        ToolbarItem(placement: .topBarLeading) {
            if viewModel.isSaving {
                ProgressView().tint(.white)
            }
        }
    }
}

// MARK: - Row

private struct FavoriteRow: View {
    let item: FavoriteItem

    var body: some View {
        HStack(spacing: XomSpacing.md) {
            Text("\(item.rank)")
                .font(.xomifyCaption)
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 22, alignment: .trailing)

            AsyncImage(url: item.imageUrl.flatMap(URL.init(string:))) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.xomifySecondary
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.xomifySubheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artist = item.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.xomifyCaption)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, XomSpacing.xs)
    }
}
