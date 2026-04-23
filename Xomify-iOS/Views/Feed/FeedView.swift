import SwiftUI

/// Root of the Feed tab. Filter chips + share list + composer FAB + empty state.
struct FeedView: View {

    @Environment(NavigationStore.self) private var navStore
    @State private var viewModel = FeedViewModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.xomifyDark.ignoresSafeArea()

            VStack(spacing: 0) {
                FilterChipsView(viewModel: viewModel)

                mainContent
            }

            if !viewModel.shares.isEmpty {
                ComposerFAB {
                    openComposer()
                }
            }
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.bootstrap()
            await viewModel.loadGroupsForChips()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: Binding(
            get: { navStore.composerSheetPresented },
            set: { navStore.composerSheetPresented = $0 }
        )) {
            ShareComposerView(viewModel: ShareComposerViewModel()) { share in
                Task { await viewModel.prependShareAndRefresh(share) }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.shares.isEmpty && viewModel.isRefreshing {
            loadingState
        } else if let error = viewModel.errorMessage, viewModel.shares.isEmpty {
            errorState(error)
        } else if viewModel.shares.isEmpty {
            FeedEmptyStateView(
                onInviteFriend: { navStore.requestDeepLink(.friends) },
                onCreateGroup:  { navStore.requestDeepLink(.groups) }
            )
            .overlay(alignment: .bottomTrailing) {
                ComposerFAB { openComposer() }
            }
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
                        viewerEmail: viewModel.userEmail
                    )
                    .padding(.horizontal, 16)
                    .onAppear {
                        if share.id == viewModel.shares.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }

                if viewModel.isLoading && !viewModel.shares.isEmpty {
                    ProgressView()
                        .tint(Color.xomifyGreen)
                        .padding(.vertical, 16)
                }

                Color.clear.frame(height: 80) // bottom inset for FAB
            }
            .padding(.top, 8)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.xomifyGreen)
            Text("Loading feed...")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.orange.opacity(0.8))
            Text("Couldn't load feed")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text("Try again")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(Color.xomifyPurple)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Composer

    private func openComposer() {
        navStore.composerSheetPresented = true
    }
}
