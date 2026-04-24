import SwiftUI

/// Avatar + display name + stats row + action button. Self or other surfaces
/// differ only in which stats render and which action button sits below.
///
/// `FriendsViewModel` binding is reserved for a future phase — v1 shows a
/// placeholder "Edit" on `.me` and "Friend"/"Add Friend" on `.other` without
/// wiring the state transition.
struct ProfileHeaderView: View {

    let viewModel: UserProfileViewModel

    var body: some View {
        VStack(spacing: 16) {
            avatar
            identityBlock
            statsRow
            actionButton
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    // MARK: - Avatar

    private var avatar: some View {
        Group {
            if let url = viewModel.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    fallbackInitial
                }
            } else {
                fallbackInitial
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(
                LinearGradient(
                    colors: [.xomifyPurple, .xomifyGreen],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 3
            )
        )
        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
        .accessibilityLabel("Profile photo for \(viewModel.displayName)")
    }

    private var fallbackInitial: some View {
        ZStack {
            LinearGradient(
                colors: [.xomifyPurple, .xomifyGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initialForDisplayName)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var initialForDisplayName: String {
        let seed = viewModel.displayName.isEmpty ? viewModel.profileEmail : viewModel.displayName
        return String(seed.prefix(1)).uppercased()
    }

    // MARK: - Identity block

    private var identityBlock: some View {
        VStack(spacing: 4) {
            if viewModel.isLoading && viewModel.displayName.isEmpty {
                ProgressView()
                    .tint(.xomifyGreen)
            } else {
                Text(viewModel.displayName.isEmpty ? viewModel.profileEmail : viewModel.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
            }

            if !viewModel.profileEmail.isEmpty {
                Text(viewModel.profileEmail)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 0) {
            if let shares = viewModel.shareCount {
                statItem(value: shares, label: "Shares", color: .xomifyGreen)
                divider
            }
            if let ratings = viewModel.ratingCount {
                statItem(value: ratings, label: "Ratings", color: .xomifyPurple)
                divider
            }
            if let friends = viewModel.friendCount {
                statItem(value: friends, label: "Friends", color: .xomifyGreen)
            } else if let followers = viewModel.followersCount {
                statItem(value: followers, label: "Followers", color: .xomifyGreen)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Divider().frame(height: 30).background(Color.gray.opacity(0.25))
    }

    private func statItem(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch viewModel.context {
        case .me:
            Button {
                // Placeholder — Edit Profile sheet deferred beyond v1.
            } label: {
                Label("Edit Profile", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.xomifyCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityHint("Opens the Settings screen from the sidebar")

        case .other:
            Button {
                // Phase 2 scope is header only — friend-mutation wiring lands
                // with the Shares / Ratings tabs.
            } label: {
                Label("Message", systemImage: "envelope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.xomifyPurple)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(true)
            .accessibilityHint("Messaging is not available in this version")
        }
    }
}
