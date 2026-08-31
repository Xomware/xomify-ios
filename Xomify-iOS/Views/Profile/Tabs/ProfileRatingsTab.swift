import SwiftUI
import UIKit

/// Ratings tab on `ProfileView`. Reuses `RatingsViewModel` parameterised by
/// the context email. Hides delete on `.other` — viewers can't mutate
/// another user's ratings.
struct ProfileRatingsTab: View {

    @Bindable var viewModel: RatingsViewModel
    let context: ProfileContext
    let viewerEmail: String

    @Environment(NavigationStore.self) private var navStore
    @State private var shuffled: [TrackRating] = []

    /// How many cards the shuffle sample shows at a time.
    private let sampleSize = 5

    private var targetEmail: String { context.email ?? viewerEmail }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.ratings.isEmpty {
                XomifyLoaderPaint(size: 40)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if let error = viewModel.errorMessage, viewModel.isEmpty {
                errorState(error)
            } else if viewModel.isEmpty {
                emptyState
            } else {
                ratingsList
            }
        }
        .task {
            if viewModel.userEmail != targetEmail || viewModel.ratings.isEmpty {
                await viewModel.load(email: targetEmail)
            }
            if shuffled.isEmpty { reshuffle() }
        }
        .onChange(of: viewModel.ratings) { _, _ in reshuffle() }
        .refreshable { await viewModel.refresh() }
    }

    private func reshuffle() {
        let pool = viewModel.ratings.shuffled()
        shuffled = Array(pool.prefix(sampleSize))
    }

    // MARK: - List

    private var ratingsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            shuffleHeader

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(shuffled) { rating in
                    HStack(spacing: 8) {
                        starsBar(for: rating.rating)
                        ratingRow(rating)
                    }
                }
            }

            viewAllButton
        }
        .padding(.horizontal)
    }

    private var shuffleHeader: some View {
        HStack {
            Text("Sample")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("· \(viewModel.ratings.count) total")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { reshuffle() }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.xomifyPurple.opacity(0.7))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shuffle sample")
        }
    }

    private var viewAllButton: some View {
        Button {
            navStore.select(.ratings)
        } label: {
            HStack {
                Text("View all ratings")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.xomifyPurple, Color.xomifyGreen],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: XomRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full ratings history")
    }

    @ViewBuilder
    private func starsBar(for count: Int) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.xomifyGreen)
            }
        }
        .frame(width: 10)
        .accessibilityHidden(true)
    }

    private func ratingRow(_ rating: TrackRating) -> some View {
        HStack(spacing: 12) {
            artworkTile(for: rating)

            VStack(alignment: .leading, spacing: 2) {
                Text(rating.trackName ?? "Unknown")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.white).lineLimit(1)
                if let artist = rating.artistName {
                    Text(artist).font(.caption).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                if let review = rating.review, !review.isEmpty {
                    Text(review).font(.caption2)
                        .foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                }
            }

            Spacer()

            if !rating.trackId.isEmpty {
                QueueButton(
                    uri: "spotify:track:\(rating.trackId)",
                    trackName: rating.trackName
                )
            }

            Menu {
                Button {
                    openInSpotify(trackId: rating.trackId)
                } label: {
                    Label("Open in Spotify", systemImage: "arrow.up.forward.app")
                }
                if context.isSelf {
                    Divider()
                    Button(role: .destructive) {
                        Task { await viewModel.delete(rating) }
                    } label: {
                        Label("Delete rating", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("More actions for \(rating.trackName ?? "track")")
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: XomRadius.lg, style: .continuous))
    }

    @ViewBuilder
    private func artworkTile(for rating: TrackRating) -> some View {
        if let url = viewModel.artworkByTrackId[rating.trackId] {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    artworkPlaceholder
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous))
        } else {
            artworkPlaceholder
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: XomRadius.md, style: .continuous))
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.xomifyPurple.opacity(0.35), Color.xomifyGreen.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Actions

    private func openInSpotify(trackId: String) {
        guard !trackId.isEmpty, let url = URL(string: "spotify:track:\(trackId)") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
                .accessibilityHidden(true)
            Text(context.isSelf ? "No ratings yet" : "No ratings yet")
                .font(.headline).foregroundStyle(.white)
            Text(context.isSelf
                 ? "Rate tracks from the Feed or Top Items screen to track your favorites here."
                 : "This user hasn't rated anything yet.")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange.opacity(0.8))
            Text("Couldn't load ratings")
                .font(.headline).foregroundStyle(.white)
            Text(message).font(.caption).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
