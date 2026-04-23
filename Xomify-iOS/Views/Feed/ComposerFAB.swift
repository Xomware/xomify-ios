import SwiftUI

/// Floating action button for the Feed tab. Triggers the share composer.
struct ComposerFAB: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient.xomifyGradient)
                    .frame(width: 56, height: 56)
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.xomifyPurple.opacity(0.4), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New share")
        .accessibilityHint("Opens the composer to share a Spotify track.")
        .padding(20)
    }
}
