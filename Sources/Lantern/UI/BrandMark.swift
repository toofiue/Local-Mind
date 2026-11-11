import SwiftUI

/// The Local Mind mark: six petals swirling around a pupil with a catchlight.
/// The same geometry as the app icon (tools/make_aperture_svg.py), drawn in the accent color.
/// The catchlight and gaps are see-through, so the mark works on any background.
struct BrandMark: View {
    var body: some View {
        BrandMarkShape()
            .fill(Palette.accent, style: FillStyle(eoFill: true))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

nonisolated struct BrandMarkShape: Shape {
    // In units of the icon's 1024 canvas, measured from the centre.
    private static let outer: CGFloat = 318
    private static let inner: CGFloat = 128
    private static let swirl: CGFloat = 58
    private static let gap: CGFloat = 15
    private static let pupil: CGFloat = 92
    private static let glint: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / (Self.outer * 2)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func point(_ radius: CGFloat, _ degrees: CGFloat) -> CGPoint {
            let angle = (degrees - 90) * .pi / 180
            return CGPoint(x: center.x + radius * scale * cos(angle), y: center.y + radius * scale * sin(angle))
        }
        func edge(_ start: CGFloat, side: CGFloat) -> [CGPoint] {
            (0...24).map { step in
                let t = CGFloat(step) / 24
                let radius = Self.inner + (Self.outer - Self.inner) * t
                let offset = (Self.gap / 2 / radius) * 180 / .pi * side
                return point(radius, start + Self.swirl * (1 - pow(1 - t, 1.25)) + offset)
            }
        }

        var path = Path()
        for petal in 0..<6 {
            let left = edge(CGFloat(petal) * 60, side: 1)
            let right = edge(CGFloat(petal + 1) * 60, side: -1)
            func angle(_ p: CGPoint) -> Angle { .radians(atan2(p.y - center.y, p.x - center.x)) }
            path.move(to: left[0])
            left.dropFirst().forEach { path.addLine(to: $0) }
            // Along the rim to the next edge, then back down it, then along the opening.
            path.addArc(center: center, radius: Self.outer * scale, startAngle: angle(left[left.count - 1]),
                        endAngle: angle(right[right.count - 1]), clockwise: false)
            right.reversed().dropFirst().forEach { path.addLine(to: $0) }
            path.addArc(center: center, radius: Self.inner * scale, startAngle: angle(right[0]),
                        endAngle: angle(left[0]), clockwise: true)
            path.closeSubpath()
        }
        let pupil = Self.pupil * scale
        path.addEllipse(in: CGRect(x: center.x - pupil, y: center.y - pupil, width: pupil * 2, height: pupil * 2))
        let glint = Self.glint * scale
        let glintCenter = CGPoint(x: center.x - pupil * 0.36, y: center.y - pupil * 0.36)
        path.addEllipse(in: CGRect(x: glintCenter.x - glint, y: glintCenter.y - glint, width: glint * 2, height: glint * 2))
        return path
    }
}
