import SwiftUI

/// Xomify paint-style loader — draws the two X-stroke legs in sequence, fades
/// out, and loops. Ports `XomFitLoaderPaint`.
///
/// This is the app's ONLY loader. Spinning and pulsing variants used to exist
/// alongside it and have been removed: neither said anything the paint does
/// not, and having three answers to "what does loading look like" meant the
/// brand animation was the one that never got used.
struct XomifyLoaderPaint: View {
    var size: CGFloat = 60

    @State private var stroke1: CGFloat = 0
    @State private var stroke2: CGFloat = 0
    @State private var opacity: Double = 1

    var body: some View {
        // The logo at FULL colour, always. The X paints as a bright stroke
        // travelling over it, rather than the logo being masked to the stroke.
        // Masking left the unpainted disc showing as dark grey wedges at the
        // sides and top -- the logo looked broken, not mid-paint.
        Image("logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .overlay {
                ZStack {
                    XStroke(topLeft: true)
                        .trim(from: 0, to: stroke1)
                        .stroke(style: StrokeStyle(lineWidth: size * 0.30, lineCap: .round))
                    XStroke(topLeft: false)
                        .trim(from: 0, to: stroke2)
                        .stroke(style: StrokeStyle(lineWidth: size * 0.30, lineCap: .round))
                }
                .foregroundStyle(.white)
                // Lightens what is already there instead of painting over it,
                // so the brand colours stay visible under the highlight.
                .blendMode(.plusLighter)
                .opacity(0.55)
            }
            .opacity(opacity)
            .onAppear { animate() }
            .accessibilityLabel("Loading")
    }

    private func animate() {
        stroke1 = 0; stroke2 = 0; opacity = 1
        withAnimation(.easeOut(duration: 0.5)) { stroke1 = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.5)) { stroke2 = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeIn(duration: 0.4)) { opacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { animate() }
    }
}

// MARK: - XStroke

/// One leg of the X-mark, drawn as a shallow quadratic curve. The two legs
/// crossed (topLeft + !topLeft) produce the complete X.
private struct XStroke: Shape {
    let topLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.1
        if topLeft {
            path.move(to: CGPoint(x: inset, y: inset))
            path.addQuadCurve(
                to: CGPoint(x: rect.width - inset, y: rect.height - inset),
                control: CGPoint(x: rect.midX + rect.width * 0.05, y: rect.midY - rect.height * 0.05)
            )
        } else {
            path.move(to: CGPoint(x: rect.width - inset, y: inset))
            path.addQuadCurve(
                to: CGPoint(x: inset, y: rect.height - inset),
                control: CGPoint(x: rect.midX - rect.width * 0.05, y: rect.midY - rect.height * 0.05)
            )
        }
        return path
    }
}

#Preview {
    ZStack {
        Color.xomifyDark.ignoresSafeArea()
        HStack(spacing: 32) {
            XomifyLoaderPaint(size: 72)
            XomifyLoaderPaint(size: 56)
            XomifyLoaderPaint(size: 48)
        }
    }
}
