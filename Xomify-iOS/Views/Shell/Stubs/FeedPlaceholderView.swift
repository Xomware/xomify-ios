import SwiftUI

/// Feed tab placeholder until ios-feed (#5) ships.
/// Route stays wired — real content drops in without shell changes.
struct FeedPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.xomifyGreen.opacity(0.6))

                Text("Feed coming soon")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Social feed lands in a future update.")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.xomifyDark.ignoresSafeArea())
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
