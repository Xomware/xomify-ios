import SwiftUI

/// Ambient starfield behind the app shell.
///
/// Replaces `AmbientBackground` (wandering blobs + lightning), mirroring the
/// web app's `SpaceBackgroundComponent` at its `ambient` intensity — the quiet
/// variant that sits behind real content without competing with it. The web's
/// `full` variant (parallax layers, shooting stars) belongs to its signed-out
/// landing page, which has no iOS counterpart.
///
/// WHY SPACE: xomware.com's own landing renders each app as a planet. This
/// continues the parent brand's visual language into the product rather than
/// inventing a second one, and keeps iOS and web looking like one thing.
///
/// CHEAP BY CONSTRUCTION. The starfield is a single `Canvas` drawn from a
/// deterministic seed — one draw pass, no per-star views, no `TimelineView`
/// redrawing behind the whole app. Only the two nebula clouds animate, on very
/// long cycles.
struct SpaceBackground: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.xomifyDark
                    .ignoresSafeArea()

                NebulaLayer(bounds: proxy.size, reduceMotion: reduceMotion)

                Canvas { context, size in
                    for star in Starfield.stars(for: size) {
                        let rect = CGRect(
                            x: star.x - star.radius,
                            y: star.y - star.radius,
                            width: star.radius * 2,
                            height: star.radius * 2
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(.white.opacity(star.alpha))
                        )
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Starfield

private struct Star {
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat
    let alpha: Double
}

private enum Starfield {

    /// Ceiling on the alpha of any star. This layer sits behind list rows and
    /// dense stats screens — the moment it is legible as "stars" rather than
    /// texture, it is competing with the content.
    private static let alphaCeiling: Double = 0.30

    /// Deterministic per size. Recomputed on every draw, ON PURPOSE.
    ///
    /// The first version memoised into a `static var` dictionary. That is
    /// shared mutable state written from inside a `Canvas` draw closure, which
    /// does not run exclusively on the main thread — the result was heap
    /// corruption (`malloc: pointer being freed was not allocated`) that
    /// crashed the host app repeatedly under the test runner.
    ///
    /// There is nothing worth caching here: this is a seeded loop over ~160
    /// stars. Recomputing is cheap, and being deterministic means the sky is
    /// byte-identical every time anyway.
    ///
    /// The seeded generator itself is still load-bearing: `Canvas` redraws on
    /// every layout pass, and `Double.random` in the draw closure would
    /// reshuffle the entire sky each time — the background would visibly
    /// twitch whenever anything above it resized.
    static func stars(for size: CGSize) -> [Star] {
        var generator = SeededGenerator(seed: 0x5F0A_C1D0)
        // Scaled by area so a phone is not as dense as an iPad, clamped so a
        // small window still reads as a sky.
        let areaScale = min(max((size.width * size.height) / (390 * 844), 0.5), 2.0)
        let count = Int(160 * areaScale)

        var stars: [Star] = []
        stars.reserveCapacity(count)
        for _ in 0..<count {
            stars.append(
                Star(
                    x: CGFloat(Double.random(in: 0...1, using: &generator)) * size.width,
                    y: CGFloat(Double.random(in: 0...1, using: &generator)) * size.height,
                    radius: CGFloat(Double.random(in: 0.4...1.3, using: &generator)),
                    alpha: Double.random(in: 0.10...alphaCeiling, using: &generator)
                )
            )
        }
        return stars
    }
}

/// Small deterministic PRNG (SplitMix64). Foundation offers no seedable
/// generator, and the sky must be identical across redraws.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Nebula

/// Two brand-coloured clouds drifting on long cycles. The only thing that
/// animates — and barely.
private struct NebulaLayer: View {

    let bounds: CGSize
    let reduceMotion: Bool

    @State private var drifted = false

    private struct Cloud {
        let start: UnitPoint
        let end: UnitPoint
        let color: Color
        let radius: CGFloat
        let period: Double
    }

    private static let clouds: [Cloud] = [
        .init(start: .init(x: 0.18, y: 0.22), end: .init(x: 0.32, y: 0.34),
              color: .xomifyPurple, radius: 260, period: 42),
        .init(start: .init(x: 0.82, y: 0.72), end: .init(x: 0.68, y: 0.60),
              color: .xomifyGreen, radius: 230, period: 55)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.clouds.enumerated()), id: \.offset) { _, cloud in
                let point = (reduceMotion || !drifted) ? cloud.start : cloud.end
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [cloud.color.opacity(0.20), cloud.color.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: cloud.radius
                        )
                    )
                    .frame(width: cloud.radius * 2, height: cloud.radius * 2)
                    .blur(radius: 40)
                    .position(
                        x: point.x * bounds.width,
                        y: point.y * bounds.height
                    )
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: cloud.period).repeatForever(autoreverses: true),
                        value: drifted
                    )
            }
        }
        .compositingGroup()
        .onAppear {
            guard !reduceMotion else { return }
            drifted = true
        }
    }
}

#Preview {
    SpaceBackground()
}
