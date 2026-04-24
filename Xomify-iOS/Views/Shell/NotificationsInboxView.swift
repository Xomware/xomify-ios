import SwiftUI
import UIKit
import UserNotifications

/// In-app notifications inbox. For v1, there is no backend feed — this
/// sheet renders the delivered push history that iOS already maintains via
/// `UNUserNotificationCenter.getDeliveredNotifications`, so it's useful
/// immediately without new endpoints. Empty state points the user at
/// Settings → Notifications when permission is denied.
struct NotificationsInboxView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var items: [InboxItem] = []
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()

                if isLoading {
                    XomifyLoaderPulse(size: 52)
                } else if authStatus == .denied {
                    deniedState
                } else if items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                if !items.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear", role: .destructive) {
                            clearAll()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .toolbarBackground(Color.xomifyDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await load() }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    private func row(_ item: InboxItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .foregroundStyle(Color.xomifyGreen)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(Color.xomifyGreen.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                if let body = item.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(3)
                }
                Text(item.relativeDate)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 44))
                .foregroundStyle(.gray.opacity(0.6))
                .accessibilityHidden(true)
            Text("No notifications yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Queue reactions and weekly digests will show up here.")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var deniedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.badge.slash")
                .font(.system(size: 44))
                .foregroundStyle(.orange.opacity(0.8))
                .accessibilityHidden(true)
            Text("Notifications are off")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Turn them on in System Settings to see queue reactions and weekly digests.")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                openSystemSettings()
            } label: {
                Text("Open Settings")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(LinearGradient.xomifyGradient)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Data

    private func load() async {
        authStatus = await NotificationsService.shared.currentAuthorizationStatus()
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        items = delivered
            .map(InboxItem.init(notification:))
            .sorted { $0.date > $1.date }
        isLoading = false
    }

    private func clearAll() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        items = []
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - InboxItem

private struct InboxItem: Identifiable {
    let id: String
    let title: String
    let body: String?
    let date: Date
    let icon: String

    init(notification: UNNotification) {
        let content = notification.request.content
        self.id = notification.request.identifier
        self.title = content.title.isEmpty ? "Xomify" : content.title
        self.body = content.body.isEmpty ? nil : content.body
        self.date = notification.date
        let payload = PushPayload(userInfo: content.userInfo)
        switch payload.kind {
        case .queueThreshold: self.icon = "music.note.list"
        case .digest:         self.icon = "calendar.badge.clock"
        case .unknown:        self.icon = "bell.fill"
        }
    }

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

#Preview {
    NotificationsInboxView()
}
