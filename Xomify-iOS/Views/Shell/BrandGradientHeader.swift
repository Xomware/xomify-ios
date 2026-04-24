import SwiftUI

/// Reusable brand-gradient header used at the top of full-screen destinations
/// (Feed, Profile, Ratings, Friends, Groups, Music Taste). Matches the visual
/// language of Wrapped / Release Radar — purple → green gradient bar with a
/// title, optional subtitle, and optional trailing accessory.
struct BrandGradientHeader<Trailing: View>: View {

    let title: String
    let subtitle: String?
    let systemImage: String?
    let trailing: () -> Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.xomifyTitle2)
                    .foregroundStyle(.white)

                if let subtitle {
                    Text(subtitle)
                        .font(.xomifyFootnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.xomifyPurple, Color.xomifyGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 12) {
        BrandGradientHeader(
            "Feed",
            subtitle: "What your friends are vibing to",
            systemImage: "sparkles"
        )
        BrandGradientHeader(
            "Ratings",
            subtitle: "128 rated tracks",
            systemImage: "star.fill"
        ) {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title2)
                .foregroundStyle(.white)
        }
    }
    .padding(.vertical)
    .background(Color.xomifyDark)
}
