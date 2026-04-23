import SwiftUI

/// Placeholder — real screen lands in ios-drawer-residents (#8).
struct StatsStubView: View {
    var body: some View {
        VStack {
            Text("Coming soon")
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }
}
