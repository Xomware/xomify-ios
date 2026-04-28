import SwiftUI

/// Root of the Feed tab. Filter chips + share list + composer FAB + empty state.
struct FeedView: View {

    @Environment(NavigationStore.self) private var navStore
    @State private var viewModel = FeedViewModel()
    @State private var showingRefinement = false
    @State private var selectedShare: Share?
    /// The view model for the composer sheet. Replaced when a deep-link track
    /// pre-loads the composer; otherwise a fresh instance on each open.
    @State private var composerViewModel = ShareComposerViewModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.xomifyDark.ignoresSafeArea()

            VStack(spacing: 0) {
                BrandGradientHeader(
                    "Feed",
                    subtitle: "What your friends are vibing to",
                    systemImage: "sparkles"
                )

                FilterChipsView(
                    viewModel: viewModel,
                    onTapRefine: { showingRefinement = true }
                )

                mainContent
            }

            if !viewModel.shares.isEmpty {
                ComposerFAB {
                    openComposer()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.bootstrap()
            await viewModel.loadGroupsForChips()
            // Consume any pending share deep link once the feed is loaded.
            await handlePendingShareDeepLink()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: Binding(
            get: { navStore.composerSheetPresented },
            set: { navStore.composerSheetPresented = $0 }
        )) {
            ShareComposerView(viewModel: composerViewModel) { share in
                Task { await viewModel.prependShareAndRefresh(share) }
            }
        }
        .sheet(isPresented: $showingRefinement) {
            FeedRefinementSheet(viewModel: viewModel) { showingRefinement = false }
                .presentationDetents([.medium, .large])
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
        } else if viewModel.filteredShares.isEmpty {
            filteredEmptyState
        } else {
            feedList
        }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(Color.xomifyPurple.opacity(0.7))
                .accessibilityHidden(true)
            Text("No posts match your filters")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Try widening the date window or clearing authors.")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                viewModel.refinement.reset()
            } label: {
                Text("Clear filters")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredShares) { share in
                    ShareCardView(
                        share: share,
                        viewerEmail: viewModel.userEmail,
                        sharerIdentity: viewModel.identity(for: share.sharedBy),
                        onDelete: {
                            Task { await viewModel.deleteShare(share) }
                        },
                        onOpenDetail: {
                            selectedShare = share
                        }
                    )
                    .padding(.horizontal, 16)
                    .onAppear {
                        if share.id == viewModel.shares.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }

                if viewModel.isLoading && !viewModel.shares.isEmpty {
                    XomifyLoaderSpin()
                        .padding(.vertical, 16)
                }

                Color.clear.frame(height: 80) // bottom inset for FAB
            }
            .padding(.top, 8)
        }
        .navigationDestination(item: $selectedShare) { share in
            ShareDetailView(
                share: share,
                viewerEmail: viewModel.userEmail,
                sharerIdentity: viewModel.identity(for: share.sharedBy)
            )
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            XomifyLoaderPulse()
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
        composerViewModel = ShareComposerViewModel()
        navStore.composerSheetPresented = true
    }

    /// If a share deep link arrived (from the Share Extension or an external
    /// URL), resolve the track from Spotify and pre-populate the composer.
    private func handlePendingShareDeepLink() async {
        guard let trackId = ShareDeepLinkCoordinator.shared.consume() else { return }
        do {
            let track = try await SpotifyService.shared.getTrack(id: trackId)
            let vm = ShareComposerViewModel()
            vm.selectTrack(track)
            composerViewModel = vm
            // Navigate to the feed tab first so the sheet appears over the
            // right screen.
            navStore.select(.feed)
            navStore.composerSheetPresented = true
        } catch {
            // Silently ignore — track lookup failed (e.g. not signed in yet).
        }
    }
}
