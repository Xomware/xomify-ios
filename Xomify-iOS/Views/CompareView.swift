import SwiftUI

/// Compare: pick a friend -> compute Jaccard similarity locally.
struct CompareView: View {

    @State private var viewModel = CompareViewModel()
    @State private var isLoadingUser = true
    @State private var userEmail: String?
    @State private var myDisplayName: String = ""

    private let spotifyService = SpotifyService.shared

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            content
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadUser() }
        .tint(Color.xomifyGreen)
    }

    @ViewBuilder
    private var content: some View {
        if isLoadingUser || viewModel.isLoadingFriends {
            ProgressView().tint(.xomifyGreen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.friends.isEmpty {
            emptyState
        } else if viewModel.isComparing {
            comparingState
        } else if let result = viewModel.result, let friend = viewModel.selectedFriend {
            resultsView(result: result, friend: friend)
        } else {
            friendPicker
        }
    }

    // MARK: - Friend picker

    private var friendPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick a friend to compare with")
                    .font(.headline)
                    .foregroundColor(.white)

                ForEach(viewModel.friends, id: \.targetEmail) { friend in
                    Button {
                        Task { await viewModel.compare(with: friend) }
                    } label: {
                        friendRow(friend)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private func friendRow(_ friend: Friend) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient.xomifyGradient)
                    .frame(width: 40, height: 40)
                Text(String(friend.label.prefix(1)).uppercased())
                    .font(.subheadline).fontWeight(.bold).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.label)
                    .font(.subheadline).fontWeight(.medium).foregroundColor(.white)
                    .lineLimit(1)
                Text(friend.targetEmail)
                    .font(.caption2).foregroundColor(.gray).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.gray)
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    // MARK: - Comparing

    private var comparingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.xomifyGreen)
            Text("Comparing...").font(.caption).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private func resultsView(result: CompareBreakdown, friend: Friend) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Avatars + score
                HStack(alignment: .center, spacing: 20) {
                    avatarStack(label: myDisplayName.isEmpty ? "You" : myDisplayName, sublabel: "You")
                    VStack(spacing: 4) {
                        Text("\(result.overallPercent)%")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(LinearGradient.xomifyGradient)
                        Text("Similarity")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    avatarStack(label: friend.label, sublabel: friend.targetEmail)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // Bars
                VStack(spacing: 12) {
                    compareBar(label: "Tracks", value: result.tracksOverlap)
                    compareBar(label: "Artists", value: result.artistsOverlap)
                    compareBar(label: "Genres", value: result.genresOverlap)
                }

                sharedSection(title: "Shared Tracks", items: result.sharedTrackNames)
                sharedSection(title: "Shared Artists", items: result.sharedArtistNames)
                sharedSection(title: "Shared Genres", items: result.sharedGenres)

                Button {
                    viewModel.result = nil
                    viewModel.selectedFriend = nil
                } label: {
                    Text("Compare With Someone Else")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                }
                .padding(.top)
            }
            .padding()
        }
    }

    private func avatarStack(label: String, sublabel: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(LinearGradient.xomifyGradient)
                    .frame(width: 60, height: 60)
                Text(String(label.prefix(1)).uppercased())
                    .font(.title2).fontWeight(.bold).foregroundColor(.white)
            }
            Text(label)
                .font(.caption).fontWeight(.medium).foregroundColor(.white)
                .lineLimit(1)
            Text(sublabel)
                .font(.caption2).foregroundColor(.gray)
                .lineLimit(1)
        }
        .frame(width: 100)
    }

    private func compareBar(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption).fontWeight(.medium).foregroundColor(.white)
                Spacer()
                Text("\(Int(round(value * 100)))%")
                    .font(.caption).foregroundColor(.gray)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient.xomifyGradient)
                        .frame(width: max(0, geo.size.width * value))
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private func sharedSection(title: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline).foregroundColor(.white)
                FlowLayout(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.xomifyCard)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            Text("No Friends Yet").font(.headline).foregroundColor(.white)
            Text("Add friends first, then come back to compare music taste.")
                .font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load

    private func loadUser() async {
        isLoadingUser = true
        do {
            let user = try await spotifyService.getCurrentUser()
            guard let email = user.email, !email.isEmpty else {
                isLoadingUser = false
                return
            }
            userEmail = email
            myDisplayName = user.displayName ?? "You"
            await viewModel.loadFriends(email: email)
        } catch {
            print("❌ Compare: load user failed - \(error)")
        }
        isLoadingUser = false
    }
}

// MARK: - Flow layout (iOS 16+)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack { CompareView() }
}
