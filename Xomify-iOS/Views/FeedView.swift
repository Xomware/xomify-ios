import SwiftUI

/// The social feed screen.
struct FeedView: View {

    @State private var viewModel = FeedViewModel()
    @State private var isLoadingUser = true
    @State private var userEmail: String?

    private let spotifyService = SpotifyService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()
                content
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            if let email = userEmail {
                                await viewModel.refresh(email: email)
                            }
                        }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isRefreshing || isLoadingUser)
                }
            }
            .task {
                await loadUserAndFeed()
            }
            .refreshable {
                if let email = userEmail {
                    await viewModel.refresh(email: email)
                }
            }
        }
        .tint(Color.xomifyGreen)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoadingUser || viewModel.isLoading {
            loadingState
        } else if let error = viewModel.errorMessage {
            errorState(error)
        } else if viewModel.isEmpty {
            emptyState
        } else {
            feedList
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.shares) { share in
                    ShareCardView(
                        share: share,
                        viewerReaction: viewModel.myReactions[share.shareId],
                        onReact: { action in
                            guard let email = userEmail else { return }
                            Task {
                                await viewModel.react(
                                    shareId: share.shareId,
                                    email: email,
                                    action: action
                                )
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.xomifyGreen)
            Text(isLoadingUser ? "Loading profile..." : "Loading feed...")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Shares Yet")
                .font(.headline)
                .foregroundColor(.white)

            Text("Share your Wrapped or Release Radar, or follow friends to see their picks here.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange.opacity(0.7))

            Text("Error Loading Feed")
                .font(.headline)
                .foregroundColor(.white)

            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Button {
                Task { await loadUserAndFeed() }
            } label: {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.xomifyPurple)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load

    private func loadUserAndFeed() async {
        isLoadingUser = true

        do {
            let user = try await spotifyService.getCurrentUser()
            guard let email = user.email, !email.isEmpty else {
                viewModel.errorMessage = "Could not get email from Spotify"
                isLoadingUser = false
                return
            }
            userEmail = email
            print("📧 Feed: Got email: \(email)")
            await viewModel.load(email: email)
        } catch {
            print("❌ Feed: Failed to get user: \(error)")
            viewModel.errorMessage = "Failed to load user profile: \(error.localizedDescription)"
        }

        isLoadingUser = false
    }
}

#Preview {
    FeedView()
}
