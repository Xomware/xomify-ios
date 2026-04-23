import SwiftUI

/// Settings stub — hosts Sign out (real, wired to AuthService.logout()) + placeholder rows.
/// Full settings UI (notification prefs, account) lands in ios-drawer-residents (#8).
struct SettingsStubView: View {
    var body: some View {
        List {
            // Placeholder rows — real settings in #8.
            Section("Account") {
                Label("Notifications", systemImage: "bell.fill")
                    .foregroundStyle(.gray)
                Label("Privacy", systemImage: "lock.fill")
                    .foregroundStyle(.gray)
            }
            .listRowBackground(Color.xomifyCard)

            Section {
                Button(role: .destructive) {
                    AuthService.shared.logout()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .listRowBackground(Color.xomifyCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
