import SwiftUI
import UserNotifications

/// Settings screen. Sections:
///   **Notifications** — push opt-ins (queue-threshold, weekly digest).
///   **Features**      — Xomify feature-enrollment toggles (Wrapped, Release Radar).
///   **Account**       — Country, Subscription, User ID rows + Open Spotify Profile link.
///   **About**         — Version / build info, Help & About sub-rows, legal links.
///   **Danger Zone**   — Sign-out with confirmation dialog.
struct SettingsView: View {

    @State private var viewModel = SettingsViewModel()
    @State private var showSignOutConfirm = false

    private let supportEmailURL = URL(string: "mailto:support@xomware.com")
    private let privacyURL      = URL(string: "https://xomify.xomware.com/privacy")
    private let termsURL        = URL(string: "https://xomify.xomware.com/terms")

    var body: some View {
        List {
            notificationsSection
            featuresSection
            privacySection
            accountSection
            aboutSection
            legalSection
            supportSection
            developerSection
            dangerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .confirmationDialog(
            "Sign out of Xomify?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await viewModel.logout() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $viewModel.queueNotificationsEnabled) {
                Label("Push notifications", systemImage: "bell.fill")
                    .foregroundStyle(.white)
            }
            .tint(Color.xomifyGreen)
            .disabled(!viewModel.togglesEnabled)
            .accessibilityHint("Queue-threshold push notifications")
            .frame(minHeight: 44)

            Toggle(isOn: $viewModel.digestEnabled) {
                Label("Weekly digest", systemImage: "envelope.fill")
                    .foregroundStyle(.white)
            }
            .tint(Color.xomifyGreen)
            .disabled(!viewModel.togglesEnabled)
            .accessibilityHint("Weekly digest push notifications")
            .frame(minHeight: 44)

            if viewModel.authorizationStatus == .denied,
               let url = viewModel.systemSettingsURL {
                Link(destination: url) {
                    Label("Open System Settings", systemImage: "gear")
                        .foregroundStyle(Color.xomifyGreen)
                }
                .frame(minHeight: 44)
                .accessibilityHint("Opens the iOS Settings app to enable notifications")
            }
        } header: {
            Text("Notifications")
                .foregroundStyle(.gray)
        } footer: {
            Text(viewModel.statusFooter)
                .font(.caption2)
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    // MARK: - Features (enrollment)

    private var featuresSection: some View {
        Section {
            enrollmentRow(
                title: "Monthly Wrapped",
                description: "Monthly insights about your listening habits.",
                icon: "chart.bar.fill",
                iconGradient: [.xomifyGreen, Color(red: 23/255, green: 183/255, blue: 91/255)],
                isEnrolled: viewModel.isWrappedEnrolled,
                isUpdating: viewModel.isUpdatingEnrollment
            ) {
                Task { await viewModel.toggleWrappedEnrollment() }
            }

            enrollmentRow(
                title: "Release Radar",
                description: "New releases from your favorite artists.",
                icon: "antenna.radiowaves.left.and.right",
                iconGradient: [.xomifyPurple, Color(red: 122/255, green: 8/255, blue: 150/255)],
                isEnrolled: viewModel.isReleaseRadarEnrolled,
                isUpdating: viewModel.isUpdatingEnrollment
            ) {
                Task { await viewModel.toggleReleaseRadarEnrollment() }
            }
        } header: {
            Text("Features")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Toggle(isOn: $viewModel.likesPublic) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Show my likes to friends", systemImage: "heart.fill")
                        .foregroundStyle(.white)
                    Text("Friends can see your liked songs count and list.")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
            .tint(Color.xomifyGreen)
            .disabled(viewModel.isUpdatingLikesPublic)
            .accessibilityHint("When off, your liked songs are hidden from friends")
            .frame(minHeight: 44)
        } header: {
            Text("Privacy")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    private func enrollmentRow(
        title: String,
        description: String,
        icon: String,
        iconGradient: [Color],
        isEnrolled: Bool,
        isUpdating: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: iconGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
                if isEnrolled {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.caption2).accessibilityHidden(true)
                        Text("Enrolled").font(.caption2).fontWeight(.medium)
                    }
                    .foregroundStyle(Color.xomifyGreen)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.xomifyGreen.opacity(0.15))
                    .clipShape(Capsule())
                    .padding(.top, 2)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(get: { isEnrolled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(.xomifyGreen)
                .disabled(isUpdating)
                .accessibilityLabel("\(title) enrollment")
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            accountRow(icon: "globe",      title: "Country",      value: viewModel.country)
            accountRow(icon: "music.note", title: "Subscription", value: viewModel.accountType)
            accountRow(icon: "person",     title: "User ID",      value: viewModel.userId)

            if let url = viewModel.spotifyProfileUrl {
                Link(destination: url) {
                    Label("Open Spotify Profile", systemImage: "arrow.up.right.square")
                        .foregroundStyle(Color.xomifyGreen)
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Open Spotify Profile")
                .accessibilityHint("Opens your profile in the Spotify app or website")
            }
        } header: {
            Text("Account")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    private func accountRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.xomifyGreen)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(.gray)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value.isEmpty ? "unknown" : value)")
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Label("Version", systemImage: "info.circle.fill")
                    .foregroundStyle(.white)
                Spacer()
                Text(Self.versionString)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .accessibilityLabel("Version \(Self.versionString)")
            }
            .frame(minHeight: 44)

            HStack {
                Label("Build", systemImage: "hammer.fill")
                    .foregroundStyle(.white)
                Spacer()
                Text(Self.buildString)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .accessibilityLabel("Build \(Self.buildString)")
            }
            .frame(minHeight: 44)
        } header: {
            Text("About")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    // MARK: - Legal

    @ViewBuilder
    private var legalSection: some View {
        Section {
            if let privacyURL {
                Link(destination: privacyURL) {
                    Label("Privacy Policy", systemImage: "lock.fill")
                        .foregroundStyle(.white)
                }
                .frame(minHeight: 44)
            }
            if let termsURL {
                Link(destination: termsURL) {
                    Label("Terms of Service", systemImage: "doc.text.fill")
                        .foregroundStyle(.white)
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text("Legal")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    // MARK: - Support

    @ViewBuilder
    private var supportSection: some View {
        Section {
            if let supportEmailURL {
                Link(destination: supportEmailURL) {
                    Label("Email support", systemImage: "envelope.badge.fill")
                        .foregroundStyle(.white)
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text("Support")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    // MARK: - Developer

    private var developerSection: some View {
        Section {
            NavigationLink {
                PlaybackDiagnosticsView()
                    .environment(SpotifyPlaybackCoordinator.shared)
            } label: {
                Label("Playback Diagnostics", systemImage: "waveform.path.ecg")
                    .foregroundStyle(.white)
            }
            .frame(minHeight: 44)
            .accessibilityHint("SDK connection status, token info, and force-fallback toggle")
        } header: {
            Text("Developer")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    // MARK: - Danger Zone

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .frame(minHeight: 44)
            .accessibilityHint("Signs you out of Xomify")
        }
        .listRowBackground(Color.xomifyCard)
    }

    // MARK: - Version helpers

    static var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
