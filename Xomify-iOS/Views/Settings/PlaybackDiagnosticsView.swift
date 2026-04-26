import SwiftUI
import UIKit

/// Developer diagnostics for the Spotify iOS SDK playback path.
///
/// Shows current SDK connection state, last error, Spotify-app-install status,
/// token expiry, and a force-fallback toggle. Useful for confirming the SDK is
/// running without adding logging instrumentation.
struct PlaybackDiagnosticsView: View {

    @Environment(SpotifyPlaybackCoordinator.self) private var coordinator

    var body: some View {
        List {
            connectionSection
            tokenSection
            fallbackSection
            actionsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.xomifyDark.ignoresSafeArea())
        .navigationTitle("Playback Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            statusRow(
                title: "Spotify app installed",
                value: spotifyInstalled ? "Yes" : "No",
                valueColor: spotifyInstalled ? .xomifyGreen : .red
            )

            statusRow(
                title: "SDK connected",
                value: coordinator.remote.isConnected ? "Connected" : "Disconnected",
                valueColor: coordinator.remote.isConnected ? .xomifyGreen : .orange
            )

            if let error = coordinator.remote.lastError {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last SDK error")
                        .foregroundStyle(.white)
                    Text(error.errorDescription ?? "Unknown error")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                .frame(minHeight: 44)
                .padding(.vertical, 4)
            }
        } header: {
            Text("SDK Status")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    private var tokenSection: some View {
        Section {
            statusRow(
                title: "Token expires",
                value: tokenExpiryString,
                valueColor: tokenExpiringSoon ? .orange : .gray
            )
        } header: {
            Text("Auth Token")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    private var fallbackSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { coordinator.forceWebFallback },
                set: { coordinator.forceWebFallback = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Force Web API fallback")
                        .foregroundStyle(.white)
                    Text("Bypasses the SDK — useful for A/B comparison.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            .tint(Color.xomifyGreen)
            .frame(minHeight: 44)
        } header: {
            Text("Fallback")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task {
                    coordinator.disconnect()
                    await coordinator.connectIfAuthenticated()
                }
            } label: {
                Label("Reconnect SDK", systemImage: "arrow.clockwise")
                    .foregroundStyle(Color.xomifyGreen)
            }
            .frame(minHeight: 44)
            .disabled(!spotifyInstalled)
            .accessibilityHint("Disconnects then reconnects the Spotify SDK")

            if let spotifyURL = URL(string: "spotify:"), spotifyInstalled {
                Button {
                    UIApplication.shared.open(spotifyURL)
                } label: {
                    Label("Open Spotify app", systemImage: "arrow.up.right.square")
                        .foregroundStyle(Color.xomifyGreen)
                }
                .frame(minHeight: 44)
                .accessibilityHint("Opens the Spotify app")
            }
        } header: {
            Text("Actions")
                .foregroundStyle(.gray)
        }
        .listRowBackground(Color.xomifyCard)
    }

    // MARK: - Helpers

    private var spotifyInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "spotify:")!)
    }

    private var tokenExpiryString: String {
        guard let expiry = AuthService.shared.tokenExpirationDate else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: expiry, relativeTo: .now)
    }

    private var tokenExpiringSoon: Bool {
        guard let expiry = AuthService.shared.tokenExpirationDate else { return true }
        return expiry.timeIntervalSinceNow < 300 // less than 5 min
    }

    private func statusRow(title: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

#Preview {
    NavigationStack {
        PlaybackDiagnosticsView()
            .environment(SpotifyPlaybackCoordinator.shared)
    }
}
