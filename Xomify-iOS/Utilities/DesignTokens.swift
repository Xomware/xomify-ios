import SwiftUI

// MARK: - Xomware Design Tokens
//
// GENERATED — DO NOT EDIT VALUES HERE.
// Canonical source: xomware-frontend/src/styles/_tokens.scss
// Mirrored via:     xomify-frontend/src/styles/_tokens.scss
// Source hash:      201003166470
//
// Structure only — spacing, radius, motion. NO COLOUR: the brand palette is a
// per-product decision and lives in ColorExtensions.swift, exactly as the SCSS
// file keeps colour out and leaves it to each app's own _variables.scss.
//
// WHAT THIS ADDS: iOS already had the type ramp (FontExtensions) and the
// palette (ColorExtensions). What it did not have was the *structural* half —
// spacing and corner radii were written inline at each call site, so the app
// drifted from the web without anyone being able to point at where.
//
// SYNC IS ONE-DIRECTIONAL. Change a value in xomware-frontend, then re-port
// here. Editing these numbers locally is how the two clients silently diverge
// again.

// MARK: Spacing — 8pt base grid

enum XomSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64
    static let xxxxl: CGFloat = 96
}

// MARK: Corner Radius

/// Tightened from the old 4/8/12/20/24 scale. The reference comparison that
/// started this work uses near-zero corners; going all the way to 0 would fight
/// the rest of the design (glass cards, soft ambient background, a cartoon
/// mascot), so this is a step toward crisper rather than a wholesale identity
/// change.
///
/// `pill` is a shape, not a corner treatment — it is deliberately unchanged.
enum XomRadius {
    static let sm: CGFloat = 3
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 16
    static let pill: CGFloat = 100
}

// MARK: Motion

/// Durations mirror the SCSS transition scale. `spring` is the one place the
/// port is not literal: the web token is a cubic-bezier with overshoot
/// (`cubic-bezier(0.34, 1.56, 0.64, 1)`), and the native equivalent of that
/// feel is a spring, not a timed curve. Matching the numbers rather than the
/// feel would be the wrong kind of fidelity.
enum XomMotion {
    static let fast: Double = 0.15
    static let base: Double = 0.30
    static let slow: Double = 0.50

    static var fastEase: Animation { .easeInOut(duration: fast) }
    static var baseEase: Animation { .easeInOut(duration: base) }
    static var slowEase: Animation { .easeInOut(duration: slow) }

    /// Overshoots slightly, matching `$transition-spring` on the web.
    static var spring: Animation { .spring(response: 0.4, dampingFraction: 0.7) }
}

// MARK: Layout

/// Breakpoints exist mainly so iPad layouts can key off the same numbers the
/// web does rather than inventing a second set.
enum XomBreakpoint {
    static let sm: CGFloat = 576
    static let md: CGFloat = 768
    static let lg: CGFloat = 992
    static let xl: CGFloat = 1200
}

// MARK: - Convenience

extension View {
    /// Standard card treatment: surface fill, hairline border, `XomRadius.xl`.
    /// Centralised so a corner-radius change lands everywhere at once instead
    /// of needing a grep for magic numbers.
    func xomCard(
        padding: CGFloat = XomSpacing.md,
        radius: CGFloat = XomRadius.xl
    ) -> some View {
        self
            .padding(padding)
            .background(Color.xomifyCard)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    /// Pill treatment for chips, tags and status labels.
    func xomPill(
        horizontal: CGFloat = XomSpacing.sm,
        vertical: CGFloat = XomSpacing.xs,
        fill: Color = Color.xomifyPurple.opacity(0.14)
    ) -> some View {
        self
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(fill)
            .clipShape(Capsule())
    }
}
