import SwiftUI

/// Slide-out navigation drawer. Overlays the leading edge of the screen.
/// Width: min(82 % of screen width, 320 pt).
///
/// The drawer is a pure menu: each row calls `navStore.select(_:)` which
/// sets `currentDestination` on `NavigationStore` AND closes the drawer in
/// a single animation. No inner `NavigationStack` lives here — destination
/// views render full-bleed inside `MainShell`.
struct DrawerView: View {
    @Environment(NavigationStore.self) private var navStore

    /// Signed-in user's avatar URL (sourced from `MainShell` via `avatarURL`).
    let avatarURL: URL?
    /// Signed-in user's display name for the profile card — falls back to email.
    let displayName: String?
    /// Signed-in user's email — always shown as a secondary label.
    let email: String?

    // MARK: - Drawer entries

    private struct DrawerEntry: Identifiable {
        let destination: SidebarDestination
        let label: String
        let systemImage: String
        var id: SidebarDestination { destination }
    }

    /// Primary entries (everything except Settings — pinned to the bottom).
    /// Profile is reached via the profile card above this list, so it is not
    /// duplicated as a row.
    private let primaryEntries: [DrawerEntry] = [
        .init(destination: .feed,             label: "Feed",              systemImage: "sparkles"),
        .init(destination: .search,           label: "Search",            systemImage: "magnifyingglass"),
        .init(destination: .likes,            label: "Likes",             systemImage: "heart.fill"),
        .init(destination: .recentlyPlayed,   label: "Recently Played",   systemImage: "clock.arrow.circlepath"),
        .init(destination: .musicTaste,       label: "Music Taste",       systemImage: "waveform"),
        .init(destination: .wrapped,          label: "Wrapped",           systemImage: "chart.bar.fill"),
        .init(destination: .releaseRadar,     label: "Release Radar",     systemImage: "antenna.radiowaves.left.and.right"),
        .init(destination: .moodPicks,        label: "Mood Picks",        systemImage: "face.smiling"),
        .init(destination: .playlistAnalysis, label: "Playlist Analysis", systemImage: "chart.pie.fill"),
        .init(destination: .ratings,          label: "Ratings",           systemImage: "star.fill"),
        .init(destination: .friends,          label: "Friends",           systemImage: "person.2.fill"),
        .init(destination: .builder,          label: "Playlist Builder",  systemImage: "music.note.list"),
    ]

    private let settingsEntry = DrawerEntry(
        destination: .settings,
        label: "Settings",
        systemImage: "gearshape.fill"
    )

    // MARK: - Layout constants

    private let drawerWidth: CGFloat = {
        let screenWidth = UIScreen.main.bounds.width
        return min(screenWidth * 0.82, 320)
    }()

    // MARK: - Body

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                drawerPanel
                    .gesture(closeDragGesture)
                Spacer()
            }
        }
        .offset(x: navStore.isDrawerOpen ? 0 : -drawerWidth)
    }

    /// Drag the open drawer leftward to dismiss. Mirrors `MainShell`'s edge
    /// swipe to open: requires a clearly horizontal drag past a small threshold
    /// so it doesn't fight scrolls inside the drawer's row list.
    private var closeDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard navStore.isDrawerOpen else { return }
                let pulledLeft = value.translation.width < -60
                let mostlyHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                guard pulledLeft, mostlyHorizontal else { return }
                navStore.closeDrawer()
            }
    }

    // MARK: - Drawer panel

    private var drawerPanel: some View {
        VStack(spacing: 0) {
            bannerHeader
            profileCard
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(primaryEntries) { entry in
                        drawerRow(entry)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }

            // Pinned Settings at the bottom.
            Divider()
                .overlay(Color.white.opacity(0.08))
            VStack(spacing: 6) {
                drawerRow(settingsEntry)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .frame(width: drawerWidth)
        .background(
            LinearGradient(
                colors: [Color.xomifyDark, Color.xomifyCard.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .vertical)
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
                .ignoresSafeArea(edges: .vertical)
        }
    }

    // MARK: - Banner header

    private var bannerHeader: some View {
        HStack {
            Image("banner-logo")
                .resizable()
                .scaledToFit()
                .frame(height: 34)
                .accessibilityLabel("Xomify")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Profile card

    private var profileCard: some View {
        Button {
            navStore.select(.profile)
        } label: {
            HStack(spacing: 12) {
                avatarView
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName ?? "Your Profile")
                        .font(.xomifyHeadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let email {
                        Text(email)
                            .font(.xomifyCaption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.xomifyPurple.opacity(0.35), Color.xomifyGreen.opacity(0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open profile for \(displayName ?? email ?? "you")")
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarView: some View {
        if let avatarURL {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    avatarPlaceholder
                @unknown default:
                    avatarPlaceholder
                }
            }
            .clipShape(.circle)
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
        } else {
            avatarPlaceholder
                .clipShape(.circle)
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.white.opacity(0.75))
            .background(Color.xomifyPurple.opacity(0.25))
    }

    // MARK: - Row

    @ViewBuilder
    private func drawerRow(_ entry: DrawerEntry) -> some View {
        let isSelected = navStore.currentDestination == entry.destination
        Button {
            navStore.select(entry.destination)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: entry.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : Color.xomifyGreen)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                Text(entry.label)
                    .font(.xomifyBody.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(rowBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool) -> some View {
        if isSelected {
            LinearGradient(
                colors: [Color.xomifyPurple, Color.xomifyGreen],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color.white.opacity(0.04)
        }
    }
}
