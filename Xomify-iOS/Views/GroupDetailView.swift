import SwiftUI

/// Detail view for a single group: Members + Tracks tabs.
struct GroupDetailView: View {

    let groupId: String
    let viewerEmail: String

    @State private var viewModel = GroupDetailViewModel()
    @State private var selectedTab: Tab = .tracks
    @State private var showingAddMembers = false
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false

    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case tracks = "Tracks"
        case members = "Members"
        var id: String { rawValue }
    }

    private var isOwner: Bool {
        viewModel.group?.ownerEmail == viewerEmail
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
                case .tracks:  tracksSection
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
        case .tracks:  return "Tracks (\(viewModel.tracks.count))"
        case .members: return "Members (\(viewModel.members.count))"
        }
    }

    // MARK: - Tracks

    private var tracksSection: some View {
        VStack(spacing: 0) {
            addSongBar

            if viewModel.isLoading && viewModel.tracks.isEmpty {
                ProgressView().tint(.xomifyGreen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.tracks.isEmpty {
                emptyTab(icon: "music.note", title: "No tracks yet",
                         message: "Paste a Spotify URL above to add one.")
            } else {
                tracksList
            }
        }
    }

    private var addSongBar: some View {
        HStack(spacing: 8) {
            TextField("Paste Spotify track URL", text: $viewModel.addSongUrl)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding()
                .background(Color.white.opacity(0.05))
                .clipShape(.rect(cornerRadius: 10))
                .foregroundStyle(.white)

            Button {
                Task { await viewModel.addSongByUrl() }
            } label: {
                if viewModel.isAddingSong {
                    ProgressView().tint(.white)
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.xomifyGreen)
                        .frame(width: 44, height: 44)
                }
            }
            .disabled(viewModel.isAddingSong || viewModel.addSongUrl.isEmpty)
            .accessibilityLabel("Add track from URL")
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var tracksList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Mark-all-listened shortcut
                Button {
                    Task { await viewModel.markAllListened() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                        Text("Mark all listened")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.bottom, 8)

                ForEach(viewModel.tracks) { track in
                    trackRow(track)
                }
            }
            .padding(.horizontal)
        }
    }

    private func trackRow(_ track: GroupTrack) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.image) { image in
                image.resizable()
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
            .frame(width: 50, height: 50)
            .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.trackName ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artist = track.artistName {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                if let by = track.addedBy {
                    Text("Added by \(by)")
                        .font(.caption2)
                        .foregroundStyle(.gray.opacity(0.8))
                }
            }

            Spacer()

            Button(role: .destructive) {
                Task { await viewModel.removeSong(track) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(track.trackName ?? "track")")
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: 10))
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(spacing: 0) {
            addMembersButton

            if viewModel.isLoading && viewModel.members.isEmpty {
                ProgressView().tint(.xomifyGreen)
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
