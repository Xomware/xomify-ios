import Foundation

/// Compile-time feature flags. Single source of truth.
///
/// Flip these in-place (and rebuild) when a backend dependency ships. No
/// remote-config or A/B testing — this is deliberately dumb and grep-able.
enum FeatureFlags {

    /// Reactions UI on share cards. Wired to the eventual `/shares/react`
    /// endpoint that sub-feature 4 (`backend-interactions-and-notifications`)
    /// is building. Keep `false` until that endpoint is deployed.
    static let reactionsEnabled: Bool = false
}
