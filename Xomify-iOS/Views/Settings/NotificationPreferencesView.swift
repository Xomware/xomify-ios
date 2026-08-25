import SwiftUI
import UserNotifications

/// Settings › Notifications — one toggle per notification kind.
///
/// Per-kind rather than a master switch or three category groups: one annoying
/// reminder should cost you that reminder, not every notification the app can
/// send. Sixteen rows is a lot of screen, which is why they are sectioned.
///
/// The rows come from `NotificationCatalog`, which mirrors the backend registry
/// (`lambdas/common/notification_kinds.py`). Adding a kind there means adding a
/// row here — deliberately manual, because the copy is not derivable.
struct NotificationPreferencesView: View {

    private let notifications = NotificationsService.shared

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            if authorizationStatus != .authorized {
                permissionSection
            }

            ForEach(NotificationSection.allCases, id: \.self) { section in
                Section {
                    ForEach(NotificationCatalog.settings(in: section)) { setting in
                        row(setting)
                    }
                } header: {
                    Text(section.title)
                        .foregroundStyle(.gray)
                }
                .listRowBackground(Color.xomifyCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            authorizationStatus = await notifications.currentAuthorizationStatus()
        }
    }

    // MARK: - Rows

    private func row(_ setting: NotificationSetting) -> some View {
        // Reading through `isEnabled(_:default:)` rather than storing sixteen
        // booleans: an untouched flag resolves to the backend's registry
        // default, which is the same rule the server applies.
        let binding = Binding<Bool>(
            get: {
                notifications.preferences.isEnabled(
                    setting.id, default: setting.defaultEnabled
                )
            },
            set: { newValue in
                Task { await notifications.setPreference(setting.id, enabled: newValue) }
            }
        )

        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(setting.title)
                    .foregroundStyle(.white)
                Text(setting.subtitle)
                    .font(.xomifyCaption)
                    .foregroundStyle(.gray)
            }
        }
        .tint(Color.xomifyGreen)
        // Toggling while denied writes a preference that can never take
        // effect — misleading. The permission row above says why.
        .disabled(authorizationStatus == .denied)
        .frame(minHeight: 44)
        .accessibilityHint(setting.subtitle)
    }

    // MARK: - Permission

    @ViewBuilder
    private var permissionSection: some View {
        Section {
            switch authorizationStatus {
            case .denied:
                VStack(alignment: .leading, spacing: XomSpacing.sm) {
                    Text("Notifications are turned off")
                        .font(.xomifyHeadline)
                        .foregroundStyle(.white)
                    Text("These settings won't do anything until you allow notifications for Xomify in iOS Settings.")
                        .font(.xomifyFootnote)
                        .foregroundStyle(.gray)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open System Settings", destination: url)
                            .foregroundStyle(Color.xomifyGreen)
                    }
                }
                .padding(.vertical, XomSpacing.xs)

            default:
                VStack(alignment: .leading, spacing: XomSpacing.sm) {
                    Text("Notifications aren't set up yet")
                        .font(.xomifyHeadline)
                        .foregroundStyle(.white)
                    Text("You'll be asked the first time something happens worth telling you about. Your choices below are saved either way.")
                        .font(.xomifyFootnote)
                        .foregroundStyle(.gray)
                }
                .padding(.vertical, XomSpacing.xs)
            }
        }
        .listRowBackground(Color.xomifyCard)
    }
}
