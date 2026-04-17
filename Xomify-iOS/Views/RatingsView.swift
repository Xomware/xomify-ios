import SwiftUI

/// Ratings screen: all of the user's ratings, grouped by stars (5 down to 1).
struct RatingsView: View {

    @State private var viewModel = RatingsViewModel()
    @State private var isLoadingUser = true
    @State private var userEmail: String?

    private let spotifyService = SpotifyService.shared

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            content
        }
        .navigationTitle("My Ratings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isRefreshing || isLoadingUser)
            }
        }
        .task { await loadUserAndData() }
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
            ratingsList
        }
    }

    private var ratingsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.grouped, id: \.stars) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            ForEach(0..<group.stars, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .foregroundColor(.xomifyGreen)
                            }
                            ForEach(group.stars..<5, id: \.self) { _ in
                                Image(systemName: "star")
                                    .foregroundColor(.gray.opacity(0.4))
                            }
                            Text("\(group.ratings.count) songs")
                                .font(.caption).foregroundColor(.gray)
                                .padding(.leading, 8)
                        }
                        .font(.caption)

                        ForEach(group.ratings) { rating in
                            ratingRow(rating)
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable { await viewModel.refresh() }
    }

    private func ratingRow(_ rating: TrackRating) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 44, height: 44)
                Image(systemName: "music.note")
                    .foregroundColor(.white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(rating.trackName ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let artist = rating.artistName {
                    Text(artist)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                if let review = rating.review, !review.isEmpty {
                    Text(review)
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.8))
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(role: .destructive) {
                Task { await viewModel.delete(rating) }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.xomifyCard)
        .cornerRadius(10)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            Text("No Ratings Yet").font(.headline).foregroundColor(.white)
            Text("Rate tracks from the Feed or Top Items screen to track your favorites here.")
                .font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center)
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

#Preview {
    NavigationStack { RatingsView() }
}
