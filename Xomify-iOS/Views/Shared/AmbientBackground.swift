import SwiftUI

/// Ambient, low-opacity decorative background. Ports the web app's
/// `AmbientBackgroundComponent` (wandering blobs + occasional lightning)
/// to SwiftUI. Intended as a ZStack underlay beneath `MainShell` content.
///
/// Designed to be cheap: 4 blurred radial-gradient circles animating between
/// two waypoints each with long easeInOut cycles; lightning is a jagged path
/// that flashes briefly every few seconds. Respects Reduce Motion.
struct AmbientBackground: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.xomifyDark
                    .ignoresSafeArea()

                ForEach(0..<Blob.seeds.count, id: \.self) { index in
                    BlobView(
                        seed: Blob.seeds[index],
                        bounds: proxy.size,
                        reduceMotion: reduceMotion
                    )
                }

                if !reduceMotion {
                    LightningLayer(bounds: proxy.size)
                }
            }
            .compositingGroup()
            .drawingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Blob

private struct Blob {
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let radius: CGFloat
    let color: Color
    let period: Double

    /// Six seeded waypoints — spread across a 1:1.5 canvas so coordinates look
    /// right once scaled into the screen.
    static let seeds: [Blob] = [
        .init(startX: 0.15, startY: 0.18, endX: 0.75, endY: 0.32, radius: 180, color: .xomifyPurple, period: 14),
        .init(startX: 0.80, startY: 0.28, endX: 0.25, endY: 0.62, radius: 220, color: .xomifyGreen,  period: 18),
        .init(startX: 0.55, startY: 0.68, endX: 0.15, endY: 0.88, radius: 160, color: .xomifyPurple, period: 22),
        .init(startX: 0.20, startY: 0.85, endX: 0.85, endY: 0.78, radius: 200, color: .xomifyGreen,  period: 16)
    ]
}

/// Single wandering blob. Drives position via a bool that flips on a
/// repeating animation — SwiftUI interpolates the two waypoints smoothly.
private struct BlobView: View {

    let seed: Blob
    let bounds: CGSize
    let reduceMotion: Bool

    @State private var atEnd = false

    var body: some View {
        let x = seed.startX * bounds.width
        let y = seed.startY * bounds.height
        let endX = seed.endX * bounds.width
        let endY = seed.endY * bounds.height

        Circle()
            .fill(
                RadialGradient(
                    colors: [seed.color.opacity(0.55), seed.color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: seed.radius
                )
            )
            .frame(width: seed.radius * 2, height: seed.radius * 2)
            .blur(radius: 30)
            .position(
                x: reduceMotion ? x : (atEnd ? endX : x),
                y: reduceMotion ? y : (atEnd ? endY : y)
            )
            .opacity(0.45)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: seed.period).repeatForever(autoreverses: true)
                ) {
                    atEnd = true
                }
            }
    }
}

// MARK: - Lightning

/// Flashes a short jagged path every ~2–4 seconds at random. Each strike
/// fades in over 50ms, holds briefly, then fades out. Not visible with
/// Reduce Motion on.
private struct LightningLayer: View {

    let bounds: CGSize

    @State private var bolt: LightningBolt?

    var body: some View {
        ZStack {
            if let bolt {
                bolt.path
                    .stroke(bolt.color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .blur(radius: 1.5)
                    .opacity(bolt.opacity)
                    .id(bolt.id)
            }
        }
        .task(id: bounds.debugDescription) {
            await runLightningLoop()
        }
    }

    private func runLightningLoop() async {
        while !Task.isCancelled {
            let wait = UInt64.random(in: 1_500_000_000...4_000_000_000)
            try? await Task.sleep(nanoseconds: wait)
            if Task.isCancelled { return }
            await strike()
        }
    }

    private func strike() async {
        let start = CGPoint(
            x: CGFloat.random(in: 0.1...0.9) * bounds.width,
            y: CGFloat.random(in: 0...0.2) * bounds.height
        )
        let length = CGFloat.random(in: 220...480)
        let path = LightningBolt.makePath(from: start, length: length, bounds: bounds)
        let color: Color = Bool.random() ? .xomifyPurple : .xomifyGreen

        let strike = LightningBolt(id: UUID(), path: path, color: color, opacity: 0)
        bolt = strike

        withAnimation(.easeIn(duration: 0.05)) {
            bolt?.opacity = Double.random(in: 0.55...0.9)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        withAnimation(.easeOut(duration: 0.25)) {
            bolt?.opacity = 0
        }
        try? await Task.sleep(nanoseconds: 260_000_000)
        if bolt?.id == strike.id {
            bolt = nil
        }
    }
}

private struct LightningBolt: Identifiable {
    let id: UUID
    let path: Path
    let color: Color
    var opacity: Double

    static func makePath(from start: CGPoint, length: CGFloat, bounds: CGSize) -> Path {
        var path = Path()
        let segments = Int.random(in: 6...12)
        let segLength = length / CGFloat(segments)
        var x = start.x
        var y = start.y
        path.move(to: CGPoint(x: x, y: y))
        for _ in 0..<segments {
            x += CGFloat.random(in: -segLength...segLength) * 0.7
            y += segLength * CGFloat.random(in: 0.6...1.0)
            x = max(20, min(bounds.width - 20, x))
            y = min(bounds.height, y)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

#Preview {
    AmbientBackground()
}
