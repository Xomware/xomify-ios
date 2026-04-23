import SwiftUI

/// Friends screen: four segmented tabs (Friends / Requests / Invites / Find).
struct FriendsView: View {

    @State private var viewModel = FriendsViewModel()
    @State private var isLoadingUser = true
    @State private var userEmail: String?
    @State private var selectedTab: Tab = .friends
    @State private var searchText: String = ""

    /// Friend queued for removal; drives the confirmation dialog.
    @State private var friendPendingRemoval: Friend?

    /// Whether the iOS share sheet is currently presented for a minted invite.
    @State private var isShareSheetPresented: Bool = false

    private let spotifyService = SpotifyService.shared
    private let inviteCoordinator = InviteCoordinator.shared

    enum Tab: String, CaseIterable, Identifiable {
        case friends = "Friends"
        case requests = "Requests"
        case invites = "Invites"
        case find = "Find"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()

            VStack(spacing: 0) {
                tabPicker
                searchField
                content
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await loadUserAndData() }
        .tint(Color.xomifyGreen)
        .confirmationDialog(
            removalConfirmationTitle,
            isPresented: Binding(
                get: { friendPendingRemoval != nil },
                set: { if !$0 { friendPendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: friendPendingRemoval
        ) { friend in
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.remove(friend)
                    friendPendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) {
                friendPendingRemoval = nil
            }
        } message: { friend in
            Text("\(friend.label) will no longer be your friend on Xomify.")
        }
        .sheet(isPresented: $isShareSheetPresented, onDismiss: {
            viewModel.clearMintedInvite()
        }) {
            if let url = viewModel.lastMintedInvite {
                InviteShareSheet(url: url)
                    .presentationDetents([.medium])
            }
        }
        .onChange(of: viewModel.lastMintedInvite) { _, new in
            // Auto-present the share sheet as soon as the mint lands.
            isShareSheetPresented = new != nil
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await viewModel.mintInvite() }
            } label: {
                if viewModel.isMintingInvite {
                    ProgressView()
                } else {
                    Label("Invite a Friend", systemImage: "person.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .accessibilityLabel("Invite a friend")
            .disabled(viewModel.isMintingInvite || isLoadingUser)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                if viewModel.isRefreshing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .accessibilityLabel("Refresh")
            .disabled(viewModel.isRefreshing || isLoadingUser)
        }
    }

    private var removalConfirmationTitle: String {
        if let friend = friendPendingRemoval {
            return "Remove \(friend.label)?"
        }
        return "Remove friend?"
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(Tab.allCases) { tab in
                Text(badgedTitle(tab)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding()
    }

    private func badgedTitle(_ tab: Tab) -> String {
        switch tab {
        case .friends:
            return viewModel.accepted.isEmpty ? "Friends" : "Friends (\(viewModel.accepted.count))"
        case .requests:
            let total = viewModel.incoming.count + viewModel.outgoing.count
            return total == 0 ? "Requests" : "Requests (\(total))"
        case .invites:
            let total = viewModel.incomingInvites.count
            return total == 0 ? "Invites" : "Invites (\(total))"
        case .find:
            return "Find"
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.gray)
            TextField("Search by name or email", text: $searchText)
                .foregroundStyle(Color.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.gray)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoadingUser || viewModel.isLoading {
            loadingState
        } else if let error = viewModel.errorMessage,
                  viewModel.accepted.isEmpty,
                  viewModel.discover.isEmpty,
                  viewModel.incomingInvites.isEmpty {
            errorState(error)
        } else {
            switch selectedTab {
            case .friends:  friendsList
            case .requests: requestsList
            case .invites:  invitesList
            case .find:     findList
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.xomifyGreen)
            Text("Loading...").font(.caption).foregroundStyle(Color.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(Color.orange.opacity(0.7))
            Text("Error").font(.headline).foregroundStyle(Color.white)
            Text(message).font(.caption).foregroundStyle(Color.gray)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadUserAndData() }
            } label: {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color.xomifyPurple)
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Friends tab

    private var filteredFriends: [Friend] {
        filter(viewModel.accepted, by: searchText) { $0.label + " " + $0.targetEmail }
    }

    private var friendsList: some View {
        Group {
            if filteredFriends.isEmpty {
                emptyTab(icon: "person.2", title: "No Friends Yet",
                         message: "Tap Invite a Friend in the top bar to share a link, or use Find to add existing users.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredFriends, id: \.targetEmail) { friend in
                            NavigationLink {
                                ProfileView(context: .other(email: friend.targetEmail))
                            } label: {
                                friendRow(friend, trailing: {
                                    AnyView(
                                        Button(role: .destructive) {
                                            friendPendingRemoval = friend
                                        } label: {
                                            Image(systemName: "person.badge.minus")
                                                .foregroundStyle(Color.red)
                                                .frame(minWidth: 44, minHeight: 44)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("Remove \(friend.label)")
                                    )
                                })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Requests tab

    private var filteredIncoming: [Friend] {
        filter(viewModel.incoming, by: searchText) { $0.label + " " + $0.targetEmail }
    }

    private var filteredOutgoing: [Friend] {
        filter(viewModel.outgoing, by: searchText) { $0.label + " " + $0.targetEmail }
    }

    private var requestsList: some View {
        Group {
            if filteredIncoming.isEmpty && filteredOutgoing.isEmpty {
                emptyTab(icon: "envelope", title: "No Requests",
                         message: "When someone sends or receives a request, it'll appear here.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if !filteredIncoming.isEmpty {
                            sectionHeader("Incoming")
                            ForEach(filteredIncoming, id: \.targetEmail) { friend in
                                friendRow(friend, trailing: {
                                    AnyView(
                                        HStack(spacing: 8) {
                                            Button {
                                                Task { await viewModel.accept(friend) }
                                            } label: {
                                                Text("Accept")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                                    .background(Color.xomifyGreen)
                                                    .foregroundStyle(Color.black)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Accept \(friend.label)")

                                            Button {
                                                Task { await viewModel.reject(friend) }
                                            } label: {
                                                Text("Reject")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                                    .background(Color.white.opacity(0.1))
                                                    .foregroundStyle(Color.white)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Reject \(friend.label)")
                                        }
                                    )
                                })
                            }
                        }

                        if !filteredOutgoing.isEmpty {
                            sectionHeader("Outgoing")
                            ForEach(filteredOutgoing, id: \.targetEmail) { friend in
                                friendRow(friend, trailing: {
                                    AnyView(
                                        Button {
                                            Task { await viewModel.cancel(friend) }
                                        } label: {
                                            Text("Cancel")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .padding(.horizontal, 12).padding(.vertical, 6)
                                                .background(Color.white.opacity(0.1))
                                                .foregroundStyle(Color.white)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Cancel request to \(friend.label)")
                                    )
                                })
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Invites tab

    private var filteredInvites: [PendingInvite] {
        filter(viewModel.incomingInvites, by: searchText) { $0.label + " " + $0.senderEmail }
    }

    private var invitesList: some View {
        Group {
            if filteredInvites.isEmpty {
                emptyTab(icon: "envelope.badge", title: "No Invites",
                         message: "Deep-link invites from other users appear here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredInvites) { invite in
                            inviteRow(invite)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func inviteRow(_ invite: PendingInvite) -> some View {
        HStack(spacing: 12) {
            avatarCircle(label: invite.label)

            VStack(alignment: .leading, spacing: 2) {
                Text(invite.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(invite.senderEmail)
                    .font(.caption2)
                    .foregroundStyle(Color.gray)
                    .lineLimit(1)
                if !invite.relativeTime.isEmpty {
                    Text(invite.relativeTime)
                        .font(.caption2)
                        .foregroundStyle(Color.gray.opacity(0.7))
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.acceptInvite(invite) }
                } label: {
                    Text("Accept")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.xomifyGreen)
                        .foregroundStyle(Color.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accept invite from \(invite.label)")
                .disabled(viewModel.inFlight.contains(invite.inviteCode))

                Button {
                    Task { await viewModel.declineInvite(invite) }
                } label: {
                    Text("Decline")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .foregroundStyle(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decline invite from \(invite.label)")
                .disabled(viewModel.inFlight.contains(invite.inviteCode))
            }
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Find tab

    private var filteredDiscover: [SearchResult] {
        filter(viewModel.discover, by: searchText) { $0.label + " " + $0.email }
    }

    private var findList: some View {
        Group {
            if filteredDiscover.isEmpty {
                emptyTab(icon: "magnifyingglass", title: "No users found",
                         message: "Try a different search.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredDiscover) { user in
                            discoverRow(user)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func discoverRow(_ user: SearchResult) -> some View {
        HStack(spacing: 12) {
            avatarCircle(label: user.label)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(user.email)
                    .font(.caption2)
                    .foregroundStyle(Color.gray)
                    .lineLimit(1)
            }

            Spacer()

            if user.isFriend == true {
                badge("Friend", color: .xomifyGreen)
            } else if user.isOutgoingRequest == true || user.isPending == true {
                badge("Requested", color: .xomifyPurple)
            } else {
                Button {
                    Task { await viewModel.request(user) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.plus")
                        Text("Add")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.xomifyPurple)
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(user.label)")
                .disabled(viewModel.inFlight.contains(user.email))
            }
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Row builders

    private func friendRow(_ friend: Friend, trailing: () -> AnyView) -> some View {
        HStack(spacing: 12) {
            avatarCircle(label: friend.label)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(friend.targetEmail)
                    .font(.caption2)
                    .foregroundStyle(Color.gray)
                    .lineLimit(1)
            }

            Spacer()

            trailing()
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func avatarCircle(label: String) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient.xomifyGradient)
                .frame(width: 40, height: 40)
            Text(String(label.prefix(1)).uppercased())
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.white)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color.gray)
            .padding(.top, 4)
    }

    private func emptyTab(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Color.gray.opacity(0.5))
            Text(title).font(.headline).foregroundStyle(Color.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filter helper

    private func filter<T>(_ list: [T], by query: String, keyFor: (T) -> String) -> [T] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return list }
        return list.filter { keyFor($0).lowercased().contains(q) }
    }

    // MARK: - Load

    private func loadUserAndData() async {
        isLoadingUser = true
        do {
            let user = try await spotifyService.getCurrentUser()
            guard let email = user.email, !email.isEmpty else {
                viewModel.errorMessage = "Could not get email from Spotify"
                isLoadingUser = false
                return
            }
            userEmail = email
            await viewModel.load(email: email)
            // If a deep-link invite was captured before we finished auth, route
            // into the Invites tab and auto-accept.
            if let pendingCode = inviteCoordinator.consume() {
                selectedTab = .invites
                await viewModel.acceptInvite(code: pendingCode)
            }
        } catch {
            viewModel.errorMessage = "Failed to load profile: \(error.localizedDescription)"
        }
        isLoadingUser = false
    }
}

// MARK: - Invite share sheet

/// Small wrapper that presents a `ShareLink`-style share sheet for a minted
/// invite URL. Kept separate so the sheet can be driven by `@State` on the
/// parent view.
private struct InviteShareSheet: View {
    let url: URL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "link")
                .font(.system(size: 40))
                .foregroundStyle(Color.xomifyGreen)
                .padding(.top, 24)

            Text("Invite a Friend")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Color.white)

            Text("Send this link to anyone you want to add as a friend on Xomify.")
                .font(.subheadline)
                .foregroundStyle(Color.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(url.absoluteString)
                .font(.caption)
                .foregroundStyle(Color.white)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.xomifyCard)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .textSelection(.enabled)
                .padding(.horizontal, 24)

            ShareLink(
                item: url,
                subject: Text("Join me on Xomify"),
                message: Text("Accept my invite to connect on Xomify: \(url.absoluteString)")
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient.xomifyGradient)
                .foregroundStyle(Color.white)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .accessibilityLabel("Share invite link")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.xomifyDark)
    }
}

#Preview {
    NavigationStack { FriendsView() }
}
