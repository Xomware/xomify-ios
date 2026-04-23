import SwiftUI

/// Drawer-resident Help & About screen.
/// Static content: logo, version, tagline, support/legal links, acknowledgements placeholder.
struct HelpAboutView: View {

    private let supportEmailURL = URL(string: "mailto:support@xomware.com")
    private let privacyURL = URL(string: "https://xomify.xomware.com/privacy")
    private let termsURL = URL(string: "https://xomify.xomware.com/terms")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                versionLine
                tagline

                Divider()
                    .background(Color.white.opacity(0.1))

                supportSection
                legalSection
                acknowledgementsSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Help & About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Xomify")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("by Xomware")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
    }

    private var versionLine: some View {
        Text("Version \(SettingsView.versionString) (\(SettingsView.buildString))")
            .font(.subheadline)
            .foregroundStyle(.gray)
    }

    private var tagline: some View {
        Text("Your Spotify companion — smarter Release Radar, monthly Wrapped, and now shared with friends.")
            .font(.callout)
            .foregroundStyle(.white.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Sections

    @ViewBuilder
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Support")

            if let supportEmailURL {
                Link(destination: supportEmailURL) {
                    row(label: "Email support", systemImage: "envelope.badge.fill")
                }
            }
        }
    }

    @ViewBuilder
    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Legal")

            if let privacyURL {
                Link(destination: privacyURL) {
                    row(label: "Privacy Policy", systemImage: "lock.fill")
                }
            }
            if let termsURL {
                Link(destination: termsURL) {
                    row(label: "Terms of Service", systemImage: "doc.text.fill")
                }
            }
        }
    }

    private var acknowledgementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Acknowledgements")

            NavigationLink {
                acknowledgementsPlaceholder
            } label: {
                row(label: "Open Source Licenses", systemImage: "text.book.closed.fill")
            }
        }
    }

    // MARK: - Row / section components

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.gray)
    }

    private func row(label: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.xomifyGreen)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.gray)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.xomifyCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var acknowledgementsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.gray.opacity(0.5))
                .accessibilityHidden(true)
            Text("Acknowledgements coming soon")
                .font(.headline)
                .foregroundStyle(.white)
            Text("We'll list third-party libraries here as we add them.")
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HelpAboutView()
    }
}
