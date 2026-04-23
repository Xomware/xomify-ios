import SwiftUI

/// Empty state shown when the feed has no shares. Dual-CTA: primary routes to
/// Friends invite flow; secondary routes to Groups.
struct FeedEmptyStateView: View {

    let onInviteFriend: () -> Void
    let onCreateGroup: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(LinearGradient.xomifyGradient)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("No shares yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Invite a friend or create a group to start seeing shared tracks here.")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button(action: onInviteFriend) {
                    Text("Invite a friend")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(LinearGradient.xomifyGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the Friends screen to share an invite.")

                Button(action: onCreateGroup) {
                    Text("Create a group")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.xomifyGreen)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .overlay(
                            Capsule().stroke(Color.xomifyGreen, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the Groups screen to create a new group.")
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
