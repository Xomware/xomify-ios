import SwiftUI
import UserNotifications

/// Persistent top header bar: avatar (opens drawer) — wordmark — bell (opens inbox).
struct HeaderBar: View {
    @Environment(NavigationStore.self) private var navStore

    /// Optional trailing toolbar override. When `nil`, renders the bell button.
    var trailingContent: AnyView? = nil

    /// Avatar image URL pulled from the caller (may be nil — shows SF symbol placeholder).
    var avatarURL: URL? = nil

    @State private var isInboxPresented = false
    @State private var unreadCount: Int = 0

    var body: some View {
        ZStack {
            // Banner logo — replaces the old "Xomify" text wordmark.
            Image("banner-logo")
                .resizable()
                .scaledToFit()
                .frame(height: 28)
                .accessibilityLabel("Xomify")
                .accessibilityAddTraits(.isHeader)

            // Leading / trailing buttons in an HStack that doesn't disturb centering.
            HStack {
                // Avatar button — opens drawer.
                Button {
                    navStore.openDrawer()
                } label: {
                    avatarView
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Open menu")
                .accessibilityHint("Shows profile, friends, groups, and settings")
                .accessibilityAddTraits(.isButton)

                Spacer()

                // Trailing slot — custom content overrides the bell when caller sets it.
                if let trailing = trailingContent {
                    trailing
                        .frame(width: 44, height: 44)
                } else {
                    bellButton
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Color.xomifyDark)
        .sheet(isPresented: $isInboxPresented, onDismiss: { Task { await refreshUnread() } }) {
            NotificationsInboxView()
        }
        .task { await refreshUnread() }
    }

    // MARK: - Bell

    private var bellButton: some View {
        Button {
            isInboxPresented = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06), in: Circle())

                if unreadCount > 0 {
                    Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.xomifyPurple, in: Capsule())
                        .offset(x: 4, y: -2)
                }
            }
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Notifications")
        .accessibilityValue(unreadCount > 0 ? "\(unreadCount) unread" : "No unread")
    }

    private func refreshUnread() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        unreadCount = delivered.count
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarView: some View {
        if let url = avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(.circle)
                case .failure, .empty:
                    placeholderAvatar
                @unknown default:
                    placeholderAvatar
                }
            }
            .frame(width: 36, height: 36)
        } else {
            placeholderAvatar
                .frame(width: 36, height: 36)
        }
    }

    private var placeholderAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.gray)
    }
}
