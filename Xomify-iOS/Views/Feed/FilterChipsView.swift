import SwiftUI

/// Horizontal scroll of filter chips: `Friends` / per-group / per-refinement.
/// Backend-scope selection is driven by `FeedViewModel.selectedFilter`;
/// the "Filters" chip opens a sheet that tunes client-side refinement.
struct FilterChipsView: View {

    @Bindable var viewModel: FeedViewModel
    let onTapRefine: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(for: .friends)

                ForEach(viewModel.groups) { group in
                    chip(for: .group(group))
                }

                Divider()
                    .frame(height: 18)
                    .overlay(Color.white.opacity(0.1))
                    .padding(.horizontal, 2)

                refineChip
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.xomifyDark)
    }

    // MARK: - Backend-scope chip

    private func chip(for filter: FeedFilter) -> some View {
        let isSelected = viewModel.selectedFilter == filter

        return Button {
            Task { await viewModel.switchFilter(filter) }
        } label: {
            Text(filter.label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 32)
                .background(isSelected ? Color.xomifyGreen : Color.xomifyCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Refine chip

    private var refineChip: some View {
        let active = viewModel.refinement.isActive
        let count = viewModel.refinement.activeCount

        return Button {
            onTapRefine()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle\(active ? ".fill" : "")")
                    .font(.caption)
                Text(active ? "Filters (\(count))" : "Filters")
                    .font(.subheadline)
                    .fontWeight(active ? .semibold : .regular)
            }
            .foregroundStyle(active ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 32)
            .background(active ? Color.xomifyGreen : Color.xomifyCard)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(active ? 0 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active ? "Filters, \(count) active" : "Filters")
        .accessibilityHint("Opens filter options")
    }
}
