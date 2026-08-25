import SwiftUI

/// Avatar + display name + stats row + action button. Self or other surfaces
/// differ only in which stats render and which action button sits below.
///
/// `FriendsViewModel` binding is reserved for a future phase — v1 shows a
/// placeholder "Edit" on `.me` and "Friend"/"Add Friend" on `.other` without
/// wiring the state transition.
struct ProfileHeaderView: View {

    let viewModel: UserProfileViewModel
    @Environment(NavigationStore.self) private var navStore

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
            if isInitialLoading {
                Circle().fill(Color.gray.opacity(0.2))
            } else if let url = viewModel.avatarURL {
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
                XomifyLoaderSpin()
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
            if isInitialLoading {
                skeletonStat
                divider
                skeletonStat
                divider
                skeletonStat
            } else {
                statItem(
                    value: viewModel.friendCount ?? 0,
                    label: "Friends",
                    color: .xomifyGreen,
                    destination: .friends
                )
                divider
                statItem(
                    value: viewModel.ratingCount ?? 0,
                    label: "Ratings",
                    color: .xomifyPurple,
                    destination: .ratings
                )
                divider
                statItem(
                    value: viewModel.shareCount ?? 0,
                    label: "Posts",
                    color: .xomifyGreen,
                    destination: .feed
                )
                // Likes chip — shown for self and friends when likesCount is
                // present. Backend omits likesCount when likes_public=false
                // (or when the backend hasn't synced yet), so nil auto-hides.
                if let likesCount = viewModel.likesCount {
                    divider
                    statItem(
                        value: likesCount,
                        label: "Likes",
                        color: .xomifyGreen,
                        destination: viewModel.context.isSelf
                            ? .likes
                            : .friendLikes(email: viewModel.profileEmail)
                    )
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: XomRadius.xl, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    /// True on first load, before any header field has populated. Drives
    /// skeleton placeholders in the stats row so the layout doesn't jump
    /// when real values arrive.
    private var isInitialLoading: Bool {
        viewModel.isLoading && viewModel.displayName.isEmpty
    }

    private var skeletonStat: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: XomRadius.sm, style: .continuous)
                .fill(Color.gray.opacity(0.25))
                .frame(width: 28, height: 16)
            RoundedRectangle(cornerRadius: XomRadius.sm, style: .continuous)
                .fill(Color.gray.opacity(0.18))
                .frame(width: 44, height: 8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var divider: some View {
        Divider().frame(height: 30).background(Color.gray.opacity(0.25))
    }

    private func statItem(
        value: Int,
        label: String,
        color: Color,
        destination: SidebarDestination?
    ) -> some View {
        // Both self and friend profiles can tap stat tiles to drill in.
        // Friend-scoped FriendsView / RatingsView / posts-feed scoping is a
        // follow-up item — for now taps land on viewer-scoped destinations,
        // which is better than being silently disabled.
        let isTappable = destination != nil

        let content = VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())

        return Group {
            if isTappable, let destination {
                Button {
                    navStore.select(destination)
                } label: {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(label): \(value)")
                .accessibilityHint("Opens \(label) page")
            } else {
                content
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(label): \(value)")
            }
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch viewModel.context {
        case .me:
            Button {
                navStore.select(.settings)
            } label: {
                Label("Edit Profile", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.xomifyCard)
                    .clipShape(RoundedRectangle(cornerRadius: XomRadius.lg, style: .continuous))
            }
            .accessibilityHint("Opens Settings")

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
                    .clipShape(RoundedRectangle(cornerRadius: XomRadius.lg, style: .continuous))
            }
            .disabled(true)
            .accessibilityHint("Messaging is not available in this version")
        }
    }
}
