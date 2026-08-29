import SwiftUI

/// Social profile screen. Renders identity header + `Shares / Ratings / Taste`
/// tabs. The same view backs both the signed-in user (`.me`) and any other
/// user (`.other(email:)`) — the old `FriendProfileView` is subsumed here.
struct ProfileView: View {

    @State private var viewModel: UserProfileViewModel
    @Namespace private var tabNamespace

    init(context: ProfileContext = .me) {
        _viewModel = State(wrappedValue: UserProfileViewModel(context: context))
    }

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            content
        }
        .navigationTitle(viewModel.displayName.isEmpty ? "Profile" : viewModel.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Force the system nav bar visible so pushed destinations (friend
        // profile from FriendsView) surface the default back button even
        // though the parent tab view (`.toolbar(.hidden)`) suppresses it.
        .toolbar(.visible, for: .navigationBar)
        .task {
            await viewModel.loadHeader()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.displayName.isEmpty {
            VStack { XomifyLoaderPaint(size: 40) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.displayName.isEmpty {
            errorState(error)
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                ProfileHeaderView(viewModel: viewModel)
                    .padding(.top, 12)

                ProfileTabPicker(
                    selection: Binding(
                        get: { viewModel.selectedTab },
                        set: { viewModel.selectedTab = $0 }
                    ),
                    namespace: tabNamespace,
                    tabs: viewModel.visibleTabs
                )

                tabContent
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .shares:
            if let sharesVM = viewModel.sharesViewModel() {
                ProfileSharesTab(
                    viewModel: sharesVM,
                    context: viewModel.context,
                    viewerEmail: viewModel.callerEmail,
                    sharerIdentity: SharerIdentity(
                        displayName: viewModel.displayName.isEmpty ? viewModel.profileEmail : viewModel.displayName,
                        avatarURL: viewModel.avatarURL
                    )
                )
            } else {
                loadingTab
            }

        case .ratings:
            ProfileRatingsTab(
                viewModel: viewModel.ratingsViewModel(),
                context: viewModel.context,
                viewerEmail: viewModel.callerEmail
            )

        case .taste:
            ProfileTasteTab(viewModel: viewModel)

        case .playlists:
            ProfilePlaylistsTab(viewModel: viewModel.playlistsViewModel())

        case .recent:
            ProfileRecentTab()
        }
    }

    private var loadingTab: some View {
        XomifyLoaderPaint(size: 36)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: - Error state

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange.opacity(0.7))
            Text("Could not load profile")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Self") {
    NavigationStack {
        ProfileView(context: .me)
    }
}

#Preview("Other") {
    NavigationStack {
        ProfileView(context: .other(email: "friend@example.com"))
    }
}
