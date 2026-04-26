import SwiftUI

/// Top-level destination: user's recently played tracks with search and
/// cursor-based pagination. Stub — full implementation lands in Phase 3.
struct RecentlyPlayedView: View {
    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            Text("Recently Played")
                .foregroundStyle(.white)
                .font(.title2)
        }
        .navigationTitle("Recently Played")
        .navigationBarTitleDisplayMode(.inline)
    }
}
