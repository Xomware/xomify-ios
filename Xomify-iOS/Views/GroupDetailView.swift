import SwiftUI

/// Detail view for a single group: Members + Tracks tabs.
struct GroupDetailView: View {

    let groupId: String
    let viewerEmail: String

    @State private var viewModel = GroupDetailViewModel()
    @State private var selectedTab: Tab = .tracks

    enum Tab: String, CaseIterable, Identifiable {
        case tracks = "Tracks"
        case members = "Members"
        var id: String { rawValue }
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
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isRefreshing)
            }
        }
        .task { await viewModel.load(email: viewerEmail, groupId: groupId) }
        .tint(Color.xomifyGreen)
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.15))
            }
        }
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
                .cornerRadius(10)
                .foregroundColor(.white)

            Button {
                Task { await viewModel.addSongByUrl() }
            } label: {
                if viewModel.isAddingSong {
                    ProgressView().tint(.white)
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.xomifyGreen)
                        .frame(width: 40, height: 40)
                }
            }
            .disabled(viewModel.isAddingSong || viewModel.addSongUrl.isEmpty)
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
                    .foregroundColor(.white)
                    .cornerRadius(16)
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
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.trackName ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let artist = track.artistName {
                    Text(artist)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                if let by = track.addedBy {
                    Text("Added by \(by)")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.8))
                }
            }

            Spacer()

            Button(role: .destructive) {
                Task { await viewModel.removeSong(track) }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(spacing: 0) {
            addMemberBar

            if viewModel.isLoading && viewModel.members.isEmpty {
                ProgressView().tint(.xomifyGreen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.members.isEmpty {
                emptyTab(icon: "person.2", title: "No members yet",
                         message: "Add someone by their email above.")
            } else {
                membersList
            }
        }
    }

    private var addMemberBar: some View {
        HStack(spacing: 8) {
            TextField("Friend email", text: $viewModel.addMemberEmail)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                .foregroundColor(.white)

            Button {
                Task { await viewModel.addMember() }
            } label: {
                if viewModel.isAddingMember {
                    ProgressView().tint(.white)
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "person.badge.plus")
                        .font(.title3)
                        .foregroundColor(.xomifyGreen)
                        .frame(width: 40, height: 40)
                }
            }
            .disabled(viewModel.isAddingMember || viewModel.addMemberEmail.isEmpty)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
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
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if member.isOwner == true {
                        Text("OWNER")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.xomifyPurple.opacity(0.2))
                            .foregroundColor(.xomifyPurple)
                            .cornerRadius(4)
                    }
                }
                Text(member.email)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer()

            if member.isOwner != true, viewModel.group?.ownerEmail == viewerEmail {
                Button(role: .destructive) {
                    Task { await viewModel.removeMember(member) }
                } label: {
                    Image(systemName: "person.badge.minus")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    // MARK: - Empty helper

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
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(groupId: "demo", viewerEmail: "me@me.com")
    }
}
