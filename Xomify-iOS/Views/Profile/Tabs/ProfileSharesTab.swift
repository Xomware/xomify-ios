import SwiftUI

/// Shares tab on `ProfileView`. Reuses `ShareCardView` for each row so queue /
/// rate behave identically to the Feed.
struct ProfileSharesTab: View {

    @Bindable var viewModel: SharesByUserViewModel
    let context: ProfileContext
    /// Signed-in user email — passed to each `ShareCardView` so per-card
    /// actions (queue, rate) can hit the right account.
    let viewerEmail: String

    var body: some View {
        Group {
            if viewModel.isRefreshing && viewModel.shares.isEmpty {
                VStack { ProgressView().tint(.xomifyGreen) }
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if let error = viewModel.errorMessage, viewModel.shares.isEmpty {
                errorState(error)
            } else if viewModel.shares.isEmpty {
                emptyState
            } else {
                sharesList
            }
        }
        .task {
            await viewModel.bootstrap()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - List

    private var sharesList: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.shares) { share in
                ShareCardView(share: share, viewerEmail: viewerEmail)
                    .onAppear {
                        if share.id == viewModel.shares.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
            }

            if viewModel.isLoading {
                ProgressView()
                    .tint(.xomifyGreen)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - States

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(Color.xomifyGreen.opacity(0.7))
                .accessibilityHidden(true)
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(.white)
            Text(emptySubtitle)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyTitle: String {
        context.isSelf ? "Post your first track" : "No posts yet"
    }

    private var emptySubtitle: String {
        context.isSelf
        ? "When you post a song, it lands here."
        : "This user hasn't posted anything yet."
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange.opacity(0.8))
                .accessibilityHidden(true)
            Text("Couldn't load posts")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
