import SwiftUI

/// Reusable friend picker with search + selection. Used by the group-create
/// flow (multi-select) and the add-member sheet (multi-select, with
/// existing members excluded).
///
/// Rendered inline inside a parent sheet — owns no chrome of its own, just
/// the search field, the rows, and the empty state. Parent is responsible
/// for navigation / confirm / cancel buttons.
struct FriendPickerView: View {

    enum Mode {
        case single
        case multi
    }

    let friends: [Friend]
    let excluding: Set<String>
    let mode: Mode
    let isLoading: Bool
    let loadError: String?
    @Binding var selected: Set<String>
    let onRetry: (() -> Void)?

    @State private var searchText: String = ""

    init(
        friends: [Friend],
        excluding: Set<String> = [],
        mode: Mode = .multi,
        isLoading: Bool = false,
        loadError: String? = nil,
        selected: Binding<Set<String>>,
        onRetry: (() -> Void)? = nil
    ) {
        self.friends = friends
        self.excluding = excluding
        self.mode = mode
        self.isLoading = isLoading
        self.loadError = loadError
        self._selected = selected
        self.onRetry = onRetry
    }

    // MARK: - Filtering

    private var available: [Friend] {
        friends.filter { !excluding.contains($0.targetEmail) }
    }

    private var filtered: [Friend] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return available }
        return available.filter {
            $0.label.lowercased().contains(q) ||
            $0.targetEmail.lowercased().contains(q)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            searchField

            if isLoading {
                loadingState
            } else if let error = loadError {
                errorState(error)
            } else if available.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                noMatchesState
            } else {
                list
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)
            TextField("Search friends", text: $searchText)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(.rect(cornerRadius: 10))
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filtered, id: \.targetEmail) { friend in
                    row(for: friend)
                }
            }
        }
    }

    private func row(for friend: Friend) -> some View {
        let isSelected = selected.contains(friend.targetEmail)

        return Button {
            toggle(friend)
        } label: {
            HStack(spacing: 12) {
                avatarCircle(label: friend.label)

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(friend.targetEmail)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                selectionIcon(selected: isSelected)
            }
            .padding(12)
            .background(Color.xomifyCard)
            .clipShape(.rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(friend.label))
        .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
        .accessibilityHint(Text("Double tap to \(isSelected ? "deselect" : "select")"))
        .accessibilityAddTraits(.isButton)
    }

    private func selectionIcon(selected: Bool) -> some View {
        Image(systemName: selected
              ? (mode == .multi ? "checkmark.square.fill" : "largecircle.fill.circle")
              : (mode == .multi ? "square" : "circle"))
            .font(.title3)
            .foregroundStyle(selected ? Color.xomifyGreen : Color.gray.opacity(0.6))
            .frame(width: 32, height: 32)
    }

    private func avatarCircle(label: String) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient.xomifyGradient)
                .frame(width: 40, height: 40)
            Text(String(label.prefix(1)).uppercased())
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView().tint(.xomifyGreen)
            Text("Loading friends...")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Color.orange.opacity(0.7))
            Text("Couldn't load friends")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
            if let onRetry {
                Button("Try Again") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .tint(Color.xomifyPurple)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 32))
                .foregroundStyle(Color.gray.opacity(0.6))
            Text("No friends yet")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text("Add some from the Friends drawer entry, then come back here.")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var noMatchesState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Color.gray.opacity(0.6))
            Text("No friends match \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: - Actions

    private func toggle(_ friend: Friend) {
        let key = friend.targetEmail
        switch mode {
        case .multi:
            if selected.contains(key) {
                selected.remove(key)
            } else {
                selected.insert(key)
            }
        case .single:
            if selected.contains(key) {
                selected.removeAll()
            } else {
                selected = [key]
            }
        }
    }
}

#Preview {
    struct Host: View {
        @State private var selected: Set<String> = []

        var body: some View {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()
                FriendPickerView(
                    friends: [
                        Friend(
                            email: "me@example.com",
                            friendEmail: "alex@example.com",
                            displayName: "Alex",
                            avatar: nil,
                            status: "accepted",
                            direction: nil,
                            createdAt: nil,
                            mutualCount: nil
                        ),
                        Friend(
                            email: "me@example.com",
                            friendEmail: "sam@example.com",
                            displayName: "Sam",
                            avatar: nil,
                            status: "accepted",
                            direction: nil,
                            createdAt: nil,
                            mutualCount: nil
                        )
                    ],
                    excluding: [],
                    mode: .multi,
                    selected: $selected
                )
                .padding()
            }
        }
    }
    return Host()
}
