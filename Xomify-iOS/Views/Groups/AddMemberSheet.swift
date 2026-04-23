import SwiftUI

/// Sheet presented from `GroupDetailView` to add members via the friend
/// picker. Also offers a "Add by email" disclosure fallback for adding
/// people who aren't friends yet (keeps the old typed-email behavior).
struct AddMemberSheet: View {

    @Bindable var viewModel: GroupDetailViewModel
    let onDismiss: () -> Void

    @State private var selected: Set<String> = []
    @State private var isAddingBatch = false
    @State private var showByEmail = false

    private var existingMemberEmails: Set<String> {
        Set(viewModel.members.map { $0.email })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()

                VStack(spacing: 12) {
                    header

                    FriendPickerView(
                        friends: viewModel.friends,
                        excluding: existingMemberEmails,
                        mode: .multi,
                        isLoading: viewModel.isLoadingFriends,
                        loadError: viewModel.friendsError,
                        selected: $selected,
                        onRetry: {
                            Task { await viewModel.loadFriends() }
                        }
                    )
                    .padding(.horizontal)

                    byEmailDisclosure
                        .padding(.horizontal)

                    confirmButton
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Add Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .tint(Color.xomifyGreen)
            .task { await viewModel.loadFriends() }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        HStack(spacing: 6) {
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
    }

    // MARK: - By-email fallback

    private var byEmailDisclosure: some View {
        DisclosureGroup(isExpanded: $showByEmail) {
            HStack(spacing: 8) {
                TextField("Friend email", text: $viewModel.addMemberEmail)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .clipShape(.rect(cornerRadius: 10))
                    .foregroundStyle(.white)

                Button {
                    Task {
                        await viewModel.addMember()
                        if viewModel.errorMessage == nil {
                            onDismiss()
                        }
                    }
                } label: {
                    if viewModel.isAddingMember {
                        ProgressView().tint(.white)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "person.badge.plus")
                            .font(.title3)
                            .foregroundStyle(Color.xomifyGreen)
                            .frame(width: 44, height: 44)
                    }
                }
                .disabled(viewModel.isAddingMember
                          || viewModel.addMemberEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add by email")
                .accessibilityHint("Adds the typed email as a member")
            }
            .padding(.top, 4)
        } label: {
            Text("Add by email")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.gray)
        }
        .tint(.gray)
    }

    // MARK: - Confirm

    private var confirmButton: some View {
        Button {
            Task { await performAdd() }
        } label: {
            HStack(spacing: 8) {
                if isAddingBatch {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text(confirmLabel)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 10)
            .background(confirmBackground)
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 22))
        }
        .disabled(selected.isEmpty || isAddingBatch)
        .accessibilityLabel("Add selected members")
        .accessibilityHint("Adds the selected friends to this group")
    }

    private var confirmLabel: String {
        if selected.isEmpty { return "Add Members" }
        if selected.count == 1 { return "Add 1 Member" }
        return "Add \(selected.count) Members"
    }

    @ViewBuilder
    private var confirmBackground: some View {
        if selected.isEmpty {
            Color.gray.opacity(0.3)
        } else {
            LinearGradient.xomifyGradient
        }
    }

    private func performAdd() async {
        let emails = Array(selected)
        guard !emails.isEmpty else { return }
        isAddingBatch = true
        await viewModel.addMembers(emails)
        isAddingBatch = false
        // Dismiss when there's no fatal error; partial-success messages will
        // be surfaced via the detail view's error banner.
        onDismiss()
    }
}
