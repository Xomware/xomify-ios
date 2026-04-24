import SwiftUI
import UIKit

/// Drawer-resident list of the user's past track ratings.
/// Tapping a row opens the track in Spotify. Swipe-to-delete removes a rating.
struct RatingsHistoryView: View {
    @State private var viewModel = RatingsHistoryViewModel()
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            BrandGradientHeader(
                "Ratings",
                subtitle: subtitleText,
                systemImage: "star.fill"
            )

            if !viewModel.ratings.isEmpty {
                searchField
            }

            Group {
                if viewModel.isLoading && viewModel.ratings.isEmpty {
                    loadingState
                } else if let error = viewModel.errorMessage, viewModel.ratings.isEmpty {
                    errorState(error)
                } else if viewModel.ratings.isEmpty {
                    emptyState
                } else if filteredRatings.isEmpty {
                    noMatchesState
                } else {
                    list
                }
            }
        }
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if viewModel.ratings.isEmpty {
                await viewModel.load()
            }
        }
        .refreshable { await viewModel.load() }
    }

    // MARK: - Filtered ratings

    private var filteredRatings: [TrackRating] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.ratings }
        let needle = trimmed.lowercased()
        return viewModel.ratings.filter { rating in
            (rating.trackName ?? "").lowercased().contains(needle)
                || (rating.artistName ?? "").lowercased().contains(needle)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))
            TextField("Search track or artist", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("Search ratings")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var noMatchesState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.5))
            Text("No ratings match \"\(query)\"")
                .font(.xomifyCaption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var subtitleText: String {
        let n = viewModel.ratings.count
        guard n > 0 else { return "Your rated tracks live here" }
        return "\(n) rated \(n == 1 ? "track" : "tracks")"
    }

    // MARK: - List (grouped by star count, high → low)

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(groupedByStars, id: \.stars) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        starGroupHeader(stars: group.stars, count: group.ratings.count)
                            .padding(.horizontal, 16)

                        VStack(spacing: 10) {
                            ForEach(group.ratings) { rating in
                                HStack(spacing: 10) {
                                    Button {
                                        openInSpotify(trackId: rating.trackId)
                                    } label: {
                                        RatingCard(
                                            rating: rating,
                                            artwork: viewModel.artworkByTrackId[rating.trackId]
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if !rating.trackId.isEmpty {
                                        QueueButton(
                                            uri: "spotify:track:\(rating.trackId)",
                                            trackName: rating.trackName
                                        )
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        Task {
                                            await QueueActionController.shared.queue(
                                                uri: "spotify:track:\(rating.trackId)",
                                                trackName: rating.trackName
                                            )
                                        }
                                    } label: {
                                        Label("Add to Spotify queue", systemImage: "text.badge.plus")
                                    }
                                    Button {
                                        openInSpotify(trackId: rating.trackId)
                                    } label: {
                                        Label("Open in Spotify", systemImage: "arrow.up.forward.app")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        Task { await viewModel.delete(rating) }
                                    } label: {
                                        Label("Delete rating", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }

    private var groupedByStars: [(stars: Int, ratings: [TrackRating])] {
        Dictionary(grouping: filteredRatings, by: { $0.rating })
            .map { (stars: $0.key, ratings: $0.value) }
            .sorted { $0.stars > $1.stars }
    }

    private func starGroupHeader(stars: Int, count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(i < stars ? Color.xomifyGreen : Color.white.opacity(0.25))
            }
            Text("\(count) \(count == 1 ? "track" : "tracks")")
                .font(.xomifyCaption2)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.leading, 6)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            XomifyLoaderPulse()
            Text("Loading ratings…")
                .font(.xomifyCaption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [Color.xomifyPurple, Color.xomifyGreen],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .accessibilityHidden(true)

            Text("No ratings yet")
                .font(.xomifyTitle3)
                .foregroundStyle(.white)

            Text("Rate a track from the feed or a share and it will show up here.")
                .font(.xomifyCaption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.orange.opacity(0.85))
                .accessibilityHidden(true)

            Text("Couldn't load ratings")
                .font(.xomifyTitle3)
                .foregroundStyle(.white)

            Text(message)
                .font(.xomifyCaption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task { await viewModel.load() }
            } label: {
                Text("Try Again")
                    .font(.xomifySubheadline.weight(.semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [Color.xomifyPurple, Color.xomifyGreen],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func openInSpotify(trackId: String) {
        guard !trackId.isEmpty, let url = URL(string: "spotify:track:\(trackId)") else { return }
        UIApplication.shared.open(url) { success in
            if !success {
                print("RatingsHistory: could not open Spotify URL for \(trackId)")
            }
        }
    }

}

// MARK: - Card

private struct RatingCard: View {
    let rating: TrackRating
    /// Cover art URL. Provided by the parent view model via
    /// `artworkByTrackId`. When `nil`, the gradient placeholder renders
    /// instead.
    let artwork: URL?

    var body: some View {
        HStack(spacing: 14) {
            artworkTile

            VStack(alignment: .leading, spacing: 4) {
                Text(rating.trackName ?? "Unknown track")
                    .font(.xomifySubheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(rating.artistName ?? "Unknown artist")
                    .font(.xomifyCaption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                if let review = rating.review, !review.isEmpty {
                    Text("“\(review)”")
                        .font(.xomifyFootnote.italic())
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: i < rating.rating ? "star.fill" : "star")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.xomifyGreen)
                        }
                    }
                    Spacer(minLength: 8)
                    if let timestamp = rating.updatedAt ?? rating.createdAt,
                       let relative = Self.relativeTime(from: timestamp) {
                        Text(relative)
                            .font(.xomifyCaption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.xomifyCard, Color.xomifySecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to open in Spotify")
    }

    private var artworkTile: some View {
        ZStack {
            if let artwork {
                AsyncImage(url: artwork) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderTile
                    }
                }
            } else {
                placeholderTile
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "star.fill")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white)
                .padding(4)
                .background(Color.xomifyGreen, in: Circle())
                .overlay(Circle().stroke(Color.xomifyDark, lineWidth: 2))
                .offset(x: 6, y: 6)
        }
    }

    private var placeholderTile: some View {
        ZStack {
            LinearGradient(
                colors: [Color.xomifyPurple, Color.xomifyGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private var accessibilityLabel: String {
        let track = rating.trackName ?? "Unknown track"
        let artist = rating.artistName ?? "Unknown artist"
        return "\(track) by \(artist), rated \(rating.rating) out of 5"
    }

    // MARK: - Relative time

    private static let iso8601Full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeTime(from timestamp: String) -> String? {
        let date = iso8601Full.date(from: timestamp) ?? iso8601Basic.date(from: timestamp)
        guard let date else { return nil }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        RatingsHistoryView()
    }
}
