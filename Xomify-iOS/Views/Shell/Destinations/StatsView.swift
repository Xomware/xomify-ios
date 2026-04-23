import SwiftUI

/// Combined Top Items + Wrapped screen pushed from the drawer.
/// Uses a segmented picker to swap between the two bodies.
struct StatsView: View {

    // MARK: - Sub-nav tabs

    enum StatsTab: String, CaseIterable, Hashable, Identifiable {
        case topItems = "Top Items"
        case wrapped = "Wrapped"

        var id: String { rawValue }
    }

    @State private var selected: StatsTab = .topItems

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Picker("Stats section", selection: $selected) {
                ForEach(StatsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.xomifyCard)

            content
        }
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch selected {
        case .topItems:
            TopItemsContent()
        case .wrapped:
            WrappedContent()
        }
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
}
