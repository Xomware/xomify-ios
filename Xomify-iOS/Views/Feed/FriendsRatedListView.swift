import SwiftUI

/// Drilldown pushed from the "friends rated" stat tile on `ShareDetailView`.
/// Shows the average across all friend ratings up top, then one row per friend
/// with their stars + optional review.
struct FriendsRatedListView: View {

    let trackName: String
    let ratings: [ShareFriendRating]
    let average: Double?

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    averageCard
                    if ratings.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 8) {
                            ForEach(ratings) { rating in
                                row(rating)
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
        .navigationTitle("Friends rated")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.xomifyGreen)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trackName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(ratings.count == 1 ? "1 friend rated this" : "\(ratings.count) friends rated this")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var averageCard: some View {
        if let avg = average {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.title3)
                    .foregroundStyle(Color.xomifyGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f / 5", avg))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("Average friend rating")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(12)
            .background(Color.xomifyCard)
            .clipShape(.rect(cornerRadius: XomRadius.xl))
        }
    }

    private var emptyState: some View {
        Text("No friends have rated this yet.")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.xomifyCard.opacity(0.5))
            .clipShape(.rect(cornerRadius: XomRadius.lg))
    }

    private func row(_ rating: ShareFriendRating) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(url: rating.avatarURL, initial: rating.resolvedName.prefix(1))
            VStack(alignment: .leading, spacing: 4) {
                Text(rating.resolvedName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let review = rating.review, !review.isEmpty {
                    Text(review)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            stars(rating.displayStars)
        }
        .padding(10)
        .background(Color.xomifyCard)
        .clipShape(.rect(cornerRadius: XomRadius.lg))
    }

    private func stars(_ value: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(Color.xomifyGreen)
            Text("\(value)/5")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
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
