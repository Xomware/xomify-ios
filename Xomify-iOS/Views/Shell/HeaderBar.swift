import SwiftUI

/// Persistent top header bar: avatar (opens drawer) — wordmark — optional trailing slot.
struct HeaderBar: View {
    @Environment(NavigationStore.self) private var navStore

    /// Optional trailing toolbar content — reserved for future search icon (v2+).
    var trailingContent: AnyView? = nil

    /// Avatar image URL pulled from the caller (may be nil — shows SF symbol placeholder).
    var avatarURL: URL? = nil

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

                // Trailing slot — empty for v1, drop-in for search icon later.
                if let trailing = trailingContent {
                    trailing
                        .frame(width: 44, height: 44)
                } else {
                    // Keep layout symmetric — invisible placeholder.
                    Color.clear
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Color.xomifyDark)
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
