import AppKit

/// Iris's menu bar icon: an aperture that opens when a model is in memory.
/// Closed means no model, half open means one is loading, open means ready.
enum ApertureIcon {
    enum State: CaseIterable {
        case closed, opening, open

        var label: String {
            switch self {
            case .closed: "Iris, no model loaded"
            case .opening: "Iris, loading a model"
            case .open: "Iris, model ready"
            }
        }

        /// How far the hexagonal opening reaches, as a share of the blade radius.
        fileprivate var opening: CGFloat {
            switch self {
            // Not quite zero, so the blades spiral like a shut lens instead of meeting like pie slices.
            case .closed: 0.12
            case .opening: 0.3
            case .open: 0.6
            }
        }
    }

    private static let cache: [State: NSImage] = Dictionary(uniqueKeysWithValues: State.allCases.map { ($0, draw($0)) })

    static func image(_ state: State) -> NSImage { cache[state]! }

    private static func draw(_ state: State) -> NSImage {
        let size = NSSize(width: 18, height: 18) // grid: ok Apple's menu bar icon size
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 7.75
            let hex = radius * state.opening
            let corners = (0..<6).map { i -> CGPoint in
                let angle = CGFloat.pi / 2 + CGFloat(i) * .pi / 3
                return CGPoint(x: center.x + hex * cos(angle), y: center.y + hex * sin(angle))
            }

            // The blades: a disc with a hexagonal hole.
            let shape = CGMutablePath()
            shape.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            if state != .closed { shape.addLines(between: corners); shape.closeSubpath() }
            context.addPath(shape)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)

            // The gaps between blades: each hexagon edge carried on to the rim.
            context.setBlendMode(.clear)
            context.setLineWidth(1.1)
            for i in 0..<6 {
                let start = corners[(i + 1) % 6]
                let angle = CGFloat.pi / 2 + CGFloat(i) * .pi / 3 + .pi * 2 / 3
                let end = CGPoint(x: start.x + radius * 2 * cos(angle), y: start.y + radius * 2 * sin(angle))
                context.move(to: start)
                context.addLine(to: end)
            }
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
