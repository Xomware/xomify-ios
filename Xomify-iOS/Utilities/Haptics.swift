import SwiftUI
import UIKit

/// Haptic feedback for actions that change something.
///
/// The app had essentially none before this — `PlaylistBuilderManager` was the
/// only call site. On iOS, a button that changes state without a tap you can
/// feel reads as slightly dead, which is a large part of why a SwiftUI app can
/// look right and still feel like a web page in a wrapper.
///
/// THE RULE: haptics confirm a *state change the user caused*. Navigation does
/// not qualify — the screen moving is its own feedback, and buzzing on every
/// push makes the phone feel broken rather than responsive.
enum Haptics {

    /// A track was queued, a rating set, a share sent. The common case.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Something the user attempted did not work.
    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// A selection changed — a tab, a chip, a star part-way through a drag.
    /// Deliberately lighter than `success()`; this fires often.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A destructive or otherwise weighty confirmation.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Light physical tap — a sheet snapping, a drawer catching.
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

extension View {
    /// Fire a haptic when `value` changes.
    ///
    /// Wraps `.sensoryFeedback` where available so the platform can honour a
    /// user's system-level haptic settings, rather than driving the generator
    /// directly and overriding them.
    func xomHaptic<V: Equatable>(
        _ feedback: SensoryFeedback,
        trigger value: V
    ) -> some View {
        self.sensoryFeedback(feedback, trigger: value)
    }
}
