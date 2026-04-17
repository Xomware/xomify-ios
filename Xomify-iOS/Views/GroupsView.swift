import SwiftUI

/// Groups listing screen. + button opens a sheet to create a new group.
struct GroupsView: View {

    @State private var viewModel = GroupsViewModel()
    @State private var isLoadingUser = true
    @State private var userEmail: String?
    @State private var showingCreate = false

    private let spotifyService = SpotifyService.shared

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            content
        }
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(isLoadingUser)
            }
        }
        .task { await loadUserAndData() }
        .sheet(isPresented: $showingCreate) {
            CreateGroupSheet(
                onCreate: { name, desc in
                    Task {
                        if let group = await viewModel.create(name: name, description: desc) {
                            _ = group
                        }
                        showingCreate = false
                    }
                },
                onCancel: { showingCreate = false },
                isCreating: viewModel.isCreating
            )
        }
        .tint(Color.xomifyGreen)
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
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient.xomifyGradient)
                    .frame(width: 50, height: 50)
                Image(systemName: "person.3.fill")
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let desc = group.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Label("\(group.memberCount ?? 0)", systemImage: "person.2")
                    Label("\(group.trackCount ?? 0)", systemImage: "music.note")
                }
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.top, 2)
            }
            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            Text("No Groups Yet").font(.headline).foregroundColor(.white)
            Text("Create a group to share and discover music with friends.")
                .font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Button {
                showingCreate = true
            } label: {
                Text("Create Group")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(LinearGradient.xomifyGradient)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
        }
        .padding(.horizontal, 40)
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

// MARK: - Create sheet

private struct CreateGroupSheet: View {
    let onCreate: (String, String?) -> Void
    let onCancel: () -> Void
    let isCreating: Bool

    @State private var name: String = ""
    @State private var description: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").font(.caption).foregroundColor(.gray)
                    TextField("My Group", text: $name)
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description (optional)").font(.caption).foregroundColor(.gray)
                    TextField("What's this group about?", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                }

                Spacer()

                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
                    onCreate(trimmed, desc.isEmpty ? nil : desc)
                } label: {
                    HStack(spacing: 8) {
                        if isCreating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                            Text("Create Group")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LinearGradient.xomifyGradient)
                    .foregroundColor(.white)
                    .cornerRadius(25)
                }
                .disabled(isCreating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color.xomifyDark.ignoresSafeArea())
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack { GroupsView() }
}
