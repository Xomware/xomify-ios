import SwiftUI

/// Sheet that tunes client-side feed refinement: date window, authors,
/// unlistened-only, and sort order. All knobs are applied locally — the
/// backend feed query doesn't re-run when the user changes any of these.
struct FeedRefinementSheet: View {

    @Bindable var viewModel: FeedViewModel
    let onDismiss: () -> Void

    /// Drives the searchable author picker. Surfaced as a separate sheet so
    /// the refinement sheet stays compact regardless of friend count — the
    /// previous pill-per-friend grid didn't scale past ~30 friends.
    @State private var showAuthorPicker: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        dateSection
                        authorsSection
                        unlistenedSection
                        sortSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.refinement.isActive {
                        Button("Clear") {
                            viewModel.refinement.reset()
                        }
                        .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Color.xomifyGreen)
        .sheet(isPresented: $showAuthorPicker) {
            AuthorPickerSheet(viewModel: viewModel) {
                showAuthorPicker = false
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Date

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Date", icon: "calendar")

            WrappingChipGrid {
                ForEach(FeedRefinement.DateWindow.allCases) { window in
                    pillChip(
                        label: window.label,
                        selected: viewModel.refinement.dateWindow == window
                    ) {
                        viewModel.refinement.dateWindow = window
                    }
                }
            }
        }
    }

    // MARK: - Authors

    @ViewBuilder
    private var authorsSection: some View {
        let authors = viewModel.availableAuthors
        let selectedCount = viewModel.refinement.authors.count

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("From", icon: "person.2")
                Spacer()
                if selectedCount > 0 {
                    Button("Clear") {
                        viewModel.refinement.authors = []
                    }
                    .font(.caption)
                    .foregroundStyle(Color.xomifyGreen)
                }
            }

            if authors.isEmpty {
                Text("No authors in the current feed yet.")
                    .font(.caption)
                    .foregroundStyle(.gray)
            } else {
                authorPickerButton(totalAuthors: authors.count, selectedCount: selectedCount)
            }
        }
    }

    /// Single-tap surface that opens the searchable picker. Replaces the
    /// pill-per-friend grid that used to live here; the grid's visual weight
    /// scaled linearly with friend count and was unusable past ~30 names.
    private func authorPickerButton(totalAuthors: Int, selectedCount: Int) -> some View {
        Button {
            showAuthorPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.body)
                    .foregroundStyle(Color.xomifyGreen)

                VStack(alignment: .leading, spacing: 2) {
                    Text(authorButtonTitle(selectedCount: selectedCount, total: totalAuthors))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                    Text(authorButtonSubtitle(selectedCount: selectedCount, total: totalAuthors))
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(12)
            .frame(minHeight: 44)
            .background(Color.xomifyCard)
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("From \(authorButtonTitle(selectedCount: selectedCount, total: totalAuthors))")
        .accessibilityHint("Opens the friend picker")
    }

    private func authorButtonTitle(selectedCount: Int, total: Int) -> String {
        switch selectedCount {
        case 0:    return "All friends"
        case 1:    return "1 friend selected"
        default:   return "\(selectedCount) friends selected"
        }
    }

    private func authorButtonSubtitle(selectedCount: Int, total: Int) -> String {
        if selectedCount == 0 {
            return "Showing posts from everyone in this feed"
        }
        return "Tap to add or remove friends · \(total) available"
    }

    // MARK: - Unlistened

    private var unlistenedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Listening status", icon: "headphones")
            Toggle(isOn: $viewModel.refinement.onlyUnlistened) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Only show posts I haven't queued")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Text("Hides anything you've already added to your Spotify queue.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            .tint(Color.xomifyGreen)
            .padding(12)
            .background(Color.xomifyCard)
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    // MARK: - Sort

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Sort", icon: "arrow.up.arrow.down")
            WrappingChipGrid {
                ForEach(FeedRefinement.SortOrder.allCases) { order in
                    pillChip(
                        label: order.label,
                        selected: viewModel.refinement.sortOrder == order
                    ) {
                        viewModel.refinement.sortOrder = order
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.xomifyGreen)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
    }

    private func pillChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? Color.black : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(selected ? Color.xomifyGreen : Color.xomifyCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(selected ? 0 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Wrapping chip grid

/// Minimal flow-layout so chips wrap onto multiple rows in the filter sheet.
private struct WrappingChipGrid<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        ChipFlow { content }
    }
}

private struct ChipFlow: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth && rowWidth > 0 {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth - spacing)
        return CGSize(width: maxRowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            _ = maxWidth
        }
    }
}
