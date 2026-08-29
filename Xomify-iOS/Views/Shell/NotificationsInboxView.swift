import SwiftUI

/// In-app notifications inbox, backed by `GET /notifications/feed`.
///
/// PREVIOUSLY this rendered `UNUserNotificationCenter.getDeliveredNotifications`
/// — the iOS notification tray. That was useful with no backend, but it emptied
/// the moment the user swiped their tray clear, showed nothing at all for a
/// user who had denied permission, and could never show anything that arrived
/// while push was muted. The backend now keeps history per user, independent of
/// whether a push was ever deliverable.
struct NotificationsInboxView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationStore.self) private var navStore

    private let notifications = NotificationsService.shared

    @State private var items: [InboxNotification] = []
    @State private var cursor: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var loadFailed = false

    private var hasUnread: Bool { items.contains { !$0.read } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.xomifyDark.ignoresSafeArea()

                if isLoading {
                    XomifyLoaderPaint(size: 64)
                } else if loadFailed && items.isEmpty {
                    failureState
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
                if hasUnread {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Mark all read") {
                            markAllRead()
                        }
                        .foregroundStyle(Color.xomifyGreen)
                    }
                }
            }
        }
        .task { await loadFirstPage() }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: XomSpacing.md) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40))
                .foregroundStyle(.gray)
            Text("Nothing yet")
                .font(.xomifyTitle3)
                .foregroundStyle(.white)
            Text("Share a song, add a friend, or wait for your next Wrapped — anything that happens shows up here.")
                .font(.xomifyFootnote)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, XomSpacing.xl)
        }
    }

    private var failureState: some View {
        VStack(spacing: XomSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Couldn't load notifications")
                .font(.xomifyHeadline)
                .foregroundStyle(.white)
            Button("Try again") {
                Task { await loadFirstPage() }
            }
            .foregroundStyle(Color.xomifyGreen)
        }
    }

    private var list: some View {
        List {
            ForEach(items) { item in
                Button {
                    open(item)
                } label: {
                    row(item)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    item.read ? Color.xomifyCard : Color.xomifyCard.opacity(0.98)
                )
            }

            if cursor != nil {
                Button {
                    Task { await loadMore() }
                } label: {
                    HStack {
                        Spacer()
                        Text(isLoadingMore ? "Loading…" : "Load more")
                            .font(.xomifyFootnote)
                            .foregroundStyle(Color.xomifyGreen)
                        Spacer()
                    }
                }
                .disabled(isLoadingMore)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await loadFirstPage() }
    }

    private func row(_ item: InboxNotification) -> some View {
        HStack(alignment: .top, spacing: XomSpacing.sm) {
            // Unread is a dot AND a bolder title — colour alone is not an
            // accessible distinction.
            Circle()
                .fill(item.read ? Color.clear : Color.xomifyPurple)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.xomifySubheadline)
                    .fontWeight(item.read ? .regular : .semibold)
                    .foregroundStyle(.white)
                Text(item.body)
                    .font(.xomifyFootnote)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, XomSpacing.xs)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func loadFirstPage() async {
        loadFailed = false
        do {
            let page = try await notifications.fetchInbox()
            items = page.items
            cursor = page.nextCursor
        } catch {
            loadFailed = true
        }
        isLoading = false
        await notifications.refreshUnreadCount()
    }

    private func loadMore() async {
        guard let cursor, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let page = try await notifications.fetchInbox(cursor: cursor)
            items.append(contentsOf: page.items)
            self.cursor = page.nextCursor
        } catch {
            // Keep what we have; the button stays available for another go.
        }
        isLoadingMore = false
    }

    /// Marks read optimistically — a row that stays bold after you tapped it
    /// reads as broken — then routes using the same token map push-open uses.
    private func open(_ item: InboxNotification) {
        if !item.read, let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].read = true
            Task { await notifications.markRead(item.tsId) }
        }

        let payload = PushPayload(
            kind: PushKind(rawValue: item.kind) ?? .unknown,
            route: item.route,
            shareId: PushPayload.subject(of: item.route, kind: "share")
        )
        if let destination = NotificationsService.destination(for: payload) {
            dismiss()
            navStore.select(destination)
        }
    }

    private func markAllRead() {
        for index in items.indices { items[index].read = true }
        Task { await notifications.markAllRead() }
    }
}
