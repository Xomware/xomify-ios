import Foundation

/// Identifies whose profile the `ProfileView` is rendering.
///
/// `.me` is the signed-in user — avatar/display name come from `SpotifyService.getCurrentUser`
/// and the action button slot holds Edit + gear.
///
/// `.other(email:)` renders any other user — avatar/display name come from
/// `/friends/profile` and the action button holds Add/Remove/Pending friendship state.
enum ProfileContext: Hashable, Sendable {
    case me
    case other(email: String)

    /// The email this context points at, or `nil` for `.me` (resolved lazily at
    /// render-time from the signed-in user).
    var email: String? {
        switch self {
        case .me:                    return nil
        case .other(let email):      return email
        }
    }

    var isSelf: Bool {
        if case .me = self { return true }
        return false
    }
}
