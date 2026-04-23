import SwiftUI
import UserNotifications

/// Drawer-resident Settings screen. Covers notification toggles, version info,
/// legal links, support email, and a destructive Sign out action.
///
/// Notification toggles are mediated by `SettingsViewModel` (sub-feature #9 —
/// `ios-notifications`) which mirrors them into `@AppStorage` and POSTs to
/// `/notifications/register` as an upsert on each flip.
struct SettingsView: View {

    @State private var viewModel = SettingsViewModel()
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
        .task {
            await viewModel.refreshAuthorizationStatus()
        }
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
            Toggle(isOn: $viewModel.queueNotificationsEnabled) {
                Label("Push notifications", systemImage: "bell.fill")
                    .foregroundStyle(.white)
            }
            .tint(Color.xomifyGreen)
            .disabled(!viewModel.togglesEnabled)
            .accessibilityHint("Queue-threshold push notifications")

            Toggle(isOn: $viewModel.digestEnabled) {
                Label("Weekly digest", systemImage: "envelope.fill")
                    .foregroundStyle(.white)
            }
            .tint(Color.xomifyGreen)
            .disabled(!viewModel.togglesEnabled)
            .accessibilityHint("Weekly digest push notifications")

            if viewModel.authorizationStatus == .denied,
               let url = viewModel.systemSettingsURL {
                Link(destination: url) {
                    Label("Open System Settings", systemImage: "gear")
                        .foregroundStyle(Color.xomifyGreen)
                }
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
