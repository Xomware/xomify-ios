import Foundation

/// Compile-time feature flags. Single source of truth.
///
/// Flip these in-place (and rebuild) when a backend dependency ships. No
/// remote-config or A/B testing — this is deliberately dumb and grep-able.
enum FeatureFlags {

    /// Reactions UI on share cards. Wired to `/shares/react` from
    /// `backend-interactions-and-notifications` (PR #131, shipped).
    static let reactionsEnabled: Bool = true
}
