import SwiftUI
import UIKit

/// Ratings tab on `ProfileView`. Reuses `RatingsViewModel` parameterised by
/// the context email. Hides delete on `.other` — viewers can't mutate
/// another user's ratings.
struct ProfileRatingsTab: View {

    @Bindable var viewModel: RatingsViewModel
    let context: ProfileContext
    let viewerEmail: String

    private var targetEmail: String { context.email ?? viewerEmail }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.ratings.isEmpty {
                XomifyLoaderPulse()
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
        }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - List

    private var ratingsList: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(viewModel.grouped, id: \.stars) { group in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(0..<group.stars, id: \.self) { _ in
                            Image(systemName: "star.fill").foregroundStyle(Color.xomifyGreen)
                        }
                        ForEach(group.stars..<5, id: \.self) { _ in
                            Image(systemName: "star").foregroundStyle(.gray.opacity(0.4))
                        }
                        Text("\(group.ratings.count) songs")
                            .font(.caption).foregroundStyle(.gray).padding(.leading, 8)
                    }
                    .font(.caption)

                    ForEach(group.ratings) { rating in
                        ratingRow(rating)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func ratingRow(_ rating: TrackRating) -> some View {
        HStack(spacing: 12) {
            artworkTile(for: rating)

            VStack(alignment: .leading, spacing: 2) {
                Text(rating.trackName ?? "Unknown")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.white).lineLimit(1)
                if let artist = rating.artistName {
                    Text(artist).font(.caption).foregroundStyle(.gray).lineLimit(1)
                }
                if let review = rating.review, !review.isEmpty {
                    Text(review).font(.caption2)
                        .foregroundStyle(.gray.opacity(0.8)).lineLimit(2)
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            artworkPlaceholder
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                .foregroundStyle(.gray.opacity(0.5))
                .accessibilityHidden(true)
            Text(context.isSelf ? "No ratings yet" : "No ratings yet")
                .font(.headline).foregroundStyle(.white)
            Text(context.isSelf
                 ? "Rate tracks from the Feed or Top Items screen to track your favorites here."
                 : "This user hasn't rated anything yet.")
                .font(.caption).foregroundStyle(.gray)
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
            Text(message).font(.caption).foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
