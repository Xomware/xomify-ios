import SwiftUI

/// More tab: entry point for secondary social + analysis features.
struct MoreView: View {

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()
                List {
                    Section {
                        row(icon: "person.2.fill",
                            title: "Friends",
                            subtitle: "Find people, accept requests",
                            tint: Color.xomifyGreen,
                            destination: AnyView(FriendsView()))
                        row(icon: "person.3.fill",
                            title: "Groups",
                            subtitle: "Share tracks in private groups",
                            tint: Color.xomifyPurple,
                            destination: AnyView(GroupsView()))
                        row(icon: "link.badge.plus",
                            title: "Invites",
                            subtitle: "Share an invite code",
                            tint: Color.xomifyGreen,
                            destination: AnyView(InvitesView()))
                    } header: {
                        sectionHeader("Social")
                    }
                    .listRowBackground(Color.xomifyCard)

                    Section {
                        row(icon: "star.fill",
                            title: "My Ratings",
                            subtitle: "Tracks you've rated",
                            tint: .yellow,
                            destination: AnyView(RatingsView()))
                    } header: {
                        sectionHeader("Library")
                    }
                    .listRowBackground(Color.xomifyCard)

                    Section {
                        row(icon: "waveform.path.ecg",
                            title: "Playlist Analysis",
                            subtitle: "Breakdown of any playlist",
                            tint: Color.xomifyGreen,
                            destination: AnyView(PlaylistAnalysisView()))
                        row(icon: "sparkles",
                            title: "Mood Picks",
                            subtitle: "Songs that match the vibe",
                            tint: .pink,
                            destination: AnyView(MoodPicksView()))
                    } header: {
                        sectionHeader("Discover")
                    }
                    .listRowBackground(Color.xomifyCard)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .tint(Color.xomifyGreen)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.gray)
            .textCase(.uppercase)
    }

    private func row(icon: String,
                     title: String,
                     subtitle: String,
                     tint: Color,
                     destination: AnyView) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    MoreView()
}
