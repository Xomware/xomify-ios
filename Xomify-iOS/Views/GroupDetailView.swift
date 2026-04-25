import SwiftUI

/// Detail view for a single group: Shares + Members tabs.
///
/// "Add song" routes through the standard composer pre-targeted at this
/// group (no public, just this groupId). The legacy `/groups/add-song`
/// flow has been retired from the UI; the shares stream below is sourced
/// from `/shares/feed?groupId=…`.
struct GroupDetailView: View {

    let groupId: String
    let viewerEmail: String

    @State private var viewModel = GroupDetailViewModel()
    @State private var selectedTab: Tab = .shares
    @State private var showingAddMembers = false
    @State private var showingComposer = false
    @State private var showingEditGroup = false
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false

    /// Composer VM is owned at the screen level so we can prefill it with the
    /// current group + reset it on dismiss.
    @State private var composerVM: ShareComposerViewModel?

    /// Drives the push to ShareDetailView when a card body is tapped.
    @State private var selectedShare: Share?

    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case shares = "Shares"
        case members = "Members"
        var id: String { rawValue }
    }

    private var isOwner: Bool {
        (viewModel.group?.ownerLabel) == viewerEmail
    }

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tabTitle(tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case .shares:  sharesSection
                case .members: membersSection
                }
            }
        }
        .navigationTitle(viewModel.group?.name ?? "Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbarMenu
            }
        }
        .task { await viewModel.load(email: viewerEmail, groupId: groupId) }
        .tint(Color.xomifyGreen)
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.15))
            }
        }
        .navigationDestination(item: $selectedShare) { share in
            ShareDetailView(
                share: share,
                viewerEmail: viewerEmail,
                sharerIdentity: identity(for: share.sharedBy)
            )
        }
        .sheet(isPresented: $showingAddMembers) {
            AddMemberSheet(
                viewModel: viewModel,
                onDismiss: { showingAddMembers = false }
            )
        }
        .sheet(isPresented: $showingComposer, onDismiss: {
            composerVM = nil
        }) {
            if let composerVM {
                ShareComposerView(
                    viewModel: composerVM,
                    onSubmitted: { _ in
                        showingComposer = false
                        Task { await viewModel.loadShares() }
                    }
                )
            }
        }
        .sheet(isPresented: $showingEditGroup) {
            EditGroupSheet(
                viewModel: viewModel,
                onDismiss: { showingEditGroup = false }
            )
        }
        .confirmationDialog(
            "Leave this group?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave Group", role: .destructive) {
                Task {
                    if await viewModel.leave() {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop receiving updates and lose access to this group's shared tracks.")
        }
        .confirmationDialog(
            "Delete this group?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                Task {
                    if await viewModel.delete() {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the group for everyone. This action can't be undone.")
        }
    }

    // MARK: - Toolbar menu

    private var toolbarMenu: some View {
        Menu {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isRefreshing)

            if isOwner {
                Button {
                    showingEditGroup = true
                } label: {
                    Label("Edit Group", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Group", systemImage: "trash")
                }
            } else if viewModel.group != nil {
                Button(role: .destructive) {
                    showLeaveConfirm = true
                } label: {
                    Label("Leave Group", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            if viewModel.isRefreshing {
                ProgressView()
            } else {
                Image(systemName: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .accessibilityLabel("Group actions")
        .accessibilityHint("Opens menu with refresh and destructive actions")
    }

    private func tabTitle(_ tab: Tab) -> String {
        switch tab {
        case .shares:  return "Shares (\(viewModel.shares.count))"
        case .members: return "Members (\(viewModel.members.count))"
        }
    }

    // MARK: - Shares

    private var sharesSection: some View {
        VStack(spacing: 0) {
            addSongButton

            if viewModel.isLoadingShares && viewModel.shares.isEmpty {
                XomifyLoaderPulse()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.sharesError, viewModel.shares.isEmpty {
                emptyTab(icon: "exclamationmark.triangle",
                         title: "Couldn't load shares",
                         message: error)
            } else if viewModel.shares.isEmpty {
                emptyTab(icon: "music.note", title: "No shares yet",
                         message: "Tap Add song to post the first one to this group.")
            } else {
                sharesList
            }
        }
    }

    private var addSongButton: some View {
        Button {
            presentComposer()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("Add song")
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 10)
            .background(LinearGradient.xomifyGradient)
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 22))
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityLabel("Add song")
        .accessibilityHint("Opens the share composer pre-targeted at this group")
    }

    private var sharesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.shares) { share in
                    ShareCardView(
                        share: share,
                        viewerEmail: viewerEmail,
                        sharerIdentity: identity(for: share.sharedBy),
                        onDelete: nil,
                        onOpenDetail: { selectedShare = share }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(spacing: 0) {
            addMembersButton

            if viewModel.isLoading && viewModel.members.isEmpty {
                XomifyLoaderPulse()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.members.isEmpty {
                emptyTab(icon: "person.2", title: "No members yet",
                         message: "Tap Add members to invite friends.")
            } else {
                membersList
            }
        }
    }

    private var addMembersButton: some View {
        Button {
            showingAddMembers = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                Text("Add members")
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 10)
            .background(LinearGradient.xomifyGradient)
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 22))
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityLabel("Add members")
        .accessibilityHint("Opens a picker to add friends to this group")
    }

    private var membersList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.members) { member in
                    memberRow(member)
                }
            }
            .padding(.horizontal)
        }
    }

    private func memberRow(_ member: GroupMember) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient.xomifyGradient)
                    .frame(width: 40, height: 40)
                Text(String(member.label.prefix(1)).uppercased())
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if member.isOwner == true {
                        Text("OWNER")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.xomifyPurple.opacity(0.2))
                            .foregroundStyle(Color.xomifyPurple)
                            .clipShape(.rect(cornerRadius: 4))
                            .accessibilityLabel("Owner")
                    }
                }
                Text(member.email)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }

            Spacer()

            if member.isOwner != true, isOwner {
                Button(role: .destructive) {
                    Task { await viewModel.removeMember(member) }
                } label: {
                    Image(systemName: "person.badge.minus")
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(member.label)")
                .accessibilityHint("Removes this member from the group")
            }
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 10))
    }

    // MARK: - Composer plumbing

    /// Spin up a composer VM pre-targeted at this group and present the sheet.
    private func presentComposer() {
        composerVM = ShareComposerViewModel(
            prefilledGroupIds: [groupId],
            defaultShareToPublic: false
        )
        showingComposer = true
    }

    /// Best-effort identity for a member email — falls back to the email.
    /// Group detail doesn't have access to the friends-graph map FeedViewModel
    /// builds, so we resolve from the loaded `members` list.
    private func identity(for email: String) -> SharerIdentity {
        if let member = viewModel.members.first(where: { $0.email == email }) {
            return SharerIdentity(displayName: member.label, avatarURL: nil)
        }
        return SharerIdentity(displayName: email, avatarURL: nil)
    }

    // MARK: - Empty helper

    private func emptyTab(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Color.gray.opacity(0.5))
            Text(title).font(.headline).foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(groupId: "demo", viewerEmail: "me@me.com")
    }
}
