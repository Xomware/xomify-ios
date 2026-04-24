import SwiftUI

/// Reusable "Add to Spotify queue" button used by every track row in the app.
/// Routes to `QueueActionController.shared` so success + error state lands in
/// one place (the root `QueueToastHost`).
///
/// Two variants:
/// - `.icon`   — compact circle button for dense rows
/// - `.pill`   — labelled pill for card UIs (feed, shares)
struct QueueButton: View {

    enum Style {
        case icon
        case pill
    }

    let uri: String
    let trackName: String?
    var style: Style = .icon

    @State private var queueAction = QueueActionController.shared

    var body: some View {
        Button {
            Task { await queueAction.queue(uri: uri, trackName: trackName) }
        } label: {
            switch style {
            case .icon:
                iconLabel
            case .pill:
                pillLabel
            }
        }
        .buttonStyle(.plain)
        .disabled(uri.isEmpty || queueAction.isQueuing(uri: uri))
        .accessibilityLabel("Add \(trackName ?? "track") to Spotify queue")
    }

    private var iconLabel: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 32, height: 32)
            if queueAction.isQueuing(uri: uri) {
                ProgressView().tint(.white.opacity(0.8)).controlSize(.small)
            } else {
                Image(systemName: "text.badge.plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private var pillLabel: some View {
        HStack(spacing: 6) {
            if queueAction.isQueuing(uri: uri) {
                ProgressView().tint(.white).controlSize(.small)
            } else {
                Image(systemName: "text.badge.plus")
            }
            Text(queueAction.isQueuing(uri: uri) ? "Queueing…" : "Queue")
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 16))
        .frame(minHeight: 44)
    }
}
