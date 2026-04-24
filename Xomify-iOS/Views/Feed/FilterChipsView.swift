import SwiftUI

/// Horizontal scroll of filter chips: `All` / `Friends only` / per-group.
/// Selection is driven by `FeedViewModel.selectedFilter`.
struct FilterChipsView: View {

    @Bindable var viewModel: FeedViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(for: .friends)

                ForEach(viewModel.groups) { group in
                    chip(for: .group(group))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.xomifyDark)
    }

    // MARK: - Chip

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
}
