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
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        .white.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)

                if let subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.92))
                }
            }

            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.xomifyPurple, Color.xomifyGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottom) {
            // Hairline separator for definition against dark content below.
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
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
