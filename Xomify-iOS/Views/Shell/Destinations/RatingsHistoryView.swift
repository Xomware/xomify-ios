import SwiftUI
import UIKit

/// Drawer-resident list of the user's past track ratings.
/// Tapping a row opens the track in Spotify. Swipe-to-delete removes a rating.
struct RatingsHistoryView: View {
    @State private var viewModel = RatingsHistoryViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.ratings.isEmpty {
                loadingState
            } else if let error = viewModel.errorMessage, viewModel.ratings.isEmpty {
                errorState(error)
            } else if viewModel.ratings.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Ratings History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.ratings.isEmpty {
                await viewModel.load()
            }
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(viewModel.ratings) { rating in
                Button {
                    openInSpotify(trackId: rating.trackId)
                } label: {
                    RatingRow(rating: rating)
                }
                .listRowBackground(Color.xomifyCard)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await viewModel.delete(rating) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading ratings...")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash")
                .font(.system(size: 50))
                .foregroundStyle(.gray.opacity(0.5))
                .accessibilityHidden(true)

            Text("No ratings yet")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Rate a track from the feed or a share and it will show up here.")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.orange.opacity(0.7))
                .accessibilityHidden(true)

            Text("Couldn't load ratings")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task { await viewModel.load() }
            } label: {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.xomifyPurple)
                    .foregroundStyle(.white)
                    .cornerRadius(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func openInSpotify(trackId: String) {
        guard !trackId.isEmpty, let url = URL(string: "spotify:track:\(trackId)") else { return }
        UIApplication.shared.open(url) { success in
            if !success {
                print("⚠️ RatingsHistory: could not open Spotify URL for \(trackId)")
            }
        }
    }
}

// MARK: - Row

private struct RatingRow: View {
    let rating: TrackRating

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rating.trackName ?? "Unknown track")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(rating.artistName ?? "Unknown artist")
                .font(.caption)
                .foregroundStyle(.gray)
                .lineLimit(1)

            if let review = rating.review, !review.isEmpty {
                Text(review)
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.9))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                stars
                Spacer()
                if let timestamp = rating.updatedAt ?? rating.createdAt,
                   let relative = Self.relativeTime(from: timestamp) {
                    Text(relative)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to open in Spotify")
    }

    private var stars: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < rating.rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(Color.xomifyGreen)
                    .accessibilityHidden(true)
            }
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
