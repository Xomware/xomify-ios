import SwiftUI

/// Drawer-resident Settings screen. Covers notification toggles (stubbed until #9),
/// version info, legal links, support email, and a destructive Sign out action.
struct SettingsView: View {

    // MARK: - Persisted toggles
    // Both keys are stub-wired. Real APNs registration + preferences sync to backend
    // land in sub-feature #9 (`ios-notifications`).

    @AppStorage("notifications.push.enabled")
    private var pushEnabled: Bool = true

    @AppStorage("notifications.digest.enabled")
    private var digestEnabled: Bool = true

    @State private var showSignOutConfirm = false

    private let supportEmailURL = URL(string: "mailto:support@xomware.com")
    private let privacyURL = URL(string: "https://xomify.xomware.com/privacy")
    private let termsURL = URL(string: "https://xomify.xomware.com/terms")

    var body: some View {
        List {
            notificationsSection
            aboutSection
            legalSection
            supportSection
            dangerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Sign out of Xomify?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                AuthService.shared.logout()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var notificationsSection: some View {
        Section {
            // TODO(#9): wire to NotificationsService.registerDeviceToken once ios-notifications ships.
            Toggle(isOn: $pushEnabled) {
                Label("Push notifications", systemImage: "bell.fill")
                    .foregroundStyle(.white)
            }
            .tint(Color.xomifyGreen)

            // TODO(#9): wire to NotificationsService.updateDigestPreference once ios-notifications ships.
            Toggle(isOn: $digestEnabled) {
                Label("Weekly digest", systemImage: "envelope.fill")
                    .foregroundStyle(.white)
            }
            .tint(Color.xomifyGreen)
        } header: {
            Text("Notifications")
                .foregroundStyle(.gray)
        } footer: {
            Text("Preferences take effect in a future update.")
                .font(.caption2)
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

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

            HStack {
                Label("Build", systemImage: "hammer.fill")
                    .foregroundStyle(.white)
                Spacer()
                Text(Self.buildString)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .accessibilityLabel("Build \(Self.buildString)")
            }
        } header: {
            Text("About")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    @ViewBuilder
    private var legalSection: some View {
        Section {
            if let privacyURL {
                Link(destination: privacyURL) {
                    Label("Privacy Policy", systemImage: "lock.fill")
                        .foregroundStyle(.white)
                }
            }
            if let termsURL {
                Link(destination: termsURL) {
                    Label("Terms of Service", systemImage: "doc.text.fill")
                        .foregroundStyle(.white)
                }
            }
        } header: {
            Text("Legal")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    @ViewBuilder
    private var supportSection: some View {
        Section {
            if let supportEmailURL {
                Link(destination: supportEmailURL) {
                    Label("Email support", systemImage: "envelope.badge.fill")
                        .foregroundStyle(.white)
                }
            }
        } header: {
            Text("Support")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
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
