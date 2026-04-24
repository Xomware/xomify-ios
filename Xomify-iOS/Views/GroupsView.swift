import SwiftUI

/// Groups listing screen. + button opens a sheet to create a new group.
struct GroupsView: View {

    @State private var viewModel = GroupsViewModel()
    @State private var isLoadingUser = true
    @State private var userEmail: String?
    @State private var showingCreate = false

    private let spotifyService = SpotifyService.shared

    private var groupsSubtitle: String {
        let count = viewModel.groups.count
        if count == 0 { return "Make a group to share with a crew" }
        return "\(count) \(count == 1 ? "group" : "groups")"
    }

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            VStack(spacing: 0) {
                BrandGradientHeader(
                    "Groups",
                    subtitle: groupsSubtitle,
                    systemImage: "person.3.fill"
                ) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    .disabled(isLoadingUser)
                    .accessibilityLabel("Create group")
                }
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadUserAndData() }
        .onAppear {
            // Return from GroupDetailView (e.g. after delete/leave) should
            // re-fetch the list so stale rows don't linger.
            guard !isLoadingUser, let email = userEmail, !email.isEmpty else { return }
            Task { await viewModel.refresh() }
        }
        .sheet(isPresented: $showingCreate) {
            CreateGroupSheet(
                viewModel: viewModel,
                onCreate: { name, memberEmails, desc in
                    Task {
                        _ = await viewModel.create(
                            name: name,
                            memberEmails: memberEmails,
                            description: desc
                        )
                        showingCreate = false
                    }
                },
                onCancel: { showingCreate = false }
            )
        }
        .overlay(alignment: .top) { errorBanner }
        .tint(Color.xomifyGreen)
    }

    // MARK: - Banners

    @ViewBuilder
    private var errorBanner: some View {
        if let error = viewModel.errorMessage, !viewModel.isEmpty {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.15))
        } else if let info = viewModel.infoMessage {
            Text(info)
                .font(.caption)
                .foregroundStyle(Color.xomifyGreen)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.xomifyGreen.opacity(0.12))
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoadingUser || viewModel.isLoading {
            ProgressView().tint(.xomifyGreen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.isEmpty {
            errorState(error)
        } else if viewModel.isEmpty {
            emptyState
        } else {
            groupsList
        }
    }

    private var groupsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.groups) { group in
                    NavigationLink {
                        GroupDetailView(groupId: group.groupId, viewerEmail: viewModel.userEmail)
                    } label: {
                        groupRow(group)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private func groupRow(_ group: XomifyGroup) -> some View {
        let isOwner = group.ownerEmail == viewModel.userEmail
        let memberCount = group.memberCount ?? 0
        let trackCount = group.trackCount ?? 0

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient.xomifyGradient)
                    .frame(width: 50, height: 50)
                Image(systemName: "person.3.fill")
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if isOwner {
                        ownerBadge
                    }
                }
                if let desc = group.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Label("\(memberCount)", systemImage: "person.2")
                    Label("\(trackCount)", systemImage: "music.note")
                }
                .font(.caption2)
                .foregroundStyle(.gray)
                .padding(.top, 2)
            }
            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.gray)
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel(
            group: group, isOwner: isOwner,
            memberCount: memberCount, trackCount: trackCount
        )))
    }

    private var ownerBadge: some View {
        Text("OWNER")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.xomifyPurple.opacity(0.2))
            .foregroundStyle(Color.xomifyPurple)
            .clipShape(.rect(cornerRadius: 4))
            .accessibilityLabel("Owner")
    }

    private func accessibilityLabel(
        group: XomifyGroup,
        isOwner: Bool,
        memberCount: Int,
        trackCount: Int
    ) -> String {
        var parts: [String] = [group.name]
        if isOwner { parts.append("owner") }
        parts.append("\(memberCount) member\(memberCount == 1 ? "" : "s")")
        parts.append("\(trackCount) track\(trackCount == 1 ? "" : "s")")
        return parts.joined(separator: ", ")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 50))
                .foregroundStyle(Color.gray.opacity(0.5))
            Text("No Groups Yet").font(.headline).foregroundStyle(.white)
            Text("Create a group to share and discover music with friends.")
                .font(.caption).foregroundStyle(.gray)
                .multilineTextAlignment(.center)
            Button {
                showingCreate = true
            } label: {
                Text("Create Group")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(LinearGradient.xomifyGradient)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 20))
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(Color.orange.opacity(0.7))
            Text("Error").font(.headline).foregroundStyle(.white)
            Text(message).font(.caption).foregroundStyle(.gray)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadUserAndData() }
            } label: {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color.xomifyPurple)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 20))
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Create sheet (two-step: name/description → friend picker)

private struct CreateGroupSheet: View {

    @Bindable var viewModel: GroupsViewModel
    let onCreate: (_ name: String, _ memberEmails: [String], _ description: String?) -> Void
    let onCancel: () -> Void

    private enum Step {
        case details
        case members
    }

    @State private var step: Step = .details
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()

                switch step {
                case .details: detailsStep
                case .members: membersStep
                }
            }
            .navigationTitle(step == .details ? "New Group" : "Add Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == .details {
                        Button("Cancel", action: onCancel)
                    } else {
                        Button("Back") { step = .details }
                    }
                }
            }
            .tint(Color.xomifyGreen)
        }
        .presentationDetents(step == .details ? [.medium] : [.large])
    }

    // MARK: - Step 1

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String? {
        let t = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.caption).foregroundStyle(.gray)
                TextField("My Group", text: $name)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .clipShape(.rect(cornerRadius: 10))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description (optional)").font(.caption).foregroundStyle(.gray)
                TextField("What's this group about?", text: $description, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .clipShape(.rect(cornerRadius: 10))
                    .foregroundStyle(.white)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    step = .members
                    Task { await viewModel.loadFriends() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.badge.plus")
                        Text("Pick Members")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 10)
                    .background(LinearGradient.xomifyGradient)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 22))
                }
                .disabled(trimmedName.isEmpty)

                Button {
                    onCreate(trimmedName, [], trimmedDescription)
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isCreating {
                            ProgressView().tint(.white)
                        } else {
                            Text("Create without members")
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(.white.opacity(0.8))
                }
                .disabled(trimmedName.isEmpty || viewModel.isCreating)
                .accessibilityHint("Creates the group with no members")
            }
        }
        .padding()
    }

    // MARK: - Step 2

    private var membersStep: some View {
        VStack(spacing: 12) {
            HStack {
                if selected.isEmpty {
                    Text("Pick friends to add")
                        .font(.caption)
                        .foregroundStyle(.gray)
                } else {
                    Text("\(selected.count) selected")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.xomifyGreen)
                }
                Spacer()
            }
            .padding(.horizontal)

            FriendPickerView(
                friends: viewModel.friends,
                excluding: [],
                mode: .multi,
                isLoading: viewModel.isLoadingFriends,
                loadError: viewModel.friendsError,
                selected: $selected,
                onRetry: { Task { await viewModel.loadFriends() } }
            )
            .padding(.horizontal)

            Button {
                onCreate(trimmedName, Array(selected), trimmedDescription)
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isCreating {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                        Text(confirmLabel)
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 10)
                .background(LinearGradient.xomifyGradient)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 22))
            }
            .disabled(viewModel.isCreating || trimmedName.isEmpty)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
    }

    private var confirmLabel: String {
        switch selected.count {
        case 0: return "Create Group"
        case 1: return "Create with 1 Member"
        default: return "Create with \(selected.count) Members"
        }
    }
}

#Preview {
    NavigationStack { GroupsView() }
}
