import SwiftUI

// MARK: - New list

/// Create a genre list, e.g. "Hip Hop" albums.
struct NewFavoritesListSheet: View {

    let onCreate: (FavoriteCategory, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: FavoriteCategory = .songs
    @State private var label = ""

    private var canCreate: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()

                VStack(alignment: .leading, spacing: XomSpacing.lg) {
                    Picker("Category", selection: $category) {
                        ForEach(FavoriteCategory.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: XomSpacing.xs) {
                        Text("Genre or theme")
                            .font(.xomifyCaption)
                            .foregroundStyle(.gray)
                        TextField("Hip Hop", text: $label)
                            .textFieldStyle(.plain)
                            .padding(XomSpacing.md)
                            .background(Color.xomifyCard)
                            .clipShape(RoundedRectangle(cornerRadius: XomRadius.lg, style: .continuous))
                            .foregroundStyle(.white)
                            .submitLabel(.done)
                            .onSubmit { create() }
                    }

                    Text("Overall lists already exist for every year. This adds a separate ranking you can keep alongside them.")
                        .font(.xomifyCaption)
                        .foregroundStyle(.gray)

                    Spacer()
                }
                .padding(XomSpacing.lg)
            }
            .navigationTitle("New list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { create() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canCreate ? Color.xomifyGreen : Color.gray)
                        .disabled(!canCreate)
                }
            }
        }
    }

    private func create() {
        guard canCreate else { return }
        onCreate(category, label)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Recommendations

/// Suggestions drawn from the caller's own listening, excluding anything
/// already in the list.
struct FavoritesRecommendationsSheet: View {

    let viewModel: FavoritesViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()

                if viewModel.isLoadingRecommendations {
                    XomifyLoaderPulse(size: 48)
                } else if viewModel.recommendations.isEmpty {
                    VStack(spacing: XomSpacing.sm) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 34))
                            .foregroundStyle(.gray)
                        Text("Nothing to suggest")
                            .font(.xomifyHeadline)
                            .foregroundStyle(.white)
                        Text("Either this list already has your top picks, or there isn't enough listening yet.")
                            .font(.xomifyFootnote)
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, XomSpacing.xl)
                    }
                } else {
                    List {
                        ForEach(viewModel.recommendations) { item in
                            Button {
                                viewModel.add(item)
                                Haptics.success()
                            } label: {
                                HStack(spacing: XomSpacing.md) {
                                    AsyncImage(url: item.imageUrl.flatMap(URL.init(string:))) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Color.xomifySecondary
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.xomifySubheadline)
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        if let artist = item.artist, !artist.isEmpty {
                                            Text(artist)
                                                .font(.xomifyCaption)
                                                .foregroundStyle(.gray)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.xomifyGreen)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.xomifyCard)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Add from your listening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(.white)
                }
            }
            .task { await viewModel.loadRecommendations() }
        }
    }
}

// MARK: - History

/// Rank changes over time. The backend records one event per changed rank on
/// every write, which is what makes "it was #3 in March" answerable at all.
struct FavoritesHistorySheet: View {

    let viewModel: FavoritesViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()

                if viewModel.isLoadingHistory {
                    XomifyLoaderPulse(size: 48)
                } else if viewModel.history.isEmpty {
                    VStack(spacing: XomSpacing.sm) {
                        Image(systemName: "clock")
                            .font(.system(size: 34))
                            .foregroundStyle(.gray)
                        Text("No changes yet")
                            .font(.xomifyHeadline)
                            .foregroundStyle(.white)
                        Text("Reorder this list and the moves show up here.")
                            .font(.xomifyFootnote)
                            .foregroundStyle(.gray)
                    }
                } else {
                    List {
                        ForEach(viewModel.history) { event in
                            HStack(spacing: XomSpacing.md) {
                                Image(systemName: icon(for: event))
                                    .foregroundStyle(colour(for: event))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(describe(event))
                                        .font(.xomifySubheadline)
                                        .foregroundStyle(.white)
                                    Text(event.ts)
                                        .font(.xomifyCaption)
                                        .foregroundStyle(.gray)
                                }
                                Spacer()
                            }
                            .listRowBackground(Color.xomifyCard)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Rank history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(.white)
                }
            }
            .task { await viewModel.loadHistory() }
        }
    }

    private func describe(_ event: FavoriteHistoryEvent) -> String {
        switch event.change {
        case .added(let to):            return "Added at #\(to)"
        case .removed(let from):        return "Removed from #\(from)"
        case .moved(let from, let to):  return "#\(from) → #\(to)"
        case nil:                       return "Unchanged"
        }
    }

    private func icon(for event: FavoriteHistoryEvent) -> String {
        switch event.change {
        case .added:   return "plus.circle.fill"
        case .removed: return "minus.circle.fill"
        case .moved(let from, let to):
            return to < from ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
        case nil:      return "circle"
        }
    }

    private func colour(for event: FavoriteHistoryEvent) -> Color {
        switch event.change {
        case .added:   return .xomifyGreen
        case .removed: return .orange
        case .moved(let from, let to):
            return to < from ? .xomifyGreen : .gray
        case nil:      return .gray
        }
    }
}
