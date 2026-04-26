import SwiftUI

/// Top-level destination: user's full Spotify liked-songs library with
/// search and infinite scroll. Stub — full implementation lands in Phase 2.
struct LikesView: View {
    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            Text("Likes")
                .foregroundStyle(.white)
                .font(.title2)
        }
        .navigationTitle("Likes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
