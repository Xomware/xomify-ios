import SwiftUI

/// App-root overlay that renders toasts emitted by `QueueActionController`.
/// Mount once on `MainShell` — any `QueueButton` anywhere in the tree will
/// surface its success/failure message here.
struct QueueToastHost: View {

    @State private var queueAction = QueueActionController.shared
    @State private var clearTask: Task<Void, Never>?

    var body: some View {
        VStack {
            if let message = queueAction.toast {
                HStack(spacing: 10) {
                    Image(systemName: "text.badge.plus")
                        .font(.footnote.weight(.semibold))
                    Text(message)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.85))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
                .padding(.horizontal, XomSpacing.lg)
                .padding(.top, XomSpacing.md)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: queueAction.toast)
        .allowsHitTesting(false)
        .onChange(of: queueAction.toast) { _, newValue in
            clearTask?.cancel()
            guard newValue != nil else { return }
            clearTask = Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled {
                    queueAction.toast = nil
                }
            }
        }
    }
}
