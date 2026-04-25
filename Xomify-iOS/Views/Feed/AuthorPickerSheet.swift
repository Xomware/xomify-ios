import SwiftUI

/// Searchable picker for the "From" filter on the feed. Replaces the
/// pill-per-friend grid that used to live inline in `FeedRefinementSheet` —
/// that grid was fine for ~10 friends but breaks down past ~30 (vertical wall
/// of pills, no way to find a name without scanning every chip). The picker
/// scales to hundreds of friends because it's just a `List` + searchable.
struct AuthorPickerSheet: View {

    @Bindable var viewModel: FeedViewModel
    let onDismiss: () -> Void

    @State private var query: String = ""

    private var filteredAuthors: [String] {
        let all = viewModel.availableAuthors
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { email in
            let name = viewModel.identity(for: email).displayName
            return name.localizedCaseInsensitiveContains(trimmed)
                || email.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()
                content
            }
            .navigationTitle("From")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.refinement.authors.isEmpty {
                        Button("Clear") {
                            viewModel.refinement.authors = []
                        }
                        .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search friends")
        }
        .tint(Color.xomifyGreen)
    }

    @ViewBuilder
    private var content: some View {
        let authors = filteredAuthors
        if viewModel.availableAuthors.isEmpty {
            emptyState("No authors in the current feed yet.")
        } else if authors.isEmpty {
            emptyState("No friends match \"\(query)\".")
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(authors, id: \.self) { email in
                        row(for: email)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func row(for email: String) -> some View {
        let identity = viewModel.identity(for: email)
        let selected = viewModel.refinement.authors.contains(email)

        return Button {
            if selected {
                viewModel.refinement.authors.remove(email)
            } else {
                viewModel.refinement.authors.insert(email)
            }
        } label: {
            HStack(spacing: 12) {
                avatar(for: identity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if identity.displayName != email {
                        Text(email)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.xomifyGreen : Color.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Color.xomifyCard)
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(identity.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func avatar(for identity: SharerIdentity) -> some View {
        if let url = identity.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarFallback(initial: identity.displayName.prefix(1))
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            avatarFallback(initial: identity.displayName.prefix(1))
        }
    }

    private func avatarFallback(initial: Substring) -> some View {
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

    private func emptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
