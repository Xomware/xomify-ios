import SwiftUI

/// Read-only profile of another user (pushed from FriendsView / CompareView).
struct FriendProfileView: View {

    let profileEmail: String
    let viewerEmail: String

    @State private var viewModel = FriendProfileViewModel()

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            content
        }
        .navigationTitle(viewModel.profile?.displayName ?? profileEmail)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(viewerEmail: viewerEmail, profileEmail: profileEmail)
        }
        .tint(Color.xomifyGreen)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .tint(.xomifyGreen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.orange.opacity(0.7))
                Text("Could not load profile")
                    .font(.headline).foregroundColor(.white)
                Text(error)
                    .font(.caption).foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statsRow
                    section(title: "Top Artists", items: viewModel.topArtistNames)
                    section(title: "Top Songs", items: viewModel.topSongNames)
                    section(title: "Top Genres", items: viewModel.topGenres)
                }
                .padding()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient.xomifyGradient)
                    .frame(width: 72, height: 72)
                let label = viewModel.profile?.displayName ?? profileEmail
                Text(String(label.prefix(1)).uppercased())
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.profile?.displayName ?? profileEmail)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(profileEmail)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: viewModel.profile?.playlistCount ?? 0, label: "Playlists", color: .xomifyPurple)
            divider
            statItem(value: viewModel.profile?.followersCount ?? 0, label: "Followers", color: .xomifyGreen)
            divider
            statItem(value: viewModel.profile?.friendsCount ?? 0, label: "Friends", color: .xomifyPurple)
        }
        .padding(.vertical, 14)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    private var divider: some View {
        Divider().frame(height: 30).background(Color.gray.opacity(0.3))
    }

    private func statItem(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3).fontWeight(.bold).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Horizontal section

    @ViewBuilder
    private func section(title: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(items.prefix(20).enumerated()), id: \.offset) { _, item in
                            tile(item)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ label: String) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(width: 110, height: 60)
            .padding(.horizontal, 8)
            .background(Color.xomifyCard)
            .cornerRadius(10)
    }
}

#Preview {
    NavigationStack {
        FriendProfileView(profileEmail: "foo@bar.com", viewerEmail: "me@me.com")
    }
}
