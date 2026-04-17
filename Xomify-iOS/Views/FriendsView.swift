import SwiftUI

/// Friends screen: three segmented tabs (Friends / Requests / Find).
struct FriendsView: View {

    @State private var viewModel = FriendsViewModel()
    @State private var isLoadingUser = true
    @State private var userEmail: String?
    @State private var selectedTab: Tab = .friends
    @State private var searchText: String = ""

    private let spotifyService = SpotifyService.shared

    enum Tab: String, CaseIterable, Identifiable {
        case friends = "Friends"
        case requests = "Requests"
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
        .toolbar {
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
                .disabled(viewModel.isRefreshing || isLoadingUser)
            }
        }
        .task { await loadUserAndData() }
        .tint(Color.xomifyGreen)
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
        case .find:
            return "Find"
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)
            TextField("Search by name or email", text: $searchText)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoadingUser || viewModel.isLoading {
            loadingState
        } else if let error = viewModel.errorMessage, viewModel.accepted.isEmpty, viewModel.discover.isEmpty {
            errorState(error)
        } else {
            switch selectedTab {
            case .friends:  friendsList
            case .requests: requestsList
            case .find:     findList
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.xomifyGreen)
            Text("Loading...").font(.caption).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange.opacity(0.7))
            Text("Error").font(.headline).foregroundColor(.white)
            Text(message).font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadUserAndData() }
            } label: {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color.xomifyPurple)
                    .foregroundColor(.white)
                    .cornerRadius(20)
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
                         message: "Invite a friend from the Invites page to get started.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredFriends, id: \.targetEmail) { friend in
                            NavigationLink {
                                FriendProfileView(profileEmail: friend.targetEmail, viewerEmail: viewModel.userEmail)
                            } label: {
                                friendRow(friend, trailing: {
                                    AnyView(
                                        Button(role: .destructive) {
                                            Task { await viewModel.remove(friend) }
                                        } label: {
                                            Image(systemName: "person.badge.minus")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.borderless)
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
                                                    .foregroundColor(.black)
                                                    .cornerRadius(12)
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                Task { await viewModel.reject(friend) }
                                            } label: {
                                                Text("Reject")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                                    .background(Color.white.opacity(0.1))
                                                    .foregroundColor(.white)
                                                    .cornerRadius(12)
                                            }
                                            .buttonStyle(.plain)
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
                                                .foregroundColor(.white)
                                                .cornerRadius(12)
                                        }
                                        .buttonStyle(.plain)
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
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(user.email)
                    .font(.caption2)
                    .foregroundColor(.gray)
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
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inFlight.contains(user.email))
            }
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    // MARK: - Row builders

    private func friendRow(_ friend: Friend, trailing: () -> AnyView) -> some View {
        HStack(spacing: 12) {
            avatarCircle(label: friend.label)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(friend.targetEmail)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer()

            trailing()
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    private func avatarCircle(label: String) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient.xomifyGradient)
                .frame(width: 40, height: 40)
            Text(String(label.prefix(1)).uppercased())
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(10)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.gray)
            .padding(.top, 4)
    }

    private func emptyTab(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            Text(title).font(.headline).foregroundColor(.white)
            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
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
        } catch {
            viewModel.errorMessage = "Failed to load profile: \(error.localizedDescription)"
        }
        isLoadingUser = false
    }
}

#Preview {
    NavigationStack { FriendsView() }
}
