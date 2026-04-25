import SwiftUI

/// Detail view for a single group: Stats + Members tabs.
///
/// The Shares card list is gone — the Feed is the place for that. The "Add
/// track" pill at the top of either tab pops the user back to the Feed
/// destination so they can use the standard composer (and optionally include
/// this group from the picker).
struct GroupDetailView: View {

    let groupId: String
    let viewerEmail: String

    @State private var viewModel = GroupDetailViewModel()
    @State private var selectedTab: Tab = .stats
    @State private var showingAddMembers = false
    @State private var showingEditGroup = false
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false

    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationStore.self) private var navStore

    enum Tab: String, CaseIterable, Identifiable {
        case stats = "Stats"
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
                case .stats:   statsSection
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
        .sheet(isPresented: $showingAddMembers) {
            AddMemberSheet(
                viewModel: viewModel,
                onDismiss: { showingAddMembers = false }
            )
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
        case .stats:   return "Stats"
        case .members: return "Members (\(viewModel.members.count))"
        }
    }

    // MARK: - Stats

    /// Compact "+ track" pill — kicks the user back to the Feed where they
    /// can compose a share and optionally include this group from the picker.
    /// Smaller than a full-width CTA on purpose; the Stats tab is the primary
    /// content here.
    private var addTrackPill: some View {
        Button {
            // Pop GroupDetailView off the navigation stack first, *then* swap
            // the root destination. Without the dismiss, SwiftUI keeps the
            // pushed detail view on top of the new Feed root and the user
            // never sees the destination change.
            dismiss()
            navStore.select(.feed)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Add track")
            }
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 32)
            .background(LinearGradient.xomifyGradient)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .accessibilityLabel("Add a track")
        .accessibilityHint("Switches to the Feed where you can share and target this group")
    }

    private var statsSection: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    addTrackPill
                }
                .padding(.horizontal)

                if viewModel.isLoadingShares && viewModel.shares.isEmpty {
                    XomifyLoaderPulse()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let error = viewModel.sharesError, viewModel.shares.isEmpty {
                    emptyTab(icon: "exclamationmark.triangle",
                             title: "Couldn't load stats",
                             message: error)
                } else if viewModel.shares.isEmpty {
                    emptyTab(icon: "chart.bar",
                             title: "No shares yet",
                             message: "Once members start sharing, totals and breakdowns will appear here.")
                } else {
                    statsContent
                }
            }
            .padding(.bottom, 16)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var statsContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                statTile(
                    value: "\(viewModel.totalShareCount)",
                    label: viewModel.totalShareCount == 1 ? "song shared" : "songs shared",
                    icon: "music.note.list"
                )
                statTile(
                    value: viewModel.averageSharerRating
                        .map { String(format: "%.1f", $0) } ?? "—",
                    label: "avg rating",
                    icon: "star.fill"
                )
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.caption)
                        .foregroundStyle(Color.xomifyGreen)
                    Text("By member")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Spacer()
                }
                ForEach(viewModel.perUserStats) { stat in
                    perUserRow(stat)
                }
            }
            .padding(.horizontal)
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.xomifyGreen)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .padding(10)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func perUserRow(_ stat: GroupDetailViewModel.GroupUserStat) -> some View {
        HStack(spacing: 12) {
            avatarCircle(url: stat.avatarURL, initial: stat.displayName.prefix(1))
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(stat.shareCount) share\(stat.shareCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            Spacer(minLength: 8)
            if let avg = stat.averageRating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.xomifyGreen)
                    Text(String(format: "%.1f", avg))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
        }
        .padding(10)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func avatarCircle(url: URL?, initial: Substring) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarFallbackCircle(initial: initial)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            avatarFallbackCircle(initial: initial)
        }
    }

    private func avatarFallbackCircle(initial: Substring) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient.xomifyGradient)
                .frame(width: 36, height: 36)
            Text(String(initial).uppercased())
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
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
        let isSelf = member.email == viewerEmail
        // Self-row uses the viewer's known display name + avatar — the
        // backend's GroupMember payload doesn't currently carry profile
        // info, so without this every self-row would show as the email.
        let displayName: String = {
            if isSelf, let mine = viewModel.viewerDisplayName, !mine.isEmpty {
                return mine
            }
            return member.label
        }()
        let avatarURL: URL? = isSelf ? viewModel.viewerAvatarURL : nil

        return HStack(spacing: 12) {
            avatarCircle(url: avatarURL, initial: displayName.prefix(1))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if isSelf {
                        Text("YOU")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.xomifyGreen.opacity(0.18))
                            .foregroundStyle(Color.xomifyGreen)
                            .clipShape(.rect(cornerRadius: 4))
                    }
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

            // Self + non-owner → Leave. Owner sees a remove button on others.
            if isSelf, member.isOwner != true {
                Button(role: .destructive) {
                    showLeaveConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Leave")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 32)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Leave this group")
            } else if !isSelf, member.isOwner != true, isOwner {
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
    .environment(NavigationStore())
}
