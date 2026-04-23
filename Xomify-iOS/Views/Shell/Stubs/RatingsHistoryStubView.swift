import SwiftUI

/// Placeholder — real screen lands in ios-drawer-residents (#8).
/// Note: Existing RatingsView is NOT reused — #8 designs a dedicated history-style view.
struct RatingsHistoryStubView: View {
    var body: some View {
        VStack {
            Text("Coming soon")
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Ratings History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
