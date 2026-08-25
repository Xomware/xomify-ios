import SwiftUI

/// Drilldown pushed from the "friends queued" stat tile on `ShareDetailView`.
/// Lists every friend who has queued the share. Read-only.
struct FriendsQueuedListView: View {

    let trackName: String
    let listeners: [ShareInteractionEntry]

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if listeners.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 8) {
                            ForEach(listeners) { entry in
                                row(entry)
                            }
                        }
                    }
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Friends queued")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.xomifyGreen)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trackName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(listeners.count == 1 ? "1 friend queued this" : "\(listeners.count) friends queued this")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        Text("No friends have queued this yet.")
            .font(.subheadline)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.xomifyCard.opacity(0.5))
            .clipShape(.rect(cornerRadius: XomRadius.lg))
    }

    private func row(_ entry: ShareInteractionEntry) -> some View {
        HStack(spacing: 12) {
            avatar(url: entry.avatarURL, initial: entry.resolvedName.prefix(1))
            Text(entry.resolvedName)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "text.badge.plus")
                .font(.caption2)
                .foregroundStyle(Color.xomifyGreen)
        }
        .padding(10)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: XomRadius.lg))
    }

    @ViewBuilder
    private func avatar(url: URL?, initial: Substring) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarFallback(initial: initial)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            avatarFallback(initial: initial)
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
}
