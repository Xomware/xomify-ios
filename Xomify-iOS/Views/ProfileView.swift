import SwiftUI

// MARK: - Profile View

/// Identity-only profile screen: banner, avatar, display name, email,
/// Followers / Following stat cards, and Quick Stats (Top Songs/Artists/Genres).
/// Settings items (enrollment, account details, logout) live in `SettingsView`.
struct ProfileView: View {
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                bannerHeader

                VStack(spacing: 20) {
                    profileHeader
                    statsSection
                    quickStatsSection
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadProfile()
        }
        .refreshable {
            await viewModel.loadProfile()
        }
    }

    // MARK: - Banner Header

    private var bannerHeader: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color.xomifyPurple.opacity(0.6), Color.xomifyDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 140)
            .overlay(
                Image("banner")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 140)
                    .clipped()
            )

            LinearGradient(
                colors: [.clear, Color.xomifyDark],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
        }
        .frame(height: 140)
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 16) {
            AsyncImage(url: viewModel.profileImageUrl) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.gray)
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(
                    LinearGradient(
                        colors: [.xomifyPurple, .xomifyGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
            )
            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
            .offset(y: -50)
            .padding(.bottom, -50)
            .accessibilityLabel("Profile photo")

            if viewModel.isLoading {
                ProgressView()
            } else {
                Text(viewModel.displayName)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                if !viewModel.email.isEmpty {
                    Text(viewModel.email)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: 16) {
            statCard(
                title: "Followers",
                value: "\(viewModel.followersCount)",
                icon: "person.2.fill",
                color: .xomifyPurple
            )

            NavigationLink(destination: FollowingView()) {
                statCardContent(
                    title: "Following",
                    value: "\(viewModel.followingCount)",
                    icon: "heart.fill",
                    color: .xomifyGreen
                )
            }
            .accessibilityLabel("Following \(viewModel.followingCount) artists. Tap to view.")
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).accessibilityHidden(true)
            Text(value).font(.title2).fontWeight(.bold).foregroundStyle(.white)
            Text(title).font(.caption).foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private func statCardContent(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).accessibilityHidden(true)
            Text(value).font(.title2).fontWeight(.bold).foregroundStyle(.white)
            Text(title).font(.caption).foregroundStyle(.gray)

            HStack(spacing: 4) {
                Text("View").font(.caption2)
                Image(systemName: "chevron.right").font(.system(size: 8)).accessibilityHidden(true)
            }
            .foregroundStyle(color.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Quick Stats Section

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Listening")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Quick overview of your music taste")
                .font(.caption)
                .foregroundStyle(.gray)

            VStack(spacing: 12) {
                NavigationLink(destination: TopItemsView()) {
                    quickStatRow(
                        title: "Top Songs",
                        subtitle: "View your most played tracks",
                        icon: "music.note",
                        iconColor: .xomifyPurple
                    )
                }
                .accessibilityLabel("Top Songs")

                NavigationLink(destination: TopItemsView()) {
                    quickStatRow(
                        title: "Top Artists",
                        subtitle: "Discover your favorite artists",
                        icon: "person.2.fill",
                        iconColor: .xomifyGreen
                    )
                }
                .accessibilityLabel("Top Artists")

                NavigationLink(destination: TopItemsView()) {
                    quickStatRow(
                        title: "Top Genres",
                        subtitle: "See what styles you love",
                        icon: "guitars.fill",
                        iconColor: .blue
                    )
                }
                .accessibilityLabel("Top Genres")
            }
        }
    }

    private func quickStatRow(title: String, subtitle: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(.gray)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.gray)
                .accessibilityHidden(true)
        }
        .padding()
        .frame(minHeight: 44)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}
